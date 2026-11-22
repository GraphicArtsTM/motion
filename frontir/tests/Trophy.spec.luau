--!strict
-- Трофеи и смелые ходы (§15й Й2): город и столица врага приносят деньги, столица — «Триумф», победа над сильным —
-- «Давид и Голиаф». Без войны и у ничьих — ничего.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")

local DT = 1 / Config.Sim.TickRate
local W, H = 64, 24
local CAP1 = 12 * W + 10
local CAP2 = 12 * W + 50
local CITY2 = 6 * W + 40 -- город державы 2 (не столица)
local NEUTRAL = 18 * W + 33 -- ничей город на земле 1

-- Держава 1 — x = 1..31, держава 2 — x = 32..62; провинция — 10 столбцов.
local function duo(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 11)
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
		n.money = 0
		Grid.setCity(m.grid, cap, true)
		m.cityOf[-id] = cap
	end
	Grid.setCity(m.grid, CITY2, true)
	m.cityOf[5] = CITY2
	Grid.setOwner(m.grid, NEUTRAL, 0)
	Grid.setCity(m.grid, NEUTRAL, true)
	m.cityOf[4] = NEUTRAL
	MatchSim.setBot(m, 2, "Novice", "Peaceful")
	return m
end

local function step(m: MatchSim.Match, seconds: number?): { any }
	local out: { any } = {}
	for _ = 1, math.max(1, math.ceil((seconds or DT) / m.speed * Config.Sim.TickRate)) do
		MatchSim.step(m, DT)
		for _, e in MatchSim.takeEvents(m) do
			table.insert(out, e)
		end
	end
	return out
end

local function find(events: { any }, kind: string): any
	for _, e in events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

T.describe("Трофеи (§15й Й2)", function()
	T.it(
		"город врага в войне — доля его денег за уровень; жертва платит, захватчик получает",
		function()
			local m = duo()
			step(m)
			DevTools.warNow(m, 1, 2)
			m.nations[2].money = 10000
			Grid.setOwner(m.grid, CITY2, 1)
			local e = find(step(m), "trophy")
			local want = math.floor(10000 * Config.Trophy.CityShare)
			T.expect(e ~= nil and e.nation == 1 and e.target == 2 and e.cell == CITY2).toBe(true)
			T.expect(e.amount).toBe(want)
			T.expect(e.capital).toBe(false)
			T.expect(m.nations[2].money <= 10000 - want + 100).toBe(true) -- + доход за тик
			T.expect(m.nations[1].money >= want).toBe(true)
		end
	)

	T.it(
		"у бедной жертвы — не меньше MinPerLevel за уровень («трофейная казна»), не больше Max",
		function()
			T.expect(MatchSim.trophyAmount(0, 0.08, 250)).toBe(250)
			T.expect(MatchSim.trophyAmount(1e9, 0.3, 2500)).toBe(Config.Trophy.Max)
			local m = duo()
			step(m)
			DevTools.warNow(m, 1, 2)
			Grid.setOwner(m.grid, CITY2, 1)
			local e = find(step(m), "trophy")
			T.expect(e.amount).toBe(Config.Trophy.MinPerLevel)
			T.expect(m.nations[2].money >= 0).toBe(true)
		end
	)

	T.it(
		"столица — большой трофей и «Триумф»: фронты быстрее на TriumphSec, потом как раньше",
		function()
			local m = duo()
			step(m)
			DevTools.warNow(m, 1, 2)
			m.nations[2].money = 20000
			T.expect((DevTools.takeCapital(m, 1))).toBe(true)
			local e = find(step(m), "trophy")
			T.expect(e.capital).toBe(true)
			T.expect(e.amount).toBe(math.floor(20000 * Config.Trophy.CapitalShare))
			T.expect(e.triumph).toBe(Config.Trophy.TriumphSec)
			T.expect(MatchSim.triumphMul(m, 1)).toBe(Config.Trophy.TriumphSpeed)
			T.expect(MatchSim.surgeMul(m, 1)).toBe(Config.Trophy.TriumphSpeed)
			T.expect(MatchSim.triumphMul(m, 2)).toBe(1)
			local msg = MatchStats.commander(m, 1)
			T.expect(msg.triumph > 0).toBe(true)
			local cs = ClientState.new(W, H)
			ClientState.applyCommander(cs, msg, 0)
			T.expect(cs.commander.triumph).toBe(msg.triumph)
			m.simTime += Config.Trophy.TriumphSec + 1
			T.expect(MatchSim.triumphMul(m, 1)).toBe(1)
		end
	)

	T.it("без войны, у ничьих и своим — трофея нет", function()
		local m = duo()
		step(m)
		Grid.setOwner(m.grid, CITY2, 1) -- нет войны
		Grid.setOwner(m.grid, NEUTRAL, 1) -- ничей
		T.expect(find(step(m), "trophy")).toBe(nil)
		T.expect((DevTools.takeCapital(m, 1))).toBe(false)
	end)
end)

T.describe("«Давид и Голиаф» (§15й Й2)", function()
	local function fight(mine: number, theirs: number): { any }
		local m = duo()
		Forces.add(m.nations[1].home, 1, mine, 0)
		Forces.add(m.nations[2].home, 1, theirs, 0)
		step(m)
		DevTools.warNow(m, 1, 2)
		for y = 1, H - 2 do
			for x = 32, 62 do
				Grid.setOwner(m.grid, y * W + x, 1)
			end
		end
		return step(m, 1)
	end

	T.it(
		"выбил врага, который был сильнее в UnderdogRatio раза и больше, — награда и событие",
		function()
			local events = fight(1000, 1000 * Config.Trophy.UnderdogRatio)
			T.expect(find(events, "eliminated") ~= nil).toBe(true)
			local e = find(events, "underdog")
			T.expect(e ~= nil and e.nation == 1 and e.target == 2).toBe(true)
			T.expect(e.amount >= Config.Trophy.Underdog.Min).toBe(true)
			T.expect(e.ratio).toBe(Config.Trophy.UnderdogRatio)
		end
	)

	T.it("враг был почти равен — награды нет", function()
		local events = fight(1000, 1000 * Config.Trophy.UnderdogRatio * 0.9)
		T.expect(find(events, "eliminated") ~= nil).toBe(true)
		T.expect(find(events, "underdog")).toBe(nil)
	end)
end)
