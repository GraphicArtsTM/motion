--!strict
--[[
	ServerList — список серверов матча для хаба (GDD §15л ч.3), MemoryStore:
	- сервер матча раз в Places.PublishSec пишет о себе (`publish`), срок записи — Places.ExpireSec, при закрытии
	  стирает (`remove`);
	- хаб читает список (`read`) и помнит коды резервных серверов, которые сам создал (`remember` / `codeOf`): войти
	  в резервный сервер можно только по коду, а сам сервер свой код не знает.
	Все вызовы MemoryStore — в pcall: недоступен (Studio без API, сбой) — пустой список, игра не падает.
]]

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Places = require(Shared:WaitForChild("Places"))

export type ServerList = {
	publish: (entry: Places.Entry) -> (),
	remove: () -> (),
	read: () -> { Places.Entry },
	remember: (psid: string, code: string) -> (),
	codeOf: (psid: string) -> string?,
	-- §15л ч.4 Свой матч по коду: код → сервер и владелец.
	savePrivate: (code: string, rec: Places.PrivateRecord) -> boolean,
	findPrivate: (code: string) -> Places.PrivateRecord?,
}

local ServerList = {}

function ServerList.new(): ServerList
	local cfg = Config.Places
	local okList, list = pcall(function(): MemoryStoreSortedMap
		return MemoryStoreService:GetSortedMap(cfg.ListName)
	end)
	local okCodes, codes = pcall(function(): MemoryStoreSortedMap
		return MemoryStoreService:GetSortedMap(cfg.CodesName)
	end)
	local okPrivate, private = pcall(function(): MemoryStoreSortedMap
		return MemoryStoreService:GetSortedMap(cfg.PrivateCodesName)
	end)
	local privateMap: MemoryStoreSortedMap? = if okPrivate then private else nil
	local listMap: MemoryStoreSortedMap? = if okList then list else nil
	local codesMap: MemoryStoreSortedMap? = if okCodes then codes else nil
	local known: { [string]: string } = {} -- коды, созданные этим хабом (без лишних чтений)
	local warned = false
	local function fail(err: any)
		if not warned then
			warned = true
			warn("[Frontir] MemoryStore недоступен — список матчей пуст:", err)
		end
	end

	local function publish(entry: Places.Entry)
		local store = listMap
		if store == nil then
			return
		end
		local ok, err = pcall(function()
			store:SetAsync(entry.id, entry, cfg.ExpireSec)
		end)
		if not ok then
			fail(err)
		end
	end

	local function remove()
		local store = listMap
		if store == nil then
			return
		end
		pcall(function()
			store:RemoveAsync(game.JobId)
		end)
	end

	local function read(): { Places.Entry }
		local store = listMap
		local out: { Places.Entry } = {}
		if store == nil then
			return out
		end
		local ok, items = pcall(function(): { any }
			return store:GetRangeAsync(Enum.SortDirection.Ascending, cfg.ReadMax)
		end)
		if not ok then
			fail(items)
			return out
		end
		local now = os.time()
		for _, item in items do
			local e = if type(item) == "table" then Places.entry(item.value, now) else nil
			if e ~= nil then
				table.insert(out, e)
			end
		end
		return out
	end

	local function remember(psid: string, code: string)
		known[psid] = code
		local store = codesMap
		if store == nil then
			return
		end
		pcall(function()
			store:SetAsync(psid, code, cfg.CodeExpireSec)
		end)
	end

	local function codeOf(psid: string): string?
		local hit = known[psid]
		if hit ~= nil then
			return hit
		end
		local store = codesMap
		if store == nil then
			return nil
		end
		local ok, code = pcall(function(): any
			return store:GetAsync(psid)
		end)
		if ok and type(code) == "string" then
			known[psid] = code
			return code
		end
		return nil
	end

	local function savePrivate(code: string, rec: Places.PrivateRecord): boolean
		local store = privateMap
		if store == nil then
			return false
		end
		local ok, err = pcall(function()
			store:SetAsync(code, rec, cfg.PrivateCodeSec)
		end)
		if not ok then
			fail(err)
		end
		return ok
	end

	local function findPrivate(code: string): Places.PrivateRecord?
		local store = privateMap
		if store == nil then
			return nil
		end
		local ok, raw = pcall(function(): any
			return store:GetAsync(code)
		end)
		return if ok then Places.privateRecord(raw) else nil
	end

	return {
		publish = publish,
		remove = remove,
		read = read,
		remember = remember,
		codeOf = codeOf,
		savePrivate = savePrivate,
		findPrivate = findPrivate,
	}
end

return table.freeze(ServerList)
