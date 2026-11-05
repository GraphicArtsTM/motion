--!strict
--[[
	MatchStats — что сервер рассылает о матче (Net/Protocol STATS, FORCES и WARS), собранное из MatchSim.
	Чистый модуль: им пользуются MatchService (рассылка) и тест трафика (Net.spec — 60 держав).
]]

local ClientState = require("../ClientState")
local Config = require("../Config")
local Commanders = require("../Commanders")
local Council = require("../Council")
local Diplomacy = require("../Diplomacy")
local Air = require("../Air")
local Fleet = require("../Fleet")
local Fog = require("../Fog")
local Forces = require("../Forces")
local Grid = require("../Grid")
local MatchSim = require("../MatchSim")
local Stability = require("../Stability")
local Tech = require("../Tech")
local Types = require("../Types")
local Wars = require("../Wars")
local Protocol = require("./Protocol")

local MatchStats = {}

-- Клетки радаров держав из набора (§6.11).
function MatchStats.radarsOf(m: MatchSim.Match, friends: { [number]: boolean }): { number }
	local out: { number } = {}
	for cell, b in m.buildings.byCell do
		if b.kind == "Radar" and friends[Grid.getOwner(m.grid, cell)] and not MatchSim.isDisabled(m, cell) then
			table.insert(out, cell)
		end
	end
	table.sort(out)
	return out
end

-- Грубый обзор державы (туман, §6.11): друзья и блоки вокруг их границ, радаров и кораблей.
export type Vision = { friends: { [number]: boolean }, blocks: { [number]: boolean } }

function MatchStats.vision(m: MatchSim.Match, viewer: number): Vision
	local friends = Diplomacy.friends(m.diplo, viewer)
	local borders: { { [number]: boolean } } = {}
	for id in friends do
		table.insert(borders, Grid.borderCells(m.grid, id))
	end
	-- Корабли и самолёты друзей тоже дают обзор (радиусы 5–6 клеток — в блоках 8×8 одинаково).
	local ships: { number } = {}
	for _, ship in m.fleet.ships do
		if ship.alive and friends[ship.owner] then
			table.insert(ships, Fleet.cellOf(m.grid.width, ship))
		end
	end
	for _, plane in m.air.planes do
		if plane.alive and friends[plane.owner] then
			table.insert(ships, Air.cellOf(m.grid.width, plane))
		end
	end
	local blocks = Fog.visionBlocks(
		m.grid.width,
		m.grid.height,
		borders,
		MatchStats.radarsOf(m, friends),
		ships,
		Commanders.visionMul(Commanders.of(m.commanders, viewer))
	)
	return { friends = friends, blocks = blocks }
end

-- Какие атаки и фронты видит держава viewer (туман, §6.11): свои и друзей — всегда, чужие — если линия фронта
-- в грубом обзоре. Возвращает фильтр.
function MatchStats.attackFilter(m: MatchSim.Match, viewer: number, vision: Vision?): (a: Types.Attack) -> boolean
	local v = vision or MatchStats.vision(m, viewer)
	local friends, blocks = v.friends, v.blocks
	return function(a: Types.Attack): boolean
		return friends[a.attacker] == true
			or friends[a.target] == true
			or (a.target ~= 0 and Fog.lineVisible(m.grid.width, blocks, a.line))
	end
end

-- Корабли глазами державы viewer (§6.12): свои и друзей — всегда (с грузом), чужие — в грубом обзоре
-- (без груза); заблокированные порты — всем; своя очередь кораблей. viewer nil — зритель: все корабли без груза;
-- all — все корабли (держава игрока выбыла или «Туман выкл»), груз и очередь — свои.
function MatchStats.ships(m: MatchSim.Match, viewer: number?, vision: Vision?, all: boolean?): Protocol.ShipsMessage
	local v = if viewer ~= nil and Config.Fog.Enabled and not all then vision or MatchStats.vision(m, viewer) else nil
	local friends: { [number]: boolean } = if viewer ~= nil then Diplomacy.friends(m.diplo, viewer) else {}
	local w = m.grid.width
	local ships: { Protocol.ShipInfo } = {}
	for _, s in m.fleet.ships do
		if s.alive then
			local mine = friends[s.owner] == true
			local cell = Fleet.cellOf(w, s)
			if mine or v == nil or v.blocks[Fog.blockOf(w, cell)] then
				table.insert(ships, {
					id = s.id,
					owner = s.owner,
					kind = s.kind,
					x = s.x,
					y = s.y,
					state = s.state,
					hp = math.clamp(s.hp / Fleet.maxHp(s.kind), 0, 1),
					cargo = if mine then Fleet.cargoPower(s) else 0,
				})
			end
		end
	end
	local blocked: { number } = {}
	for cell in m.fleet.blocked do
		table.insert(blocked, cell)
	end
	table.sort(blocked)
	local queue: { { kind: "Transport" | "Destroyer", left: number } } = {}
	local own: { Fleet.Build } = if viewer ~= nil then m.fleet.queues[viewer] or {} else {}
	for _, b in own do
		table.insert(queue, { kind = b.kind, left = b.left / m.speed })
	end
	return { ships = ships, blocked = blocked, queue = queue }
end

-- Общая статистика: все державы и атаки/фронты. viewer — держава игрока: чужие фронты вне его обзора
-- не попадают (туман, §6.11); nil — все (зритель, туман выключен).
function MatchStats.build(m: MatchSim.Match, tickMs: number, changed: number, viewer: number?): Protocol.Stats
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
	local visible = if viewer ~= nil and Config.Fog.Enabled then MatchStats.attackFilter(m, viewer) else nil
	for _, a in m.attacks do
		if visible ~= nil and not visible(a) then
			continue
		end
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

-- Та же статистика (full — build без viewer) глазами державы viewer: чужие фронты вне обзора убраны (§6.11).
-- Державы те же — их начало сообщения можно закодировать один раз (Protocol.encodeStatsHead).
function MatchStats.forViewer(m: MatchSim.Match, full: Protocol.Stats, viewer: number?, vision: Vision?): Protocol.Stats
	if viewer == nil or not Config.Fog.Enabled then
		return full
	end
	local visible = MatchStats.attackFilter(m, viewer, vision)
	local attacks: { Protocol.AttackStats } = {}
	for k, a in m.attacks do
		if visible(a) and full.attacks[k] ~= nil then
			table.insert(attacks, full.attacks[k])
		end
	end
	return { tickMs = full.tickMs, changed = full.changed, nations = full.nations, attacks = attacks }
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

-- Стабильность (§6.10) игроку: средняя и его провинции, всем — повстанцы. Таблица stability.
export type StabilityMessage = ClientState.StabilityMessage

function MatchStats.stability(m: MatchSim.Match, viewer: number?): StabilityMessage
	local st = m.stability
	local ids, values = {}, {}
	local average, lowCells = 0, 0
	if viewer ~= nil then
		for _, e in Stability.provincesOf(st, viewer) do
			table.insert(ids, e.province)
			table.insert(values, math.floor(e.value + 0.5))
		end
		local sum = Stability.summaryOf(st, viewer)
		average = math.floor(sum.average + 0.5)
		lowCells = sum.lowCells
	end
	local rebels, rebelLeft = {}, {}
	for p, r in st.rebels do
		table.insert(rebels, p)
		table.insert(rebelLeft, math.max(0, math.floor(r.untilTime - m.simTime)))
	end
	return {
		kind = "stability",
		average = average,
		lowCells = lowCells,
		ids = ids,
		values = values,
		rebels = rebels,
		rebelLeft = rebelLeft,
	}
end

-- Технологии (§6.14) игроку: свои уровни и текущее исследование. Таблица tech.
export type TechMessage = ClientState.TechMessage

function MatchStats.tech(m: MatchSim.Match, viewer: number?): TechMessage
	if viewer == nil then
		return ClientState.emptyTech()
	end
	local r = m.tech.research[viewer]
	return {
		kind = "tech",
		levels = {
			Army = Tech.level(m.tech, viewer, "Army"),
			Economy = Tech.level(m.tech, viewer, "Economy"),
			Fleet = Tech.level(m.tech, viewer, "Fleet"),
		},
		research = if r ~= nil
			then { branch = r.branch, level = r.level, left = math.max(0, math.ceil(r.left)), total = r.total }
			else nil,
	}
end

-- Генерал (§6.15) игроку: кто, сколько до готовности способностей, сколько осталось эффектам. Таблица commander.
export type CommanderMessage = ClientState.CommanderMessage

function MatchStats.commander(m: MatchSim.Match, viewer: number): CommanderMessage
	local st = m.commanders
	local now = m.simTime
	return {
		kind = "commander",
		commander = Commanders.of(st, viewer),
		left = {
			math.ceil(Commanders.left(st, viewer, 1, now)),
			math.ceil(Commanders.left(st, viewer, 2, now)),
		},
		surge = math.max(0, math.ceil((st.surgeUntil[viewer] or 0) - now)),
		reveal = math.max(0, math.ceil((st.revealUntil[viewer] or 0) - now)),
	}
end

-- Самолёты (§6.13) глазами державы viewer: свои и друзей — всегда, чужие — в грубом обзоре; выведенные из строя
-- здания — всем; своя очередь. viewer nil или all — все самолёты.
function MatchStats.air(m: MatchSim.Match, viewer: number?, vision: Vision?, all: boolean?): Protocol.AirMessage
	local v = if viewer ~= nil and Config.Fog.Enabled and not all then vision or MatchStats.vision(m, viewer) else nil
	local friends: { [number]: boolean } = if viewer ~= nil then Diplomacy.friends(m.diplo, viewer) else {}
	local w = m.grid.width
	local planes: { Protocol.PlaneInfo } = {}
	for _, p in m.air.planes do
		if p.alive then
			local cell = Air.cellOf(w, p)
			if friends[p.owner] or v == nil or v.blocks[Fog.blockOf(w, cell)] then
				table.insert(planes, {
					id = p.id,
					owner = p.owner,
					kind = p.kind,
					x = p.x,
					y = p.y,
					state = p.state,
					hp = math.clamp(p.hp / Air.maxHp(p.kind), 0, 1),
				})
			end
		end
	end
	local disabled: { { cell: number, left: number } } = {}
	for cell, untilTime in m.air.disabled do
		if untilTime > m.simTime then
			table.insert(disabled, { cell = cell, left = (untilTime - m.simTime) / m.speed })
		end
	end
	table.sort(disabled, function(a, b): boolean
		return a.cell < b.cell
	end)
	local queue: { { kind: "Fighter" | "Bomber", left: number } } = {}
	local own: { Air.Build } = if viewer ~= nil then m.air.queues[viewer] or {} else {}
	for _, b in own do
		table.insert(queue, { kind = b.kind, left = b.left / m.speed })
	end
	return { planes = planes, disabled = disabled, queue = queue }
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
