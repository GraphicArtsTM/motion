--!strict
--[[
	Quests — ежедневные задания и рейтинг дуэлей (GDD §11.5, этап 9г). Чистый модуль:
	- forDay: какие задания у игрока в этот день (по номеру дня UTC и UserId, без повторов);
	- sync: новый день — новые задания;
	- onMatch: прогресс по итогу матча, награды (медали и опыт пропуска) и жетон за все три;
	- Эло: ожидание и изменение рейтинга.
]]

local Bits = require("./Bits")
local Config = require("./Config")
local Profile = require("./Profile")

export type MatchOutcome = {
	place: number,
	won: boolean,
	cities: number,
	landPercent: number, -- доля суши державы к концу матча, %
}

export type Done = { pool: number, medals: number, xp: number }

local Quests = {}

-- Индексы пула на день (PerDay штук, без повторов).
function Quests.forDay(day: number, userId: number): { number }
	local pool = Config.Quests.Pool
	local out: { number } = {}
	local salt = 0
	while #out < math.min(Config.Quests.PerDay, #pool) do
		local k = Bits.hash2(day, userId % 2147483647, 7001 + salt) % #pool + 1
		if table.find(out, k) == nil then
			table.insert(out, k)
		end
		salt += 1
	end
	return out
end

function Quests.sync(d: Profile.Data, day: number, userId: number)
	if d.questDay == day then
		return
	end
	d.questDay = day
	d.questsBonus = false
	table.clear(d.quests)
	for _, k in Quests.forDay(day, userId) do
		table.insert(d.quests, { pool = k, progress = 0, done = false })
	end
end

local function step(kind: string, o: MatchOutcome): number
	if kind == "play" then
		return 1
	elseif kind == "win" then
		return if o.won then 1 else 0
	elseif kind == "top3" then
		return if o.place <= 3 then 1 else 0
	end
	return 0
end

-- Итог матча: прогресс, награды выполненных, жетон за все. Возвращает выполненные сейчас и жетонов выдано.
function Quests.onMatch(d: Profile.Data, o: MatchOutcome, day: number, userId: number, now: number): ({ Done }, number)
	Quests.sync(d, day, userId)
	local done: { Done } = {}
	for _, q in d.quests do
		if not q.done then
			local row = Config.Quests.Pool[q.pool]
			if row.kind == "cities" then
				q.progress = math.max(q.progress, o.cities)
			elseif row.kind == "land" then
				q.progress = math.max(q.progress, math.floor(o.landPercent))
			else
				q.progress += step(row.kind, o)
			end
			if q.progress >= row.target then
				q.progress = row.target
				q.done = true
				d.medals += row.medals
				Profile.addSeasonXp(d, row.xp, now)
				table.insert(done, { pool = q.pool, medals = row.medals, xp = row.xp })
			end
		end
	end
	local tokens = 0
	if not d.questsBonus and #d.quests > 0 then
		local all = true
		for _, q in d.quests do
			all = all and q.done
		end
		if all then
			d.questsBonus = true
			tokens = Config.Quests.AllDoneTokens
			d.tokens += tokens
		end
	end
	return done, tokens
end

-- Эло (§11.5): ожидаемый результат a против b и изменение рейтинга a (score: 1 — победа, 0 — поражение).
function Quests.eloExpected(a: number, b: number): number
	return 1 / (1 + 10 ^ ((b - a) / 400))
end

function Quests.eloDelta(a: number, b: number, score: number): number
	return math.round(Config.Elo.K * (score - Quests.eloExpected(a, b)))
end

return table.freeze(Quests)
