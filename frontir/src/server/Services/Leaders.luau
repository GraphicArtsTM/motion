--!strict
--[[
	Leaders — таблицы лидеров (GDD §11.5, этап 9г) на OrderedDataStore:
	- «Победы за неделю»: своя таблица на каждую неделю UTC (Config.Leaders.WeeklyStore .. номер недели),
	  IncrementAsync(UserId, 1) после победы;
	- «Рейтинг дуэлей»: SetAsync(UserId, Эло) после дуэли.
	Топ-10 читается раз в Leaders.RefreshSec (GetSortedAsync → GetCurrentPage), имена — Players:GetNameFromUserIdAsync
	(кеш). Без DataStore (Studio без доступа к API) — пустые таблицы, ничего не падает.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Shop = require(Shared:WaitForChild("Shop"))

export type Entry = { userId: number, name: string, value: number }
export type Boards = { weekly: { Entry }, duel: { Entry } }

export type Leaders = {
	addWin: (userId: number) -> (),
	setElo: (userId: number, elo: number) -> (),
	current: () -> Boards,
}

local Leaders = {}

function Leaders.start(onUpdate: (boards: Boards) -> ()): Leaders
	local cfg = Config.Leaders
	local boards: Boards = { weekly = {}, duel = {} }
	local names: { [number]: string } = {}

	local function store(name: string): OrderedDataStore?
		local ok, s = pcall(function(): OrderedDataStore
			return DataStoreService:GetOrderedDataStore(name)
		end)
		return if ok then s else nil
	end
	local function weeklyName(): string
		return cfg.WeeklyStore .. tostring(Shop.week(os.time()))
	end

	local function nameOf(userId: number): string
		local cached = names[userId]
		if cached ~= nil then
			return cached
		end
		local ok, name = pcall(function(): string
			return Players:GetNameFromUserIdAsync(userId)
		end)
		local result = if ok then name else tostring(userId)
		names[userId] = result
		return result
	end

	local function top(name: string): { Entry }
		local s = store(name)
		if s == nil then
			return {}
		end
		local ok, page = pcall(function(): { any }
			local pages = s:GetSortedAsync(false, cfg.Top)
			return pages:GetCurrentPage()
		end)
		if not ok then
			return {}
		end
		local out: { Entry } = {}
		for _, row in page do
			local userId = tonumber(row.key)
			if userId ~= nil and type(row.value) == "number" then
				table.insert(out, { userId = userId, name = nameOf(userId), value = row.value })
			end
		end
		return out
	end

	local function refresh()
		boards = { weekly = top(weeklyName()), duel = top(cfg.DuelStore) }
		onUpdate(boards)
	end
	task.spawn(function()
		while true do
			refresh()
			task.wait(cfg.RefreshSec)
		end
	end)

	return {
		addWin = function(userId: number)
			task.spawn(function()
				local s = store(weeklyName())
				if s ~= nil then
					pcall(function()
						s:IncrementAsync(tostring(userId), 1)
					end)
				end
			end)
		end,
		setElo = function(userId: number, elo: number)
			task.spawn(function()
				local s = store(cfg.DuelStore)
				if s ~= nil then
					pcall(function()
						s:SetAsync(tostring(userId), math.max(0, math.floor(elo)))
					end)
				end
			end)
		end,
		current = function(): Boards
			return boards
		end,
	}
end

return Leaders
