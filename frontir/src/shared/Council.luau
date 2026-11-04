--!strict
--[[
	Council — Совет держав (GDD §8.2, этап 6б). Чистый модуль: когда собирается Совет, голосование (один голос
	у живой державы), итог и действующие резолюции. Что резолюция делает (санкции, перемирие, помощь, свободная
	торговля), применяет MatchSim.

	- Первый Совет — через Council.EverySec от начала игры, дальше каждые EverySec.
	- На голосовании Council.Options случайных резолюций из Council.Pool, голосование — VoteSec.
	- Побеждает вариант с большинством голосов; ничья — тот, что выше в списке; без голосов — резолюции нет.
	Время — игровое (simTime).
]]

local Config = require("./Config")
local Rng = require("./Rng")
local Types = require("./Types")

type Rng = Rng.Rng

export type Vote = {
	options: { Types.Resolution },
	endsAt: number,
	votes: { [number]: number }, -- держава → номер варианта
}

export type Active = {
	kind: Types.Resolution,
	untilTime: number,
	target: number?, -- санкции: против кого
}

export type CouncilState = {
	nextAt: number,
	vote: Vote?,
	active: { Active },
	version: number,
}

-- Что произошло при обновлении.
export type Change = { kind: "opened", vote: Vote } | { kind: "closed", winner: Types.Resolution?, votes: { number } }

local Council = {}

function Council.new(): CouncilState
	return { nextAt = Config.Council.EverySec, vote = nil, active = {}, version = 0 }
end

-- Голоса по вариантам.
function Council.tally(vote: Vote): { number }
	local counts: { number } = table.create(#vote.options, 0)
	for _, option in vote.votes do
		counts[option] = (counts[option] or 0) + 1
	end
	return counts
end

-- Победитель голосования: большинство; ничья — вариант выше в списке; без голосов — nil.
function Council.winner(vote: Vote): Types.Resolution?
	local counts = Council.tally(vote)
	local best, bestCount = 0, 0
	for k = 1, #vote.options do
		if (counts[k] or 0) > bestCount then
			best, bestCount = k, counts[k]
		end
	end
	return if best > 0 then vote.options[best] else nil
end

function Council.vote(c: CouncilState, nation: number, option: number): (boolean, string?)
	local v = c.vote
	if v == nil then
		return false, "noVote"
	end
	if option ~= math.floor(option) or option < 1 or option > #v.options then
		return false, "badOption"
	end
	v.votes[nation] = option -- переголосовать можно, пока идёт голосование
	c.version += 1
	return true, nil
end

-- Действует ли резолюция kind (и против кого).
function Council.active(c: CouncilState, kind: Types.Resolution, now: number): Active?
	for _, a in c.active do
		if a.kind == kind and now < a.untilTime then
			return a
		end
	end
	return nil
end

function Council.addActive(c: CouncilState, kind: Types.Resolution, untilTime: number, target: number?)
	table.insert(c.active, { kind = kind, untilTime = untilTime, target = target })
	c.version += 1
end

-- Случайные варианты из пула (без повторов).
local function pickOptions(rng: Rng): { Types.Resolution }
	local pool = (table.clone(Config.Council.Pool) :: any) :: { Types.Resolution }
	local out: { Types.Resolution } = {}
	while #out < Config.Council.Options and #pool > 0 do
		local k = Rng.range(rng, 1, #pool)
		table.insert(out, pool[k])
		table.remove(pool, k)
	end
	return out
end

function Council.update(c: CouncilState, now: number, rng: Rng): { Change }
	local changes: { Change } = {}
	-- Кончились резолюции.
	local j = 1
	while j <= #c.active do
		if now >= c.active[j].untilTime then
			table.remove(c.active, j)
			c.version += 1
		else
			j += 1
		end
	end
	local v = c.vote
	if v ~= nil and now >= v.endsAt then
		c.vote = nil
		c.version += 1
		table.insert(changes, { kind = "closed", winner = Council.winner(v), votes = Council.tally(v) })
	elseif v == nil and now >= c.nextAt then
		local vote: Vote = { options = pickOptions(rng), endsAt = now + Config.Council.VoteSec, votes = {} }
		c.vote = vote
		c.nextAt = now + Config.Council.EverySec
		c.version += 1
		table.insert(changes, { kind = "opened", vote = vote })
	end
	return changes
end

return table.freeze(Council)
