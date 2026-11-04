--!strict
--[[
	Точка входа сервера. Сервер решает всё: принимает намерения клиентов,
	считает симуляцию и рассылает изменения (docs/GDD.md §12).
	Выбирает карту, распаковывает её, сообщает клиентам её id и запускает матч (Match/MatchService).
	Все карты лежат в ServerStorage.Maps (клиенты их не скачивают); выбранная копируется в
	ReplicatedStorage.Maps — только её получают игроки.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapData = require(Shared:WaitForChild("MapData"))
local MapFormat = require(Shared:WaitForChild("MapFormat"))
local Types = require(Shared:WaitForChild("Types"))

local MatchService = require(script.Parent:WaitForChild("Match"):WaitForChild("MatchService"))

local mapId = if Config.Dev.Map ~= "" then Config.Dev.Map else Config.Match.DefaultMap
local started = os.clock()
local source = ServerStorage:WaitForChild("Maps"):WaitForChild(mapId) :: ModuleScript
local mapModule = require(source) :: any
local map = MapFormat.fromModule(mapModule :: MapFormat.MapModule)

-- Клиентам — только выбранная карта.
local shared = Instance.new("Folder")
shared.Name = "Maps"
source:Clone().Parent = shared
shared.Parent = ReplicatedStorage
local counts = MapData.terrainCounts(map)
local land = map.width * map.height - (counts[Types.Terrain.Water] or 0)

-- Клиенты ждут этот атрибут и грузят карту из ReplicatedStorage.Maps.
ReplicatedStorage:SetAttribute("MapId", mapId)

print(
	string.format(
		"[Frontir] server: карта %s %d×%d, суша %.1f%%, распаковка %.0f мс, тик %d Гц",
		map.name,
		map.width,
		map.height,
		land / (map.width * map.height) * 100,
		(os.clock() - started) * 1000,
		Config.Sim.TickRate
	)
)

MatchService.start(map)
