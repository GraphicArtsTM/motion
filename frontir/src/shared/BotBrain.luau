--!strict
--[[
	BotBrain — решения бота (GDD §9, §9.1 «Боты v2»).
	Бот видит только то, что видел бы игрок (BotView: своя держава, у соседей — сила, состав войск, войны,
	доля суши), и отвечает тем же намерением (Intent), что и игрок. Читов нет; Генералу — +10% дохода (§9),
	это считает MatchSim.

	Уровень (Config.BotLevels) — насколько бот умён, личность (Config.BotPersonalities) — что он любит.
	Порядок раздумья:
	1. Ошибка уровня — пропуск хода (Новичок часто, Генерал никогда).
	2. Фронт стоит с плохим перевесом (или без снабжения) — отмена, войска домой.
	3. Стройка: завод, вышки, рынки, укрепления у фронта, города (Новичок — что попало).
	4. Найм: Новичок — пехота, Обычный — случайно, Генерал — против состава врага.
	5. Долгая проигранная война — просит мира.
	6. Война идёт — фронт или подкрепление против лучшей цели.
	7. Ничья земля рядом — расширение людьми.
	8. Иначе — объявить войну соседу (Новичок — случайному, Обычный — слабейшему, Генерал — по оценке цели),
	   если отправит войск в advantage раз сильнее его обороны.
]]

local Config = require("./Config")
local Economy = require("./Economy")
local Forces = require("./Forces")
local Rng = require("./Rng")
local Types = require("./Types")

type Rng = Rng.Rng

export type Neighbour = {
	id: number,
	people: number,
	power: number, -- гарнизон соседа
	frontPower: number?, -- его войска на фронтах
	atWar: boolean, -- с ним идёт активная война (можно открыть фронт)
	canDeclare: boolean, -- можно объявить ему войну (нет войны и запрета после мира)
	border: number?, -- клеток общей границы
	share: number?, -- его доля суши (0..1)
	distracted: boolean?, -- уже воюет с кем-то другим
	enemies: number?, -- §15п: со сколькими державами (кроме нас) воюет
	mix: { number }?, -- доли типов войск гарнизона (Types.LandUnits)
	city: number?, -- его город, ближайший к нашей столице (направление удара)
	cities: number?, -- сколько у него городов
	treaty: ("pact" | "alliance" | "vassal" | "overlord")?, -- договор с нами (§8.1)
	traitor: boolean?, -- метка «Предатель»
	demandProvince: number?, -- его провинция у нашей границы, которую можно потребовать
	trade: boolean?, -- с ним торговое соглашение (§8.2)
	weakened: boolean?, -- воюет с кем-то ещё и потерял больше Diplomacy.BetrayLossShare войск
	embargo: boolean?, -- между нами эмбарго
	-- §15у: полное доверие
	trust: boolean?, -- союз с ним — с полным доверием
	trustReady: boolean?, -- можно предложить ему полное доверие
	via: number?, -- держава за союзником с полным доверием (через кого бить)
	canJoin: boolean?, -- можно вступить в войну с ней вместе с союзником
}

-- Свой фронт или атака глазами бота.
export type FrontView = {
	target: number, -- 0 — ничья земля
	ratio: number, -- перевес (math.huge — обороны нет)
	supplied: boolean,
	fighting: boolean,
	stalledSec: number, -- секунд без захвата клетки
	power: number,
}

-- Война бота глазами бота.
export type WarView = {
	enemy: number,
	active: boolean, -- мобилизация закончилась
	age: number, -- секунд активной войны
	myGain: number, -- клеток взято у врага в этой войне
	theirGain: number, -- клеток враг взял у нас
	theirPower: number, -- вся сила врага (гарнизон и фронты)
	canPropose: boolean, -- нет висящего предложения и давно не просили
	proposedBefore: boolean, -- уже просил мира в этой войне
}

export type BotView = {
	people: number,
	maxPeople: number,
	attacks: number, -- активных атак и фронтов
	queue: number, -- юнитов в очереди найма
	power: number, -- сила гарнизона (войска дома)
	totalPower: number, -- гарнизон и фронты
	hasCapital: boolean,
	hasNeutral: boolean, -- рядом есть ничья земля, которую можно взять
	neighbours: { Neighbour }, -- соседние державы
	reach: { Neighbour }?, -- §15у: державы за союзниками с полным доверием (бить через союзника)
	wars: { WarView },
	fronts: { FrontView }?,
	mix: { number }?, -- доли типов своих войск (гарнизон)
	time: number?, -- simTime (для памяти бота)
	-- Дипломатия (§8.1)
	allies: number?, -- сколько союзников
	allyEnemies: { number }?, -- с кем воюют наши союзники
	overlord: number?, -- наш сюзерен (мы — вассал)
	overlordPower: number?,
	canRebel: boolean?,
	leader: number?, -- держава ближе всех к победе (не мы), если её доля суши к победе от Bots.StopLeaderShare (§15п)
	tradeDeals: number?, -- сколько торговых соглашений (§8.2)
	alliesAtWar: { number }?, -- союзники, которые воюют (им можно помочь деньгами)
	money: number,
	oil: number,
	economy: { income: number, oilIncome: number, upkeep: number }, -- в секунду
	owned: {
		factories: number,
		rigs: number,
		forts: number,
		cityLevels: number,
		barracksLevel: number?, -- §15д: лучший уровень казарм (танки — 2, ПВО — 3)
		incomeBonus: number?, -- §15х ч.6: доля к доходу от заводов ур. 3
		housing: number?,
	},
	spots: BuildSpots,
	stability: number?, -- средняя стабильность своих провинций (§6.10, этап 7а)
	navy: NavyView?, -- флот (§6.12, этап 7б-1)
	air: AirView?, -- авиация (§6.13, этап 7б-2)
	tech: TechView?, -- технологии (§6.14, этап 7в-1)
}

-- Технологии бота (§6.14): изученные уровни веток и идёт ли исследование.
export type TechView = { Army: number, Economy: number, Fleet: number, researching: boolean }

-- Авиация бота (§6.13): что есть и куда бомбить — подбирает MatchSim (цель — лениво).
export type AirView = {
	airfield: number?, -- свой работающий аэродром (там нанимать)
	fighters: number, -- с очередью
	bombers: number,
	idleBomber: boolean, -- есть бомбардировщик на аэродроме
	raidTarget: (() -> number?)?, -- точка на линии фронта с врагом в радиусе авиации
	bombed: boolean, -- нас недавно бомбили (нужна батарея ПВО)
	bombedCell: number?, -- где бомбили в последний раз (в радиусе нашей авиации)
	coverFighter: number?, -- наш истребитель, который прикрывает другое место (можно перенацелить)
	homeFighter: number?, -- наш истребитель, который прикрывает свой аэродром (§15б: его можно выдвинуть к фронту)
	frontCover: (() -> number?)?, -- точка на линии фронта, где враг наступает на нас (в радиусе авиации)
}

-- Флот бота (§6.12): что есть и что можно сделать — подбирает MatchSim.
export type NavyView = {
	port: number?, -- свой незаблокированный порт (там нанимать)
	transports: number, -- с очередью
	destroyers: number,
	idlePort: number?, -- порт, у которого стоит свободный транспорт
	-- Куда высадиться: берег врага (активная война), иначе ничий берег (если по суше расти некуда). Ищется лениво.
	landTarget: (() -> number?)?,
	idleDestroyer: number?, -- эсминец без приказа (есть война)
	patrolTarget: (() -> number?)?, -- причал порта врага в море эсминца, иначе море у его берега
	need: boolean, -- флот нужен: по суше расти некуда, а за морем есть ничья земля, или враг за морем
}

-- Где можно строить (клетка для намерения build) — подбирает MatchSim.
export type BuildSpots = {
	free: number?, -- провинция без здания и без нефти
	oilRig: number?, -- провинция с нефтяным полем без вышки
	fort: number?, -- провинция у границы с врагом
	city: number?, -- свой город, который можно улучшить
	unstable: number?, -- своя провинция со стабильностью ниже Stability.LowBelow и без здания (§6.10)
	unstableCity: number?, -- свой город в такой провинции, который можно улучшить
	port: number?, -- своя прибрежная провинция без здания (§6.12)
	airfield: number?, -- своя провинция без здания, ближайшая к врагу (§6.13)
	battery: number?, -- своя провинция без здания, ближайшая к месту недавнего налёта на нас (сводная правка)
	sam: number?, -- §15х ч.6: ПВО у столицы под улучшение до ур. 3 (или место для новой) — у врага шахта
	factory: number?, -- §15х ч.6: свой завод ниже предела — улучшить (ур. 3 — +доход)
	barracks: number?, -- свои казармы, которые можно улучшить (§15д)
	batteryCovered: boolean?, -- место налёта уже прикрыто своей батареей ПВО — новую не ставить
}

-- Что бот знает, отвечая на предложение договора или требование (§8.1).
export type OfferView = {
	kind: Types.OfferKind,
	myPower: number, -- вся сила бота
	fromPower: number, -- вся сила предлагающего
	fromTraitor: boolean,
	fromIsLeader: boolean, -- предлагающий сам близок к победе
	threat: boolean, -- есть лидер (не мы и не предлагающий) — общая угроза
	atWarElsewhere: boolean, -- бот воюет с кем-то
	allies: number,
}

-- Что бот знает, голосуя в Совете держав (§8.2).
export type CouncilView = {
	options: { Types.Resolution },
	isLeader: boolean,
	losingWar: boolean,
	inTail: boolean, -- среди последних по суше (помощь слабым)
}

-- Что бот знает, отвечая на предложение мира.
export type PeaceOffer = {
	terms: Types.PeaceTerms,
	myGain: number,
	theirGain: number,
	myPower: number,
	theirPower: number,
}

-- Память бота между раздумьями: после отступления не лезть на того же врага сразу.
export type Memory = {
	retreatUntil: { [number]: number }, -- цель → simTime, до которого фронт против неё не открывать
	lastOfferAt: number?, -- когда бот последний раз что-то предлагал (§8.1)
}

-- Уровень и личность конкретного бота.
export type Profile = {
	level: Types.BotLevelParams,
	personality: Types.BotPersonalityParams,
	personalityName: Types.BotPersonality?, -- для порядка технологий (Config.Tech.BotOrder)
}

local BotBrain = {}

function BotBrain.newMemory(): Memory
	return { retreatUntil = {} }
end

function BotBrain.profile(level: Types.BotLevel?, personality: Types.BotPersonality?): Profile
	local name: Types.BotPersonality = personality or "Admiral"
	return {
		level = Config.BotLevels[level or "Normal"] or Config.BotLevels.Normal,
		personality = Config.BotPersonalities[name] or Config.BotPersonalities.Admiral,
		personalityName = name,
	}
end

-- Уровень бота по весам Bots.LevelMix (или Dev.BotLevel — все одного уровня).
function BotBrain.rollLevel(rng: Rng): Types.BotLevel
	local forced = Config.Dev.BotLevel
	for _, name: Types.BotLevel in Types.BotLevels do
		if name == forced then
			return name
		end
	end
	local mix = Config.Bots.LevelMix :: { [string]: number }
	local total = 0
	for _, name in Types.BotLevels do
		total += mix[name] or 0
	end
	local roll = Rng.nextFloat(rng) * total
	for _, name: Types.BotLevel in Types.BotLevels do
		roll -= mix[name] or 0
		if roll < 0 then
			return name
		end
	end
	return "Normal"
end

function BotBrain.rollPersonality(rng: Rng): Types.BotPersonality
	return Types.BotPersonalities[Rng.range(rng, 1, #Types.BotPersonalities)]
end

-- Через сколько секунд бот подумает снова.
function BotBrain.nextThinkDelay(rng: Rng, profile: Profile?): number
	local level = (profile or BotBrain.profile(nil, nil)).level
	return level.thinkMinSec + Rng.nextFloat(rng) * (level.thinkMaxSec - level.thinkMinSec)
end

-- Обычный бот: пехота чаще, танки и артиллерия реже.
local HIRE_ORDER: { Types.LandUnit } = { "Infantry", "Infantry", "Infantry", "Tanks", "Tanks", "Artillery" }

-- Насколько юнит kind хорош против состава enemyMix (§6.7 контр-типы) на единицу силы: содержание войск
-- идёт за силу, поэтому Генерал ценит качество, а деньги проверяет при найме. Без врага — среднее атаки и защиты.
function BotBrain.unitValue(kind: number, enemyMix: { number }?): number
	local stats = Forces.stats(kind)
	if enemyMix == nil then
		return (stats.attack + stats.defense) / 2
	end
	local name = Types.LandUnits[kind]
	local bonus = Config.Combat.CounterBonus - 1
	local good, bad = 0, 0
	for k, share in enemyMix do
		local enemyName = Types.LandUnits[k]
		if table.find((Config.Counters :: any)[name], enemyName) ~= nil then
			good += share
		end
		if table.find((Config.Counters :: any)[enemyName], name) ~= nil then
			bad += share
		end
	end
	return stats.attack * (1 + bonus * good) / (1 + bonus * bad)
end

-- Какой юнит нанять.
local function chooseUnit(view: BotView, profile: Profile, rng: Rng, enemyMix: { number }?): Types.LandUnit
	-- Техника — по уровню казарм (§15д): танки и пушки — ур. 2, ПВО — ур. 3.
	local barracks = view.owned.barracksLevel or 0
	local level = profile.level
	if barracks < 2 then
		return "Infantry"
	end
	local function allowed(kind: number): boolean
		local stats = Forces.stats(kind)
		return stats.requires ~= "Barracks" or barracks >= (stats.requiresLevel or 1)
	end
	if level.counterMix then
		local mine = view.mix
		if mine ~= nil and (mine[1] or 0) < Config.Bots.MinInfantryShare then
			return "Infantry"
		end
		local best, bestValue = 1, -1
		for k in Types.LandUnits do
			local v = BotBrain.unitValue(k, enemyMix)
			if v > bestValue and allowed(k) then
				best, bestValue = k, v
			end
		end
		return Types.LandUnits[best] :: Types.LandUnit
	end
	if level.randomTarget then
		return if Rng.nextFloat(rng) < Config.Bots.NoviceTanksChance then "Tanks" else "Infantry"
	end
	return HIRE_ORDER[Rng.range(rng, 1, #HIRE_ORDER)]
end

-- Что построить (§6.9), если хватает денег с запасом уровня.
local function chooseBuild(view: BotView, profile: Profile, rng: Rng, atWar: boolean): Types.Intent?
	local level, personality = profile.level, profile.personality
	local spots, owned = view.spots, view.owned
	local function want(kind: Types.BuildingKind, cell: number?): Types.Intent?
		if cell == nil then
			return nil
		end
		local stats = (Config.Buildings :: any)[kind]
		local price = stats.cost -- город ур. 3 дороже: не хватит — MatchSim откажет, бот попробует позже
		if view.money >= price + level.buildReserve then
			return { kind = "build", building = kind, cell = cell }
		end
		return nil
	end
	local fortSpot = if personality.forts then spots.fort else nil
	-- Новичок строит что попало: случайное из доступного.
	if level.randomTarget then
		local options: { Types.Intent } = {}
		local function add(intent: Types.Intent?)
			if intent ~= nil then
				table.insert(options, intent)
			end
		end
		add(want("Barracks", if (owned.barracksLevel or 0) == 0 then spots.free else spots.barracks))
		add(want("Factory", spots.free))
		add(want("Housing", spots.free))
		add(want("OilRig", spots.oilRig))
		add(want("Factory", spots.factory))
		add(want("City", spots.city))
		return if #options > 0 then options[Rng.range(rng, 1, #options)] else nil
	end
	-- Экономика 2.0 (§15д): казармы (линия найма), завод (деньги), казармы ур. 2 (танки и пушки).
	local barracks = owned.barracksLevel or 0
	if barracks == 0 then
		return want("Barracks", spots.free or spots.oilRig)
	end
	if owned.factories == 0 then
		return want("Factory", spots.free or spots.oilRig)
	end
	if barracks < 2 and spots.barracks ~= nil then
		local up = want("Barracks", spots.barracks)
		if up ~= nil then
			return up
		end
	end
	-- Порт (§6.12): Флотоводец — сразу после завода, остальные — когда без флота расти некуда.
	local navy = view.navy
	if spots.port ~= nil and (navy == nil or navy.port == nil) then
		if personality.navy >= 1 or (navy ~= nil and navy.need and personality.navy > 0) then
			local port = want("Port", spots.port)
			if port ~= nil then
				return port
			end
		end
	end
	-- Авиация (§6.13): в войне — аэродром после завода (Агрессор, Хитрец, любой Генерал); бомбят — батарея ПВО.
	local air = view.air
	if atWar and air ~= nil then
		local keen = personality.air >= 0.5 or level.smartTarget
		-- Сводная правка: самолётам нужна нефть — аэродром без нефтедобычи стоит без дела.
		if
			keen
			and air.airfield ~= nil
			and view.oil < (Config.Units :: any).Bomber.oil
			and view.economy.oilIncome <= 0
		then
			local rig = want("OilRig", spots.oilRig)
			if rig ~= nil then
				return rig
			end
		end
		if keen and air.airfield == nil and spots.airfield ~= nil then
			local airfield = want("Airfield", spots.airfield)
			if airfield ~= nil then
				return airfield
			end
		end
		-- §15х ч.6: у врага шахта — Генерал ставит у столицы дальнюю ПВО (ур. 3).
		if level.smartTarget and spots.sam ~= nil then
			local sam = want("AirDefense", spots.sam)
			if sam ~= nil then
				return sam
			end
		end
		if air.bombed and not spots.batteryCovered then
			-- Сводная правка: батарея — туда, куда бомбили (враг бьёт ту же линию снова).
			local battery = want("AirDefense", spots.battery or spots.fort or spots.free)
			if battery ~= nil then
				return battery
			end
		end
	end
	-- Нестабильная провинция (§6.10): укрепление или улучшение города поднимают стабильность.
	-- Не больше Stability.BotCalmForts укреплений: деньги нужны и на войска.
	if owned.forts < Config.Stability.BotCalmForts then
		local calm = want("Fort", spots.unstable) or want("City", spots.unstableCity)
		if calm ~= nil then
			return calm
		end
	end
	-- Генерал в войне сначала укрепляет границу с врагом.
	if level.smartTarget and atWar and owned.forts < 1 + owned.factories then
		local fort = want("Fort", fortSpot)
		if fort ~= nil then
			return fort
		end
	end
	return want("OilRig", if owned.rigs < Config.Bots.MaxRigs then spots.oilRig else nil)
		or want("Factory", if owned.factories <= personality.maxFactories then spots.free else nil)
		or want("Barracks", if atWar or barracks < 2 then spots.barracks else nil)
		or want("Housing", if (owned.housing or 0) < 1 + owned.factories // 2 then spots.free else nil)
		-- §15х ч.6: улучшить завод (ур. 3 — +доход, бывший «Рынок»): заводов ур. 3 — до половины maxFactories (улучшение —
		-- два шага, и каждый сам даёт деньги; так бот строит примерно столько же раз, сколько с рынками).
		or want(
			"Factory",
			if (owned.incomeBonus or 0)
					< math.ceil(personality.maxFactories / 2) * Config.Buildings.Factory.incomeBonus
				then spots.factory
				else nil
		)
		or want("Fort", fortSpot)
		or want("City", spots.city)
end

-- Флот (§6.12): высадка, патруль к порту врага, найм кораблей. Новичок флотом не пользуется.
-- Нефть, которую бот с аэродромом бережёт на первые самолёты (§15б): пока нет бомбардировщика или истребителя,
-- танки и корабли не тратят нефть ниже цены бомбардировщика (денег у ботов хватает, нефти — нет).
function BotBrain.oilForPlanes(view: BotView): number
	local air = view.air
	if air == nil or air.airfield == nil then
		return 0
	end
	if air.bombers < Config.Air.BotBombers or air.fighters < Config.Air.BotFighters then
		return (Config.Units :: any).Bomber.oil
	end
	return 0
end

local function navyDecision(view: BotView, p: Profile, rng: Rng): Types.Intent?
	local navy = view.navy
	local level, personality = p.level, p.personality
	if navy == nil or level.randomTarget or personality.navy <= 0 then
		return nil
	end
	local keen = personality.navy >= 1
	if not keen and not navy.need then
		return nil
	end
	local cfg = Config.Naval
	if Rng.nextFloat(rng) >= cfg.BotLandChance * personality.navy * (if navy.need then 2 else 1) then
		return nil
	end
	-- Высадка: на врага — войсками, на ничью землю — людьми и войсками.
	local landTarget = navy.landTarget
	if navy.idlePort ~= nil and landTarget ~= nil and view.power >= Config.Forces.MinFrontStrength * 2 then
		local target = landTarget()
		if target ~= nil then
			return { kind = "land", port = navy.idlePort, target = target, percent = cfg.BotLandShare }
		end
	end
	local patrolTarget = navy.patrolTarget
	if navy.idleDestroyer ~= nil and patrolTarget ~= nil then
		local cell = patrolTarget()
		if cell ~= nil then
			return { kind = "patrol", ship = navy.idleDestroyer, cell = cell }
		end
	end
	if navy.port ~= nil then
		local scale = math.max(1, math.round(personality.navy * 2))
		local kind: Types.ShipKind? = if navy.transports < cfg.BotTransports * scale
			then "Transport"
			elseif navy.destroyers < cfg.BotDestroyers * scale then "Destroyer"
			else nil
		if kind ~= nil then
			local stats = (Config.Units :: any)[kind]
			if
				view.money >= stats.cost + level.buildReserve
				and view.oil >= stats.oil + BotBrain.oilForPlanes(view)
			then
				return { kind = "ship", ship = kind, port = navy.port }
			end
		end
	end
	return nil
end

-- Авиация (§6.13): налёт на линию фронта, найм самолётов. Новичок авиацией не пользуется.
local function airDecision(view: BotView, p: Profile, rng: Rng): Types.Intent?
	local air = view.air
	local level, personality = p.level, p.personality
	if air == nil or level.randomTarget then
		return nil
	end
	-- Генерал под бомбами (§6.13): истребитель прикрывает место налёта, а если истребителей мало — нанимает их.
	-- Сводная правка: так же — личности, любящие авиацию (Хитрец, Агрессор).
	if (level.smartTarget or personality.air >= Config.Air.BotCoverAir) and air.bombed then
		local bombedCell, fighter = air.bombedCell, air.coverFighter
		if bombedCell ~= nil and fighter ~= nil then
			return { kind = "cover", plane = fighter, cell = bombedCell }
		end
		if air.airfield ~= nil and air.fighters < Config.Air.BotFightersWhenBombed then
			local stats = (Config.Units :: any).Fighter
			if view.money >= stats.cost and view.oil >= stats.oil then
				return { kind = "plane", plane = "Fighter", airfield = air.airfield }
			end
		end
	end
	-- §15б: в войне истребитель не сидит над аэродромом — прикрывает фронт, куда летят бомбардировщики врага.
	local frontCover = air.frontCover
	if
		(level.smartTarget or personality.air >= Config.Air.BotCoverAir)
		and air.homeFighter ~= nil
		and frontCover ~= nil
	then
		local cell = frontCover()
		if cell ~= nil then
			return { kind = "cover", plane = air.homeFighter, cell = cell }
		end
	end
	local interest = math.max(personality.air, if level.smartTarget then 0.6 else 0)
	if interest <= 0 or Rng.nextFloat(rng) >= Config.Air.BotRaidChance * interest then
		return nil
	end
	local raidTarget = air.raidTarget
	if air.idleBomber and raidTarget ~= nil then
		local cell = raidTarget()
		if cell ~= nil then
			return { kind = "raid", cell = cell }
		end
	end
	if air.airfield ~= nil then
		local kind: Types.PlaneKind? = if air.bombers < Config.Air.BotBombers
			then "Bomber"
			elseif air.fighters < Config.Air.BotFighters then "Fighter"
			else nil
		if kind ~= nil then
			local stats = (Config.Units :: any)[kind]
			if view.money >= stats.cost + level.buildReserve and view.oil >= stats.oil then
				return { kind = "plane", plane = kind, airfield = air.airfield }
			end
		end
	end
	return nil
end

-- Технологии (§6.14): какую ветку бот хочет следующей — по порядку личности (Генерал — по своей очереди),
-- Новичок — случайно. Деньги не проверяет. Возвращает ветку и цену её следующего уровня.
local function techWanted(view: BotView, p: Profile, rng: Rng?): (string?, number)
	local tech = view.tech
	if tech == nil or tech.researching then
		return nil, 0
	end
	local cfg = Config.Tech
	local function nextLevel(branch: string): number?
		local level = (tech :: any)[branch] + 1
		local locked = (cfg.Locked :: any)[branch]
		if level > #cfg.Cost or (locked ~= nil and level >= locked) then
			return nil
		end
		return level
	end
	local branch: string? = nil
	if p.level.randomTarget then
		if rng == nil then
			return nil, 0
		end
		local open: { string } = {}
		for _, b in { "Army", "Economy", "Fleet" } do
			if nextLevel(b) ~= nil then
				table.insert(open, b)
			end
		end
		if #open > 0 then
			branch = open[Rng.range(rng, 1, #open)]
		end
	else
		-- Очередь (Генерал — своя, остальные — по личности): первая запись, уровень которой ещё не изучен.
		local order: { string } = if p.level.smartTarget
			then cfg.GeneralOrder
			else (cfg.BotOrder :: any)[p.personalityName or ""] or cfg.GeneralOrder
		local seen: { [string]: number } = {}
		for _, b: string in order do
			seen[b] = (seen[b] or 0) + 1
			if nextLevel(b) == seen[b] then
				branch = b
				break
			end
		end
	end
	if branch == nil then
		return nil, 0
	end
	return branch, cfg.Cost[nextLevel(branch) :: number]
end

-- Технология, которую бот начнёт сейчас: желаемая ветка, если хватает денег с запасом уровня.
function BotBrain.techChoice(view: BotView, p: Profile, rng: Rng): Types.TechBranch?
	local branch, cost = techWanted(view, p, rng)
	if branch == nil or view.money < cost + p.level.buildReserve then
		return nil
	end
	return branch :: any
end

-- Копилка на технологию (§6.14): в мире бот (не Новичок) не тратит на найм деньги следующего уровня.
function BotBrain.techSavings(view: BotView, p: Profile): number
	if p.level.randomTarget then
		return 0
	end
	if #view.wars > 0 then
		return 0 -- война или мобилизация: деньги — на войска
	end
	local _, cost = techWanted(view, p, nil)
	return cost * Config.Tech.BotSaveShare
end

local function techDecision(view: BotView, p: Profile, rng: Rng): Types.Intent?
	if view.tech == nil then
		return nil
	end
	local chance = Config.Tech.BotChance * (if p.level.randomTarget then 0.3 else 1)
	if Rng.nextFloat(rng) >= chance then
		return nil
	end
	local branch = BotBrain.techChoice(view, p, rng)
	if branch == nil then
		return nil
	end
	local intent: Types.ResearchIntent = { kind = "research", branch = branch :: Types.TechBranch }
	return intent
end

-- §15п: во сколько раз гарнизон соседа слабее у нашей границы — лидер (доля суши к победе от StopLeaderShare),
-- воюющий с другими, делит гарнизон по фронтам: (его войн + 1), не больше LeaderSplitMax. Остальные — 1.
function BotBrain.leaderSplit(n: Neighbour): number
	if (n.share or 0) < Config.Bots.StopLeaderShare then
		return 1
	end
	return math.clamp(1 + (n.enemies or 0), 1, Config.Bots.LeaderSplitMax)
end

-- Оценка цели войны (Генерал, §9.1): перевес, длина границы, враг отвлечён, лидер, добыча.
function BotBrain.targetScore(
	n: Neighbour,
	send: number,
	personality: Types.BotPersonalityParams,
	maxBorder: number
): number
	local defense = math.max(1, n.power * Config.Combat.DefenderHomeBonus / BotBrain.leaderSplit(n))
	local score = math.min(send / defense, 4)
	score *= 0.5 + math.min(1, (n.border or 0) / math.max(1, maxBorder))
	if n.distracted then
		score *= personality.distracted
	end
	if (n.share or 0) >= Config.Bots.StopLeaderShare then
		score *= personality.leader
	end
	score *= 1 + 0.1 * math.min(n.cities or 0, 5)
	return score
end

-- Лучшая цель из соседей, подходящих filter.
local function pickTarget(
	view: BotView,
	profile: Profile,
	rng: Rng,
	send: number,
	filter: (n: Neighbour) -> boolean
): Neighbour?
	local level = profile.level
	local candidates: { Neighbour } = {}
	local maxBorder = 1
	for _, n in view.neighbours do
		if filter(n) then
			table.insert(candidates, n)
			maxBorder = math.max(maxBorder, n.border or 0)
		end
	end
	-- §15у: за союзником с полным доверием — тоже цели (удар через его землю).
	local reach: { Neighbour } = view.reach or {}
	for _, n in reach do
		if filter(n) then
			table.insert(candidates, n)
		end
	end
	if #candidates == 0 then
		return nil
	end
	if level.randomTarget then
		return candidates[Rng.range(rng, 1, #candidates)]
	end
	local best: Neighbour? = nil
	local bestScore = -math.huge
	for _, n in candidates do
		-- Обычный — «слабейший» сосед; гарнизон лидера на нескольких фронтах — делённый (§15п).
		local s = if level.smartTarget
			then BotBrain.targetScore(n, send, profile.personality, maxBorder)
			else -n.power / BotBrain.leaderSplit(n)
		if s > bestScore then
			best, bestScore = n, s
		end
	end
	return best
end

local function frontAgainst(view: BotView, target: number): FrontView?
	local fronts: { FrontView } = view.fronts or {}
	for _, f in fronts do
		if f.target == target then
			return f
		end
	end
	return nil
end

-- Дипломатия бота за раздумье (§8.1): независимость, вступление в войну союзника, предательство, предложения.
local function diplomacy(view: BotView, p: Profile, rng: Rng, memory: Memory?, now: number, send: number): Types.Intent?
	local personality = p.personality
	local cfg = Config.Diplomacy
	-- Вассал окреп — независимость.
	if view.overlord ~= nil and view.canRebel and view.totalPower >= (view.overlordPower or 0) * cfg.RebelAbove then
		return { kind = "rebel" }
	end
	-- Союзник воюет — верный бот вступает в войну против его врага-соседа.
	-- §15у: и против врага за союзником с полным доверием (бить будет через него).
	local allyEnemies: { number } = view.allyEnemies or {}
	for _, enemy in allyEnemies do
		for _, n in view.neighbours do
			if
				n.id == enemy
				and n.canDeclare
				and send >= Config.Forces.MinFrontStrength
				and Rng.nextFloat(rng) < 0.5 * personality.loyalty
			then
				return { kind = "declare", target = n.id }
			end
		end
		local reach: { Neighbour } = view.reach or {}
		for _, n in reach do
			if
				n.id == enemy
				and n.canJoin
				and send >= Config.Forces.MinFrontStrength
				and Rng.nextFloat(rng) < 0.5 * personality.loyalty
			then
				return { kind = "declare", target = n.id }
			end
		end
	end
	-- Хитрец бьёт в спину партнёру по союзу или пакту (§8.1):
	-- 1) партнёр воюет с кем-то ещё и потерял больше трети войск — удобный момент, хватит и равных сил
	--    (так поступают только записные предатели: betray от Diplomacy.OpportunistBetray — Хитрец);
	-- 2) или партнёр просто намного слабее, а сам Хитрец ни с кем не воюет.
	if personality.betray > 0 and #view.wars <= 1 then
		for _, n in view.neighbours do
			if (n.treaty == "alliance" or n.treaty == "pact") and send >= Config.Forces.MinFrontStrength then
				local defense = n.power * Config.Combat.DefenderHomeBonus
				local opportunity = personality.betray >= cfg.OpportunistBetray
					and n.weakened == true
					and send >= defense * cfg.BetrayWeakenedAdvantage
					and Rng.nextFloat(rng) < cfg.BetrayWeakenedChance * personality.betray
				-- Пакт ломают только записные предатели; союзника — любой, у кого betray > 0 (как в 6а).
				local crushing = #view.wars == 0
					and (n.treaty == "alliance" or personality.betray >= cfg.OpportunistBetray)
					and send >= defense * cfg.BetrayAdvantage
					and Rng.nextFloat(rng) < 0.2 * personality.betray
				if opportunity or crushing then
					return { kind = "declare", target = n.id }
				end
			end
		end
	end
	-- Богатый бот помогает союзнику, который воюет (§8.2).
	local allyAtWar = (view.alliesAtWar or {})[1]
	if
		allyAtWar ~= nil
		and view.money > Config.Trade.BotGiftReserve
		and Rng.nextFloat(rng) < 0.3 * personality.loyalty
	then
		local gift = math.min(
			Config.Trade.LimitPerMinute.money,
			math.floor((view.money - Config.Trade.BotGiftReserve) * Config.Trade.BotGiftShare)
		)
		if gift > 0 then
			return { kind = "transfer", target = allyAtWar, money = gift, oil = 0, people = 0 }
		end
	end
	-- Предложения — не чаще OfferRetrySec и с вероятностью по личности.
	local last = if memory ~= nil then memory.lastOfferAt else nil
	if last ~= nil and now - last < cfg.OfferRetrySec then
		return nil
	end
	if Rng.nextFloat(rng) >= cfg.OfferChance * personality.alliance then
		return nil
	end
	local function made(intent: Types.Intent): Types.Intent
		if memory ~= nil then
			memory.lastOfferAt = now
		end
		return intent
	end
	-- §15у: верный бот предлагает союзнику полное доверие (союз уже достаточно старый — trustReady).
	-- Случайное число берётся, только если есть кому предложить (иначе поток решений не меняется).
	if personality.loyalty >= Config.Alliance.BotTrustLoyalty then
		for _, n in view.neighbours do
			if n.trustReady and not n.traitor then
				if Rng.nextFloat(rng) < Config.Alliance.BotTrustChance then
					return made({ kind = "offer", target = n.id, offer = "trust" })
				end
				break
			end
		end
	end
	-- Союз против лидера: с самым сильным соседом, который не лидер и не предатель.
	if view.leader ~= nil and view.overlord == nil and (view.allies or 0) < Config.Match.MaxAlliesFfa then
		local best: Neighbour? = nil
		for _, n in view.neighbours do
			if
				n.id ~= view.leader
				and not n.traitor
				and n.treaty ~= "alliance"
				and n.treaty ~= "vassal"
				and n.treaty ~= "overlord"
				and not n.atWar
				and (best == nil or n.power > best.power)
			then
				best = n
			end
		end
		if best ~= nil then
			return made({ kind = "offer", target = best.id, offer = "alliance" })
		end
	end
	-- Торговое соглашение с соседом в мире (Торговцы — охотнее всех).
	if (view.tradeDeals or 0) < Config.Trade.MaxAgreements and Rng.nextFloat(rng) < 0.5 * personality.trade then
		for _, n in view.neighbours do
			if not n.trade and not n.embargo and not n.atWar and not n.traitor and n.treaty ~= "overlord" then
				return made({ kind = "offer", target = n.id, offer = "trade" })
			end
		end
	end
	-- Воюем — пакт с сильным соседом, чтобы не получить второй фронт.
	if #view.wars > 0 then
		for _, n in view.neighbours do
			if
				n.treaty == nil
				and not n.atWar
				and not n.traitor
				and n.power >= view.power * cfg.PactAgainstStronger
			then
				return made({ kind = "offer", target = n.id, offer = "pact5" })
			end
		end
	end
	-- Хитрец сам набирает пакты с соседями: чем больше договоров, тем больше удобных моментов для удара в спину.
	if personality.betray >= Config.Diplomacy.OpportunistBetray then
		for _, n in view.neighbours do
			if n.treaty == nil and not n.atWar and not n.traitor and n.canDeclare then
				return made({ kind = "offer", target = n.id, offer = "pact5" })
			end
		end
	end
	-- Требование к слабому соседу.
	if personality.demand > 0 and Rng.nextFloat(rng) < personality.demand then
		for _, n in view.neighbours do
			if
				n.treaty == nil
				and n.canDeclare
				and n.demandProvince ~= nil
				and send >= math.max(Config.Forces.MinFrontStrength, n.power * cfg.DemandAdvantage)
			then
				return made({ kind = "offer", target = n.id, offer = "demand", province = n.demandProvince })
			end
		end
	end
	return nil
end
BotBrain.diplomacy = diplomacy

-- Отдельные потоки случайных чисел бота для флота, авиации и дипломатии (§12): новые решения в этих системах
-- не сдвигают числа главных решений. Без них всё берётся из rng (тесты).
export type Streams = { navy: Rng?, air: Rng?, diplo: Rng?, tech: Rng? }

function BotBrain.decide(view: BotView, rng: Rng, profile: Profile?, memory: Memory?, streams: Streams?): Types.Intent?
	local p = profile or BotBrain.profile(nil, nil)
	local now = view.time or 0
	local level, personality = p.level, p.personality
	local cfg = Config.Bots
	if level.mistake > 0 and Rng.nextFloat(rng) < level.mistake then
		return nil
	end

	-- Фронт стоит и проигрывает (или без снабжения) — войска домой.
	local fronts: { FrontView } = view.fronts or {}
	if level.cancelBelowRatio > 0 then
		for _, f in fronts do
			if f.target ~= 0 and f.fighting and f.stalledSec >= level.cancelAfterSec then
				if f.ratio < level.cancelBelowRatio or (level.cancelUnsupplied and not f.supplied) then
					if memory ~= nil then
						memory.retreatUntil[f.target] = now + Config.Bots.RetreatSec
					end
					return { kind = "cancel", target = f.target }
				end
			end
		end
	end

	local atWar = false
	for _, n in view.neighbours do
		if n.atWar then
			atWar = true
		end
	end

	local frontPercent = math.clamp(level.frontPercent * personality.front, 0.1, 0.9)
	local send = view.power * frontPercent
	-- §15с: война с соседом, а своего фронта против врагов нет — сначала фронт (Обычный и Генерал; Новичок — как был).
	if
		cfg.FrontFirst
		and atWar
		and not level.randomTarget
		and send >= Config.Forces.MinFrontStrength
		and view.attacks < cfg.MaxAttacks
	then
		local hasFront = false
		for _, f in fronts do
			if f.target ~= 0 then
				hasFront = true
				break
			end
		end
		if not hasFront then
			local first = pickTarget(view, p, rng, send, function(n: Neighbour): boolean
				local until_ = if memory ~= nil then memory.retreatUntil[n.id] else nil
				return n.atWar and (until_ == nil or now >= until_)
			end)
			if first ~= nil then
				return {
					kind = "attack",
					target = first.id,
					percent = frontPercent,
					focus = if level.useFocus then first.city else nil,
				}
			end
		end
	end

	if Rng.nextFloat(rng) < level.buildChance * personality.build then
		local build = chooseBuild(view, p, rng, atWar)
		if build ~= nil then
			return build
		end
	end

	local navalIntent = navyDecision(view, p, if streams ~= nil and streams.navy ~= nil then streams.navy else rng)
	if navalIntent ~= nil then
		return navalIntent
	end
	local airIntent = airDecision(view, p, if streams ~= nil and streams.air ~= nil then streams.air else rng)
	if airIntent ~= nil then
		return airIntent
	end
	local techIntent = techDecision(view, p, if streams ~= nil and streams.tech ~= nil then streams.tech else rng)
	if techIntent ~= nil then
		return techIntent
	end

	-- Против кого война: лучшая цель среди тех, с кем воюем.
	local enemy = pickTarget(view, p, rng, send, function(n: Neighbour): boolean
		local until_ = if memory ~= nil then memory.retreatUntil[n.id] else nil
		return n.atWar and (until_ == nil or now >= until_)
	end)

	if
		view.hasCapital
		and view.queue < level.maxQueue
		and view.people
			>= view.maxPeople
				* level.hireWhenFill
				-- §15с: в войне нанимает раньше (BotLevels.*.warHireFillMul)
				* (if atWar then level.warHireFillMul else 1)
		-- Угроза (война или мобилизация): Торговец нанимает чаще (personality.threatHire).
		and Rng.nextFloat(rng)
			< level.hireChance * personality.hire * (if #view.wars > 0 then personality.threatHire or 1 else 1)
	then
		local enemyMix = if enemy ~= nil then enemy.mix else nil
		local unit: Types.LandUnit = chooseUnit(view, p, rng, enemyMix)
		local savings = BotBrain.techSavings(view, p)
		local function affordable(u: Types.LandUnit): boolean
			local stats = Forces.stats(Forces.kindIndex(u) :: number)
			local net = view.economy.income - view.economy.upkeep
			return view.people >= stats.people
				and view.money >= stats.cost + savings
				and view.oil >= stats.oil + (if stats.oil > 0 then BotBrain.oilForPlanes(view) else 0)
				and net >= Economy.upkeep(stats.strength)
		end
		-- Хватает людей, денег, нефти, и доход покроет содержание; не хватает на выбранный — пехота.
		if affordable(unit) then
			return { kind = "hire", unit = unit }
		elseif unit ~= "Infantry" and level.counterMix and affordable("Infantry") then
			return { kind = "hire", unit = "Infantry" }
		end
	end

	-- Мир: долгая война, а мы сильно слабее. Земля бунтует (§6.10) — просим раньше.
	local unrest = if view.stability ~= nil and view.stability < Config.Stability.BotPeaceBelow
		then Config.Stability.BotPeaceMul
		else 1
	for _, war in view.wars do
		if
			war.active
			and war.canPropose
			and war.age >= level.peaceAfterSec
			and view.totalPower < war.theirPower * cfg.PeaceWhenWeaker * personality.peace * unrest
		then
			-- Сначала просит белый мир; не вышло — готов отдать захваченное, лишь бы война кончилась.
			local keep = war.myGain > war.theirGain
				or war.proposedBefore
				or view.totalPower < war.theirPower * cfg.ConcedeWhenWeaker
			local terms: Types.PeaceTerms = if keep then "keep" else "white"
			-- Уже просил, а войск меньше трети врага — капитуляция, вассалитет (§8.1).
			if
				war.proposedBefore
				and view.overlord == nil
				and view.totalPower < war.theirPower * Config.Diplomacy.CapitulateBelow
			then
				terms = "capitulate"
			end
			return { kind = "peace", target = war.enemy, terms = terms }
		end
	end

	local diplo =
		diplomacy(view, p, if streams ~= nil and streams.diplo ~= nil then streams.diplo else rng, memory, now, send)
	if diplo ~= nil then
		return diplo
	end

	-- Война идёт — фронт против лучшей цели или подкрепление.
	if enemy ~= nil and send >= Config.Forces.MinFrontStrength then
		local existing = frontAgainst(view, enemy.id)
		local open = if existing == nil
			then view.attacks < cfg.MaxAttacks
			else (not level.smartTarget or existing.ratio < cfg.ReinforceBelowRatio)
		if open then
			return {
				kind = "attack",
				target = enemy.id,
				percent = frontPercent,
				focus = if level.useFocus then enemy.city else nil,
			}
		end
	end

	if view.hasNeutral then
		if view.people < view.maxPeople * level.attackWhenFill then
			return nil
		end
		-- Если атака на ничью землю уже идёт, MatchSim сольёт отряды — это подкрепление.
		if view.attacks >= cfg.MaxAttacks and frontAgainst(view, 0) == nil then
			return nil
		end
		return { kind = "attack", target = 0, percent = cfg.NeutralPercent }
	end

	if view.attacks >= cfg.MaxAttacks then
		return nil
	end
	-- Ничьей земли нет — объявить войну, если войск хватает.
	local maxWars = personality.maxWars
	if level.secondWar and #view.wars >= maxWars and #view.wars > 0 then
		-- Генерал берётся за вторую войну, только если все фронты идут с большим перевесом.
		local winning = true
		for _, f in fronts do
			if f.target ~= 0 and f.ratio < cfg.SecondWarAboveRatio then
				winning = false
			end
		end
		if winning then
			maxWars += 1
		end
	end
	if #view.wars >= maxWars then
		return nil
	end
	local target = pickTarget(view, p, rng, send, function(n: Neighbour): boolean
		return n.canDeclare
	end)
	if target == nil then
		return nil
	end
	local defense = target.power
		* (if level.smartTarget then Config.Combat.DefenderHomeBonus else 1)
		/ (if level.randomTarget then 1 else BotBrain.leaderSplit(target)) -- §15п: лидер на нескольких фронтах; Новичок — как был
	local need = math.max(Config.Forces.MinFrontStrength, defense * level.advantage * personality.declare)
	if send >= need then
		return { kind = "declare", target = target.id }
	end
	return nil
end

-- Ответ бота на предложение мира (миролюбивые соглашаются охотнее).
function BotBrain.answerPeace(offer: PeaceOffer, profile: Profile?): boolean
	local cfg = Config.Bots
	local peace = if profile ~= nil then profile.personality.peace else 1
	if offer.terms == "capitulate" then
		return true -- вассал платит дань и не воюет с нами — выгодно
	end
	if offer.terms == "white" then
		-- Белый мир вернёт всё взятое: выгоден тому, кто проигрывает.
		return offer.myPower < offer.theirPower * cfg.AcceptWhiteWhenWeaker * peace or offer.theirGain > offer.myGain
	end
	-- «Забрать захваченное»: соглашаемся, если сами взяли не меньше или сильно слабее.
	return offer.myGain >= offer.theirGain or offer.myPower < offer.theirPower * cfg.AcceptKeepWhenWeaker * peace
end

-- Голос бота в Совете (§8.2): номер варианта.
function BotBrain.councilVote(view: CouncilView, profile: Profile?): number
	local p = profile or BotBrain.profile(nil, nil)
	local best, bestScore = 1, -math.huge
	for k, option in view.options do
		local score = 0
		if option == "sanctions" then
			score = if view.isLeader then -10 else 1
		elseif option == "truce" then
			score = if view.losingWar then 1.5 elseif view.isLeader then -0.5 else 0.2
		elseif option == "aid" then
			score = if view.inTail then 2 else 0.3
		elseif option == "freeTrade" then
			score = 0.4 * p.personality.trade
		elseif option == "superweaponBan" then
			score = if view.isLeader then -1 else 0.5
		end
		if score > bestScore then
			best, bestScore = k, score
		end
	end
	return best
end

-- Ответ бота на предложение договора или требование (§8.1). С «Предателем» договоров нет.
function BotBrain.answerOffer(offer: OfferView, profile: Profile?): boolean
	local p = profile or BotBrain.profile(nil, nil)
	local personality = p.personality
	local cfg = Config.Diplomacy
	if offer.kind == "demand" then
		-- Отдаёт провинцию, только если сильно слабее: иначе — война.
		return offer.myPower < offer.fromPower * cfg.DemandYieldBelow
	end
	if offer.fromTraitor then
		return false
	end
	if offer.kind == "trade" then
		return true -- +5% дохода обоим; войны и эмбарго проверены при предложении
	end
	if offer.kind == "alliance" then
		if offer.allies >= Config.Match.MaxAlliesFfa or offer.fromIsLeader then
			return false
		end
		local stronger = offer.fromPower >= offer.myPower * cfg.AllyStrongerShare
		local score = personality.alliance * (if offer.threat then 1 else 0.6) * (if stronger then 1.2 else 0.9)
		return score >= 0.9
	end
	if offer.kind == "trust" then
		-- §15у: полное доверие — не лидеру; при общей угрозе, своей войне или если бот верный.
		if offer.fromIsLeader then
			return false
		end
		return offer.threat or offer.atWarElsewhere or personality.loyalty >= Config.Alliance.BotTrustLoyalty
	end
	-- Пакт: соглашается, если сам не собирался нападать (сосед не слабак), если занят войной или миролюбив.
	return offer.fromPower >= offer.myPower * 0.7 or offer.atWarElsewhere or personality.alliance >= 1.3
end

return table.freeze(BotBrain)
