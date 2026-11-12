--!strict
--[[
	ItemArt — картинки предметов в карточках окон (GDD §15л ч.9): W×H (RGBA) из палитры и спрайтов игры (PixelCanvas).
	Ключи: "shop.<товар>", "pattern.<узор>", "capture.<цвет>", "title.<титул>", "quest.<вид>", "tech.<ветка><уровень>",
	"arsenal.<предмет>", "council.*", "naval.*", "air.*", "war.declare", "peace.*", "results.*". Неизвестный ключ — запасная картинка (не ошибка). Клиент — UI/CardKit, превью — tools/item_preview.
]]

local Palette = require("./Palette")
local PixelCanvas = require("./PixelCanvas")

type Canvas = PixelCanvas.Canvas
type Rgb = PixelCanvas.Rgb
local rgb = PixelCanvas.rgb
local put = PixelCanvas.put
local rect = PixelCanvas.rect
local sky = PixelCanvas.sky
local stars = PixelCanvas.stars
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
local sun = PixelCanvas.sun

local ItemArt = {}

ItemArt.W = 48
ItemArt.H = 32

-- Фон карточки: небо двух-трёх цветов и пол.
local function stage(c: Canvas, names: { string }, floor: string?)
	sky(c, names, c.h - 6)
	if floor ~= nil then
		rect(c, 0, c.h - 5, c.w, 5, rgb(floor))
		rect(c, 0, c.h - 5, c.w, 1, rgb(if floor == "Grass" then "Meadow" else "Mist"))
	end
end

-- Маленькая звезда-искра.
local function spark(c: Canvas, x: number, y: number, name: string)
	local col = rgb(name)
	put(c, x, y, col.r, col.g, col.b)
	put(c, x - 1, y, col.r, col.g, col.b)
	put(c, x + 1, y, col.r, col.g, col.b)
	put(c, x, y - 1, col.r, col.g, col.b)
	put(c, x, y + 1, col.r, col.g, col.b)
end

local function medal(c: Canvas, x: number, y: number, ribbon: string, disk: string)
	rect(c, x, y, 3, 7, rgb(ribbon))
	rect(c, x + 5, y, 3, 7, rgb(ribbon))
	sun(c, x + 4, y + 11, 5, "Orange")
	sun(c, x + 4, y + 11, 4, disk)
	rect(c, x + 3, y + 9, 3, 4, rgb("White"))
end

local function crate(c: Canvas, x: number, y: number, s: number)
	icon(c, "arsenal", x, y, s)
end

local function crown(c: Canvas, x: number, y: number)
	local g, o = rgb("Gold"), rgb("Orange")
	rect(c, x, y + 6, 18, 6, g)
	rect(c, x, y + 11, 18, 1, o)
	for k = 0, 2 do
		rect(c, x + k * 7, y, 4, 7, g)
		rect(c, x + 1 + k * 7, y - 1, 2, 1, g)
	end
	rect(c, x + 7, y + 7, 4, 3, rgb("Red"))
	rect(c, x + 2, y + 8, 2, 2, rgb("Sky"))
	rect(c, x + 14, y + 8, 2, 2, rgb("Sky"))
end

local function cup(c: Canvas, x: number, y: number)
	local g, o = rgb("Gold"), rgb("Orange")
	rect(c, x, y, 16, 2, g)
	rect(c, x + 1, y + 2, 14, 7, g)
	rect(c, x + 3, y + 9, 10, 2, g)
	rect(c, x + 6, y + 11, 4, 4, o)
	rect(c, x + 3, y + 15, 10, 3, g)
	rect(c, x - 3, y + 2, 3, 2, g)
	rect(c, x + 16, y + 2, 3, 2, g)
	rect(c, x + 3, y + 3, 2, 4, rgb("White"))
end

local function podium(c: Canvas, x: number, y: number)
	rect(c, x + 12, y, 12, 18, rgb("Gold"))
	rect(c, x, y + 6, 12, 12, rgb("Mist"))
	rect(c, x + 24, y + 9, 12, 9, rgb("Orange"))
	rect(c, x + 16, y + 4, 4, 6, rgb("Orange"))
	rect(c, x + 4, y + 9, 4, 6, rgb("Slate"))
	rect(c, x + 28, y + 11, 4, 5, rgb("Basalt"))
end

local function ribbon(c: Canvas, name: string)
	local col = rgb(name)
	rect(c, 6, 10, 36, 12, col)
	rect(c, 2, 13, 4, 9, col)
	rect(c, 42, 13, 4, 9, col)
	rect(c, 6, 10, 36, 1, rgb("White"))
	rect(c, 6, 21, 36, 1, rgb("Ink"))
	spark(c, 24, 16, "Gold")
	spark(c, 15, 16, "White")
	spark(c, 33, 16, "White")
end

-- Узор территории на квадрате цвета державы (как TerritoryPaint.Extra.pattern — по смыслу).
local function swatch(c: Canvas, kind: string)
	local base = rgb("River")
	local edge = rgb("Ink")
	local mark = rgb("Sky")
	rect(c, 6, 3, 36, 26, base)
	for y = 3, 28 do
		for x = 6, 41 do
			local u, v = x - 6, y - 3
			local hit = false
			if kind == "Stripes" then
				hit = (u + v) % 6 < 2
			elseif kind == "Checker" then
				hit = ((u // 4) + (v // 4)) % 2 == 0
			elseif kind == "Dots" then
				hit = u % 6 >= 2 and u % 6 <= 3 and v % 6 >= 2 and v % 6 <= 3
			elseif kind == "Grid" then
				hit = u % 6 == 0 or v % 6 == 0
			elseif kind == "Waves" then
				hit = (v + math.floor(2 * math.sin(u * 0.6))) % 6 == 0
			end
			if hit then
				put(c, x, y, mark.r, mark.g, mark.b)
			end
		end
	end
	rect(c, 5, 2, 38, 1, edge)
	rect(c, 5, 29, 38, 1, edge)
	rect(c, 5, 2, 1, 28, edge)
	rect(c, 42, 2, 1, 28, edge)
end

local ITEMS: { [string]: (c: Canvas) -> () } = {}

-- Магазин: бусты.
ITEMS["shop.Mobilize"] = function(c)
	stage(c, { "Night", "Slate" }, "Grass")
	unit(c, "Infantry", 2, 15, 1, nation(1))
	unit(c, "Infantry", 34, 15, 1, nation(1))
	unit(c, "Infantry", 12, 6, 2, nation(1))
end
ITEMS["shop.Loan"] = function(c)
	stage(c, { "Night", "Plum" }, nil)
	icon(c, "money", 4, 10, 2)
	icon(c, "money", 12, 4, 3)
	icon(c, "money", 32, 14, 2)
	spark(c, 40, 6, "White")
end
ITEMS["shop.Research"] = function(c)
	stage(c, { "Abyss", "Sea" }, nil)
	icon(c, "tech", 12, 4, 3)
	spark(c, 8, 6, "Lime")
	spark(c, 40, 10, "Lime")
	spark(c, 38, 24, "White")
end
ITEMS["shop.Reserve"] = function(c)
	stage(c, { "Night", "Violet" }, nil)
	icon(c, "hqReserve", 12, 4, 3)
	spark(c, 40, 8, "Gold")
end
ITEMS["shop.Guards"] = function(c)
	stage(c, { "Night", "Plum" }, "Grass")
	unit(c, "Tanks", 12, 7, 2, nation(9))
	spark(c, 6, 6, "Gold")
	spark(c, 12, 4, "Gold")
end
ITEMS["shop.Airstrike"] = function(c)
	stage(c, { "Night", "Plum", "Orange" }, "Basalt")
	plane(c, "Bomber", 8, 2, 3, nation(2))
	burst(c, 34, 24, 4, "Orange", "Gold")
end
ITEMS["shop.Squadron"] = function(c)
	sky(c, { "Sea", "Sky" }, 18)
	water(c, 0, 20, c.w, 3)
	ship(c, "Destroyer", 2, 6, 3, nation(4))
	ship(c, "Transport", 28, 12, 2, nation(4))
end
ITEMS["shop.AirWing"] = function(c)
	sky(c, { "Sea", "Sky" }, c.h)
	plane(c, "Fighter", 2, 4, 2, nation(6))
	plane(c, "Bomber", 22, 14, 3, nation(6))
end
-- Пропуска.
ITEMS["shop.HQ"] = function(c)
	stage(c, { "Slate", "Steel" }, "Basalt")
	building(c, "Fort", 6, 3, 2, nation(10))
	flag(c, 36, 8, nation(10), rgb("Gold"))
end
ITEMS["shop.Intel"] = function(c)
	stage(c, { "Ink", "Night" }, "Basalt")
	building(c, "Radar", 12, 3, 2, nation(7))
	for k = 1, 3 do
		rect(c, 38 + k * 2, 8 - k, 1, 4 + k * 2, rgb("Sky"))
	end
end
ITEMS["shop.Vip"] = function(c)
	stage(c, { "Plum", "Violet" }, nil)
	crown(c, 15, 10)
	spark(c, 8, 6, "White")
	spark(c, 40, 8, "Gold")
	spark(c, 38, 26, "White")
end
ITEMS["shop.AllCommanders"] = function(c)
	stage(c, { "Night", "Slate" }, "Grass")
	for k = 0, 3 do
		unit(c, "Infantry", 1 + k * 12, 15, 1, nation(2 + k * 5))
	end
	spark(c, 24, 5, "Gold")
end
-- Наборы.
ITEMS["shop.Recruit"] = function(c)
	stage(c, { "Sea", "River" }, "Grass")
	unit(c, "Infantry", 6, 6, 2, nation(11))
	icon(c, "money", 32, 16, 1)
	icon(c, "money", 38, 10, 1)
end
ITEMS["shop.Medals"] = function(c)
	stage(c, { "Night", "Plum" }, nil)
	medal(c, 8, 3, "Red", "Gold")
	medal(c, 28, 6, "Sky", "Gold")
end
ITEMS["shop.Tokens"] = function(c)
	stage(c, { "Abyss", "Sea" }, nil)
	for k = 0, 1 do
		local x, y = 16 + k * 14, 15 - k * 4
		sun(c, x, y, 9, "River")
		sun(c, x, y, 7, "Sky")
		spark(c, x, y, "White")
	end
end
ITEMS["shop.Crate1"] = function(c)
	stage(c, { "Night", "Slate" }, "Basalt")
	crate(c, 12, 2, 3)
end
ITEMS["shop.Crate5"] = function(c)
	stage(c, { "Night", "Slate" }, "Basalt")
	crate(c, 2, 11, 2)
	crate(c, 17, 11, 2)
	crate(c, 32, 11, 2)
	crate(c, 10, 0, 2)
	crate(c, 25, 0, 2)
end
ITEMS["shop.Crates"] = function(c)
	stage(c, { "Night", "Plum" }, "Basalt")
	crate(c, 12, 6, 3)
	burst(c, 24, 6, 5, "Gold", "White")
end
ITEMS["shop.SeasonPass"] = function(c)
	stage(c, { "Violet", "Plum" }, nil)
	icon(c, "quests", 6, 4, 3)
	spark(c, 38, 8, "Gold")
	spark(c, 34, 20, "Gold")
	spark(c, 42, 24, "White")
end
ITEMS["shop.Weekly"] = function(c)
	stage(c, { "Plum", "Orange" }, "Dune")
	crate(c, 4, 6, 2)
	icon(c, "money", 24, 8, 2)
	spark(c, 42, 6, "White")
end

-- Задания.
ITEMS["quest.play"] = function(c)
	stage(c, { "Night", "Plum" }, nil)
	icon(c, "army", 12, 4, 3)
end
ITEMS["quest.win"] = function(c)
	stage(c, { "Night", "Violet" }, nil)
	cup(c, 16, 6)
	spark(c, 8, 8, "Gold")
	spark(c, 40, 10, "White")
end
ITEMS["quest.top3"] = function(c)
	stage(c, { "Night", "Slate" }, nil)
	podium(c, 6, 12)
	spark(c, 24, 6, "Gold")
end
ITEMS["quest.cities"] = function(c)
	stage(c, { "Sea", "Sky" }, "Grass")
	city(c, 3, 6, 4, 1, nation(3))
	city(c, 4, 26, 2, 1, nation(3), true)
end
ITEMS["quest.land"] = function(c)
	stage(c, { "Sea", "River" }, "Grass")
	icon(c, "land", 12, 2, 3)
end

-- Технологии.
local TECH: { [string]: (c: Canvas) -> () } = {
	Army1 = function(c)
		building(c, "Barracks", 4, 3, 2, nation(1))
		unit(c, "Infantry", 32, 15, 1, nation(1))
	end,
	Army2 = function(c)
		icon(c, "convoy", 12, 4, 3)
	end,
	Army3 = function(c)
		building(c, "MissileSilo", 12, 3, 2, nation(1))
	end,
	Army4 = function(c)
		unit(c, "Tanks", 12, 7, 2, rgb("Steel"))
	end,
	Economy1 = function(c)
		icon(c, "money", 12, 4, 3)
	end,
	Economy2 = function(c)
		building(c, "OilRig", 12, 3, 2, nation(5))
	end,
	Economy3 = function(c)
		ship(c, "Merchant", 8, 3, 4, nation(5))
	end,
	Economy4 = function(c)
		icon(c, "stability", 12, 2, 3)
	end,
	Fleet1 = function(c)
		building(c, "Port", 12, 3, 2, nation(4))
	end,
	Fleet2 = function(c)
		plane(c, "Fighter", 6, 4, 3, nation(4))
		plane(c, "Bomber", 28, 14, 2, nation(4))
	end,
	Fleet3 = function(c)
		building(c, "AirDefenseLong", 12, 3, 2, nation(4)) -- «Дальняя ПВО» (§15х ч.6)
	end,
	Fleet4 = function(c)
		building(c, "AirDefense", 12, 3, 2, nation(4)) -- «Сеть ПВО»
	end,
}
for key, draw in TECH do
	local branch = string.match(key, "^%a+") :: string
	local back = if branch == "Army"
		then { "Night", "Plum" }
		elseif branch == "Economy" then { "Night", "Ochre" }
		else { "Abyss", "Sea" }
	ITEMS["tech." .. key] = function(c)
		stage(c, back, "Basalt")
		draw(c)
	end
end

-- Арсенал.
ITEMS["arsenal.Reinforce"] = function(c)
	stage(c, { "Night", "Slate" }, "Grass")
	for k = 0, 2 do
		unit(c, "Infantry", 2 + k * 15, 15, 1, nation(8))
	end
	icon(c, "reinforce", 18, 1, 1)
end
ITEMS["arsenal.Convoy"] = function(c)
	stage(c, { "Night", "Ochre" }, "Dune")
	icon(c, "convoy", 4, 10, 2)
	icon(c, "convoy", 26, 12, 2)
	icon(c, "oil", 20, 2, 1)
end
ITEMS["arsenal.HqReserve"] = function(c)
	stage(c, { "Night", "Violet" }, nil)
	icon(c, "hqReserve", 12, 4, 3)
end
ITEMS["arsenal.Barrage"] = function(c)
	stage(c, { "Night", "Plum", "Orange" }, "Basalt")
	unit(c, "Artillery", 2, 15, 1, nation(12))
	burst(c, 30, 12, 5, "Orange", "Gold")
	burst(c, 40, 20, 3, "Gold", "White")
end
ITEMS["arsenal.Jammer"] = function(c)
	stage(c, { "Ink", "Night" }, "Basalt")
	stars(c, 14, 10, 4)
	icon(c, "jammer", 12, 3, 3)
end

-- Совет (§15л ч.10): резолюции.
local function cross(c: Canvas, x: number, y: number, size: number)
	local red = rgb("Red")
	for k = 0, size - 1 do
		rect(c, x + k, y + k, 2, 2, red)
		rect(c, x + size - 1 - k, y + k, 2, 2, red)
	end
end
ITEMS["council.sanctions"] = function(c)
	stage(c, { "Night", "Plum" }, nil)
	icon(c, "money", 12, 4, 3)
	cross(c, 10, 4, 26)
end
ITEMS["council.truce"] = function(c)
	stage(c, { "Sea", "Sky" }, "Grass")
	rect(c, 14, 2, 2, 25, rgb("Mist"))
	rect(c, 16, 3, 18, 11, rgb("White"))
	rect(c, 16, 13, 18, 1, rgb("Snow"))
	unit(c, "Infantry", 34, 15, 1, nation(3), true)
end
ITEMS["council.aid"] = function(c)
	stage(c, { "Sea", "River" }, "Dune")
	crate(c, 2, 8, 2)
	icon(c, "people", 26, 6, 2)
	icon(c, "money", 34, 20, 1)
end
ITEMS["council.freeTrade"] = function(c)
	sky(c, { "Sea", "Sky" }, 18)
	water(c, 0, 20, c.w, 5)
	ship(c, "Merchant", 4, 6, 3, nation(5))
	icon(c, "money", 34, 4, 1)
	icon(c, "money", 40, 12, 1)
end
ITEMS["council.superweaponBan"] = function(c)
	stage(c, { "Ink", "Night" }, "Basalt")
	building(c, "MissileSilo", 12, 3, 2, nation(4))
	cross(c, 8, 2, 30)
end

-- Порт, аэродром, война и мир, итоги (§15л ч.11).
ITEMS["naval.port"] = function(c)
	sky(c, { "Night", "Sea", "Sky" }, 20)
	water(c, 0, 21, c.w, 11)
	rect(c, 0, 19, 22, 3, rgb("Rock"))
	building(c, "Port", 2, 1, 2, nation(4))
	ship(c, "Transport", 26, 16, 2, nation(4))
	ship(c, "Destroyer", 36, 22, 1, nation(4))
end
ITEMS["naval.Transport"] = function(c)
	sky(c, { "Sea", "Sky" }, 22)
	water(c, 0, 23, c.w, 5)
	ship(c, "Transport", 8, 6, 4, nation(4))
	icon(c, "people", 38, 2, 1)
end
ITEMS["naval.Destroyer"] = function(c)
	sky(c, { "Night", "Sea", "Sky" }, 22)
	water(c, 0, 23, c.w, 9)
	ship(c, "Destroyer", 8, 6, 4, nation(4))
	burst(c, 42, 8, 3, "Orange", "Gold")
end
ITEMS["naval.land"] = function(c)
	sky(c, { "Sea", "Sky" }, 20)
	water(c, 0, 21, 26, 3)
	rect(c, 26, 21, 22, 11, rgb("Dune"))
	rect(c, 26, 21, 22, 1, rgb("Mist"))
	ship(c, "Transport", 2, 10, 2, nation(4))
	unit(c, "Infantry", 30, 11, 1, nation(4))
	flag(c, 43, 5, nation(4), rgb("White"))
end
ITEMS["air.airfield"] = function(c)
	stage(c, { "Sea", "Sky" }, "Grass")
	building(c, "Airfield", 2, 3, 2, nation(6))
	plane(c, "Fighter", 30, 2, 2, nation(6))
end
ITEMS["air.Fighter"] = function(c)
	sky(c, { "Sea", "Sky" }, c.h)
	rect(c, 2, 24, 12, 3, rgb("White"))
	rect(c, 34, 6, 10, 2, rgb("White"))
	plane(c, "Fighter", 8, 4, 4, nation(6))
end
ITEMS["air.Bomber"] = function(c)
	sky(c, { "Night", "Sea", "Sky" }, c.h)
	rect(c, 36, 24, 10, 2, rgb("White"))
	plane(c, "Bomber", 6, 2, 4, nation(6))
	rect(c, 18, 28, 2, 3, rgb("Ink"))
end
ITEMS["air.raid"] = function(c)
	stage(c, { "Night", "Plum", "Orange" }, "Basalt")
	plane(c, "Bomber", 2, 2, 2, nation(6))
	rect(c, 22, 18, 2, 3, rgb("Ink"))
	building(c, "Factory", 28, 9, 1, rgb("Steel"))
	burst(c, 36, 20, 6, "Orange", "Gold")
end
ITEMS["war.declare"] = function(c)
	stage(c, { "Night", "Plum", "Red" }, "Basalt")
	icon(c, "army", 12, 2, 3)
	burst(c, 6, 8, 3, "Orange", "Gold")
	burst(c, 42, 10, 3, "Orange", "Gold")
end
ITEMS["peace.white"] = function(c)
	stage(c, { "Sea", "Sky" }, "Grass")
	unit(c, "Infantry", 2, 17, 1, nation(2))
	unit(c, "Infantry", 34, 17, 1, nation(9), true)
	rect(c, 23, 2, 2, 25, rgb("Mist"))
	rect(c, 25, 3, 12, 8, rgb("White"))
	rect(c, 25, 10, 12, 1, rgb("Snow"))
end
ITEMS["peace.keep"] = function(c)
	stage(c, { "Sea", "River" }, "Grass")
	rect(c, 4, 20, 40, 7, nation(2))
	rect(c, 4, 20, 40, 1, rgb("White"))
	flag(c, 10, 4, nation(2), rgb("Gold"))
	flag(c, 30, 6, nation(2), rgb("Gold"))
	icon(c, "land", 18, 8, 1)
end
ITEMS["peace.capitulate"] = function(c)
	stage(c, { "Slate", "Steel" }, "Basalt")
	building(c, "Fort", 4, 4, 2, rgb("Steel"))
	rect(c, 34, 2, 2, 25, rgb("Mist"))
	rect(c, 36, 3, 10, 7, rgb("White"))
	rect(c, 36, 9, 10, 1, rgb("Snow"))
end
ITEMS["peace.offer"] = function(c)
	stage(c, { "Teal", "Sky" }, nil)
	icon(c, "diplomacy", 12, 4, 3)
	spark(c, 8, 8, "White")
	spark(c, 40, 22, "White")
end
ITEMS["results.place"] = function(c)
	stage(c, { "Night", "Slate" }, nil)
	podium(c, 6, 12)
	spark(c, 24, 6, "Gold")
end
ITEMS["results.peak"] = function(c)
	stage(c, { "Sea", "River" }, "Grass")
	for k = 0, 4 do
		rect(c, 6 + k * 8, 24 - k * 4, 6, 3 + k * 4, nation(3))
	end
	flag(c, 40, 3, nation(3), rgb("Gold"))
end
ITEMS["results.time"] = function(c)
	stage(c, { "Night", "Violet" }, nil)
	sun(c, 24, 16, 12, "Orange")
	sun(c, 24, 16, 10, "Snow")
	for k = 0, 11 do
		local a = k * math.pi / 6
		local col = rgb(if k % 3 == 0 then "Ink" else "Mist")
		put(c, math.floor(24 + math.cos(a) * 8 + 0.5), math.floor(16 + math.sin(a) * 8 + 0.5), col.r, col.g, col.b)
	end
	rect(c, 23, 9, 2, 8, rgb("Ink"))
	rect(c, 24, 15, 6, 2, rgb("Red"))
	rect(c, 21, 2, 6, 2, rgb("Orange"))
end
ITEMS["results.out"] = function(c)
	stage(c, { "Ink", "Night" }, "Basalt")
	city(c, 2, 12, 6, 1, rgb("Steel"))
	cross(c, 12, 4, 24)
end
ITEMS["results.reward"] = function(c)
	stage(c, { "Plum", "Violet" }, nil)
	crate(c, 2, 8, 2)
	medal(c, 32, 4, "Red", "Gold")
	spark(c, 26, 6, "White")
end
for place, disk in { "Gold", "Mist", "Orange" } do
	ITEMS["results.medal" .. place] = function(c)
		stage(c, { "Night", "Slate" }, nil)
		medal(c, 20, 4, if place == 1 then "Red" elseif place == 2 then "Sea" else "Forest", disk)
	end
end

-- Вспышки захвата и титулы — по цвету / по списку.
local CAPTURE = { "Gold", "Sky", "Red", "Lime", "Violet" }
for _, name in CAPTURE do
	ITEMS["capture." .. name] = function(c)
		stage(c, { "Night", "Slate" }, "Grass")
		burst(c, 24, 14, 9, name, "White")
		burst(c, 24, 14, 4, name, "White")
	end
end
local TITLE_COLORS: { [string]: string } = {
	Strategist = "Sea",
	Diplomat = "Teal",
	Seawolf = "River",
	Veteran = "Forest",
	Conqueror = "Red",
	Legend = "Plum",
}
for id, color in TITLE_COLORS do
	ITEMS["title." .. id] = function(c)
		stage(c, { "Night", "Slate" }, nil)
		ribbon(c, color)
	end
end
for _, id in { "Stripes", "Checker", "Dots", "Grid", "Waves" } do
	ITEMS["pattern." .. id] = function(c)
		stage(c, { "Night", "Slate" }, nil)
		swatch(c, id)
	end
end

-- §15х ч.5: удары в панели «УДАРЫ» и в кольце — ракета, налёт, удары генералов.
local function arc(c: Canvas, x0: number, y0: number, x1: number, y1: number, peak: number, name: string)
	local col = rgb(name)
	for k = 0, 24 do
		if k % 2 == 0 then
			local t = k / 24
			local x = x0 + (x1 - x0) * t
			local y = y0 + (y1 - y0) * t - peak * 4 * t * (1 - t)
			put(c, math.round(x), math.round(y), col.r, col.g, col.b)
		end
	end
end
ITEMS["strike.missile"] = function(c)
	stage(c, { "Ink", "Night", "Plum" }, "Basalt")
	stars(c, 12, 5, 7)
	building(c, "MissileSilo", 2, 13, 1, nation(2))
	arc(c, 8, 16, 38, 23, 16, "Mist")
	rect(c, 27, 4, 4, 2, rgb("White"))
	rect(c, 31, 4, 2, 2, rgb("Red"))
	rect(c, 25, 4, 2, 2, rgb("Orange"))
	burst(c, 39, 22, 5, "Red", "Gold")
end
ITEMS["strike.raid"] = function(c)
	stage(c, { "Night", "Plum", "Orange" }, "Basalt")
	plane(c, "Bomber", 2, 2, 2, nation(6))
	rect(c, 20, 15, 2, 3, rgb("Ink"))
	rect(c, 24, 19, 2, 3, rgb("Ink"))
	building(c, "Factory", 28, 10, 1, rgb("Steel"))
	burst(c, 36, 21, 6, "Orange", "Gold")
end
ITEMS["strike.Airstrike"] = function(c)
	stage(c, { "Night", "Plum", "Orange" }, "Grass")
	plane(c, "Fighter", 4, 2, 2, nation(2))
	unit(c, "Tanks", 24, 16, 1, nation(9))
	burst(c, 30, 18, 5, "Orange", "Gold")
	burst(c, 42, 22, 3, "Gold", "White")
end
ITEMS["strike.Surge"] = function(c)
	stage(c, { "Night", "Slate", "Ochre" }, "Grass")
	unit(c, "Tanks", 2, 15, 1, nation(2))
	unit(c, "Infantry", 18, 16, 1, nation(2))
	for k = 0, 2 do
		rect(c, 34 + k * 4, 12 + k, 3, 1, rgb("Gold"))
		rect(c, 34 + k * 4, 20 - k, 3, 1, rgb("Gold"))
	end
	spark(c, 44, 16, "White")
end
ITEMS["strike.SeaLanding"] = function(c)
	sky(c, { "Sea", "Sky" }, 18)
	water(c, 0, 18, 30, 3)
	rect(c, 30, 18, 18, 14, rgb("Dune"))
	ship(c, "Transport", 2, 10, 2, nation(4))
	unit(c, "Infantry", 32, 12, 1, nation(4))
end
ITEMS["strike.Blockade"] = function(c)
	sky(c, { "Night", "Sea" }, 16)
	water(c, 0, 16, c.w, 5)
	ship(c, "Destroyer", 4, 8, 2, nation(4))
	building(c, "Port", 32, 6, 1, rgb("Steel"))
	burst(c, 38, 12, 3, "Orange", "Gold")
end
ITEMS["strike.Reveal"] = function(c)
	stage(c, { "Ink", "Night" }, "Basalt")
	building(c, "Radar", 4, 7, 2, nation(6))
	for k = 1, 3 do
		arc(c, 22, 18 - k * 3, 44, 18 - k * 3, 2 + k, "Lime")
	end
end
ITEMS["strike.Propaganda"] = function(c)
	stage(c, { "Night", "Plum" }, "Grass")
	flag(c, 8, 4, nation(6), rgb("White"))
	icon(c, "stability", 24, 6, 2)
end
ITEMS["strike.Fortify"] = function(c)
	stage(c, { "Slate", "Steel" }, "Basalt")
	building(c, "Fort", 8, 3, 2, nation(10))
	spark(c, 40, 6, "Gold")
end
ITEMS["strike.Airdrop"] = function(c)
	sky(c, { "Sea", "Sky" }, 26)
	rect(c, 0, 26, c.w, 6, rgb("Grass"))
	plane(c, "Bomber", 2, 2, 2, nation(8))
	for k = 0, 2 do
		local x = 22 + k * 8
		rect(c, x, 10 + k * 3, 6, 2, rgb("White"))
		rect(c, x + 2, 12 + k * 3, 2, 3, rgb("Ink"))
	end
end

ItemArt.Keys = (function(): { string }
	local out: { string } = {}
	for key in ITEMS do
		table.insert(out, key)
	end
	table.sort(out)
	return table.freeze(out)
end)()

function ItemArt.has(key: string): boolean
	return ITEMS[key] ~= nil
end

-- Динамические ключи (§15л ч.10): "building.<вид>" — здание на площадке, "nation.<цвет>" — город державы её цветом.
local function dynamic(c: Canvas, key: string): boolean
	local kind = string.match(key, "^building%.(%a+)$")
	if kind ~= nil then
		local BUILD_COLOR = rgb("River") -- нейтральный цвет зданий в меню стройки
		stage(c, { "Night", "Slate" }, "Grass")
		if kind == "City" then
			PixelCanvas.city(c, 3, 13, 3, 1, BUILD_COLOR, true)
		else
			building(c, kind, 12, 3, 2, BUILD_COLOR)
		end
		return true
	end
	local index = tonumber(string.match(key, "^nation%.(%d+)$"))
	if index ~= nil then
		local col = nation(math.clamp(math.floor(index), 1, 24))
		stage(c, { "Sea", "River", "Sky" }, "Grass")
		PixelCanvas.city(c, 4, 13, 1, 1, col, true)
		flag(c, 38, 6, col, rgb("White"))
		return true
	end
	return false
end

-- Картинка предмета key: RGBA W×H. Неизвестный — тёмная плашка со значком «?».
function ItemArt.paint(key: string): buffer
	local c = PixelCanvas.new(ItemArt.W, ItemArt.H)
	local draw = ITEMS[key]
	if draw ~= nil then
		draw(c)
	elseif not dynamic(c, key) then
		stage(c, { "Night", "Slate" }, nil)
		icon(c, "help", 16, 8, 2)
	end
	return c.buf
end

-- Цвет палитры по имени (для клиента, чтобы не тянуть Palette отдельно).
ItemArt.rgb = function(name: string): Rgb
	return Palette.rgb(name)
end

return table.freeze(ItemArt)
