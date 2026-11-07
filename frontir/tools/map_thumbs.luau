--!strict
--[[
	Миниатюры карт для списка «МАТЧИ» в хабе (GDD §15л ч.6): каждая карта Config.RealMapOrder → Thumb.W×Thumb.H,
	цвет клетки — самый частый цвет палитры в её прямоугольнике (MapPaint, как в игре). Пишет src/shared/MapThumbs.luau.
	Запуск из frontir/:  lune run tools/map_thumbs [картинка-превью=build/thumbs.png]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Config = require("../src/shared/Config")
local MapFormat = require("../src/shared/MapFormat")
local MapPaint = require("../src/shared/MapPaint")
local Palette = require("../src/shared/Palette")
local Png = require("./lib/Png")

local TW, TH = 48, 28
local KEYS = "abcdefghijklmnopqrstuvwxyzABCDEF" -- знак = индекс в Palette.Swatches
local function nearest(r: number, g: number, b: number): number
	local best, bestD = 1, math.huge
	for k, sw in Palette.Swatches do
		local c = Palette.rgb(sw.name)
		local d = (c.r - r) ^ 2 + (c.g - g) ^ 2 + (c.b - b) ^ 2
		if d < bestD then
			best, bestD = k, d
		end
	end
	return best
end

local lines: { string } = {
	"--!strict",
	"--[[",
	"\tMapThumbs — миниатюры карт для «МАТЧИ» в хабе (GDD §15л ч.6). Сделано tools/map_thumbs — руками не править.",
	'\tСтрока — ряд сверху вниз, знак — номер цвета в Palette.Swatches (Keys: "a" — 1-й, …).',
	"]]",
	"",
	"local MapThumbs = {}",
	"",
	string.format("MapThumbs.W = %d", TW),
	string.format("MapThumbs.H = %d", TH),
	string.format('MapThumbs.Keys = "%s"', KEYS),
	"",
	"-- stylua: ignore",
	"MapThumbs.Maps = table.freeze({",
}
local preview = buffer.create(TW * TH * 3 * #Config.RealMapOrder)
for m, name in Config.RealMapOrder do
	local map = MapFormat.fromModule((require :: any)("../maps/" .. name) :: MapFormat.MapModule)
	local colors = MapPaint.paint(map)
	table.insert(lines, string.format("\t%s = table.freeze({", name))
	for ty = 0, TH - 1 do
		local row = table.create(TW)
		local y0, y1 = math.floor(ty * map.height / TH), math.floor((ty + 1) * map.height / TH) - 1
		for tx = 0, TW - 1 do
			local x0, x1 = math.floor(tx * map.width / TW), math.floor((tx + 1) * map.width / TW) - 1
			local counts: { [number]: number } = {}
			local step = math.max(1, (x1 - x0) // 6)
			for y = y0, math.max(y0, y1), step do
				for x = x0, math.max(x0, x1), step do
					local i = (y * map.width + x) * 4
					local k =
						nearest(buffer.readu8(colors, i), buffer.readu8(colors, i + 1), buffer.readu8(colors, i + 2))
					counts[k] = (counts[k] or 0) + 1
				end
			end
			local best, bestN = 1, -1
			for k, n in counts do
				if n > bestN or (n == bestN and k < best) then
					best, bestN = k, n
				end
			end
			row[tx + 1] = string.sub(KEYS, best, best)
			local c = Palette.rgb(Palette.Swatches[best].name)
			local o = (((m - 1) * TH + ty) * TW + tx) * 3
			buffer.writeu8(preview, o, c.r)
			buffer.writeu8(preview, o + 1, c.g)
			buffer.writeu8(preview, o + 2, c.b)
		end
		table.insert(lines, string.format('\t\t"%s",', table.concat(row)))
	end
	table.insert(lines, "\t}),")
end
table.insert(lines, "})")
table.insert(lines, "")
table.insert(lines, "return table.freeze(MapThumbs)")
fs.writeFile("src/shared/MapThumbs.luau", table.concat(lines, "\n") .. "\n")
local out = process.args[1] or "build/thumbs.png"
fs.writeFile(out, Png.encodeRgb(TW, TH * #Config.RealMapOrder, preview))
print(
	string.format(
		"MapThumbs: %d карт %d×%d → src/shared/MapThumbs.luau, превью %s",
		#Config.RealMapOrder,
		TW,
		TH,
		out
	)
)
