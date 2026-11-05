--!strict
--[[
	ProfileStore — сохранение профилей игроков (GDD §11.2, этап 9а). Своя обёртка над DataStore с блокировкой сессии:
	- запись по ключу "u<UserId>": { data = Profile.Data, lock = { jobId, at } };
	- загрузка — UpdateAsync: чужая живая блокировка (моложе LockStaleSec) — отменяем запись и пробуем снова через
	  LockRetrySec (до LockRetries раз); старая — забираем (сервер упал);
	- сохранение — UpdateAsync только если блокировка наша; при выходе — снимаем её;
	- автосохранение раз в AutosaveSec, всё сохраняется в BindToClose;
	- DataStore недоступен (Studio без доступа к API) или блокировку забрать не вышло — профиль только в памяти и не
	  сохраняется (чтобы не затереть чужую сессию); игра не падает.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Profile = require(Shared:WaitForChild("Profile"))

export type Session = {
	userId: number,
	data: Profile.Data,
	saving: boolean, -- false — только в памяти
	released: boolean,
}

export type ProfileStore = {
	load: (userId: number) -> Session,
	get: (userId: number) -> Session?,
	save: (userId: number) -> boolean,
	release: (userId: number) -> (),
}

local ProfileStore = {}

function ProfileStore.new(): ProfileStore
	local cfg = Config.Profile
	local okStore, store = pcall(function(): DataStore
		return DataStoreService:GetDataStore(cfg.StoreName)
	end)
	local ds: DataStore? = if okStore then store else nil
	if ds == nil then
		warn("[Frontir] DataStore недоступен — профили только в памяти:", store)
	end
	local sessions: { [number]: Session } = {}

	local function key(userId: number): string
		return "u" .. tostring(userId)
	end

	-- Одна попытка забрать блокировку: данные или nil (занято / ошибка).
	local function tryLock(userId: number): (Profile.Data?, string?)
		local s = ds
		if s == nil then
			return nil, "noStore"
		end
		local result: Profile.Data? = nil
		local busy = false
		local ok, err = pcall(function()
			s:UpdateAsync(key(userId), function(old: any): any
				local record = if type(old) == "table" then old else {}
				local lock = record.lock
				if
					type(lock) == "table"
					and lock.jobId ~= game.JobId
					and type(lock.at) == "number"
					and os.time() - lock.at < cfg.LockStaleSec
				then
					busy = true
					return nil -- чужая живая сессия: ничего не пишем
				end
				record.lock = { jobId = game.JobId, at = os.time() }
				result = Profile.migrate(record.data)
				record.data = result
				return record
			end)
		end)
		if not ok then
			return nil, tostring(err)
		end
		if busy then
			return nil, "locked"
		end
		return result, nil
	end

	local function writeOut(session: Session, release: boolean): boolean
		local s = ds
		if s == nil or not session.saving then
			return false
		end
		local ok, err = pcall(function()
			s:UpdateAsync(key(session.userId), function(old: any): any
				local record = if type(old) == "table" then old else {}
				local lock = record.lock
				if type(lock) == "table" and lock.jobId ~= game.JobId then
					return nil -- сессию забрал другой сервер: не затираем
				end
				record.data = session.data
				record.lock = if release then nil else { jobId = game.JobId, at = os.time() }
				return record
			end)
		end)
		if not ok then
			warn("[Frontir] не удалось сохранить профиль", session.userId, err)
		end
		return ok
	end

	local self: ProfileStore = {
		load = function(userId: number): Session
			local existing = sessions[userId]
			if existing ~= nil then
				return existing
			end
			local data: Profile.Data? = nil
			for attempt = 1, cfg.LockRetries do
				local d, why = tryLock(userId)
				if d ~= nil then
					data = d
					break
				end
				if why ~= "locked" or attempt == cfg.LockRetries then
					break
				end
				task.wait(cfg.LockRetrySec)
			end
			local session: Session = {
				userId = userId,
				data = data or Profile.new(),
				saving = data ~= nil,
				released = false,
			}
			sessions[userId] = session
			return session
		end,
		get = function(userId: number): Session?
			return sessions[userId]
		end,
		save = function(userId: number): boolean
			local session = sessions[userId]
			return session ~= nil and writeOut(session, false)
		end,
		release = function(userId: number)
			local session = sessions[userId]
			if session == nil or session.released then
				return
			end
			session.released = true
			writeOut(session, true)
			sessions[userId] = nil
		end,
	}

	-- Автосохранение и сохранение при закрытии сервера.
	task.spawn(function()
		while true do
			task.wait(cfg.AutosaveSec)
			for _, session in sessions do
				writeOut(session, false)
			end
		end
	end)
	game:BindToClose(function()
		for userId in sessions do
			self.release(userId)
		end
	end)
	return self
end

return ProfileStore
