--!strict
--[[
	Modes — режимы матча (GDD §5.1, этап 8а). Чистый модуль: правила режима как данные, варианты голосования
	(«Каждый сам за себя», «Команды», режим недели), подсчёт голосов, деление на команды по месту старта.
	MatchSim берёт правила из m.rules, клиент — по id режима из info (тот же модуль).
]]

local Config = require("./Config")
local Types = require("./Types")

export type ModeId = Types.ModeId

export type Rules = {
	mode: ModeId,
	victoryShare: number, -- доля суши для победы (державы с союзом или команды)
	timeLimitSec: number, -- лимит времени матча (часы матча)
	speed: number, -- множитель скорости поверх Config.Match.Speed
	visionMul: number, -- обзор тумана ×
	fog: boolean, -- туман на карте (только «Мгла»; в остальных карта открыта, скрыта мощь — §6.11а)
	hideTerritory: boolean, -- туман прячет и чужие границы (правило 7а)
	siloFree: boolean, -- ракетная шахта без технологии
	teams: boolean,
	capitalHunt: boolean,
	duel: boolean, -- «Дуэль» (§5.2): без ботов, 2×2 — две команды
	flood: boolean, -- «Потоп» (§5.3): вода поднимается по ступеням
	diplomacy: boolean, -- false — только война и мир (частный сервер, §5.4)
	boosts: boolean, -- бусты магазина и бонусы пропусков (§11.1); в «Дуэли» — нет
}

local Modes = {}

function Modes.isMode(id: any): boolean
	return table.find(Types.ModeIds, id) ~= nil
end

function Modes.rules(id: ModeId): Rules
	local match, cfg = Config.Match, Config.Modes
	local r: Rules = {
		mode = id,
		victoryShare = match.VictoryLandShareFfa,
		timeLimitSec = match.TimeLimitSec,
		speed = 1,
		visionMul = 1,
		fog = false,
		hideTerritory = Config.Fog.HideTerritory,
		siloFree = false,
		teams = false,
		capitalHunt = false,
		duel = false,
		flood = false,
		diplomacy = true,
		boosts = true,
	}
	if id == "Teams" then
		r.teams = true
		r.victoryShare = match.VictoryLandShareTeams
	elseif id == "Blitz" then
		r.speed = cfg.BlitzSpeed
		r.timeLimitSec = match.BlitzDurationSec
	elseif id == "Mist" then
		r.fog = true
		r.visionMul = cfg.MistVisionMul
		r.hideTerritory = true
	elseif id == "Superweapon" then
		r.siloFree = true
	elseif id == "CapitalHunt" then
		r.capitalHunt = true
	elseif id == "Flood" then
		r.flood = true
	elseif id == "Duel" then
		local duel = cfg.Duel
		r.duel = true
		r.boosts = false -- рейтинговая дуэль — без платных преимуществ (§11.1)
		r.victoryShare = duel.VictoryShare
		r.timeLimitSec = duel.TimeLimitSec
		r.speed = duel.Speed
	end
	return table.freeze(r)
end

-- Правила режима с туманом на карте (правило 7а без «Мглы»): тесты тумана, частные серверы (8в).
function Modes.withFog(id: ModeId): Rules
	local r = table.clone(Modes.rules(id))
	r.fog = true
	return table.freeze(r)
end

-- Режим недели: номер недели UTC (с понедельника) по кругу Config.Modes.Weekly.
function Modes.weekly(unixTime: number): ModeId
	local list = Config.Modes.Weekly
	local week = math.floor((unixTime - Config.Modes.WeekStartUnix) / (7 * 86400))
	return list[week % #list + 1] :: ModeId
end

-- Варианты голосования в лобби; «Дуэль» — четвёртым, если игроков ровно 2 или 4 (§5.2).
function Modes.options(unixTime: number, humans: number?): { ModeId }
	local out: { ModeId } = { "Ffa", "Teams", Modes.weekly(unixTime) }
	if humans ~= nil and table.find(Config.Modes.Duel.Players, humans) ~= nil then
		table.insert(out, "Duel")
	end
	return out
end

-- Голосование за карту (§5.2): текущая первой, дальше Options − 1 случайных других из пула (pick(n) → 1..n).
function Modes.mapOptions(current: string, pick: (n: number) -> number): { string }
	local rest: { string } = {}
	for _, id in Config.MapVote.Pool do
		if id ~= current then
			table.insert(rest, id)
		end
	end
	local out = { current }
	while #out < Config.MapVote.Options and #rest > 0 do
		table.insert(out, table.remove(rest, pick(#rest)) :: string)
	end
	return out
end

-- Итог голосования за карту: больше голосов; ничья — раньше в списке; голосов нет — первая (текущая).
function Modes.mapWinner(options: { string }, votes: { [number]: string }): string
	local counts = Modes.mapCounts(options, votes)
	local best = 1
	for k = 2, #options do
		if counts[k] > counts[best] then
			best = k
		end
	end
	return options[best]
end

function Modes.mapCounts(options: { string }, votes: { [number]: string }): { number }
	local out: { number } = table.create(#options, 0)
	for _, id in votes do
		local k = table.find(options, id)
		if k ~= nil then
			out[k] += 1
		end
	end
	return out
end

-- Голоса по вариантам (в порядке options).
function Modes.counts(options: { ModeId }, votes: { [number]: ModeId }): { number }
	local out: { number } = table.create(#options, 0)
	for _, mode in votes do
		local k = table.find(options, mode)
		if k ~= nil then
			out[k] += 1
		end
	end
	return out
end

-- Итог голосования: больше голосов; ничья или нет голосов — первый из лидеров по порядку вариантов.
function Modes.tally(options: { ModeId }, votes: { [number]: ModeId }): ModeId
	local counts = Modes.counts(options, votes)
	local best = 1
	for k = 2, #options do
		if counts[k] > counts[best] then
			best = k
		end
	end
	return options[best]
end

-- Сколько команд при стольких державах.
function Modes.teamCount(nations: number): number
	for _, row in Config.Modes.TeamsBy do
		if nations <= row.upTo then
			return row.teams
		end
	end
	return 2
end

-- Команды по месту старта: державы по долготе столицы (запад → восток, при равенстве — по id) режутся
-- на count равных кусков. starts — { id, x }. Возвращает держава → номер команды (1..count).
function Modes.assignTeams(starts: { { id: number, x: number } }, count: number): { [number]: number }
	local order = table.clone(starts)
	table.sort(order, function(a, b)
		if a.x ~= b.x then
			return a.x < b.x
		end
		return a.id < b.id
	end)
	local out: { [number]: number } = {}
	local n = #order
	for k, s in order do
		out[s.id] = math.min(count, (k - 1) * count // math.max(1, n) + 1)
	end
	return out
end

return table.freeze(Modes)
