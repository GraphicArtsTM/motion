--!strict
--[[
	MatchStats — что сервер рассылает о матче (Net/Protocol STATS, FORCES и WARS), собранное из MatchSim.
	Чистый модуль: им пользуются MatchService (рассылка) и тест трафика (Net.spec — 60 держав).
]]

local Forces = require("../Forces")
local Grid = require("../Grid")
local MatchSim = require("../MatchSim")
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

return table.freeze(MatchStats)
