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

-- Метки размера над рамкой (строки 0–4): тип и сколько.
local MARKS: { { kind: string, n: number } } = {
	{ kind = "none", n = 0 }, -- новобранец
	{ kind = "dot", n = 1 }, -- отделение
	{ kind = "dot", n = 3 }, -- взвод
	{ kind = "bar", n = 1 }, -- рота
	{ kind = "bar", n = 2 }, -- батальон
	{ kind = "bar", n = 3 }, -- полк
	{ kind = "cross", n = 1 }, -- бригада
	{ kind = "cross", n = 2 }, -- дивизия
	{ kind = "cross", n = 3 }, -- корпус
	{ kind = "cross", n = 4 }, -- армия
	{ kind = "cross", n = 5 }, -- фронт
}

local function build(rank: number): { Part }
	local out: { Part } = {}
	local edge = Ranks.GroupColors[Ranks.group(rank)]
	-- Рамка части (строки 6–15) с тёмным полем и перекрестьем.
	table.insert(out, p(0, 6, 16, 10, "Ink"))
	table.insert(out, p(0, 6, 16, 1, edge))
	table.insert(out, p(0, 15, 16, 1, edge))
	table.insert(out, p(0, 6, 1, 10, edge))
	table.insert(out, p(15, 6, 1, 10, edge))
	for k = 0, 6 do
		-- Перекрестье: две диагонали внутри рамки (14×8), по 2 клетки в шаге.
		table.insert(out, p(1 + 2 * k, 7 + k, 2, 1, "White"))
		table.insert(out, p(13 - 2 * k, 7 + k, 2, 1, "White"))
	end
	-- Метки размера по центру над рамкой.
	local m = MARKS[math.clamp(rank, 1, #MARKS)]
	if m.kind == "dot" then
		local start = 8 - (3 * m.n - 1) // 2
		for k = 0, m.n - 1 do
			table.insert(out, p(start + 3 * k, 2, 2, 2, edge))
		end
	elseif m.kind == "bar" then
		local start = 8 - (3 * m.n - 1) // 2
		for k = 0, m.n - 1 do
			table.insert(out, p(start + 3 * k, 0, 1, 5, edge))
		end
	elseif m.kind == "cross" then
		local w = 3 * m.n
		local start = 8 - w // 2
		for k = 0, m.n - 1 do
			local x = start + 3 * k
			-- Крестик 3×3 (с пропуском между ними — в соседней клетке следующего).
			table.insert(out, p(x, 1, 1, 1, edge))
			table.insert(out, p(x + 2, 1, 1, 1, edge))
			table.insert(out, p(x + 1, 2, 1, 1, edge))
			table.insert(out, p(x, 3, 1, 1, edge))
			table.insert(out, p(x + 2, 3, 1, 1, edge))
		end
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
