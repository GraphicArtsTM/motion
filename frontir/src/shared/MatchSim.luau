--!strict
--[[
	MatchSim — симуляция матча без Roblox API. Сервер (MatchService) только кормит её игроками,
	намерениями и временем, а результаты рассылает. Тесты гоняют её в Lune.

	Фазы:
	- Waiting — ждём первого игрока;
	- Pick — Config.Match.StartPickSec секунд игроки выбирают точку старта (GDD §6.2);
	- Play — люди растут, атаки и фронты двигают границы, боты думают.
	Лобби, победа и возврат в лобби — этап 4.

	В конце выбора: кто не выбрал — получает точку автоматически, свободные места до
	Config.Match.TargetNations (или m.targetNations) занимают боты, цвета раздаются по точкам старта
	(NationColors.assign), столица становится городом, вокруг неё — круг клеток.

	Война (GDD §6.5–6.7, модель «Фронты»):
	- войска — пул державы по типам (Forces): найм по очереди за людей, дома — гарнизон;
	- атака на ничью землю — людьми (+ войска, если отправлены, берут ничейные города);
	- атака на державу — фронт: доля войск уходит на границу, бой (Fronts) решает, идёт ли фронт
	  и берёт ли он города; потери, опыт, снабжение;
	- держава выбывает, когда пал её последний город: её клетки становятся ничьими.
]]

local BotBrain = require("./BotBrain")
local Config = require("./Config")
local Economy = require("./Economy")
local Expansion = require("./Expansion")
local Forces = require("./Forces")
local Fronts = require("./Fronts")
local Grid = require("./Grid")
local MapData = require("./MapData")
local NameGen = require("./NameGen")
local NationColors = require("./NationColors")
local Provinces = require("./Provinces")
local Rng = require("./Rng")
local StartPositions = require("./StartPositions")
local Types = require("./Types")

type Grid = Grid.Grid
type MapData = MapData.MapData
type Rng = Rng.Rng
type Nation = Types.Nation
type Attack = Types.Attack

export type MatchEvent =
	{ kind: "eliminated", nation: number, by: number }
	| { kind: "capitalLost", nation: number, by: number }

export type Match = {
	map: MapData,
	grid: Grid,
	rng: Rng,
	seed: number,
	phase: Types.Phase,
	phaseLeft: number, -- секунд до конца фазы выбора
	time: number, -- секунд реального времени с начала фазы Play (часы матча)
	speed: number, -- множитель скорости игрового времени (Config.Match.Speed, «Блиц» — 2)
	simTime: number, -- игровое время: time × speed
	tick: number,
	targetNations: number, -- сколько держав в матче (игроки + боты)
	nations: { Nation },
	attacks: { Attack },
	botNextThink: { [number]: number },
	infoDirty: boolean, -- изменились державы или фаза — разослать клиентам
	events: { MatchEvent },
	lastCaptured: number, -- клеток захвачено за последний тик
	provinces: Provinces.ProvinceSet,
	cityOf: { [number]: number }, -- провинция → клетка города (нейтрального, державы или столицы)
}

local MatchSim = {}

function MatchSim.new(map: MapData, seed: number): Match
	local grid = Grid.new(map)
	local provinces = Provinces.build(map)
	local cityOf: { [number]: number } = {}
	for _, p in provinces.list do
		local city = p.city
		if city ~= nil then
			cityOf[p.id] = city
			Grid.setCity(grid, city, true)
		end
	end
	return {
		map = map,
		grid = grid,
		rng = Rng.new(seed),
		seed = seed,
		phase = "Waiting",
		phaseLeft = 0,
		time = 0,
		speed = Config.Match.Speed,
		simTime = 0,
		tick = 0,
		targetNations = Config.Match.TargetNations,
		nations = {},
		attacks = {},
		botNextThink = {},
		infoDirty = true,
		events = {},
		lastCaptured = 0,
		provinces = provinces,
		cityOf = cityOf,
	}
end

-- Все города на карте (клетки) — для клиентов.
function MatchSim.cities(m: Match): { number }
	local out: { number } = {}
	for _, cell in m.cityOf do
		table.insert(out, cell)
	end
	table.sort(out)
	return out
end

-- Ближайший к from город державы или nil.
local function nearestOwnedCity(m: Match, nationId: number, from: number): number?
	local w = m.grid.width
	local best: number? = nil
	local bestD = math.huge
	for _, cell in m.cityOf do
		if Grid.getOwner(m.grid, cell) == nationId then
			local d = (cell % w - from % w) ^ 2 + (cell // w - from // w) ^ 2
			if d < bestD or (d == bestD and best ~= nil and cell < best) then
				best, bestD = cell, d
			end
		end
	end
	return best
end

-- Сколько городов у державы.
function MatchSim.citiesOf(m: Match, nationId: number): number
	local count = 0
	for _, cell in m.cityOf do
		if Grid.getOwner(m.grid, cell) == nationId then
			count += 1
		end
	end
	return count
end

-- Столица взята: переезжает в ближайший свой город (если он есть).
function MatchSim.capitalLost(m: Match, nationId: number, by: number)
	local n = m.nations[nationId]
	if n == nil or n.capital == nil then
		return
	end
	n.capital = nearestOwnedCity(m, nationId, n.capital)
	table.insert(m.events, { kind = "capitalLost", nation = nationId, by = by })
	m.infoDirty = true
end

local function newNation(m: Match, name: string, nameEn: string, isBot: boolean, userId: number?): Nation
	local nation: Nation = {
		id = #m.nations + 1,
		name = name,
		nameEn = nameEn,
		isBot = isBot,
		userId = userId,
		colorIndex = 0,
		capital = nil,
		people = 0,
		alive = true,
		home = Forces.new(),
		queue = {},
	}
	table.insert(m.nations, nation)
	m.infoDirty = true
	return nation
end

-- Добавляет игрока (только до начала игры). Возвращает id державы или nil, если мест нет / игра идёт.
function MatchSim.addPlayer(m: Match, userId: number, name: string): number?
	if m.phase == "Play" or #m.nations >= Config.Match.MaxPlayers then
		return nil
	end
	return newNation(m, name, name, false, userId).id
end

-- Игрок ушёл: его держава остаётся на карте и переходит под управление бота.
function MatchSim.removePlayer(m: Match, nationId: number)
	local n = m.nations[nationId]
	if n == nil then
		return
	end
	n.isBot = true
	n.userId = nil
	m.botNextThink[nationId] = m.simTime + BotBrain.nextThinkDelay(m.rng)
	m.infoDirty = true
end

function MatchSim.startPick(m: Match)
	if m.phase ~= "Waiting" then
		return
	end
	m.phase = "Pick"
	m.phaseLeft = Config.Match.StartPickSec
	m.infoDirty = true
end

local function capitals(m: Match, except: number?): { number }
	local out: { number } = {}
	for _, n in m.nations do
		if n.capital ~= nil and n.id ~= except then
			table.insert(out, n.capital)
		end
	end
	return out
end

-- Конец выбора старта: автостарты, боты, цвета, столицы-города, круги клеток, люди.
function MatchSim.finishPick(m: Match)
	if m.phase == "Play" then
		return
	end
	local taken: { [string]: boolean } = {}
	for _, n in m.nations do
		taken[n.name] = true
	end
	while #m.nations < m.targetNations and #m.nations < Config.Match.MaxPlayers do
		local name = NameGen.generate(m.rng, taken)
		taken[name.ru] = true
		newNation(m, name.ru, name.en, true, nil)
	end
	for _, n in m.nations do
		if n.capital == nil then
			n.capital = StartPositions.autoPick(m.grid, capitals(m), m.rng)
		end
	end

	local starts: { NationColors.StartPoint } = {}
	local order: { Nation } = {}
	for _, n in m.nations do
		local cap = n.capital
		if cap ~= nil then
			-- Координаты считаем отдельно: StyLua 2.6 падает на «//» внутри длинного конструктора таблицы.
			local x, y = cap % m.grid.width, cap // m.grid.width
			table.insert(starts, { x = x, y = y })
			table.insert(order, n)
		else
			n.alive = false -- места на карте не нашлось (крошечная карта)
		end
	end
	local colors = NationColors.assign(starts)
	for k, n in order do
		n.colorIndex = colors[k]
		-- Столица — город. В провинции один город: нейтральный город провинции столицы исчезает.
		local cap = n.capital :: number
		local province = MapData.getProvince(m.map, cap)
		local oldCity = m.cityOf[province]
		if oldCity ~= nil and oldCity ~= cap then
			Grid.setCity(m.grid, oldCity, false)
		end
		m.cityOf[province] = cap
		Grid.setCity(m.grid, cap, true)
		for _, cell in StartPositions.circle(m.grid, cap, Config.Start.Radius) do
			-- Чужие города в круг не попадают: города берёт только фронт с войсками.
			if Grid.getOwner(m.grid, cell) == 0 and (cell == cap or not Grid.isCity(m.grid, cell)) then
				Grid.setOwner(m.grid, cell, n.id)
			end
		end
		n.people = Config.People.Start
		if n.isBot then
			m.botNextThink[n.id] = BotBrain.nextThinkDelay(m.rng)
		end
	end
	m.phase = "Play"
	m.phaseLeft = 0
	m.time = 0
	m.simTime = 0
	m.infoDirty = true
end

local function findAttack(m: Match, attacker: number, target: number): (number?, Attack?)
	for k, a in m.attacks do
		if a.attacker == attacker and a.target == target then
			return k, a
		end
	end
	return nil, nil
end

local function attacksOf(m: Match, attacker: number): number
	local count = 0
	for _, a in m.attacks do
		if a.attacker == attacker then
			count += 1
		end
	end
	return count
end

-- Возвращает войска и людей атаки домой.
local function returnHome(m: Match, a: Attack)
	local n = m.nations[a.attacker]
	if n ~= nil and n.alive then
		n.people += math.max(0, a.troops)
		Forces.merge(n.home, a.forces)
	end
	a.troops = 0
end

-- Войска на всех фронтах державы.
function MatchSim.frontForces(m: Match, nationId: number): Types.Forces
	local sum = Forces.new()
	for _, a in m.attacks do
		if a.attacker == nationId then
			for kind, s in a.forces do
				Forces.add(sum, kind, s.strength, s.xp)
			end
		end
	end
	return sum
end

-- Применяет намерение державы. Возвращает успех и код ошибки (для клиента и логов).
function MatchSim.applyIntent(m: Match, nationId: number, intent: Types.Intent): (boolean, string?)
	local n = m.nations[nationId]
	if n == nil then
		return false, "noNation"
	end
	if intent.kind == "pick" then
		if m.phase ~= "Pick" then
			return false, "phase"
		end
		local ok, err = StartPositions.check(m.grid, intent.cell, capitals(m, nationId))
		if not ok then
			return false, err
		end
		n.capital = intent.cell
		m.infoDirty = true
		return true, nil
	end

	if m.phase ~= "Play" then
		return false, "phase"
	end
	if not n.alive then
		return false, "dead"
	end

	if intent.kind == "cancel" then
		local k, a = findAttack(m, nationId, intent.target)
		if k == nil or a == nil then
			return false, "noAttack"
		end
		returnHome(m, a)
		table.remove(m.attacks, k)
		return true, nil
	end

	if intent.kind == "hire" then
		if #n.queue >= Config.Forces.MaxQueue then
			return false, "queueFull"
		end
		if n.capital == nil then
			return false, "noCapital"
		end
		local kind = Forces.kindIndex(intent.unit) :: number
		local stats = Forces.stats(kind)
		if n.people < stats.people then
			return false, "noTroops"
		end
		n.people -= stats.people
		table.insert(n.queue, { kind = kind, left = stats.recruitSec })
		return true, nil
	end

	-- attack
	local target = intent.target
	if target == nationId then
		return false, "self"
	end
	if target ~= 0 then
		local t = m.nations[target]
		if t == nil or not t.alive then
			return false, "target"
		end
	end
	local focus = intent.focus
	if focus ~= nil and focus >= m.grid.size then
		return false, "focus"
	end
	-- Города в соседстве считаются, если их есть чем брать: фронт против державы или войска с собой.
	if not Expansion.hasFrontier(m.grid, nationId, target, target ~= 0 or Forces.total(n.home) > 0) then
		return false, "notAdjacent"
	end
	local _, existing = findAttack(m, nationId, target)
	if existing == nil and attacksOf(m, nationId) >= Config.Expansion.MaxAttacks then
		return false, "tooMany"
	end
	local forces = Forces.take(n.home, intent.percent)
	local troops = 0
	if target == 0 then
		-- Ничья земля — людьми; войска (если есть) идут следом и берут ничейные города.
		troops = n.people * intent.percent
		if troops < Config.Expansion.MinTroops then
			Forces.merge(n.home, forces)
			return false, "noTroops"
		end
		n.people -= troops
	elseif
		Forces.total(forces) + (if existing ~= nil then Forces.total(existing.forces) else 0)
		< Config.Forces.MinFrontStrength
	then
		Forces.merge(n.home, forces)
		return false, "noUnits"
	end
	if existing ~= nil then
		existing.troops += troops
		Forces.merge(existing.forces, forces)
		existing.focus = focus
	else
		table.insert(m.attacks, {
			attacker = nationId,
			target = target,
			troops = troops,
			focus = focus,
			forces = forces,
			supplied = true,
			ratio = math.huge,
			fighting = false,
		})
	end
	return true, nil
end

-- Что бот «видит» о своей державе.
local function botView(m: Match, n: Nation): BotBrain.BotView
	local adjacent = Grid.adjacentOwners(m.grid, n.id)
	local neighbours: { BotBrain.Neighbour } = {}
	for owner in adjacent do
		if owner ~= 0 then
			local other = m.nations[owner]
			if other ~= nil and other.alive then
				table.insert(neighbours, { id = owner, people = other.people, power = Forces.total(other.home) })
			end
		end
	end
	table.sort(neighbours, function(a: BotBrain.Neighbour, b: BotBrain.Neighbour): boolean
		return a.id < b.id
	end)
	return {
		people = n.people,
		maxPeople = Economy.maxPeople(Grid.cellsOf(m.grid, n.id)),
		attacks = attacksOf(m, n.id),
		queue = #n.queue,
		power = Forces.total(n.home),
		hasCapital = n.capital ~= nil,
		-- Ничья земля «рядом», если её можно взять: обычные клетки — людьми, ничейный город — войсками.
		hasNeutral = Expansion.hasFrontier(m.grid, n.id, 0, false)
			or (
				Forces.total(n.home) >= Config.Combat.NeutralCityGarrison
				and Expansion.hasFrontier(m.grid, n.id, 0, true)
			),
		neighbours = neighbours,
	}
end

-- Держава выбыла: войска гибнут, её клетки становятся ничьими, атаки на неё заканчиваются.
local function eliminate(m: Match, n: Nation, by: number)
	n.alive = false
	n.people = 0
	n.home = Forces.new()
	n.queue = {}
	n.capital = nil
	local g = m.grid
	for i = 0, g.size - 1 do
		if Grid.getOwner(g, i) == n.id then
			Grid.setOwner(g, i, 0)
		end
	end
	local j = 1
	while j <= #m.attacks do
		local a = m.attacks[j]
		if a.attacker == n.id then
			table.remove(m.attacks, j)
		elseif a.target == n.id then
			returnHome(m, a)
			table.remove(m.attacks, j)
		else
			j += 1
		end
	end
	table.insert(m.events, { kind = "eliminated", nation = n.id, by = by })
	m.infoDirty = true
end

-- Ничейный город: войска атаки берут его, если могут оплатить гарнизон силой.
local function neutralCityTaker(a: Attack): ((cell: number) -> boolean)?
	if Forces.total(a.forces) <= 0 then
		return nil
	end
	return function(_cell: number): boolean
		local garrison = Config.Combat.NeutralCityGarrison
		if Forces.total(a.forces) < garrison then
			return false
		end
		Forces.applyDamage(a.forces, garrison)
		return true
	end
end

-- Шаг атак и фронтов на simDt игровых секунд. Возвращает число захваченных клеток.
local function stepAttacks(m: Match, simDt: number): number
	local g = m.grid
	local cities = MatchSim.cities(m)
	local captured = 0

	-- Фронты против держав: длины фронтов нужны, чтобы делить гарнизон защитника.
	type FrontInfo = { list: { number }, touching: { [number]: number } }
	local fronts: { [Attack]: FrontInfo } = {}
	local frontLength: { [number]: number } = {}
	for _, a in m.attacks do
		if a.target ~= 0 then
			local list, touching = Expansion.frontier(g, a.attacker, a.target, true)
			fronts[a] = { list = list, touching = touching }
			frontLength[a.target] = (frontLength[a.target] or 0) + #list
		end
	end

	local battled: { [Attack]: boolean } = {}
	local k = 1
	while k <= #m.attacks do
		local a = m.attacks[k]
		local done = false
		if a.target == 0 then
			local d, cells = Expansion.advance(m.map, g, m.nations, a, m.tick, m.seed, simDt, neutralCityTaker(a))
			done = d
			captured += cells
		else
			local front = fronts[a]
			local defender = m.nations[a.target]
			if front == nil or #front.list == 0 or defender == nil or not defender.alive then
				done = true
			else
				local _, counter = findAttack(m, a.target, a.attacker)
				local totalLen = math.max(1, frontLength[a.target] or #front.list)
				a.supplied = Fronts.supplied(g, cities, a.attacker, front.list)
				-- Встречные фронты пары — один бой: потери считаются один раз за тик.
				local applyLosses = not (counter ~= nil and battled[counter])
				local result = Fronts.battle(a, {
					home = defender.home,
					share = #front.list / totalLen,
					counter = if counter ~= nil then counter.forces else nil,
				}, Fronts.terrainDefense(m.map, front.list), m.rng, simDt, applyLosses)
				battled[a] = true
				a.ratio = result.ratio
				a.fighting = result.fighting
				local mul = Fronts.advanceMul(a, result.ratio)
				local allowCities = result.ratio >= Config.Combat.CityCaptureRatio
				captured += Expansion.advanceFront(
					g,
					m.nations,
					a,
					front.list,
					front.touching,
					mul,
					allowCities,
					m.tick,
					m.seed,
					simDt
				)
				done = Forces.total(a.forces) < 1
			end
		end
		if done then
			returnHome(m, a)
			table.remove(m.attacks, k)
		else
			k += 1
		end
	end
	return captured
end

-- Шаг симуляции на dt секунд (сервер зовёт с dt = 1 / TickRate).
function MatchSim.step(m: Match, dt: number)
	if m.phase == "Waiting" then
		return
	elseif m.phase == "Pick" then
		m.phaseLeft -= dt
		if m.phaseLeft <= 0 then
			MatchSim.finishPick(m)
		end
		return
	end

	m.tick += 1
	m.time += dt
	local simDt = dt * m.speed
	m.simTime += simDt
	local g = m.grid

	-- Люди и найм.
	for _, n in m.nations do
		if n.alive then
			n.people = Economy.grow(n.people, Economy.maxPeople(Grid.cellsOf(g, n.id)), simDt)
			local first = n.queue[1]
			if first ~= nil then
				first.left -= simDt
				if first.left <= 0 then
					Forces.add(n.home, first.kind, Forces.stats(first.kind).strength, 0)
					table.remove(n.queue, 1)
				end
			end
		end
	end

	m.lastCaptured = stepAttacks(m, simDt)

	-- Столицы и выбывание: держава живёт, пока у неё есть хоть один город.
	for _, n in m.nations do
		if n.alive then
			local capital = n.capital
			if capital ~= nil and Grid.getOwner(g, capital) ~= n.id then
				MatchSim.capitalLost(m, n.id, Grid.getOwner(g, capital))
			end
			if MatchSim.citiesOf(m, n.id) == 0 or Grid.cellsOf(g, n.id) == 0 then
				local by = if capital ~= nil then Grid.getOwner(g, capital) else 0
				eliminate(m, n, by)
			end
		end
	end

	-- Боты.
	for _, n in m.nations do
		local due = m.botNextThink[n.id]
		if n.alive and n.isBot and due ~= nil and m.simTime >= due then
			m.botNextThink[n.id] = m.simTime + BotBrain.nextThinkDelay(m.rng)
			local intent = BotBrain.decide(botView(m, n), m.rng)
			if intent ~= nil then
				MatchSim.applyIntent(m, n.id, intent)
			end
		end
	end
end

-- Забирает накопленные события (для ленты событий).
function MatchSim.takeEvents(m: Match): { MatchEvent }
	local out = m.events
	m.events = {}
	return out
end

-- Людей в атаках у державы (для HUD и статистики).
function MatchSim.troopsOf(m: Match, nationId: number): number
	local sum = 0
	for _, a in m.attacks do
		if a.attacker == nationId then
			sum += a.troops
		end
	end
	return sum
end

return table.freeze(MatchSim)
