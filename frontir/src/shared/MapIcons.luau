--!strict
--[[
	MapIcons — размеры значков на карте (GDD §15ы), без Roblox API. zoom — пикселей экрана на клетку.
	Все значки — квадраты с центром в своей клетке:
	- здание: сторона растёт с зумом (Render.MapIcons.BuildingCells, от MinPx до MaxPx), но не больше места до
	  соседа (buildingRoom / cityRoom) — так два значка не перекрываются ни на одном зуме со значками;
	- город: жетон по уровню (CityCells, от CityMinPx до CityMaxPx); рядом здания — жетон уступает им место
	  (citySideAmong, не мельче CityShrinkMin), значок здания считает место от настоящего края жетона;
	- корабль: картинка Render.ShipAnim.Cells клеток (от MinPx до MaxPx).
	Прямоугольники (rect) — для тестов и раскладки подписей: x0, y0, x1, y1 в пикселях холста.
]]

local Config = require("./Config")
local Types = require("./Types")

export type Rect = { x0: number, y0: number, x1: number, y1: number }

local MapIcons = {}

local function cfg()
	return Config.Render.MapIcons
end

-- Обычная сторона значка здания на зуме (без соседей).
function MapIcons.buildingBase(zoom: number): number
	local c = cfg()
	return math.clamp(zoom * c.BuildingCells, c.MinPx, c.MaxPx)
end

-- Место (px стороны) для значка здания, если другое здание стоит в (dx, dy) клетках от него: оба значка не больше
-- расстояния по большей оси минус зазор — между центрами хватит места на две половины.
function MapIcons.buildingRoom(zoom: number, dx: number, dy: number): number
	return math.max(math.abs(dx), math.abs(dy)) * zoom - cfg().GapPx
end

-- Сторона жетона города уровня level на зуме (с кантом — + 2 × CityRingPx).
function MapIcons.citySide(level: number, zoom: number): number
	local c = cfg()
	local k = math.clamp(math.floor(level), 1, #c.CityCells)
	return math.round(math.clamp(zoom * c.CityCells[k], c.CityMinPx[k], c.CityMaxPx))
end

-- Сторона жетона города с соседними зданиями (смещения в клетках от города): жетон уступает место, чтобы рядом
-- влез значок здания хотя бы наименьшего размера у города (NearCityMin), но не мельче CityShrinkMin обычного.
function MapIcons.citySideAmong(level: number, zoom: number, buildings: { { dx: number, dy: number } }): number
	local c = cfg()
	local normal = MapIcons.citySide(level, zoom)
	local side = normal
	local floor = math.max(c.MinPx, MapIcons.buildingBase(zoom) * c.NearCityMin)
	for _, b in buildings do
		local d = math.max(math.abs(b.dx), math.abs(b.dy))
		side = math.min(side, 2 * (d * zoom - c.GapPx - floor / 2 - c.CityRingPx))
	end
	return math.floor(math.max(side, normal * c.CityShrinkMin))
end

-- Половина жетона стороны side с кантом (px).
function MapIcons.halfOf(side: number): number
	return side / 2 + cfg().CityRingPx
end

-- §15й Й1: жетон города крупнее его клетки — нажатие по жетону должно попасть в город. dx, dy — от центра клетки
-- города до точки нажатия (клетки), side — сторона жетона (px) на зуме zoom (px на клетку).
function MapIcons.inToken(dx: number, dy: number, side: number, zoom: number): boolean
	local r = MapIcons.halfOf(side) / math.max(zoom, 1e-6)
	return dx * dx + dy * dy <= r * r
end

-- Половина города уровня level без соседей (px, с кантом).
function MapIcons.cityHalf(level: number, zoom: number): number
	return MapIcons.halfOf(MapIcons.citySide(level, zoom))
end

-- Смещения (в клетках) зданий около клетки cell — не дальше radius по большей оси; города (вид "City") не считаются.
function MapIcons.buildingsNear(
	buildings: { [number]: Types.Building },
	cell: number,
	width: number,
	radius: number
): { { dx: number, dy: number } }
	local out = {}
	local x, y = cell % width, cell // width
	for c, b in buildings do
		if b.kind ~= "City" and c ~= cell then
			local dx, dy = c % width - x, c // width - y
			if math.abs(dx) <= radius and math.abs(dy) <= radius then
				table.insert(out, { dx = dx, dy = dy })
			end
		end
	end
	return out
end

-- Место для значка здания, если город (половина жетона half с кантом) стоит в (dx, dy) клетках: значок должен уйти
-- от края города хотя бы по одной оси. Может быть меньше нуля (город перекрывает клетку здания).
function MapIcons.cityRoom(zoom: number, dx: number, dy: number, half: number): number
	local gap = cfg().GapPx
	local d = math.max(math.abs(dx), math.abs(dy))
	return 2 * (d * zoom - half - gap)
end

-- Сторона значка здания: обычная, но не больше места room (у города — не мельче NearCityMin обычной;
-- nearCity = room пришло от города). Не мельче MinPx.
function MapIcons.buildingSide(zoom: number, room: number, nearCity: boolean?): number
	local c = cfg()
	local base = MapIcons.buildingBase(zoom)
	local floor = if nearCity then math.max(c.MinPx, base * c.NearCityMin) else c.MinPx
	return math.floor(math.clamp(room, floor, base))
end

-- Сторона значка здания с соседями: buildings — смещения (dx, dy) других зданий, cities — смещения и половины
-- жетонов городов (halfOf). Возвращает сторону, true — если её урезал город, и влез ли значок (false — даже
-- наименьший налезает на жетон: BuildingLayer рисует вместо него точку).
function MapIcons.sideAmong(
	zoom: number,
	buildings: { { dx: number, dy: number } },
	cities: { { dx: number, dy: number, half: number } }
): (number, boolean, boolean)
	local room, byCity = math.huge, false
	for _, b in buildings do
		room = math.min(room, MapIcons.buildingRoom(zoom, b.dx, b.dy))
	end
	for _, c in cities do
		local r = MapIcons.cityRoom(zoom, c.dx, c.dy, c.half)
		if r < room then
			room, byCity = r, true
		end
	end
	local side = MapIcons.buildingSide(zoom, room, byCity)
	return side, byCity, room >= side
end

-- Квадрат стороны side с центром в клетке (cx, cy).
function MapIcons.rect(cx: number, cy: number, zoom: number, side: number): Rect
	local x, y = (cx + 0.5) * zoom, (cy + 0.5) * zoom
	return { x0 = x - side / 2, y0 = y - side / 2, x1 = x + side / 2, y1 = y + side / 2 }
end

function MapIcons.overlap(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
end

-- Сторона картинки корабля на зуме.
function MapIcons.shipSide(zoom: number): number
	local a = Config.Render.ShipAnim
	return math.round(math.clamp(zoom * a.Cells, a.MinPx, a.MaxPx))
end

return table.freeze(MapIcons)
