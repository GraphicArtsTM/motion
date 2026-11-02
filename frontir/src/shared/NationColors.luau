--!strict
--[[
	NationColors — цвета держав: отдельный набор из 24 хорошо различимых цветов (не входит в 32 цвета
	палитры, docs/palette.md). Граница державы — её цвет × Config.Nations.BorderShade (≈0.55 яркости).

	Цвета подобраны «самыми удалёнными точками» в пространстве CIE Lab: любые два различаются
	на ΔE76 ≥ 25 (тест tests/NationColors.spec.luau), без кислотных оттенков и непохожие на воду.

	Если держав больше 24, цвета повторяются. assign() раздаёт их так, что у каждой державы
	её Config.Nations.DistinctNearest ближайших по точке старта соседей — другого цвета.
]]

local Config = require("./Config")
local Palette = require("./Palette")

type Rgb = Palette.Rgb

export type StartPoint = { x: number, y: number }

local HEX: { string } = {
	"84636f",
	"e61919",
	"f29688",
	"e66b19",
	"ab6f2b",
	"decc9c",
	"e6bd19",
	"9aa136",
	"addf49",
	"19e619",
	"36a152",
	"3eea77",
	"95e4b5",
	"36a18b",
	"3edeea",
	"368ba1",
	"3e9aea",
	"b1d3f1",
	"3e60ea",
	"af19e6",
	"c174dc",
	"edb6e2",
	"e619af",
	"d45487",
}

local colors: { Rgb } = {}
for _, hex in HEX do
	table.insert(colors, Palette.hexToRgb(hex))
end

local function border(c: Rgb): Rgb
	local k = Config.Nations.BorderShade
	return table.freeze({ r = math.floor(c.r * k), g = math.floor(c.g * k), b = math.floor(c.b * k) })
end

local borders: { Rgb } = {}
for _, c in colors do
	table.insert(borders, border(c))
end

local function dist2(a: StartPoint, b: StartPoint): number
	return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

--[[
	Раздаёт индексы цветов (1..24) державам по их точкам старта. Детерминированно.

	1. Для каждой державы берём K = nearest ближайших (ничьи — по номеру державы). Соседи взаимны:
	   если B среди ближайших у A, то A и B не могут совпасть по цвету, даже если A не среди ближайших у B.
	2. Красим по порядку. Из цветов, которых нет у уже окрашенных соседей, берём тот, у которого
	   ближайшая держава того же цвета дальше всех (неиспользованный цвет — «бесконечно далеко»).

	Почему цвет всегда найдётся при K = 3: на плоскости точка может быть ближайшей не более чем
	для 6 других (контактное число), значит среди K ближайших — не более чем для 6K. Соседей у державы
	не больше K + 6K = 21 < 24, и свободный цвет есть всегда. Для K > 3 гарантия только практическая;
	если свободного цвета нет, берётся цвет с самым далёким совпадением.
]]
local function assign(starts: { StartPoint }, nearest: number?): { number }
	local n = #starts
	local k = math.min(nearest or Config.Nations.DistinctNearest, n - 1)
	local neighbours: { { [number]: boolean } } = table.create(n)
	for i = 1, n do
		neighbours[i] = {}
	end
	for i = 1, n do
		local order: { number } = {}
		for j = 1, n do
			if j ~= i then
				table.insert(order, j)
			end
		end
		table.sort(order, function(a: number, b: number): boolean
			local da, db = dist2(starts[i], starts[a]), dist2(starts[i], starts[b])
			if da ~= db then
				return da < db
			end
			return a < b
		end)
		for r = 1, k do
			neighbours[i][order[r]] = true
			neighbours[order[r]][i] = true
		end
	end

	local result: { number } = table.create(n, 0)
	for i = 1, n do
		local forbidden: { [number]: boolean } = {}
		for j in neighbours[i] do
			if result[j] ~= 0 then
				forbidden[result[j]] = true
			end
		end
		local best, bestScore, bestAllowed = 1, -1, false
		for c = 1, #colors do
			local allowed = not forbidden[c]
			local score = math.huge
			for j = 1, i - 1 do
				if result[j] == c then
					score = math.min(score, dist2(starts[i], starts[j]))
				end
			end
			-- Разрешённый цвет всегда лучше запрещённого; среди равных — дальнее совпадение, потом меньший номер.
			if (allowed and not bestAllowed) or (allowed == bestAllowed and score > bestScore) then
				best, bestScore, bestAllowed = c, score, allowed
			end
		end
		result[i] = best
	end
	return result
end

export type NationColorsModule = {
	Count: number,
	Hex: { string },
	Colors: { Rgb },
	Borders: { Rgb },
	border: (c: Rgb) -> Rgb,
	assign: (starts: { StartPoint }, nearest: number?) -> { number },
}

local NationColors: NationColorsModule = {
	Count = #colors,
	Hex = table.freeze(HEX),
	Colors = table.freeze(colors),
	Borders = table.freeze(borders),
	border = border,
	assign = assign,
}

return table.freeze(NationColors)
