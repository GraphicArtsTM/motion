--!strict
--[[
	MatchStats — что сервер рассылает о матче (Net/Protocol STATS, FORCES и WARS), собранное из MatchSim.
	Чистый модуль: им пользуются MatchService (рассылка) и тест трафика (Net.spec — 60 держав).
]]

local ClientState = require("../ClientState")
local Config = require("../Config")
local Council = require("../Council")
local Forces = require("../Forces")
local Grid = require("../Grid")
local MatchSim = require("../MatchSim")
local Types = require("../Types")
local Wars = require("../Wars")
local Protocol = require("./Protocol")

local MatchStats = {}

-- Общая статистика: все державы и все атаки/фронты.
function MatchStats.build(m: MatchSim.Match, tickMs: number, changed: number): Protocol.Stats
	local nations: { Protocol.NationStats } = {}
	for _, n in m.nations do
		local cells = Grid.cellsOf(m.grid, n.id)
		table.insert(nations, {
			id = n.id,
			people = n.people,
			maxPeople = MatchSim.maxPeopleOf(m, n.id),
			cells = cells,
			troops = MatchSim.troopsOf(m, n.id),
			power = Forces.total(n.home),
			frontPower = Forces.total(MatchSim.frontForces(m, n.id)),
			cities = MatchSim.citiesOf(m, n.id),
			mix = Forces.composition(n.home),
			weariness = Wars.weariness(m.wars, n.id, m.simTime),
		})
	end
	local attacks: { Protocol.AttackStats } = {}
	for _, a in m.attacks do
		table.insert(attacks, {
			attacker = a.attacker,
			target = a.target,
			troops = a.troops,
			power = Forces.total(a.forces),
			mix = Forces.composition(a.forces),
			supplied = a.supplied,
			fighting = a.fighting,
			ratio = a.ratio,
			focus = a.focus,
		})
	end
	return { tickMs = tickMs, changed = changed, nations = nations, attacks = attacks }
end

-- Свои войска державы: дома, на фронтах, очередь найма.
function MatchStats.forcesOf(m: MatchSim.Match, nationId: number): Protocol.MyForces
	local n = m.nations[nationId]
	local front = MatchSim.frontForces(m, nationId)
	local kinds: { Protocol.KindForces } = {}
	for kind = 1, Forces.KINDS do
		kinds[kind] = {
			home = if n ~= nil then n.home[kind].strength else 0,
			xp = if n ~= nil then n.home[kind].xp else 0,
			front = front[kind].strength,
		}
	end
	local queue: { Protocol.QueueItem } = {}
	if n ~= nil then
		for _, r in n.queue do
			table.insert(queue, { kind = r.kind, left = r.left })
		end
	end
	local e = m.economy[nationId]
	return {
		kinds = kinds,
		queue = queue,
		economy = {
			money = if n ~= nil then n.money else 0,
			oil = if n ~= nil then n.oil else 0,
			income = if e ~= nil then e.income else 0,
			oilIncome = if e ~= nil then e.oilIncome else 0,
			upkeep = if e ~= nil then e.upkeep else 0,
			factories = MatchSim.ownedOf(m, nationId).factories,
		},
	}
end

-- Войны и запреты на новую войну после мира (§6.7а). Обратные отсчёты — в секундах реального времени
-- (игровое время ÷ Match.Speed), чтобы таймер у клиента шёл как часы.
function MatchStats.wars(m: MatchSim.Match): Protocol.WarsMessage
	local function power(id: number): number
		local n = m.nations[id]
		return if n ~= nil then Forces.total(n.home) + Forces.total(MatchSim.frontForces(m, id)) else 0
	end
	local wars: { Protocol.WarStats } = {}
	for _, war in m.wars.list do
		local byA, byB = Wars.takenCells(war, m.grid)
		local p = war.proposal
		table.insert(wars, {
			a = war.a,
			b = war.b,
			active = war.state == "active",
			timeLeft = math.max(0, war.activeAt - m.simTime) / m.speed,
			age = math.max(0, m.simTime - war.activeAt),
			takenA = byA,
			takenB = byB,
			lossesA = war.lossesA,
			lossesB = war.lossesB,
			powerA = power(war.a),
			powerB = power(war.b),
			proposalFrom = if p ~= nil then p.from else 0,
			proposalTerms = if p ~= nil then p.terms else "white",
			proposalLeft = if p ~= nil then math.max(0, p.expiresAt - m.simTime) / m.speed else 0,
		})
	end
	local cooldowns: { Protocol.Cooldown } = {}
	for key, untilTime in m.wars.cooldown do
		local left = untilTime - m.simTime
		if left > 0 then
			-- Стороны считаем отдельно: StyLua 2.6 падает на «//» внутри конструктора таблицы.
			local a, b = key // 65536, key % 65536
			table.insert(cooldowns, { a = a, b = b, left = left / m.speed })
		end
	end
	table.sort(cooldowns, function(x: Protocol.Cooldown, y: Protocol.Cooldown): boolean
		if x.a ~= y.a then
			return x.a < y.a
		end
		return x.b < y.b
	end)
	return { wars = wars, cooldowns = cooldowns }
end

-- Договоры (§8.1) для всех: таблица diplo, сроки — сколько секунд игрового времени осталось.
function MatchStats.diplo(m: MatchSim.Match): ClientState.DiploMessage
	local ds, now = m.diplo, m.simTime
	local treaties: { ClientState.DiploTreaty } = {}
	for _, t in ds.treaties do
		table.insert(treaties, {
			kind = t.kind,
			a = t.a,
			b = t.b,
			left = if t.untilTime ~= nil then math.max(0, t.untilTime - now) else nil,
			breakLeft = if t.breakAt ~= nil then math.max(0, t.breakAt - now) else nil,
		})
	end
	local offers: { ClientState.DiploOffer } = {}
	for _, o in ds.offers do
		table.insert(
			offers,
			{ kind = o.kind, from = o.from, to = o.to, province = o.province, left = math.max(0, o.expiresAt - now) }
		)
	end
	local traitors: { { id: number, left: number } } = {}
	for id, untilTime in ds.traitors do
		if untilTime > now then
			table.insert(traitors, { id = id, left = untilTime - now })
		end
	end
	local vassals: { { vassal: number, overlord: number, rebelLeft: number } } = {}
	for id, v in ds.vassals do
		local rebelLeft = math.max(0, v.since + Config.Diplomacy.VassalRebelSec - now)
		table.insert(vassals, { vassal = id, overlord = v.overlord, rebelLeft = rebelLeft })
	end
	local history: { { kind: string, a: number, b: number, minutes: number? } } = {}
	for _, e in ds.history do
		local kind: string = e.kind
		table.insert(history, { kind = kind, a = e.a, b = e.b, minutes = e.minutes })
	end
	local trade: { { a: number, b: number } } = {}
	for key in ds.trade do
		local a = key // 65536 -- StyLua 2.6 падает на «//» внутри конструктора таблицы
		table.insert(trade, { a = a, b = key % 65536 })
	end
	local embargoes: { { from: number, to: number } } = {}
	for key in ds.embargo do
		local from = key // 65536
		table.insert(embargoes, { from = from, to = key % 65536 })
	end
	-- Совет держав: голосование (варианты, сколько осталось, голоса), действующие резолюции.
	local c = m.council
	local active: { { kind: Types.Resolution, left: number, target: number? } } = {}
	for _, a in c.active do
		if a.untilTime > now then
			table.insert(active, { kind = a.kind, left = a.untilTime - now, target = a.target })
		end
	end
	local v = c.vote
	local council: ClientState.DiploCouncil = {
		vote = if v ~= nil
			then { options = v.options, left = math.max(0, v.endsAt - now), tallies = Council.tally(v) }
			else nil,
		active = active,
		nextLeft = math.max(0, c.nextAt - now),
	}
	return {
		kind = "diplo",
		treaties = treaties,
		offers = offers,
		traitors = traitors,
		vassals = vassals,
		history = history,
		trade = trade,
		embargoes = embargoes,
		council = council,
	}
end

return table.freeze(MatchStats)
