--!strict
--[[
	Отчёт для правок баланса (этап 10в): lune run tools/balance_report [партий=10] [карта=Europe] [держав=12] [база сидов=5000]
	Пока живой аналитики нет, «логи» — полные партии ботов (сиды 5000 + k·31): длина матча, причины победы, победы
	по генералам, уровням и личностям (доля побед к доле в партиях), способности, события, ракеты, наёмники.
]]

local process = require("@lune/process")

local Commanders = require("../src/shared/Commanders")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")
local Tech = require("../src/shared/Tech")
local Types = require("../src/shared/Types")

local games = tonumber(process.args[1]) or 10
local mapName = process.args[2] or "Europe"
local nations = tonumber(process.args[3]) or 12
local seedBase = tonumber(process.args[4]) or 5000 -- новые сиды — новая выборка (§15д ч.3)
local map = MapFormat.fromModule((require :: any)("../maps/" .. mapName) :: MapFormat.MapModule)
local dt = 1 / Config.Sim.TickRate

type Tally = { [string]: { games: number, wins: number, share: number } }
local byCommander: Tally, byLevel: Tally, byPersonality: Tally = {}, {}, {}
local reasons: { [string]: number } = {}
local abilities: { [string]: number } = {}
local events: { [string]: number } = {}
local lengths: { number } = {}
local missiles, mercs, mercsMoney = 0, 0, 0
-- За первые 10 минут: предательства и сбитые самолёты (сводная правка: в каждой партии хотя бы по одному).
local early = {
	betrayals = 0,
	shot = 0,
	gamesBetrayal = 0,
	gamesShot = 0,
	planes = 0,
	raids = 0,
	shotAll = 0,
	firstShot = math.huge,
	gamesShot15 = 0, -- §15б: партий, где первый сбитый самолёт — до 15-й минуты
}
local techLevels, techNations = 0, 0

local function count(t: Tally, key: string, won: boolean, share: number)
	local e = t[key]
	if e == nil then
		e = { games = 0, wins = 0, share = 0 }
		t[key] = e
	end
	e.games += 1
	e.share += share
	if won then
		e.wins += 1
	end
end

local t0 = os.clock()
for k = 1, games do
	local seed = seedBase + k * 31
	local m = MatchSim.new(map, seed)
	m.targetNations = nations
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, dt)
	end
	local limit = m.rules.timeLimitSec + 5
	local betr, shot = 0, 0
	local shot15 = false
	while m.phase == "Play" and m.time < limit do
		MatchSim.step(m, dt)
		for _, e in MatchSim.takeEvents(m) do
			if m.time <= 600 and e.kind == "betrayal" then
				betr += 1
			elseif m.time <= 600 and e.kind == "planeShot" then
				shot += 1
			elseif m.time <= 600 and e.kind == "planeBuilt" then
				early.planes += 1
			elseif m.time <= 600 and e.kind == "raid" then
				early.raids += 1
			end
			if e.kind == "planeShot" then
				early.shotAll += 1
				shot15 = shot15 or m.time <= 900
				early.firstShot = math.min(early.firstShot, m.time / 60)
			end
			if e.kind == "ability" then
				abilities[e.ability] = (abilities[e.ability] or 0) + 1
			elseif e.kind == "worldEvent" then
				events[e.event] = (events[e.event] or 0) + 1
			elseif e.kind == "missileLaunched" then
				missiles += 1
			elseif e.kind == "mercs" and e.nation ~= 0 then
				mercs += 1
				mercsMoney += e.amount
			end
		end
	end
	local result = m.result :: Types.MatchResult?
	local winner = if result ~= nil then result.winner else 0
	local co: { number } = if result ~= nil and result.coWinners ~= nil then result.coWinners :: { number } else {}
	reasons[if result ~= nil then result.reason else "none"] = (
		reasons[if result ~= nil then result.reason else "none"] or 0
	) + 1
	table.insert(lengths, m.time / 60)
	early.betrayals += betr
	early.shot += shot
	early.gamesBetrayal += if betr > 0 then 1 else 0
	early.gamesShot += if shot > 0 then 1 else 0
	early.gamesShot15 += if shot15 then 1 else 0
	local land = math.max(1, m.grid.capturableCount)
	for _, n in m.nations do
		local won = n.id == winner or table.find(co, n.id) ~= nil
		local share = Grid.cellsOf(m.grid, n.id) / land
		count(byCommander, Commanders.of(m.commanders, n.id), won, share)
		count(byLevel, n.botLevel or "?", won, share)
		count(byPersonality, n.personality or "?", won, share)
		techNations += 1
		for _, b in Tech.Branches do
			techLevels += Tech.level(m.tech, n.id, b :: any)
		end
	end
	print(
		string.format(
			"партия %2d (сид %d): %.1f мин, %s, победил %d (%s, %s, %s)",
			k,
			seed,
			m.time / 60,
			if result ~= nil then result.reason else "—",
			winner,
			if winner ~= 0 then Commanders.of(m.commanders, winner) else "—",
			if winner ~= 0 then m.nations[winner].botLevel or "?" else "—",
			if winner ~= 0 then m.nations[winner].personality or "?" else "—"
		)
	)
end

local function show(title: string, t: Tally)
	local keys: { string } = {}
	for key in t do
		table.insert(keys, key)
	end
	table.sort(keys)
	local parts: { string } = {}
	local totalGames, totalWins = 0, 0
	for _, key in keys do
		totalGames += t[key].games
		totalWins += t[key].wins
	end
	for _, key in keys do
		local e = t[key]
		-- Индекс: доля побед / доля в партиях (1.0 — «по справедливости»).
		local index = if totalWins > 0 then (e.wins / totalWins) / (e.games / totalGames) else 0
		table.insert(
			parts,
			string.format(
				"%s: побед %d из %d, индекс %.2f, суша в конце %.0f%%",
				key,
				e.wins,
				e.games,
				index,
				e.share / e.games * 100
			)
		)
	end
	print(title)
	for _, p in parts do
		print("  " .. p)
	end
end

table.sort(lengths)
local sum = 0
for _, l in lengths do
	sum += l
end
print(
	string.format(
		"\nИТОГ: %d партий «%s», %d держав, %.0f с",
		games,
		mapName,
		nations,
		os.clock() - t0
	)
)
print(
	string.format(
		"Длина матча: средняя %.1f мин, медиана %.1f, от %.1f до %.1f",
		sum / #lengths,
		lengths[(#lengths + 1) // 2],
		lengths[1],
		lengths[#lengths]
	)
)
local rs: { string } = {}
for r, c in reasons do
	table.insert(rs, r .. " " .. c)
end
table.sort(rs)
print("Причины победы: " .. table.concat(rs, ", "))
show("Генералы (держав-партий, индекс побед):", byCommander)
show("Уровни ботов:", byLevel)
show("Личности:", byPersonality)
local function line(t: { [string]: number }): string
	local out: { string } = {}
	for k2, v in t do
		table.insert(out, string.format("%s %.1f", k2, v / games))
	end
	table.sort(out)
	return table.concat(out, ", ")
end
print(
	string.format(
		"Первые 10 минут: предательств %.1f за партию (были в %d из %d партий), сбито самолётов %.1f (в %d из %d), построено самолётов %.1f, налётов %.1f",
		early.betrayals / games,
		early.gamesBetrayal,
		games,
		early.shot / games,
		early.gamesShot,
		games,
		early.planes / games,
		early.raids / games
	)
)
print(
	string.format(
		"За весь матч сбито самолётов %.1f за партию, первый — на %s; партий со сбитым до 15-й минуты — %d из %d",
		early.shotAll / games,
		if early.firstShot < math.huge then string.format("%.1f мин", early.firstShot) else "—",
		early.gamesShot15,
		games
	)
)
print("Способности за партию: " .. line(abilities))
print("События за партию: " .. line(events))
print(
	string.format(
		"Ракет за партию %.1f; наёмников купили %d раз, средняя цена $%.0f; уровней технологий у державы в конце %.1f",
		missiles / games,
		mercs,
		if mercs > 0 then mercsMoney / mercs else 0,
		techLevels / math.max(1, techNations)
	)
)
