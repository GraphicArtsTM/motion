--!strict
--[[
	StartPositions — выбор точки старта (GDD §6.2).
	Точка годится, если это захватываемая суша, до других стартов не меньше Config.Start.MinDistance,
	и круг старта радиуса Config.Start.Radius хотя бы на MinCircleShare состоит из суши (не мыс, не островок).
	Боты и игроки, не успевшие выбрать, получают точку автоматически: самую далёкую от уже выбранных.
]]

local Config = require("./Config")
local Grid = require("./Grid")
local Rng = require("./Rng")

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

-- Автоматический выбор: из случайных кандидатов — самый далёкий от уже выбранных.
-- Если по правилам места нет, требование дистанции постепенно ослабляется.
function StartPositions.autoPick(g: Grid, others: { number }, rng: Rng): number?
	local cfg = Config.Start
	local minD = cfg.MinDistance
	while minD >= 1 do
		local best: number? = nil
		local bestScore = -1
		for _ = 1, cfg.AutoPickTries do
			local cell = Rng.range(rng, 0, g.size - 1)
			if StartPositions.check(g, cell, others, minD) then
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
