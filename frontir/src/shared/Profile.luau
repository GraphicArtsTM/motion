--!strict
--[[
	Profile — данные игрока между матчами (GDD §11.2, этап 9а). Чистый модуль: форма данных, миграция сырой
	записи DataStore, уровни по опыту, награда за матч, жетоны за уровни, генералы по уровням, начисление покупок
	(идемпотентно по id покупки). Хранение и блокировка сессии — сервер (Services/ProfileStore).
]]

local Config = require("./Config")
local Arsenal = require("./Arsenal")
local Shop = require("./Shop")
local Types = require("./Types")

export type Data = {
	version: number,
	xp: number, -- весь опыт с начала
	medals: number,
	tokens: number, -- жетоны штаба (бесплатный путь к бустам, §11.1)
	matches: number,
	wins: number,
	stock: { [string]: number }, -- купленные бусты в запасе (Shop.BoostKeys)
	packs: { [string]: boolean }, -- купленные разовые наборы
	purchases: { string }, -- последние id покупок (Profile.PurchaseLog)
	-- Этап 9б (§11.3): ящики, пропуск сезона, ежедневная награда, первая победа дня, предложение недели.
	crates: number,
	pity: number, -- ящиков подряд без джекпота
	seasonId: number,
	seasonXp: number,
	seasonPremium: boolean,
	seasonFree: number, -- до какой ступени выданы бесплатные награды
	seasonPaid: number, -- … премиум-награды
	dailyDay: number, -- день (unix / 86400) последней ежедневной награды
	dailyStreak: number,
	firstWinDay: number,
	weeklyWeek: number, -- неделя, когда куплено предложение недели (−1 — нет)
	-- Этап 9в (§11.4): косметика.
	cosmetics: { [string]: boolean }, -- купленное ("pattern:Stripes")
	equipped: { [string]: string }, -- pattern / capture / title → id
	flag: { bg: string, layout: string, layoutColor: string, emblem: string, emblemColor: string }?,
	-- Этап 9г (§11.5): задания дня и рейтинг дуэлей.
	questDay: number,
	quests: { { pool: number, progress: number, done: boolean } },
	questsBonus: boolean, -- жетон за все три уже выдан
	elo: number,
	tutorialDone: boolean, -- обучение пройдено (§5.5)
	-- Этап 10б (§13): громкости игрока 0..1.
	sfx: number,
	music: number,
	-- Сводная правка ч.4: в стране игрока платные случайные награды запрещены (PolicyService). Не из DataStore —
	-- сервер ставит при каждом входе; пока стоит, ящики за Robux (наборы, неделя, премиум-пропуск) заменяются
	-- фиксированной наградой Config.Crates.Restricted, а наборы ящиков не продаются.
	noPaidRandom: boolean,
	-- §15л ч.6 Арсенал: открытое навсегда и взятое в бой.
	arsenal: { [string]: boolean },
	loadout: string?,
	commander: string?, -- §15ф Ф1: генерал по умолчанию (выбор в Арсенале, не в лобби)
	pathClaimed: number, -- §15щ Щ1: награды «Пути командира» забраны до этого уровня включительно (1 — ни одной)
	unlocks: { [string]: boolean }, -- §15э Э1: техника, купленная навсегда (Config.Unlocks; по уровню — само)
}

-- Награда (пропуск, ящик, ежедневная, набор).
export type Reward = { medals: number, tokens: number, crates: number, stock: { [string]: number } }

local Profile = {}

function Profile.new(): Data
	return {
		version = Config.Profile.Version,
		xp = 0,
		medals = 0,
		tokens = 0,
		matches = 0,
		wins = 0,
		stock = {},
		packs = {},
		purchases = {},
		crates = 0,
		pity = 0,
		seasonId = Config.Season.Id,
		seasonXp = 0,
		seasonPremium = false,
		seasonFree = 0,
		seasonPaid = 0,
		dailyDay = 0,
		dailyStreak = 0,
		firstWinDay = 0,
		weeklyWeek = -1,
		cosmetics = {},
		equipped = {},
		flag = nil,
		questDay = -1,
		quests = {},
		questsBonus = false,
		elo = Config.Elo.Start,
		tutorialDone = false,
		sfx = Config.Audio.DefaultSfx,
		music = Config.Audio.DefaultMusic,
		noPaidRandom = false,
		arsenal = {},
		loadout = nil,
		commander = nil,
		pathClaimed = 1,
		unlocks = {},
	}
end

-- §15ф Ф1: генерал по умолчанию — только открытый (уровень или пропуск «Все генералы»).
function Profile.setCommander(d: Data, commander: any, allPass: boolean): (boolean, string?)
	if type(commander) ~= "string" or table.find(Types.CommanderIds, commander) == nil then
		return false, "commander"
	end
	if not Profile.commanderUnlocked(d, commander :: any, allPass) then
		return false, "locked"
	end
	d.commander = commander
	return true, nil
end

-- Громкости (§13): 0..1, с шагом Audio.VolumeStep; мусор — по умолчанию.
function Profile.setVolumes(d: Data, sfx: any, music: any): (boolean, string?)
	local function ok(v: any): boolean
		return type(v) == "number" and v == v and v >= 0 and v <= 1
	end
	if not ok(sfx) or not ok(music) then
		return false, "target"
	end
	local step = Config.Audio.VolumeStep
	d.sfx = math.round(sfx / step) * step
	d.music = math.round(music / step) * step
	return true, nil
end

local function num(v: any): number
	return if type(v) == "number" and v == v and v >= 0 and v < 1e12 then math.floor(v) else 0
end

-- Сырая запись DataStore → данные текущей версии (недостающее — по умолчанию, мусор — отбрасываем).
function Profile.migrate(raw: any): Data
	local d = Profile.new()
	if type(raw) ~= "table" then
		return d
	end
	d.xp = num(raw.xp)
	d.pathClaimed = math.max(1, num(raw.pathClaimed))
	if type(raw.unlocks) == "table" then
		for key in Config.Unlocks.Items do
			if raw.unlocks[key] == true then
				d.unlocks[key] = true
			end
		end
	end
	d.medals = num(raw.medals)
	d.tokens = num(raw.tokens)
	d.matches = num(raw.matches)
	d.wins = num(raw.wins)
	if type(raw.stock) == "table" then
		for _, key in Shop.BoostKeys do
			local v = num(raw.stock[key])
			if v > 0 then
				d.stock[key] = v
			end
		end
	end
	if type(raw.packs) == "table" then
		for _, key in Shop.PackKeys do
			if raw.packs[key] == true then
				d.packs[key] = true
			end
		end
	end
	if type(raw.purchases) == "table" then
		for _, id in raw.purchases do
			if type(id) == "string" then
				table.insert(d.purchases, id)
			end
		end
	end
	d.crates = num(raw.crates)
	d.pity = num(raw.pity)
	d.seasonId = if type(raw.seasonId) == "number" then raw.seasonId else Config.Season.Id
	d.seasonXp = num(raw.seasonXp)
	d.seasonPremium = raw.seasonPremium == true
	d.seasonFree = num(raw.seasonFree)
	d.seasonPaid = num(raw.seasonPaid)
	d.dailyDay = num(raw.dailyDay)
	d.dailyStreak = num(raw.dailyStreak)
	d.firstWinDay = num(raw.firstWinDay)
	d.weeklyWeek = if type(raw.weeklyWeek) == "number" then raw.weeklyWeek else -1
	if type(raw.cosmetics) == "table" then
		for key, v in raw.cosmetics do
			if type(key) == "string" and v == true then
				d.cosmetics[key] = true
			end
		end
	end
	if type(raw.equipped) == "table" then
		for _, kind in { "pattern", "capture", "title" } do
			if type(raw.equipped[kind]) == "string" then
				d.equipped[kind] = raw.equipped[kind]
			end
		end
	end
	d.questDay = if type(raw.questDay) == "number" then raw.questDay else -1
	d.questsBonus = raw.questsBonus == true
	if type(raw.quests) == "table" then
		for _, q in raw.quests do
			if type(q) == "table" and type(q.pool) == "number" and Config.Quests.Pool[q.pool] ~= nil then
				table.insert(d.quests, { pool = q.pool, progress = num(q.progress), done = q.done == true })
			end
		end
	end
	d.elo = if type(raw.elo) == "number" and raw.elo == raw.elo then math.floor(raw.elo) else Config.Elo.Start
	d.tutorialDone = raw.tutorialDone == true
	if not Profile.setVolumes(d, raw.sfx, raw.music) then
		d.sfx, d.music = Config.Audio.DefaultSfx, Config.Audio.DefaultMusic
	end
	local f = raw.flag
	if
		type(f) == "table"
		and type(f.bg) == "string"
		and type(f.layout) == "string"
		and type(f.layoutColor) == "string"
		and type(f.emblem) == "string"
		and type(f.emblemColor) == "string"
	then
		d.flag = {
			bg = f.bg,
			layout = f.layout,
			layoutColor = f.layoutColor,
			emblem = f.emblem,
			emblemColor = f.emblemColor,
		}
	end
	d.arsenal, d.loadout = Arsenal.migrate(raw.arsenal, raw.loadout)
	if type(raw.commander) == "string" and table.find(Types.CommanderIds, raw.commander) ~= nil then
		d.commander = raw.commander
	end
	Profile.syncSeason(d)
	return d
end

local function emptyReward(): Reward
	return { medals = 0, tokens = 0, crates = 0, stock = {} }
end

-- Награда за Robux (прямо или через пропуск и наборы): там, где платные случайные награды запрещены, ящики
-- заменяются фиксированной наградой. Бесплатные ящики (ежедневная, бесплатная ступень пропуска) — как есть.
function Profile.paidReward(r: Reward, noPaidRandom: boolean): Reward
	if not noPaidRandom or r.crates <= 0 then
		return r
	end
	local c = Config.Crates.Restricted
	return {
		medals = r.medals + r.crates * c.medals,
		tokens = r.tokens + r.crates * c.tokens,
		crates = 0,
		stock = r.stock,
	}
end

-- Выдать награду.
function Profile.give(d: Data, r: Reward)
	d.medals += r.medals
	d.tokens += r.tokens
	d.crates += r.crates
	for key, n in r.stock do
		if Shop.isBoost(key) and n > 0 then
			d.stock[key] = (d.stock[key] or 0) + n
		end
	end
end

-- Боевой пропуск (§11.3) ---------------------------------------------------------------------------

-- Награда ступени tier: бесплатная или премиум.
function Profile.seasonReward(tier: number, premium: boolean): Reward
	local r = emptyReward()
	if not premium then
		if tier % 5 == 0 then
			r.crates = 1
		elseif tier % 2 == 0 then
			r.tokens = 1
		else
			r.medals = 150
		end
	elseif tier == Config.Season.Tiers then
		r.crates, r.tokens = 3, 3
	elseif tier % 3 == 0 then
		r.crates = 1
	elseif tier % 3 == 1 then
		local units = Shop.UnitKeys
		r.stock[units[(tier // 3) % #units + 1]] = 1
	else
		r.medals = 400
	end
	return r
end

-- Новый сезон — пропуск с нуля.
function Profile.syncSeason(d: Data)
	if d.seasonId ~= Config.Season.Id then
		d.seasonId = Config.Season.Id
		d.seasonXp, d.seasonPremium, d.seasonFree, d.seasonPaid = 0, false, 0, 0
	end
end

function Profile.seasonTier(d: Data): number
	return math.min(Config.Season.Tiers, d.seasonXp // Config.Season.XpPerTier)
end

-- Выдать награды пройденных ступеней (бесплатные и, если куплен, премиум). Возвращает выданное.
function Profile.grantSeason(d: Data): { Reward }
	local out: { Reward } = {}
	local tier = Profile.seasonTier(d)
	for t = d.seasonFree + 1, tier do
		local r = Profile.seasonReward(t, false)
		Profile.give(d, r)
		table.insert(out, r)
	end
	d.seasonFree = math.max(d.seasonFree, tier)
	if d.seasonPremium then
		for t = d.seasonPaid + 1, tier do
			local r = Profile.paidReward(Profile.seasonReward(t, true), d.noPaidRandom)
			Profile.give(d, r)
			table.insert(out, r)
		end
		d.seasonPaid = math.max(d.seasonPaid, tier)
	end
	return out
end

-- Опыт в пропуск (после конца сезона — нет).
function Profile.addSeasonXp(d: Data, xp: number, now: number): { Reward }
	Profile.syncSeason(d)
	local ends = Config.Season.EndsUnix
	if ends > 0 and now >= ends then
		return {}
	end
	d.seasonXp += math.max(0, math.floor(xp))
	return Profile.grantSeason(d)
end

-- Ящики снабжения (§11.3) ---------------------------------------------------------------------------

-- Шансы наград ящика в процентах (для окна — до покупки).
function Profile.crateOdds(): { { key: string, percent: number } }
	local total = 0
	for _, row in Config.Crates.Table do
		total += row.weight
	end
	local out: { { key: string, percent: number } } = {}
	for _, row in Config.Crates.Table do
		table.insert(out, { key = row.key, percent = row.weight / total * 100 })
	end
	return out
end

-- Открыть ящик: roll(n) — случайное целое 1..n (сервер). Гарантия: Pity-й ящик подряд без джекпота — джекпот.
-- Возвращает ключ награды, платную часть (для «unit») и саму награду; nil — ящиков нет.
function Profile.openCrate(d: Data, roll: (n: number) -> number): (string?, string?, Reward?)
	if d.crates <= 0 then
		return nil, nil, nil
	end
	d.crates -= 1
	local cfg = Config.Crates
	local row = cfg.Table[#cfg.Table]
	d.pity += 1
	if d.pity < cfg.Pity then
		local total = 0
		for _, r in cfg.Table do
			total += r.weight
		end
		local x = roll(total)
		for _, r in cfg.Table do
			if x <= r.weight then
				row = r
				break
			end
			x -= r.weight
		end
	end
	if row.key == "jackpot" then
		d.pity = 0
	end
	local reward = emptyReward()
	reward.medals, reward.tokens = row.medals, row.tokens
	local unit: string? = nil
	if row.key == "unit" then
		local units = Shop.UnitKeys
		unit = units[roll(#units)]
		reward.stock[unit :: string] = 1
	end
	Profile.give(d, reward)
	return row.key, unit, reward
end

-- Обучение пройдено (§5.5): награда один раз. true — выдана сейчас.
function Profile.finishTutorial(d: Data): boolean
	if d.tutorialDone then
		return false
	end
	d.tutorialDone = true
	d.tokens += Config.Tutorial.RewardTokens
	d.medals += Config.Tutorial.RewardMedals
	return true
end

-- Ежедневная награда (§11.3) ----------------------------------------------------------------------

-- День по времени сервера (unix).
function Profile.dayOf(unixTime: number): number
	return unixTime // 86400
end

-- Награда за вход: раз в день; подряд — серия до 7, пропуск дня — заново. nil — сегодня уже была.
function Profile.claimDaily(d: Data, day: number): (number?, Reward?)
	if d.dailyDay == day then
		return nil, nil
	end
	local rewards = Config.Daily.Rewards
	d.dailyStreak = if d.dailyDay == day - 1 then d.dailyStreak % #rewards + 1 else 1
	d.dailyDay = day
	local row = rewards[d.dailyStreak]
	local r: Reward = { medals = row.medals, tokens = row.tokens, crates = row.crates, stock = {} }
	Profile.give(d, r)
	return d.dailyStreak, r
end

-- Опыта нужно, чтобы с уровня level перейти на следующий (§15щ Щ1: линейно).
function Profile.xpNeeded(level: number): number
	local cfg = Config.Profile
	return math.floor(cfg.XpBase + cfg.XpStep * (math.max(1, level) - 1))
end

-- Уровень по всему опыту: (уровень, опыта внутри уровня, нужно до следующего).
function Profile.levelOf(xp: number): (number, number, number)
	local level, left = 1, xp
	while level < Config.Profile.MaxLevel do
		local need = Profile.xpNeeded(level)
		if left < need then
			return level, left, need
		end
		left -= need
		level += 1
	end
	return level, 0, 0
end

-- Награда за матч (§11.2): опыт и медали. place — место (1 — лучшее), cities — города державы к концу,
-- won — победа (и совместная), mul — множители (VIP, Premium).
function Profile.matchReward(place: number, cities: number, won: boolean, mul: number): (number, number)
	local cfg = Config.Profile
	local xp = cfg.XpPlay + (cfg.XpPlace[place] or 0) + cfg.XpPerCity * math.max(0, cities)
	if won then
		xp += cfg.XpWin
	end
	xp = math.floor(xp * mul)
	return xp, math.floor(xp * cfg.MedalShare)
end

-- Начислить опыт: (уровней получено, наград «Пути командира» ждёт). §15щ Щ1: жетоны за уровни не выдаются сами —
-- они на дорожке наград (Profile.pathClaim).
function Profile.addXp(d: Data, xp: number): (number, number)
	local before = Profile.levelOf(d.xp)
	d.xp += math.max(0, math.floor(xp))
	local after = Profile.levelOf(d.xp)
	return after - before, Profile.pathClaimable(d)
end

-- «Путь командира» (§15щ Щ1) -------------------------------------------------------------------------

export type PathReward = {
	medals: number,
	tokens: number,
	crates: number,
	stock: { [string]: number },
	cosmetic: string?,
	unit: string?, -- §15э Э1: на этом уровне открывается техника (ключ Config.Unlocks.Order); открывает сам уровень
}

-- Техника, которая открывается на уровне level (или nil).
local function unitAt(level: number): string?
	for _, key in Config.Unlocks.Order do
		if Config.Unlocks.Items[key].level == level then
			return key
		end
	end
	return nil
end

-- Награда уровня (2…MaxLevel): правило Config.Path, ступени званий и последний уровень — Milestones.
function Profile.pathReward(level: number): PathReward
	local cfg = Config.Path
	local r: PathReward = { medals = 0, tokens = 0, crates = 0, stock = {}, cosmetic = nil, unit = nil }
	if level < 2 or level > Config.Profile.MaxLevel then
		return r
	end
	r.unit = unitAt(level)
	local ms = cfg.Milestones[level]
	if ms ~= nil then
		r.medals, r.tokens, r.crates, r.cosmetic = ms.medals, ms.tokens, ms.crates, ms.cosmetic
		return r
	end
	if level % cfg.TokenEvery == 0 then
		r.tokens = 1
	else
		r.medals = cfg.MedalsBase + cfg.MedalsPerLevel * level
	end
	if level % cfg.CrateEvery == 0 then
		r.crates = 1
	end
	return r
end

-- Сколько наград ждёт (пройденные уровни, ещё не забранные).
function Profile.pathClaimable(d: Data): number
	local level = Profile.levelOf(d.xp)
	return math.max(0, level - d.pathClaimed)
end

-- Забрать по порядку все награды до текущего уровня. Возвращает забранное: { level, reward } (пусто — нечего).
-- Узор или вспышка, которые уже есть, — вместо них медали по их цене.
function Profile.pathClaim(d: Data): { { level: number, reward: PathReward } }
	local out: { { level: number, reward: PathReward } } = {}
	local level = Profile.levelOf(d.xp)
	for lv = d.pathClaimed + 1, level do
		local r = Profile.pathReward(lv)
		local cosmetic = r.cosmetic
		if cosmetic ~= nil then
			if d.cosmetics[cosmetic] then
				local kind, id = string.match(cosmetic, "^(%a+):(%a+)$")
				local price = 0
				for _, list in { Config.Cosmetics.Patterns, Config.Cosmetics.Captures } do
					for _, it in list :: { { id: string, price: number } } do
						if (kind == "pattern" or kind == "capture") and it.id == id then
							price = it.price
						end
					end
				end
				r.medals += price
				r.cosmetic = nil
			else
				d.cosmetics[cosmetic] = true
			end
		end
		Profile.give(d, { medals = r.medals, tokens = r.tokens, crates = r.crates, stock = r.stock })
		table.insert(out, { level = lv, reward = r })
	end
	d.pathClaimed = math.max(d.pathClaimed, level)
	return out
end

-- Итог матча в профиль.
function Profile.applyMatch(
	d: Data,
	place: number,
	cities: number,
	won: boolean,
	mul: number,
	now: number?
): (number, number)
	local xp, medals = Profile.matchReward(place, cities, won, mul)
	-- Первая победа дня — ×FirstWinMul опыта (§11.3).
	if won and now ~= nil and d.firstWinDay ~= Profile.dayOf(now) then
		d.firstWinDay = Profile.dayOf(now)
		xp = math.floor(xp * Config.Daily.FirstWinMul)
	end
	if now ~= nil then
		Profile.addSeasonXp(d, xp, now)
	end
	d.matches += 1
	if won then
		d.wins += 1
	end
	d.medals += medals
	Profile.addXp(d, xp)
	return xp, medals
end

-- Открыт ли генерал (§11.2): по уровню или пассом «Все генералы».
function Profile.commanderUnlocked(d: Data, commander: Types.CommanderId, allPass: boolean): boolean
	if allPass then
		return true
	end
	local need = (Config.Profile.CommanderLevels :: any)[commander] or 1
	return (Profile.levelOf(d.xp)) >= need
end

function Profile.unlockedCommanders(d: Data, allPass: boolean): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, raw in Types.CommanderIds do
		local c: Types.CommanderId = raw :: any
		if Profile.commanderUnlocked(d, c, allPass) then
			out[c] = true
		end
	end
	return out
end

-- §15э Э1: открыта ли техника (Tanks / Artillery / AntiAir / Missile): куплена или уровень «Пути» не ниже нужного.
-- Ключа нет в Config.Unlocks — не закрыта.
function Profile.unitUnlocked(d: Data, key: string): boolean
	local item = Config.Unlocks.Items[key]
	if item == nil or d.unlocks[key] then
		return true
	end
	return (Profile.levelOf(d.xp)) >= item.level
end

function Profile.unlockedUnits(d: Data): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, key in Config.Unlocks.Order do
		if Profile.unitUnlocked(d, key) then
			out[key] = true
		end
	end
	return out
end

-- Покупка уже начислена?
function Profile.hasPurchase(d: Data, purchaseId: string): boolean
	return table.find(d.purchases, purchaseId) ~= nil
end

local function logPurchase(d: Data, purchaseId: string)
	table.insert(d.purchases, purchaseId)
	while #d.purchases > Config.Profile.PurchaseLog do
		table.remove(d.purchases, 1)
	end
end

-- Начислить продукт (ProcessReceipt): буст — в запас, набор — жетоны и медали. Повтор того же purchaseId —
-- ничего (true: уже начислено). false — продукт не наш или разовый набор уже куплен.
function Profile.grantProduct(d: Data, kind: string, key: string, purchaseId: string, now: number?): boolean
	if Profile.hasPurchase(d, purchaseId) then
		return true
	end
	if kind == "boost" and Shop.isBoost(key) then
		d.stock[key] = (d.stock[key] or 0) + 1
	elseif kind == "unlock" then
		-- §15э Э1: техника навсегда; «All» — вся.
		if key == "All" then
			for _, k in Config.Unlocks.Order do
				d.unlocks[k] = true
			end
		elseif Config.Unlocks.Items[key] ~= nil then
			d.unlocks[key] = true
		else
			return false
		end
	elseif kind == "pack" then
		local pack = (Config.Shop.Packs :: any)[key]
		if pack == nil then
			return false
		end
		-- Разовый набор куплен повторно (окно его прячет) — всё равно начисляем: Robux уже списаны.
		if pack.once then
			d.packs[key] = true
		end
		-- Набор ящиков там, где они запрещены, окно не продаёт; куплен всё же — Robux списаны, даём замену.
		Profile.give(
			d,
			Profile.paidReward(
				{ medals = pack.medals or 0, tokens = pack.tokens or 0, crates = pack.crates or 0, stock = {} },
				d.noPaidRandom
			)
		)
		if pack.season then
			Profile.syncSeason(d)
			d.seasonPremium = true
			Profile.grantSeason(d) -- премиум-награды уже пройденных ступеней — сразу
		end
		if pack.weekly then
			local offer = Shop.weeklyOffer(now or 0)
			Profile.give(
				d,
				Profile.paidReward(
					{ medals = 0, tokens = offer.tokens, crates = offer.crates, stock = offer.stock },
					d.noPaidRandom
				)
			)
			d.weeklyWeek = Shop.week(now or 0)
		end
	else
		return false
	end
	logPurchase(d, purchaseId)
	return true
end

-- Можно ли сейчас показать разовый набор (§11.1: «Набор новобранца» — до maxLevel, один раз).
function Profile.packAvailable(d: Data, key: string, now: number?): boolean
	local pack = (Config.Shop.Packs :: any)[key]
	if pack == nil then
		return false
	end
	if pack.once and d.packs[key] then
		return false
	end
	if pack.season and d.seasonPremium then
		return false
	end
	if pack.maxLevel ~= nil and (Profile.levelOf(d.xp)) > pack.maxLevel then
		return false
	end
	if pack.weekly and d.weeklyWeek == Shop.week(now or 0) then
		return false
	end
	-- Наборы ящиков — платная случайная награда (PolicyService).
	if d.noPaidRandom and (pack.crates or 0) > 0 then
		return false
	end
	return true
end

return table.freeze(Profile)
