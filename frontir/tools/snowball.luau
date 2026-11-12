--!strict
--[[
	Замер «снежного кома» (решение геймдизайнера после внешнего обзора): решается ли матч рано и сбиваются ли
	остальные против лидера. Только замер — правила игры не меняет.

	lune run tools/snowball [партий=12] [карта=Europe] [держав=12] [вариант=base] [база сидов=7000]
	Варианты (одни и те же сиды — сравнение парное):
	  base     — как в игре;
	  noGiant  — без бонусов «Сверхдержавы» (§15м, флаг m.giantOff);
	  noDoom   — без «часов судного дня» (§15з, rules.doomsday = false);
	  neither  — без обоих.
	Пишет итог в build/snowball-<вариант>.json (для сравнения вариантов).

	Что считаем (по доле суши, раз в минуту матча):
	- удержание лидерства: лидер на 3/5/8/10/15-й минуте — среди победителей (сам или в победившем союзе; без
	  победы — первый в конце);
	- предопределённость: ранговая корреляция (Спирмен) доли на минуте N и итоговой доли (1 — всё решено);
	- отрыв: лидер / второй на минуте N; доля лидера на минуте N;
	- камбэки: место будущего победителя на 5-й и 10-й минуте;
	- коалиция: со сколькими державами воюет лидер / сколько войн в среднем у остальных (больше 1 — против лидера
	  объединяются); доля новых войн, объявленных лидеру (против «справедливой» 1 / (живых − 1)).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Diplomacy")
local Grid = require("../src/shared/Grid")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")
local Types = require("../src/shared/Types")

local games = tonumber(process.args[1]) or 12
local mapName = process.args[2] or "Europe"
local nations = tonumber(process.args[3]) or 12
local variant = process.args[4] or "base"
local seedBase = tonumber(process.args[5]) or 7000
if variant ~= "base" and variant ~= "noGiant" and variant ~= "noDoom" and variant ~= "neither" then
	error("вариант: base | noGiant | noDoom | neither")
end
local map = MapFormat.fromModule((require :: any)("../maps/" .. mapName) :: MapFormat.MapModule)
local dt = 1 / Config.Sim.TickRate
local CHECKS = { 3, 5, 8, 10, 15 } -- минуты матча

-- Ранги (1 — больше всех), одинаковым — средний ранг.
local function ranks(values: { number }): { number }
	local idx: { number } = {}
	for i = 1, #values do
		idx[i] = i
	end
	table.sort(idx, function(a, b)
		return values[a] > values[b]
	end)
	local out: { number } = {}
	local i = 1
	while i <= #idx do
		local j = i
		while j < #idx and values[idx[j + 1]] == values[idx[i]] do
			j += 1
		end
		for k = i, j do
			out[idx[k]] = (i + j) / 2
		end
		i = j + 1
	end
	return out
end

local function spearman(x: { number }, y: { number }): number?
	if #x < 3 then
		return nil
	end
	local rx, ry = ranks(x), ranks(y)
	local n = #rx
	local mx, my = 0, 0
	for i = 1, n do
		mx += rx[i]
		my += ry[i]
	end
	mx /= n
	my /= n
	local sxy, sxx, syy = 0, 0, 0
	for i = 1, n do
		sxy += (rx[i] - mx) * (ry[i] - my)
		sxx += (rx[i] - mx) ^ 2
		syy += (ry[i] - my) ^ 2
	end
	if sxx <= 0 or syy <= 0 then
		return nil
	end
	return sxy / math.sqrt(sxx * syy)
end

type Snapshot = { minute: number, shares: { [number]: number } }

local function sharesOf(m: MatchSim.Match): { [number]: number }
	local land = math.max(1, m.grid.capturableCount)
	local out: { [number]: number } = {}
	for _, n in m.nations do
		if n.alive then
			out[n.id] = Grid.cellsOf(m.grid, n.id) / land
		end
	end
	return out
end

local function leaderOf(shares: { [number]: number }): (number, number, number)
	local best, bestShare, second = 0, -1, 0
	for id, s in shares do
		if s > bestShare then
			best, second, bestShare = id, math.max(second, bestShare), s
		elseif s > second then
			second = s
		end
	end
	return best, math.max(bestShare, 0), math.max(second, 0)
end

-- Сколько войн (объявленных и идущих; закончившиеся из списка убираются) у каждой державы.
local function warsCount(m: MatchSim.Match): { [number]: number }
	local out: { [number]: number } = {}
	for _, w in m.wars.list do
		out[w.a] = (out[w.a] or 0) + 1
		out[w.b] = (out[w.b] or 0) + 1
	end
	return out
end

type Acc = { sum: number, n: number }
local function acc(): Acc
	return { sum = 0, n = 0 }
end
local function add(a: Acc, v: number?)
	if v ~= nil and v == v and v ~= math.huge then
		a.sum += v
		a.n += 1
	end
end
local function mean(a: Acc): number?
	return if a.n > 0 then a.sum / a.n else nil
end

local stats = {
	leaderWins = {} :: { [number]: Acc },
	rho = {} :: { [number]: Acc },
	gap = {} :: { [number]: Acc },
	leaderShare = {} :: { [number]: Acc },
	coalition = {} :: { [number]: Acc },
	winnerRank = {} :: { [number]: Acc },
	warsOnLeader = acc(), -- доля новых войн против текущего лидера
	warsOnLeaderFair = acc(), -- «справедливая» доля 1 / (живых − 1)
	length = acc(),
	decided = acc(), -- партий с победителем
	finalTop = acc(), -- доля первого в конце
	allianceWin = acc(), -- победа союза (у победителя есть со-победители)
	blocShare = acc(), -- доля суши победителей вместе (с вассалами — так считает победа, §8.1)
	vassalShare = acc(), -- из неё — суша вассалов победителей
	vassalWin = acc(), -- без вассалов до победы не хватило бы
	capitulations = acc(), -- капитуляций (новых вассалов) за партию
	vassalToLeader = acc(), -- доля капитуляций перед текущим лидером по суше
}
for _, t in CHECKS do
	stats.leaderWins[t] = acc()
	stats.rho[t] = acc()
	stats.gap[t] = acc()
	stats.leaderShare[t] = acc()
	stats.coalition[t] = acc()
	stats.winnerRank[t] = acc()
end
local reasons: { [string]: number } = {}

local t0 = os.clock()
for k = 1, games do
	local seed = seedBase + k * 37
	local m = MatchSim.new(map, seed)
	m.targetNations = nations
	m.giantOff = variant == "noGiant" or variant == "neither"
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, dt)
	end
	if variant == "noDoom" or variant == "neither" then
		local rules = table.clone(m.rules) -- правила режима заморожены — подменяем копией
		rules.doomsday = false
		m.rules = table.freeze(rules)
	end
	local snaps: { Snapshot } = {}
	local capitulations = 0
	local coalitionAt: { [number]: number } = {}
	local nextMinute = 1
	local limit = m.rules.timeLimitSec + 5
	while m.phase == "Play" and m.time < limit do
		MatchSim.step(m, dt)
		for _, e in MatchSim.takeEvents(m) do
			if e.kind == "vassal" then
				capitulations += 1
				add(stats.vassalToLeader, if e.target == (leaderOf(sharesOf(m))) then 1 else 0)
			elseif e.kind == "warDeclared" then
				local shares = sharesOf(m)
				local leader = leaderOf(shares)
				local alive = 0
				for _ in shares do
					alive += 1
				end
				if alive > 2 and e.nation ~= leader then
					add(stats.warsOnLeader, if e.target == leader then 1 else 0)
					add(stats.warsOnLeaderFair, 1 / (alive - 1))
				end
			end
		end
		if m.time >= nextMinute * 60 then
			local shares = sharesOf(m)
			table.insert(snaps, { minute = nextMinute, shares = shares })
			if table.find(CHECKS, nextMinute) ~= nil then
				-- Коалиция: войны лидера против среднего числа войн остальных живых.
				local leader = leaderOf(shares)
				local wars = warsCount(m)
				local others, count = 0, 0
				for id in shares do
					if id ~= leader then
						others += wars[id] or 0
						count += 1
					end
				end
				local avg = if count > 0 then others / count else 0
				coalitionAt[nextMinute] = if avg > 0 then (wars[leader] or 0) / avg else nil :: any
			end
			nextMinute += 1
		end
	end
	local result = m.result :: Types.MatchResult?
	local final = sharesOf(m)
	local land = math.max(1, m.grid.capturableCount)
	local finalAll: { [number]: number } = {}
	for _, n in m.nations do
		finalAll[n.id] = Grid.cellsOf(m.grid, n.id) / land
	end
	local winner = if result ~= nil and result.winner ~= 0 then result.winner else (leaderOf(final))
	-- Победители: сам победитель и его союзники (в «Каждый за себя» побеждает союз до 3 держав, §8.1).
	local winners: { [number]: boolean } = { [winner] = true }
	local co: { number } = if result ~= nil and result.coWinners ~= nil then result.coWinners :: { number } else {}
	local bloc, vassals = finalAll[winner] or 0, 0
	for _, id in co do
		if not winners[id] then
			winners[id] = true
			bloc += finalAll[id] or 0
		end
	end
	for id in table.clone(winners) do
		for _, v in Diplomacy.vassalsOf(m.diplo, id) do
			vassals += finalAll[v] or 0
		end
	end
	add(stats.vassalShare, vassals)
	add(stats.vassalWin, if result ~= nil and result.reason == "land" and bloc < m.rules.victoryShare then 1 else 0)
	add(stats.capitulations, capitulations)
	bloc += vassals
	local reason = if result ~= nil then result.reason else "none"
	reasons[reason] = (reasons[reason] or 0) + 1
	add(stats.length, m.time / 60)
	add(stats.decided, if result ~= nil and result.winner ~= 0 then 1 else 0)
	add(stats.finalTop, finalAll[winner] or 0)
	add(stats.allianceWin, if #co > 0 then 1 else 0)
	add(stats.blocShare, bloc)
	local line: { string } = {}
	for _, snap in snaps do
		local t = snap.minute
		if table.find(CHECKS, t) ~= nil then
			local leader, top, second = leaderOf(snap.shares)
			add(stats.leaderWins[t], if winners[leader] then 1 else 0)
			add(stats.leaderShare[t], top)
			add(stats.gap[t], if second > 0 then top / second else nil)
			add(stats.coalition[t], coalitionAt[t])
			local xs: { number } = {}
			local ys: { number } = {}
			local winnerShare = snap.shares[winner]
			local rank = 1
			for id, s in snap.shares do
				table.insert(xs, s)
				table.insert(ys, finalAll[id] or 0)
				if winnerShare ~= nil and s > winnerShare then
					rank += 1
				end
			end
			add(stats.rho[t], spearman(xs, ys))
			add(stats.winnerRank[t], if winnerShare ~= nil then rank else nil)
			table.insert(line, string.format("%d′: лидер %d %.0f%%", t, leader, top * 100))
		end
	end
	print(
		string.format(
			"[%s] партия %2d (сид %d): %.1f мин, %s, победил %d (%.0f%%%s) · %s",
			variant,
			k,
			seed,
			m.time / 60,
			reason,
			winner,
			(finalAll[winner] or 0) * 100,
			(if #co > 0 then string.format(", союз %d держ.", #co + 1) else "")
				.. (if vassals > 0 then string.format(", вассалы %.0f%%", vassals * 100) else ""),
			table.concat(line, ", ")
		)
	)
end

local function fmt(v: number?, pattern: string): string
	return if v ~= nil then string.format(pattern, v) else "—"
end

local summary: { [string]: any } = {
	variant = variant,
	map = mapName,
	nations = nations,
	games = games,
	seedBase = seedBase,
	length = mean(stats.length),
	decided = mean(stats.decided),
	finalTop = mean(stats.finalTop),
	allianceWin = mean(stats.allianceWin),
	blocShare = mean(stats.blocShare),
	vassalShare = mean(stats.vassalShare),
	vassalWin = mean(stats.vassalWin),
	capitulations = mean(stats.capitulations),
	vassalToLeader = mean(stats.vassalToLeader),
	warsOnLeader = mean(stats.warsOnLeader),
	warsOnLeaderFair = mean(stats.warsOnLeaderFair),
	reasons = reasons,
	checks = {},
}
print(
	string.format(
		"\nИТОГ [%s]: %d партий «%s», %d держав, %.0f с",
		variant,
		games,
		mapName,
		nations,
		os.clock() - t0
	)
)
local rs: { string } = {}
for r, c in reasons do
	table.insert(rs, r .. " " .. c)
end
table.sort(rs)
print(
	string.format(
		"Длина %s мин; победа в %s партий (%s); победа союза %s; доля победителя %s, с союзниками %s",
		fmt(mean(stats.length), "%.1f"),
		fmt(mean(stats.decided) and (mean(stats.decided) :: number) * 100, "%.0f%%"),
		table.concat(rs, ", "),
		fmt(mean(stats.allianceWin) and (mean(stats.allianceWin) :: number) * 100, "%.0f%%"),
		fmt(mean(stats.finalTop) and (mean(stats.finalTop) :: number) * 100, "%.0f%%"),
		fmt(mean(stats.blocShare) and (mean(stats.blocShare) :: number) * 100, "%.0f%%")
	)
)
for _, t in CHECKS do
	local row = {
		minute = t,
		leaderWins = mean(stats.leaderWins[t]),
		rho = mean(stats.rho[t]),
		gap = mean(stats.gap[t]),
		leaderShare = mean(stats.leaderShare[t]),
		coalition = mean(stats.coalition[t]),
		winnerRank = mean(stats.winnerRank[t]),
	}
	table.insert(summary.checks, row)
	print(
		string.format(
			"%2d′: лидер среди победителей %s · ρ(доля→итог) %s · отрыв от второго ×%s · доля лидера %s · войн у лидера / у остальных ×%s · место будущего победителя %s",
			t,
			fmt(row.leaderWins and row.leaderWins * 100, "%.0f%%"),
			fmt(row.rho, "%.2f"),
			fmt(row.gap, "%.2f"),
			fmt(row.leaderShare and row.leaderShare * 100, "%.1f%%"),
			fmt(row.coalition, "%.2f"),
			fmt(row.winnerRank, "%.1f")
		)
	)
end
print(
	string.format(
		"Вассалы: капитуляций за партию %s, из них перед лидером по суше %s; суша вассалов у победителя %s; без вассалов не хватило бы до победы — %s партий",
		fmt(mean(stats.capitulations), "%.1f"),
		fmt(mean(stats.vassalToLeader) and (mean(stats.vassalToLeader) :: number) * 100, "%.0f%%"),
		fmt(mean(stats.vassalShare) and (mean(stats.vassalShare) :: number) * 100, "%.0f%%"),
		fmt(mean(stats.vassalWin) and (mean(stats.vassalWin) :: number) * 100, "%.0f%%")
	)
)
print(
	string.format(
		"Новые войны против лидера: %s (справедливо было бы %s)",
		fmt(mean(stats.warsOnLeader) and (mean(stats.warsOnLeader) :: number) * 100, "%.0f%%"),
		fmt(mean(stats.warsOnLeaderFair) and (mean(stats.warsOnLeaderFair) :: number) * 100, "%.0f%%")
	)
)
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile("build/snowball-" .. variant .. ".json", serde.encode("json", summary, true))
