--!strict
--[[
	SceneArt — пиксельные картинки-шапки окон (GDD §15л ч.8): сцена W×H (RGBA) из палитры и спрайтов игры —
	небо с пиксельным переходом (упорядоченный дизеринг), звёзды или солнце, холмы, земля или море и спрайты
	(UnitSprites, BuildingSprites, ShipSprites, PlaneSprites, CitySprites, PixelIcons). Чистый модуль: рисует и клиент
	(UI/SceneBanner → EditableImage), и превью (tools/scene_preview). Одинаковый ключ — одинаковая картинка.
]]

local BuildingSprites = require("./BuildingSprites")
local CitySprites = require("./CitySprites")
local NationColors = require("./NationColors")
local Palette = require("./Palette")
local PixelIcons = require("./PixelIcons")
local PlaneSprites = require("./PlaneSprites")
local ShipSprites = require("./ShipSprites")
local UnitSprites = require("./UnitSprites")

local SceneArt = {}

SceneArt.W = 200
SceneArt.H = 36
SceneArt.Keys = table.freeze({
	"shop",
	"wardrobe",
	"quests",
	"ranks",
	"arsenal",
	"tech",
	"diplomacy",
	"council",
	"sound",
	"server",
	"help",
	"gamemenu",
	"victory",
	"defeat",
	"lobby",
	"battle",
}) :: { string }

type Canvas = { w: number, h: number, buf: buffer }
type Rgb = { r: number, g: number, b: number }

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

-- Сцены.
local SCENES: { [string]: (c: Canvas) -> () } = {}

SCENES.shop = function(c)
	sky(c, { "Plum", "Orange", "Gold" }, 26)
	sun(c, 160, 22, 7, "Gold")
	hills(c, 24, 3, 0.05, 1, "Basalt")
	ground(c, 28, "Sand", "Dune")
	building(c, "Market", 20, 4, 2, nation(5))
	building(c, "Market", 52, 4, 2, nation(9))
	for k = 0, 3 do
		icon(c, "arsenal", 90 + k * 11, 20, 1)
	end
	icon(c, "money", 84, 12, 1)
	icon(c, "money", 136, 18, 1)
	water(c, 150, 26, 50, 7)
	ship(c, "Merchant", 168, 14, 2, nation(3))
end

SCENES.wardrobe = function(c)
	sky(c, { "Sea", "River", "Sky" }, 24)
	hills(c, 22, 4, 0.04, 2, "Forest")
	ground(c, 27, "Meadow", "Grass")
	for k = 0, 5 do
		flag(c, 14 + k * 30, 6 + (k % 2) * 3, nation(1 + k * 3), rgb(if k % 2 == 0 then "White" else "Gold"))
	end
	for k = 0, 6 do
		unit(c, "Infantry", 8 + k * 27, 17, 1, nation(1 + (k * 5) % 24))
	end
end

SCENES.quests = function(c)
	sky(c, { "Ink", "Night", "Abyss" }, 28)
	stars(c, 20, 40, 3)
	sun(c, 30, 7, 3, "Snow")
	hills(c, 25, 4, 0.06, 4, "Pine")
	ground(c, 29, "Forest", "Pine")
	icon(c, "quests", 82, 4, 3)
	burst(c, 140, 27, 2, "Orange", "Gold")
	unit(c, "Infantry", 122, 18, 1, nation(11))
	unit(c, "Infantry", 152, 18, 1, nation(11), true)
	building(c, "Barracks", 170, 15, 1, nation(11))
end

SCENES.ranks = function(c)
	sky(c, { "Night", "Violet", "Orange" }, 26)
	hills(c, 24, 2, 0.05, 3, "Basalt")
	ground(c, 28, "Rock", "Basalt")
	flag(c, 10, 8, nation(2), rgb("Gold"))
	for k = 0, 7 do
		unit(c, "Infantry", 24 + k * 16, 18, 1, nation(2))
	end
	unit(c, "Tanks", 156, 14, 1, nation(2))
	icon(c, "army", 176, 4, 2)
end

SCENES.arsenal = function(c)
	sky(c, { "Ink", "Night", "Slate" }, 28)
	stars(c, 18, 30, 5)
	hills(c, 26, 3, 0.07, 1, "Basalt")
	ground(c, 30, "Rock", "Basalt")
	building(c, "MissileSilo", 14, 6, 2, nation(4))
	building(c, "Sam", 50, 6, 2, nation(4))
	building(c, "AirDefense", 84, 6, 2, nation(4))
	-- Ракета в небе с дымным следом.
	for k = 0, 14 do
		put(c, 120 + k * 3, 26 - k, 74, 83, 120)
	end
	rect(c, 165, 10, 3, 3, rgb("White"))
	rect(c, 168, 9, 2, 2, rgb("Red"))
	burst(c, 186, 8, 4, "Gold", "White")
end

SCENES.tech = function(c)
	sky(c, { "Abyss", "Sea", "Shallows" }, 26)
	hills(c, 24, 3, 0.05, 5, "Pine")
	ground(c, 28, "Meadow", "Grass")
	building(c, "Radar", 14, 4, 2, nation(6))
	building(c, "Factory", 48, 4, 2, nation(6))
	building(c, "Airfield", 86, 4, 2, nation(6))
	plane(c, "Fighter", 140, 6, 2, nation(6))
	plane(c, "Bomber", 170, 12, 2, nation(6))
	icon(c, "tech", 124, 18, 1)
end

SCENES.diplomacy = function(c)
	sky(c, { "Sea", "River", "Sky" }, 26)
	hills(c, 24, 3, 0.04, 2, "Forest")
	ground(c, 28, "Meadow", "Grass")
	city(c, 4, 14, 5, 1, nation(3))
	city(c, 4, 160, 5, 1, nation(13))
	flag(c, 46, 10, nation(3), rgb("White"))
	flag(c, 146, 10, nation(13), rgb("White"))
	icon(c, "diplomacy", 84, 2, 4)
end

SCENES.council = function(c)
	sky(c, { "Night", "Slate", "Steel" }, 26)
	hills(c, 24, 2, 0.05, 1, "Basalt")
	ground(c, 28, "Rock", "Basalt")
	city(c, 5, 86, 1, 1, nation(8), true)
	for k = 0, 3 do
		flag(c, 16 + k * 18, 10, nation(1 + k * 5), rgb("White"))
		flag(c, 128 + k * 18, 10, nation(4 + k * 5), rgb("Gold"))
	end
end

SCENES.sound = function(c)
	sky(c, { "Ink", "Night", "Violet" }, 28)
	stars(c, 22, 45, 9)
	hills(c, 26, 5, 0.05, 2, "Pine")
	ground(c, 30, "Forest", "Pine")
	icon(c, "sound", 60, 4, 2)
	icon(c, "sound", 96, 10, 1)
	icon(c, "sound", 120, 2, 2)
	sun(c, 172, 9, 5, "Snow")
end

SCENES.server = function(c)
	sky(c, { "Slate", "Steel", "Mist" }, 26)
	hills(c, 24, 2, 0.05, 1, "Rock")
	ground(c, 28, "Rock", "Basalt")
	building(c, "Fort", 20, 4, 2, nation(10))
	building(c, "Barracks", 56, 4, 2, nation(10))
	icon(c, "server", 96, 2, 3)
	building(c, "Radar", 140, 4, 2, nation(10))
	flag(c, 180, 9, nation(10), rgb("Gold"))
end

SCENES.help = function(c)
	-- Вид сверху: море, два материка разных держав (кругами — неровный берег) и стрелка наступления.
	water(c, 0, 0, c.w, 11)
	local a, b = nation(2), nation(14)
	local ink = rgb("Ink")
	local function land(cx: number, cy: number, col: Rgb)
		local r = rand(cx * 7 + cy)
		for _ = 1, 9 do
			local x, y = cx + math.floor((r() - 0.5) * 50), cy + math.floor((r() - 0.5) * 16)
			local rad = 6 + math.floor(r() * 7)
			for dy = -rad - 1, rad + 1 do
				for dx = -rad - 1, rad + 1 do
					local d = dx * dx + dy * dy
					if d <= (rad + 1) * (rad + 1) and d > rad * rad then
						local i = ((y + dy) * c.w + x + dx) * 4
						if x + dx >= 0 and x + dx < c.w and y + dy >= 0 and y + dy < c.h then
							if buffer.readu8(c.buf, i) ~= col.r or buffer.readu8(c.buf, i + 1) ~= col.g then
								put(c, x + dx, y + dy, ink.r, ink.g, ink.b)
							end
						end
					end
				end
			end
			for dy = -rad, rad do
				for dx = -rad, rad do
					if dx * dx + dy * dy <= rad * rad then
						put(c, x + dx, y + dy, col.r, col.g, col.b)
					end
				end
			end
		end
	end
	land(55, 18, a)
	land(145, 18, b)
	for k = 0, 4 do
		rect(c, 66 + k * 7, 17, 5, 2, rgb("White"))
	end
	rect(c, 101, 14, 2, 8, rgb("White"))
	rect(c, 103, 15, 2, 6, rgb("White"))
	rect(c, 105, 17, 2, 2, rgb("White"))
	city(c, 3, 34, 10, 1, a, true)
	city(c, 3, 150, 10, 1, b, true)
end

SCENES.gamemenu = function(c)
	sky(c, { "Night", "Plum", "Orange" }, 26)
	hills(c, 24, 3, 0.06, 2, "Basalt")
	ground(c, 28, "Rock", "Basalt")
	unit(c, "Tanks", 20, 14, 1, nation(2))
	unit(c, "Artillery", 40, 14, 1, nation(2))
	unit(c, "Tanks", 150, 14, 1, nation(12), true)
	unit(c, "Infantry", 170, 15, 1, nation(12), true)
	burst(c, 96, 18, 5, "Orange", "Gold")
	burst(c, 112, 12, 3, "Gold", "White")
	smoke(c, 104, 26, 8, 3)
	plane(c, "Bomber", 70, 3, 2, nation(2))
end

SCENES.victory = function(c)
	sky(c, { "Ink", "Night", "Violet" }, 28)
	stars(c, 14, 20, 13)
	burst(c, 40, 8, 6, "Gold", "White")
	burst(c, 100, 5, 5, "Rose", "White")
	burst(c, 160, 9, 6, "Sky", "White")
	hills(c, 27, 2, 0.05, 1, "Pine")
	ground(c, 30, "Forest", "Pine")
	city(c, 5, 84, 6, 1, nation(9), true)
	flag(c, 120, 10, nation(9), rgb("Gold"))
	unit(c, "Infantry", 30, 20, 1, nation(9))
	unit(c, "Tanks", 150, 19, 1, nation(9))
end

SCENES.defeat = function(c)
	sky(c, { "Basalt", "Rock", "Steel" }, 28)
	hills(c, 27, 2, 0.05, 2, "Basalt")
	ground(c, 30, "Rock", "Basalt")
	-- Развалины: обломки стен и дым.
	for k = 0, 5 do
		local hgt = 4 + (k * 7) % 9
		rect(c, 30 + k * 26, 30 - hgt, 10, hgt, rgb("Basalt"))
		rect(c, 30 + k * 26, 30 - hgt, 10, 1, rgb("Rock"))
		smoke(c, 34 + k * 26, 30 - hgt, 6 + k % 3, k + 1)
	end
	rect(c, 100, 14, 1, 16, rgb("Mist"))
	rect(c, 101, 18, 7, 4, rgb("Red"))
end

SCENES.lobby = function(c)
	sky(c, { "Sea", "River", "Sky" }, 24)
	sun(c, 176, 7, 5, "Gold")
	hills(c, 22, 4, 0.05, 3, "Forest")
	ground(c, 26, "Meadow", "Grass")
	for k = 0, 4 do
		unit(c, "Infantry", 6 + k * 14, 16, 1, nation(1))
	end
	unit(c, "Tanks", 80, 15, 1, nation(1))
	unit(c, "Artillery", 100, 15, 1, nation(1))
	unit(c, "AntiAir", 120, 15, 1, nation(1))
	plane(c, "Fighter", 140, 3, 2, nation(1))
	plane(c, "Fighter", 160, 9, 2, nation(1))
end

SCENES.battle = function(c)
	sky(c, { "Night", "Plum", "Orange" }, 24)
	hills(c, 22, 3, 0.05, 1, "Basalt")
	ground(c, 26, "Grass", "Forest")
	water(c, 140, 24, 60, 21)
	unit(c, "Tanks", 16, 15, 1, nation(4))
	unit(c, "Infantry", 34, 16, 1, nation(4))
	unit(c, "Infantry", 100, 16, 1, nation(15), true)
	unit(c, "Tanks", 116, 15, 1, nation(15), true)
	burst(c, 70, 14, 5, "Orange", "Gold")
	smoke(c, 70, 24, 6, 9)
	ship(c, "Destroyer", 160, 12, 2, nation(15))
	plane(c, "Bomber", 50, 3, 2, nation(4))
end

-- Картинка сцены key: RGBA w×h (по умолчанию SceneArt.W×H). Неизвестный ключ — небо и земля.
function SceneArt.paint(key: string, w: number?, h: number?): buffer
	local c: Canvas =
		{ w = w or SceneArt.W, h = h or SceneArt.H, buf = buffer.create((w or SceneArt.W) * (h or SceneArt.H) * 4) }
	local draw = SCENES[key]
	if draw ~= nil then
		draw(c)
	else
		sky(c, { "Night", "Slate" }, c.h - 6)
		ground(c, c.h - 6, "Grass", "Forest")
	end
	return c.buf
end

return table.freeze(SceneArt)
