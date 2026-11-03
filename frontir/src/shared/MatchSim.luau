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

	Война и мир (§6.7а, Wars): по умолчанию мир; фронт против державы — только в активной войне
	(объявление → мобилизация). Без войны граница людей идёт только на ничью землю, окружение не берёт
	куски чужих стран. Мир: белый (взятое в войне возвращается) или «забрать захваченное»; после мира —
	запрет на новую войну; долгая война — усталость (меньше прирост людей).
]]

local BotBrain = require("./BotBrain")
local Buildings = require("./Buildings")
local Config = require("./Config")
local Economy = require("./Economy")
local Expansion = require("./Expansion")
local Forces = require("./Forces")
local Fronts = require("./Fronts")
local Grid = require("./Grid")
local MapData = require("./MapData")
local NameGen = require("./NameGen")
local NationColors = require("./NationColors")
local Pockets = require("./Pockets")
local Provinces = require("./Provinces")
local Rng = require("./Rng")
local StartPositions = require("./StartPositions")
local Types = require("./Types")
local Wars = require("./Wars")

type Grid = Grid.Grid
type MapData = MapData.MapData
type Rng = Rng.Rng
type Nation = Types.Nation
type Attack = Types.Attack

export type MatchEvent =
	{ kind: "eliminated", nation: number, by: number }
	| { kind: "capitalLost", nation: number, by: number }
	| { kind: "warDeclared", nation: number, target: number }
	| { kind: "warStarted", nation: number, target: number }
	| { kind: "peaceProposed", nation: number, target: number, terms: Types.PeaceTerms }
	| { kind: "peaceRejected", nation: number, target: number, expired: boolean }
	| { kind: "peace", nation: number, target: number, terms: Types.PeaceTerms, returned: number }
	| { kind: "pocketSurrendered", nation: number, by: number, cells: number }
	| { kind: "victory", nation: number, reason: Types.VictoryReason }

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
	wars: Wars.WarSet,
	buildings: Buildings.BuildingSet, -- §6.9
	owned: { [number]: Buildings.Owned }, -- здания и уровни городов по державам (пересчёт каждый тик)
	economy: { [number]: NationEconomy }, -- доход и содержание по державам (последний тик)
	pockets: { [number]: Pockets.NationPockets }, -- котлы по державам (§6.7)
	pocketCursor: number, -- чья связность проверяется следующей
	pocketCheck: { [number]: { version: number, at: number } }, -- когда и при какой территории считали котлы
	result: Types.MatchResult?, -- итог (фаза Over)
	victory: boolean, -- проверять ли победу (тесты на крошечных картах выключают)
	history: { times: { number }, shares: { [number]: { number } } }, -- доля суши по времени
	nextHistoryAt: number,
}

-- Экономика державы за последний тик, в секунду (§6.8).
export type NationEconomy = { income: number, oilIncome: number, upkeep: number }

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
		wars = Wars.new(),
		buildings = Buildings.new(),
		owned = {},
		economy = {},
		pockets = {},
		pocketCursor = 1,
		pocketCheck = {},
		result = nil,
		victory = true,
		history = { times = {}, shares = {} },
		nextHistoryAt = 0,
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
		money = 0,
		oil = 0,
	}
	table.insert(m.nations, nation)
	m.infoDirty = true
	return nation
end

-- Добавляет игрока (только до начала игры). Возвращает id державы или nil, если мест нет / игра идёт.
function MatchSim.addPlayer(m: Match, userId: number, name: string): number?
	if m.phase == "Play" or m.phase == "Over" or #m.nations >= Config.Match.MaxPlayers then
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

-- Лобби (этап 4в): игроки собираются, через LobbySec начинается выбор старта.
function MatchSim.startLobby(m: Match)
	if m.phase ~= "Waiting" then
		return
	end
	m.phase = "Lobby"
	m.phaseLeft = Config.Match.LobbySec
	m.infoDirty = true
end

-- Выбор старта (из ожидания — сразу, минуя лобби: так делают тесты и превью).
function MatchSim.startPick(m: Match)
	if m.phase ~= "Waiting" and m.phase ~= "Lobby" then
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
		n.money = Config.Economy.StartMoney
		if n.isBot then
			m.botNextThink[n.id] = BotBrain.nextThinkDelay(m.rng)
		end
	end
	m.phase = "Play"
	m.phaseLeft = 0
	m.time = 0
	m.simTime = 0
	m.infoDirty = true
	MatchSim.refreshOwned(m)
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
		local owned = MatchSim.ownedOf(m, nationId)
		if stats.requires == "Factory" and owned.factories == 0 then
			return false, "needFactory"
		end
		if n.people < stats.people then
			return false, "noTroops"
		end
		if n.money < stats.cost then
			return false, "noMoney"
		end
		if n.oil < stats.oil then
			return false, "noOil"
		end
		n.people -= stats.people
		n.money -= stats.cost
		n.oil -= stats.oil
		-- Свой завод ускоряет найм (§6.9).
		local speed = if owned.factories > 0 then 1 - Config.Buildings.Factory.recruitSpeedBonus else 1
		table.insert(n.queue, { kind = kind, left = stats.recruitSec * speed })
		return true, nil
	end

	if intent.kind == "build" then
		local spot, reason = Buildings.check(m.buildings, m.grid, m.map, m.provinces, function(cell: number): boolean
			return Grid.isCity(m.grid, cell)
		end, nationId, intent.building, intent.cell)
		if spot == nil then
			return false, reason
		end
		local money, oil = Buildings.cost(m.buildings, intent.building, spot)
		if money == nil then
			return false, "maxLevel"
		end
		if n.money < money then
			return false, "noMoney"
		end
		if n.oil < oil then
			return false, "noOil"
		end
		n.money -= money
		n.oil -= oil
		Buildings.place(m.buildings, intent.building, spot, MapData.getProvince(m.map, spot))
		MatchSim.refreshOwned(m)
		return true, nil
	end

	if intent.kind == "declare" then
		local t = m.nations[intent.target]
		if t == nil or not t.alive then
			return false, "target"
		end
		local ok, reason = Wars.canDeclare(m.wars, nationId, intent.target, m.simTime)
		if not ok then
			return false, reason
		end
		Wars.declare(m.wars, nationId, intent.target, m.simTime)
		table.insert(m.events, { kind = "warDeclared", nation = nationId, target = intent.target })
		return true, nil
	end

	if intent.kind == "peace" then
		local war = Wars.find(m.wars, nationId, intent.target)
		if war == nil then
			return false, "notAtWar"
		end
		if intent.terms == "capitulate" then
			return false, "notYet" -- вассалитет — этап 6
		end
		if war.proposal ~= nil then
			return false, "peacePending"
		end
		war.proposal = {
			from = nationId,
			terms = intent.terms,
			madeAt = m.simTime,
			expiresAt = m.simTime + Config.War.PeaceReplySec,
		}
		war.lastProposal[nationId] = m.simTime
		table.insert(m.events, {
			kind = "peaceProposed",
			nation = nationId,
			target = intent.target,
			terms = intent.terms,
		})
		return true, nil
	end

	if intent.kind == "peaceReply" then
		local war = Wars.find(m.wars, nationId, intent.target)
		local proposal = if war ~= nil then war.proposal else nil
		if war == nil or proposal == nil or proposal.from ~= intent.target then
			return false, "noProposal"
		end
		war.proposal = nil
		if intent.accept then
			MatchSim.makePeace(m, war, proposal.terms)
		else
			table.insert(m.events, {
				kind = "peaceRejected",
				nation = nationId,
				target = intent.target,
				expired = false,
			})
		end
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
		-- Землю страны берёт только фронт, и только в активной войне (§6.7а).
		local war = Wars.find(m.wars, nationId, target)
		if war == nil then
			return false, "notAtWar"
		elseif war.state ~= "active" then
			return false, "mobilizing"
		end
	end
	local focus = intent.focus
	if focus ~= nil and focus >= m.grid.size then
		return false, "focus"
	end
	-- Города в соседстве считаются, если их есть чем брать: фронт против державы или войска с собой.
	-- Фронт против страны видит и землю за рекой; граница людей реку не переходит.
	local riverMap = if target ~= 0 then m.map else nil
	if not Expansion.hasFrontier(m.grid, nationId, target, target ~= 0 or Forces.total(n.home) > 0, riverMap) then
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
			lastAdvance = m.simTime,
		})
	end
	return true, nil
end

-- Что бот «видит» о своей державе.
local NO_BUILDINGS: Buildings.Owned = table.freeze({ factories = 0, markets = 0, rigs = 0, forts = 0, cityLevels = 0 })

-- Здания и уровни городов державы (пересчитываются каждый тик и после постройки).
function MatchSim.ownedOf(m: Match, nationId: number): Buildings.Owned
	return m.owned[nationId] or NO_BUILDINGS
end

function MatchSim.refreshOwned(m: Match)
	m.owned = Buildings.owned(m.buildings, m.grid, MatchSim.cities(m))
end

-- Максимум людей державы: клетки вне котлов и уровни своих городов (§6.3, §6.7, §6.8).
function MatchSim.maxPeopleOf(m: Match, nationId: number): number
	local pocket = m.pockets[nationId]
	local cells = Grid.cellsOf(m.grid, nationId) - (if pocket ~= nil then pocket.cells else 0)
	return Economy.maxPeople(cells, MatchSim.ownedOf(m, nationId).cityLevels)
end

-- Вся сила державы: гарнизон и фронты.
local function totalPower(m: Match, id: number): number
	local n = m.nations[id]
	if n == nil then
		return 0
	end
	return Forces.total(n.home) + Forces.total(MatchSim.frontForces(m, id))
end

-- Где боту можно строить: первая подходящая провинция для каждого здания (§6.9).
local function buildSpots(m: Match, n: Nation): BotBrain.BuildSpots
	local spots: BotBrain.BuildSpots = {}
	local g = m.grid
	for _, p in m.provinces.list do
		if Grid.getOwner(g, p.center) == n.id and m.buildings.byProvince[p.id] == nil then
			if p.oil and spots.oilRig == nil then
				spots.oilRig = p.center
			elseif not p.oil and spots.free == nil then
				spots.free = p.center
			end
			-- Укрепление — в провинции у границы с врагом.
			if spots.fort == nil then
				local touches = false
				for _, other in p.neighbours do
					local o = Grid.getOwner(g, m.provinces.list[other].center)
					if o ~= 0 and o ~= n.id and Wars.isActive(m.wars, n.id, o) then
						touches = true
						break
					end
				end
				if touches then
					spots.fort = p.center
				end
			end
		end
	end
	for _, cell in m.cityOf do
		if Grid.getOwner(g, cell) == n.id and Buildings.cityLevel(m.buildings, cell) < Config.Economy.MaxCityLevel then
			if spots.city == nil or cell == n.capital then
				spots.city = cell
			end
		end
	end
	return spots
end

local function botView(m: Match, n: Nation): BotBrain.BotView
	local adjacent = Grid.adjacentOwners(m.grid, n.id)
	local neighbours: { BotBrain.Neighbour } = {}
	for owner in adjacent do
		if owner ~= 0 then
			local other = m.nations[owner]
			if other ~= nil and other.alive then
				table.insert(neighbours, {
					id = owner,
					people = other.people,
					power = Forces.total(other.home),
					atWar = Wars.isActive(m.wars, n.id, owner),
					canDeclare = (Wars.canDeclare(m.wars, n.id, owner, m.simTime)),
				})
			end
		end
	end
	local wars: { BotBrain.WarView } = {}
	for _, war in Wars.of(m.wars, n.id) do
		local enemy = Wars.enemyOf(war, n.id)
		local byA, byB = Wars.takenCells(war, m.grid)
		local last = war.lastProposal[n.id]
		table.insert(wars, {
			enemy = enemy,
			active = war.state == "active",
			age = math.max(0, m.simTime - war.activeAt),
			myGain = if war.a == n.id then byA else byB,
			theirGain = if war.a == n.id then byB else byA,
			theirPower = totalPower(m, enemy),
			canPropose = war.proposal == nil and (last == nil or m.simTime - last >= Config.Bots.PeaceRetrySec),
			proposedBefore = last ~= nil,
		})
	end
	table.sort(neighbours, function(a: BotBrain.Neighbour, b: BotBrain.Neighbour): boolean
		return a.id < b.id
	end)
	return {
		people = n.people,
		maxPeople = MatchSim.maxPeopleOf(m, n.id),
		attacks = attacksOf(m, n.id),
		queue = #n.queue,
		power = Forces.total(n.home),
		totalPower = totalPower(m, n.id),
		hasCapital = n.capital ~= nil,
		-- Ничья земля «рядом», если её можно взять: обычные клетки — людьми, ничейный город — войсками.
		hasNeutral = Expansion.hasFrontier(m.grid, n.id, 0, false)
			or (
				Forces.total(n.home) >= Config.Combat.NeutralCityGarrison
				and Expansion.hasFrontier(m.grid, n.id, 0, true)
			),
		neighbours = neighbours,
		wars = wars,
		money = n.money,
		oil = n.oil,
		economy = m.economy[n.id] or { income = 0, oilIncome = 0, upkeep = 0 },
		owned = MatchSim.ownedOf(m, n.id),
		spots = buildSpots(m, n),
	}
end

-- Держава выбыла: войска гибнут, её клетки становятся ничьими, атаки на неё заканчиваются.
local function eliminate(m: Match, n: Nation, by: number)
	n.alive = false
	n.eliminatedAt = m.time
	n.people = 0
	n.home = Forces.new()
	n.queue = {}
	n.capital = nil
	-- Клетки державы ищем заливкой от её границы (у каждого её куска есть пограничная клетка),
	-- а не перебором всей карты: на «Мире» это 524 тыс. клеток.
	local g = m.grid
	local cells: { number } = {}
	local seen: { [number]: boolean } = {}
	for i in Grid.borderCells(g, n.id) do
		if not seen[i] then
			seen[i] = true
			table.insert(cells, i)
		end
	end
	local head = 1
	while head <= #cells do
		Grid.forNeighbours(g, cells[head], function(j)
			if not seen[j] and Grid.getOwner(g, j) == n.id then
				seen[j] = true
				table.insert(cells, j)
			end
		end)
		head += 1
	end
	for _, i in cells do
		Grid.setOwner(g, i, 0)
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
	for _, war in Wars.of(m.wars, n.id) do
		Wars.finish(m.wars, war, m.simTime, false)
	end
	table.insert(m.events, { kind = "eliminated", nation = n.id, by = by })
	m.infoDirty = true
end

-- Мир между сторонами войны: белый — взятое в войне возвращается; фронты между ними закрываются,
-- войска идут домой; паре на PeaceCooldownSec запрещено снова объявлять войну.
function MatchSim.makePeace(m: Match, war: Wars.War, terms: Types.PeaceTerms)
	local returned = 0
	if terms == "white" then
		returned = Wars.returnTaken(war, m.grid, function(id: number): boolean
			local nation = m.nations[id]
			return nation ~= nil and nation.alive
		end)
	end
	local j = 1
	while j <= #m.attacks do
		local a = m.attacks[j]
		if (a.attacker == war.a and a.target == war.b) or (a.attacker == war.b and a.target == war.a) then
			returnHome(m, a)
			table.remove(m.attacks, j)
		else
			j += 1
		end
	end
	Wars.finish(m.wars, war, m.simTime, true)
	table.insert(m.events, { kind = "peace", nation = war.a, target = war.b, terms = terms, returned = returned })
end

-- Чьи окружённые куски может забрать attacker: ничьи и тех, с кем идёт война.
local function enclaveRule(m: Match, attacker: number): (owner: number) -> boolean
	return function(owner: number): boolean
		return owner == 0 or Wars.isActive(m.wars, attacker, owner)
	end
end

local function recordCapture(m: Match): (cell: number, old: number, new: number) -> ()
	return function(cell: number, old: number, new: number)
		Wars.record(m.wars, cell, old, new)
	end
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
	local fronts: { [Attack]: Expansion.FrontLine } = {}
	local frontLength: { [number]: number } = {}
	for _, a in m.attacks do
		if a.target ~= 0 then
			local list, touching, river = Expansion.frontier(g, a.attacker, a.target, true, m.map)
			fronts[a] = { list = list, touching = touching, river = river }
			frontLength[a.target] = (frontLength[a.target] or 0) + #list
		end
	end
	local record = recordCapture(m)

	local battled: { [Attack]: boolean } = {}
	local k = 1
	while k <= #m.attacks do
		local a = m.attacks[k]
		local done = false
		if a.target == 0 then
			local d, cells = Expansion.advance(m.map, g, m.nations, a, m.tick, m.seed, simDt, {
				cityAllowed = neutralCityTaker(a),
				canTake = enclaveRule(m, a.attacker),
				record = record,
			})
			done = d
			captured += cells
		else
			local front = fronts[a]
			local defender = m.nations[a.target]
			local war = Wars.find(m.wars, a.attacker, a.target)
			if
				front == nil
				or #front.list == 0
				or defender == nil
				or not defender.alive
				or war == nil
				or war.state ~= "active"
			then
				done = true
			else
				local _, counter = findAttack(m, a.target, a.attacker)
				local totalLen = math.max(1, frontLength[a.target] or #front.list)
				-- Котлы: клетки фронта в котле защитника гарнизон не защищает; фронт из котла атакующего —
				-- без снабжения (§6.7).
				local defPockets, atkPockets = m.pockets[a.target], m.pockets[a.attacker]
				local inDefPocket, fromAtkPocket = 0, 0
				for _, cell in front.list do
					if defPockets ~= nil and defPockets.inPocket[cell] ~= nil then
						inDefPocket += 1
					end
					if atkPockets ~= nil and atkPockets.cells > 0 then
						local fromPocket = false
						Grid.forNeighbours(g, cell, function(j)
							if atkPockets.inPocket[j] ~= nil then
								fromPocket = true
							end
						end)
						if fromPocket then
							fromAtkPocket += 1
						end
					end
				end
				a.supplied = Fronts.supplied(g, cities, a.attacker, front.list) and fromAtkPocket * 2 <= #front.list
				local homeShare = #front.list / totalLen * (1 - inDefPocket / #front.list)
				-- Укреплённая линия: фронт долго стоит — защитнику бонус (§6.9).
				local still = m.simTime - a.lastAdvance >= Config.Fortify.AfterSec
				local function fortified(cell: number): boolean
					return Buildings.fortified(m.buildings, g, m.map, cell)
				end
				-- Встречные фронты пары — один бой: потери считаются один раз за тик.
				local applyLosses = not (counter ~= nil and battled[counter])
				local result = Fronts.battle(a, {
					home = defender.home,
					share = homeShare,
					counter = if counter ~= nil then counter.forces else nil,
					bonus = if still then Config.Fortify.LineBonus else 1,
				}, Fronts.terrainDefense(m.map, front.list, front.river, fortified), m.rng, simDt, applyLosses)
				battled[a] = true
				a.ratio = result.ratio
				a.fighting = result.fighting
				Wars.addLosses(war, a.attacker, result.lostAttacker)
				Wars.addLosses(war, a.target, result.lostDefender)
				local mul = Fronts.advanceMul(a, result.ratio)
				local allowCities = result.ratio >= Config.Combat.CityCaptureRatio
				local took = Expansion.advanceFront(
					m.map,
					g,
					m.nations,
					a,
					front,
					mul,
					allowCities,
					m.tick,
					m.seed,
					simDt,
					{ canTake = enclaveRule(m, a.attacker), record = record }
				)
				if took > 0 then
					a.lastAdvance = m.simTime
				end
				captured += took
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

-- Боты отвечают на предложения мира (с небольшой задержкой, как человек).
local function answerBotProposals(m: Match)
	for _, war in table.clone(m.wars.list) do
		local p = war.proposal
		if p ~= nil and m.simTime >= p.madeAt + Config.War.BotReplyDelaySec then
			local me = Wars.enemyOf(war, p.from)
			local bot = m.nations[me]
			if bot ~= nil and bot.isBot then
				war.proposal = nil
				local byA, byB = Wars.takenCells(war, m.grid)
				local accept = BotBrain.answerPeace({
					terms = p.terms,
					myGain = if war.a == me then byA else byB,
					theirGain = if war.a == me then byB else byA,
					myPower = totalPower(m, me),
					theirPower = totalPower(m, p.from),
				})
				if accept then
					MatchSim.makePeace(m, war, p.terms)
				else
					table.insert(m.events, { kind = "peaceRejected", nation = me, target = p.from, expired = false })
				end
			end
		end
	end
end

-- Деньги и нефть державы за simDt (§6.8): доход, вышки, содержание войск; денег нет — войска тают.
local function stepEconomy(m: Match, n: Nation, simDt: number)
	local owned = MatchSim.ownedOf(m, n.id)
	local strength = Forces.total(n.home) + Forces.total(MatchSim.frontForces(m, n.id))
	local e: NationEconomy = {
		income = Economy.income(Grid.cellsOf(m.grid, n.id), owned.cityLevels, owned.markets),
		oilIncome = Economy.oilIncome(owned.rigs),
		upkeep = Economy.upkeep(strength),
	}
	m.economy[n.id] = e
	n.oil += e.oilIncome * simDt
	n.money += (e.income - e.upkeep) * simDt
	if n.money < 0 then
		n.money = 0
		-- Платить нечем: войска разбегаются.
		local loss = Config.Economy.UnpaidAttritionPerSec * simDt
		Forces.attrition(n.home, loss)
		for _, a in m.attacks do
			if a.attacker == n.id then
				Forces.attrition(a.forces, loss)
			end
		end
	end
end

-- Котлы (§6.7): по NationsPerTick держав за тик пересчитать связность; котёл без города, который
-- держится дольше SurrenderSec, переходит соседу, с которым идёт война.
local function stepPockets(m: Match)
	local count = #m.nations
	if count == 0 then
		return
	end
	for _ = 1, Config.Pocket.NationsPerTick do
		local n = m.nations[(m.pocketCursor - 1) % count + 1]
		m.pocketCursor = m.pocketCursor % count + 1
		local previous = m.pockets[n.id]
		local version = m.grid.version[n.id] or 0
		local check = m.pocketCheck[n.id]
		-- Пересчёт — только если территория менялась и не чаще CheckEverySec.
		local stale = check == nil or (check.version ~= version and m.simTime - check.at >= Config.Pocket.CheckEverySec)
		if n.alive and stale then
			m.pocketCheck[n.id] = { version = version, at = m.simTime }
			m.pockets[n.id] = Pockets.compute(m.grid, n.id, n.capital, function(cell: number): boolean
				return Grid.isCity(m.grid, cell)
			end, m.simTime, previous)
		end
		local result = m.pockets[n.id]
		if n.alive and result ~= nil then
			for _, pocket in result.pockets do
				if not pocket.hasCity and m.simTime - pocket.since >= Config.Pocket.SurrenderSec then
					local captor = Pockets.captor(m.grid, n.id, pocket, function(other: number): boolean
						return Wars.isActive(m.wars, n.id, other)
					end)
					if captor ~= 0 then
						for _, cell in pocket.cells do
							Grid.setOwner(m.grid, cell, captor)
							Wars.record(m.wars, cell, n.id, captor)
						end
						table.insert(m.events, {
							kind = "pocketSurrendered",
							nation = n.id,
							by = captor,
							cells = #pocket.cells,
						})
						m.pockets[n.id] = nil -- пересчитать при следующей проверке
						m.pocketCheck[n.id] = nil
					end
				end
			end
		end
	end
end

-- Точка графика доли суши (раз в HistoryEverySec секунд матча).
local function recordHistory(m: Match, force: boolean?)
	if m.time < m.nextHistoryAt and not force then
		return
	end
	m.nextHistoryAt = m.time + Config.Match.HistoryEverySec
	table.insert(m.history.times, math.floor(m.time))
	for _, n in m.nations do
		local list = m.history.shares[n.id]
		if list == nil then
			list = {}
			m.history.shares[n.id] = list
		end
		table.insert(list, math.floor(Grid.cellsOf(m.grid, n.id) / math.max(1, m.grid.capturableCount) * 100 + 0.5))
	end
end

-- Места: победитель; дальше живые по доле суши; дальше выбывшие — кто продержался дольше.
function MatchSim.places(m: Match, winner: number): { number }
	local order: { Nation } = table.clone(m.nations)
	table.sort(order, function(a: Nation, b: Nation): boolean
		if (a.id == winner) ~= (b.id == winner) then
			return a.id == winner
		end
		if a.alive ~= b.alive then
			return a.alive
		end
		if a.alive then
			local ca, cb = Grid.cellsOf(m.grid, a.id), Grid.cellsOf(m.grid, b.id)
			if ca ~= cb then
				return ca > cb
			end
		else
			local ea, eb = a.eliminatedAt or 0, b.eliminatedAt or 0
			if ea ~= eb then
				return ea > eb
			end
		end
		return a.id < b.id
	end)
	local out: { number } = {}
	for _, n in order do
		table.insert(out, n.id)
	end
	return out
end

-- Победа (§2): 60% суши, последний выживший или больше всех суши к лимиту времени. Возвращает true, если матч кончился.
local function checkVictory(m: Match): boolean
	if not m.victory then
		return false
	end
	local alive, last = 0, 0
	local leader, leaderCells = 0, -1
	for _, n in m.nations do
		if n.alive then
			alive += 1
			last = n.id
			local cells = Grid.cellsOf(m.grid, n.id)
			if cells > leaderCells then
				leader, leaderCells = n.id, cells
			end
		end
	end
	local reason: Types.VictoryReason? = nil
	local winner = leader
	if leaderCells >= m.grid.capturableCount * Config.Match.VictoryLandShareFfa then
		reason = "land"
	elseif alive <= 1 and #m.nations > 1 then
		reason, winner = "last", last
	elseif m.time >= Config.Match.TimeLimitSec then
		reason = "time"
	end
	if reason == nil or winner == 0 then
		return false
	end
	m.nextHistoryAt = 0
	recordHistory(m, true) -- последняя точка графика — момент победы
	m.result = {
		winner = winner,
		reason = reason,
		places = MatchSim.places(m, winner),
		times = m.history.times,
		shares = m.history.shares,
	}
	m.phase = "Over"
	m.phaseLeft = Config.Match.ResultsSec
	m.infoDirty = true
	table.insert(m.events, { kind = "victory", nation = winner, reason = reason })
	return true
end

-- Шаг симуляции на dt секунд (сервер зовёт с dt = 1 / TickRate).
function MatchSim.step(m: Match, dt: number)
	if m.phase == "Waiting" then
		return
	elseif m.phase == "Over" then
		m.phaseLeft -= dt -- экран результатов; сервер начнёт новый матч, когда время выйдет
		return
	elseif m.phase == "Lobby" then
		m.phaseLeft -= dt
		if m.phaseLeft <= 0 then
			MatchSim.startPick(m)
		end
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

	-- Здания, экономика, люди и найм.
	MatchSim.refreshOwned(m)
	for _, n in m.nations do
		if n.alive then
			stepEconomy(m, n, simDt)
			local growthMul = 1 - Wars.weariness(m.wars, n.id, m.simTime)
			n.people = Economy.grow(n.people, MatchSim.maxPeopleOf(m, n.id), simDt, growthMul)
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

	-- Войны: конец мобилизации, истёкшие предложения мира, ответы ботов.
	local started, expired = Wars.update(m.wars, m.simTime)
	for _, war in started do
		table.insert(m.events, { kind = "warStarted", nation = war.a, target = war.b })
	end
	for _, e in expired do
		local to = Wars.enemyOf(e.war, e.proposal.from)
		table.insert(m.events, { kind = "peaceRejected", nation = to, target = e.proposal.from, expired = true })
	end
	answerBotProposals(m)

	m.lastCaptured = stepAttacks(m, simDt)
	stepPockets(m)

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

	recordHistory(m)
	if checkVictory(m) then
		return
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
