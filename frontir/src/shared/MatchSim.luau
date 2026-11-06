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

local Air = require("./Air")
local BotBrain = require("./BotBrain")
local Buildings = require("./Buildings")
local Config = require("./Config")
local Commanders = require("./Commanders")
local Council = require("./Council")
local Diplomacy = require("./Diplomacy")
local Economy = require("./Economy")
local Expansion = require("./Expansion")
local Flood = require("./Flood")
local Fleet = require("./Fleet")
local Forces = require("./Forces")
local Fronts = require("./Fronts")
local Grid = require("./Grid")
local MapData = require("./MapData")
local Modes = require("./Modes")
local NameGen = require("./NameGen")
local NationColors = require("./NationColors")
local Naval = require("./Naval")
local Pockets = require("./Pockets")
local Provinces = require("./Provinces")
local Rng = require("./Rng")
local ServerSettings = require("./ServerSettings")
local Shop = require("./Shop")
local Stability = require("./Stability")
local StartPositions = require("./StartPositions")
local Tech = require("./Tech")
local Types = require("./Types")
local Wars = require("./Wars")
local WorldEvents = require("./WorldEvents")

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
	-- Договоры (§8.1)
	| { kind: "offerMade", nation: number, target: number, offer: Types.OfferKind, province: number? }
	| { kind: "offerAccepted", nation: number, target: number, offer: Types.OfferKind, province: number? }
	| { kind: "offerRefused", nation: number, target: number, offer: Types.OfferKind, expired: boolean }
	| { kind: "breakAnnounced", nation: number, target: number, treaty: Types.TreatyKind }
	| { kind: "treatyBroken", nation: number, target: number, treaty: Types.TreatyKind, betrayal: boolean }
	| { kind: "treatyExpired", nation: number, target: number }
	| { kind: "betrayal", nation: number, target: number }
	| { kind: "vassal", nation: number, target: number }
	| { kind: "independence", nation: number, target: number }
	| { kind: "allyAttacked", nation: number, target: number, ally: number }
	-- Торговля, Совет, пинги (§8.2)
	| { kind: "transfer", nation: number, target: number, money: number, oil: number, people: number }
	| { kind: "embargo", nation: number, target: number, on: boolean }
	| { kind: "tradeEnded", nation: number, target: number }
	| { kind: "councilOpened", options: { Types.Resolution } }
	| { kind: "councilClosed", winner: Types.Resolution?, votes: { number } }
	| { kind: "resolution", resolution: Types.Resolution, target: number? }
	| { kind: "ping", nation: number, cell: number, phrase: Types.Phrase }
	-- Стабильность (§6.10, этап 7а)
	| { kind: "revolt", nation: number, province: number }
	-- Технологии (§6.14, этап 7в-1)
	| { kind: "researched", nation: number, branch: Types.TechBranch, level: number }
	-- Случайные события (§6.16, этап 7г): событие; наёмники наняты (nation 0 — ставок не было)
	| { kind: "worldEvent", event: string, cell: number?, radius: number?, province: number?, nation: number? }
	| { kind: "mercs", nation: number, amount: number }
	-- Ракеты (§6.9, этап 7г): пуск (target — держава в клетке цели), удар, перехват сетью ПВО
	| { kind: "missileLaunched", nation: number, target: number, cell: number, impactIn: number }
	| { kind: "missileHit", nation: number, cell: number, cells: number }
	| { kind: "missileShot", nation: number, by: number, cell: number }
	-- Разведка (§6.11а): nation разведал target
	| { kind: "flood", step: number, cells: number } -- «Потоп» (§5.3): вода поднялась
	| { kind: "boost", nation: number, boost: string } -- буст магазина (§11.1)
	| { kind: "tutorial", nation: number, step: number } -- «Обучение» (§5.5): шаг пройден
	| { kind: "tutorialDone", nation: number }
	| { kind: "intel", nation: number, target: number }
	-- Генералы (§6.15, этап 7в-2): применена способность (target — держава в клетке цели, 0 — нет)
	| { kind: "ability", nation: number, ability: string, cell: number?, target: number }
	-- Флот (§6.12, этап 7б-1)
	| { kind: "shipBuilt", nation: number, ship: Types.ShipKind }
	| { kind: "shipSunk", nation: number, by: number, ship: Types.ShipKind, lost: number }
	| { kind: "landed", nation: number, target: number, cell: number, cells: number }
	| { kind: "blockade", nation: number, cell: number, on: boolean }
	-- Авиация (§6.13, этап 7б-2)
	| { kind: "planeBuilt", nation: number, plane: Types.PlaneKind }
	| { kind: "planeShot", nation: number, by: number, plane: Types.PlaneKind }
	| { kind: "raid", nation: number, target: number, cell: number, lost: number, buildings: number }

-- Потоки случайных чисел бота: когда думать, главные решения, флот, авиация, дипломатия.
export type Missile = { owner: number, cell: number, impactAt: number }

export type BotRngs = {
	think: Rng,
	main: Rng,
	navy: Rng,
	air: Rng,
	diplo: Rng,
	tech: Rng,
	ability: Rng,
	missile: Rng,
	intel: Rng,
}

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
	botProfiles: { [number]: BotBrain.Profile }, -- уровень и личность ботов (§9.1)
	botMemory: { [number]: BotBrain.Memory },
	botThinks: number, -- сколько ботов подумало в последнем тике (бюджет)
	infoDirty: boolean, -- изменились державы или фаза — разослать клиентам
	events: { MatchEvent },
	lastCaptured: number, -- клеток захвачено за последний тик
	provinces: Provinces.ProvinceSet,
	cityOf: { [number]: number }, -- провинция → клетка города (нейтрального, державы или столицы)
	wars: Wars.WarSet,
	diplo: Diplomacy.DiploSet, -- договоры (§8.1)
	frontCache: Expansion.FrontCache, -- линии фронтов между тиками (обновляются по журналу смен владельца)
	-- Отдельные потоки случайных чисел по системам (§12): новая механика одной системы не меняет ход других.
	-- m.rng — только расстановка (уровни ботов, имена, автостарт).
	councilRng: Rng,
	stabilityRng: Rng,
	botRngs: { [number]: BotRngs }, -- у каждого бота свои
	battleRngs: { [number]: Rng }, -- бой: у каждой пары атакующий → цель свой
	council: Council.CouncilState, -- Совет держав (§8.2)
	sent: { [number]: { { at: number, money: number, oil: number, people: number } } }, -- переводы за минуту
	pingAt: { [number]: number }, -- когда держава последний раз ставила пинг
	buildings: Buildings.BuildingSet, -- §6.9
	owned: { [number]: Buildings.Owned }, -- здания и уровни городов по державам (пересчёт каждый тик)
	economy: { [number]: NationEconomy }, -- доход и содержание по державам (последний тик)
	pockets: { [number]: Pockets.NationPockets }, -- котлы по державам (§6.7)
	pocketCursor: number, -- чья связность проверяется следующей
	pocketCheck: { [number]: { version: number, at: number } }, -- когда и при какой территории считали котлы
	stability: Stability.State, -- стабильность провинций и повстанцы (§6.10)
	sea: Naval.SeaMap, -- море, причалы, пути (§6.12)
	tech: Tech.TechState, -- технологии держав (§6.14)
	commanders: Commanders.CommanderState, -- генералы игроков и способности (§6.15)
	world: WorldEvents.WorldState, -- случайные события (§6.16)
	worldRng: Rng, -- поток событий
	missileRng: Rng, -- поток сети ПВО (перехват ракет)
	missiles: { Missile }, -- ракеты в полёте (§6.9)
	missileReady: { [number]: number }, -- держава → когда снова можно пускать
	fleet: Fleet.FleetState, -- корабли
	air: Air.AirState, -- самолёты и выведенные из строя здания (§6.13)
	bombedAt: { [number]: number }, -- держава → когда её последний раз бомбили (боты ставят батарею ПВО)
	bombedCell: { [number]: number }, -- держава → клетка последнего налёта на неё (Генерал прикрывает её истребителем)
	nextBlockadeAt: number,
	result: Types.MatchResult?, -- итог (фаза Over)
	victory: boolean, -- проверять ли победу (тесты на крошечных картах выключают)
	history: { times: { number }, shares: { [number]: { number } } }, -- доля суши по времени
	nextHistoryAt: number,
	-- Режимы (§5.1, этап 8а): правила режима, голосование в лобби, команды, охота на столицы, против ботов.
	mode: Types.ModeId,
	rules: Modes.Rules,
	modeOptions: { Types.ModeId }, -- варианты голосования
	modeVotes: { [number]: Types.ModeId }, -- держава игрока → голос
	voteTime: number, -- время сервера (unix) для режима недели
	mapOptions: { string }, -- голосование за карту на экране итогов (§5.2)
	mapVotes: { [number]: string },
	forcedMode: Types.ModeId?, -- режим без голосования (Dev.Mode, F4)
	teams: { [number]: number }, -- держава → команда («Команды»)
	teamCount: number,
	startCapitals: { [number]: number }, -- держава → исходная столица («Охота на столицы»)
	huntCount: { [number]: number }, -- держава → сколько исходных столиц врагов держит
	huntSince: { [number]: number }, -- держава → с какого времени держит нужное число
	solo: boolean, -- в матче один игрок («Против ботов»): пауза и ×2
	difficulty: Types.BotLevel?, -- уровень всех ботов, выбранный одиночным игроком
	paused: boolean,
	fast: boolean,
	-- Разведка (§6.11а): кто чью мощь видит.
	flood: { step: number, nextAt: number }, -- «Потоп» (§5.3): ступень воды, когда следующая (часы матча)
	tutorialStep: number, -- «Обучение» (§5.5): текущий шаг (1..6), 7 — пройдено
	tutorialStart: number, -- клеток игрока на старте (для шага «Расширение»)
	settings: ServerSettings.Settings?, -- настройки частного сервера (§5.4); nil — обычный сервер
	-- Магазин и профиль (§11.1, §11.2, этап 9а): перки геймпассов, бусты за матч, открытые генералы.
	perks: { [number]: Shop.Perks },
	boostsUsed: { [number]: { [string]: boolean } },
	unlocked: { [number]: { [string]: boolean } }, -- держава игрока → открытые генералы (нет записи — все)
	intel: { [number]: { [number]: number } }, -- разведчик → цель → до какого simTime
	radarIntel: { [number]: { [number]: boolean } }, -- держава → державы в радиусе её радаров
	nextRadarIntelAt: number,
}

-- Экономика державы за последний тик, в секунду (§6.8).
export type NationEconomy = { income: number, oilIncome: number, upkeep: number }

local MatchSim = {}

-- Море считается из карты один раз на карту (сервер создаёт новый матч на той же карте).
local seaCache: { [MapData]: { sea: Naval.SeaMap, provinces: Provinces.ProvinceSet } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any

function MatchSim.new(map: MapData, seed: number): Match
	local grid = Grid.new(map)
	local provinces = Provinces.build(map)
	local cachedSea = seaCache[map]
	local sea = if cachedSea ~= nil then cachedSea.sea else Naval.buildSea(map, provinces)
	if cachedSea == nil then
		seaCache[map] = { sea = sea, provinces = provinces }
	end
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
		botProfiles = {},
		botMemory = {},
		botThinks = 0,
		infoDirty = true,
		events = {},
		lastCaptured = 0,
		provinces = provinces,
		cityOf = cityOf,
		wars = Wars.new(),
		diplo = Diplomacy.new(),
		frontCache = Expansion.newCache(),
		councilRng = Rng.stream(seed, 101),
		stabilityRng = Rng.stream(seed, 102),
		botRngs = {},
		battleRngs = {},
		council = Council.new(),
		sent = {},
		pingAt = {},
		buildings = Buildings.new(),
		owned = {},
		economy = {},
		pockets = {},
		pocketCursor = 1,
		pocketCheck = {},
		stability = Stability.new(),
		sea = sea,
		fleet = Fleet.new(),
		tech = Tech.new(),
		commanders = Commanders.new(),
		world = WorldEvents.new(),
		worldRng = Rng.stream(seed, 300),
		missileRng = Rng.stream(seed, 301),
		missiles = {},
		missileReady = {},
		air = Air.new(),
		bombedAt = {},
		bombedCell = {},
		nextBlockadeAt = 0,
		result = nil,
		victory = true,
		history = { times = {}, shares = {} },
		nextHistoryAt = 0,
		mode = "Ffa",
		rules = Modes.rules("Ffa"),
		modeOptions = Modes.options(0),
		modeVotes = {},
		voteTime = 0,
		mapOptions = {},
		mapVotes = {},
		forcedMode = if Modes.isMode(Config.Dev.Mode) then Config.Dev.Mode :: Types.ModeId else nil,
		teams = {},
		teamCount = 0,
		startCapitals = {},
		huntCount = {},
		huntSince = {},
		solo = false,
		difficulty = nil,
		paused = false,
		fast = false,
		flood = { step = 0, nextAt = Config.Flood.EverySec },
		tutorialStep = 1,
		tutorialStart = 0,
		settings = nil,
		perks = {},
		boostsUsed = {},
		unlocked = {},
		intel = {},
		radarIntel = {},
		nextRadarIntelAt = 0,
	}
end

-- Режимы (§5.1) ---------------------------------------------------------------------------------

-- Игроки (не боты) в матче.
function MatchSim.humans(m: Match): number
	local count = 0
	for _, n in m.nations do
		if not n.isBot then
			count += 1
		end
	end
	return count
end

-- Одна команда («Команды»): война, разрыв союза и договоры с чужими по этому правилу.
function MatchSim.teammates(m: Match, a: number, b: number): boolean
	local ta = m.teams[a]
	return ta ~= nil and ta == m.teams[b]
end

-- Режим матча: правила, скорость. Зовётся в конце лобби (или тестом до выбора старта).
function MatchSim.setMode(m: Match, mode: Types.ModeId)
	m.mode = mode
	m.rules = Modes.rules(mode)
	local settings = m.settings
	if settings ~= nil then
		m.rules = ServerSettings.applyRules(m.rules, settings) -- частный сервер (§5.4)
	end
	m.speed = Config.Match.Speed * m.rules.speed
	m.infoDirty = true
end

-- Магазин (§11.1, этап 9а) ------------------------------------------------------------------------

-- Перки геймпассов державы в этом матче; без бустов в режиме (дуэль, частный сервер) — никаких.
function MatchSim.perksOf(m: Match, id: number): Shop.Perks
	local p = m.perks[id]
	if p == nil or not m.rules.boosts then
		return Shop.noPerks()
	end
	return p
end

function MatchSim.setPerks(m: Match, id: number, perks: Shop.Perks)
	m.perks[id] = perks
end

-- Открытые генералы игрока (по уровню профиля, §11.2); nil — все.
function MatchSim.setUnlocked(m: Match, id: number, set: { [string]: boolean }?)
	(m.unlocked :: any)[id] = set
end

-- Буст в матче (§11.1): один каждого вида за матч, только в игре и где бусты разрешены. Оплату (Robux или жетон)
-- проверяет сервер до вызова. Возвращает ok и причину отказа.
function MatchSim.canBoost(m: Match, id: number, key: string): (boolean, string?)
	local n = m.nations[id]
	if n == nil or not n.alive or n.isBot then
		return false, "dead"
	end
	if m.phase ~= "Play" then
		return false, "phase"
	end
	if not m.rules.boosts then
		return false, "noBoosts"
	end
	if not Shop.isBoost(key) then
		return false, "target"
	end
	local used = m.boostsUsed[id]
	if used ~= nil and used[key] then
		return false, "boostUsed"
	end
	if key == "Research" and m.tech.research[id] == nil then
		return false, "noResearch"
	end
	if key == "Squadron" and MatchSim.squadronPort(m, id) == nil then
		return false, "noPort"
	end
	if key == "AirWing" and MatchSim.airWingField(m, id) == nil then
		return false, "noAirfield"
	end
	return true, nil
end

-- Свой порт для «Эскадры» (§11.3): первый порт державы с причалом.
function MatchSim.squadronPort(m: Match, id: number): Port?
	for _, p in MatchSim.portsOf(m, id) do
		if not MatchSim.isDisabled(m, p.cell) then
			return p
		end
	end
	return nil
end

-- Свой аэродром для «Авиакрыла» (§11.3).
function MatchSim.airWingField(m: Match, id: number): number?
	for _, b in MatchSim.buildingsOf(m, "Airfield") do
		if b.owner == id and not MatchSim.isDisabled(m, b.cell) then
			return b.cell
		end
	end
	return nil
end

-- cell — цель «Авиаудара».
function MatchSim.useBoost(m: Match, id: number, key: string, cell: number?): (boolean, string?)
	local ok, why = MatchSim.canBoost(m, id, key)
	if not ok then
		return false, why
	end
	local n = m.nations[id]
	local cfg = Config.Shop.Boosts
	if key == "Mobilize" then
		for kind = 1, Forces.KINDS do
			local u = n.home[kind]
			u.strength += u.strength * cfg.Mobilize.garrisonShare
		end
	elseif key == "Loan" then
		n.money += cfg.Loan.money
	elseif key == "Research" then
		local r = m.tech.research[id]
		if r ~= nil then
			r.left = 0
		end
	elseif key == "Reserve" then
		Commanders.resetCooldowns(m.commanders, id)
	elseif key == "Guards" then
		-- Танки 2★: доля силы державы (гарнизон и фронты), не меньше minStrength (§11.3).
		local g = cfg.Guards
		local power = Forces.total(n.home) + Forces.total(MatchSim.frontForces(m, id))
		local tanks = Forces.kindIndex("Tanks") :: number
		Forces.add(n.home, tanks, math.max(g.minStrength, power * g.powerShare), g.xp)
	elseif key == "Airstrike" then
		local ok2, why2 = MatchSim.strikeAt(m, n, cell or -1, cfg.Airstrike.frontLoss)
		if not ok2 then
			return false, why2
		end
	elseif key == "Squadron" then
		local p = MatchSim.squadronPort(m, id) :: Port
		Fleet.spawn(m.fleet, m.grid.width, id, "Destroyer", p.cell, p.dock)
		Fleet.spawn(m.fleet, m.grid.width, id, "Transport", p.cell, p.dock)
	elseif key == "AirWing" then
		local field = MatchSim.airWingField(m, id) :: number
		Air.spawn(m.air, m.grid.width, id, "Fighter", field)
		Air.spawn(m.air, m.grid.width, id, "Bomber", field)
	end
	local used = m.boostsUsed[id]
	if used == nil then
		used = {}
		m.boostsUsed[id] = used
	end
	used[key] = true
	table.insert(m.events, { kind = "boost", nation = id, boost = key })
	return true, nil
end

-- Разведка и скрытая мощь (§6.11а) ------------------------------------------------------------

-- Чью военную мощь видит viewer: сам, друзья, разведанные, в радиусе радаров (своих и друзей).
-- nil — видно всё (мощь не скрывается или идёт «Радарная вспышка»).
function MatchSim.knownSet(m: Match, viewer: number): { [number]: boolean }?
	if not Config.Intel.HidePower or MatchSim.revealing(m, viewer) then
		return nil
	end
	local friends = Diplomacy.friends(m.diplo, viewer)
	local out: { [number]: boolean } = table.clone(friends)
	local spied = m.intel[viewer]
	if spied ~= nil then
		for target, untilTime in spied do
			if untilTime > m.simTime then
				out[target] = true
			end
		end
	end
	for id in friends do
		local seen = m.radarIntel[id]
		if seen ~= nil then
			for target in seen do
				out[target] = true
			end
		end
	end
	return out
end

-- Видит ли viewer военную мощь target.
function MatchSim.knows(m: Match, viewer: number, target: number): boolean
	local set = MatchSim.knownSet(m, viewer)
	return set == nil or set[target] == true
end

-- Разведка: за Intel.Cost мощь цели видна DurationSec; цели — событие (уведомление).
function MatchSim.spy(m: Match, n: Nation, target: number): (boolean, string?)
	local t = m.nations[target]
	if t == nil or not t.alive or target == n.id then
		return false, "target"
	end
	if Diplomacy.friends(m.diplo, n.id)[target] then
		return false, "already" -- мощь друзей и так видна
	end
	local perks = MatchSim.perksOf(m, n.id) -- «Разведуправление» (§11.1)
	local cost = math.floor(Config.Intel.Cost * perks.intelCostMul)
	if n.money < cost then
		return false, "noMoney"
	end
	n.money -= cost
	local list = m.intel[n.id]
	if list == nil then
		list = {}
		m.intel[n.id] = list
	end
	list[target] = math.max(list[target] or 0, m.simTime) + (perks.intelDurationSec or Config.Intel.DurationSec)
	table.insert(m.events, { kind = "intel", nation = n.id, target = target })
	return true, nil
end

-- «Потоп» (§5.3) ----------------------------------------------------------------------------------

-- Вода поднимается на ступень: клетки ниже порога — под воду (ничьи, незахватываемые), города и здания на них
-- исчезают; столица переедет и держава без городов выбудет обычной проверкой в конце тика.
function MatchSim.floodStep(m: Match): number
	local cfg = Config.Flood
	if m.flood.step >= cfg.MaxSteps then
		return 0
	end
	local levels = Flood.levels(m.map)
	local cells = Flood.sinking(levels, m.grid.width, m.flood.step, m.flood.step + 1)
	m.flood.step += 1
	local sunk = 0
	for _, cell in cells do
		if Grid.isCapturable(m.grid, cell) then
			sunk += 1
		end
		local province = MapData.getProvince(m.map, cell)
		if m.cityOf[province] == cell then
			m.cityOf[province] = nil
		end
		Buildings.remove(m.buildings, cell, province)
		Grid.sink(m.grid, cell)
	end
	MatchSim.clearBuildingsCache(m)
	m.infoDirty = true
	table.insert(m.events, { kind = "flood", step = m.flood.step, cells = sunk })
	return sunk
end

-- «Обучение» (§5.5) -------------------------------------------------------------------------------

-- Выполнен ли шаг step обучения державой n.
function MatchSim.tutorialDone(m: Match, n: Nation, step: number): boolean
	local kind = Config.Tutorial.Steps[step]
	if kind == "start" then
		return m.phase == "Play" and n.capital ~= nil
	elseif kind == "expand" then
		return Grid.cellsOf(m.grid, n.id) >= m.tutorialStart * Config.Tutorial.ExpandMul
	elseif kind == "hire" then
		return #n.queue > 0 or Forces.total(n.home) + Forces.total(MatchSim.frontForces(m, n.id)) > 0
	elseif kind == "city" then
		return MatchSim.citiesOf(m, n.id) >= 2
	elseif kind == "build" then
		local o = MatchSim.ownedOf(m, n.id)
		return o.factories + o.markets + o.rigs + o.forts + o.ports + o.airfields + o.silos > 0
	elseif kind == "alliance" then
		return #Diplomacy.alliesOf(m.diplo, n.id) > 0
	end
	return false
end

-- Шаги проходятся по порядку; пройденный — событие tutorial, все — tutorialDone (награду даёт сервер).
local function stepTutorial(m: Match)
	if not m.rules.tutorial or m.tutorialStep > #Config.Tutorial.Steps then
		return
	end
	for _, n in m.nations do
		if not n.isBot and n.alive then
			while m.tutorialStep <= #Config.Tutorial.Steps and MatchSim.tutorialDone(m, n, m.tutorialStep) do
				table.insert(m.events, { kind = "tutorial", nation = n.id, step = m.tutorialStep })
				m.tutorialStep += 1
				m.infoDirty = true
				if m.tutorialStep > #Config.Tutorial.Steps then
					table.insert(m.events, { kind = "tutorialDone", nation = n.id })
				end
			end
			return -- обучение — для одного игрока
		end
	end
end

local function stepFlood(m: Match)
	if not m.rules.flood or m.time < m.flood.nextAt then
		return
	end
	m.flood.nextAt += Config.Flood.EverySec
	MatchSim.floodStep(m)
end

-- Радар — постоянная разведка: державы, чья земля в радиусе радара (выборка клеток круга).
local function stepRadarIntel(m: Match)
	if m.simTime < m.nextRadarIntelAt then
		return
	end
	m.nextRadarIntelAt = m.simTime + Config.Intel.RadarEverySec
	table.clear(m.radarIntel)
	local g = m.grid
	local w, h = g.width, g.height
	local r = Config.Fog.RadarVision
	local step = Config.Intel.RadarStep
	for _, b in MatchSim.buildingsOf(m, "Radar") do
		if not MatchSim.isDisabled(m, b.cell) then
			local seen = m.radarIntel[b.owner]
			if seen == nil then
				seen = {}
				m.radarIntel[b.owner] = seen
			end
			local cx, cy = b.cell % w, b.cell // w
			for dy = -r, r, step do
				local y = cy + dy
				if y >= 0 and y < h then
					for dx = -r, r, step do
						local x = cx + dx
						if x >= 0 and x < w and dx * dx + dy * dy <= r * r then
							local o = Grid.getOwner(g, y * w + x)
							if o ~= 0 and o ~= b.owner then
								seen[o] = true
							end
						end
					end
				end
			end
		end
	end
end

-- Бот иногда разведывает сильнейшего соседа (§6.11а): игрок получает уведомление, сам бот видит всё и так.
local function botIntel(m: Match, n: Nation, rng: Rng)
	local cfg = Config.Intel
	if n.botLevel == "Novice" or n.money < cfg.Cost * cfg.BotMoneyMul or Rng.nextFloat(rng) >= cfg.BotChance then
		return
	end
	local near = Grid.adjacentOwners(m.grid, n.id)
	local best, bestPower = 0, 0
	local friends = Diplomacy.friends(m.diplo, n.id)
	for id in near do
		local other = m.nations[id]
		if other ~= nil and other.alive and not friends[id] and not MatchSim.knows(m, n.id, id) then
			local power = Forces.total(other.home)
			if power > bestPower then
				best, bestPower = id, power
			end
		end
	end
	if best ~= 0 then
		MatchSim.spy(m, n, best)
	end
end

-- Варианты голосования по времени сервера (режим недели — по номеру недели UTC).
function MatchSim.openVote(m: Match, unixTime: number)
	m.voteTime = unixTime
	-- Режим задан (F4, Dev.Mode, частный сервер) — голосования нет.
	m.modeOptions = if m.forcedMode ~= nil then {} else Modes.options(unixTime, MatchSim.humans(m))
	table.clear(m.modeVotes)
	m.infoDirty = true
end

-- Игроков в лобби стало больше или меньше — варианты («Дуэль» при 2 и 4, §5.2); голоса за пропавший вариант снимаются.
local function refreshModeOptions(m: Match)
	if m.phase ~= "Waiting" and m.phase ~= "Lobby" then
		return
	end
	m.modeOptions = if m.forcedMode ~= nil then {} else Modes.options(m.voteTime, MatchSim.humans(m))
	for id, mode in m.modeVotes do
		if table.find(m.modeOptions, mode) == nil then
			m.modeVotes[id] = nil
		end
	end
	m.infoDirty = true
end

-- Итог голосования за карту (§5.2): карта следующего матча.
function MatchSim.mapWinner(m: Match): string
	if #m.mapOptions == 0 then
		return m.map.name
	end
	return Modes.mapWinner(m.mapOptions, m.mapVotes)
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

-- Потоки случайных чисел бота (создаются при первом обращении).
local function botRngsOf(m: Match, id: number): BotRngs
	local r = m.botRngs[id]
	if r == nil then
		r = {
			think = Rng.stream(m.seed, 200, id),
			main = Rng.stream(m.seed, 201, id),
			navy = Rng.stream(m.seed, 202, id),
			air = Rng.stream(m.seed, 203, id),
			diplo = Rng.stream(m.seed, 204, id),
			tech = Rng.stream(m.seed, 205, id),
			ability = Rng.stream(m.seed, 206, id),
			missile = Rng.stream(m.seed, 207, id),
			intel = Rng.stream(m.seed, 208, id),
		}
		m.botRngs[id] = r
	end
	return r
end

-- Бот получает уровень и личность (§9.1); level — свой (игрок ушёл) или по Bots.LevelMix.
local function makeBot(m: Match, n: Nation, level: Types.BotLevel?)
	n.isBot = true
	n.botLevel = level or BotBrain.rollLevel(m.rng)
	n.personality = BotBrain.rollPersonality(m.rng)
	m.botProfiles[n.id] = BotBrain.profile(n.botLevel, n.personality)
	-- Генерал (§6.15): по личности; у державы ушедшего игрока остаётся его выбор.
	if m.commanders.chosen[n.id] == nil then
		Commanders.choose(m.commanders, n.id, Commanders.forPersonality(n.personality))
	end
	m.infoDirty = true
end

-- Профиль бота (Обычный — если не задан).
local function profileOf(m: Match, id: number): BotBrain.Profile
	local p = m.botProfiles[id]
	if p == nil then
		p = BotBrain.profile(nil, nil)
		m.botProfiles[id] = p
	end
	return p
end

-- Держава id — бот уровня level (личность — заданная или случайная). Для арены, тестов и превью.
function MatchSim.setBot(m: Match, id: number, level: Types.BotLevel, personality: Types.BotPersonality?)
	local n = m.nations[id]
	if n == nil then
		return
	end
	n.userId = nil
	makeBot(m, n, level)
	if personality ~= nil then
		n.personality = personality
		m.botProfiles[id] = BotBrain.profile(level, personality)
		Commanders.choose(m.commanders, id, Commanders.forPersonality(personality))
	end
	if m.botNextThink[id] == nil then
		m.botNextThink[id] = m.simTime + BotBrain.nextThinkDelay(botRngsOf(m, id).think, profileOf(m, id))
	end
end

-- Добавляет игрока (только до начала игры). Возвращает id державы или nil, если мест нет / игра идёт.
function MatchSim.addPlayer(m: Match, userId: number, name: string): number?
	if m.phase == "Play" or m.phase == "Over" or #m.nations >= Config.Match.MaxPlayers then
		return nil
	end
	local id = newNation(m, name, name, false, userId).id
	refreshModeOptions(m)
	return id
end

-- Игрок ушёл: его держава остаётся на карте и переходит под управление бота.
function MatchSim.removePlayer(m: Match, nationId: number)
	local n = m.nations[nationId]
	if n == nil then
		return
	end
	n.userId = nil
	makeBot(m, n, "Normal") -- держава ушедшего игрока — под Обычным ботом
	m.botNextThink[nationId] = m.simTime + BotBrain.nextThinkDelay(botRngsOf(m, nationId).think, profileOf(m, nationId))
	m.modeVotes[nationId] = nil
	m.mapVotes[nationId] = nil
	refreshModeOptions(m)
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

-- Обучение (§5.5) идёт только на карте Tutorial.Map (сводная правка): какую карту загрузить вместо текущей (nil — эта).
function MatchSim.tutorialMap(m: Match): string?
	if m.rules.tutorial and m.map.name ~= Config.Tutorial.Map then
		return Config.Tutorial.Map
	end
	return nil
end

-- Выбор старта (из ожидания — сразу, минуя лобби: так делают тесты и превью).
function MatchSim.startPick(m: Match)
	if m.phase ~= "Waiting" and m.phase ~= "Lobby" then
		return
	end
	m.phase = "Pick"
	m.phaseLeft = Config.Match.StartPickSec
	MatchSim.setMode(m, m.forcedMode or Modes.tally(m.modeOptions, m.modeVotes))
	m.solo = MatchSim.humans(m) == 1
	if m.rules.duel then
		m.targetNations = math.max(2, MatchSim.humans(m)) -- дуэль без ботов (§5.2); один игрок — против одного бота
	end
	if m.rules.tutorial then
		m.targetNations = Config.Tutorial.Nations -- обучение (§5.5): игрок и два мирных Новичка
		m.victory = false
	end
	if not m.solo then
		m.difficulty = nil
	end
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
		local settingsLevel: Types.BotLevel? = if m.settings ~= nil then m.settings.botLevel else nil
		makeBot(m, newNation(m, name.ru, name.en, true, nil), m.difficulty or settingsLevel)
	end
	local landmass: buffer? = nil
	for _, n in m.nations do
		if n.capital == nil then
			landmass = landmass or StartPositions.landmasses(m.map, m.grid)
			n.capital = StartPositions.autoPick(m.grid, capitals(m), m.rng, landmass)
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
		n.money = if m.settings ~= nil then m.settings.startMoney else Config.Economy.StartMoney
		if n.isBot then
			m.botNextThink[n.id] = BotBrain.nextThinkDelay(botRngsOf(m, n.id).think, profileOf(m, n.id))
		end
	end
	for _, n in order do
		m.startCapitals[n.id] = n.capital :: number
	end
	-- Команды (§5.1): по долготе столицы, внутри команды — вечный союз.
	local duelTeams = m.rules.duel and #order == 4 -- дуэль 2×2 (§5.2)
	if m.rules.teams or duelTeams then
		local byX: { { id: number, x: number } } = {}
		for _, n in order do
			table.insert(byX, { id = n.id, x = (n.capital :: number) % m.grid.width })
		end
		m.teamCount = if duelTeams then 2 else Modes.teamCount(#byX)
		m.teams = Modes.assignTeams(byX, m.teamCount)
		for i, a in order do
			for j = i + 1, #order do
				local b = order[j]
				if m.teams[a.id] == m.teams[b.id] then
					Diplomacy.sign(m.diplo, "alliance", a.id, b.id, 0)
				end
			end
		end
	end
	if m.rules.tutorial then
		for _, n in m.nations do
			if n.isBot then
				MatchSim.setBot(m, n.id, "Novice", "Peaceful")
			else
				m.tutorialStart = math.max(1, Grid.cellsOf(m.grid, n.id))
			end
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
	if intent.kind == "modeVote" then
		-- Голос за режим (§5.1): только в лобби, только игрок, только из вариантов.
		if m.phase ~= "Waiting" and m.phase ~= "Lobby" then
			return false, "phase"
		end
		if n.isBot or table.find(m.modeOptions, intent.mode) == nil then
			return false, "mode"
		end
		m.modeVotes[nationId] = intent.mode
		m.infoDirty = true
		return true, nil
	end
	if intent.kind == "mapVote" then
		-- Голос за карту (§5.2): только на экране итогов, только игрок, только из вариантов.
		if m.phase ~= "Over" then
			return false, "phase"
		end
		if n.isBot or table.find(m.mapOptions, intent.map) == nil then
			return false, "mode"
		end
		m.mapVotes[nationId] = intent.map
		m.infoDirty = true
		return true, nil
	end
	if intent.kind == "difficulty" then
		-- Против ботов (§5.1): сложность выбирает единственный игрок в лобби.
		if m.phase ~= "Waiting" and m.phase ~= "Lobby" then
			return false, "phase"
		end
		if n.isBot or MatchSim.humans(m) ~= 1 then
			return false, "solo"
		end
		m.difficulty = intent.level
		m.infoDirty = true
		return true, nil
	end
	if intent.kind == "solo" then
		if not m.solo or n.isBot or (m.phase ~= "Play" and m.phase ~= "Pick") then
			return false, "solo"
		end
		m.paused = intent.pause
		m.fast = intent.fast and not intent.pause
		m.infoDirty = true
		return true, nil
	end
	if intent.kind == "commander" then
		-- Генерал (§6.15): выбор до начала игры, потом закреплён.
		if m.phase ~= "Waiting" and m.phase ~= "Lobby" and m.phase ~= "Pick" then
			return false, "phase"
		end
		local open = m.unlocked[nationId]
		if open ~= nil and not open[intent.commander] then
			return false, "locked" -- генерал ещё не открыт уровнем (§11.2)
		end
		Commanders.choose(m.commanders, nationId, intent.commander)
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
		local cost = MatchSim.unitCost(m, nationId, kind)
		if n.money < cost then
			return false, "noMoney"
		end
		if n.oil < stats.oil then
			return false, "noOil"
		end
		n.people -= stats.people
		n.money -= cost
		n.oil -= stats.oil
		-- Свой завод ускоряет найм (§6.9).
		local speed = if owned.factories > 0 then 1 - Config.Buildings.Factory.recruitSpeedBonus else 1
		table.insert(n.queue, { kind = kind, left = stats.recruitSec * speed })
		return true, nil
	end

	if intent.kind == "build" then
		local spot, reason = Buildings.check(
			m.buildings,
			m.grid,
			m.map,
			m.provinces,
			function(cell: number): boolean
				return Grid.isCity(m.grid, cell)
			end,
			nationId,
			intent.building,
			intent.cell,
			function(province: number): boolean
				return m.sea.docks[province] ~= nil
			end,
			function(kind: Types.BuildingKind): boolean
				return MatchSim.techAllows(m, nationId, kind)
			end
		)
		if spot == nil then
			return false, reason
		end
		local base, oil = Buildings.cost(m.buildings, intent.building, spot)
		if base == nil then
			return false, "maxLevel"
		end
		-- Инженер (§6.15): здания дешевле.
		local money = base * Commanders.buildCostMul(Commanders.of(m.commanders, nationId))
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

	if intent.kind == "bid" then
		return MatchSim.bid(m, n, intent.amount)
	end
	if intent.kind == "missile" then
		return MatchSim.launch(m, n, intent.cell)
	end

	if intent.kind == "ability" then
		return MatchSim.useAbility(m, n, intent.slot, intent.cell, intent.percent)
	end

	if intent.kind == "research" then
		local level, reason = Tech.next(m.tech, nationId, intent.branch)
		if level == nil then
			return false, reason
		end
		local cost = Config.Tech.Cost[level]
		if n.money < cost then
			return false, "noMoney"
		end
		n.money -= cost
		Tech.start(m.tech, nationId, intent.branch, level)
		return true, nil
	end

	if intent.kind == "ship" or intent.kind == "land" or intent.kind == "patrol" then
		return MatchSim.navalIntent(m, n, intent)
	end
	if intent.kind == "plane" or intent.kind == "raid" or intent.kind == "cover" then
		return MatchSim.airIntent(m, n, intent)
	end

	if intent.kind == "declare" then
		local t = m.nations[intent.target]
		if t == nil or not t.alive then
			return false, "target"
		end
		-- Вассал и сюзерен друг с другом не воюют: вассалу — только «Независимость» (§8.1).
		if Diplomacy.overlordOf(m.diplo, nationId) == intent.target then
			return false, "vassalRebel"
		end
		if Diplomacy.overlordOf(m.diplo, intent.target) == nationId then
			return false, "ownVassal"
		end
		if Council.active(m.council, "truce", m.simTime) ~= nil then
			return false, "truce" -- всеобщее перемирие (§8.2)
		end
		if MatchSim.teammates(m, nationId, intent.target) then
			return false, "team" -- своей команде войну не объявить (§5.1)
		end
		local ok, reason = Wars.canDeclare(m.wars, nationId, intent.target, m.simTime)
		if not ok then
			return false, reason
		end
		MatchSim.declareWar(m, nationId, intent.target)
		return true, nil
	end

	if intent.kind == "peace" then
		local war = Wars.find(m.wars, nationId, intent.target)
		if war == nil then
			return false, "notAtWar"
		end
		-- Капитуляция (§8.1): только безнадёжно слабый и только если он ещё не вассал.
		if intent.terms == "capitulate" then
			if Diplomacy.overlordOf(m.diplo, nationId) ~= nil then
				return false, "vassal"
			end
			local mine, theirs = MatchSim.totalPower(m, nationId), MatchSim.totalPower(m, intent.target)
			if mine >= theirs * Config.Diplomacy.CapitulateBelow then
				return false, "notWeakEnough"
			end
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
			MatchSim.makePeace(m, war, proposal.terms, proposal.from)
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

	if intent.kind == "offer" then
		return MatchSim.offer(m, nationId, intent.target, intent.offer, intent.province)
	end

	if intent.kind == "offerReply" then
		local offer = Diplomacy.offerBetween(m.diplo, intent.target, nationId)
		if offer == nil then
			return false, "noOffer"
		end
		MatchSim.resolveOffer(m, offer, intent.accept, false)
		return true, nil
	end

	if intent.kind == "breakTreaty" then
		if MatchSim.teammates(m, nationId, intent.target) then
			return false, "team" -- союз команды вечный (§5.1)
		end
		local t = Diplomacy.treaty(m.diplo, nationId, intent.target)
		local ok, reason = Diplomacy.startBreak(m.diplo, nationId, intent.target, m.simTime)
		if not ok or t == nil then
			return false, reason
		end
		table.insert(m.events, { kind = "breakAnnounced", nation = nationId, target = intent.target, treaty = t.kind })
		return true, nil
	end

	if intent.kind == "intel" then
		return MatchSim.spy(m, n, intent.target)
	end

	if intent.kind == "transfer" then
		return MatchSim.transfer(m, nationId, intent.target, intent.money, intent.oil, intent.people)
	end

	if intent.kind == "embargo" then
		local t = m.nations[intent.target]
		if t == nil or intent.target == nationId then
			return false, "target"
		end
		local hadTrade = Diplomacy.hasTrade(m.diplo, nationId, intent.target)
		Diplomacy.setEmbargo(m.diplo, nationId, intent.target, intent.on, m.simTime)
		table.insert(m.events, { kind = "embargo", nation = nationId, target = intent.target, on = intent.on })
		if hadTrade and intent.on then
			table.insert(m.events, { kind = "tradeEnded", nation = nationId, target = intent.target })
		end
		return true, nil
	end

	if intent.kind == "vote" then
		return Council.vote(m.council, nationId, intent.option)
	end

	if intent.kind == "ping" then
		if intent.cell < 0 or intent.cell >= m.grid.size then
			return false, "focus"
		end
		local last = m.pingAt[nationId]
		if last ~= nil and m.time - last < Config.Pings.CooldownSec then
			return false, "pingCooldown"
		end
		m.pingAt[nationId] = m.time
		table.insert(m.events, { kind = "ping", nation = nationId, cell = intent.cell, phrase = intent.phrase })
		return true, nil
	end

	if intent.kind == "rebel" then
		if Council.active(m.council, "truce", m.simTime) ~= nil then
			return false, "truce"
		end
		local ok, reason = Diplomacy.canRebel(m.diplo, nationId, m.simTime)
		local overlord = Diplomacy.overlordOf(m.diplo, nationId)
		if not ok or overlord == nil then
			return false, reason
		end
		Diplomacy.free(m.diplo, nationId, m.simTime, true)
		table.insert(m.events, { kind = "independence", nation = nationId, target = overlord })
		if Wars.find(m.wars, nationId, overlord) == nil then
			MatchSim.declareWar(m, nationId, overlord)
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
local NO_BUILDINGS: Buildings.Owned = table.freeze({
	factories = 0,
	markets = 0,
	rigs = 0,
	forts = 0,
	ports = 0,
	airfields = 0,
	silos = 0,
	cityLevels = 0,
})

-- Здания и уровни городов державы (пересчитываются каждый тик и после постройки).
function MatchSim.ownedOf(m: Match, nationId: number): Buildings.Owned
	return m.owned[nationId] or NO_BUILDINGS
end

-- Работающие здания по видам (MatchSim.buildingsOf) — кеш на тик: боты спрашивают аэродромы на каждое
-- раздумье, а зданий на «Мире» сотни. Сбрасывается при пересчёте зданий (refreshOwned).
local buildingsCache: { [Match]: { tick: number, lists: { [string]: { { cell: number, owner: number } } } } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any
function MatchSim.clearBuildingsCache(m: Match)
	buildingsCache[m] = nil
end

function MatchSim.refreshOwned(m: Match)
	MatchSim.clearBuildingsCache(m) -- здания могли появиться или выйти из строя
	m.owned = Buildings.owned(m.buildings, m.grid, MatchSim.cities(m), function(cell: number): boolean
		return Air.isDisabled(m.air, cell, m.simTime)
	end)
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
MatchSim.totalPower = totalPower

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
	-- Батарея ПВО (сводная правка): свободная своя провинция, ближайшая к месту недавнего налёта на нас.
	local bombedAt, bombedCell = m.bombedAt[n.id], m.bombedCell[n.id]
	if bombedAt ~= nil and bombedCell ~= nil and m.simTime - bombedAt < Config.Air.BuildingDisableSec * 2 then
		local w = g.width
		local bx, by = bombedCell % w, bombedCell // w
		local r2 = Config.Buildings.AirDefense.radius ^ 2
		for _, b in MatchSim.buildingsOf(m, "AirDefense") do
			if b.owner == n.id and (b.cell % w - bx) ^ 2 + (b.cell // w - by) ^ 2 <= r2 then
				spots.batteryCovered = true
			end
		end
		local best = if spots.batteryCovered then -1 else r2 * 2
		for _, p in m.provinces.list do
			if Grid.getOwner(g, p.center) == n.id and m.buildings.byProvince[p.id] == nil then
				local d = (p.center % w - bx) ^ 2 + (p.center // w - by) ^ 2
				if d < best then
					spots.battery, best = p.center, d
				end
			end
		end
	end
	-- Прибрежная провинция под порт (§6.12): ближайшая к столице.
	local cap = n.capital
	local bestPort = math.huge
	for _, p in m.provinces.list do
		if m.sea.docks[p.id] ~= nil and Grid.getOwner(g, p.center) == n.id and m.buildings.byProvince[p.id] == nil then
			local d = if cap ~= nil
				then (p.center % g.width - cap % g.width) ^ 2 + (p.center // g.width - cap // g.width) ^ 2
				else 0
			if d < bestPort then
				spots.port, bestPort = p.center, d
			end
		end
	end
	-- Провинция под аэродром (§6.13): свободная, ближайшая к врагу (к первому, с кем активная война). Ищем только
	-- для тех, кто строит аэродромы (Агрессор, Хитрец, Генерал), и пока своего аэродрома нет.
	local enemyCapital: number? = nil
	local profile = profileOf(m, n.id)
	local wantsAirfield = (profile.personality.air >= 0.5 or profile.level.smartTarget)
		and MatchSim.ownedOf(m, n.id).airfields == 0
		and MatchSim.techAllows(m, n.id, "Airfield") -- «Авиация» (§6.14)
	local wars: { Wars.War } = if wantsAirfield then Wars.of(m.wars, n.id) else {}
	for _, war in wars do
		local enemy = m.nations[Wars.enemyOf(war, n.id)]
		if war.state == "active" and enemy ~= nil and enemy.capital ~= nil then
			enemyCapital = enemy.capital
			break
		end
	end
	if enemyCapital ~= nil then
		local ec = enemyCapital :: number
		local bestAir = math.huge
		for _, p in m.provinces.list do
			-- Не в пограничной с врагом провинции: там аэродром быстро возьмут (самолёты без аэродрома теряются).
			local frontier = false
			for _, q in p.neighbours do
				local o = Grid.getOwner(g, m.provinces.list[q].center)
				if o ~= 0 and o ~= n.id and Wars.isActive(m.wars, n.id, o) then
					frontier = true
					break
				end
			end
			if not frontier and Grid.getOwner(g, p.center) == n.id and m.buildings.byProvince[p.id] == nil then
				local d = (p.center % g.width - ec % g.width) ^ 2 + (p.center // g.width - ec // g.width) ^ 2
				if d < bestAir then
					spots.airfield, bestAir = p.center, d
				end
			end
		end
	end
	-- Самая нестабильная своя провинция ниже LowBelow (§6.10): укрепление в центре или улучшение города.
	local worst = Config.Stability.LowBelow
	for _, entry in Stability.provincesOf(m.stability, n.id) do
		if entry.value < worst then
			local p = m.provinces.list[entry.province]
			local city = m.cityOf[entry.province]
			local free = Grid.getOwner(g, p.center) == n.id and m.buildings.byProvince[p.id] == nil
			local upgradable = city ~= nil
				and Grid.getOwner(g, city) == n.id
				and Buildings.cityLevel(m.buildings, city) < Config.Economy.MaxCityLevel
			if free or upgradable then
				worst = entry.value
				spots.unstable = if free then p.center else nil
				spots.unstableCity = if upgradable then city else nil
			end
		end
	end
	return spots
end

-- Держава id «ослабла» для Хитреца (§8.1): воюет не с viewer и потеряла в этих войнах больше
-- Diplomacy.BetrayLossShare своих войск (потери / (потери + что осталось)).
local function weakenedElsewhere(m: Match, id: number, viewer: number): boolean
	local lost = 0
	local fighting = false
	for _, war in Wars.of(m.wars, id) do
		if Wars.enemyOf(war, id) ~= viewer then
			fighting = true
			lost += if war.a == id then war.lossesA else war.lossesB
		end
	end
	if not fighting or lost <= 0 then
		return false
	end
	return lost / (lost + totalPower(m, id)) > Config.Diplomacy.BetrayLossShare
end
MatchSim.weakenedElsewhere = weakenedElsewhere

local function botView(m: Match, n: Nation): BotBrain.BotView
	local g = m.grid
	local adjacent = Grid.adjacentOwners(g, n.id)
	-- Города соседей: сколько и какой ближе всего к нашей столице (направление удара Генерала).
	local nearCity: { [number]: number } = {}
	local nearDist: { [number]: number } = {}
	local cityCount: { [number]: number } = {}
	local cap = n.capital
	local cx, cy = if cap ~= nil then cap % g.width else 0, if cap ~= nil then cap // g.width else 0
	for _, cell in m.cityOf do
		local o = Grid.getOwner(g, cell)
		if o ~= 0 and o ~= n.id and adjacent[o] ~= nil then
			cityCount[o] = (cityCount[o] or 0) + 1
			local dx, dy = cell % g.width - cx, cell // g.width - cy
			local d = dx * dx + dy * dy
			if nearDist[o] == nil or d < nearDist[o] then
				nearCity[o], nearDist[o] = cell, d
			end
		end
	end
	-- Провинция соседа у нашей границы (не со столицей) — что можно потребовать (§8.1).
	local demandOf: { [number]: number } = {}
	for _, p in m.provinces.list do
		local o = Grid.getOwner(g, p.center)
		if o ~= 0 and o ~= n.id and adjacent[o] ~= nil and demandOf[o] == nil then
			local other = m.nations[o]
			local capital = if other ~= nil then other.capital else nil
			if capital == nil or MapData.getProvince(m.map, capital) ~= p.id then
				for _, q in p.neighbours do
					if Grid.getOwner(g, m.provinces.list[q].center) == n.id then
						demandOf[o] = p.id
						break
					end
				end
			end
		end
	end
	local ds = m.diplo
	local myLord = Diplomacy.overlordOf(ds, n.id)
	local neighbours: { BotBrain.Neighbour } = {}
	for owner, border in adjacent do
		if owner ~= 0 then
			local other = m.nations[owner]
			if other ~= nil and other.alive then
				-- Отвлечён: уже воюет с кем-то, кроме нас.
				local distracted = false
				for _, war in Wars.of(m.wars, owner) do
					if Wars.enemyOf(war, owner) ~= n.id then
						distracted = true
					end
				end
				local t = Diplomacy.treaty(ds, n.id, owner)
				local treaty: ("pact" | "alliance" | "vassal" | "overlord")? = if t ~= nil
					then t.kind
					elseif myLord == owner then "overlord"
					elseif Diplomacy.overlordOf(ds, owner) == n.id then "vassal"
					else nil
				table.insert(neighbours, {
					id = owner,
					people = other.people,
					power = Forces.total(other.home),
					frontPower = Forces.total(MatchSim.frontForces(m, owner)),
					atWar = Wars.isActive(m.wars, n.id, owner),
					-- С партнёром по договору и в вассалитете обычной войны нет (предательство — отдельное решение).
					canDeclare = treaty == nil and (Wars.canDeclare(m.wars, n.id, owner, m.simTime)),
					treaty = treaty,
					traitor = Diplomacy.isTraitor(ds, owner, m.simTime),
					demandProvince = demandOf[owner],
					trade = Diplomacy.hasTrade(ds, n.id, owner),
					weakened = weakenedElsewhere(m, owner, n.id),
					embargo = Diplomacy.embargoed(ds, n.id, owner),
					border = border,
					share = Grid.cellsOf(g, owner) / math.max(1, g.capturableCount),
					distracted = distracted,
					mix = Forces.composition(other.home),
					city = nearCity[owner],
					cities = cityCount[owner] or 0,
				})
			end
		end
	end
	-- Враги союзников (вступить в их войну) и лидер к победе (союз против него).
	local allyEnemies: { number } = {}
	local alliesAtWar: { number } = {}
	for _, ally in Diplomacy.alliesOf(ds, n.id) do
		if #Wars.of(m.wars, ally) > 0 then
			table.insert(alliesAtWar, ally)
		end
		for _, war in Wars.of(m.wars, ally) do
			local enemy = Wars.enemyOf(war, ally)
			if enemy ~= n.id and table.find(allyEnemies, enemy) == nil then
				table.insert(allyEnemies, enemy)
			end
		end
	end
	local leader: number? = nil
	local leaderCells = g.capturableCount * Config.Bots.StopLeaderShare
	for _, other in m.nations do
		if other.alive and other.id ~= n.id and Grid.cellsOf(g, other.id) >= leaderCells then
			leader, leaderCells = other.id, Grid.cellsOf(g, other.id)
		end
	end
	local fronts: { BotBrain.FrontView } = {}
	for _, a in m.attacks do
		if a.attacker == n.id then
			table.insert(fronts, {
				target = a.target,
				ratio = a.ratio,
				supplied = a.supplied,
				fighting = a.fighting,
				stalledSec = m.simTime - a.lastAdvance,
				power = Forces.total(a.forces),
			})
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
	-- Ничья земля «рядом», если её можно взять: обычные клетки — людьми, ничейный город — войсками.
	local hasNeutral = Expansion.hasFrontier(m.grid, n.id, 0, false)
		or (Forces.total(n.home) >= Config.Combat.NeutralCityGarrison and Expansion.hasFrontier(m.grid, n.id, 0, true))
	return {
		people = n.people,
		maxPeople = MatchSim.maxPeopleOf(m, n.id),
		attacks = attacksOf(m, n.id),
		queue = #n.queue,
		power = Forces.total(n.home),
		totalPower = totalPower(m, n.id),
		hasCapital = n.capital ~= nil,
		-- Ничья земля «рядом», если её можно взять: обычные клетки — людьми, ничейный город — войсками.
		hasNeutral = hasNeutral,
		neighbours = neighbours,
		wars = wars,
		fronts = fronts,
		mix = Forces.composition(n.home),
		time = m.simTime,
		allies = #Diplomacy.alliesOf(ds, n.id),
		allyEnemies = allyEnemies,
		overlord = myLord,
		overlordPower = if myLord ~= nil then totalPower(m, myLord) else nil,
		canRebel = (Diplomacy.canRebel(ds, n.id, m.simTime)),
		leader = leader,
		tradeDeals = Diplomacy.tradeCount(ds, n.id),
		alliesAtWar = alliesAtWar,
		money = n.money,
		oil = n.oil,
		economy = m.economy[n.id] or { income = 0, oilIncome = 0, upkeep = 0 },
		owned = MatchSim.ownedOf(m, n.id),
		spots = buildSpots(m, n),
		stability = Stability.summaryOf(m.stability, n.id).average,
		navy = MatchSim.navyView(m, n, hasNeutral, neighbours),
		air = MatchSim.airView(m, n),
		tech = MatchSim.techView(m, n),
	}
end

-- Держава выбыла: войска гибнут, её клетки становятся ничьими, атаки на неё заканчиваются.
local function eliminate(m: Match, n: Nation, by: number)
	Diplomacy.removeNation(m.diplo, n.id)
	Stability.removeNation(m.stability, n.id)
	Tech.removeNation(m.tech, n.id)
	Commanders.removeNation(m.commanders, n.id)
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
function MatchSim.makePeace(m: Match, war: Wars.War, terms: Types.PeaceTerms, from: number?)
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
	-- Капитуляция: предложивший становится вассалом (каждый оставляет захваченное, §8.1).
	if terms == "capitulate" and from ~= nil then
		local overlord = Wars.enemyOf(war, from)
		Diplomacy.setVassal(m.diplo, from, overlord, m.simTime)
		table.insert(m.events, { kind = "vassal", nation = from, target = overlord })
	end
end

-- Перевод денег, нефти и людей (§8.2): нет войны и эмбарго, хватает своего, лимит за минуту;
-- налог сгорает (при «Свободной торговле» — нет).
function MatchSim.transfer(
	m: Match,
	from: number,
	to: number,
	money: number,
	oil: number,
	people: number
): (boolean, string?)
	local n, t = m.nations[from], m.nations[to]
	if n == nil or t == nil or not t.alive or from == to then
		return false, "target"
	end
	if Wars.find(m.wars, from, to) ~= nil then
		return false, "atWar"
	end
	if Diplomacy.embargoed(m.diplo, from, to) then
		return false, "embargo"
	end
	if money < 0 or oil < 0 or people < 0 or money + oil + people <= 0 then
		return false, "amount"
	end
	if money > n.money then
		return false, "noMoney"
	end
	if oil > n.oil then
		return false, "noOil"
	end
	if people > n.people then
		return false, "noTroops"
	end
	-- Лимит за скользящую минуту (часы матча).
	local log: { { at: number, money: number, oil: number, people: number } } = m.sent[from] or {}
	m.sent[from] = log
	local j = 1
	while j <= #log do
		if m.time - log[j].at >= 60 then
			table.remove(log, j)
		else
			j += 1
		end
	end
	local sumMoney, sumOil, sumPeople = money, oil, people
	for _, e in log do
		sumMoney += e.money
		sumOil += e.oil
		sumPeople += e.people
	end
	local limit = Config.Trade.LimitPerMinute
	if sumMoney > limit.money or sumOil > limit.oil or sumPeople > limit.people then
		return false, "tradeLimit"
	end
	table.insert(log, { at = m.time, money = money, oil = oil, people = people })
	local tax = if Council.active(m.council, "freeTrade", m.simTime) ~= nil then 0 else Config.Trade.TaxShare
	if MatchSim.teammates(m, from, to) then
		tax = math.min(tax, Config.Modes.TeamTaxShare)
	end
	local keep = 1 - tax
	n.money -= money
	n.oil -= oil
	n.people -= people
	t.money += money * keep
	t.oil += oil * keep
	t.people += people * keep
	table.insert(m.events, { kind = "transfer", nation = from, target = to, money = money, oil = oil, people = people })
	return true, nil
end

-- Объявление войны (§6.7а) с правилами договоров (§8.1): война партнёру по пакту или союзнику до конца
-- договора — предательство; союзникам жертвы — запись в ленту (боты-союзники вступают сами).
function MatchSim.declareWar(m: Match, a: number, b: number)
	-- Разрыв, который уже прошёл предупреждение, Diplomacy.update закроет в этом же тике.
	if Diplomacy.warIsBetrayal(m.diplo, a, b, m.simTime) then
		Diplomacy.betray(m.diplo, a, b, m.simTime)
		table.insert(m.events, { kind = "betrayal", nation = a, target = b })
	end
	-- Война рвёт торговое соглашение (§8.2).
	if Diplomacy.endTrade(m.diplo, a, b) then
		table.insert(m.events, { kind = "tradeEnded", nation = a, target = b })
	end
	Wars.declare(m.wars, a, b, m.simTime)
	table.insert(m.events, { kind = "warDeclared", nation = a, target = b })
	for _, ally in Diplomacy.alliesOf(m.diplo, b) do
		if ally ~= a then
			table.insert(m.events, { kind = "allyAttacked", nation = a, target = b, ally = ally })
		end
	end
end

-- Провинция, которую можно потребовать у target (§8.1): его центр, граничит с землёй from, без столицы target.
function MatchSim.demandable(m: Match, from: number, target: number, provinceId: number): (boolean, string?)
	local p = m.provinces.list[provinceId]
	if p == nil then
		return false, "province"
	end
	local g = m.grid
	if Grid.getOwner(g, p.center) ~= target then
		return false, "notTheirs"
	end
	local t = m.nations[target]
	if t ~= nil and t.capital ~= nil and MapData.getProvince(m.map, t.capital) == provinceId then
		return false, "capital"
	end
	for _, other in p.neighbours do
		if Grid.getOwner(g, m.provinces.list[other].center) == from then
			return true, nil
		end
	end
	return false, "notBorder"
end

-- Предложение договора или требование (§8.1).
function MatchSim.offer(
	m: Match,
	from: number,
	to: number,
	kind: Types.OfferKind,
	province: number?
): (boolean, string?)
	local t = m.nations[to]
	if t == nil or not t.alive then
		return false, "target"
	end
	if Wars.find(m.wars, from, to) ~= nil then
		return false, "atWar"
	end
	-- Частный сервер без дипломатии (§5.4): только война и мир.
	if not m.rules.diplomacy then
		return false, "diplomacyOff"
	end
	-- Команды (§5.1): союз и пакты — только своя команда (вечный союз уже есть), требовать у своих нельзя.
	if m.rules.teams and (kind ~= "trade" and (kind ~= "demand" or MatchSim.teammates(m, from, to))) then
		return false, "team"
	end
	local ok, reason = Diplomacy.canOffer(m.diplo, from, to, kind, m.simTime)
	if not ok then
		return false, reason
	end
	if kind == "demand" then
		if Council.active(m.council, "truce", m.simTime) ~= nil then
			return false, "truce"
		end
		if province == nil then
			return false, "province"
		end
		local can, why = MatchSim.demandable(m, from, to, province)
		if not can then
			return false, why
		end
		-- Отказ — война: требовать можно, только если войну можно объявить.
		local canWar, warWhy = Wars.canDeclare(m.wars, from, to, m.simTime)
		if not canWar then
			return false, warWhy
		end
	end
	Diplomacy.offer(m.diplo, from, to, kind, m.simTime, province)
	table.insert(m.events, { kind = "offerMade", nation = from, target = to, offer = kind, province = province })
	return true, nil
end

-- Провинция переходит от from к to целиком (с городом) — уступка по требованию.
local function cedeProvince(m: Match, provinceId: number, from: number, to: number): number
	local p = m.provinces.list[provinceId]
	if p == nil then
		return 0
	end
	local moved = 0
	for _, cell in p.cells do
		if Grid.getOwner(m.grid, cell) == from then
			Grid.setOwner(m.grid, cell, to)
			moved += 1
		end
	end
	return moved
end

-- Ответ на предложение (игрок, бот или истёк срок).
function MatchSim.resolveOffer(m: Match, offer: Diplomacy.Offer, accept: boolean, expired: boolean)
	Diplomacy.removeOffer(m.diplo, offer)
	local from, to = offer.from, offer.to
	local fromNation, toNation = m.nations[from], m.nations[to]
	if fromNation == nil or toNation == nil or not fromNation.alive or not toNation.alive then
		return
	end
	if accept then
		local kind: Types.OfferKind = offer.kind
		if kind == "demand" then
			local province = offer.province
			if province ~= nil and MatchSim.demandable(m, from, to, province) then
				cedeProvince(m, province, to, from)
				Diplomacy.note(m.diplo, "ceded", to, from, m.simTime)
			end
		elseif kind == "trade" then
			-- Те же проверки, что при предложении (без паузы между предложениями: оно уже сделано).
			if Diplomacy.canOffer(m.diplo, from, to, "trade", m.simTime + Config.Diplomacy.OfferRetrySec) then
				Diplomacy.signTrade(m.diplo, from, to, m.simTime)
			else
				accept = false
			end
		elseif kind == "alliance" then
			local max = Config.Match.MaxAlliesFfa
			if
				#Diplomacy.alliesOf(m.diplo, from) >= max
				or #Diplomacy.alliesOf(m.diplo, to) >= max
				or Wars.find(m.wars, from, to) ~= nil
			then
				accept = false
			else
				Diplomacy.sign(m.diplo, "alliance", from, to, m.simTime)
			end
		else
			if Wars.find(m.wars, from, to) ~= nil then
				accept = false
			else
				local minutes = if kind == "pact5"
					then Config.Diplomacy.PactMinutes[2]
					else Config.Diplomacy.PactMinutes[1]
				Diplomacy.sign(m.diplo, "pact", from, to, m.simTime, minutes)
			end
		end
		if accept then
			table.insert(
				m.events,
				{ kind = "offerAccepted", nation = to, target = from, offer = kind, province = offer.province }
			)
			return
		end
	end
	table.insert(m.events, { kind = "offerRefused", nation = to, target = from, offer = offer.kind, expired = expired })
	-- Требование отклонено — требующий объявляет войну.
	if offer.kind == "demand" and Wars.canDeclare(m.wars, from, to, m.simTime) then
		Diplomacy.note(m.diplo, "refused", to, from, m.simTime)
		MatchSim.declareWar(m, from, to)
	end
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

-- Ничейный город: войска атаки берут его, если могут оплатить гарнизон силой (у повстанцев он больше, §6.10).
local function neutralCityTaker(m: Match, a: Attack): ((cell: number) -> boolean)?
	if Forces.total(a.forces) <= 0 then
		return nil
	end
	return function(cell: number): boolean
		local rebel = Stability.isRebel(m.stability, MapData.getProvince(m.map, cell))
		local garrison = if rebel then Config.Stability.RebelGarrison else Config.Combat.NeutralCityGarrison
		if Forces.total(a.forces) < garrison then
			return false
		end
		Forces.applyDamage(a.forces, garrison)
		return true
	end
end

-- Шаг атак и фронтов на simDt игровых секунд. Возвращает число захваченных клеток.
-- Поток случайных чисел боя пары атакующий → цель (§12): разброс урона одного фронта не сдвигает другие.
local function battleRng(m: Match, a: Attack): Rng
	local key = a.attacker * 65536 + a.target
	local r = m.battleRngs[key]
	if r == nil then
		r = Rng.stream(m.seed, 300 + a.attacker, a.target)
		m.battleRngs[key] = r
	end
	return r
end

local function stepAttacks(m: Match, simDt: number): number
	local g = m.grid
	local cities = MatchSim.cities(m)
	local captured = 0

	-- Фронты против держав: длины фронтов нужны, чтобы делить гарнизон защитника.
	-- Линии берём из кеша (Expansion.FrontCache): он обновляется по сменившим владельца клеткам, а не обходом
	-- всей границы атакующего каждый тик.
	local cache = m.frontCache
	Expansion.syncCache(cache, g)
	local fronts: { [Attack]: Expansion.FrontLine } = {}
	local frontLength: { [number]: number } = {}
	for _, a in m.attacks do
		if a.target ~= 0 then
			local front = Expansion.line(cache, g, a.attacker, a.target, true, m.map, m.tick)
			local list = front.list
			fronts[a] = front
			-- Выборка линии фронта для тумана (§6.11): сервер шлёт чужой фронт, только если он в обзоре.
			local line: { number } = {}
			local stride = math.max(1, math.ceil(#list / Config.Fog.LineSamples))
			for j = 1, #list, stride do
				table.insert(line, list[j])
			end
			a.line = line
			frontLength[a.target] = (frontLength[a.target] or 0) + #list
		end
	end
	local record = recordCapture(m)

	-- Ничья земля повстанцев дороже для границы людей (§6.10).
	local rebelCost: ((cell: number) -> number)? = nil
	if next(m.stability.rebels) ~= nil then
		rebelCost = function(cell: number): number
			return if Stability.isRebel(m.stability, MapData.getProvince(m.map, cell))
				then Config.Stability.RebelCellCostMul
				else 1
		end
	end
	local battled: { [Attack]: boolean } = {}
	local truce = Council.active(m.council, "truce", m.simTime) ~= nil
	local k = 1
	while k <= #m.attacks do
		local a = m.attacks[k]
		local done = false
		if truce and a.target ~= 0 then
			-- Всеобщее перемирие (§8.2): фронты против держав стоят — без боя и захвата.
			k += 1
			continue
		end
		if a.target == 0 then
			local cityAllowed = neutralCityTaker(m, a)
			Expansion.syncCache(cache, g) -- захваты этого тика (прежние атаки) уже в линии
			local line = Expansion.line(cache, g, a.attacker, 0, cityAllowed ~= nil, nil, m.tick)
			-- Прорыв (§6.15): наступление на ничью землю тоже быстрее.
			local d, cells =
				Expansion.advance(m.map, g, m.nations, a, m.tick, m.seed, simDt * MatchSim.surgeMul(m, a.attacker), {
					cityAllowed = cityAllowed,
					canTake = enclaveRule(m, a.attacker),
					record = record,
					costMul = rebelCost,
				}, line)
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
				-- Снабжают свои города и города союзников, вассалов и сюзерена (§8.1).
				local landSupplied = Fronts.supplied(
					g,
					cities,
					a.attacker,
					front.list,
					Diplomacy.friends(m.diplo, a.attacker),
					if Tech.has(m.tech, a.attacker, "Army", 2) then Config.Tech.SupplyRangeMul else 1
				) and fromAtkPocket * 2 <= #front.list
				-- Снабжение по морю (§6.12): рядом с линией фронта берег, до которого недалеко от своего порта.
				if not landSupplied and (a.seaCheckedAt == nil or m.simTime - (a.seaCheckedAt :: number) >= 1) then
					a.seaCheckedAt = m.simTime
					local sets = MatchSim.seaSupplySets(m, a.attacker)
					local sea = false
					local line: { number } = a.line or {}
					for _, cell in line do
						if Naval.nearCoast(m.sea, cell, Config.Naval.SeaSupplyNear, sets) then
							sea = true
							break
						end
					end
					a.seaSupplied = sea
				end
				a.supplied = landSupplied or a.seaSupplied == true
				local homeShare = #front.list / totalLen * (1 - inDefPocket / #front.list)
				-- Укреплённая линия: фронт долго стоит — защитнику бонус (§6.9).
				local still = m.simTime - a.lastAdvance >= Config.Fortify.AfterSec
				local function fortified(cell: number): boolean
					local spot = m.buildings.byProvince[MapData.getProvince(m.map, cell)]
					return Buildings.fortified(m.buildings, g, m.map, cell)
						and not (spot ~= nil and Air.isDisabled(m.air, spot, m.simTime))
				end
				-- Встречные фронты пары — один бой: потери считаются один раз за тик.
				local applyLosses = not (counter ~= nil and battled[counter])
				local result = Fronts.battle(
					a,
					{
						home = defender.home,
						share = homeShare,
						counter = if counter ~= nil then counter.forces else nil,
						bonus = (if still then Config.Fortify.LineBonus else 1) * MatchSim.abilityDefenseMul(m, a),
						armor = if Tech.has(m.tech, a.target, "Army", 4) then Config.Tech.TankArmor else nil, -- Войска-4 (сводная правка)
					},
					Fronts.terrainDefense(m.map, front.list, front.river, fortified),
					battleRng(m, a),
					simDt,
					applyLosses
				)
				battled[a] = true
				a.ratio = result.ratio
				a.fighting = result.fighting
				Wars.addLosses(war, a.attacker, result.lostAttacker)
				Wars.addLosses(war, a.target, result.lostDefender)
				local mul = Fronts.advanceMul(a, result.ratio)
					* MatchSim.surgeMul(m, a.attacker)
					* MatchSim.openingMul(m, war, a.attacker)
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
	Expansion.pruneCache(cache, m.tick)
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
				}, profileOf(m, me))
				if accept then
					MatchSim.makePeace(m, war, p.terms, p.from)
				else
					table.insert(m.events, { kind = "peaceRejected", nation = me, target = p.from, expired = false })
				end
			end
		end
	end
end

-- Что бот знает, голосуя в Совете: лидер ли он, проигрывает ли войну, в хвосте ли по суше.
local function councilView(m: Match, id: number, options: { Types.Resolution }): BotBrain.CouncilView
	local g = m.grid
	local mine = Grid.cellsOf(g, id)
	local leader, leaderCells, below = 0, -1, 0
	for _, other in m.nations do
		if other.alive then
			local cells = Grid.cellsOf(g, other.id)
			if cells > leaderCells then
				leader, leaderCells = other.id, cells
			end
			if other.id ~= id and cells < mine then
				below += 1
			end
		end
	end
	local losing = false
	for _, war in Wars.of(m.wars, id) do
		local enemy = Wars.enemyOf(war, id)
		if totalPower(m, id) < totalPower(m, enemy) then
			losing = true
		end
	end
	return {
		options = options,
		isLeader = leader == id,
		losingWar = losing,
		inTail = below < Config.Council.AidCount,
	}
end

-- Резолюция Совета вступает в силу.
function MatchSim.applyResolution(m: Match, kind: Types.Resolution)
	local cfg = Config.Council
	local now = m.simTime
	local target: number? = nil
	if kind == "sanctions" then
		local best = -1
		for _, n in m.nations do
			if n.alive and Grid.cellsOf(m.grid, n.id) > best then
				target, best = n.id, Grid.cellsOf(m.grid, n.id)
			end
		end
		Council.addActive(m.council, kind, now + cfg.SanctionsSec, target)
	elseif kind == "truce" then
		Council.addActive(m.council, kind, now + cfg.TruceSec)
	elseif kind == "freeTrade" then
		Council.addActive(m.council, kind, now + cfg.FreeTradeSec)
	elseif kind == "superweaponBan" then
		Council.addActive(m.council, kind, now + cfg.SuperweaponBanSec)
	elseif kind == "aid" then
		local alive: { Nation } = {}
		for _, n in m.nations do
			if n.alive then
				table.insert(alive, n)
			end
		end
		table.sort(alive, function(a: Nation, b: Nation): boolean
			local ca, cb = Grid.cellsOf(m.grid, a.id), Grid.cellsOf(m.grid, b.id)
			if ca ~= cb then
				return ca < cb
			end
			return a.id < b.id
		end)
		for k = 1, math.min(cfg.AidCount, #alive) do
			alive[k].money += cfg.AidMoney
		end
	end
	table.insert(m.events, { kind = "resolution", resolution = kind, target = target })
end

-- Совет держав (§8.2): открыть голосование (боты голосуют сразу), закрыть и применить резолюцию.
local function stepCouncil(m: Match)
	for _, c in Council.update(m.council, m.simTime, m.councilRng) do
		if c.kind == "opened" then
			table.insert(m.events, { kind = "councilOpened", options = c.vote.options })
			for _, n in m.nations do
				if n.alive and n.isBot then
					local option = BotBrain.councilVote(councilView(m, n.id, c.vote.options), profileOf(m, n.id))
					Council.vote(m.council, n.id, option)
				end
			end
		else
			local winner: Types.Resolution? = (c :: any).winner
			table.insert(m.events, { kind = "councilClosed", winner = winner, votes = (c :: any).votes })
			if winner ~= nil then
				MatchSim.applyResolution(m, winner)
			end
		end
	end
end

-- Бот решает, принять ли предложение или требование (§8.1).
local function botAnswersOffer(m: Match, offer: Diplomacy.Offer): boolean
	if m.rules.tutorial and offer.kind == "alliance" then
		return true -- обучение (§5.5): бот соглашается на союз
	end
	local g = m.grid
	local leaderCells = g.capturableCount * Config.Bots.StopLeaderShare
	local threat = false
	for _, other in m.nations do
		if
			other.alive
			and other.id ~= offer.to
			and other.id ~= offer.from
			and Grid.cellsOf(g, other.id) >= leaderCells
		then
			threat = true
		end
	end
	return BotBrain.answerOffer({
		kind = offer.kind,
		myPower = totalPower(m, offer.to),
		fromPower = totalPower(m, offer.from),
		fromTraitor = Diplomacy.isTraitor(m.diplo, offer.from, m.simTime),
		fromIsLeader = Grid.cellsOf(g, offer.from) >= leaderCells,
		threat = threat,
		atWarElsewhere = #Wars.of(m.wars, offer.to) > 0,
		allies = #Diplomacy.alliesOf(m.diplo, offer.to),
	}, profileOf(m, offer.to))
end

-- Договоры (§8.1): сроки, разрывы, просроченные предложения; боты отвечают на предложения.
local function stepDiplomacy(m: Match)
	for _, c in Diplomacy.update(m.diplo, m.simTime) do
		if c.kind == "broken" then
			local t = c.treaty
			local breaker = t.breaker or t.a
			table.insert(m.events, {
				kind = "treatyBroken",
				nation = breaker,
				target = if t.a == breaker then t.b else t.a,
				treaty = t.kind,
				betrayal = c.betrayal,
			})
		elseif c.kind == "expired" then
			table.insert(m.events, { kind = "treatyExpired", nation = c.treaty.a, target = c.treaty.b })
		elseif c.kind == "offerExpired" then
			MatchSim.resolveOffer(m, c.offer, false, true)
		end
	end
	for _, offer in table.clone(m.diplo.offers) do
		local bot = m.nations[offer.to]
		if bot ~= nil and bot.isBot and m.simTime >= offer.madeAt + Config.War.BotReplyDelaySec then
			MatchSim.resolveOffer(m, offer, botAnswersOffer(m, offer), false)
		end
	end
end

-- Деньги и нефть державы за simDt (§6.8): доход, вышки, содержание войск; денег нет — войска тают.
local function stepEconomy(m: Match, n: Nation, simDt: number)
	local owned = MatchSim.ownedOf(m, n.id)
	local strength = Forces.total(n.home) + Forces.total(MatchSim.frontForces(m, n.id))
	-- Провинции ниже Stability.LowBelow дают меньше дохода (§6.10): их клетки и города — с множителем.
	local unrest = Stability.summaryOf(m.stability, n.id)
	local cut = 1 - Config.Stability.LowIncomeMul
	local cells = Grid.cellsOf(m.grid, n.id) - unrest.lowCells * cut
	local cityLevels = owned.cityLevels - unrest.lowCityLevels * cut
	local e: NationEconomy = {
		-- Генералу +10% дохода — единственное послабление ботам (§9).
		income = Economy.income(math.max(0, cells), math.max(0, cityLevels), owned.markets)
			* (1 + (if n.isBot then profileOf(m, n.id).level.incomeBonus else 0)),
		oilIncome = Economy.oilIncome(owned.rigs),
		upkeep = Economy.upkeep(strength),
	}
	-- Технологии (§6.14): «Налоги» — доход, «Нефтедобыча» — нефть, «Торговые пути» — бонус соглашений.
	if Tech.has(m.tech, n.id, "Economy", 1) then
		e.income *= 1 + Config.Tech.TaxBonus
	end
	if Tech.has(m.tech, n.id, "Economy", 2) then
		e.oilIncome *= 1 + Config.Tech.OilBonus
	end
	local tradeBonus = Config.Trade.AgreementIncome
		* (if Tech.has(m.tech, n.id, "Economy", 3) then Config.Tech.TradeMul else 1)
	-- Торговые соглашения +5% каждое, санкции Совета −25% (§8.2).
	e.income *= 1 + tradeBonus * Diplomacy.tradeCount(m.diplo, n.id)
	e.income *= MatchSim.perksOf(m, n.id).incomeMul -- «Штаб» (§11.1)
	local sanctions = Council.active(m.council, "sanctions", m.simTime)
	if sanctions ~= nil and sanctions.target == n.id then
		e.income *= Config.Council.SanctionsIncomeMul
	end
	-- Вассал отдаёт долю дохода сюзерену (§8.1); в доходе вассала — уже без дани.
	local overlord = Diplomacy.overlordOf(m.diplo, n.id)
	local lord = if overlord ~= nil then m.nations[overlord] else nil
	if lord ~= nil and lord.alive then
		local tribute = e.income * Config.Diplomacy.VassalTribute
		e.income -= tribute
		lord.money += tribute * simDt
	end
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
				if
					not pocket.hasCity
					and m.simTime - pocket.since >= Config.Pocket.SurrenderSec
					and not MatchSim.pocketSeaSupplied(m, n.id, pocket.cells)
				then
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

-- Цена наземного юнита (индекс kind) в деньгах: Маршал (§6.15) — танки дешевле.
function MatchSim.unitCost(m: Match, nationId: number, kind: number): number
	local cost = Forces.stats(kind).cost
	if Types.LandUnits[kind] == "Tanks" then
		cost *= Commanders.tankCostMul(Commanders.of(m.commanders, nationId))
	end
	return cost
end

-- Сколько юнитов очереди найма готовится одновременно: 1 + свои заводы + уровни городов / CityLevelsPerLine,
-- не больше Forces.MaxRecruitLines.
function MatchSim.recruitLines(m: Match, nationId: number): number
	local cfg = Config.Forces
	local owned = MatchSim.ownedOf(m, nationId)
	return math.min(cfg.MaxRecruitLines, 1 + owned.factories + owned.cityLevels // cfg.CityLevelsPerLine)
		+ MatchSim.perksOf(m, nationId).recruitLines -- «Штаб» (§11.1)
end

-- Технологии (§6.14, этап 7в-1) ---------------------------------------------------------------

-- Открыто ли державе здание kind технологией (Config.Tech.Unlocks; остальные здания — всегда).
function MatchSim.techAllows(m: Match, nationId: number, kind: Types.BuildingKind): boolean
	if kind == "MissileSilo" and m.rules.siloFree then
		return true -- «Супероружие» (§5.1)
	end
	local need = (Config.Tech.Unlocks :: any)[kind]
	return need == nil or Tech.has(m.tech, nationId, need.branch, need.level)
end

-- Цена корабля в деньгах с «Верфями» (Флот-1).
function MatchSim.shipCost(m: Match, nationId: number, kind: Types.ShipKind): number
	local cost = Fleet.stats(kind).cost
	if Tech.has(m.tech, nationId, "Fleet", 1) then
		cost *= 1 - Config.Tech.ShipyardDiscount
	end
	return cost * Commanders.shipCostMul(Commanders.of(m.commanders, nationId)) -- Адмирал (§6.15)
end

-- Технологии глазами бота: уровни веток и идёт ли исследование.
function MatchSim.techView(m: Match, n: Nation): BotBrain.TechView
	local r = m.tech.research[n.id]
	return {
		Army = Tech.level(m.tech, n.id, "Army"),
		Economy = Tech.level(m.tech, n.id, "Economy"),
		Fleet = Tech.level(m.tech, n.id, "Fleet"),
		researching = r ~= nil,
	}
end

-- Генералы (§6.15, этап 7в-2) ----------------------------------------------------------------

-- Касается ли линия фронта (выборка a.line) круга r вокруг клетки cell.
local function lineTouches(m: Match, a: Attack, cell: number, r: number): boolean
	local line = a.line
	if line == nil then
		return false
	end
	local w = m.grid.width
	local cx, cy = cell % w, cell // w
	local r2 = r * r
	for _, c in line :: { number } do
		local dx, dy = c % w - cx, c // w - cy
		if dx * dx + dy * dy <= r2 then
			return true
		end
	end
	return false
end

-- Расстояние «ref» (клеток на ширине 512) на этой карте.
local function refCells(m: Match, cells: number): number
	return cells * m.grid.width / Config.UnitsReferenceMapWidth
end

-- Множитель обороны защитника фронта a от способностей генералов: авиаудар врага (×StrikeDefenseMul),
-- укрепрайон защитника (×FortMul).
function MatchSim.abilityDefenseMul(m: Match, a: Attack): number
	local st = m.commanders
	if (#st.strikes == 0 and #st.forts == 0) or a.line == nil then
		return 1
	end
	local cfg = Config.Commanders
	local mul = 1
	for _, s in st.strikes do
		if
			(s.owner == a.attacker or Diplomacy.friends(m.diplo, a.attacker)[s.owner])
			and Wars.isActive(m.wars, s.owner, a.target)
			and lineTouches(m, a, s.cell, cfg.StrikeRadius)
		then
			mul *= cfg.StrikeDefenseMul
			break
		end
	end
	for _, f in st.forts do
		if f.owner == a.target then
			for _, c in a.line :: { number } do
				if MapData.getProvince(m.map, c) == f.province then
					mul *= cfg.FortMul
					break
				end
			end
		end
	end
	return mul
end

-- Свои фронты идут быстрее (Прорыв).
function MatchSim.surgeMul(m: Match, id: number): number
	return if Commanders.surging(m.commanders, id, m.simTime) then Config.Commanders.SurgeMul else 1
end

-- «Первый удар» (§15б): объявивший войну первые Combat.OpeningSec после мобилизации наступает быстрее.
function MatchSim.openingMul(m: Match, war: Wars.War, attacker: number): number
	local cfg = Config.Combat
	if war.a == attacker and war.state == "active" and m.simTime - war.activeAt < cfg.OpeningSec then
		return cfg.OpeningSpeedMul
	end
	return 1
end

-- Видно ли державе всю карту (Радарная вспышка).
function MatchSim.revealing(m: Match, id: number): boolean
	return Commanders.revealing(m.commanders, id, m.simTime)
end

-- Чужая клетка суши, куда можно высадиться: ничья или врага (война идёт).
local function landable(m: Match, id: number, cell: number): boolean
	local g = m.grid
	if cell < 0 or cell >= g.size or not Grid.isCapturable(g, cell) then
		return false
	end
	local o = Grid.getOwner(g, cell)
	return o ~= id and (o == 0 or Wars.isActive(m.wars, id, o))
end

-- Авиаудар по клетке at (способность Маршала, платная часть «Авиаудар», §6.15, §11.3): в круге StrikeRadius должна быть
-- земля врага в войне; его фронты, касающиеся круга, теряют долю loss силы (ПВО в составе снижает).
function MatchSim.strikeAt(m: Match, n: Nation, at: number, loss: number): (boolean, string?)
	local cfg = Config.Commanders
	local g = m.grid
	local w = g.width
	if at < 0 or at >= g.size then
		return false, "focus"
	end
	local r = cfg.StrikeRadius
	local enemy = false
	for dy = -r, r do
		for dx = -r, r do
			local x, y = at % w + dx, at // w + dy
			if x >= 0 and y >= 0 and x < w and y < g.height and dx * dx + dy * dy <= r * r then
				local o = Grid.getOwner(g, y * w + x)
				if o ~= 0 and o ~= n.id and Wars.isActive(m.wars, n.id, o) then
					enemy = true
				end
			end
		end
	end
	if not enemy then
		return false, "noEnemy"
	end
	for _, a in m.attacks do
		if
			a.target ~= 0
			and a.attacker ~= n.id
			and Wars.isActive(m.wars, n.id, a.attacker)
			and lineTouches(m, a, at, r)
		then
			local mul = 1 - Air.aaReduction(Forces.composition(a.forces))
			Forces.applyDamage(a.forces, Forces.total(a.forces) * loss * mul)
		end
	end
	table.insert(m.commanders.strikes, { owner = n.id, cell = at, untilTime = m.simTime + cfg.StrikeSec })
	return true, nil
end

-- Применить способность слота slot (1 — Q, 2 — E). percent — доля войск для десантов.
function MatchSim.useAbility(m: Match, n: Nation, slot: number, cell: number?, percent: number?): (boolean, string?)
	local st = m.commanders
	local cfg = Config.Commanders
	if slot ~= 1 and slot ~= 2 then
		return false, "?"
	end
	if Commanders.left(st, n.id, slot, m.simTime) > 0 then
		return false, "cooldown"
	end
	local ability = Commanders.ability(Commanders.of(st, n.id), slot)
	local g = m.grid
	local w = g.width
	if Commanders.needsTarget(ability) and (cell == nil or cell < 0 or cell >= g.size) then
		return false, "focus"
	end
	local at = cell or 0
	local victim = if cell ~= nil then Grid.getOwner(g, at) else 0
	local share = math.clamp(percent or 0.5, 0, 1)
	local function inCircle(c: number, r: number): boolean
		local dx, dy = c % w - at % w, c // w - at // w
		return dx * dx + dy * dy <= r * r
	end

	if ability == "Airstrike" then
		local ok, why = MatchSim.strikeAt(m, n, at, cfg.StrikeLoss)
		if not ok then
			return false, why
		end
	elseif ability == "Surge" then
		st.surgeUntil[n.id] = m.simTime + cfg.SurgeSec
	elseif ability == "SeaLanding" or ability == "Airdrop" then
		if not landable(m, n.id, at) then
			return false, "target"
		end
		if ability == "SeaLanding" and Naval.waterNear(m.sea, at, 2) == nil then
			return false, "notCoast"
		end
		local cargo: Types.Forces
		if ability == "SeaLanding" then
			cargo = Forces.take(n.home, share)
		else
			-- Воздушный десант: пехота гарнизона, не больше AirdropShare.
			local inf = Forces.kindIndex("Infantry") :: number
			local squad = n.home[inf]
			local amount = squad.strength * math.min(share, cfg.AirdropShare)
			cargo = Forces.new()
			Forces.add(cargo, inf, amount, squad.xp)
			squad.strength -= amount
		end
		if Forces.total(cargo) < Config.Forces.MinFrontStrength then
			Forces.merge(n.home, cargo)
			return false, "noTroops"
		end
		local r = if ability == "SeaLanding" then Config.Naval.BeachheadRadius else cfg.AirdropRadius
		MatchSim.landAt(m, n.id, at, cargo, 0, r)
	elseif ability == "Blockade" then
		local r = refCells(m, cfg.BlockadeRadius)
		local hit = 0
		for _, p in MatchSim.buildingsOf(m, "Port") do
			if p.owner ~= n.id and Wars.isActive(m.wars, n.id, p.owner) and inCircle(p.cell, r) then
				m.air.disabled[p.cell] = m.simTime + cfg.BlockadeSec
				hit += 1
			end
		end
		if hit == 0 then
			return false, "noEnemy"
		end
		m.air.version += 1
		MatchSim.refreshOwned(m)
	elseif ability == "Reveal" then
		st.revealUntil[n.id] = m.simTime + cfg.RevealSec
	elseif ability == "Propaganda" then
		local r = refCells(m, cfg.PropagandaRadius)
		local hit = 0
		for p, s in m.stability.provinces do
			local province = m.provinces.list[p]
			if
				province ~= nil
				and s.owner ~= 0
				and s.owner ~= n.id
				and Wars.isActive(m.wars, n.id, s.owner)
				and inCircle(province.center, r)
			then
				s.value = math.max(0, s.value - cfg.PropagandaLoss)
				hit += 1
			end
		end
		if hit == 0 then
			return false, "noEnemy"
		end
	elseif ability == "Fortify" then
		if victim ~= n.id then
			return false, "notOwner"
		end
		table.insert(
			st.forts,
			{ owner = n.id, province = MapData.getProvince(m.map, at), untilTime = m.simTime + cfg.FortSec }
		)
	end
	Commanders.use(st, n.id, slot, m.simTime)
	table.insert(m.events, {
		kind = "ability",
		nation = n.id,
		ability = ability,
		cell = cell,
		target = if victim ~= n.id then victim else 0,
	})
	return true, nil
end

-- Бот применяет способность (во время войны, со своим шансом). Цели — по ситуации на фронтах.
local function botAbility(m: Match, n: Nation, profile: BotBrain.Profile, rng: Rng)
	local cfg = Config.Commanders
	local enemies = Wars.of(m.wars, n.id)
	local active: { number } = {}
	for _, war in enemies do
		if war.state == "active" then
			table.insert(active, Wars.enemyOf(war, n.id))
		end
	end
	if #active == 0 then
		return
	end
	local chance = cfg.BotChance * (if profile.level.randomTarget then 0.3 else 1)
	if Rng.nextFloat(rng) >= chance then
		return
	end
	local isEnemy: { [number]: boolean } = {}
	for _, e in active do
		isEnemy[e] = true
	end
	-- Линии фронтов: свои против врага и врага против нас.
	local mine: { Attack } = {}
	local theirs: { Attack } = {}
	for _, a in m.attacks do
		if a.line ~= nil and #(a.line :: { number }) > 0 then
			if a.attacker == n.id and isEnemy[a.target] then
				table.insert(mine, a)
			elseif a.target == n.id and isEnemy[a.attacker] then
				table.insert(theirs, a)
			end
		end
	end
	local function lineCell(list: { Attack }): number?
		if #list == 0 then
			return nil
		end
		local a = list[Rng.range(rng, 1, #list)]
		local line = a.line :: { number }
		return line[Rng.range(rng, 1, #line)]
	end
	local function enemyCity(coastal: boolean): number?
		local best: number? = nil
		local bestD = math.huge
		local cap = n.capital or 0
		local w = m.grid.width
		for _, c in m.cityOf do
			local o = Grid.getOwner(m.grid, c)
			if isEnemy[o] and (not coastal or Naval.waterNear(m.sea, c, 2) ~= nil) then
				local d = (c % w - cap % w) ^ 2 + (c // w - cap // w) ^ 2
				if d < bestD then
					best, bestD = c, d
				end
			end
		end
		return best
	end
	for _, slot in { 1, 2 } do
		if Commanders.left(m.commanders, n.id, slot, m.simTime) <= 0 then
			local ability = Commanders.ability(Commanders.of(m.commanders, n.id), slot)
			local cell: number? = nil
			local percent: number? = nil
			if ability == "Airstrike" or ability == "Propaganda" then
				cell = lineCell(mine) or lineCell(theirs)
			elseif ability == "Surge" then
				cell = if #mine > 0 then -1 else nil
			elseif ability == "Reveal" then
				cell = -1
			elseif ability == "Fortify" then
				local c = lineCell(theirs)
				cell = if c ~= nil and Grid.getOwner(m.grid, c) == n.id then c else nil
			elseif ability == "Blockade" then
				for _, p in MatchSim.buildingsOf(m, "Port") do
					if isEnemy[p.owner] then
						cell = p.cell
						break
					end
				end
			elseif ability == "SeaLanding" then
				cell = enemyCity(true)
				percent = cfg.BotLandPercent
			elseif ability == "Airdrop" then
				cell = enemyCity(false)
				percent = 1
			end
			if cell ~= nil then
				local target = if cell >= 0 then cell else nil
				-- Десант — рядом с городом врага (сам город плацдарм не берёт).
				if target ~= nil and (ability == "SeaLanding" or ability == "Airdrop") then
					local g = m.grid
					local found: number? = nil
					Grid.forNeighbours(g, target, function(j)
						if found == nil and landable(m, n.id, j) and not Grid.isCity(g, j) then
							found = j
						end
					end)
					target = found
				end
				if target ~= nil or not Commanders.needsTarget(ability) then
					local ok = MatchSim.useAbility(m, n, slot, target, percent)
					if ok then
						return
					end
				end
			end
		end
	end
end

-- Случайные события и ракеты (§6.16, §6.9, этап 7г) -------------------------------------------

-- Ставка на аукционе наёмников (деньги — в конце, если ставка победила).
function MatchSim.bid(m: Match, n: Nation, amount: number): (boolean, string?)
	if n.money < amount then
		return false, "noMoney"
	end
	local reason = WorldEvents.bid(m.world, n.id, amount, m.simTime)
	if reason ~= nil then
		return false, reason
	end
	MatchSim.botsBid(m)
	return true, nil
end

-- Боты перебивают ставку, пока хватает их предела (доля денег; Новичок — половина).
function MatchSim.botsBid(m: Match)
	local cfg = Config.Events
	for _ = 1, 50 do
		local need = WorldEvents.minBid(m.world, m.simTime)
		local a = m.world.auction
		if need == nil or a == nil then
			return
		end
		local best: Nation? = nil
		local bestCap = need - 1
		for _, n in m.nations do
			if n.alive and n.isBot and n.id ~= a.topId then
				local personality = Config.BotPersonalities[n.personality or "Admiral"] :: any
				local share = cfg.BotBidShare
					* (if n.botLevel == "Novice" then 0.5 else 1)
					* (if personality ~= nil and personality.bidShare ~= nil then personality.bidShare else 1)
				local cap = math.floor(n.money * share)
				if cap > bestCap then
					best, bestCap = n, cap
				end
			end
		end
		if best == nil then
			return
		end
		WorldEvents.bid(m.world, best.id, need, m.simTime)
	end
end

-- Самая нестабильная провинция державы (не столица).
local function mostUnstable(m: Match, id: number): number?
	local n = m.nations[id]
	local capitalProvince = if n ~= nil and n.capital ~= nil then MapData.getProvince(m.map, n.capital) else 0
	local best: number? = nil
	local bestValue = math.huge
	for _, e in Stability.provincesOf(m.stability, id) do
		if e.province ~= capitalProvince and e.value < bestValue then
			best, bestValue = e.province, e.value
		end
	end
	return best
end

-- Применить случайное событие kind. Возвращает false, если сейчас ему не к чему примениться.
function MatchSim.worldEvent(m: Match, kind: string): boolean
	local st = m.world
	local cfg = Config.Events
	local rng = m.worldRng
	local g = m.grid
	local w = g.width
	local event: { [string]: any } = { kind = "worldEvent", event = kind }
	if kind == "OilRush" then
		local candidates: { number } = {}
		for _, p in m.provinces.list do
			if not p.oil and p.capturable > 0 and not Stability.isRebel(m.stability, p.id) then
				table.insert(candidates, p.id)
			end
		end
		if #candidates == 0 then
			return false
		end
		local id = candidates[Rng.range(rng, 1, #candidates)]
		local p = m.provinces.list[id];
		(p :: any).oil = true
		table.insert(st.oilExtra, id)
		st.version += 1
		m.infoDirty = true
		event.province, event.cell = id, p.center
	elseif kind == "Storm" then
		local cell: number? = nil
		for _ = 1, 400 do
			local i = Rng.range(rng, 0, g.size - 1)
			if Naval.seaAt(m.sea, i) ~= 0 then
				cell = i
				break
			end
		end
		if cell == nil then
			return false
		end
		local radius = cfg.StormRadius * w / Config.UnitsReferenceMapWidth
		st.storm = { cell = cell, radius = radius, untilTime = m.simTime + cfg.StormSec }
		st.version += 1
		event.cell, event.radius = cell, radius
	elseif kind == "Harvest" then
		st.harvestUntil = m.simTime + cfg.HarvestSec
	elseif kind == "Mercenaries" then
		WorldEvents.startAuction(st, m.simTime)
		MatchSim.botsBid(m)
	elseif kind == "Revolt" then
		local leader, most = 0, 0
		for _, n in m.nations do
			local cells = if n.alive then Grid.cellsOf(g, n.id) else 0
			if cells > most then
				leader, most = n.id, cells
			end
		end
		local p = if leader ~= 0 then mostUnstable(m, leader) else nil
		if p == nil then
			return false
		end
		event.nation, event.province = leader, p
		event.cell = m.provinces.list[p].center
		table.insert(m.events, event :: any)
		MatchSim.revolt(m, p, leader)
		return true
	elseif kind == "Defectors" then
		local weakest, least = 0, math.huge
		for _, n in m.nations do
			if n.alive then
				local cells = Grid.cellsOf(g, n.id)
				if cells < least then
					weakest, least = n.id, cells
				end
			end
		end
		if weakest == 0 then
			return false
		end
		Forces.add(m.nations[weakest].home, Forces.kindIndex("Infantry") :: number, cfg.DefectorStrength)
		event.nation = weakest
	end
	table.insert(m.events, event :: any)
	return true
end

-- Пуск ракеты из своей шахты по клетке врага (§6.9).
function MatchSim.launch(m: Match, n: Nation, cell: number): (boolean, string?)
	local g = m.grid
	if cell < 0 or cell >= g.size then
		return false, "focus"
	end
	local hasSilo = false
	for _, s in MatchSim.buildingsOf(m, "MissileSilo") do
		if s.owner == n.id then
			hasSilo = true
		end
	end
	if not hasSilo then
		return false, "needSilo"
	end
	if (m.missileReady[n.id] or 0) > m.simTime then
		return false, "cooldown"
	end
	if Council.active(m.council, "superweaponBan", m.simTime) ~= nil then
		return false, "banned"
	end
	local target = Grid.getOwner(g, cell)
	if target == 0 or target == n.id or not Wars.isActive(m.wars, n.id, target) then
		return false, "notAtWar"
	end
	local cfg = Config.Buildings.MissileSilo
	m.missileReady[n.id] = m.simTime + cfg.cooldownSec
	table.insert(m.missiles, { owner = n.id, cell = cell, impactAt = m.simTime + cfg.warningSec })
	table.insert(
		m.events,
		{ kind = "missileLaunched", nation = n.id, target = target, cell = cell, impactIn = cfg.warningSec }
	)
	return true, nil
end

-- Удар ракеты (или перехват сетью ПВО).
local function missileImpact(m: Match, missile: Missile)
	local g = m.grid
	local w = g.width
	local cell = missile.cell
	local r = Config.Buildings.MissileSilo.strikeRadius
	local cx, cy = cell % w, cell // w
	-- Сеть ПВО (Флот-4): батарея державы с технологией (или её друга) рядом с целью — шанс сбить.
	local victim = Grid.getOwner(g, cell)
	if victim ~= 0 then
		local friends = Diplomacy.friends(m.diplo, victim)
		local reach2 = Config.Buildings.AirDefense.radius ^ 2
		for _, b in MatchSim.buildingsOf(m, "AirDefense") do
			if friends[b.owner] and Tech.has(m.tech, b.owner, "Fleet", 4) then
				local dx, dy = b.cell % w - cx, b.cell // w - cy
				if dx * dx + dy * dy <= reach2 then
					if Rng.nextFloat(m.missileRng) < Config.Missile.InterceptChance then
						table.insert(
							m.events,
							{ kind = "missileShot", nation = missile.owner, by = b.owner, cell = cell }
						)
						return
					end
					break
				end
			end
		end
	end
	local taken = 0
	for dy = -r, r do
		for dx = -r, r do
			local x, y = cx + dx, cy + dy
			if x >= 0 and y >= 0 and x < w and y < g.height and dx * dx + dy * dy <= r * r then
				local i = y * w + x
				if Grid.isCapturable(g, i) and Grid.getOwner(g, i) ~= 0 then
					Grid.setOwner(g, i, 0)
					taken += 1
				end
			end
		end
	end
	for _, a in m.attacks do
		if lineTouches(m, a, cell, r) then
			Forces.applyDamage(a.forces, Forces.total(a.forces) * Config.Missile.FrontLoss)
		end
	end
	table.insert(m.events, { kind = "missileHit", nation = missile.owner, cell = cell, cells = taken })
end

-- События по расписанию, конец шторма и аукциона, удары ракет.
local function stepWorld(m: Match)
	local st = m.world
	if st.storm ~= nil and m.simTime >= (st.storm :: WorldEvents.Storm).untilTime then
		st.storm = nil
		st.version += 1
	end
	local auction = WorldEvents.closeAuction(st, m.simTime)
	if auction ~= nil then
		local winner = m.nations[auction.topId]
		if winner ~= nil and winner.alive and winner.money >= auction.top then
			winner.money -= auction.top
			local cfg = Config.Events
			local xp = Config.Combat.StarXp[cfg.MercStars]
			Forces.add(winner.home, Forces.kindIndex("Infantry") :: number, cfg.MercStrength * 2 / 3, xp)
			Forces.add(winner.home, Forces.kindIndex("Tanks") :: number, cfg.MercStrength / 3, xp)
			table.insert(m.events, { kind = "mercs", nation = winner.id, amount = auction.top })
		else
			table.insert(m.events, { kind = "mercs", nation = 0, amount = 0 })
		end
	end
	if m.rules.events and WorldEvents.due(st, m.simTime, m.worldRng) then
		-- Не к чему примениться — берём другое событие (не больше трёх попыток).
		for _ = 1, 3 do
			local kind = WorldEvents.pick(m.worldRng, function(k: string): boolean
				return k ~= "Mercenaries" or st.auction == nil
			end)
			if kind == nil or MatchSim.worldEvent(m, kind) then
				break
			end
		end
	end
	local k = 1
	while k <= #m.missiles do
		local missile = m.missiles[k]
		if m.simTime >= missile.impactAt then
			table.remove(m.missiles, k)
			missileImpact(m, missile)
		else
			k += 1
		end
	end
end

-- Бот с шахтой: в войне — пуск по линии фронта врага (своей или его) или по городу врага; без шахты — строит её.
local function botMissile(m: Match, n: Nation, rng: Rng)
	if Rng.nextFloat(rng) >= Config.Missile.BotChance then
		return
	end
	local enemy: { [number]: boolean } = {}
	local any = false
	for _, war in Wars.of(m.wars, n.id) do
		if war.state == "active" then
			enemy[Wars.enemyOf(war, n.id)] = true
			any = true
		end
	end
	if not any then
		return
	end
	if MatchSim.ownedOf(m, n.id).silos == 0 then
		local cfg = Config.Buildings.MissileSilo
		if
			MatchSim.techAllows(m, n.id, "MissileSilo")
			and n.money >= cfg.cost * Config.Missile.BotSiloMoneyMul
			and n.oil >= cfg.oil
		then
			-- Свободная своя провинция подальше от фронта: ближайшая к столице.
			local cap = n.capital or 0
			local w = m.grid.width
			local best: number? = nil
			local bestD = math.huge
			for _, p in m.provinces.list do
				if Grid.getOwner(m.grid, p.center) == n.id and m.buildings.byProvince[p.id] == nil then
					local d = (p.center % w - cap % w) ^ 2 + (p.center // w - cap // w) ^ 2
					if d < bestD then
						best, bestD = p.center, d
					end
				end
			end
			if best ~= nil then
				MatchSim.applyIntent(m, n.id, { kind = "build", building = "MissileSilo", cell = best })
			end
		end
		return
	end
	-- Цель: клетка врага на линии фронта с наибольшими войсками.
	local target: number? = nil
	local most = 0
	for _, a in m.attacks do
		local line = a.line
		if
			line ~= nil
			and #(line :: { number }) > 0
			and (enemy[a.attacker] or (a.attacker == n.id and enemy[a.target]))
		then
			local power = Forces.total(a.forces)
			if power > most then
				for _, c in line :: { number } do
					if enemy[Grid.getOwner(m.grid, c)] then
						target, most = c, power
						break
					end
				end
			end
		end
	end
	if target ~= nil then
		MatchSim.launch(m, n, target)
	end
end

-- Флот (§6.12, этап 7б-1) ------------------------------------------------------------------

-- Котёл (плацдарм) со снабжением по морю не сдаётся: в нём есть берег, до которого недалеко от своего порта.
function MatchSim.pocketSeaSupplied(m: Match, nationId: number, cells: { number }): boolean
	local sets = MatchSim.seaSupplySets(m, nationId)
	if #sets == 0 then
		return false
	end
	for _, cell in cells do
		for _, set in sets do
			if set[cell] then
				return true
			end
		end
	end
	return false
end

export type Port = { cell: number, dock: number, owner: number }

-- Все порты на карте (клетка здания, причал, хозяин по сетке; ничьи пропускаются).
function MatchSim.ports(m: Match): { Port }
	local out: { Port } = {}
	for cell, b in m.buildings.byCell do
		if b.kind == "Port" and not Air.isDisabled(m.air, cell, m.simTime) then
			local dock = m.sea.docks[MapData.getProvince(m.map, cell)]
			local owner = Grid.getOwner(m.grid, cell)
			if dock ~= nil and owner ~= 0 then
				table.insert(out, { cell = cell, dock = dock, owner = owner })
			end
		end
	end
	table.sort(out, function(a: Port, b: Port): boolean
		return a.cell < b.cell
	end)
	return out
end

-- Порты державы (с причалом; заблокированные тоже).
function MatchSim.portsOf(m: Match, nationId: number): { Port }
	local out: { Port } = {}
	for _, p in MatchSim.ports(m) do
		if p.owner == nationId then
			table.insert(out, p)
		end
	end
	return out
end

local function atWar(m: Match): (a: number, b: number) -> boolean
	return function(a: number, b: number): boolean
		return Wars.isActive(m.wars, a, b)
	end
end

-- Берег, который снабжают по морю незаблокированные порты державы и её друзей (§6.12).
local function seaSupplySets(m: Match, nationId: number): { { [number]: boolean } }
	local friends = Diplomacy.friends(m.diplo, nationId)
	local sets: { { [number]: boolean } } = {}
	for _, p in MatchSim.ports(m) do
		if friends[p.owner] and not m.fleet.blocked[p.cell] then
			table.insert(sets, Naval.coastReach(m.sea, p.dock))
		end
	end
	return sets
end
MatchSim.seaSupplySets = seaSupplySets

-- Ближайший к точке (x, y) незаблокированный порт державы в море seaId.
local function nearestPort(m: Match, nationId: number, x: number, y: number, seaId: number): Port?
	local best: Port? = nil
	local bestD = math.huge
	for _, p in MatchSim.portsOf(m, nationId) do
		if not m.fleet.blocked[p.cell] and Naval.seaAt(m.sea, p.dock) == seaId then
			local dx, dy = p.dock % m.grid.width + 0.5 - x, p.dock // m.grid.width + 0.5 - y
			local d = dx * dx + dy * dy
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	return best
end

-- Берег державы target в море причала dock, ближайший к нему (клетка суши у моря, не город).
function MatchSim.coastOf(m: Match, target: number, dock: number): number?
	local seaId = Naval.seaAt(m.sea, dock)
	local w = m.grid.width
	local best: number? = nil
	local bestD = math.huge
	for cell in Grid.borderCells(m.grid, target) do
		if not Grid.isCity(m.grid, cell) and Naval.waterNear(m.sea, cell, 1, seaId) ~= nil then
			local dx, dy = cell % w - dock % w, cell // w - dock // w
			local d = dx * dx + dy * dy
			if d < bestD or (d == bestD and best ~= nil and cell < best) then
				best, bestD = cell, d
			end
		end
	end
	return best
end

-- Флот глазами бота (§6.12): порт, корабли; куда высадиться и где патрулировать — лениво (функции), чтобы не искать
-- берег врага на каждое раздумье (это стоило до 25 мс за тик на «Европе»).
function MatchSim.navyView(
	m: Match,
	n: Nation,
	hasNeutral: boolean,
	neighbours: { BotBrain.Neighbour }
): BotBrain.NavyView
	local w = m.grid.width
	local fs = m.fleet
	local view: BotBrain.NavyView = { transports = 0, destroyers = 0, need = false }
	for _, p in MatchSim.portsOf(m, n.id) do
		if not fs.blocked[p.cell] and view.port == nil then
			view.port = p.cell
		end
	end
	local queue: { Fleet.Build } = fs.queues[n.id] or {}
	for _, b in queue do
		if b.kind == "Transport" then
			view.transports += 1
		else
			view.destroyers += 1
		end
	end
	local idleTransport: Fleet.Ship? = nil
	local idleDestroyer: Fleet.Ship? = nil
	for _, ship in Fleet.ofNation(fs, n.id) do
		if ship.kind == "Transport" then
			view.transports += 1
			if ship.state == "docked" and ship.home ~= nil and not fs.blocked[ship.home :: number] then
				idleTransport = ship
			end
		else
			view.destroyers += 1
			-- Свободен — стоит у причала (в патруле он уже при деле).
			if ship.state == "docked" then
				idleDestroyer = ship
			end
		end
	end
	-- Враги за морем: идёт война, а общей границы по суше нет.
	local landNeighbours: { [number]: boolean } = {}
	for _, nb in neighbours do
		landNeighbours[nb.id] = true
	end
	local enemies: { number } = {}
	for _, war in Wars.of(m.wars, n.id) do
		if war.state == "active" then
			local enemy = Wars.enemyOf(war, n.id)
			table.insert(enemies, enemy)
			if not landNeighbours[enemy] then
				view.need = true
			end
		end
	end
	-- Ничья прибрежная провинция (центр ничей) в море seaId (0 — в любом): клетка суши у её причала.
	local function neutralCoast(from: number?, seaId: number): number?
		local best: number? = nil
		local bestD = math.huge
		for _, p in m.provinces.list do
			local pd = m.sea.docks[p.id]
			if
				pd ~= nil
				and Grid.getOwner(m.grid, p.center) == 0
				and (seaId == 0 or Naval.seaAt(m.sea, pd) == seaId)
			then
				for _, j in { pd - 1, pd + 1, pd - w, pd + w } do
					if
						j >= 0
						and j < m.grid.size
						and MapData.getProvince(m.map, j) == p.id
						and Grid.isCapturable(m.grid, j)
						and Grid.getOwner(m.grid, j) == 0
					then
						if from == nil then
							return j
						end
						local d = (j % w - from % w) ^ 2 + (j // w - from // w) ^ 2
						if d < bestD then
							best, bestD = j, d
						end
						break
					end
				end
			end
		end
		return best
	end
	if not hasNeutral and #fs.ships + #MatchSim.portsOf(m, n.id) == 0 then
		-- Порта ещё нет: нужен ли флот вообще (есть ли ничья земля у моря).
		view.need = view.need or neutralCoast(nil, 0) ~= nil
	elseif not hasNeutral then
		view.need = true
	end
	if idleTransport ~= nil then
		local port = idleTransport.home :: number
		local dock = m.sea.docks[MapData.getProvince(m.map, port)]
		if dock ~= nil then
			view.idlePort = port
			view.landTarget = function(): number?
				local best: number? = nil
				local bestD = math.huge
				for _, enemy in enemies do
					local coast = MatchSim.coastOf(m, enemy, dock)
					if coast ~= nil then
						local d = (coast % w - dock % w) ^ 2 + (coast // w - dock // w) ^ 2
						if d < bestD then
							best, bestD = coast, d
						end
					end
				end
				if best ~= nil or hasNeutral then
					return best
				end
				return neutralCoast(dock, Naval.seaAt(m.sea, dock))
			end
		end
	end
	if idleDestroyer ~= nil and #enemies > 0 then
		local ship = idleDestroyer :: Fleet.Ship
		view.idleDestroyer = ship.id
		view.patrolTarget = function(): number?
			local here = Fleet.cellOf(w, ship)
			local water = Naval.waterNear(m.sea, here, 2) or here
			local seaId = Naval.seaAt(m.sea, water)
			local best: number? = nil
			local bestD = math.huge
			-- Порт врага в этом море — блокада; нет порта — море у его берега (обстрел и перехват).
			for _, p in MatchSim.ports(m) do
				if table.find(enemies, p.owner) ~= nil and Naval.seaAt(m.sea, p.dock) == seaId then
					local dx, dy = p.dock % w + 0.5 - ship.x, p.dock // w + 0.5 - ship.y
					local d = dx * dx + dy * dy
					if d < bestD then
						best, bestD = p.dock, d
					end
				end
			end
			if best ~= nil then
				return best
			end
			for _, enemy in enemies do
				local coast = MatchSim.coastOf(m, enemy, water)
				local near = if coast ~= nil then Naval.waterNear(m.sea, coast, 2, seaId) else nil
				if near ~= nil then
					local dx, dy = near % w + 0.5 - ship.x, near // w + 0.5 - ship.y
					local d = dx * dx + dy * dy
					if d < bestD then
						best, bestD = near, d
					end
				end
			end
			return best
		end
	end
	return view
end

-- Найм корабля, высадка, патруль.
function MatchSim.navalIntent(m: Match, n: Nation, intent: Types.Intent): (boolean, string?)
	local w = m.grid.width
	if intent.kind == "ship" then
		local b = m.buildings.byCell[intent.port]
		if b == nil or b.kind ~= "Port" or Grid.getOwner(m.grid, intent.port) ~= n.id then
			return false, "needPort"
		end
		if m.fleet.blocked[intent.port] then
			return false, "blockaded"
		end
		local queue = m.fleet.queues[n.id] or {}
		if #queue >= Config.Naval.ShipQueue then
			return false, "queueFull"
		end
		if Fleet.count(m.fleet, n.id) >= Config.Naval.MaxShips then
			return false, "maxShips"
		end
		local stats = Fleet.stats(intent.ship)
		local cost = MatchSim.shipCost(m, n.id, intent.ship)
		if n.money < cost then
			return false, "noMoney"
		end
		if n.oil < stats.oil then
			return false, "noOil"
		end
		n.money -= cost
		n.oil -= stats.oil
		table.insert(queue, { kind = intent.ship, port = intent.port, left = stats.recruitSec })
		m.fleet.queues[n.id] = queue
		return true, nil
	elseif intent.kind == "land" then
		local b = m.buildings.byCell[intent.port]
		if b == nil or b.kind ~= "Port" or Grid.getOwner(m.grid, intent.port) ~= n.id then
			return false, "needPort"
		end
		if m.fleet.blocked[intent.port] then
			return false, "blockaded"
		end
		local ship = Fleet.idleTransport(m.fleet, n.id, intent.port)
		if ship == nil then
			return false, "noTransport"
		end
		local target = intent.target
		if target < 0 or target >= m.grid.size or not Grid.isCapturable(m.grid, target) then
			return false, "notCoast"
		end
		local dock = m.sea.docks[MapData.getProvince(m.map, intent.port)] :: number
		local water = Naval.waterNear(m.sea, target, Config.Naval.LandReach, Naval.seaAt(m.sea, dock))
		if water == nil then
			return false, "notCoast"
		end
		local owner = Grid.getOwner(m.grid, target)
		if owner ~= 0 and owner ~= n.id and not Wars.isActive(m.wars, n.id, owner) then
			return false, "notAtWar"
		end
		-- Груз: доля гарнизона (не больше вместимости) и столько же процентов людей.
		local share = intent.percent
		local total = Forces.total(n.home)
		if total > 0 then
			share = math.min(share, Config.Naval.TransportCapacity / total)
		end
		local cargo = if total > 0 then Forces.take(n.home, share) else Forces.new()
		local people = math.min(n.people * intent.percent, Config.Naval.TransportPeople)
		if Forces.total(cargo) < 1 and people < Config.Expansion.MinTroops then
			Forces.merge(n.home, cargo)
			return false, "noTroops"
		end
		n.people -= people
		ship.cargo = cargo
		ship.people = people
		ship.target = target
		Fleet.order(ship, "land", water)
		return true, nil
	elseif intent.kind == "patrol" then
		local ship = Fleet.byId(m.fleet, intent.ship)
		if ship == nil or ship.owner ~= n.id then
			return false, "noShip"
		end
		if ship.kind ~= "Destroyer" then
			return false, "notDestroyer"
		end
		local here = Fleet.cellOf(w, ship)
		local seaId = Naval.seaAt(m.sea, here)
		if seaId == 0 then
			seaId = Naval.seaAt(m.sea, Naval.waterNear(m.sea, here, 2) or here)
		end
		local cell = intent.cell
		if Naval.seaAt(m.sea, cell) ~= seaId then
			cell = Naval.waterNear(m.sea, cell, Config.Naval.LandReach, seaId) or -1
		end
		if cell < 0 then
			return false, "notSea"
		end
		Fleet.order(ship, "patrol", cell)
		return true, nil
	end
	return false, "?"
end

-- Высадка (§6.12): плацдарм, войска — фронт против врага рядом (или атака ничьей земли), люди — с ними или домой.
function MatchSim.land(m: Match, ship: Fleet.Ship)
	local target = ship.target
	local cargo = ship.cargo or Forces.new()
	local people = ship.people
	ship.cargo, ship.people, ship.target = nil, 0, nil
	if target == nil then
		return
	end
	MatchSim.landAt(m, ship.owner, target, cargo, people, Config.Naval.BeachheadRadius)
end

-- Плацдарм радиуса r у клетки target: свои клетки в круге (ничьи и врага, кроме городов), войска cargo — фронт
-- против врага рядом (или на ничью землю), люди — с ними или домой. Общее для высадки с транспорта и десантов
-- генералов (§6.15).
function MatchSim.landAt(m: Match, owner: number, target: number, cargo: Types.Forces, people: number, r: number)
	local n = m.nations[owner]
	if n == nil or not n.alive then
		return
	end
	local g = m.grid
	local w = g.width
	local tx, ty = target % w, target // w
	local taken = 0
	local enemies: { [number]: number } = {}
	local neutral = false
	for dy = -r - 2, r + 2 do
		for dx = -r - 2, r + 2 do
			local x, y = tx + dx, ty + dy
			if x >= 0 and y >= 0 and x < w and y < g.height then
				local i = y * w + x
				if Grid.isCapturable(g, i) then
					local o = Grid.getOwner(g, i)
					local inside = dx * dx + dy * dy <= r * r
					local hostile = o ~= 0 and o ~= n.id and Wars.isActive(m.wars, n.id, o)
					if inside and not Grid.isCity(g, i) and (o == 0 or hostile) then
						Grid.setOwner(g, i, n.id)
						if o ~= 0 then
							Wars.record(m.wars, i, o, n.id)
						end
						taken += 1
					elseif not inside then
						if hostile then
							enemies[o] = (enemies[o] or 0) + 1
						elseif o == 0 then
							neutral = true
						end
					end
				end
			end
		end
	end
	local enemy, most = 0, 0
	for id, count in enemies do
		if count > most or (count == most and id < enemy) then
			enemy, most = id, count
		end
	end
	local function open(targetId: number, forces: Types.Forces, troops: number)
		local _, existing = findAttack(m, n.id, targetId)
		if existing ~= nil then
			Forces.merge(existing.forces, forces)
			existing.troops += troops
			existing.focus = target
		else
			table.insert(m.attacks, {
				attacker = n.id,
				target = targetId,
				troops = troops,
				focus = target,
				forces = forces,
				supplied = true,
				ratio = math.huge,
				fighting = false,
				lastAdvance = m.simTime,
			})
		end
	end
	if enemy ~= 0 then
		open(enemy, cargo, 0)
		if neutral and people >= Config.Expansion.MinTroops then
			open(0, Forces.new(), people)
		else
			n.people += people
		end
	elseif neutral and people + Forces.total(cargo) > 0 then
		open(0, cargo, people)
	else
		Forces.merge(n.home, cargo)
		n.people += people
	end
	table.insert(m.events, { kind = "landed", nation = n.id, target = enemy, cell = target, cells = taken })
end

-- Флот за simDt: найм, пути, движение и высадки, бой кораблей, обстрел берега, блокада.
local function stepFleet(m: Match, simDt: number)
	local fs = m.fleet
	local w = m.grid.width
	-- Найм: у каждой державы готовится первый корабль очереди; заблокированный порт — ждёт.
	for owner, queue in fs.queues do
		local first = queue[1]
		local nation = m.nations[owner]
		if first ~= nil and nation ~= nil and nation.alive and not fs.blocked[first.port] then
			first.left -= simDt
			if first.left <= 0 then
				table.remove(queue, 1)
				local b = m.buildings.byCell[first.port]
				local dock = m.sea.docks[MapData.getProvince(m.map, first.port)]
				if b ~= nil and b.kind == "Port" and dock ~= nil and Grid.getOwner(m.grid, first.port) == owner then
					Fleet.spawn(fs, w, owner, first.kind, first.port, dock)
					table.insert(m.events, { kind = "shipBuilt", nation = owner, ship = first.kind })
				else
					-- Порт потерян: деньги и нефть возвращаются.
					local stats = Fleet.stats(first.kind)
					nation.money += MatchSim.shipCost(m, owner, first.kind)
					nation.oil += stats.oil
				end
			end
		end
	end
	if #fs.ships == 0 then
		return
	end
	local happenings: { Fleet.Happening } = {}
	Fleet.planPaths(fs, m.sea, happenings)
	Fleet.move(fs, w, simDt, happenings, function(x: number, y: number): boolean
		return WorldEvents.inStorm(m.world, w, x, y, m.simTime) -- шторм (§6.16)
	end)
	local war = atWar(m)
	Fleet.fight(fs, w, simDt, war, happenings)
	for _, h in happenings do
		local ship = h.ship
		if h.kind == "arrived" then
			if ship.order == "land" then
				MatchSim.land(m, ship)
				ship.order = "return"
			end
			if ship.order == "return" then
				local here = Fleet.cellOf(w, ship)
				local port = nearestPort(m, ship.owner, ship.x, ship.y, Naval.seaAt(m.sea, here))
				if port == nil then
					ship.order = nil
				elseif here == port.dock then
					ship.state, ship.order, ship.home = "docked", nil, port.cell
				else
					Fleet.order(ship, "return", port.dock)
				end
			elseif ship.order == "patrol" then
				ship.order = nil
			end
		elseif h.kind == "noPath" then
			-- Пути нет: груз — домой, приказ отменён.
			local nation = m.nations[ship.owner]
			if nation ~= nil and ship.cargo ~= nil then
				Forces.merge(nation.home, ship.cargo)
				nation.people += ship.people
				ship.cargo, ship.people, ship.target = nil, 0, nil
			end
		elseif h.kind == "sunk" then
			table.insert(m.events, {
				kind = "shipSunk",
				nation = ship.owner,
				by = h.by,
				ship = ship.kind,
				lost = Fleet.cargoPower(ship),
			})
		end
	end
	-- Транспорт без приказа в море (нет пути, порт потерян) — раз в секунду пробует вернуться в свой порт.
	if m.simTime >= m.nextBlockadeAt then
		for _, ship in fs.ships do
			if ship.alive and ship.kind == "Transport" and ship.state == "patrol" and ship.order == nil then
				local here = Fleet.cellOf(w, ship)
				local seaId = Naval.seaAt(m.sea, Naval.waterNear(m.sea, here, 2) or here)
				local port = nearestPort(m, ship.owner, ship.x, ship.y, seaId)
				if port ~= nil then
					Fleet.order(ship, "return", port.dock)
				end
			end
		end
	end
	-- Обстрел берега: вражеские фронты, линия которых в радиусе эсминца, теряют силу.
	local range = Config.Naval.DestroyerRange * w / Config.UnitsReferenceMapWidth
	local range2 = range * range
	local shore = Fleet.stats("Destroyer").attack * Config.Naval.ShoreDamage * simDt
	for _, d in fs.ships do
		if d.alive and d.kind == "Destroyer" then
			for _, a in m.attacks do
				if a.target ~= 0 and a.attacker ~= d.owner and Wars.isActive(m.wars, d.owner, a.attacker) then
					local line = a.line
					if line ~= nil then
						for _, c in line do
							local dx, dy = c % w + 0.5 - d.x, c // w + 0.5 - d.y
							if dx * dx + dy * dy <= range2 then
								Forces.applyDamage(a.forces, shore)
								break
							end
						end
					end
				end
			end
		end
	end
	-- Блокада — раз в секунду.
	if m.simTime >= m.nextBlockadeAt then
		m.nextBlockadeAt = m.simTime + 1
		local before = table.clone(fs.blocked)
		if Fleet.updateBlockade(fs, w, MatchSim.ports(m), war) then
			for cell in fs.blocked do
				if not before[cell] then
					local owner = Grid.getOwner(m.grid, cell)
					table.insert(m.events, { kind = "blockade", nation = owner, cell = cell, on = true })
				end
			end
			for cell in before do
				if not fs.blocked[cell] then
					local owner = Grid.getOwner(m.grid, cell)
					table.insert(m.events, { kind = "blockade", nation = owner, cell = cell, on = false })
				end
			end
		end
	end
	Fleet.cleanup(fs, function(owner: number): boolean
		local nation = m.nations[owner]
		return nation ~= nil and nation.alive
	end)
end

-- Авиация (§6.13, этап 7б-2) -------------------------------------------------------------

-- Здание в клетке выведено из строя налётом.
function MatchSim.isDisabled(m: Match, cell: number): boolean
	return Air.isDisabled(m.air, cell, m.simTime)
end

-- Работающие здания вида kind (клетка, хозяин по сетке; ничьи и выведенные из строя пропускаются).
function MatchSim.buildingsOf(m: Match, kind: Types.BuildingKind): { { cell: number, owner: number } }
	local cache = buildingsCache[m]
	if cache == nil or cache.tick ~= m.tick then
		cache = { tick = m.tick, lists = {} }
		buildingsCache[m] = cache
	end
	local hit = (cache :: any).lists[kind]
	if hit ~= nil then
		return hit
	end
	local out: { { cell: number, owner: number } } = {}
	(cache :: any).lists[kind] = out
	for cell, b in m.buildings.byCell do
		if b.kind == kind then
			local owner = Grid.getOwner(m.grid, cell)
			if owner ~= 0 and not MatchSim.isDisabled(m, cell) then
				table.insert(out, { cell = cell, owner = owner })
			end
		end
	end
	table.sort(out, function(a, b): boolean
		return a.cell < b.cell
	end)
	return out
end

-- Ближайший к точке (x, y) работающий аэродром державы (клетка) и расстояние до него в клетках.
local function nearestAirfield(m: Match, nationId: number, x: number, y: number): (number?, number)
	local w = m.grid.width
	local best: number? = nil
	local bestD = math.huge
	for _, a in MatchSim.buildingsOf(m, "Airfield") do
		if a.owner == nationId then
			local dx, dy = a.cell % w + 0.5 - x, a.cell // w + 0.5 - y
			local d = math.sqrt(dx * dx + dy * dy)
			if d < bestD then
				best, bestD = a.cell, d
			end
		end
	end
	return best, bestD
end
MatchSim.nearestAirfield = nearestAirfield

-- Клетка в радиусе авиации державы (не дальше Air.Range от её работающего аэродрома).
function MatchSim.inAirRange(m: Match, nationId: number, cell: number): boolean
	local w = m.grid.width
	local _, d = nearestAirfield(m, nationId, cell % w + 0.5, cell // w + 0.5)
	return d <= Config.Air.Range * Air.scale(w)
end

-- Есть ли в круге налёта вокруг cell земля врага (активная война с nationId).
local function enemyNear(m: Match, nationId: number, cell: number): boolean
	local g = m.grid
	local w = g.width
	local r = Config.Air.BombRadius
	local cx, cy = cell % w, cell // w
	for dy = -r, r do
		for dx = -r, r do
			local x, y = cx + dx, cy + dy
			if x >= 0 and y >= 0 and x < w and y < g.height and dx * dx + dy * dy <= r * r then
				local o = Grid.getOwner(g, y * w + x)
				if o ~= 0 and o ~= nationId and Wars.isActive(m.wars, nationId, o) then
					return true
				end
			end
		end
	end
	return false
end

-- Авиация глазами бота (§6.13): аэродром, самолёты, куда бомбить (лениво), бомбили ли нас.
function MatchSim.airView(m: Match, n: Nation): BotBrain.AirView
	local view: BotBrain.AirView = {
		fighters = 0,
		bombers = 0,
		idleBomber = false,
		bombed = m.bombedAt[n.id] ~= nil and m.simTime - m.bombedAt[n.id] < Config.Air.BuildingDisableSec * 2,
	}
	for _, a in MatchSim.buildingsOf(m, "Airfield") do
		if a.owner == n.id and view.airfield == nil then
			view.airfield = a.cell
		end
	end
	local queue: { Air.Build } = m.air.queues[n.id] or {}
	for _, b in queue do
		if b.kind == "Fighter" then
			view.fighters += 1
		else
			view.bombers += 1
		end
	end
	for _, p in Air.ofNation(m.air, n.id) do
		if p.kind == "Fighter" then
			view.fighters += 1
		else
			view.bombers += 1
			if p.state == "based" then
				view.idleBomber = true
			end
		end
	end
	-- Нас бомбили недавно — где (Генерал прикрывает это место истребителем, §6.13).
	local bombedCell = m.bombedCell[n.id]
	local w = m.grid.width
	if view.bombed and bombedCell ~= nil and MatchSim.inAirRange(m, n.id, bombedCell) then
		view.bombedCell = bombedCell
		local bx, by = bombedCell % w + 0.5, bombedCell // w + 0.5
		local near = Config.Air.InterceptRadius * Air.scale(w) * Config.Air.BotCoverNear
		for _, p in Air.ofNation(m.air, n.id) do
			if p.kind == "Fighter" then
				local cx, cy = p.cover % w + 0.5, p.cover // w + 0.5
				if (cx - bx) ^ 2 + (cy - by) ^ 2 > near * near then
					view.coverFighter = p.id
					break
				end
			end
		end
	end
	-- §15б: истребитель над своим аэродромом и точка на фронте, где враг наступает на нас (туда летят его бомбардировщики).
	for _, p in Air.ofNation(m.air, n.id) do
		if p.kind == "Fighter" and p.cover == p.base then
			view.homeFighter = p.id
			break
		end
	end
	if view.homeFighter ~= nil then
		view.frontCover = function(): number?
			for _, a in m.attacks do
				if a.target == n.id and Wars.isActive(m.wars, n.id, a.attacker) then
					local line: { number } = a.line or {}
					local mid = line[(#line + 1) // 2]
					if mid ~= nil and MatchSim.inAirRange(m, n.id, mid) then
						return mid
					end
				end
			end
			return nil
		end
	end
	if view.idleBomber then
		view.raidTarget = function(): number?
			-- Линия фронта с врагом: сначала фронт врага против нас (его войска), потом наш фронт против него
			-- (его гарнизон у линии). Точка — клетка выборки линии в радиусе авиации.
			for pass = 1, 2 do
				for _, a in m.attacks do
					local fits = if pass == 1
						then a.target == n.id and Wars.isActive(m.wars, n.id, a.attacker)
						else a.attacker == n.id and a.target ~= 0 and Wars.isActive(m.wars, n.id, a.target)
					if fits then
						local line: { number } = a.line or {}
						for _, c in line do
							if MatchSim.inAirRange(m, n.id, c) and enemyNear(m, n.id, c) then
								return c
							end
						end
					end
				end
			end
			return nil
		end
	end
	return view
end

-- Найм самолёта, налёт, точка прикрытия истребителя.
function MatchSim.airIntent(m: Match, n: Nation, intent: Types.Intent): (boolean, string?)
	local w = m.grid.width
	if intent.kind == "plane" then
		local b = m.buildings.byCell[intent.airfield]
		if b == nil or b.kind ~= "Airfield" or Grid.getOwner(m.grid, intent.airfield) ~= n.id then
			return false, "needAirfield"
		end
		if MatchSim.isDisabled(m, intent.airfield) then
			return false, "disabled"
		end
		local queue = m.air.queues[n.id] or {}
		if #queue >= Config.Air.Queue then
			return false, "queueFull"
		end
		if Air.count(m.air, n.id) >= Config.Air.MaxAircraft then
			return false, "maxAircraft"
		end
		local stats = Air.stats(intent.plane)
		if n.money < stats.cost then
			return false, "noMoney"
		end
		if n.oil < stats.oil then
			return false, "noOil"
		end
		n.money -= stats.cost
		n.oil -= stats.oil
		table.insert(queue, { kind = intent.plane, airfield = intent.airfield, left = stats.recruitSec })
		m.air.queues[n.id] = queue
		return true, nil
	elseif intent.kind == "raid" then
		local cell = intent.cell
		if cell < 0 or cell >= m.grid.size then
			return false, "focus"
		end
		if not MatchSim.inAirRange(m, n.id, cell) then
			return false, "outOfRange"
		end
		if not enemyNear(m, n.id, cell) then
			return false, "notAtWar"
		end
		local bomber = Air.idleBomber(m.air, w, n.id, cell)
		if bomber == nil then
			return false, "noBomber"
		end
		Air.sortie(bomber, w, cell)
		return true, nil
	elseif intent.kind == "cover" then
		local plane = Air.byId(m.air, intent.plane)
		if plane == nil or plane.owner ~= n.id then
			return false, "noPlane"
		end
		if plane.kind ~= "Fighter" then
			return false, "notFighter"
		end
		if intent.cell < 0 or intent.cell >= m.grid.size or not MatchSim.inAirRange(m, n.id, intent.cell) then
			return false, "outOfRange"
		end
		Air.coverAt(plane, w, intent.cell)
		return true, nil
	end
	return false, "?"
end

-- Налёт (§6.13) по кругу вокруг цели бомбардировщика: фронты врага, его гарнизон у нашей линии, его здания.
function MatchSim.bomb(m: Match, plane: Air.Plane, target: number)
	local g = m.grid
	local w = g.width
	local cfg = Config.Air
	local r = cfg.BombRadius
	local tx, ty = target % w + 0.5, target // w + 0.5
	local r2 = r * r
	local damage = Air.stats("Bomber").attack * cfg.BombDamage
	local owner = plane.owner
	local hitGarrison: { [number]: boolean } = {}
	local lost = 0
	local function inCircle(c: number): boolean
		local dx, dy = c % w + 0.5 - tx, c // w + 0.5 - ty
		return dx * dx + dy * dy <= r2
	end
	for _, a in m.attacks do
		if a.target ~= 0 and a.line ~= nil then
			local touches = false
			for _, c in a.line :: { number } do
				if inCircle(c) then
					touches = true
					break
				end
			end
			if touches then
				if a.attacker ~= owner and Wars.isActive(m.wars, owner, a.attacker) then
					-- Фронт врага в круге.
					local mul = 1 - Air.aaReduction(Forces.composition(a.forces))
					lost += Forces.applyDamage(a.forces, damage * mul)
				elseif Wars.isActive(m.wars, owner, a.target) and not hitGarrison[a.target] then
					-- Наша (или союзника) линия против врага: его гарнизон у этой линии.
					hitGarrison[a.target] = true
					local enemy = m.nations[a.target]
					if enemy ~= nil and enemy.alive then
						local mul = 1 - Air.aaReduction(Forces.composition(enemy.home))
						lost += Forces.applyDamage(enemy.home, damage * cfg.GarrisonShare * mul)
					end
				end
			end
		end
	end
	local disabled = 0
	for cell, b in m.buildings.byCell do
		-- Город и батарея ПВО налётом не выводятся из строя (батарея иначе гасла бы от первого же налёта на неё).
		if b.kind ~= "City" and b.kind ~= "AirDefense" and inCircle(cell) then
			local o = Grid.getOwner(g, cell)
			if o ~= 0 and o ~= owner and Wars.isActive(m.wars, owner, o) then
				m.air.disabled[cell] = m.simTime + cfg.BuildingDisableSec
				m.air.version += 1
				disabled += 1
			end
		end
	end
	if disabled > 0 then
		MatchSim.refreshOwned(m)
	end
	local victim = Grid.getOwner(g, target)
	if victim ~= 0 and victim ~= owner then
		m.bombedAt[victim] = m.simTime
		m.bombedCell[victim] = target
	end
	table.insert(m.events, {
		kind = "raid",
		nation = owner,
		target = Grid.getOwner(g, target),
		cell = target,
		lost = lost,
		buildings = disabled,
	})
end

-- Авиация за simDt: найм, перелёт без аэродрома, полёты, налёты, бой в воздухе, батареи ПВО, ремонт зданий.
local function stepAir(m: Match, simDt: number)
	local as = m.air
	local w = m.grid.width
	for owner, queue in as.queues do
		local first = queue[1]
		local nation = m.nations[owner]
		if first ~= nil and nation ~= nil and nation.alive and not MatchSim.isDisabled(m, first.airfield) then
			first.left -= simDt
			if first.left <= 0 then
				table.remove(queue, 1)
				local b = m.buildings.byCell[first.airfield]
				if b ~= nil and b.kind == "Airfield" and Grid.getOwner(m.grid, first.airfield) == owner then
					Air.spawn(as, w, owner, first.kind, first.airfield)
					table.insert(m.events, { kind = "planeBuilt", nation = owner, plane = first.kind })
				else
					-- Аэродром потерян: деньги и нефть возвращаются.
					local stats = Air.stats(first.kind)
					nation.money += stats.cost
					nation.oil += stats.oil
				end
			end
		end
	end
	if Air.repair(as, m.simTime) then
		MatchSim.refreshOwned(m)
	end
	if #as.planes == 0 then
		return
	end
	Air.rebase(as, w, function(cell: number, owner: number): boolean
		local b = m.buildings.byCell[cell]
		return b ~= nil and b.kind == "Airfield" and Grid.getOwner(m.grid, cell) == owner
	end, function(owner: number, x: number, y: number): number?
		local cell = nearestAirfield(m, owner, x, y)
		return cell
	end)
	local happenings: { Air.Happening } = {}
	Air.step(as, w, simDt, m.simTime, atWar(m), MatchSim.buildingsOf(m, "AirDefense"), happenings)
	for _, h in happenings do
		if h.kind == "raid" then
			MatchSim.bomb(m, h.plane, h.cell)
		elseif h.kind == "shot" then
			-- Где сбит (клетки): клиент показывает падение и взрыв.
			table.insert(m.events, {
				kind = "planeShot",
				nation = h.plane.owner,
				by = h.by,
				plane = h.plane.kind,
				x = h.plane.x,
				y = h.plane.y,
			})
		end
	end
	Air.cleanup(as, function(owner: number): boolean
		local nation = m.nations[owner]
		return nation ~= nil and nation.alive
	end)
end

-- Что Stability знает о матче (§6.10).
function MatchSim.stabilityContext(m: Match): Stability.Context
	return {
		grid = m.grid,
		provinces = m.provinces,
		cityOf = m.cityOf,
		rng = m.stabilityRng,
		now = m.simTime,
		capitalOf = function(id: number): number?
			local n = m.nations[id]
			return if n ~= nil then n.capital else nil
		end,
		cityLevel = function(cell: number): number
			return Buildings.cityLevel(m.buildings, cell)
		end,
		fort = function(p: number, owner: number): boolean
			local spot = m.buildings.byProvince[p]
			local b = if spot ~= nil then m.buildings.byCell[spot] else nil
			return b ~= nil and b.kind == "Fort" and Grid.getOwner(m.grid, spot :: number) == owner
		end,
		atWar = function(id: number): boolean
			for _, war in Wars.of(m.wars, id) do
				if war.state == "active" then
					return true
				end
			end
			return false
		end,
		weariness = function(id: number): number
			return Wars.weariness(m.wars, id, m.simTime)
		end,
		traitor = function(id: number): boolean
			return Diplomacy.isTraitor(m.diplo, id, m.simTime)
		end,
		bonus = function(id: number): number
			return if Tech.has(m.tech, id, "Economy", 4) then Config.Tech.OrderStability else 0
		end,
	}
end

-- Восстание (§6.10): клетки хозяина в провинции становятся ничьими, его город — городом повстанцев.
function MatchSim.revolt(m: Match, provinceId: number, owner: number)
	local p = m.provinces.list[provinceId]
	if p == nil then
		return
	end
	for _, cell in p.cells do
		if Grid.getOwner(m.grid, cell) == owner then
			Grid.setOwner(m.grid, cell, 0)
		end
	end
	Stability.revolt(m.stability, provinceId, owner, m.simTime)
	table.insert(m.events, { kind = "revolt", nation = owner, province = provinceId })
end

-- Стабильность раз в Stability.UpdateSec и восстания.
local function stepStability(m: Match)
	if m.simTime < m.stability.nextUpdateAt then
		return
	end
	for _, r in Stability.update(m.stability, MatchSim.stabilityContext(m)) do
		local n = m.nations[r.owner]
		if n ~= nil and n.alive then
			MatchSim.revolt(m, r.province, r.owner)
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

-- Места: победитель, его союзники (совместная победа, §8.1); дальше живые по доле суши; дальше выбывшие —
-- кто продержался дольше.
function MatchSim.places(m: Match, winner: number, coWinners: { number }?): { number }
	local co: { [number]: boolean } = {}
	if coWinners ~= nil then
		for _, id in coWinners do
			co[id] = true
		end
	end
	local function rank(n: Nation): number
		return if n.id == winner then 0 elseif co[n.id] then 1 else 2
	end
	local order: { Nation } = table.clone(m.nations)
	table.sort(order, function(a: Nation, b: Nation): boolean
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
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

-- Суша державы для победы: своя и её вассалов (§8.1).
local function landOf(m: Match, id: number): number
	local sum = Grid.cellsOf(m.grid, id)
	for _, v in Diplomacy.vassalsOf(m.diplo, id) do
		sum += Grid.cellsOf(m.grid, v)
	end
	return sum
end

-- Победа (§2, §8.1): 60% суши у державы с союзниками и вассалами, последний выживший (или все живые — союз
-- с вассалами), больше всех суши к лимиту времени. Союзники победителя побеждают вместе с ним.
-- Возвращает true, если матч кончился.
local function finishMatch(m: Match, winner: number, reason: Types.VictoryReason, coWinners: { number })
	m.nextHistoryAt = 0
	recordHistory(m, true) -- последняя точка графика — момент победы
	m.result = {
		winner = winner,
		reason = reason,
		places = MatchSim.places(m, winner, coWinners),
		coWinners = coWinners,
		times = m.history.times,
		shares = m.history.shares,
	}
	m.phase = "Over"
	m.phaseLeft = Config.Match.ResultsSec
	m.paused, m.fast = false, false
	-- Голосование за карту следующего матча (§5.2): текущая и случайные другие (свой поток ГСЧ).
	local mapRng = Rng.stream(m.seed, 400)
	m.mapOptions = Modes.mapOptions(m.map.name, function(n: number): number
		return Rng.range(mapRng, 1, n)
	end)
	if m.settings ~= nil and m.settings.map ~= nil then
		m.mapOptions = {} -- карту выбрал владелец частного сервера (§5.4)
	end
	table.clear(m.mapVotes)
	m.infoDirty = true
	table.insert(m.events, { kind = "victory", nation = winner, reason = reason })
end

-- «Охота на столицы» (§5.1): сколько исходных столиц врагов держит каждая живая держава; кто держит
-- CapitalHunt.Need столиц HoldSec секунд подряд — победитель.
local function huntWinner(m: Match): number?
	if not m.rules.capitalHunt then
		return nil
	end
	local cfg = Config.Modes.CapitalHunt
	local counts: { [number]: number } = {}
	for id, cell in m.startCapitals do
		local owner = Grid.getOwner(m.grid, cell)
		if owner ~= 0 and owner ~= id then
			counts[owner] = (counts[owner] or 0) + 1
		end
	end
	local winner: number? = nil
	for _, n in m.nations do
		local c = if n.alive then counts[n.id] or 0 else 0
		if c ~= (m.huntCount[n.id] or 0) then
			m.huntCount[n.id] = c
			m.infoDirty = true
		end
		if c >= cfg.Need then
			local since = m.huntSince[n.id]
			if since == nil then
				m.huntSince[n.id] = m.time
				m.infoDirty = true
			elseif m.time - since >= cfg.HoldSec and winner == nil then
				winner = n.id
			end
		elseif m.huntSince[n.id] ~= nil then
			m.huntSince[n.id] = nil
			m.infoDirty = true
		end
	end
	return winner
end

-- Победа команды (§5.1): 70% суши у команды, последняя команда, больше всех суши к лимиту времени.
-- Земля вассала считается команде сюзерена. Побеждает вся команда; первым в итогах — её самая большая держава.
local function checkTeamVictory(m: Match): boolean
	local land: { [number]: number } = {}
	local alive: { [number]: boolean } = {}
	local aliveTeams = 0
	for _, n in m.nations do
		if n.alive then
			local lord = Diplomacy.overlordOf(m.diplo, n.id) or n.id
			local t = m.teams[lord] or 0
			land[t] = (land[t] or 0) + Grid.cellsOf(m.grid, n.id)
			if not alive[t] then
				alive[t] = true
				aliveTeams += 1
			end
		end
	end
	local best, bestLand = 0, -1
	for t = 1, m.teamCount do
		if (land[t] or 0) > bestLand then
			best, bestLand = t, land[t] or 0
		end
	end
	local reason: Types.VictoryReason? = nil
	if bestLand >= m.grid.capturableCount * m.rules.victoryShare then
		reason = "land"
	elseif aliveTeams <= 1 and #m.nations > 1 then
		reason = "last"
	elseif m.time >= m.rules.timeLimitSec then
		reason = "time"
	end
	if reason == nil or best == 0 then
		return false
	end
	local winner, winnerLand = 0, -1
	local members: { number } = {}
	for _, n in m.nations do
		if m.teams[n.id] == best then
			table.insert(members, n.id)
			local c = if n.alive then Grid.cellsOf(m.grid, n.id) else -1
			if c > winnerLand then
				winner, winnerLand = n.id, c
			end
		end
	end
	local co: { number } = {}
	for _, id in members do
		if id ~= winner then
			table.insert(co, id)
		end
	end
	finishMatch(m, winner, reason, co)
	return true
end

local function checkVictory(m: Match): boolean
	if not m.victory then
		return false
	end
	if m.teamCount > 0 then
		return checkTeamVictory(m)
	end
	local hunter = huntWinner(m)
	local ds = m.diplo
	local aliveList: { Nation } = {}
	local leader, leaderLand = 0, -1
	for _, n in m.nations do
		if n.alive then
			table.insert(aliveList, n)
			-- Вассал сам не побеждает: его суша — у сюзерена.
			if Diplomacy.overlordOf(ds, n.id) == nil then
				local land = landOf(m, n.id)
				if land > leaderLand then
					leader, leaderLand = n.id, land
				end
			end
		end
	end
	local need = m.grid.capturableCount * m.rules.victoryShare
	local reason: Types.VictoryReason? = nil
	local winner = leader
	-- Суша союза: держава, её союзники и все их вассалы.
	local bestBloc, blocWinner = -1, 0
	for _, n in aliveList do
		if Diplomacy.overlordOf(ds, n.id) == nil then
			local land = landOf(m, n.id)
			for _, ally in Diplomacy.alliesOf(ds, n.id) do
				land += landOf(m, ally)
			end
			if land > bestBloc or (land == bestBloc and landOf(m, n.id) > landOf(m, blocWinner)) then
				bestBloc, blocWinner = land, n.id
			end
		end
	end
	-- Все живые — победитель, его союзники и их вассалы?
	local function inBloc(owner: number, id: number): boolean
		local lord = Diplomacy.overlordOf(ds, id) or id
		return lord == owner or Diplomacy.allied(ds, owner, lord)
	end
	local allFriends = leader ~= 0
	for _, n in aliveList do
		if not inBloc(leader, n.id) then
			allFriends = false
		end
	end
	if bestBloc >= need and blocWinner ~= 0 then
		reason, winner = "land", blocWinner
	elseif #m.nations > 1 and (#aliveList <= 1 or allFriends) then
		reason = "last"
		winner = if #aliveList == 1 then aliveList[1].id else leader
	elseif hunter ~= nil then
		reason, winner = "capitals", hunter
	elseif m.time >= m.rules.timeLimitSec then
		reason = "time"
	end
	if reason == nil or winner == 0 then
		return false
	end
	finishMatch(m, winner, reason, Diplomacy.alliesOf(ds, winner))
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
			local growthMul = (1 - Wars.weariness(m.wars, n.id, m.simTime))
				* (if WorldEvents.harvest(m.world, m.simTime) then Config.Events.HarvestMul else 1) -- урожай (§6.16)
			n.people = Economy.grow(n.people, MatchSim.maxPeopleOf(m, n.id), simDt, growthMul)
			-- Линии найма: первые recruitLines юнитов очереди готовятся параллельно.
			local lines = MatchSim.recruitLines(m, n.id)
			local k = 1
			while k <= math.min(lines, #n.queue) do
				local item = n.queue[k]
				item.left -= simDt
				if item.left <= 0 then
					-- «Учебка» (§6.14): новобранцы сразу с 1★.
					local xp = if Tech.has(m.tech, n.id, "Army", 1) then Config.Combat.StarXp[1] else 0
					Forces.add(n.home, item.kind, Forces.stats(item.kind).strength, xp)
					table.remove(n.queue, k)
					lines -= 1 -- линия освободилась на этом шаге: следующий юнит начнёт со следующего
				else
					k += 1
				end
			end
		end
	end

	Commanders.cleanup(m.commanders, m.simTime) -- истёкшие зоны авиаудара и укрепрайона (§6.15)

	-- Технологии (§6.14): законченные исследования.
	for _, done in Tech.step(m.tech, simDt) do
		table.insert(m.events, { kind = "researched", nation = done.id, branch = done.branch, level = done.level })
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
	stepDiplomacy(m)
	stepCouncil(m)

	stepWorld(m) -- случайные события и ракеты (§6.16, §6.9)
	stepRadarIntel(m) -- радар — постоянная разведка (§6.11а)
	stepFlood(m) -- «Потоп» (§5.3)
	stepTutorial(m) -- «Обучение» (§5.5)
	stepFleet(m, simDt)
	stepAir(m, simDt)
	m.lastCaptured = stepAttacks(m, simDt)
	stepPockets(m)
	stepStability(m)

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

	-- Боты: не больше Bots.MaxThinksPerTick раздумий за тик (§9), остальные подумают в следующем тике.
	local thinks = 0
	for _, n in m.nations do
		local due = m.botNextThink[n.id]
		if n.alive and n.isBot and due ~= nil and m.simTime >= due and thinks < Config.Bots.MaxThinksPerTick then
			thinks += 1
			local profile = profileOf(m, n.id)
			local rngs = botRngsOf(m, n.id)
			m.botNextThink[n.id] = m.simTime + BotBrain.nextThinkDelay(rngs.think, profile)
			local memory = m.botMemory[n.id]
			if memory == nil then
				memory = BotBrain.newMemory()
				m.botMemory[n.id] = memory
			end
			local intent = BotBrain.decide(
				botView(m, n),
				rngs.main,
				profile,
				memory,
				{ navy = rngs.navy, air = rngs.air, diplo = rngs.diplo, tech = rngs.tech }
			)
			if intent ~= nil then
				local ok = MatchSim.applyIntent(m, n.id, intent)
				-- Богатый бот (правка перед 7в-2) за одно раздумье ставит в очередь столько же юнитов, сколько у него
				-- линий найма: иначе один юнит за раздумье не успевает за доходом большой державы.
				if ok and intent.kind == "hire" and n.money >= Config.Bots.RichHireMoney then
					local cap = math.max(profile.level.maxQueue, MatchSim.recruitLines(m, n.id))
					while #n.queue < cap and n.money >= Config.Bots.RichHireMoney do
						if not MatchSim.applyIntent(m, n.id, intent) then
							break
						end
					end
				end
			end
			botAbility(m, n, profile, rngs.ability) -- способности генерала (§6.15)
			botMissile(m, n, rngs.missile) -- ракетная шахта (§6.9)
			botIntel(m, n, rngs.intel) -- разведка (§6.11а)
		end
	end
	m.botThinks = thinks
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
