--!strict
--[[
	StartPositions — выбор точки старта (GDD §6.2).
	Точка годится, если это захватываемая суша, до других стартов не меньше Config.Start.MinDistance,
	и круг старта радиуса Config.Start.Radius хотя бы на MinCircleShare состоит из суши (не мыс, не островок).
	Боты и игроки, не успевшие выбрать, получают точку автоматически: самую далёкую от уже выбранных — на крупном
	массиве суши (не меньше Start.MinLandmassShare всей суши), если такое место есть: на острове расти некуда.
]]

local Config = require("./Config")
local Grid = require("./Grid")
local MapData = require("./MapData")
local Rng = require("./Rng")
local Types = require("./Types")

type Grid = Grid.Grid
type Rng = Rng.Rng

export type PickError = "OutOfMap" | "NotLand" | "TooClose" | "TooSmall"

local StartPositions = {}

local function dist2(g: Grid, a: number, b: number): number
	local dx = a % g.width - b % g.width
	local dy = a // g.width - b // g.width
	return dx * dx + dy * dy
end

-- Клетки круга старта: захватываемая суша в радиусе, связанная с центром (не через воду).
function StartPositions.circle(g: Grid, center: number, radius: number): { number }
	local out: { number } = {}
	if not Grid.isCapturable(g, center) then
		return out
	end
	local r2 = radius * radius
	local seen: { [number]: boolean } = { [center] = true }
	local queue = { center }
	local head = 1
	while head <= #queue do
		local i = queue[head]
		head += 1
		table.insert(out, i)
		Grid.forNeighbours(g, i, function(j)
			if not seen[j] and Grid.isCapturable(g, j) and dist2(g, center, j) <= r2 then
				seen[j] = true
				table.insert(queue, j)
			end
		end)
	end
	return out
end

-- Сколько клеток в идеальном круге этого радиуса (для проверки «не мыс»).
local function discSize(radius: number): number
	local n = 0
	for dy = -radius, radius do
		for dx = -radius, radius do
			if dx * dx + dy * dy <= radius * radius then
				n += 1
			end
		end
	end
	return n
end

-- Можно ли стартовать в клетке cell, если другие уже выбрали others.
function StartPositions.check(g: Grid, cell: number, others: { number }, minDistance: number?): (boolean, PickError?)
	if cell ~= math.floor(cell) or cell < 0 or cell >= g.size then
		return false, "OutOfMap"
	end
	if not Grid.isCapturable(g, cell) or Grid.getOwner(g, cell) ~= 0 then
		return false, "NotLand"
	end
	local minD = minDistance or Config.Start.MinDistance
	for _, other in others do
		if dist2(g, cell, other) < minD * minD then
			return false, "TooClose"
		end
	end
	local cfg = Config.Start
	if #StartPositions.circle(g, cell, cfg.Radius) < discSize(cfg.Radius) * cfg.MinCircleShare then
		return false, "TooSmall"
	end
	return true, nil
end

-- Размер массива суши каждой клетки (u32 на клетку, 0 — не суша): связность по 4 соседям, реки — часть суши
-- (фронт их переходит). Считается один раз на матч.
function StartPositions.landmasses(map: MapData.MapData, g: Grid): buffer
	local sizes = buffer.create(g.size * 4)
	local river = Types.Terrain.River
	local function land(i: number): boolean
		return Grid.isCapturable(g, i) or MapData.getTerrain(map, i) == river
	end
	local queue: { number } = {}
	for start = 0, g.size - 1 do
		if buffer.readu32(sizes, start * 4) == 0 and land(start) then
			table.clear(queue)
			queue[1] = start
			buffer.writeu32(sizes, start * 4, 1) -- метка «в очереди»; размер допишем после заливки
			local head = 1
			while head <= #queue do
				local i = queue[head]
				head += 1
				Grid.forNeighbours(g, i, function(j)
					if buffer.readu32(sizes, j * 4) == 0 and land(j) then
						buffer.writeu32(sizes, j * 4, 1)
						table.insert(queue, j)
					end
				end)
			end
			-- Считаем только захватываемые клетки массива (реки не дают земли).
			local count = 0
			for _, i in queue do
				if Grid.isCapturable(g, i) then
					count += 1
				end
			end
			for _, i in queue do
				buffer.writeu32(sizes, i * 4, math.max(1, count))
			end
		end
	end
	return sizes
end

-- Автоматический выбор: из случайных кандидатов — самый далёкий от уже выбранных.
-- Если по правилам места нет, требование дистанции постепенно ослабляется.
function StartPositions.autoPick(g: Grid, others: { number }, rng: Rng, landmass: buffer?): number?
	local cfg = Config.Start
	-- Сначала — только крупные массивы суши (если знаем размеры), потом — где угодно.
	local minLand = if landmass ~= nil then g.capturableCount * cfg.MinLandmassShare else 0
	local pick = StartPositions.pickFar(g, others, rng, landmass, minLand)
	if pick == nil and minLand > 0 then
		pick = StartPositions.pickFar(g, others, rng, landmass, 0)
	end
	return pick
end

-- Самая далёкая от others годная клетка на массиве суши не меньше minLand клеток.
function StartPositions.pickFar(g: Grid, others: { number }, rng: Rng, landmass: buffer?, minLand: number): number?
	local cfg = Config.Start
	local minD = cfg.MinDistance
	while minD >= 1 do
		local best: number? = nil
		local bestScore = -1
		for _ = 1, cfg.AutoPickTries do
			local cell = Rng.range(rng, 0, g.size - 1)
			local bigEnough = landmass == nil or buffer.readu32(landmass, cell * 4) >= minLand
			if bigEnough and StartPositions.check(g, cell, others, minD) then
				local score = math.huge
				for _, other in others do
					score = math.min(score, dist2(g, cell, other))
				end
				if score > bestScore then
					best, bestScore = cell, score
				end
			end
		end
		if best ~= nil then
			return best
		end
		minD = math.floor(minD / 2)
	end
	return nil
end

return table.freeze(StartPositions)
