--!strict
--[[
	ProfileSessions — сессии профилей с блокировкой (GDD §11.2, правка по аудиту). Чистый модуль: хранилище, время,
	ожидание и id сервера подставляются (в игре — DataStore, os.time, task.wait, game.JobId; в тестах — подделки).

	Запись по ключу "u<UserId>": { data = Profile.Data, lock = { jobId, at } }.
	- Загрузка (`claim`): чужая живая блокировка (моложе LockStaleSec) — не пишем и пробуем снова через LockRetrySec
	  (до LockRetries раз); старая — забираем. Не вышло — профиль только в памяти (`saving = false`).
	- Сохранение (`write`) — только если блокировка наша. Иначе запись отменена, и это НЕ успех: сессия перестаёт
	  писать (её забрал другой сервер).
	- Игрок вышел, пока профиль грузился, — загрузка сразу снимает взятую блокировку и сессию не создаёт; вернулся до
	  конца загрузки — ждёт ту же загрузку (и идущее снятие блокировки).
	- Покупка (`grant`): «куплено» — только после записи в хранилище; профиль только в памяти — товар не начисляем.
]]

local Config = require("./Config")
local Profile = require("./Profile")

-- Хранилище: update — как DataStore:UpdateAsync (transform может вызываться несколько раз; nil — не писать).
-- Возвращает ok (без ошибки) и текст ошибки.
export type Store = {
	update: (key: string, transform: (old: any) -> any) -> (boolean, string?),
}

export type Deps = {
	store: Store?, -- nil — хранилища нет (Studio без доступа к API)
	jobId: string,
	now: () -> number,
	wait: (sec: number) -> (),
	warn: ((...any) -> ())?,
}

export type Session = {
	userId: number,
	data: Profile.Data,
	saving: boolean, -- false — только в памяти (или блокировку забрал другой сервер)
	released: boolean,
}

export type Grant = "granted" | "retry"

export type Manager = {
	load: (userId: number) -> Session,
	get: (userId: number) -> Session?,
	save: (userId: number) -> boolean,
	release: (userId: number) -> (),
	-- Начислить покупку: apply меняет данные (false — не вышло). allowMemory — можно и без хранилища (Studio).
	grant: (userId: number, apply: (data: Profile.Data) -> boolean, allowMemory: boolean) -> Grant,
	autosave: () -> (),
	closeAll: () -> (),
	loading: (userId: number) -> boolean,
}

local ProfileSessions = {}

function ProfileSessions.key(userId: number): string
	return "u" .. tostring(userId)
end

function ProfileSessions.isOurs(lock: any, jobId: string): boolean
	return type(lock) == "table" and lock.jobId == jobId
end

-- Забрать блокировку: новая запись и данные; nil — чужая живая сессия (ничего не пишем).
function ProfileSessions.claim(old: any, jobId: string, now: number): (any, Profile.Data?)
	local record = if type(old) == "table" then old else {}
	local lock = record.lock
	if
		type(lock) == "table"
		and lock.jobId ~= jobId
		and type(lock.at) == "number"
		and now - lock.at < Config.Profile.LockStaleSec
	then
		return nil, nil
	end
	local data = Profile.migrate(record.data)
	record.data = data
	record.lock = { jobId = jobId, at = now }
	return record, data
end

-- Записать данные: новая запись; nil — блокировка не наша (сессию забрали — не затираем).
function ProfileSessions.write(old: any, jobId: string, data: Profile.Data, release: boolean, now: number): any
	local record = if type(old) == "table" then old else {}
	if not ProfileSessions.isOurs(record.lock, jobId) then
		return nil
	end
	record.data = data
	record.lock = if release then nil else { jobId = jobId, at = now }
	return record
end

type Pending = { cancelled: boolean, done: boolean }

function ProfileSessions.new(deps: Deps): Manager
	local cfg = Config.Profile
	local sessions: { [number]: Session } = {}
	local pending: { [number]: Pending } = {}
	local releasing: { [number]: boolean } = {}
	local closing = false
	local function say(...: any)
		local w = deps.warn
		if w ~= nil then
			w(...)
		end
	end

	-- Записать сессию; true — только если запись правда ушла в хранилище.
	local function writeOut(session: Session, release: boolean): boolean
		local store = deps.store
		if store == nil or not session.saving then
			return false
		end
		local written = false
		local ok, err = store.update(ProfileSessions.key(session.userId), function(old: any): any
			local record = ProfileSessions.write(old, deps.jobId, session.data, release, deps.now())
			written = record ~= nil -- transform может вызываться повторно: итог — по последнему вызову
			return record
		end)
		if not ok then
			say("[Frontir] не удалось сохранить профиль", session.userId, err)
			return false
		end
		if not written then
			-- Блокировку забрал другой сервер: дальше не пишем, чтобы не затереть его данные.
			session.saving = false
			say(
				"[Frontir] блокировка профиля потеряна — сохранение остановлено",
				session.userId
			)
			return false
		end
		return true
	end

	-- Одна попытка забрать блокировку: данные или nil и причина ("locked" — чужая живая сессия).
	local function tryLock(userId: number): (Profile.Data?, string?)
		local store = deps.store
		if store == nil then
			return nil, "noStore"
		end
		local data: Profile.Data? = nil
		local busy = false
		local ok, err = store.update(ProfileSessions.key(userId), function(old: any): any
			local record, d = ProfileSessions.claim(old, deps.jobId, deps.now())
			busy = record == nil
			data = d
			return record
		end)
		if not ok then
			return nil, err or "error"
		end
		if busy then
			return nil, "locked"
		end
		return data, nil
	end

	local function waitWhile(cond: () -> boolean)
		while cond() do
			deps.wait(cfg.WaitPollSec)
		end
	end

	local self: Manager
	self = {
		load = function(userId: number): Session
			-- Вернулся, пока снималась блокировка прошлого захода, — дождаться (иначе снятие сотрёт новую).
			waitWhile(function(): boolean
				return releasing[userId] == true
			end)
			local existing = sessions[userId]
			if existing ~= nil then
				return existing
			end
			local p = pending[userId]
			if p ~= nil then
				-- Вернулся до конца загрузки: та же загрузка, только уже не отменённая.
				p.cancelled = false
				local job = p
				waitWhile(function(): boolean
					return not job.done
				end)
				local s = sessions[userId]
				if s ~= nil then
					return s
				end
				if closing then
					return { userId = userId, data = Profile.new(), saving = false, released = true }
				end
				-- Та загрузка успела отмениться и снять блокировку — загрузить заново.
				return self.load(userId)
			end
			local mine: Pending = { cancelled = false, done = false }
			pending[userId] = mine
			local data: Profile.Data? = nil
			for attempt = 1, cfg.LockRetries do
				if mine.cancelled or closing then
					break
				end
				local d, why = tryLock(userId)
				if d ~= nil then
					data = d
					break
				end
				if why ~= "locked" or attempt == cfg.LockRetries then
					break
				end
				deps.wait(cfg.LockRetrySec)
			end
			local session: Session = {
				userId = userId,
				data = data or Profile.new(),
				saving = data ~= nil,
				released = false,
			}
			if mine.cancelled or closing then
				-- Игрок ушёл (или сервер закрывается), пока грузили: блокировку снять, сессию не создавать.
				session.released = true
				releasing[userId] = true
				pending[userId] = nil
				mine.done = true
				writeOut(session, true)
				releasing[userId] = nil
				return session
			end
			sessions[userId] = session
			pending[userId] = nil
			mine.done = true
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
			local p = pending[userId]
			if p ~= nil then
				p.cancelled = true -- загрузка ещё идёт: снимет блокировку сама, когда закончит
			end
			local session = sessions[userId]
			if session == nil or session.released then
				return
			end
			session.released = true
			sessions[userId] = nil -- сначала убрать: автосохранение больше не трогает (и не продлевает блокировку)
			releasing[userId] = true
			writeOut(session, true)
			releasing[userId] = nil
		end,
		grant = function(userId: number, apply: (data: Profile.Data) -> boolean, allowMemory: boolean): Grant
			local session = sessions[userId]
			if session == nil or session.released then
				return "retry"
			end
			if not session.saving and not allowMemory then
				return "retry" -- не сохранится — не начисляем: Roblox повторит, когда профиль будет записываться
			end
			if not apply(session.data) then
				return "retry"
			end
			if session.saving and not writeOut(session, false) then
				return "retry" -- начислено в памяти (по PurchaseId не задвоится), но не записано — повторить
			end
			return "granted"
		end,
		autosave = function()
			local list: { Session } = {}
			for _, s in sessions do
				table.insert(list, s)
			end
			for _, s in list do
				if not s.released then
					writeOut(s, false)
				end
			end
		end,
		closeAll = function()
			closing = true
			for _, p in pending do
				p.cancelled = true
			end
			local ids: { number } = {}
			for userId in sessions do
				table.insert(ids, userId)
			end
			for _, userId in ids do
				self.release(userId)
			end
			-- Незаконченные загрузки снимут свои блокировки сами — подождать их (не дольше CloseWaitSec).
			local waited = 0
			while next(pending) ~= nil and waited < cfg.CloseWaitSec do
				deps.wait(cfg.WaitPollSec)
				waited += cfg.WaitPollSec
			end
		end,
		loading = function(userId: number): boolean
			return pending[userId] ~= nil
		end,
	}
	return self
end

return table.freeze(ProfileSessions)
