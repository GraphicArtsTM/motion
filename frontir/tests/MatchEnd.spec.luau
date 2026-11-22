--!strict
-- Поражение и итоги (§15й Й5): счётчики матча (города, трофеи, задачи, пик суши), «Новый матч» после выбывания.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")

local DT = 1 / Config.Sim.TickRate
local W, H = 64, 24
local CAP1 = 12 * W + 10
local CAP2 = 12 * W + 50
local CITY2 = 6 * W + 40
local NEUTRAL = 18 * W + 33

-- Держава 1 (человек) — x = 1..31, держава 2 — x = 32..62 (бот или второй человек).
local function duo(twoHumans: boolean?): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 13)
	m.victory = false
	MatchSim.addPlayer(m, 1, "N1")
	MatchSim.addPlayer(m, 2, "N2")
	m.phase = "Play"
	for _, cell in m.cityOf do
		Grid.setCity(m.grid, cell, false)
	end
	table.clear(m.cityOf)
	for y = 1, H - 2 do
		for x = 1, 62 do
			Grid.setOwner(m.grid, y * W + x, if x <= 31 then 1 else 2)
		end
	end
	for id, cap in { CAP1, CAP2 } do
		local n = m.nations[id]
		n.colorIndex = id
		n.capital = cap
		Grid.setCity(m.grid, cap, true)
		m.cityOf[-id] = cap
	end
	Grid.setCity(m.grid, CITY2, true)
	m.cityOf[5] = CITY2
	Grid.setOwner(m.grid, NEUTRAL, 0)
	Grid.setCity(m.grid, NEUTRAL, true)
	m.cityOf[4] = NEUTRAL
	if not twoHumans then
		MatchSim.setBot(m, 2, "Novice", "Peaceful")
	end
	return m
end

local function step(m: MatchSim.Match)
	MatchSim.step(m, DT)
	MatchSim.takeEvents(m)
end

T.describe("Счётчики матча (§15й Й5)", function()
	T.it(
		"город — ничей и вражеский — в счёт взявшего; трофеи — суммой; в таблице task",
		function()
			local m = duo()
			step(m)
			Grid.setOwner(m.grid, NEUTRAL, 1)
			step(m)
			DevTools.warNow(m, 1, 2)
			m.nations[2].money = 10000
			Grid.setOwner(m.grid, CITY2, 1)
			step(m)
			local st = MatchSim.matchStats(m, 1)
			T.expect(st.cities).toBe(2)
			T.expect(st.trophies).toBe(math.floor(10000 * Config.Trophy.CityShare))
			T.expect(st.peak >= 48).toBe(true) -- почти половина суши
			T.expect(MatchSim.matchStats(m, 2).cities).toBe(0)
			local cs = ClientState.new(W, H)
			ClientState.applyTask(cs, MatchStats.task(m, 1), 0)
			local got = (
					cs.task :: ClientState.TaskMessage
				).stats :: { cities: number, trophies: number, tasks: number, peak: number }
			T.expect(got.cities).toBe(2)
			T.expect(got.trophies).toBe(st.trophies)
		end
	)

	T.it("пик суши — наибольшая точка графика, а не сейчас", function()
		local m = duo()
		m.history.shares[1] = { 10, 37, 20 }
		T.expect(MatchSim.matchStats(m, 1).peak >= 37).toBe(true)
	end)
end)

T.describe("«Новый матч» после выбывания (§15й Й5)", function()
	T.it(
		"пока жив — нельзя; выбыл и один человек — матч кончается по времени",
		function()
			T.expect(Intents.parse("endSolo", {}) ~= nil).toBe(true)
			local m = duo()
			step(m)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "endSolo" }))).toBe("notNow")
			m.nations[1].alive = false
			T.expect((MatchSim.applyIntent(m, 1, { kind = "endSolo" }))).toBe(true)
			T.expect(m.phase).toBe("Over")
			local result = m.result :: any
			T.expect(result.reason).toBe("time")
			T.expect(result.winner).toBe(2)
		end
	)

	T.it(
		"F4 «Сдаться»: города уходят соседу — держава выбывает, «добил» — он",
		function()
			local m = duo()
			step(m)
			T.expect((DevTools.fall(m, 1))).toBe(true)
			local out: { any } = {}
			MatchSim.step(m, DT)
			for _, e in MatchSim.takeEvents(m) do
				table.insert(out, e)
			end
			local hit = false
			for _, e in out do
				if e.kind == "eliminated" and e.nation == 1 and e.by == 2 then
					hit = true
				end
			end
			T.expect(hit).toBe(true)
			T.expect(m.nations[1].alive).toBe(false)
		end
	)

	T.it("людей в матче двое — нельзя", function()
		local m = duo(true)
		step(m)
		m.nations[1].alive = false
		T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "endSolo" }))).toBe("notNow")
		T.expect(m.phase).toBe("Play")
	end)
end)
