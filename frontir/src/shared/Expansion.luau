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

	Окружение: если после захвата кусок чужой или ничьей земли со всех сторон окружён атакующим
	(вода и реки тоже считаются стеной), он переходит к атакующему целиком — без «дыр» в территории.
	Не окружаются: кусок со столицей или городом, кусок больше EnclaveMaxCells, кусок у третьей державы.
	Города ползущая граница не берёт вовсе — только армии (GDD §6.5).

	Порядок захвата: сначала «щели» — клетки, у которых NotchTouch и больше наших соседей (не остаётся
	одиночных пикселей), затем клетки, ближайшие к «центру» атаки — точке focus, если игрок нажал на карту,
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
			if Grid.getOwner(g, j) == target and Grid.isCapturable(g, j) and not Grid.isCity(g, j) then
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
			if not found and Grid.getOwner(g, j) == target and Grid.isCapturable(g, j) and not Grid.isCity(g, j) then
				found = true
			end
		end)
		if found then
			return true
		end
	end
	return false
end

-- Окружённые куски земли рядом с клетками seeds переходят к attacker. Возвращает число клеток.
-- Чтобы не заливать одни и те же большие области каждый тик, клетки «открытых» кусков помечаются
-- тиком; до EnclaveRecheckTicks тиков заливка, дойдя до такой клетки, сразу останавливается.
function Expansion.captureEnclaves(
	g: Grid,
	nations: { Nation },
	attacker: number,
	seeds: { number },
	tick: number
): number
	local cfg = Config.Expansion
	local function recentlyOpen(i: number): boolean
		local stamp = buffer.readu32(g.openStamp, i * 4)
		return stamp > 0 and tick - stamp < cfg.EnclaveRecheckTicks
	end
	local visited: { [number]: boolean } = {}
	local captured = 0
	for _, s in seeds do
		Grid.forNeighbours(g, s, function(start)
			local owner = Grid.getOwner(g, start)
			if visited[start] or owner == attacker or not Grid.isCapturable(g, start) or recentlyOpen(start) then
				return
			end
			-- Заливка куска владельца owner, пока он окружён только атакующим и «стенами».
			local defender: Nation? = if owner ~= 0 then nations[owner] else nil
			local capital = if defender ~= nil then defender.capital else nil
			local piece: { number } = { start }
			visited[start] = true
			local enclosed = true
			local head = 1
			while head <= #piece and enclosed do
				local i = piece[head]
				head += 1
				if i == capital or Grid.isCity(g, i) or #piece > cfg.EnclaveMaxCells or recentlyOpen(i) then
					enclosed = false
					break
				end
				Grid.forNeighbours(g, i, function(j)
					if not enclosed or not Grid.isCapturable(g, j) then
						return
					end
					local o = Grid.getOwner(g, j)
					if o == owner then
						if not visited[j] then
							visited[j] = true
							table.insert(piece, j)
						end
					elseif o ~= attacker then
						enclosed = false -- кусок касается третьей стороны
					end
				end)
			end
			if not enclosed then
				for _, i in piece do
					buffer.writeu32(g.openStamp, i * 4, tick)
				end
				return
			end
			for _, i in piece do
				if defender ~= nil then
					local cells = Grid.cellsOf(g, owner)
					local density = defender.people / math.max(1, cells)
					defender.people = math.max(0, defender.people - density * cfg.DefenderLossFactor)
				end
				Grid.setOwner(g, i, attacker)
				captured += 1
			end
		end)
	end
	return captured
end

-- Шаг атаки на dt секунд игрового времени. Возвращает: закончилась ли атака и сколько клеток захвачено.
-- Остаток людей при окончании возвращает вызывающий (MatchSim), здесь troops только тратятся.
function Expansion.advance(
	map: MapData,
	g: Grid,
	nations: { Nation },
	attack: Attack,
	tick: number,
	seed: number,
	dt: number
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
		local p = (if touching[i] >= cfg.NotchTouch then cfg.NotchBonus else 0)
			+ touching[i] * cfg.TouchWeight
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

	local budget = math.min(cfg.MaxCellsPerTick, math.max(1, math.ceil(#front * cfg.FrontAdvancePerSec * dt)))
	local defender: Nation? = if attack.target ~= 0 then nations[attack.target] else nil
	local captured = 0
	local taken: { number } = {}
	local finished = false
	for k = 1, math.min(budget, #front) do
		local i = front[k]
		if Grid.getOwner(g, i) == attack.target then
			local defenderCells = Grid.cellsOf(g, attack.target)
			local terrainCost = Config.Terrain[MapData.getTerrain(map, i)].captureCost
			local cost = Expansion.cellCost(terrainCost, defender, defenderCells)
			if attack.troops < cost then
				finished = true
				break
			end
			attack.troops -= cost
			if defender ~= nil then
				local density = defender.people / math.max(1, defenderCells)
				defender.people = math.max(0, defender.people - density * cfg.DefenderLossFactor)
			end
			Grid.setOwner(g, i, attack.attacker)
			table.insert(taken, i)
			captured += 1
		end
	end
	captured += Expansion.captureEnclaves(g, nations, attack.attacker, taken, tick)
	return finished or attack.troops < cfg.MinTroops, captured
end

return table.freeze(Expansion)
