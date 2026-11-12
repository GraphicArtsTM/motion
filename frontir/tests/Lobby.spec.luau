--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Config = require("../src/shared/Config")
local MatchSim = require("../src/shared/MatchSim")
local Modes = require("../src/shared/Modes")
local Profile = require("../src/shared/Profile")

T.describe("Вход в матч без голосований (§15ф Ф1)", function()
	T.it("режим — по кругу ModeRotation, карта — следующая в пуле", function()
		local list = Config.Match.ModeRotation
		for seed = 0, #list * 2 do
			T.expect(Modes.rotation(seed)).toBe(list[seed % #list + 1])
		end
		local pool = Config.MapVote.Pool
		T.expect(Modes.nextMap(pool[1])).toBe(pool[2])
		T.expect(Modes.nextMap(pool[#pool])).toBe(pool[1])
		T.expect(Modes.nextMap("Nowhere")).toBe(pool[1])
	end)

	T.it(
		"лобби: вариантов голосования нет, режим известен сразу и становится режимом матча",
		function()
			local m = MatchSim.new(Fixtures.pangea, 7)
			T.expect(m.lobbyVotes).toBe(Config.Match.LobbyVotes)
			m.lobbyVotes = false
			MatchSim.addPlayer(m, 1, "A")
			MatchSim.addPlayer(m, 2, "B")
			MatchSim.openVote(m, 0)
			MatchSim.startLobby(m)
			T.expect(#m.modeOptions).toBe(0)
			T.expect(#m.mapOptions).toBe(0)
			local want = Modes.rotation(7)
			T.expect(m.mode).toBe(want)
			T.expect(MatchSim.mapWinner(m)).toBe(m.map.name)
			MatchSim.startPick(m)
			T.expect(m.rules.mode).toBe(want)
			-- Без лобби (тесты, арена) — как раньше: «Все против всех».
			local direct = MatchSim.new(Fixtures.pangea, 8)
			direct.lobbyVotes = false
			MatchSim.addPlayer(direct, 1, "A")
			MatchSim.startPick(direct)
			T.expect(direct.rules.mode).toBe("Ffa")
			-- Заданный режим важнее очереди (обучение, F4).
			local tut = MatchSim.new(Fixtures.pangea, 9)
			tut.lobbyVotes = false
			MatchSim.addPlayer(tut, 1, "A")
			MatchSim.startLobby(tut)
			tut.forcedMode = "Tutorial"
			MatchSim.startPick(tut)
			T.expect(tut.rules.mode).toBe("Tutorial")
		end
	)

	T.it(
		"генерал по умолчанию в профиле: только известный и открытый",
		function()
			local d = Profile.new()
			T.expect(select(2, Profile.setCommander(d, "Nobody", false))).toBe("commander")
			T.expect(select(2, Profile.setCommander(d, "Scout", false))).toBe("locked") -- Разведчик — с 10 уровня
			T.expect((Profile.setCommander(d, "Scout", true))).toBe(true) -- пропуск «Все генералы»
			T.expect(d.commander).toBe("Scout")
			T.expect((Profile.setCommander(d, "Marshal", false))).toBe(true)
			-- Переживает сохранение.
			local again = Profile.migrate(d)
			T.expect(again.commander).toBe("Marshal")
			T.expect(Profile.migrate({ commander = "Nobody" }).commander).toBe(nil)
		end
	)
end)
