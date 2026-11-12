--!strict
--[[
	Armies — сухопутные армии (GDD §6.5, §6.6, §7), этап 3а: найм, движение, захват провинций.

	- Армия нанимается в столице (Config.Units.*.recruitSec игровых секунд), стоит людей.
	- Движение: по пути из Pathfind, скорость = Units.speed × (ширина карты / эталонные 512) × местность.
	- Захват: армия, стоящая в провинции, где есть не её клетки, заливает их «волной» от себя
	  (поиск в ширину по клеткам провинции), Units.captureRate клеток в секунду. Чужой город в провинции
	  замедляет захват (Config.Armies.CityCaptureSlowdown). Города берут только армии.
	- Приказ «авто»: армия сама выбирает соседнюю непокорённую провинцию — города, ничья земля,
	  слабые соседи, ближе (Config.Armies.Auto*).
	Бой, ветераны и снабжение — этап 3б.
]]

local Config = require("./Config")
local Grid = require("./Grid")
local MapData = require("./MapData")
local Pathfind = require("./Pathfind")
local Provinces = require("./Provinces")
local Types = require("./Types")

type Grid = Grid.Grid
type MapData = MapData.MapData
type Army = Types.Army
type Nation = Types.Nation

-- Всё, что нужно армиям от матча.
export type Context = {
	map: MapData,
	grid: Grid,
	provinces: Provinces.ProvinceSet,
	nations: { Nation },
	cityOf: { [number]: number }, -- провинция → клетка города
	onCapitalLost: (nation: number, by: number) -> (),
}

local Armies = {}

function Armies.stats(kind: Types.LandUnit): Types.UnitStats
	local u = Config.Units
	if kind == "Tanks" then
		return u.Tanks
	elseif kind == "Artillery" then
		return u.Artillery
	end
	return u.Infantry
end

function Armies.isLandUnit(kind: string): boolean
	return table.find(Types.LandUnits, kind) ~= nil
end

-- Скорость армии на карте этой ширины, клеток в секунду (без учёта местности).
function Armies.baseSpeed(map: MapData, kind: Types.LandUnit): number
	return Armies.stats(kind).speed * map.width / Config.UnitsReferenceMapWidth
end

function Armies.new(id: number, owner: number, kind: Types.LandUnit, cell: number, mapWidth: number): Army
	local s = Armies.stats(kind)
	local cx, cy = cell % mapWidth, cell // mapWidth -- отдельно: StyLua 2.6 падает на «//» в конструкторе
	return {
		id = id,
		owner = owner,
		kind = kind,
		x = cx + 0.5,
		y = cy + 0.5,
		cell = cell,
		strength = s.strength,
		maxStrength = s.strength,
		stars = 0,
		state = "recruit",
		recruitLeft = s.recruitSec,
		path = {},
		pathIndex = 1,
		auto = false,
		captureProvince = 0,
		captureQueue = {},
		captureIndex = 1,
		captureTotal = 0,
		captureDone = 0,
		captureAcc = 0,
		recheckLeft = 0,
	}
end

local function stopCapture(a: Army)
	a.captureProvince = 0
	a.captureQueue = {}
	a.captureIndex = 1
	a.captureTotal = 0
	a.captureDone = 0
	a.captureAcc = 0
end

-- Отправляет армию по пути (захват прерывается).
function Armies.setPath(a: Army, path: { number })
	stopCapture(a)
	a.path = path
	a.pathIndex = 1
	a.state = if #path > 0 then "move" else "idle"
	a.recheckLeft = 0
end

function Armies.stop(a: Army)
	a.path = {}
	a.pathIndex = 1
	if a.state == "move" then
		a.state = "idle"
	end
	a.recheckLeft = 0
end

-- Доля захвата провинции 0..1 (для кольца прогресса).
function Armies.captureProgress(a: Army): number
	if a.state ~= "capture" or a.captureTotal == 0 then
		return 0
	end
	return math.clamp(a.captureDone / a.captureTotal, 0, 1)
end

-- Клетки провинции, которые армии ещё предстоит взять, в порядке «волны» от армии
-- (вся провинция связна, поэтому поиском в ширину находятся все её клетки).
local function captureQueue(ctx: Context, a: Army, province: number): { number }
	local map, g = ctx.map, ctx.grid
	local w = map.width
	local queue: { number } = {}
	local seen: { [number]: boolean } = { [a.cell] = true }
	local frontier = { a.cell }
	local head = 1
	while head <= #frontier do
		local i = frontier[head]
		head += 1
		if Grid.isCapturable(g, i) and Grid.getOwner(g, i) ~= a.owner then
			table.insert(queue, i)
		end
		local x = i % w
		local function visit(j: number)
			if not seen[j] and MapData.getProvince(map, j) == province then
				seen[j] = true
				table.insert(frontier, j)
			end
		end
		if x > 0 then
			visit(i - 1)
		end
		if x < w - 1 then
			visit(i + 1)
		end
		if i >= w then
			visit(i - w)
		end
		if i + w < map.width * map.height then
			visit(i + w)
		end
	end
	-- Волна круглая: по обычному расстоянию до армии (обход в ширину дал бы ромб).
	local ax, ay = a.x, a.y
	local dist: { [number]: number } = {}
	for _, i in queue do
		dist[i] = (i % w + 0.5 - ax) ^ 2 + (i // w + 0.5 - ay) ^ 2
	end
	table.sort(queue, function(p: number, q: number): boolean
		if dist[p] ~= dist[q] then
			return dist[p] < dist[q]
		end
		return p < q
	end)
	return queue
end

-- Начинает захват провинции, в которой стоит армия, если там есть что брать.
local function tryStartCapture(ctx: Context, a: Army): boolean
	local province = MapData.getProvince(ctx.map, a.cell)
	if province == 0 then
		return false
	end
	local queue = captureQueue(ctx, a, province)
	if #queue == 0 then
		stopCapture(a)
		return false
	end
	a.captureProvince = province
	a.captureQueue = queue
	a.captureIndex = 1
	a.captureTotal = #queue
	a.captureDone = 0
	a.captureAcc = 0
	a.state = "capture"
	return true
end

-- Сколько клеток провинции ещё не принадлежит державе owner.
local function missingCells(ctx: Context, province: Provinces.Province, owner: number): number
	local missing = 0
	for _, i in province.cells do
		if Grid.isCapturable(ctx.grid, i) and Grid.getOwner(ctx.grid, i) ~= owner then
			missing += 1
		end
	end
	return missing
end

-- Цели для «авто»: соседние непокорённые провинции по убыванию привлекательности
-- (если таких нет — ближайшие непокорённые по графу провинций).
function Armies.autoTargets(ctx: Context, a: Army): { number }
	local set = ctx.provinces
	local here = MapData.getProvince(ctx.map, a.cell)
	if here == 0 then
		return {}
	end
	local owner = ctx.nations[a.owner]
	local cfg = Config.Armies
	local w = ctx.map.width
	local scored: { { province: number, score: number } } = {}
	local function consider(id: number)
		local p = set.list[id]
		if missingCells(ctx, p, a.owner) == 0 then
			return
		end
		local score = 0
		local city = ctx.cityOf[id]
		if city ~= nil and Grid.getOwner(ctx.grid, city) ~= a.owner then
			score += cfg.AutoCityWeight
		end
		local holder = Grid.getOwner(ctx.grid, p.center)
		if holder == 0 then
			score += cfg.AutoNeutralWeight
		else
			local other = ctx.nations[holder]
			if other ~= nil and owner ~= nil and holder ~= a.owner and other.people < owner.people then
				score += cfg.AutoWeakWeight
			end
		end
		local d = math.sqrt((p.center % w + 0.5 - a.x) ^ 2 + (p.center // w + 0.5 - a.y) ^ 2)
		score -= d * cfg.AutoDistancePenalty
		table.insert(scored, { province = id, score = score })
	end
	for _, id in set.list[here].neighbours do
		consider(id)
	end
	if #scored == 0 then
		-- Соседи все наши: ищем ближайшие непокорённые провинции по графу.
		local seen: { [number]: boolean } = { [here] = true }
		local layer = { here }
		while #scored == 0 and #layer > 0 do
			local nextLayer: { number } = {}
			for _, id in layer do
				for _, n in set.list[id].neighbours do
					if not seen[n] then
						seen[n] = true
						table.insert(nextLayer, n)
						consider(n)
					end
				end
			end
			layer = nextLayer
		end
	end
	table.sort(scored, function(x, y)
		if x.score ~= y.score then
			return x.score > y.score
		end
		return x.province < y.province
	end)
	local out: { number } = {}
	for _, s in scored do
		table.insert(out, s.province)
	end
	return out
end

-- Захват клеток из очереди: возвращает число захваченных.
local function advanceCapture(ctx: Context, a: Army, dt: number): number
	local s = Armies.stats(a.kind)
	local rate = s.captureRate
	local city = ctx.cityOf[a.captureProvince]
	if city ~= nil and Grid.getOwner(ctx.grid, city) ~= a.owner then
		rate *= Config.Armies.CityCaptureSlowdown
	end
	a.captureAcc += rate * dt
	local captured = 0
	local g = ctx.grid
	while a.captureAcc >= 1 and a.captureIndex <= #a.captureQueue do
		local i = a.captureQueue[a.captureIndex]
		a.captureIndex += 1
		local prev = Grid.getOwner(g, i)
		if prev ~= a.owner then
			a.captureAcc -= 1
			local defender = if prev ~= 0 then ctx.nations[prev] else nil
			if defender ~= nil then
				local density = defender.people / math.max(1, Grid.cellsOf(g, prev))
				defender.people = math.max(0, defender.people - density * Config.Expansion.DefenderLossFactor)
			end
			Grid.setOwner(g, i, a.owner)
			captured += 1
			if defender ~= nil and defender.capital == i then
				ctx.onCapitalLost(prev, a.owner)
			end
		end
		a.captureDone += 1
	end
	if a.captureIndex > #a.captureQueue then
		stopCapture(a)
		a.state = "idle"
		a.recheckLeft = 0
	end
	return captured
end

local function advanceMove(ctx: Context, a: Army, dt: number)
	local map = ctx.map
	local w = map.width
	local base = Armies.baseSpeed(map, a.kind)
	local remaining = dt
	while remaining > 0 and a.pathIndex <= #a.path do
		local nextCell = a.path[a.pathIndex]
		local nx, ny = nextCell % w + 0.5, nextCell // w + 0.5
		local dist = math.sqrt((nx - a.x) ^ 2 + (ny - a.y) ^ 2)
		local speed = base * math.max(0.05, Config.Terrain[MapData.getTerrain(map, nextCell)].armySpeed)
		local need = dist / speed
		if need <= remaining then
			a.x, a.y = nx, ny
			a.cell = nextCell
			a.pathIndex += 1
			remaining -= need
		else
			local f = remaining / need
			a.x += (nx - a.x) * f
			a.y += (ny - a.y) * f
			remaining = 0
		end
	end
	if a.pathIndex > #a.path then
		a.path = {}
		a.pathIndex = 1
		a.state = "idle"
		a.recheckLeft = 0
	end
end

-- Шаг армии на dt игровых секунд. Возвращает число захваченных клеток.
function Armies.step(ctx: Context, a: Army, dt: number): number
	if a.state == "recruit" then
		a.recruitLeft -= dt
		if a.recruitLeft <= 0 then
			a.recruitLeft = 0
			a.state = "idle"
			a.recheckLeft = 0
		end
		return 0
	elseif a.state == "move" then
		advanceMove(ctx, a, dt)
		return 0
	elseif a.state == "capture" then
		if MapData.getProvince(ctx.map, a.cell) ~= a.captureProvince then
			stopCapture(a)
			a.state = "idle"
			return 0
		end
		return advanceCapture(ctx, a, dt)
	end
	-- idle: время от времени проверяем, есть ли что захватывать, и в режиме «авто» ищем цель.
	a.recheckLeft -= dt
	if a.recheckLeft > 0 then
		return 0
	end
	a.recheckLeft = Config.Armies.IdleRecheckSec
	if tryStartCapture(ctx, a) then
		return advanceCapture(ctx, a, dt)
	end
	if a.auto then
		for k, id in Armies.autoTargets(ctx, a) do
			if k > 3 then
				break
			end
			local path = Pathfind.find(ctx.map, a.cell, ctx.provinces.list[id].center)
			if path ~= nil and #path > 0 then
				Armies.setPath(a, path)
				break
			end
		end
	end
	return 0
end

return table.freeze(Armies)
