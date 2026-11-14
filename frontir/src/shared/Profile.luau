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
	-- §15ю: премиум-дорога (навсегда), её награды забраны до уровня; бонусы после MaxLevel — забрано бесплатных / премиум.
	pathPremium: boolean,
	pathPaid: number,
	pathBonus: number,
	pathBonusPaid: number,
	xpBoostUntil: number, -- §15я: ускоритель опыта действует до (unix; 0 — нет)
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
		pathPremium = false,
		pathPaid = 1,
		pathBonus = 0,
		pathBonusPaid = 0,
		xpBoostUntil = 0,
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
	d.pathPaid = math.max(1, num(raw.pathPaid))
	d.pathBonus = num(raw.pathBonus)
	d.pathBonusPaid = num(raw.pathBonusPaid)
	d.xpBoostUntil = num(raw.xpBoostUntil)
	-- §15ю: купивший пропуск сезона — премиум-дорога; дошедший до 30-й ступени премиума — «Легенда».
	d.pathPremium = raw.pathPremium == true or raw.seasonPremium == true
	if raw.seasonPremium == true and num(raw.seasonXp) >= 30 * 400 then
		d.cosmetics["title:Legend"] = true
	end
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
	local free, paid, bonus = Profile.pathClaimable(d)
	return after - before, free + paid + bonus
end

-- «Путь командира» (§15щ Щ1) -------------------------------------------------------------------------

export type PathReward = {
	medals: number,
	tokens: number,
	crates: number,
	stock: { [string]: number },
	cosmetic: string?, -- «вид:id» (Cosmetics)
	unit: string?, -- §15э Э1: на этом уровне дорога открывает технику (открывает сам уровень)
	pass: string?, -- §15ю Ю4: улучшение навсегда (как геймпасс Config.Shop.Passes; открывает сам уровень)
	title: string?, -- титул за уровень (Cosmetics.Titles.level) — только показать, он и так открыт
}

-- Что из забранного: уровень (после MaxLevel — бонус), дорога, награда.
export type PathGot = { level: number, premium: boolean, bonus: boolean, reward: PathReward }

local function emptyPath(): PathReward
	return { medals = 0, tokens = 0, crates = 0, stock = {}, cosmetic = nil, unit = nil, pass = nil, title = nil }
end

-- Награда бесплатной дороги уровня (2…MaxLevel): правило Config.Path, ступени званий и последний — Milestones.
function Profile.pathReward(level: number): PathReward
	local cfg = Config.Path
	local r = emptyPath()
	if level < 2 or level > Config.Profile.MaxLevel then
		return r
	end
	for _, key in Config.Unlocks.Order do
		if Config.Unlocks.Items[key].level == level then
			r.unit = key
		end
	end
	for _, it in Config.Cosmetics.Titles do
		if it.level == level then
			r.title = it.id
		end
	end
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
	local fs = cfg.FreeStock
	if level % fs.Every == 0 then
		r.stock[fs.Keys[(level // fs.Every - 1) % #fs.Keys + 1]] = 1
	end
	return r
end

-- §15ю Ю4: награда премиум-дороги уровня (2…MaxLevel): база + Specials.
function Profile.premiumReward(level: number): PathReward
	local cfg = Config.Path.Premium
	local r = emptyPath()
	if level < 2 or level > Config.Profile.MaxLevel then
		return r
	end
	r.medals = cfg.MedalsBase + cfg.MedalsPerLevel * level
	if level % cfg.StockEvery == 0 then
		r.stock[cfg.StockKeys[(level // cfg.StockEvery - 1) % #cfg.StockKeys + 1]] = 1
	end
	if level % cfg.CrateEvery == 0 then
		r.crates += 1
	end
	if level % cfg.TokensEvery == 0 then
		r.tokens += cfg.Tokens
	end
	local sp = cfg.Specials[level]
	if sp ~= nil then
		r.unit, r.pass, r.cosmetic = sp.unit, sp.pass, sp.cosmetic
		r.medals += sp.medals or 0
		r.crates += sp.crates or 0
		r.tokens += sp.tokens or 0
	end
	return r
end

-- §15ю Ю5: бонус после последнего уровня.
function Profile.bonusReward(premium: boolean): PathReward
	local b = if premium then Config.Path.Bonus.premium else Config.Path.Bonus.free
	local r = emptyPath()
	r.medals, r.crates = b.medals, b.crates
	return r
end

-- Опыт, нужный до последнего уровня (всё, что сверх, — к бонусам).
local xpToMaxCache: number? = nil
function Profile.xpToMax(): number
	local cached = xpToMaxCache
	if cached ~= nil then
		return cached
	end
	local sum = 0
	for lv = 1, Config.Profile.MaxLevel - 1 do
		sum += Profile.xpNeeded(lv)
	end
	xpToMaxCache = sum
	return sum
end

-- Сколько бонусов заработано и опыт к следующему: (заработано, в текущем, нужно).
function Profile.bonusEarned(d: Data): (number, number, number)
	local over = math.max(0, d.xp - Profile.xpToMax())
	local per = Config.Path.BonusXp
	if (Profile.levelOf(d.xp)) < Config.Profile.MaxLevel then
		return 0, 0, per
	end
	return over // per, over % per, per
end

-- Сколько наград ждёт: (бесплатная, премиум, бонусы обеих дорог).
function Profile.pathClaimable(d: Data): (number, number, number)
	local level = Profile.levelOf(d.xp)
	local free = math.max(0, level - d.pathClaimed)
	local paid = if d.pathPremium then math.max(0, level - d.pathPaid) else 0
	local earned = Profile.bonusEarned(d)
	local bonus = math.max(0, earned - d.pathBonus)
		+ (if d.pathPremium then math.max(0, earned - d.pathBonusPaid) else 0)
	return free, paid, bonus
end

-- Цена косметики в медалях (для повтора); эксклюзив без цены — DuplicateMedals.
local function cosmeticRefund(key: string): number
	local kind, id = string.match(key, "^(%a+):(%a+)$")
	local list: { { id: string, price: number? } } = if kind == "pattern"
		then Config.Cosmetics.Patterns
		elseif kind == "capture" then Config.Cosmetics.Captures
		else Config.Cosmetics.Titles :: any
	for _, it in list do
		if it.id == id then
			return it.price or Config.Path.Premium.DuplicateMedals
		end
	end
	return Config.Path.Premium.DuplicateMedals
end

-- §15я Я1: награда, которая уже есть, — медали. Улучшение куплено в магазине (owned); техника уже открыта покупкой
-- или раньше этого уровня (премиум-дорогой).
local function dedupe(d: Data, r: PathReward, level: number, owned: { [string]: boolean })
	local cfg = Config.Path.Premium
	local pass = r.pass
	if pass ~= nil and owned[pass] then
		r.medals += cfg.PassRefund
		r.pass = nil
	end
	local unit = r.unit
	if unit ~= nil then
		local item = Config.Unlocks.Items[unit]
		local earlier = d.pathPremium and item ~= nil and item.premiumLevel < level
		if d.unlocks[unit] or earlier then
			r.medals += cfg.UnitRefund
			r.unit = nil
		end
	end
end

local function grant(d: Data, r: PathReward, paid: boolean)
	local cosmetic = r.cosmetic
	if cosmetic ~= nil then
		if d.cosmetics[cosmetic] then
			r.medals += cosmeticRefund(cosmetic)
			r.cosmetic = nil
		else
			d.cosmetics[cosmetic] = true
		end
	end
	local give: Reward = { medals = r.medals, tokens = r.tokens, crates = r.crates, stock = r.stock }
	if paid then
		give = Profile.paidReward(give, d.noPaidRandom)
		r.medals, r.tokens, r.crates = give.medals, give.tokens, give.crates
	end
	Profile.give(d, give)
end

-- Забрать по порядку все награды обеих дорог (и бонусы после последнего уровня). Возвращает забранное (пусто —
-- нечего). Повтор косметики — медали. Премиум куплен позже — премиум пройденных уровней тоже забирается.
function Profile.pathClaim(d: Data, owned: { [string]: boolean }?): { PathGot }
	local bought = owned or {}
	local out: { PathGot } = {}
	local level = Profile.levelOf(d.xp)
	for lv = 2, level do
		if lv > d.pathClaimed then
			local r = Profile.pathReward(lv)
			dedupe(d, r, lv, bought)
			grant(d, r, false)
			table.insert(out, { level = lv, premium = false, bonus = false, reward = r })
		end
		if d.pathPremium and lv > d.pathPaid then
			local r = Profile.premiumReward(lv)
			dedupe(d, r, lv, bought)
			grant(d, r, true)
			table.insert(out, { level = lv, premium = true, bonus = false, reward = r })
		end
	end
	d.pathClaimed = math.max(d.pathClaimed, level)
	if d.pathPremium then
		d.pathPaid = math.max(d.pathPaid, level)
	end
	local earned = Profile.bonusEarned(d)
	local maxLevel = Config.Profile.MaxLevel
	for k = d.pathBonus + 1, earned do
		local r = Profile.bonusReward(false)
		grant(d, r, false)
		table.insert(out, { level = maxLevel + k, premium = false, bonus = true, reward = r })
	end
	d.pathBonus = math.max(d.pathBonus, earned)
	if d.pathPremium then
		for k = d.pathBonusPaid + 1, earned do
			local r = Profile.bonusReward(true)
			grant(d, r, true)
			table.insert(out, { level = maxLevel + k, premium = true, bonus = true, reward = r })
		end
		d.pathBonusPaid = math.max(d.pathBonusPaid, earned)
	end
	return out
end

-- §15ю Ю4: улучшения навсегда с премиум-дороги (как геймпассы; к купленным — Profile.passesWith).
function Profile.pathPasses(d: Data): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if not d.pathPremium then
		return out
	end
	local level = Profile.levelOf(d.xp)
	for lv, sp in Config.Path.Premium.Specials do
		if sp.pass ~= nil and level >= lv then
			out[sp.pass] = true
		end
	end
	return out
end

function Profile.passesWith(d: Data, owned: { [string]: boolean }): { [string]: boolean }
	local out = table.clone(owned)
	for key in Profile.pathPasses(d) do
		out[key] = true
	end
	return out
end

-- §15я: сколько секунд ещё действует ускоритель опыта.
function Profile.xpBoostLeft(d: Data, now: number?): number
	return if now == nil then 0 else math.max(0, d.xpBoostUntil - now)
end

-- §15я Я1: +n уровней «Пути» (опыт ровно до них); после последнего — в бонусы (BonusXp за уровень).
function Profile.addLevels(d: Data, n: number)
	local gain = 0
	local level = Profile.levelOf(d.xp)
	for k = 0, n - 1 do
		local lv = level + k
		gain += if lv < Config.Profile.MaxLevel then Profile.xpNeeded(lv) else Config.Path.BonusXp
	end
	-- Опыт внутри уровня сохраняется: добавляем ровно цену n уровней.
	d.xp += gain
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
	if Profile.xpBoostLeft(d, now) > 0 then
		xp = math.floor(xp * Config.Shop.XpBoostMul) -- §15я: ускоритель опыта (с VIP перемножается)
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
	local level = Profile.levelOf(d.xp)
	return level >= item.level or (d.pathPremium and level >= item.premiumLevel) -- §15ю Ю2
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
		if pack.premiumPath then
			d.pathPremium = true -- §15ю Ю1: премиум пройденных уровней ждёт на дороге («Забрать всё»)
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
		-- §15я Я2: уровни, ускоритель (продлевает), набор оформления.
		if pack.levels ~= nil then
			Profile.addLevels(d, pack.levels)
		end
		if pack.xpBoostHours ~= nil then
			local t = now or 0
			d.xpBoostUntil = math.max(d.xpBoostUntil, t) + pack.xpBoostHours * 3600
		end
		if pack.cosmetics ~= nil then
			for _, key in pack.cosmetics :: { string } do
				d.cosmetics[key] = true
			end
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
	if pack.premiumPath and d.pathPremium then
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
