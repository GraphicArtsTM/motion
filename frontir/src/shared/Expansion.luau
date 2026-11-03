--!strict
--[[
	Expansion — захват клеток вдоль границы (GDD §6.4, §6.6).

	Два вида атаки:
	- на ничью землю — людьми (troops): клетка стоит людей (местность × NeutralCellCost), фронт идёт
	  ~FrontAdvancePerSec клеток в секунду. Если в атаке есть войска, они берут и ничейные города
	  (теряя силу гарнизона города, решает вызывающий через cityAllowed);
	- на державу — фронтом войск (advanceFront): людей не тратит; скорость и право брать города задаёт
	  исход боя на фронте (MatchSim + Forces): множитель mul и allowCities. Защитник теряет людей
	  с каждой клеткой. Реки и вода не захватываются.

	Окружение: если после захвата кусок чужой или ничьей земли со всех сторон окружён атакующим
	(вода и реки тоже считаются стеной), он переходит к атакующему целиком — без «дыр» в территории.
	Не окружаются: кусок со столицей или городом, кусок больше EnclaveMaxCells, кусок у третьей державы.

	Порядок захвата: сначала «щели» — клетки, у которых NotchTouch и больше наших соседей, затем клетки,
	ближайшие к «центру» атаки — точке focus, если игрок нажал на карту, иначе к своей столице (фронт
	идёт кругом). К расстоянию добавляется плавный пространственный шум (граница с «языками») и бонус
	за число наших соседей, плюс крошечный шум тика для разрешения ничьих.
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

-- Людей за захват клетки ничьей земли с местностью terrainCost.
function Expansion.cellCost(terrainCost: number): number
	return Config.Expansion.NeutralCellCost * terrainCost
end

-- Клетки цели, которые касаются границы атакующего, и сколько у каждой наших соседей.
-- Города — только если includeCities.
function Expansion.frontier(
	g: Grid,
	attacker: number,
	target: number,
	includeCities: boolean?
): ({ number }, { [number]: number })
	local list: { number } = {}
	local touching: { [number]: number } = {}
	for i in Grid.borderCells(g, attacker) do
		Grid.forNeighbours(g, i, function(j)
			if
				Grid.getOwner(g, j) == target
				and Grid.isCapturable(g, j)
				and (includeCities or not Grid.isCity(g, j))
			then
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

-- Есть ли у атакующего общая граница с целью (с городами — если includeCities).
function Expansion.hasFrontier(g: Grid, attacker: number, target: number, includeCities: boolean?): boolean
	for i in Grid.borderCells(g, attacker) do
		local found = false
		Grid.forNeighbours(g, i, function(j)
			if
				not found
				and Grid.getOwner(g, j) == target
				and Grid.isCapturable(g, j)
				and (includeCities or not Grid.isCity(g, j))
			then
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

-- Сортирует клетки фронта по приоритету захвата (см. шапку модуля).
local function orderFront(
	g: Grid,
	nations: { Nation },
	attack: Attack,
	front: { number },
	touching: { [number]: number },
	tick: number,
	seed: number
)
	local cfg = Config.Expansion
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
end

-- Сколько клеток фронта брать за dt при множителе скорости mul.
local function budgetFor(frontSize: number, dt: number, mul: number): number
	if mul <= 0 then
		return 0
	end
	local cfg = Config.Expansion
	return math.min(cfg.MaxCellsPerTick, math.max(1, math.ceil(frontSize * cfg.FrontAdvancePerSec * dt * mul)))
end

-- Атака на ничью землю людьми, шаг на dt секунд игрового времени. Возвращает: закончилась ли атака
-- (кончились люди или фронт) и сколько клеток захвачено. cityAllowed(cell) — можно ли взять ничейный
-- город (вызывающий списывает силы гарнизона); nil — города не трогаем.
function Expansion.advance(
	map: MapData,
	g: Grid,
	nations: { Nation },
	attack: Attack,
	tick: number,
	seed: number,
	dt: number,
	cityAllowed: ((cell: number) -> boolean)?
): (boolean, number)
	local cfg = Config.Expansion
	local front, touching = Expansion.frontier(g, attack.attacker, attack.target, cityAllowed ~= nil)
	if #front == 0 then
		return true, 0
	end
	orderFront(g, nations, attack, front, touching, tick, seed)
	local budget = budgetFor(#front, dt, 1)
	local captured = 0
	local taken: { number } = {}
	local finished = false
	for k = 1, math.min(budget, #front) do
		local i = front[k]
		if Grid.getOwner(g, i) == attack.target then
			if Grid.isCity(g, i) and not (cityAllowed :: (number) -> boolean)(i) then
				continue
			end
			local cost = Expansion.cellCost(Config.Terrain[MapData.getTerrain(map, i)].captureCost)
			if attack.troops < cost then
				finished = true
				break
			end
			attack.troops -= cost
			Grid.setOwner(g, i, attack.attacker)
			table.insert(taken, i)
			captured += 1
		end
	end
	captured += Expansion.captureEnclaves(g, nations, attack.attacker, taken, tick)
	return finished or attack.troops < cfg.MinTroops, captured
end

-- Фронт войск против державы: захват клеток с множителем скорости mul (исход боя). Людей не тратит;
-- защитник теряет людей, живших на клетке. Города — только при allowCities. Возвращает число клеток.
function Expansion.advanceFront(
	g: Grid,
	nations: { Nation },
	attack: Attack,
	front: { number },
	touching: { [number]: number },
	mul: number,
	allowCities: boolean,
	tick: number,
	seed: number,
	dt: number
): number
	if #front == 0 or mul <= 0 then
		return 0
	end
	orderFront(g, nations, attack, front, touching, tick, seed)
	local budget = budgetFor(#front, dt, mul)
	local defender = nations[attack.target]
	local captured = 0
	local taken: { number } = {}
	local loss = Config.Expansion.DefenderLossFactor
	for k = 1, #front do
		if captured >= budget then
			break
		end
		local i = front[k]
		if Grid.getOwner(g, i) == attack.target and (allowCities or not Grid.isCity(g, i)) then
			if defender ~= nil then
				local density = defender.people / math.max(1, Grid.cellsOf(g, attack.target))
				defender.people = math.max(0, defender.people - density * loss)
			end
			Grid.setOwner(g, i, attack.attacker)
			table.insert(taken, i)
			captured += 1
		end
	end
	return captured + Expansion.captureEnclaves(g, nations, attack.attacker, taken, tick)
end

return table.freeze(Expansion)
