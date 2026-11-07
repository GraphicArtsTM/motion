--!strict
--[[
	SceneArt — пиксельные картинки-шапки окон (GDD §15л ч.8): сцена W×H (RGBA) из палитры и спрайтов игры —
	небо с пиксельным переходом (упорядоченный дизеринг), звёзды или солнце, холмы, земля или море и спрайты
	(рисование — PixelCanvas). Чистый модуль: рисует и клиент (UI/SceneBanner → EditableImage), и превью
	(tools/scene_preview). Одинаковый ключ — одинаковая картинка.
]]

local PixelCanvas = require("./PixelCanvas")

type Canvas = PixelCanvas.Canvas
type Rgb = PixelCanvas.Rgb
local rgb = PixelCanvas.rgb
local put = PixelCanvas.put
local rect = PixelCanvas.rect
local sky = PixelCanvas.sky
local rand = PixelCanvas.rand
local stars = PixelCanvas.stars
local hills = PixelCanvas.hills
local ground = PixelCanvas.ground
local water = PixelCanvas.water
local nation = PixelCanvas.nation
local unit = PixelCanvas.unit
local building = PixelCanvas.building
local ship = PixelCanvas.ship
local plane = PixelCanvas.plane
local city = PixelCanvas.city
local icon = PixelCanvas.icon
local flag = PixelCanvas.flag
local burst = PixelCanvas.burst
local smoke = PixelCanvas.smoke
local sun = PixelCanvas.sun

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
