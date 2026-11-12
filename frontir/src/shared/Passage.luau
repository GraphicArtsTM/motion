--!strict
--[[
	Passage — удар через союзника с полным доверием (§15у). Чистый модуль: где войска выйдут на землю врага
	(клетка врага у границы союзника, ближайшая к точке удара), откуда идут (наша клетка у границы того же союзника,
	ближайшая к месту выхода) и сколько идут. Одинаково на сервере (MatchSim) и в подсказке клиента (MapTooltip).

	Поиск — расширяющимися квадратами вокруг точки (каждое кольцо смотрится один раз), не дальше
	Alliance.SearchCells (на ширину UnitsReferenceMapWidth): по всей карте не ходим.
]]

local Config = require("./Config")

export type Ctx = {
	width: number,
	height: number,
	ownerAt: (cell: number) -> number,
	capturable: (cell: number) -> boolean,
	isCity: (cell: number) -> boolean,
	-- Наша клетка у границы союзника, ближайшая к exit. Сервер ищет по своей границе (Grid.borderCells — точно и
	-- дёшево); без неё — кольцами вокруг exit до EntrySearchMul × SearchCells (клиент).
	entryNear: ((me: number, ally: number, exit: number) -> number?)?,
	-- Клетка врага у границы союзников, ближайшая к point, — по их границе (сервер: без предела радиуса). Без неё
	-- — кольцами вокруг point до SearchCells (клиент).
	exitNear: ((enemy: number, allies: { [number]: boolean }, point: number) -> (number?, number))?,
}

export type Route = {
	ally: number, -- через чью землю
	exit: number, -- клетка врага, где войска выйдут
	from: number, -- наша клетка у границы союзника, откуда пошли
	cells: number, -- длина пути (по прямой, клеток)
	sec: number, -- время в пути (игровых секунд)
}

local Passage = {}

local function maxRadius(ctx: Ctx, mul: number?): number
	return math.max(8, math.round(Config.Alliance.SearchCells * (mul or 1) * ctx.width / Config.UnitsReferenceMapWidth))
end

-- Касается ли клетка i земли кого-то из owners (4 соседа). Возвращает хозяина соседа или 0.
local function touching(ctx: Ctx, i: number, owners: { [number]: boolean }): number
	local w, h = ctx.width, ctx.height
	local x, y = i % w, i // w
	if x > 0 and owners[ctx.ownerAt(i - 1)] then
		return ctx.ownerAt(i - 1)
	end
	if x < w - 1 and owners[ctx.ownerAt(i + 1)] then
		return ctx.ownerAt(i + 1)
	end
	if y > 0 and owners[ctx.ownerAt(i - w)] then
		return ctx.ownerAt(i - w)
	end
	if y < h - 1 and owners[ctx.ownerAt(i + w)] then
		return ctx.ownerAt(i + w)
	end
	return 0
end

-- Ближайшая к point клетка, для которой test(cell) вернёт не 0 (кольцами, до радиуса limit). Возвращает клетку и
-- то, что вернул test.
local function nearest(ctx: Ctx, point: number, limit: number, test: (cell: number) -> number): (number?, number)
	local w, h = ctx.width, ctx.height
	local px, py = point % w, point // w
	local best: number? = nil
	local bestValue, bestD = 0, math.huge
	for r = 0, limit do
		-- Нашли на прошлом кольце, и это кольцо уже дальше найденного — хватит.
		if best ~= nil and r * r > bestD then
			break
		end
		for dy = -r, r do
			local y = py + dy
			if y >= 0 and y < h then
				local edge = math.abs(dy) == r
				local dx = -r
				while dx <= r do
					local x = px + dx
					if x >= 0 and x < w then
						local d = dx * dx + dy * dy
						if d < bestD then
							local i = y * w + x
							local v = test(i)
							if v ~= 0 then
								best, bestValue, bestD = i, v, d
							end
						end
					end
					-- Внутри кольца — только края (левый и правый), на верхней и нижней строке — все клетки.
					dx += if edge or dx == r then 1 else 2 * r
				end
			end
		end
	end
	return best, bestValue
end

-- Клетка врага у границы союзника из allies, ближайшая к point (без городов). Возвращает клетку и союзника.
function Passage.exitNear(ctx: Ctx, enemy: number, allies: { [number]: boolean }, point: number): (number?, number)
	if ctx.exitNear ~= nil then
		return ctx.exitNear(enemy, allies, point)
	end
	return nearest(ctx, point, maxRadius(ctx), function(i: number): number
		if ctx.ownerAt(i) ~= enemy or not ctx.capturable(i) or ctx.isCity(i) then
			return 0
		end
		return touching(ctx, i, allies)
	end)
end

-- Наша клетка у границы союзника ally, ближайшая к exit (откуда войска войдут на его землю).
function Passage.entryNear(ctx: Ctx, me: number, ally: number, exit: number): number?
	if ctx.entryNear ~= nil then
		return ctx.entryNear(me, ally, exit)
	end
	local only = { [ally] = true }
	local cell = nearest(ctx, exit, maxRadius(ctx, Config.Alliance.EntrySearchMul), function(i: number): number
		if ctx.ownerAt(i) ~= me then
			return 0
		end
		return touching(ctx, i, only)
	end)
	return cell
end

-- Расстояние между клетками по прямой.
function Passage.distance(a: number, b: number, width: number): number
	return math.sqrt((a % width - b % width) ^ 2 + (a // width - b // width) ^ 2)
end

-- Время в пути (игровых секунд) на cells клеток по прямой.
function Passage.travelSec(cells: number, width: number): number
	local cfg = Config.Alliance
	local speed = cfg.PassageCellsPerSec * width / Config.UnitsReferenceMapWidth
	return math.clamp(cells / speed, cfg.PassageMinSec, cfg.PassageMaxSec)
end

-- Путь через союзников allies (с полным доверием) к врагу у точки point: место выхода, откуда и сколько идти.
-- nil — нет союзника с полным доверием между нами и врагом у этой точки.
function Passage.route(ctx: Ctx, me: number, enemy: number, allies: { [number]: boolean }, point: number): Route?
	if next(allies) == nil then
		return nil
	end
	local exit, ally = Passage.exitNear(ctx, enemy, allies, point)
	if exit == nil then
		return nil
	end
	local from = Passage.entryNear(ctx, me, ally, exit)
	if from == nil then
		-- Этот союзник с нами не граничит — пробуем остальных по очереди.
		local rest = table.clone(allies)
		rest[ally] = nil
		return Passage.route(ctx, me, enemy, rest, point)
	end
	local w = ctx.width
	local cells = Passage.distance(exit, from, w)
	return { ally = ally, exit = exit, from = from, cells = cells, sec = Passage.travelSec(cells, w) }
end

return table.freeze(Passage)
