--!strict
--[[
	Ranks — путь командира (§15ф, вместо 20 воинских званий §15л): уровень профиля показывает, КАКОЙ ЧАСТЬЮ вы
	командуете — от новобранца до командующего фронтом. 11 ступеней, первая — с уровня Config.Ranks.Tiers[k].
	Только вид (наград за ступень нет): меню, окно «Путь командира», итоги. Названия — Strings «rank.N»,
	«сколько бойцов» — Strings «rank.troops.N».

	Значок 16×16 — знак части с карты: прямоугольник с перекрестьем (пехота), над ним метки размера части —
	точки (отделение, взвод), палочки (рота, батальон, полк), крестики (бригада и выше). Цвет рамки по группе:
	бойцы — голубой, офицеры — золото, генералы — оранжевый, командующие — красный.
]]

local Config = require("./Config")
local PixelIcons = require("./PixelIcons")

type Part = PixelIcons.Part

local Ranks = {}

Ranks.IconSize = 16
Ranks.Count = #Config.Ranks.Tiers

-- Ступень по уровню: последняя, чей первый уровень не больше level.
function Ranks.of(level: number): number
	local lv = math.max(1, math.floor(level))
	local rank = 1
	for k, first in Config.Ranks.Tiers do
		if lv >= first then
			rank = k
		end
	end
	return rank
end

function Ranks.firstLevel(rank: number): number
	return Config.Ranks.Tiers[math.clamp(rank, 1, Ranks.Count)]
end

-- Уровень следующей ступени (nil — уже высшая).
function Ranks.nextAt(level: number): number?
	local rank = Ranks.of(level)
	if rank >= Ranks.Count then
		return nil
	end
	return Ranks.firstLevel(rank + 1)
end

-- Группа ступени: 1 — бойцы, 2 — офицеры, 3 — генералы, 4 — командующие (цвет значка и подписи).
function Ranks.group(rank: number): number
	if rank <= 3 then
		return 1
	elseif rank <= 6 then
		return 2
	elseif rank <= 9 then
		return 3
	end
	return 4
end

Ranks.GroupColors = table.freeze({ "Sky", "Gold", "Orange", "Red" })

local function p(x: number, y: number, w: number, h: number, color: string): Part
	return { x = x, y = y, w = w, h = h, color = color }
end

-- §15щ Щ2: погон ступени — по общему виду (без знаков какой-либо реальной страны). Погон 10×16 по центру клетки
-- 16×16: тёмный силуэт, поле, кант, пуговица сверху. Бойцы — полевой погон и 0 / 2 / 3 лычки; офицеры — один (рота)
-- или два просвета и звёзды (3 малых; 1 / 2 / 3 больших); генералы — золотое поле с плетением и 1–3 большие звезды;
-- командующий фронтом — большая звезда с венком.
type Look = { field: string, kind: "stripes" | "officer" | "general" | "marshal", n: number, lanes: number }
local LOOKS: { Look } = {
	{ field = "Ochre", kind = "stripes", n = 0, lanes = 0 }, -- новобранец
	{ field = "Ochre", kind = "stripes", n = 2, lanes = 0 }, -- командир отделения
	{ field = "Ochre", kind = "stripes", n = 3, lanes = 0 }, -- командир взвода
	{ field = "Ochre", kind = "officer", n = 3, lanes = 1 }, -- рота: просвет и 3 малые звезды
	{ field = "Ochre", kind = "officer", n = 1, lanes = 2 }, -- батальон
	{ field = "Ochre", kind = "officer", n = 2, lanes = 2 }, -- полк
	{ field = "Ochre", kind = "officer", n = 3, lanes = 2 }, -- бригада
	{ field = "Gold", kind = "general", n = 1, lanes = 0 }, -- дивизия
	{ field = "Gold", kind = "general", n = 2, lanes = 0 }, -- корпус
	{ field = "Gold", kind = "general", n = 3, lanes = 0 }, -- армия
	{ field = "Gold", kind = "marshal", n = 1, lanes = 0 }, -- фронт
}

-- Большая звезда 4×3 с верхним рядом y (центр погона — колонки 7–8).
local function bigStar(out: { Part }, y: number, color: string)
	table.insert(out, p(7, y, 2, 1, color))
	table.insert(out, p(6, y + 1, 4, 1, color))
	table.insert(out, p(7, y + 2, 2, 1, color))
end

local function build(rank: number): { Part }
	local out: { Part } = {}
	local look = LOOKS[math.clamp(rank, 1, #LOOKS)]
	-- Силуэт: скруглённый верх, тело погона, тёмная обводка.
	table.insert(out, p(5, 0, 6, 1, "Ink"))
	table.insert(out, p(4, 1, 8, 1, "Ink"))
	table.insert(out, p(3, 2, 10, 14, "Ink"))
	-- Поле и красный кант по краю.
	table.insert(out, p(5, 1, 6, 1, look.field))
	table.insert(out, p(4, 2, 8, 13, "Red"))
	table.insert(out, p(5, 2, 6, 12, look.field))
	-- Плетение генеральского погона: косые стежки.
	if look.kind == "general" or look.kind == "marshal" then
		for y = 3, 13 do
			for x = 5, 10 do
				if (x + y) % 3 == 0 then
					table.insert(out, p(x, y, 1, 1, "Dune"))
				end
			end
		end
	end
	-- Пуговица сверху.
	table.insert(out, p(7, 1, 2, 2, if look.kind == "stripes" then "Mist" else "Gold"))
	if look.kind == "stripes" then
		-- Поперечные лычки снизу вверх.
		for k = 1, look.n do
			table.insert(out, p(5, 14 - 2 * k, 6, 1, "Gold"))
		end
	elseif look.kind == "officer" then
		-- Просветы вдоль погона.
		if look.lanes == 1 then
			table.insert(out, p(7, 4, 2, 10, "Red"))
		else
			table.insert(out, p(6, 4, 1, 10, "Red")) -- на пиксель от канта, чтобы не сливались
			table.insert(out, p(9, 4, 1, 10, "Red"))
		end
		if look.lanes == 1 then
			-- Три малые звезды треугольником.
			table.insert(out, p(5, 10, 2, 2, "Gold"))
			table.insert(out, p(9, 10, 2, 2, "Gold"))
			table.insert(out, p(7, 6, 2, 2, "Gold"))
		else
			for k = 1, look.n do
				bigStar(out, 15 - 4 * k, "Gold")
			end
		end
	elseif look.kind == "general" then
		for k = 1, look.n do
			bigStar(out, 15 - 4 * k, "Red")
		end
	else
		-- Командующий фронтом: большая звезда и венок.
		table.insert(out, p(7, 3, 2, 1, "Red"))
		table.insert(out, p(6, 4, 4, 1, "Red"))
		table.insert(out, p(5, 5, 6, 1, "Red"))
		table.insert(out, p(6, 6, 4, 1, "Red"))
		table.insert(out, p(6, 7, 1, 1, "Red"))
		table.insert(out, p(9, 7, 1, 1, "Red"))
		table.insert(out, p(5, 9, 1, 3, "Forest"))
		table.insert(out, p(10, 9, 1, 3, "Forest"))
		table.insert(out, p(6, 12, 4, 1, "Forest"))
	end
	return out
end

local icons: { { Part } } = {}
for rank = 1, Ranks.Count do
	icons[rank] = table.freeze(build(rank))
end

-- Значок ступени: части 16×16 в именах палитры (PixelIcons.Part).
function Ranks.icon(rank: number): { Part }
	return icons[math.clamp(rank, 1, Ranks.Count)]
end

return table.freeze(Ranks)
