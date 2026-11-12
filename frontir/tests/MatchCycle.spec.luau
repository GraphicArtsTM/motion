--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MatchSim = require("../src/shared/MatchSim")

local DT = 1 / Config.Sim.TickRate

local function playing(seed: number): MatchSim.Match
	local m = MatchSim.new(Fixtures.pangea, seed)
	m.forcedMode = "Ffa" -- §15ф Ф1: режим по очереди сервера — здесь проверяем «Все против всех»
	MatchSim.addPlayer(m, 1, "A")
	MatchSim.startLobby(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, DT)
	end
	return m
end

-- Отдать державе id нужную долю захватываемой суши (по порядку клеток).
local function grant(m: MatchSim.Match, id: number, share: number)
	local need = math.ceil(m.grid.capturableCount * share) - Grid.cellsOf(m.grid, id)
	for i = 0, m.grid.size - 1 do
		if need <= 0 then
			break
		end
		if Grid.isCapturable(m.grid, i) and Grid.getOwner(m.grid, i) ~= id and not Grid.isCity(m.grid, i) then
			Grid.setOwner(m.grid, i, id)
			need -= 1
		end
	end
end

T.describe("Цикл матча", function()
	T.it("лобби: игроки входят, через LobbySec — выбор старта", function()
		local m = MatchSim.new(Fixtures.pangea, 1)
		MatchSim.addPlayer(m, 1, "A")
		MatchSim.startLobby(m)
		T.expect(m.phase).toBe("Lobby")
		T.expect(MatchSim.addPlayer(m, 2, "B")).toBe(2)
		for _ = 1, math.floor(Config.Match.LobbySec * Config.Sim.TickRate) - 1 do
			MatchSim.step(m, DT)
		end
		T.expect(m.phase).toBe("Lobby")
		MatchSim.step(m, DT)
		MatchSim.step(m, DT)
		T.expect(m.phase).toBe("Pick")
	end)

	T.it(
		"победа по суше: 60% — конец матча, итог, событие; дальше симуляция стоит",
		function()
			local m = playing(2)
			grant(m, 1, Config.Match.VictoryLandShareFfa + 0.01)
			MatchSim.step(m, DT)
			T.expect(m.phase).toBe("Over")
			local result = m.result :: any
			T.expect(result.winner).toBe(1)
			T.expect(result.reason).toBe("land")
			T.expect(result.places[1]).toBe(1)
			T.expect(#result.places).toBe(#m.nations)
			local victory = false
			for _, e in MatchSim.takeEvents(m) do
				if e.kind == "victory" then
					victory = true
				end
			end
			T.expect(victory).toBe(true)
			local tick = m.tick
			MatchSim.step(m, DT)
			T.expect(m.tick).toBe(tick) -- на экране результатов игра не идёт
			T.expect(m.phaseLeft < Config.Match.ResultsSec).toBe(true)
		end
	)

	T.it(
		"последний выживший побеждает; выбывшие — по времени выбывания",
		function()
			local m = playing(3)
			local order = {}
			for k = #m.nations, 2, -1 do
				local n = m.nations[k]
				-- Забираем у державы все города — она выбывает на этом тике.
				for _, cell in m.cityOf do
					if Grid.getOwner(m.grid, cell) == n.id then
						Grid.setOwner(m.grid, cell, 1)
					end
				end
				MatchSim.step(m, 1) -- шаг в секунду: у каждой своё время выбывания
				table.insert(order, n.id)
			end
			T.expect(m.phase).toBe("Over")
			local result = m.result :: any
			T.expect(result.reason).toBe("last")
			T.expect(result.winner).toBe(1)
			-- Позже выбывший — выше: последний выбывший на втором месте.
			T.expect(result.places[2]).toBe(order[#order])
			T.expect(result.places[#result.places]).toBe(order[1])
		end
	)

	T.it(
		"лимит времени: побеждает держава с наибольшей долей суши; график копится",
		function()
			local m = playing(4)
			for _ = 1, 25 * Config.Sim.TickRate do
				MatchSim.step(m, DT)
			end
			T.expect(#m.history.times >= 2).toBe(true)
			grant(m, 3, 0.4)
			m.time = Config.Match.TimeLimitSec
			MatchSim.step(m, DT)
			T.expect(m.phase).toBe("Over")
			local result = m.result :: any
			T.expect(result.reason).toBe("time")
			T.expect(result.winner).toBe(3)
			T.expect(#result.shares[3]).toBe(#result.times)
			T.expect(result.shares[3][#result.times] >= 40).toBe(true)
		end
	)
end)
