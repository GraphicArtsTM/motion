--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local Diplomacy = require("../src/shared/Diplomacy")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MatchSim = require("../src/shared/MatchSim")
local Modes = require("../src/shared/Modes")
local Types = require("../src/shared/Types")

local DT = 1 / Config.Sim.TickRate
local WEEK = 7 * 86400

-- Матч на «Пангее»: humans игроков, всего nations держав, режим mode (без голосования), до фазы Play.
local function played(mode: Types.ModeId, humans: number, nations: number): MatchSim.Match
	local m = MatchSim.new(Fixtures.pangea, 77)
	m.targetNations = nations
	for k = 1, humans do
		MatchSim.addPlayer(m, 1000 + k, "Игрок" .. k)
	end
	m.forcedMode = mode
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, DT)
	end
	-- Боты в этих тестах не думают: проверяем правила режима, а не ход партии.
	for _, n in m.nations do
		if n.isBot then
			m.botNextThink[n.id] = math.huge
		end
	end
	return m
end

T.describe("Режимы (§5.1)", function()
	T.it(
		"правила: Блиц ×2 и 8 минут, Мгла прячет границы, Команды — 70%, Супероружие, Охота",
		function()
			local ffa = Modes.rules("Ffa")
			T.expect(ffa.victoryShare).toBeNear(Config.Match.VictoryLandShareFfa)
			T.expect(ffa.timeLimitSec).toBe(Config.Match.TimeLimitSec)
			T.expect(ffa.hideTerritory).toBe(false)
			local blitz = Modes.rules("Blitz")
			T.expect(blitz.speed).toBe(Config.Modes.BlitzSpeed)
			T.expect(blitz.timeLimitSec).toBe(8 * 60)
			local mist = Modes.rules("Mist")
			T.expect(mist.hideTerritory).toBe(true)
			T.expect(mist.visionMul).toBeNear(Config.Modes.MistVisionMul)
			T.expect(Modes.rules("Teams").victoryShare).toBeNear(Config.Match.VictoryLandShareTeams)
			T.expect(Modes.rules("Superweapon").siloFree).toBe(true)
			T.expect(Modes.rules("CapitalHunt").capitalHunt).toBe(true)
		end
	)

	T.it(
		"режим недели — по кругу по номеру недели; варианты: FFA, Команды, режим недели",
		function()
			local t0 = Config.Modes.WeekStartUnix
			local seen: { string } = {}
			for k = 0, #Config.Modes.Weekly - 1 do
				table.insert(seen, Modes.weekly(t0 + k * WEEK + 3600))
			end
			T.expect(seen).toEqual(Config.Modes.Weekly)
			T.expect(Modes.weekly(t0 + #Config.Modes.Weekly * WEEK)).toBe(Config.Modes.Weekly[1])
			T.expect(Modes.weekly(t0 + WEEK - 1)).toBe(Config.Modes.Weekly[1]) -- воскресенье — та же неделя
			local options = Modes.options(t0 + WEEK)
			T.expect(options).toEqual({ "Ffa", "Teams", Config.Modes.Weekly[2] })
		end
	)

	T.it(
		"подсчёт голосов: больше голосов; ничья и пусто — первый по порядку",
		function()
			local options: { Types.ModeId } = { "Ffa", "Teams", "Blitz" }
			T.expect(Modes.tally(options, {})).toBe("Ffa")
			T.expect(Modes.tally(options, { [1] = "Blitz", [2] = "Blitz", [3] = "Teams" })).toBe("Blitz")
			T.expect(Modes.tally(options, { [1] = "Blitz", [2] = "Teams" })).toBe("Teams")
			T.expect(Modes.tally(options, { [1] = "Mist" })).toBe("Ffa") -- не из вариантов — не считается
			T.expect(Modes.counts(options, { [1] = "Blitz", [5] = "Ffa" })).toEqual({ 1, 0, 1 })
		end
	)

	T.it(
		"команды: число по державам, деление по долготе на равные куски",
		function()
			T.expect(Modes.teamCount(6)).toBe(2)
			T.expect(Modes.teamCount(12)).toBe(2)
			T.expect(Modes.teamCount(13)).toBe(3)
			T.expect(Modes.teamCount(60)).toBe(4)
			local teams = Modes.assignTeams({
				{ id = 1, x = 500 },
				{ id = 2, x = 10 },
				{ id = 3, x = 300 },
				{ id = 4, x = 20 },
				{ id = 5, x = 400 },
				{ id = 6, x = 200 },
			}, 2)
			T.expect(teams).toEqual({ [2] = 1, [4] = 1, [6] = 1, [3] = 2, [5] = 2, [1] = 2 })
			local three =
				Modes.assignTeams({ { id = 1, x = 1 }, { id = 2, x = 2 }, { id = 3, x = 3 }, { id = 4, x = 4 } }, 3)
			T.expect(three[1]).toBe(1)
			T.expect(three[4]).toBe(3)
		end
	)

	T.it(
		"голосование в лобби: только игроки, только варианты; конец лобби — режим и скорость",
		function()
			local m = MatchSim.new(Fixtures.pangea, 5)
			local a = MatchSim.addPlayer(m, 1, "A") :: number
			local b = MatchSim.addPlayer(m, 2, "B") :: number
			local c = MatchSim.addPlayer(m, 3, "C") :: number
			MatchSim.openVote(m, Config.Modes.WeekStartUnix) -- неделя 0: Блиц
			MatchSim.startLobby(m)
			T.expect(m.modeOptions).toEqual({ "Ffa", "Teams", "Blitz" })
			T.expect((MatchSim.applyIntent(m, a, { kind = "modeVote", mode = "Blitz" }))).toBe(true)
			T.expect((MatchSim.applyIntent(m, b, { kind = "modeVote", mode = "Blitz" }))).toBe(true)
			T.expect((MatchSim.applyIntent(m, c, { kind = "modeVote", mode = "Mist" }))).toBe(false)
			T.expect((MatchSim.applyIntent(m, c, { kind = "modeVote", mode = "Teams" }))).toBe(true)
			-- Сложность — только когда игрок один.
			T.expect((MatchSim.applyIntent(m, a, { kind = "difficulty", level = "General" }))).toBe(false)
			while m.phase == "Lobby" do
				MatchSim.step(m, DT)
			end
			T.expect(m.mode).toBe("Blitz")
			T.expect(m.speed).toBeNear(Config.Match.Speed * Config.Modes.BlitzSpeed)
			T.expect(m.solo).toBe(false)
			-- В выборе старта голос уже не принимается.
			T.expect((MatchSim.applyIntent(m, a, { kind = "modeVote", mode = "Ffa" }))).toBe(false)
			-- Разбор намерений с клиента.
			T.expect((Intents.parse("modeVote", { mode = "Teams" }))).toEqual({ kind = "modeVote", mode = "Teams" })
			T.expect((Intents.parse("modeVote", { mode = "Real" }))).toBe(nil)
			T.expect((Intents.parse("difficulty", { level = "Novice" })))
				.toEqual({ kind = "difficulty", level = "Novice" })
			T.expect((Intents.parse("solo", { pause = true, fast = false })))
				.toEqual({ kind = "solo", pause = true, fast = false })
			T.expect((Intents.parse("solo", { pause = 1, fast = false }))).toBe(nil)
		end
	)

	T.it(
		"против ботов: один игрок выбирает сложность, ставит паузу и ×2",
		function()
			local m = MatchSim.new(Fixtures.pangea, 9)
			m.targetNations = 4
			local me = MatchSim.addPlayer(m, 1, "Я") :: number
			MatchSim.startLobby(m)
			T.expect((MatchSim.applyIntent(m, me, { kind = "difficulty", level = "General" }))).toBe(true)
			T.expect((MatchSim.applyIntent(m, me, { kind = "solo", pause = true, fast = false }))).toBe(false) -- рано
			while m.phase ~= "Play" do
				MatchSim.step(m, DT)
			end
			T.expect(m.solo).toBe(true)
			for _, n in m.nations do
				if n.isBot then
					T.expect(n.botLevel).toBe("General")
				end
			end
			T.expect((MatchSim.applyIntent(m, me, { kind = "solo", pause = true, fast = true }))).toBe(true)
			T.expect(m.paused).toBe(true)
			T.expect(m.fast).toBe(false) -- на паузе ×2 не включается
			T.expect((MatchSim.applyIntent(m, me, { kind = "solo", pause = false, fast = true }))).toBe(true)
			T.expect(m.paused).toBe(false)
			T.expect(m.fast).toBe(true)
			-- Бот не может.
			T.expect((MatchSim.applyIntent(m, 2, { kind = "solo", pause = true, fast = false }))).toBe(false)
		end
	)

	T.it(
		"команды: вечный союз внутри, войны и договоры со своими нельзя, переводы без налога",
		function()
			local m = played("Teams", 2, 6)
			T.expect(m.teamCount).toBe(2)
			local mates: { [number]: { number } } = {}
			for _, n in m.nations do
				local t = m.teams[n.id]
				T.expect(t ~= nil).toBe(true)
				mates[t :: number] = mates[t :: number] or {}
				table.insert(mates[t :: number], n.id)
			end
			T.expect(#mates[1]).toBe(3)
			T.expect(#mates[2]).toBe(3)
			local a, b, enemy = mates[1][1], mates[1][2], mates[2][1]
			T.expect(Diplomacy.allied(m.diplo, a, b)).toBe(true)
			T.expect(Diplomacy.allied(m.diplo, a, enemy)).toBe(false)
			T.expect(select(2, MatchSim.applyIntent(m, a, { kind = "declare", target = b }))).toBe("team")
			T.expect(select(2, MatchSim.applyIntent(m, a, { kind = "breakTreaty", target = b }))).toBe("team")
			T.expect(select(2, MatchSim.offer(m, a, enemy, "alliance"))).toBe("team")
			T.expect(select(2, MatchSim.offer(m, a, enemy, "pact3"))).toBe("team")
			T.expect((MatchSim.offer(m, a, enemy, "trade"))).toBe(true)
			-- Чужой команде войну объявить можно.
			T.expect((MatchSim.applyIntent(m, a, { kind = "declare", target = enemy }))).toBe(true)
			-- Перевод своим — без налога.
			m.nations[a].money = 1000
			local before = m.nations[b].money
			T.expect((MatchSim.transfer(m, a, b, 500, 0, 0))).toBe(true)
			T.expect(m.nations[b].money - before).toBeNear(500)
		end
	)

	T.it("команды: 70% суши у команды — победа всей команды", function()
		local m = played("Teams", 1, 4)
		local team1: { number } = {}
		for _, n in m.nations do
			if m.teams[n.id] == 1 then
				table.insert(team1, n.id)
			end
		end
		-- Команда 1 забирает почти всю ничью сушу (города врагов не трогаем).
		local g = m.grid
		local k = 0
		for i = 0, g.size - 1 do
			if Grid.isCapturable(g, i) and Grid.getOwner(g, i) == 0 and not Grid.isCity(g, i) then
				k += 1
				Grid.setOwner(g, i, team1[k % #team1 + 1])
			end
		end
		MatchSim.step(m, DT)
		T.expect(m.phase).toBe("Over")
		local result = m.result :: Types.MatchResult
		T.expect(m.teams[result.winner]).toBe(1)
		T.expect(#(result.coWinners :: { number })).toBe(#team1 - 1)
		T.expect(result.reason).toBe("land")
	end)

	T.it("охота на столицы: 3 столицы врагов 60 секунд — победа", function()
		local m = played("CapitalHunt", 1, 5)
		local hunter = 1
		local taken = 0
		for id, cell in m.startCapitals do
			if id ~= hunter and taken < Config.Modes.CapitalHunt.Need then
				Grid.setOwner(m.grid, cell, hunter)
				taken += 1
			end
		end
		MatchSim.step(m, DT)
		T.expect(m.huntCount[hunter]).toBe(3)
		T.expect(m.huntSince[hunter] ~= nil).toBe(true)
		local steps = math.ceil(Config.Modes.CapitalHunt.HoldSec / DT) + 2
		for _ = 1, steps do
			if m.phase ~= "Play" then
				break
			end
			MatchSim.step(m, DT)
		end
		T.expect(m.phase).toBe("Over")
		local result = m.result :: Types.MatchResult
		T.expect(result.winner).toBe(hunter)
		T.expect(result.reason).toBe("capitals")
	end)

	T.it(
		"Супероружие — шахта без технологии; Мгла и Блиц — правила в матче",
		function()
			local sw = played("Superweapon", 1, 3)
			T.expect(MatchSim.techAllows(sw, 1, "MissileSilo")).toBe(true)
			local ffa = played("Ffa", 1, 3)
			T.expect(MatchSim.techAllows(ffa, 1, "MissileSilo")).toBe(false)
			local mist = played("Mist", 1, 3)
			T.expect(mist.rules.hideTerritory).toBe(true)
			local blitz = played("Blitz", 1, 3)
			T.expect(blitz.rules.timeLimitSec).toBe(Config.Match.BlitzDurationSec)
			T.expect(blitz.speed).toBeNear(Config.Match.Speed * Config.Modes.BlitzSpeed)
		end
	)

	T.it(
		"голосование за карту: текущая и две другие; больше голосов; пусто — текущая (§5.2)",
		function()
			local k = 0
			local options = Modes.mapOptions("Europe", function(n: number): number
				k += 1
				return math.min(n, k)
			end)
			T.expect(#options).toBe(Config.MapVote.Options)
			T.expect(options[1]).toBe("Europe")
			T.expect(table.find(options, "Europe", 2)).toBe(nil)
			T.expect(Modes.mapWinner(options, {})).toBe("Europe")
			T.expect(Modes.mapWinner(options, { [1] = options[3], [2] = options[3], [3] = options[2] }))
				.toBe(options[3])
			T.expect(Modes.mapWinner(options, { [1] = options[3], [2] = options[2] })).toBe(options[2]) -- ничья — раньше
			T.expect(Modes.mapCounts(options, { [1] = options[2], [7] = "Nowhere" })).toEqual({ 0, 1, 0 })
			-- §15к: голос — в лобби (не в игре и не на итогах), только игрок, только из вариантов.
			local m = played("Ffa", 2, 3)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "mapVote", map = "World" }))).toBe(false) -- в игре
			DevTools.endMatch(m)
			while m.phase == "Play" do
				MatchSim.step(m, DT)
			end
			T.expect(m.phase).toBe("Over")
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "mapVote", map = "World" }))).toBe("phase")
			local lobby = MatchSim.new(Fixtures.pangea, 78)
			MatchSim.addPlayer(lobby, 1001, "Игрок1")
			MatchSim.addPlayer(lobby, 1002, "Игрок2")
			MatchSim.startLobby(lobby)
			T.expect(lobby.phase).toBe("Lobby")
			T.expect(lobby.mapOptions[1]).toBe(lobby.map.name)
			local other = lobby.mapOptions[2]
			T.expect((MatchSim.applyIntent(lobby, 1, { kind = "mapVote", map = other }))).toBe(true)
			T.expect((MatchSim.applyIntent(lobby, 1, { kind = "mapVote", map = "Atlantis" }))).toBe(false)
			T.expect(MatchSim.mapWinner(lobby)).toBe(other)
			T.expect((Intents.parse("mapVote", { map = "Europe" }))).toEqual({ kind = "mapVote", map = "Europe" })
			T.expect((Intents.parse("mapVote", { map = "Atlantis" }))).toBe(nil)
		end
	)

	T.it(
		"дуэль: вариант при 2 и 4 игроках; без ботов; 2×2 — две команды по двое (§5.2)",
		function()
			T.expect(Modes.options(0, 1)[4]).toBe("Tutorial") -- один игрок — «Обучение» (§5.5)
			T.expect(Modes.options(0, 1)[3]).toBe(Modes.options(0)[3])
			T.expect(Modes.options(0, 2)[4]).toBe("Duel")
			T.expect(Modes.options(0, 3)[4]).toBe(nil)
			T.expect(Modes.options(0, 4)[4]).toBe("Duel")
			local duel = Modes.rules("Duel")
			T.expect(duel.victoryShare).toBeNear(Config.Modes.Duel.VictoryShare)
			T.expect(duel.timeLimitSec).toBe(Config.Modes.Duel.TimeLimitSec)
			-- Лобби: третий игрок пришёл — «Дуэли» нет, голос за неё снят.
			local m = MatchSim.new(Fixtures.pangea, 31)
			local a = MatchSim.addPlayer(m, 1, "A") :: number
			MatchSim.addPlayer(m, 2, "B")
			MatchSim.startLobby(m)
			T.expect(m.modeOptions[4]).toBe("Duel")
			T.expect((MatchSim.applyIntent(m, a, { kind = "modeVote", mode = "Duel" }))).toBe(true)
			MatchSim.addPlayer(m, 3, "C")
			T.expect(m.modeOptions[4]).toBe(nil)
			T.expect(m.modeVotes[a]).toBe(nil)
			-- 1×1: две державы, ботов нет.
			local one = played("Duel", 2, 12)
			T.expect(#one.nations).toBe(2)
			T.expect(one.teamCount).toBe(0)
			-- 2×2: четыре державы, две команды по двое.
			local two = played("Duel", 4, 12)
			T.expect(#two.nations).toBe(4)
			T.expect(two.teamCount).toBe(2)
			local sizes = { 0, 0 }
			for _, n in two.nations do
				sizes[two.teams[n.id]] += 1
			end
			T.expect(sizes).toEqual({ 2, 2 })
		end
	)
end)
