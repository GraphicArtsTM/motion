--!strict
--[[
	Ranks — звания по уровню профиля (GDD §15л): 20 званий, каждые Config.Ranks.LevelsPerRank уровней — новое.
	Только вид (наград за звание нет): меню, лобби, итоги. Названия — Strings «rank.N».
	Значок 14×14 рисуется программно (пока нет арта, docs/ART_LIST.md), цвета — имена палитры:
	- 1–6 — рядовые и сержанты: золотые шевроны (1–3), у старших — полосы под ними;
	- 7–14 — погон: прапорщик (серебряные звёзды), младшие офицеры (одна полоса, 1–4 малые звезды),
	  старшие (две полосы, 1–3 большие звезды);
	- 15–18 — генералы: золотой погон, 1–3 большие звезды, у генерала армии — одна крупная;
	- 19–20 — маршалы: большая звезда с лавром.
]]

local Config = require("./Config")
local PixelIcons = require("./PixelIcons")

type Part = PixelIcons.Part

local Ranks = {}

Ranks.IconSize = 14
Ranks.Count = Config.Ranks.Count

-- Звание (1..Count) по уровню профиля.
function Ranks.of(level: number): number
	local per = Config.Ranks.LevelsPerRank
	return math.clamp((math.max(1, math.floor(level)) - 1) // per + 1, 1, Ranks.Count)
end

-- С какого уровня звание.
function Ranks.firstLevel(rank: number): number
	return (math.clamp(rank, 1, Ranks.Count) - 1) * Config.Ranks.LevelsPerRank + 1
end

-- Уровень, на котором будет следующее звание (nil — звание последнее).
function Ranks.nextAt(level: number): number?
	local rank = Ranks.of(level)
	if rank >= Ranks.Count then
		return nil
	end
	return Ranks.firstLevel(rank + 1)
end

local function p(x: number, y: number, w: number, h: number, color: string): Part
	return { x = x, y = y, w = w, h = h, color = color }
end

-- Шеврон «^» шириной 10 и высотой 4 (тень снизу) с верхушкой в строке y.
local function chevron(out: { Part }, y: number)
	table.insert(out, p(6, y + 1, 2, 1, "Orange"))
	table.insert(out, p(4, y + 2, 2, 1, "Orange"))
	table.insert(out, p(8, y + 2, 2, 1, "Orange"))
	table.insert(out, p(2, y + 3, 2, 1, "Orange"))
	table.insert(out, p(10, y + 3, 2, 1, "Orange"))
	table.insert(out, p(6, y, 2, 1, "Gold"))
	table.insert(out, p(4, y + 1, 2, 1, "Gold"))
	table.insert(out, p(8, y + 1, 2, 1, "Gold"))
	table.insert(out, p(2, y + 2, 2, 1, "Gold"))
	table.insert(out, p(10, y + 2, 2, 1, "Gold"))
end

-- Звезда: крест с лучами длины r и заполненной серединой (r = 1 — крестик 3×3); с r ≥ 4 лучи толще,
-- а середина — ромб радиуса ⌈r/2⌉, чтобы звезда не превращалась в ромб.
local function star(out: { Part }, cx: number, cy: number, r: number, color: string)
	table.insert(out, p(cx, cy - r, 1, 2 * r + 1, color))
	table.insert(out, p(cx - r, cy, 2 * r + 1, 1, color))
	local core = r
	if r >= 4 then
		table.insert(out, p(cx - 1, cy - r + 1, 3, 2 * r - 1, color))
		table.insert(out, p(cx - r + 1, cy - 1, 2 * r - 1, 3, color))
		core = math.ceil(r / 2) + 1
	end
	for k = 1, core - 1 do
		table.insert(out, p(cx - k, cy - (core - k), 2 * k + 1, 2 * (core - k) + 1, color))
	end
end

-- Погон 7×14 (x 3..9): основа, кромка, продольные полосы (0, 1 или 2).
local function board(out: { Part }, base: string, edge: string, stripes: number)
	table.insert(out, p(3, 0, 7, 14, base))
	table.insert(out, p(3, 0, 1, 14, edge))
	table.insert(out, p(9, 0, 1, 14, edge))
	if stripes == 1 then
		table.insert(out, p(6, 0, 1, 14, "Red"))
	elseif stripes == 2 then
		table.insert(out, p(4, 0, 1, 14, "Red"))
		table.insert(out, p(8, 0, 1, 14, "Red"))
	end
end

local SMALL_ROWS = { { 7 }, { 4, 10 }, { 3, 7, 11 }, { 2, 5, 8, 11 } }
local BIG_ROWS = { { 7 }, { 4, 10 }, { 2, 7, 11 } }

local function build(rank: number): { Part }
	local out: { Part } = {}
	if rank <= 6 then
		-- Шевроны и полосы, по центру по высоте.
		local chevrons = ({ 1, 2, 3, 2, 3, 2 })[rank]
		local bars = ({ 0, 0, 0, 1, 1, 2 })[rank]
		local height = 3 * chevrons + 1 + (if bars > 0 then 3 * bars else 0)
		local y = (Ranks.IconSize - height) // 2
		for k = 0, chevrons - 1 do
			chevron(out, y + 3 * k)
		end
		local by = y + 3 * chevrons + 1
		for k = 0, bars - 1 do
			table.insert(out, p(2, by + 3 * k + 1, 10, 1, "Orange"))
			table.insert(out, p(2, by + 3 * k, 10, 1, "Gold"))
		end
	elseif rank == 7 then
		board(out, "Steel", "Slate", 0)
		for _, y in SMALL_ROWS[2] do
			star(out, 6, y, 1, "Mist")
		end
	elseif rank <= 11 then
		board(out, "Steel", "Slate", 1)
		for _, y in SMALL_ROWS[rank - 7] do
			star(out, 6, y, 1, "Gold")
		end
	elseif rank <= 14 then
		board(out, "Steel", "Slate", 2)
		for _, y in BIG_ROWS[rank - 11] do
			star(out, 6, y, 2, "Gold")
		end
	elseif rank <= 17 then
		board(out, "Gold", "Orange", 0)
		for _, y in BIG_ROWS[rank - 14] do
			star(out, 6, y, 2, "White")
		end
	elseif rank == 18 then
		board(out, "Gold", "Orange", 0)
		star(out, 6, 7, 3, "White")
	else
		-- Маршал: звезда в обводке, лавр снизу; у Главного маршала — красная середина.
		star(out, 7, 6, 6, "Orange")
		star(out, 7, 6, 5, "Gold")
		if rank == 20 then
			star(out, 7, 6, 2, "Red")
		end
		table.insert(out, p(0, 11, 4, 2, "Grass"))
		table.insert(out, p(10, 11, 4, 2, "Grass"))
		table.insert(out, p(1, 13, 3, 1, "Forest"))
		table.insert(out, p(10, 13, 3, 1, "Forest"))
	end
	return out
end

local icons: { { Part } } = {}
for rank = 1, Ranks.Count do
	icons[rank] = table.freeze(build(rank))
end

-- Значок звания: части 14×14 в именах палитры (PixelIcons.Part).
function Ranks.icon(rank: number): { Part }
	return icons[math.clamp(rank, 1, Ranks.Count)]
end

return table.freeze(Ranks)
