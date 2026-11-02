--!strict
--[[
	MapPaint — цвета клеток карты (слои 1–2 из GDD §3: вода и местность). Чистый модуль:
	считает RGBA-буфер всей карты, который клиент копирует в EditableImage чанками.
	Цвета только из Palette. Владельцы и границы (слои 3–6) — этап 2.

	- Вода: три оттенка по расстоянию до суши (мель, море, глубина).
	- Суша: основной цвет местности и «дизеринг» — часть клеток альтернативным оттенком
	  по хешу координат (стабильная пиксельная фактура).
	- Горы, вокруг которых в радиусе SnowRadius только горы, — снежные вершины.
]]

local Bits = require("./Bits")
local Config = require("./Config")
local MapData = require("./MapData")
local MapGen = require("./MapGen")
local Palette = require("./Palette")
local Types = require("./Types")

type MapData = MapData.MapData
type Rgb = Palette.Rgb

local T = Types.Terrain
local DITHER_SALT = 0xD17E5

-- Основной и альтернативный цвет для каждой местности суши.
local LAND_COLORS: { [number]: { Rgb } } = {
	[T.Plains] = { Palette.rgb("Grass"), Palette.rgb("Meadow") },
	[T.Forest] = { Palette.rgb("Forest"), Palette.rgb("Pine") },
	[T.Hills] = { Palette.rgb("Hills"), Palette.rgb("Ochre") },
	[T.Mountains] = { Palette.rgb("Rock"), Palette.rgb("Basalt") },
	[T.Desert] = { Palette.rgb("Sand"), Palette.rgb("Dune") },
	[T.Tundra] = { Palette.rgb("Frost"), Palette.rgb("Tundra") },
	[T.River] = { Palette.rgb("River"), Palette.rgb("River") },
}
local SNOW = Palette.rgb("Snow")
local SHALLOWS = Palette.rgb("Shallows")
local SEA = Palette.rgb("Sea")
local ABYSS = Palette.rgb("Abyss")

local MapPaint = {}

-- Расстояние от каждой водной клетки до ближайшей суши (u16 на клетку, для суши 0).
function MapPaint.waterDepth(map: MapData): buffer
	local w, h = map.width, map.height
	return MapGen.distanceField(w, h, function(i)
		return buffer.readu8(map.terrain, i) ~= T.Water
	end, function(i)
		return buffer.readu8(map.terrain, i) == T.Water
	end)
end

local function isMountain(map: MapData, x: number, y: number): boolean
	if not MapData.inBounds(map, x, y) then
		return false
	end
	return buffer.readu8(map.terrain, y * map.width + x) == T.Mountains
end

-- RGBA-буфер всей карты (4 байта на клетку, строки сверху вниз).
function MapPaint.paint(map: MapData, depth: buffer?): buffer
	local w, h = map.width, map.height
	local depthBuf = depth or MapPaint.waterDepth(map)
	local out = buffer.create(w * h * 4)
	local cfg = Config.Render
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local i = y * w + x
			local t = buffer.readu8(map.terrain, i)
			local c: Rgb
			if t == T.Water then
				local d = buffer.readu16(depthBuf, i * 2)
				if d <= cfg.WaterShallowDistance then
					c = SHALLOWS
				elseif d <= cfg.WaterMidDistance then
					c = SEA
				else
					c = ABYSS
				end
			elseif t == T.Mountains then
				local peak = true
				local r = cfg.SnowRadius
				for dy = -r, r do
					for dx = -r, r do
						if not isMountain(map, x + dx, y + dy) then
							peak = false
						end
					end
				end
				if peak then
					c = SNOW
				else
					local pair = LAND_COLORS[t]
					c = if Bits.hash2f(x, y, DITHER_SALT) < cfg.DitherShare then pair[2] else pair[1]
				end
			else
				local pair = LAND_COLORS[t]
				c = if Bits.hash2f(x, y, DITHER_SALT) < cfg.DitherShare then pair[2] else pair[1]
			end
			local o = i * 4
			buffer.writeu8(out, o, c.r)
			buffer.writeu8(out, o + 1, c.g)
			buffer.writeu8(out, o + 2, c.b)
			buffer.writeu8(out, o + 3, 255)
		end
	end
	return out
end

-- Маска клеток моря, где можно рисовать блики (u8 на клетку: 1 — можно), не ближе minDepth к суше.
function MapPaint.sparkleMask(map: MapData, depth: buffer, minDepth: number): buffer
	local n = map.width * map.height
	local mask = buffer.create(n)
	for i = 0, n - 1 do
		if buffer.readu8(map.terrain, i) == T.Water and buffer.readu16(depth, i * 2) >= minDepth then
			buffer.writeu8(mask, i, 1)
		end
	end
	return mask
end

-- Копирует прямоугольник (x0, y0, w, h) из RGBA-буфера карты в отдельный буфер чанка.
function MapPaint.copyRect(colors: buffer, mapWidth: number, x0: number, y0: number, w: number, h: number): buffer
	local out = buffer.create(w * h * 4)
	local rowBytes = w * 4
	for row = 0, h - 1 do
		buffer.copy(out, row * rowBytes, colors, ((y0 + row) * mapWidth + x0) * 4, rowBytes)
	end
	return out
end

return table.freeze(MapPaint)
