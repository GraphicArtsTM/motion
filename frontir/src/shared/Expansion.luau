--!strict
--[[
	Expansion — расширение границ (GDD §6.4), основной макро-механизм.

	Атака — это отряд людей (troops), которых держава отправила на цель: ничью землю (0) или соседа.
	Каждый тик фронт продвигается: из клеток цели, касающихся границы атакующего, выбирается доля
	FrontAdvancePerSec / TickRate (фронт идёт со скоростью ~FrontAdvancePerSec клеток в секунду)
	и захватывается, пока хватает людей. Стоимость клетки = местность × защита:
	- ничья земля: NeutralCellCost;
	- держава: NationCellCostBase + плотность её людей (людей на клетку) × DensityCostFactor.
	Защитник теряет людей, живших на потерянной клетке. Реки и вода не захватываются.

	Порядок захвата: сначала клетки, ближайшие к «центру» атаки — точке focus, если игрок нажал на карту,
	иначе к своей столице (фронт идёт кругом, а не квадратом). К расстоянию добавляется плавный
	пространственный шум (граница с «языками», а не циркульная) и бонус за число наших соседей
	(заливаются щели в один пиксель), плюс крошечный шум тика для разрешения ничьих.
]]

local Bits = require("./Bits")
local Config = require("./Config")
local Grid = require("./Grid")
local MapData = require("./MapData")
local Noise = require("./Noise")
local Types = require("./Types")

type Grid = Grid.Grid
type MapData = MapData.MapData
type Nation = Types.Nation
type Attack = Types.Attack

local Expansion = {}

-- Людей за захват клетки с местностью terrainCost у защитника (nil — ничья земля).
function Expansion.cellCost(terrainCost: number, defender: Nation?, defenderCells: number): number
	local cfg = Config.Expansion
	if defender == nil then
		return cfg.NeutralCellCost * terrainCost
	end
	local density = defender.people / math.max(1, defenderCells)
	return terrainCost * (cfg.NationCellCostBase + density * cfg.DensityCostFactor)
end

-- Клетки цели, которые касаются границы атакующего, и сколько у каждой наших соседей.
function Expansion.frontier(g: Grid, attacker: number, target: number): ({ number }, { [number]: number })
	local list: { number } = {}
	local touching: { [number]: number } = {}
	for i in Grid.borderCells(g, attacker) do
		Grid.forNeighbours(g, i, function(j)
			if Grid.getOwner(g, j) == target and Grid.isCapturable(g, j) then
				local c = touching[j]
				if c == nil then
					table.insert(list, j)
					touching[j] = 1
				else
					touching[j] = c + 1
				end
			end
		end)
	end
	return list, touching
end

-- Есть ли у атакующего общая граница с целью.
function Expansion.hasFrontier(g: Grid, attacker: number, target: number): boolean
	for i in Grid.borderCells(g, attacker) do
		local found = false
		Grid.forNeighbours(g, i, function(j)
			if not found and Grid.getOwner(g, j) == target and Grid.isCapturable(g, j) then
				found = true
			end
		end)
		if found then
			return true
		end
	end
	return false
end

-- Один тик атаки. Возвращает: закончилась ли атака и сколько клеток захвачено.
-- Остаток людей при окончании возвращает вызывающий (MatchSim), здесь troops только тратятся.
function Expansion.advance(
	map: MapData,
	g: Grid,
	nations: { Nation },
	attack: Attack,
	tick: number,
	seed: number
): (boolean, number)
	local cfg = Config.Expansion
	local front, touching = Expansion.frontier(g, attack.attacker, attack.target)
	if #front == 0 then
		return true, 0
	end

	-- Приоритет клеток фронта: ближе к центру атаки — раньше.
	local priority: { [number]: number } = {}
	local origin = attack.focus
	if origin == nil then
		local attackerNation = nations[attack.attacker]
		origin = if attackerNation ~= nil then attackerNation.capital else nil
	end
	local ox = if origin ~= nil then origin % g.width else 0
	local oy = if origin ~= nil then origin // g.width else 0
	for _, i in front do
		local x, y = i % g.width, i // g.width
		local p = touching[i] * cfg.TouchWeight
			+ Noise.value2(x / cfg.BorderNoiseScale, y / cfg.BorderNoiseScale, seed) * cfg.BorderNoise
			+ Bits.hash2f(i, tick, seed) * cfg.TickJitter
		if origin ~= nil then
			p -= math.sqrt((x - ox) ^ 2 + (y - oy) ^ 2)
		end
		priority[i] = p
	end
	table.sort(front, function(a: number, b: number): boolean
		local pa, pb = priority[a], priority[b]
		if pa ~= pb then
			return pa > pb
		end
		return a < b
	end)

	local share = cfg.FrontAdvancePerSec / Config.Sim.TickRate
	local budget = math.min(cfg.MaxCellsPerTick, math.max(1, math.ceil(#front * share)))
	local defender: Nation? = if attack.target ~= 0 then nations[attack.target] else nil
	local captured = 0
	for k = 1, math.min(budget, #front) do
		local i = front[k]
		if Grid.getOwner(g, i) == attack.target then
			local defenderCells = Grid.cellsOf(g, attack.target)
			local terrainCost = Config.Terrain[MapData.getTerrain(map, i)].captureCost
			local cost = Expansion.cellCost(terrainCost, defender, defenderCells)
			if attack.troops < cost then
				return true, captured
			end
			attack.troops -= cost
			if defender ~= nil then
				local density = defender.people / math.max(1, defenderCells)
				defender.people = math.max(0, defender.people - density * cfg.DefenderLossFactor)
			end
			Grid.setOwner(g, i, attack.attacker)
			captured += 1
		end
	end
	return attack.troops < cfg.MinTroops, captured
end

return table.freeze(Expansion)
