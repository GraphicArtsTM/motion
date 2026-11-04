--!strict
--[[
	Expansion — захват клеток вдоль границы (GDD §6.4, §6.6–6.7а).

	Два вида атаки:
	- на ничью землю — людьми (troops): клетка стоит людей (местность × NeutralCellCost). Если в атаке есть
	  войска, они берут и ничейные города (теряя силу гарнизона города, решает вызывающий через hooks.cityAllowed);
	- на державу — фронтом войск (advanceFront): людей не тратит; скорость и право брать города задаёт
	  исход боя на фронте (MatchSim + Fronts): множитель mul и allowCities. Местность и реки замедляют фронт
	  (стоимость захвата × RiverCrossCost за рекой). Защитник теряет людей с каждой клеткой.
	  Граница людей реку не переходит, фронт — переходит (frontier с map: клетка на том берегу).

	Как идёт граница (selectCells): каждая клетка фронта берётся с вероятностью, которая даёт в среднем
	FrontAdvancePerSec клеток в секунду, — идёт вся граница, а не только сторона клика. Точка focus (главное
	направление удара) ускоряет свою сторону: вес спадает от 1 у точки до FocusMinWeight на дальней стороне.
	Плавный шум даёт «языки», клетки с несколькими нашими соседями идут быстрее, а «щели» (NotchTouch и больше
	наших соседей) и «дыры» (все соседи наши или вода, река, край карты) берутся сразу — дыр не остаётся.

	Окружение: если после захвата кусок чужой или ничьей земли со всех сторон окружён атакующим
	(вода и реки тоже считаются стеной), он переходит к атакующему целиком. Не окружаются: кусок со столицей
	или городом, кусок больше EnclaveMaxCells, кусок у третьей державы, кусок страны, с которой нет войны
	(hooks.canTake).
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

-- Линия фронта: клетки цели у нашей границы, сколько у каждой наших соседей, какие из них за рекой.
export type FrontLine = { list: { number }, touching: { [number]: number }, river: { [number]: boolean } }

-- Необязательные правила захвата (MatchSim подставляет войны и журнал захвата).
export type Hooks = {
	cityAllowed: ((cell: number) -> boolean)?, -- можно ли взять ничейный город (атака людьми с войсками)
	canTake: ((owner: number) -> boolean)?, -- чьи окружённые куски можно забрать (nil — любые)
	record: ((cell: number, oldOwner: number, newOwner: number) -> ())?, -- журнал захвата (для войн)
}

local Expansion = {}

-- Людей за захват клетки ничьей земли с местностью terrainCost.
function Expansion.cellCost(terrainCost: number): number
	return Config.Expansion.NeutralCellCost * terrainCost
end

-- Клетка за рекой: от клетки i через реку в направлении dir (±1 или ±width) — первая не речная клетка
-- не дальше RiverMaxWidth клеток реки, или nil.
local function acrossRiver(g: Grid, map: MapData, i: number, dir: number): number?
	local w = g.width
	local river = Types.Terrain.River
	local cur = i
	for _ = 1, Config.Combat.RiverMaxWidth + 1 do
		local x = cur % w
		if (dir == 1 and x == w - 1) or (dir == -1 and x == 0) then
			return nil
		end
		local nextCell = cur + dir
		if nextCell < 0 or nextCell >= g.size then
			return nil
		end
		cur = nextCell
		if MapData.getTerrain(map, cur) ~= river then
			return if cur ~= i + dir then cur else nil
		end
	end
	return nil
end

-- Клетки цели, которые касаются границы атакующего, сколько у каждой наших соседей и какие из них за рекой.
-- Города — только если includeCities. С map фронт видит и клетки на том берегу реки (§6.7: фронт переходит реку).
function Expansion.frontier(
	g: Grid,
	attacker: number,
	target: number,
	includeCities: boolean?,
	map: MapData?
): ({ number }, { [number]: number }, { [number]: boolean })
	local list: { number } = {}
	local touching: { [number]: number } = {}
	local river: { [number]: boolean } = {}
	local function add(j: number, overRiver: boolean)
		if Grid.getOwner(g, j) == target and Grid.isCapturable(g, j) and (includeCities or not Grid.isCity(g, j)) then
			local c = touching[j]
			if c == nil then
				table.insert(list, j)
				touching[j] = 1
				if overRiver then
					river[j] = true
				end
			else
				touching[j] = c + 1
				if not overRiver then
					river[j] = nil -- клетку можно взять и по суше
				end
			end
		end
	end
	local riverId = Types.Terrain.River
	for i in Grid.borderCells(g, attacker) do
		Grid.forNeighbours(g, i, function(j)
			if map ~= nil and MapData.getTerrain(map, j) == riverId then
				local far = acrossRiver(g, map, i, j - i)
				if far ~= nil then
					add(far, true)
				end
			else
				add(j, false)
			end
		end)
	end
	return list, touching, river
end

-- Есть ли у атакующего общая граница с целью (с городами — если includeCities; с map — и через реку).
function Expansion.hasFrontier(
	g: Grid,
	attacker: number,
	target: number,
	includeCities: boolean?,
	map: MapData?
): boolean
	local riverId = Types.Terrain.River
	local function ok(j: number): boolean
		return Grid.getOwner(g, j) == target and Grid.isCapturable(g, j) and (includeCities or not Grid.isCity(g, j))
	end
	for i in Grid.borderCells(g, attacker) do
		local found = false
		Grid.forNeighbours(g, i, function(j)
			if found then
				return
			end
			if map ~= nil and MapData.getTerrain(map, j) == riverId then
				local far = acrossRiver(g, map, i, j - i)
				found = far ~= nil and ok(far)
			else
				found = ok(j)
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
	tick: number,
	hooks: Hooks?
): number
	local cfg = Config.Expansion
	local canTake = if hooks ~= nil then hooks.canTake else nil
	local record = if hooks ~= nil then hooks.record else nil
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
			if canTake ~= nil and not canTake(owner) then
				return -- кусок страны, с которой нет войны
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
				if record ~= nil then
					record(i, owner, attacker)
				end
				captured += 1
			end
		end)
	end
	return captured
end

-- Вес главного направления удара для клетки фронта: (nx, ny) — куда клетка «смотрит» от нашей земли,
-- (fx, fy) — от клетки к точке focus. Смотрит на точку — 1, вбок и назад — меньше, но не ниже FocusMinWeight.
-- На маленькой территории это ускоряет сторону клика, на длинной прямой линии — участок напротив точки.
function Expansion.focusWeight(nx: number, ny: number, fx: number, fy: number): number
	local cfg = Config.Expansion
	local nl, fl = math.sqrt(nx * nx + ny * ny), math.sqrt(fx * fx + fy * fy)
	if fl < 1e-9 then
		return 1 -- сама точка удара
	end
	local cos = if nl < 1e-9 then 0 else (nx * fx + ny * fy) / (nl * fl)
	return cfg.FocusMinWeight + (1 - cfg.FocusMinWeight) * ((1 + cos) / 2) ^ cfg.FocusSharpness
end

-- Клетка — «дыра»: все 4 соседа наши или стена (вода, река, край карты). Такие берутся сразу.
local function isHole(g: Grid, i: number, attacker: number): boolean
	local w = g.width
	local x = i % w
	local walls = (if x == 0 then 1 else 0)
		+ (if x == w - 1 then 1 else 0)
		+ (if i < w then 1 else 0)
		+ (if i + w >= g.size then 1 else 0)
	local closed = walls
	Grid.forNeighbours(g, i, function(j)
		if Grid.getOwner(g, j) == attacker or not Grid.isCapturable(g, j) then
			closed += 1
		end
	end)
	return closed >= 4
end

local function selectCells(
	g: Grid,
	attacker: number,
	front: { number },
	touching: { [number]: number },
	focus: number?,
	costOf: (cell: number) -> number,
	dt: number,
	mul: number,
	tick: number,
	seed: number
): { number }
	local cfg = Config.Expansion
	if #front == 0 or mul <= 0 then
		return {}
	end
	local w = g.width
	local base: { number } = table.create(#front)
	local fx, fy = if focus ~= nil then focus % w else 0, if focus ~= nil then focus // w else 0
	local sum = 0
	for k, i in front do
		local x, y = i % w, i // w
		local n = Noise.value2(x / cfg.BorderNoiseScale, y / cfg.BorderNoiseScale, seed) * 2 - 1
		local b = (1 + cfg.TouchWeight * (touching[i] - 1)) * math.max(0.2, 1 + cfg.BorderNoise * n)
		if focus ~= nil then
			-- Куда клетка «смотрит»: от наших соседей к ней.
			local nx, ny = 0, 0
			Grid.forNeighbours(g, i, function(j)
				if Grid.getOwner(g, j) == attacker then
					nx += x - j % w
					ny += y - j // w
				end
			end)
			b *= Expansion.focusWeight(nx, ny, fx - x, fy - y)
		end
		base[k] = b
		sum += b
	end
	local scale = cfg.FrontAdvancePerSec * dt * mul * #front / sum
	local picked: { number } = {}
	local prio: { [number]: number } = {}
	for k, i in front do
		local notch = touching[i] >= cfg.NotchTouch or isHole(g, i, attacker)
		local p = if notch then 2 else base[k] * scale / costOf(i)
		if p >= 1 or Bits.hash2f(i, tick, seed) < p then
			table.insert(picked, i)
			prio[i] = p
		end
	end
	table.sort(picked, function(a: number, b: number): boolean
		local pa, pb = prio[a], prio[b]
		if pa ~= pb then
			return pa > pb
		end
		return a < b
	end)
	while #picked > cfg.MaxCellsPerTick do
		table.remove(picked)
	end
	return picked
end

-- Атака на ничью землю людьми, шаг на dt секунд игрового времени. Возвращает: закончилась ли атака
-- (кончились люди или фронт) и сколько клеток захвачено. hooks.cityAllowed(cell) — можно ли взять ничейный
-- город (вызывающий списывает силы гарнизона); без него города не трогаем.
function Expansion.advance(
	map: MapData,
	g: Grid,
	nations: { Nation },
	attack: Attack,
	tick: number,
	seed: number,
	dt: number,
	hooks: Hooks?
): (boolean, number)
	local cfg = Config.Expansion
	local cityAllowed = if hooks ~= nil then hooks.cityAllowed else nil
	local record = if hooks ~= nil then hooks.record else nil
	local front, touching = Expansion.frontier(g, attack.attacker, attack.target, cityAllowed ~= nil)
	if #front == 0 then
		return true, 0
	end
	-- Скорость людей не зависит от местности: местность задаёт цену клетки в людях.
	local picked = selectCells(g, attack.attacker, front, touching, attack.focus, function()
		return 1
	end, dt, 1, tick, seed)
	local captured = 0
	local taken: { number } = {}
	local finished = false
	for _, i in picked do
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
			if record ~= nil then
				record(i, attack.target, attack.attacker)
			end
			table.insert(taken, i)
			captured += 1
		end
	end
	captured += Expansion.captureEnclaves(g, nations, attack.attacker, taken, tick, hooks)
	return finished or attack.troops < cfg.MinTroops, captured
end

-- Фронт войск против державы: захват клеток с множителем скорости mul (исход боя). Людей не тратит;
-- защитник теряет людей, живших на клетке. Местность и река замедляют (цена клетки). Города — только при
-- allowCities. Возвращает число клеток.
function Expansion.advanceFront(
	map: MapData,
	g: Grid,
	nations: { Nation },
	attack: Attack,
	line: FrontLine,
	mul: number,
	allowCities: boolean,
	tick: number,
	seed: number,
	dt: number,
	hooks: Hooks?
): number
	if #line.list == 0 or mul <= 0 then
		return 0
	end
	local record = if hooks ~= nil then hooks.record else nil
	local riverCost = Config.Combat.RiverCrossCost
	local picked = selectCells(g, attack.attacker, line.list, line.touching, attack.focus, function(i: number): number
		local cost = Config.Terrain[MapData.getTerrain(map, i)].captureCost
		return if line.river[i] then cost * riverCost else cost
	end, dt, mul, tick, seed)
	local defender = nations[attack.target]
	local captured = 0
	local taken: { number } = {}
	local loss = Config.Expansion.DefenderLossFactor
	for _, i in picked do
		if Grid.getOwner(g, i) == attack.target and (allowCities or not Grid.isCity(g, i)) then
			if defender ~= nil then
				local density = defender.people / math.max(1, Grid.cellsOf(g, attack.target))
				defender.people = math.max(0, defender.people - density * loss)
			end
			Grid.setOwner(g, i, attack.attacker)
			if record ~= nil then
				record(i, attack.target, attack.attacker)
			end
			table.insert(taken, i)
			captured += 1
		end
	end
	return captured + Expansion.captureEnclaves(g, nations, attack.attacker, taken, tick, hooks)
end

return table.freeze(Expansion)
