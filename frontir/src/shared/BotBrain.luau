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
	mix: { number }?, -- доли типов войск гарнизона (Types.LandUnits)
	city: number?, -- его город, ближайший к нашей столице (направление удара)
	cities: number?, -- сколько у него городов
	treaty: ("pact" | "alliance" | "vassal" | "overlord")?, -- договор с нами (§8.1)
	traitor: boolean?, -- метка «Предатель»
	demandProvince: number?, -- его провинция у нашей границы, которую можно потребовать
	trade: boolean?, -- с ним торговое соглашение (§8.2)
	weakened: boolean?, -- воюет с кем-то ещё и потерял больше Diplomacy.BetrayLossShare войск
	embargo: boolean?, -- между нами эмбарго
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
	leader: number?, -- держава ближе всех к победе (не мы), если её доля суши от Bots.StopLeaderShare
	tradeDeals: number?, -- сколько торговых соглашений (§8.2)
	alliesAtWar: { number }?, -- союзники, которые воюют (им можно помочь деньгами)
	money: number,
	oil: number,
	economy: { income: number, oilIncome: number, upkeep: number }, -- в секунду
	owned: { factories: number, markets: number, rigs: number, forts: number, cityLevels: number },
	spots: BuildSpots,
	stability: number?, -- средняя стабильность своих провинций (§6.10, этап 7а)
	navy: NavyView?, -- флот (§6.12, этап 7б-1)
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
}

local BotBrain = {}

function BotBrain.newMemory(): Memory
	return { retreatUntil = {} }
end

function BotBrain.profile(level: Types.BotLevel?, personality: Types.BotPersonality?): Profile
	return {
		level = Config.BotLevels[level or "Normal"] or Config.BotLevels.Normal,
		personality = Config.BotPersonalities[personality or "Admiral"] or Config.BotPersonalities.Admiral,
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
	local hasFactory = view.owned.factories > 0
	local level = profile.level
	if not hasFactory then
		return "Infantry"
	end
	if level.counterMix then
		local mine = view.mix
		if mine ~= nil and (mine[1] or 0) < Config.Bots.MinInfantryShare then
			return "Infantry"
		end
		local best, bestValue = 1, -1
		for k in Types.LandUnits do
			local v = BotBrain.unitValue(k, enemyMix)
			if v > bestValue then
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
		add(want("Factory", if owned.factories == 0 then spots.free else nil))
		add(want("OilRig", spots.oilRig))
		add(want("Market", spots.free))
		add(want("City", spots.city))
		return if #options > 0 then options[Rng.range(rng, 1, #options)] else nil
	end
	if owned.factories == 0 then
		return want("Factory", spots.free or spots.oilRig)
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
		or want("Market", if owned.markets < personality.maxMarkets then spots.free else nil)
		or want("Fort", fortSpot)
		or want("City", spots.city)
end

-- Флот (§6.12): высадка, патруль к порту врага, найм кораблей. Новичок флотом не пользуется.
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
			if view.money >= stats.cost + level.buildReserve and view.oil >= stats.oil then
				return { kind = "ship", ship = kind, port = navy.port }
			end
		end
	end
	return nil
end

-- Оценка цели войны (Генерал, §9.1): перевес, длина границы, враг отвлечён, лидер, добыча.
function BotBrain.targetScore(
	n: Neighbour,
	send: number,
	personality: Types.BotPersonalityParams,
	maxBorder: number
): number
	local defense = math.max(1, n.power * Config.Combat.DefenderHomeBonus)
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
	if #candidates == 0 then
		return nil
	end
	if level.randomTarget then
		return candidates[Rng.range(rng, 1, #candidates)]
	end
	local best: Neighbour? = nil
	local bestScore = -math.huge
	for _, n in candidates do
		local s = if level.smartTarget then BotBrain.targetScore(n, send, profile.personality, maxBorder) else -n.power -- слабейший
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

function BotBrain.decide(view: BotView, rng: Rng, profile: Profile?, memory: Memory?): Types.Intent?
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

	if Rng.nextFloat(rng) < level.buildChance * personality.build then
		local build = chooseBuild(view, p, rng, atWar)
		if build ~= nil then
			return build
		end
	end

	local navalIntent = navyDecision(view, p, rng)
	if navalIntent ~= nil then
		return navalIntent
	end

	local frontPercent = math.clamp(level.frontPercent * personality.front, 0.1, 0.9)
	local send = view.power * frontPercent
	-- Против кого война: лучшая цель среди тех, с кем воюем.
	local enemy = pickTarget(view, p, rng, send, function(n: Neighbour): boolean
		local until_ = if memory ~= nil then memory.retreatUntil[n.id] else nil
		return n.atWar and (until_ == nil or now >= until_)
	end)

	if
		view.hasCapital
		and view.queue < level.maxQueue
		and view.people >= view.maxPeople * level.hireWhenFill
		and Rng.nextFloat(rng) < level.hireChance * personality.hire
	then
		local enemyMix = if enemy ~= nil then enemy.mix else nil
		local unit: Types.LandUnit = chooseUnit(view, p, rng, enemyMix)
		local function affordable(u: Types.LandUnit): boolean
			local stats = Forces.stats(Forces.kindIndex(u) :: number)
			local net = view.economy.income - view.economy.upkeep
			return view.people >= stats.people
				and view.money >= stats.cost
				and view.oil >= stats.oil
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

	local diplo = diplomacy(view, p, rng, memory, now, send)
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
	local defense = target.power * (if level.smartTarget then Config.Combat.DefenderHomeBonus else 1)
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
	-- Пакт: соглашается, если сам не собирался нападать (сосед не слабак), если занят войной или миролюбив.
	return offer.fromPower >= offer.myPower * 0.7 or offer.atWarElsewhere or personality.alliance >= 1.3
end

return table.freeze(BotBrain)
