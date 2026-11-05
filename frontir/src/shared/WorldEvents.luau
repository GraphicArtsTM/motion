--!strict
--[[
	WorldEvents — случайные события (GDD §6.16, этап 7г). Чистый модуль: расписание, выбор события по весам,
	действующие эффекты (шторм, урожай), аукцион наёмников. Что событие делает с матчем, решает MatchSim
	(секция «События»).
]]

local Config = require("./Config")
local Rng = require("./Rng")

type Rng = Rng.Rng

export type Kind = "OilRush" | "Storm" | "Harvest" | "Mercenaries" | "Revolt" | "Defectors"

export type Storm = { cell: number, radius: number, untilTime: number }
export type Auction = { endsAt: number, top: number, topId: number }

export type WorldState = {
	nextAt: number, -- когда следующее событие (игровое время); 0 — расписание ещё не начато
	storm: Storm?,
	harvestUntil: number,
	auction: Auction?,
	oilExtra: { number }, -- провинции, ставшие нефтяными полями («Нефтяная лихорадка»)
	version: number, -- растёт при изменениях, которые видит клиент (аукцион, шторм, нефть)
}

local WorldEvents = {}

local KINDS: { string } = { "OilRush", "Storm", "Harvest", "Mercenaries", "Revolt", "Defectors" }
WorldEvents.Kinds = KINDS

function WorldEvents.new(): WorldState
	return { nextAt = 0, storm = nil, harvestUntil = 0, auction = nil, oilExtra = {}, version = 0 }
end

-- Пора ли событию (now — время с начала игры). Первое — через FirstSec, дальше — MinGapSec..MaxGapSec.
function WorldEvents.due(st: WorldState, now: number, rng: Rng): boolean
	local cfg = Config.Events
	if st.nextAt == 0 then
		st.nextAt = now + cfg.FirstSec
		return false
	end
	if now < st.nextAt then
		return false
	end
	st.nextAt = now + cfg.MinGapSec + Rng.nextFloat(rng) * (cfg.MaxGapSec - cfg.MinGapSec)
	return true
end

-- Случайное событие по весам Config.Events.Weights (allowed — какие сейчас возможны).
function WorldEvents.pick(rng: Rng, allowed: ((kind: string) -> boolean)?): string?
	local weights = Config.Events.Weights :: any
	local total = 0
	for _, kind in WorldEvents.Kinds do
		if allowed == nil or allowed(kind) then
			total += weights[kind] or 0
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = Rng.nextFloat(rng) * total
	for _, kind in WorldEvents.Kinds do
		if allowed == nil or allowed(kind) then
			roll -= weights[kind] or 0
			if roll < 0 then
				return kind
			end
		end
	end
	return WorldEvents.Kinds[#WorldEvents.Kinds]
end

-- Внутри ли шторма точка (x, y) в клетках.
function WorldEvents.inStorm(st: WorldState, width: number, x: number, y: number, now: number): boolean
	local s = st.storm
	if s == nil or now >= s.untilTime then
		return false
	end
	local dx, dy = x - (s.cell % width + 0.5), y - (s.cell // width + 0.5)
	return dx * dx + dy * dy <= s.radius * s.radius
end

function WorldEvents.harvest(st: WorldState, now: number): boolean
	return st.harvestUntil > now
end

-- Аукцион: наименьшая допустимая ставка сейчас (nil — аукциона нет).
function WorldEvents.minBid(st: WorldState, now: number): number?
	local a = st.auction
	if a == nil or now >= a.endsAt then
		return nil
	end
	local cfg = Config.Events
	return if a.topId == 0 then cfg.MercMinBid else a.top + cfg.MercStep
end

-- Ставка: nil — принята, иначе причина отказа ("noAuction" | "lowBid").
function WorldEvents.bid(st: WorldState, id: number, amount: number, now: number): string?
	local need = WorldEvents.minBid(st, now)
	if need == nil then
		return "noAuction"
	end
	if amount < need then
		return "lowBid"
	end
	local a = st.auction :: Auction
	a.top, a.topId = amount, id
	st.version += 1
	return nil
end

function WorldEvents.startAuction(st: WorldState, now: number)
	st.auction = { endsAt = now + Config.Events.AuctionSec, top = 0, topId = 0 }
	st.version += 1
end

-- Закончился ли аукцион: возвращает его (и убирает), иначе nil.
function WorldEvents.closeAuction(st: WorldState, now: number): Auction?
	local a = st.auction
	if a == nil or now < a.endsAt then
		return nil
	end
	st.auction = nil
	st.version += 1
	return a
end

return table.freeze(WorldEvents)
