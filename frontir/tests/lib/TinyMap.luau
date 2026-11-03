--!strict
--[[
	Маленькие карты для быстрых тестов. Карта задаётся строками, один символ — клетка:
	. равнина, ~ вода, ^ горы, f лес, h холмы, r река.
]]

local MapData = require("../../src/shared/MapData")
local Types = require("../../src/shared/Types")

local T = Types.Terrain
local CODES: { [string]: number } = {
	["."] = T.Plains,
	["~"] = T.Water,
	["^"] = T.Mountains,
	["f"] = T.Forest,
	["h"] = T.Hills,
	["r"] = T.River,
}

local TinyMap = {}

function TinyMap.fromRows(rows: { string }): MapData.MapData
	local h = #rows
	local w = #rows[1]
	local map = MapData.new("Tiny", 1, w, h)
	for y = 0, h - 1 do
		local row = rows[y + 1]
		assert(#row == w, "строки карты разной длины")
		for x = 0, w - 1 do
			local code = CODES[string.sub(row, x + 1, x + 1)]
			assert(code ~= nil, "неизвестный символ карты")
			MapData.setTerrain(map, y * w + x, code)
		end
	end
	return map
end

-- Прямоугольник равнины w×h с рамкой воды в 1 клетку.
function TinyMap.plains(w: number, h: number): MapData.MapData
	local rows: { string } = {}
	for y = 1, h do
		if y == 1 or y == h then
			table.insert(rows, string.rep("~", w))
		else
			table.insert(rows, "~" .. string.rep(".", w - 2) .. "~")
		end
	end
	return TinyMap.fromRows(rows)
end

return TinyMap
