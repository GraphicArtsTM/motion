--!strict
--[[
	ProfileStore — сохранение профилей игроков (GDD §11.2, этап 9а; правка по аудиту). Тонкая обёртка: вся логика
	сессий и блокировок — чистый ProfileSessions (тесты с подставным хранилищем), здесь — DataStore, время,
	автосохранение раз в AutosaveSec и BindToClose.
	- DataStore недоступен (Studio без доступа к API) или блокировку забрать не вышло — профиль только в памяти и не
	  сохраняется (чтобы не затереть чужую сессию); игра не падает.
	- save / grant — true / "granted" только если запись правда ушла в DataStore.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Profile = require(Shared:WaitForChild("Profile"))
local ProfileSessions = require(Shared:WaitForChild("ProfileSessions"))

export type Session = ProfileSessions.Session

export type ProfileStore = {
	load: (userId: number) -> Session,
	get: (userId: number) -> Session?,
	save: (userId: number) -> boolean,
	release: (userId: number) -> (),
	grant: (userId: number, apply: (data: Profile.Data) -> boolean, allowMemory: boolean) -> ProfileSessions.Grant,
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
	local wrapped: ProfileSessions.Store? = nil
	if ds ~= nil then
		local s: DataStore = ds
		wrapped = {
			update = function(key: string, transform: (old: any) -> any): (boolean, string?)
				local ok, err = pcall(function()
					s:UpdateAsync(key, transform)
				end)
				return ok, if ok then nil else tostring(err)
			end,
		}
	end
	local manager = ProfileSessions.new({
		store = wrapped,
		jobId = game.JobId,
		now = os.time,
		wait = function(sec: number)
			task.wait(sec)
		end,
		warn = warn,
	})

	-- Автосохранение и сохранение при закрытии сервера.
	task.spawn(function()
		while true do
			task.wait(cfg.AutosaveSec)
			manager.autosave()
		end
	end)
	game:BindToClose(function()
		manager.closeAll()
	end)
	return {
		load = manager.load,
		get = manager.get,
		save = manager.save,
		release = manager.release,
		grant = manager.grant,
	}
end

return ProfileStore
