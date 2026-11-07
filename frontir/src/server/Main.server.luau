--!strict
--[[
	Точка входа сервера. Сервер решает всё: принимает намерения клиентов,
	считает симуляцию и рассылает изменения (docs/GDD.md §12).
	Выбирает карту, распаковывает её, сообщает клиентам её id и запускает матч (Match/MatchService).
	§15л ч.3: роль сервера (Places.role) — хаб, матч или «как раньше»; в хабе карта — только фон меню.
	Все карты лежат в ServerStorage.Maps (клиенты их не скачивают); выбранная копируется в
	ReplicatedStorage.Maps — только её получают игроки.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapData = require(Shared:WaitForChild("MapData"))
local MapFormat = require(Shared:WaitForChild("MapFormat"))
local Places = require(Shared:WaitForChild("Places"))
local Types = require(Shared:WaitForChild("Types"))

local MatchService = require(script.Parent:WaitForChild("Match"):WaitForChild("MatchService"))

-- Загружает карту id: распаковка, клиентам — только она (ReplicatedStorage.Maps), атрибут MapId.
-- Этап 8б: зовётся и при смене карты после голосования (MatchService).
local function loadMap(mapId: string): MapData.MapData
	local started = os.clock()
	local source = ServerStorage:WaitForChild("Maps"):WaitForChild(mapId) :: ModuleScript
	local mapModule = require(source) :: any
	local map = MapFormat.fromModule(mapModule :: MapFormat.MapModule)

	local shared = ReplicatedStorage:FindFirstChild("Maps")
	if shared == nil then
		local folder = Instance.new("Folder")
		folder.Name = "Maps"
		folder.Parent = ReplicatedStorage
		shared = folder
	end
	local folder = shared :: Instance
	if folder:FindFirstChild(mapId) == nil then
		source:Clone().Parent = folder
	end
	-- Прежние карты убираем: клиентам нужна только текущая.
	for _, child in folder:GetChildren() do
		if child.Name ~= mapId then
			child:Destroy()
		end
	end
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
	return map
end

-- §15л ч.3: роль сервера — хаб (меню без матча), матч или как раньше (меню поверх матча).
local role: Places.Role = Places.role(game.PlaceId, RunService:IsStudio(), game.PrivateServerOwnerId, Config.Dev.Role)
print("[Frontir] server: роль " .. role .. ", место " .. tostring(game.PlaceId))
local firstMap = if Config.Dev.Map ~= "" then Config.Dev.Map else Config.Match.DefaultMap
MatchService.start(loadMap(firstMap), loadMap, role)
