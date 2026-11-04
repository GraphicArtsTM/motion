--!strict
--[[
	Общие тяжёлые данные для тестов: карта «Пангея» генерируется один раз на весь прогон
	(Lune кеширует require, поэтому все spec-файлы получают один и тот же объект).
]]

local Config = require("../../src/shared/Config")
local MapData = require("../../src/shared/MapData")
local MapGen = require("../../src/shared/MapGen")

local map, stats = MapGen.generate(Config.MapGen.Pangea)

local Fixtures: { pangea: MapData.MapData, pangeaStats: MapGen.GenStats } = {
	pangea = map,
	pangeaStats = stats,
}

return Fixtures
