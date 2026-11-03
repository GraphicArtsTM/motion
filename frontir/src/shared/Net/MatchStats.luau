--!strict
--[[
	MatchStats — что сервер рассылает о матче (Net/Protocol STATS и FORCES), собранное из MatchSim.
	Чистый модуль: им пользуются MatchService (рассылка) и тест трафика (Net.spec — 60 держав).
]]

local Economy = require("../Economy")
local Forces = require("../Forces")
local Grid = require("../Grid")
local MatchSim = require("../MatchSim")
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
			maxPeople = Economy.maxPeople(cells),
			cells = cells,
			troops = MatchSim.troopsOf(m, n.id),
			power = Forces.total(n.home),
			frontPower = Forces.total(MatchSim.frontForces(m, n.id)),
			cities = MatchSim.citiesOf(m, n.id),
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
	return { kinds = kinds, queue = queue }
end

return table.freeze(MatchStats)
