--!strict
--[[
	CitySprites — город на карте (§15д ч.4): растёт с уровнем. Программный пиксель-арт (пока нет арта), общий для
	клиента (UI/NationLabels) и превью партии (tools/match_preview).

	Размер — Size(level) пикселей (ур. 1 — 11, ур. 5 — 27): крест дорог и кварталы 3×3 через пиксель.
	- ур. 1 «Посёлок» — домики с крышами;
	- ур. 2 «Город» — дома выше, площадь в центре;
	- ур. 3 «Промышленный» — заводы с трубами;
	- ур. 4 «Крупный» — многоэтажки к центру;
	- ур. 5 «Мегаполис» — небоскрёбы со светящимися окнами.
	Тона деталей: body — цвет хозяина, roof — темнее, light — светлее, ink — тёмная, road — дорога, window —
	окна (золото), glass — стекло (голубое). Высокие дома растут вверх за край квартала (рисуются снизу вверх).
]]

export type Tone = "body" | "roof" | "light" | "ink" | "road" | "window" | "glass"
export type Part = { x: number, y: number, w: number, h: number, tone: Tone }

local Palette = require("./Palette")
local UnitSprites = require("./UnitSprites")

local CitySprites = {}

CitySprites.Names = { "Village", "Town", "Industrial", "Large", "Metropolis" }

-- Сторона города в пикселях спрайта.
function CitySprites.size(level: number): number
	return 7 + 4 * math.clamp(level, 1, 5)
end

-- Оттенок тона для цвета хозяина (как UnitSprites.shade): множитель, nil — свой цвет (ink/road/window/glass).
CitySprites.Shade = table.freeze({ body = 1, roof = 0.45, light = 1.5 }) :: { [string]: number }

local cache: { [string]: { Part } } = {}

-- Детали города уровня level (capital — флаг над центром). Порядок — для рисования (дальние сверху вниз).
function CitySprites.parts(level: number, capital: boolean): { Part }
	level = math.clamp(level, 1, 5)
	local key = level .. (if capital then "c" else "")
	local hit = cache[key]
	if hit ~= nil then
		return hit
	end
	local s = CitySprites.size(level)
	local half = s // 2
	local out: { Part } = {}
	local function add(x: number, y: number, w: number, h: number, tone: Tone)
		table.insert(out, { x = x, y = y, w = w, h = h, tone = tone })
	end
	-- Дороги крестом.
	add(0, half, s, 1, "road")
	add(half, 0, 1, s, "road")
	-- Кварталы 3×3 через пиксель (не на дорогах), сверху вниз — нижние перекрывают верхние высокие дома.
	local lots: { { x: number, y: number, d: number } } = {}
	for gy = 0, s - 3, 4 do
		for gx = 0, s - 3, 4 do
			local onRoad = (gx <= half and half <= gx + 2) or (gy <= half and half <= gy + 2)
			if not onRoad then
				local d = math.max(math.abs(gx + 1 - half), math.abs(gy + 1 - half)) / math.max(1, half)
				table.insert(lots, { x = gx, y = gy, d = d })
			end
		end
	end
	for k, lot in lots do
		local x, y, d = lot.x, lot.y, lot.d
		local center = d < 0.55
		if level >= 5 and center then
			-- Небоскрёб: высокий, стекло и окна.
			local h = 6 + math.floor((1 - d) * 8)
			add(x, y + 3 - h, 3, h, "glass")
			add(x + 2, y + 3 - h, 1, h, "light")
			for wy = y + 4 - h, y + 1, 2 do
				add(x + 1, wy, 1, 1, "window")
			end
		elseif level >= 4 and (center or k % 3 == 0) then
			-- Многоэтажка.
			local h = 4 + math.floor((1 - d) * 4)
			add(x, y + 3 - h, 3, h, "light")
			add(x, y + 3 - h, 3, 1, "roof")
			for wy = y + 4 - h, y + 1, 2 do
				add(x + 1, wy, 1, 1, "window")
			end
		elseif level == 3 and k % 3 == 1 then
			-- Завод с трубой.
			add(x, y + 1, 3, 2, "roof")
			add(x + 2, y - 2, 1, 3, "ink")
			add(x, y + 2, 1, 1, "window")
		elseif level >= 2 and center then
			-- Дом в два этажа.
			add(x, y, 3, 3, "light")
			add(x, y, 3, 1, "roof")
			add(x + 1, y + 2, 1, 1, "ink")
		else
			-- Домик с крышей.
			add(x, y + 1, 3, 2, "light")
			add(x, y, 3, 1, "roof")
			add(x + 1, y + 2, 1, 1, "ink")
		end
	end
	if level >= 2 then
		-- Площадь в центре.
		add(half - 1, half - 1, 3, 3, "light")
	end
	if capital then
		-- Флаг столицы над центром.
		add(half, half - 6, 1, 6, "ink")
		add(half + 1, half - 6, 3, 2, "window")
	end
	cache[key] = out
	return out
end

local INK, ROAD, GOLD, SKY = Palette.rgb("Ink"), Palette.rgb("Slate"), Palette.rgb("Gold"), Palette.rgb("Sky")

-- Цвет детали (0..255) для цвета хозяина r, g, b.
function CitySprites.rgb(part: Part, r: number, g: number, b: number): (number, number, number)
	local shade = CitySprites.Shade[part.tone]
	if shade ~= nil then
		return UnitSprites.shade(r, g, b, shade)
	end
	local c = if part.tone == "road"
		then ROAD
		elseif part.tone == "window" then GOLD
		elseif part.tone == "glass" then SKY
		else INK
	return c.r, c.g, c.b
end

return table.freeze(CitySprites)
