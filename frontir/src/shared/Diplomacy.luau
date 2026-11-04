--!strict
--[[
	Diplomacy — договоры между державами (GDD §8.1, этап 6а). Чистый модуль: пакты, союзы, разрыв,
	метка «Предатель», вассалы, предложения и требования, история. Правила войны (что можно объявить, что
	делать с землёй) решает MatchSim, бой — Wars/Fronts.

	- Пакт о ненападении — на срок; союз — пока не разорвут (до Match.MaxAlliesFfa союзников у каждого).
	- «Разорвать»: договор кончается через BreakWarningSec. Пакт, разорванный раньше срока, — предательство.
	- Предательство: войну объявили партнёру, не дождавшись конца договора. Договор рвётся сразу, метка
	  «Предатель» на TraitorSec.
	- Вассал: отдаёт долю дохода сюзерену, не воюет с ним и не заключает союзов; через VassalRebelSec может
	  объявить независимость.
	Время — игровое (simTime).
]]

local Config = require("./Config")
local Types = require("./Types")

export type Treaty = {
	kind: Types.TreatyKind,
	a: number,
	b: number,
	since: number,
	untilTime: number?, -- конец пакта
	breakAt: number?, -- объявлен разрыв: договор кончится в этот момент
	breaker: number?, -- кто разрывает
}

export type Offer = {
	kind: Types.OfferKind,
	from: number,
	to: number,
	province: number?, -- требование: какую провинцию отдать
	madeAt: number,
	expiresAt: number,
}

export type Vassalage = { overlord: number, since: number }

-- Запись истории договоров (для окна дипломатии).
export type Entry = {
	kind: "pact"
		| "alliance"
		| "broken"
		| "expired"
		| "betrayal"
		| "vassal"
		| "independence"
		| "ceded"
		| "refused"
		| "trade"
		| "embargo",
	a: number,
	b: number,
	at: number,
	minutes: number?,
}

export type DiploSet = {
	treaties: { Treaty },
	offers: { Offer },
	traitors: { [number]: number }, -- держава → simTime конца метки
	vassals: { [number]: Vassalage }, -- вассал → сюзерен
	lastOffer: { [number]: number }, -- пара (от кого → кому) → simTime последнего предложения
	trade: { [number]: number }, -- торговые соглашения (§8.2): пара → simTime заключения
	embargo: { [number]: boolean }, -- эмбарго: (кто * 65536 + кому) → true
	history: { Entry },
	version: number, -- растёт при каждом изменении (сервер рассылает diplo)
}

-- Что случилось при обновлении: для ленты событий и решений MatchSim.
export type Change =
	{ kind: "expired", treaty: Treaty }
	| { kind: "broken", treaty: Treaty, betrayal: boolean }
	| { kind: "offerExpired", offer: Offer }
	| { kind: "traitorCleared", nation: number }

local Diplomacy = {}

local function pairKey(a: number, b: number): number
	return math.min(a, b) * 65536 + math.max(a, b)
end

function Diplomacy.new(): DiploSet
	return {
		treaties = {},
		offers = {},
		traitors = {},
		vassals = {},
		lastOffer = {},
		trade = {},
		embargo = {},
		history = {},
		version = 0,
	}
end

local function touch(ds: DiploSet)
	ds.version += 1
end

local function log(ds: DiploSet, entry: Entry)
	table.insert(ds.history, entry)
	while #ds.history > Config.Diplomacy.HistorySize do
		table.remove(ds.history, 1)
	end
end

-- Договор между a и b (или nil).
function Diplomacy.treaty(ds: DiploSet, a: number, b: number): Treaty?
	for _, t in ds.treaties do
		if pairKey(t.a, t.b) == pairKey(a, b) then
			return t
		end
	end
	return nil
end

function Diplomacy.allied(ds: DiploSet, a: number, b: number): boolean
	local t = Diplomacy.treaty(ds, a, b)
	return t ~= nil and t.kind == "alliance"
end

function Diplomacy.alliesOf(ds: DiploSet, a: number): { number }
	local out: { number } = {}
	for _, t in ds.treaties do
		if t.kind == "alliance" then
			if t.a == a then
				table.insert(out, t.b)
			elseif t.b == a then
				table.insert(out, t.a)
			end
		end
	end
	table.sort(out)
	return out
end

function Diplomacy.overlordOf(ds: DiploSet, vassal: number): number?
	local v = ds.vassals[vassal]
	return if v ~= nil then v.overlord else nil
end

function Diplomacy.vassalsOf(ds: DiploSet, overlord: number): { number }
	local out: { number } = {}
	for id, v in ds.vassals do
		if v.overlord == overlord then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

-- Свои для снабжения и победы: союзники, вассалы и сюзерен.
function Diplomacy.friends(ds: DiploSet, a: number): { [number]: boolean }
	local out: { [number]: boolean } = { [a] = true }
	for _, id in Diplomacy.alliesOf(ds, a) do
		out[id] = true
	end
	for _, id in Diplomacy.vassalsOf(ds, a) do
		out[id] = true
	end
	local lord = Diplomacy.overlordOf(ds, a)
	if lord ~= nil then
		out[lord] = true
	end
	return out
end

function Diplomacy.isTraitor(ds: DiploSet, a: number, now: number): boolean
	local untilTime = ds.traitors[a]
	return untilTime ~= nil and now < untilTime
end

function Diplomacy.markTraitor(ds: DiploSet, a: number, now: number)
	ds.traitors[a] = now + Config.Diplomacy.TraitorSec
	touch(ds)
end

-- Торговые соглашения и эмбарго (§8.2).
function Diplomacy.hasTrade(ds: DiploSet, a: number, b: number): boolean
	return ds.trade[pairKey(a, b)] ~= nil
end

function Diplomacy.tradeCount(ds: DiploSet, a: number): number
	local count = 0
	for key in ds.trade do
		if key // 65536 == a or key % 65536 == a then
			count += 1
		end
	end
	return count
end

-- Партнёры державы по торговым соглашениям.
function Diplomacy.tradePartners(ds: DiploSet, a: number): { number }
	local out: { number } = {}
	for key in ds.trade do
		local x, y = key // 65536, key % 65536
		if x == a then
			table.insert(out, y)
		elseif y == a then
			table.insert(out, x)
		end
	end
	table.sort(out)
	return out
end

function Diplomacy.signTrade(ds: DiploSet, a: number, b: number, now: number)
	ds.trade[pairKey(a, b)] = now
	log(ds, { kind = "trade", a = a, b = b, at = now })
	touch(ds)
end

-- Соглашение рвётся (война, эмбарго). Возвращает true, если оно было.
function Diplomacy.endTrade(ds: DiploSet, a: number, b: number): boolean
	local key = pairKey(a, b)
	if ds.trade[key] == nil then
		return false
	end
	ds.trade[key] = nil
	touch(ds)
	return true
end

-- Есть ли эмбарго между a и b (в любую сторону).
function Diplomacy.embargoed(ds: DiploSet, a: number, b: number): boolean
	return ds.embargo[a * 65536 + b] == true or ds.embargo[b * 65536 + a] == true
end

-- a объявляет (on) или снимает эмбарго против b. Объявление рвёт торговое соглашение.
function Diplomacy.setEmbargo(ds: DiploSet, a: number, b: number, on: boolean, now: number)
	if on then
		ds.embargo[a * 65536 + b] = true
	else
		ds.embargo[a * 65536 + b] = nil
	end
	if on then
		Diplomacy.endTrade(ds, a, b)
		log(ds, { kind = "embargo", a = a, b = b, at = now })
	end
	touch(ds)
end

-- Можно ли from предложить to договор kind. Война между ними проверяется в MatchSim.
function Diplomacy.canOffer(
	ds: DiploSet,
	from: number,
	to: number,
	kind: Types.OfferKind,
	now: number
): (boolean, string?)
	if from == to then
		return false, "self"
	end
	for _, o in ds.offers do
		if (o.from == from and o.to == to) or (o.from == to and o.to == from) then
			return false, "offerPending"
		end
	end
	local t = Diplomacy.treaty(ds, from, to)
	local vassalPair = Diplomacy.overlordOf(ds, from) == to or Diplomacy.overlordOf(ds, to) == from
	-- Повторно — не раньше OfferRetrySec (иначе можно засыпать соседа окнами).
	local function cooldown(): (boolean, string?)
		local last = ds.lastOffer[from * 65536 + to]
		if last ~= nil and now - last < Config.Diplomacy.OfferRetrySec then
			return false, "offerCooldown"
		end
		return true, nil
	end
	if kind == "demand" then
		if t ~= nil or vassalPair then
			return false, "treaty"
		end
		return cooldown()
	end
	if kind == "trade" then
		if Diplomacy.hasTrade(ds, from, to) then
			return false, "already"
		end
		if Diplomacy.embargoed(ds, from, to) then
			return false, "embargo"
		end
		local max = Config.Trade.MaxAgreements
		if Diplomacy.tradeCount(ds, from) >= max or Diplomacy.tradeCount(ds, to) >= max then
			return false, "maxTrade"
		end
		return cooldown()
	end
	if vassalPair then
		return false, "vassal"
	end
	if kind == "alliance" then
		if t ~= nil and t.kind == "alliance" then
			return false, "already"
		end
		if Diplomacy.overlordOf(ds, from) ~= nil or Diplomacy.overlordOf(ds, to) ~= nil then
			return false, "vassal" -- вассалы союзов не заключают
		end
		local max = Config.Match.MaxAlliesFfa
		if #Diplomacy.alliesOf(ds, from) >= max or #Diplomacy.alliesOf(ds, to) >= max then
			return false, "maxAllies"
		end
		return cooldown()
	end
	-- Пакт: если уже союз или пакт — незачем.
	if t ~= nil then
		return false, "already"
	end
	return cooldown()
end

function Diplomacy.offer(
	ds: DiploSet,
	from: number,
	to: number,
	kind: Types.OfferKind,
	now: number,
	province: number?
): Offer
	local o: Offer = {
		kind = kind,
		from = from,
		to = to,
		province = province,
		madeAt = now,
		expiresAt = now + Config.Diplomacy.OfferSec,
	}
	table.insert(ds.offers, o)
	ds.lastOffer[from * 65536 + to] = now
	touch(ds)
	return o
end

-- Предложение from → to (или nil).
function Diplomacy.offerBetween(ds: DiploSet, from: number, to: number): Offer?
	for _, o in ds.offers do
		if o.from == from and o.to == to then
			return o
		end
	end
	return nil
end

function Diplomacy.removeOffer(ds: DiploSet, offer: Offer)
	local k = table.find(ds.offers, offer)
	if k ~= nil then
		table.remove(ds.offers, k)
		touch(ds)
	end
end

local function removeTreaty(ds: DiploSet, t: Treaty)
	local k = table.find(ds.treaties, t)
	if k ~= nil then
		table.remove(ds.treaties, k)
		touch(ds)
	end
end

-- Заключить пакт (minutes) или союз. Пакт поверх пакта продлевается; союз заменяет пакт.
function Diplomacy.sign(
	ds: DiploSet,
	kind: Types.TreatyKind,
	a: number,
	b: number,
	now: number,
	minutes: number?
): Treaty
	local old = Diplomacy.treaty(ds, a, b)
	if old ~= nil then
		removeTreaty(ds, old)
	end
	local t: Treaty = {
		kind = kind,
		a = a,
		b = b,
		since = now,
		untilTime = if kind == "pact" then now + (minutes or Config.Diplomacy.PactMinutes[1]) * 60 else nil,
	}
	table.insert(ds.treaties, t)
	log(ds, { kind = kind, a = a, b = b, at = now, minutes = minutes })
	touch(ds)
	return t
end

-- «Разорвать»: договор кончится через BreakWarningSec.
function Diplomacy.startBreak(ds: DiploSet, breaker: number, other: number, now: number): (boolean, string?)
	local t = Diplomacy.treaty(ds, breaker, other)
	if t == nil then
		return false, "noTreaty"
	end
	if t.breakAt ~= nil then
		return false, "breaking"
	end
	t.breakAt = now + Config.Diplomacy.BreakWarningSec
	t.breaker = breaker
	touch(ds)
	return true, nil
end

-- Сейчас между a и b можно воевать без предательства?
function Diplomacy.warIsBetrayal(ds: DiploSet, a: number, b: number, now: number): boolean
	local t = Diplomacy.treaty(ds, a, b)
	return t ~= nil and not (t.breakAt ~= nil and now >= t.breakAt)
end

-- Предательство: a объявил войну партнёру b. Договор рвётся, a — «Предатель».
function Diplomacy.betray(ds: DiploSet, a: number, b: number, now: number)
	local t = Diplomacy.treaty(ds, a, b)
	if t ~= nil then
		removeTreaty(ds, t)
	end
	Diplomacy.markTraitor(ds, a, now)
	log(ds, { kind = "betrayal", a = a, b = b, at = now })
end

-- Вассалитет: vassal становится вассалом overlord. Союзы вассала рвутся, предложения между ними снимаются.
function Diplomacy.setVassal(ds: DiploSet, vassal: number, overlord: number, now: number)
	for _, ally in Diplomacy.alliesOf(ds, vassal) do
		local t = Diplomacy.treaty(ds, vassal, ally)
		if t ~= nil then
			removeTreaty(ds, t)
		end
	end
	local t = Diplomacy.treaty(ds, vassal, overlord)
	if t ~= nil then
		removeTreaty(ds, t)
	end
	-- Вассалы вассала переходят к сюзерену.
	for _, sub in Diplomacy.vassalsOf(ds, vassal) do
		ds.vassals[sub] = { overlord = overlord, since = ds.vassals[sub].since }
	end
	ds.vassals[vassal] = { overlord = overlord, since = now }
	log(ds, { kind = "vassal", a = vassal, b = overlord, at = now })
	touch(ds)
end

function Diplomacy.canRebel(ds: DiploSet, vassal: number, now: number): (boolean, string?)
	local v = ds.vassals[vassal]
	if v == nil then
		return false, "notVassal"
	end
	if now - v.since < Config.Diplomacy.VassalRebelSec then
		return false, "tooEarly"
	end
	return true, nil
end

-- Вассал свободен (независимость или сюзерен выбыл).
function Diplomacy.free(ds: DiploSet, vassal: number, now: number, rebellion: boolean)
	local v = ds.vassals[vassal]
	if v == nil then
		return
	end
	ds.vassals[vassal] = nil
	if rebellion then
		log(ds, { kind = "independence", a = vassal, b = v.overlord, at = now })
	end
	touch(ds)
end

-- Записать уступку провинции или отказ (для истории).
function Diplomacy.note(ds: DiploSet, kind: "ceded" | "refused", a: number, b: number, now: number)
	log(ds, { kind = kind, a = a, b = b, at = now })
	touch(ds)
end

-- Держава выбыла: её договоры, предложения и вассалитет исчезают.
function Diplomacy.removeNation(ds: DiploSet, id: number)
	local j = 1
	while j <= #ds.treaties do
		local t = ds.treaties[j]
		if t.a == id or t.b == id then
			table.remove(ds.treaties, j)
		else
			j += 1
		end
	end
	j = 1
	while j <= #ds.offers do
		local o = ds.offers[j]
		if o.from == id or o.to == id then
			table.remove(ds.offers, j)
		else
			j += 1
		end
	end
	ds.vassals[id] = nil
	for vassal, v in ds.vassals do
		if v.overlord == id then
			ds.vassals[vassal] = nil
		end
	end
	ds.traitors[id] = nil
	for key in ds.trade do
		if key // 65536 == id or key % 65536 == id then
			ds.trade[key] = nil
		end
	end
	for key in ds.embargo do
		if key // 65536 == id or key % 65536 == id then
			ds.embargo[key] = nil
		end
	end
	touch(ds)
end

-- Обновление: сроки пактов, разрывы, просроченные предложения, конец меток «Предатель».
function Diplomacy.update(ds: DiploSet, now: number): { Change }
	local changes: { Change } = {}
	for _, t in table.clone(ds.treaties) do
		if t.breakAt ~= nil and now >= t.breakAt then
			-- Пакт, разорванный раньше срока, — предательство.
			local betrayal = t.kind == "pact" and t.untilTime ~= nil and t.breakAt < t.untilTime
			removeTreaty(ds, t)
			local breaker = t.breaker :: number
			if betrayal then
				Diplomacy.markTraitor(ds, breaker, now)
				log(ds, { kind = "betrayal", a = breaker, b = if t.a == breaker then t.b else t.a, at = now })
			else
				log(ds, { kind = "broken", a = breaker, b = if t.a == breaker then t.b else t.a, at = now })
			end
			table.insert(changes, { kind = "broken", treaty = t, betrayal = betrayal })
		elseif t.untilTime ~= nil and now >= t.untilTime then
			removeTreaty(ds, t)
			log(ds, { kind = "expired", a = t.a, b = t.b, at = now })
			table.insert(changes, { kind = "expired", treaty = t })
		end
	end
	for _, o in table.clone(ds.offers) do
		if now >= o.expiresAt then
			Diplomacy.removeOffer(ds, o)
			table.insert(changes, { kind = "offerExpired", offer = o })
		end
	end
	for id, untilTime in ds.traitors do
		if now >= untilTime then
			ds.traitors[id] = nil
			touch(ds)
			table.insert(changes, { kind = "traitorCleared", nation = id })
		end
	end
	return changes
end

return table.freeze(Diplomacy)
