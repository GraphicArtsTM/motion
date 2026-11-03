--!strict
--[[
	Лист всех карт с реальной географией (Config.RealMapOrder) в одной картинке, каждая — в половину размера,
	цветами клиента (MapPaint). Запуск из frontir/:  lune run tools/maps_preview [файл=build/maps.png]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Config = require("../src/shared/Config")
local MapFormat = require("../src/shared/MapFormat")
local MapPaint = require("../src/shared/MapPaint")
local Palette = require("../src/shared/Palette")
local Png = require("./lib/Png")

local GAP = 6
local PER_ROW = 3

type Tile = { w: number, h: number, colors: buffer, scale: number }
local tiles: { Tile } = {}
for _, name in Config.RealMapOrder do
	local map = MapFormat.fromModule((require :: any)("../maps/" .. name) :: MapFormat.MapModule)
	-- Размеры считаем отдельно: StyLua 2.6 падает на «//» внутри конструктора таблицы.
	local tw, th = map.width // 2, map.height // 2
	table.insert(tiles, { w = tw, h = th, colors = MapPaint.paint(map), scale = map.width })
end

-- Раскладка по строкам: ширина строки — сумма ширин, высота — самая высокая карта.
local rows: { { Tile } } = {}
for k, tile in tiles do
	local r = (k - 1) // PER_ROW + 1
	rows[r] = rows[r] or {}
	table.insert(rows[r], tile)
end
local W, H = 0, GAP
for _, row in rows do
	local rw, rh = GAP, 0
	for _, tile in row do
		rw += tile.w + GAP
		rh = math.max(rh, tile.h)
	end
	W = math.max(W, rw)
	H += rh + GAP
end

local bg = Palette.rgb("Ink")
local pixels = buffer.create(W * H * 3)
for i = 0, W * H - 1 do
	buffer.writeu8(pixels, i * 3, bg.r)
	buffer.writeu8(pixels, i * 3 + 1, bg.g)
	buffer.writeu8(pixels, i * 3 + 2, bg.b)
end
local y0 = GAP
for _, row in rows do
	local x0, rh = GAP, 0
	for _, tile in row do
		local srcW = tile.scale
		for y = 0, tile.h - 1 do
			for x = 0, tile.w - 1 do
				local src = ((y * 2) * srcW + x * 2) * 4
				local dst = ((y0 + y) * W + x0 + x) * 3
				buffer.writeu8(pixels, dst, buffer.readu8(tile.colors, src))
				buffer.writeu8(pixels, dst + 1, buffer.readu8(tile.colors, src + 1))
				buffer.writeu8(pixels, dst + 2, buffer.readu8(tile.colors, src + 2))
			end
		end
		x0 += tile.w + GAP
		rh = math.max(rh, tile.h)
	end
	y0 += rh + GAP
end

local out = process.args[1] or "build/maps.png"
fs.writeFile(out, Png.encodeRgb(W, H, pixels))
print(string.format("Лист карт %d×%d → %s", W, H, out))
