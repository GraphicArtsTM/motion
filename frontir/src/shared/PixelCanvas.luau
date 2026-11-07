--!strict
--[[
	PixelCanvas — рисование пиксельных картинок интерфейса (GDD §15л ч.8–9), общее для SceneArt (шапки окон) и
	ItemArt (картинки предметов): холст RGBA, прямоугольники, небо с дизерингом, холмы, земля, море, звёзды, солнце,
	салют, дым, флаг и спрайты игры (юниты, здания, корабли, самолёты, города, значки) цветом державы.
]]

local BuildingSprites = require("./BuildingSprites")
local CitySprites = require("./CitySprites")
local NationColors = require("./NationColors")
local Palette = require("./Palette")
local PixelIcons = require("./PixelIcons")
local PlaneSprites = require("./PlaneSprites")
local ShipSprites = require("./ShipSprites")
local UnitSprites = require("./UnitSprites")

export type Canvas = { w: number, h: number, buf: buffer }
export type Rgb = { r: number, g: number, b: number }

local function rgb(name: string): Rgb
	return Palette.rgb(name)
end

local function put(c: Canvas, x: number, y: number, r: number, g: number, b: number)
	if x < 0 or y < 0 or x >= c.w or y >= c.h then
		return
	end
	local i = (y * c.w + x) * 4
	buffer.writeu8(c.buf, i, math.clamp(math.floor(r), 0, 255))
	buffer.writeu8(c.buf, i + 1, math.clamp(math.floor(g), 0, 255))
	buffer.writeu8(c.buf, i + 2, math.clamp(math.floor(b), 0, 255))
	buffer.writeu8(c.buf, i + 3, 255)
end

local function rect(c: Canvas, x: number, y: number, w: number, h: number, col: Rgb)
	for yy = y, y + h - 1 do
		for xx = x, x + w - 1 do
			put(c, xx, yy, col.r, col.g, col.b)
		end
	end
end

-- Упорядоченный дизеринг 4×4: переход между полосами цветов без смешанных оттенков.
local BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }

-- Небо: полосы цветов сверху вниз (переход до высоты h), между соседними — дизеринг.
local function sky(c: Canvas, names: { string }, h: number)
	local n = #names
	for y = 0, c.h - 1 do -- ниже h — последний цвет (под холмами не остаётся пустых строк)
		local t = math.min(y, h - 1) / math.max(1, h - 1) * (n - 1)
		local k = math.min(n - 1, math.floor(t))
		local f = t - k
		for x = 0, c.w - 1 do
			local th = (BAYER[(y % 4) * 4 + (x % 4) + 1] + 0.5) / 16
			local col = rgb(names[if f > th then k + 2 else k + 1])
			put(c, x, y, col.r, col.g, col.b)
		end
	end
end

-- Детерминированный шум сцены (одинаковая картинка у всех).
local function rand(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

local function stars(c: Canvas, h: number, count: number, seed: number)
	local r = rand(seed)
	local white, mist = rgb("White"), rgb("Mist")
	for _ = 1, count do
		local x, y = math.floor(r() * c.w), math.floor(r() * h)
		local col = if r() < 0.3 then white else mist
		put(c, x, y, col.r, col.g, col.b)
	end
end

-- Холмы: силуэт от линии base с волной amp, залит цветом до низа.
local function hills(c: Canvas, base: number, amp: number, freq: number, phase: number, name: string)
	local col = rgb(name)
	for x = 0, c.w - 1 do
		local top =
			math.floor(base - amp * (0.6 * math.sin(x * freq + phase) + 0.4 * math.sin(x * freq * 2.7 + phase * 1.9)))
		for y = math.max(0, top), c.h - 1 do
			put(c, x, y, col.r, col.g, col.b)
		end
	end
end

local function ground(c: Canvas, y0: number, top: string, body: string)
	rect(c, 0, y0, c.w, 1, rgb(top))
	rect(c, 0, y0 + 1, c.w, c.h - y0 - 1, rgb(body))
end

local function water(c: Canvas, x0: number, y0: number, w: number, seed: number)
	rect(c, x0, y0, w, c.h - y0, rgb("Sea"))
	local r = rand(seed)
	local foam = rgb("Shallows")
	for _ = 1, w // 3 do
		rect(c, x0 + math.floor(r() * w), y0 + 1 + math.floor(r() * (c.h - y0 - 2)), 3, 1, foam)
	end
end

local function nation(i: number): Rgb
	local n = NationColors.Colors[i]
	return { r = n.r, g = n.g, b = n.b }
end

-- Спрайты игры: позиция — левый верхний угол, s — масштаб, flip — зеркально.
local function unit(c: Canvas, kind: string, x: number, y: number, s: number, col: Rgb, flip: boolean?)
	local ink = rgb("Ink")
	for _, p in UnitSprites.Shapes[kind] do
		local r, g, b = col.r, col.g, col.b
		if p.ink then
			r, g, b = ink.r, ink.g, ink.b
		else
			r, g, b = UnitSprites.shade(col.r, col.g, col.b, p.shade)
		end
		local px = if flip then UnitSprites.Width - p.x - p.w else p.x
		for yy = 0, p.h * s - 1 do
			for xx = 0, p.w * s - 1 do
				put(c, x + px * s + xx, y + p.y * s + yy, r, g, b)
			end
		end
	end
end

local function building(c: Canvas, kind: string, x: number, y: number, s: number, col: Rgb)
	for _, p in BuildingSprites.Shapes[kind] do
		local r, g, b = BuildingSprites.rgb(p, col.r, col.g, col.b)
		for yy = 0, p.h * s - 1 do
			for xx = 0, p.w * s - 1 do
				put(c, x + p.x * s + xx, y + p.y * s + yy, r, g, b)
			end
		end
	end
end

local function ship(c: Canvas, kind: string, x: number, y: number, s: number, col: Rgb)
	local ink, white = rgb("Ink"), rgb("White")
	for _, p in ShipSprites.Shapes[kind] do
		local q = if p.ink then ink elseif p.light then white else col
		for yy = 0, p.h * s - 1 do
			for xx = 0, p.w * s - 1 do
				put(c, x + p.x * s + xx, y + p.y * s + yy, q.r, q.g, q.b)
			end
		end
	end
end

local function plane(c: Canvas, kind: string, x: number, y: number, s: number, col: Rgb)
	local ink = rgb("Ink")
	for _, p in PlaneSprites.Shapes[kind] do
		local q = if p.ink then ink else col
		for yy = 0, p.h * s - 1 do
			for xx = 0, p.w * s - 1 do
				put(c, x + p.x * s + xx, y + p.y * s + yy, q.r, q.g, q.b)
			end
		end
	end
end

local function city(c: Canvas, level: number, x: number, y: number, s: number, col: Rgb, capital: boolean?)
	for _, p in CitySprites.parts(level, capital == true) do
		local r, g, b = CitySprites.rgb(p, col.r, col.g, col.b)
		for yy = 0, p.h * s - 1 do
			for xx = 0, p.w * s - 1 do
				put(c, x + p.x * s + xx, y + p.y * s + yy, r, g, b)
			end
		end
	end
end

local function icon(c: Canvas, key: string, x: number, y: number, s: number)
	local parts: { PixelIcons.Part } = PixelIcons.Icons[key] or {}
	for _, p in parts do
		local col = rgb(p.color)
		rect(c, x + p.x * s, y + p.y * s, p.w * s, p.h * s, col)
	end
end

-- Флаг на древке: полотнище цвета col с полосой.
local function flag(c: Canvas, x: number, y: number, col: Rgb, stripe: Rgb)
	rect(c, x, y, 1, 16, rgb("Mist"))
	rect(c, x + 1, y, 9, 6, col)
	rect(c, x + 1, y + 2, 9, 2, stripe)
	rect(c, x, y - 1, 1, 1, rgb("Gold"))
end

-- Вспышка салюта / взрыва: лучи из точки.
local function burst(c: Canvas, x: number, y: number, r: number, name: string, core: string?)
	local col = rgb(name)
	for k = 0, 7 do
		local a = k * math.pi / 4
		for d = 1, r do
			if d % 2 == 1 or d == r then
				put(
					c,
					math.floor(x + math.cos(a) * d + 0.5),
					math.floor(y + math.sin(a) * d + 0.5),
					col.r,
					col.g,
					col.b
				)
			end
		end
	end
	local cc = rgb(core or "White")
	put(c, x, y, cc.r, cc.g, cc.b)
end

local function smoke(c: Canvas, x: number, y: number, h: number, seed: number)
	local r = rand(seed)
	local a, b = rgb("Steel"), rgb("Rock")
	for k = 0, h do
		local w = 2 + math.floor(k / 3)
		local cx = x + math.floor((r() - 0.5) * 3) + k // 4
		rect(c, cx - w // 2, y - k * 2, w, 2, if k % 2 == 0 then a else b)
	end
end

local function sun(c: Canvas, x: number, y: number, rad: number, name: string)
	local col = rgb(name)
	for dy = -rad, rad do
		for dx = -rad, rad do
			if dx * dx + dy * dy <= rad * rad then
				put(c, x + dx, y + dy, col.r, col.g, col.b)
			end
		end
	end
end

local function new(w: number, h: number): Canvas
	return { w = w, h = h, buf = buffer.create(w * h * 4) }
end

return table.freeze({
	new = new,
	rgb = rgb,
	put = put,
	rect = rect,
	sky = sky,
	rand = rand,
	stars = stars,
	hills = hills,
	ground = ground,
	water = water,
	nation = nation,
	unit = unit,
	building = building,
	ship = ship,
	plane = plane,
	city = city,
	icon = icon,
	flag = flag,
	burst = burst,
	smoke = smoke,
	sun = sun,
})
