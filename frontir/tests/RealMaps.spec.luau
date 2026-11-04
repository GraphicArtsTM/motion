--!strict
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MapFormat = require("../src/shared/MapFormat")
local Provinces = require("../src/shared/Provinces")
local Rng = require("../src/shared/Rng")
local StartPositions = require("../src/shared/StartPositions")
local Types = require("../src/shared/Types")
local Geo = require("../tools/lib/Geo")

-- Модули карт лежат в maps/ (пишет tools/realmap). Lune подключает их как обычные модули.
local function load(name: string): MapData.MapData
	local module = (require :: any)("../maps/" .. name) :: MapFormat.MapModule
	return MapFormat.fromModule(module)
end

T.describe("Карты с реальной географией", function()
	for _, name in Config.RealMapOrder do
		T.it(
			name .. ": размер, суша, провинции с именами, места для старта",
			function()
				local p = (Config.RealMaps :: any)[name] :: Types.RealMapParams
				local map = load(name)
				T.expect(map.width).toBe(p.Width)
				T.expect(map.height).toBe(p.Height)
				-- EditableImage — не больше 1024 × 1024.
				T.expect(map.width <= 1024 and map.height <= 1024).toBe(true)
				local counts = MapData.terrainCounts(map)
				local land = map.width * map.height - (counts[Types.Terrain.Water] or 0)
				local share = land / (map.width * map.height)
				T.expect(share > 0.2 and share < 0.8).toBe(true)
				-- Провинции: 60–250 (GDD §4), у каждой имя на двух языках, без реальных стран.
				local set = Provinces.build(map)
				T.expect(set.count >= 60 and set.count <= 250).toBe(true)
				local names = map.provinceNames :: { MapData.ProvinceName }
				T.expect(#names).toBe(set.count)
				for _, prov in set.list do
					local ru = string.gsub(prov.name, "%-%d+$", "")
					local en = string.gsub(prov.nameEn, "%-%d+$", "")
					T.expect(Geo.isNameAllowed(ru, en)).toBe(true)
				end
				-- Хватает мест для старта стольких держав, сколько ставит матч по умолчанию.
				local g = Grid.new(map)
				local rng = Rng.new(1)
				local taken: { number } = {}
				for _ = 1, Config.Match.TargetNations do
					local cell = StartPositions.autoPick(g, taken, rng)
					T.expect(cell ~= nil).toBe(true)
					table.insert(taken, cell :: number)
				end
			end
		)
	end
end)
