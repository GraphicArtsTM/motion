--!strict
--[[
	Profile — данные игрока между матчами (GDD §11.2, этап 9а). Чистый модуль: форма данных, миграция сырой
	записи DataStore, уровни по опыту, награда за матч, жетоны за уровни, генералы по уровням, начисление покупок
	(идемпотентно по id покупки). Хранение и блокировка сессии — сервер (Services/ProfileStore).
]]

local Config = require("./Config")
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
}

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
	}
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
	return d
end

-- Опыта нужно, чтобы с уровня level перейти на следующий.
function Profile.xpNeeded(level: number): number
	local cfg = Config.Profile
	return math.floor(cfg.XpBase * cfg.XpGrowth ^ (level - 1))
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

-- Начислить опыт: (уровней получено, жетонов получено).
function Profile.addXp(d: Data, xp: number): (number, number)
	local before = Profile.levelOf(d.xp)
	d.xp += math.max(0, math.floor(xp))
	local after = Profile.levelOf(d.xp)
	local every = Config.Profile.TokenEveryLevels
	local tokens = after // every - before // every
	d.tokens += tokens
	return after - before, tokens
end

-- Итог матча в профиль.
function Profile.applyMatch(d: Data, place: number, cities: number, won: boolean, mul: number): (number, number)
	local xp, medals = Profile.matchReward(place, cities, won, mul)
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
function Profile.grantProduct(d: Data, kind: string, key: string, purchaseId: string): boolean
	if Profile.hasPurchase(d, purchaseId) then
		return true
	end
	if kind == "boost" and Shop.isBoost(key) then
		d.stock[key] = (d.stock[key] or 0) + 1
	elseif kind == "pack" then
		local pack = (Config.Shop.Packs :: any)[key]
		if pack == nil then
			return false
		end
		if pack.once then
			if d.packs[key] then
				return false
			end
			d.packs[key] = true
		end
		d.tokens += pack.tokens or 0
		d.medals += pack.medals or 0
	else
		return false
	end
	logPurchase(d, purchaseId)
	return true
end

-- Можно ли сейчас показать разовый набор (§11.1: «Набор новобранца» — до maxLevel, один раз).
function Profile.packAvailable(d: Data, key: string): boolean
	local pack = (Config.Shop.Packs :: any)[key]
	if pack == nil then
		return false
	end
	if pack.once and d.packs[key] then
		return false
	end
	if pack.maxLevel ~= nil and (Profile.levelOf(d.xp)) > pack.maxLevel then
		return false
	end
	return true
end

return table.freeze(Profile)
