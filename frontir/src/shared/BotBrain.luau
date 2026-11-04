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
	money: number,
	oil: number,
	economy: { income: number, oilIncome: number, upkeep: number }, -- в секунду
	owned: { factories: number, markets: number, rigs: number, forts: number, cityLevels: number },
	spots: BuildSpots,
}

-- Где можно строить (клетка для намерения build) — подбирает MatchSim.
export type BuildSpots = {
	free: number?, -- провинция без здания и без нефти
	oilRig: number?, -- провинция с нефтяным полем без вышки
	fort: number?, -- провинция у границы с врагом
	city: number?, -- свой город, который можно улучшить
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

	-- Мир: долгая война, а мы сильно слабее.
	for _, war in view.wars do
		if
			war.active
			and war.canPropose
			and war.age >= level.peaceAfterSec
			and view.totalPower < war.theirPower * cfg.PeaceWhenWeaker * personality.peace
		then
			-- Сначала просит белый мир; не вышло — готов отдать захваченное, лишь бы война кончилась.
			local keep = war.myGain > war.theirGain
				or war.proposedBefore
				or view.totalPower < war.theirPower * cfg.ConcedeWhenWeaker
			local terms: Types.PeaceTerms = if keep then "keep" else "white"
			return { kind = "peace", target = war.enemy, terms = terms }
		end
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
		return false
	end
	if offer.terms == "white" then
		-- Белый мир вернёт всё взятое: выгоден тому, кто проигрывает.
		return offer.myPower < offer.theirPower * cfg.AcceptWhiteWhenWeaker * peace or offer.theirGain > offer.myGain
	end
	-- «Забрать захваченное»: соглашаемся, если сами взяли не меньше или сильно слабее.
	return offer.myGain >= offer.theirGain or offer.myPower < offer.theirPower * cfg.AcceptKeepWhenWeaker * peace
end

return table.freeze(BotBrain)
