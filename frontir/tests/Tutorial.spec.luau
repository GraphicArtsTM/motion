--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Buildings = require("../src/shared/Buildings")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Diplomacy")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Modes = require("../src/shared/Modes")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number

local function stepsOf(m: MatchSim.Match): { number }
	local out: { number } = {}
	for _, e in MatchSim.takeEvents(m) do
		if e.kind == "tutorial" then
			table.insert(out, (e :: any).step)
		end
	end
	return out
end

T.describe("Обучение (§5.5)", function()
	T.it(
		"правила: без событий, бустов и победы; 2 мирных Новичка; вариант для одного игрока",
		function()
			local r = Modes.rules("Tutorial")
			T.expect(r.tutorial).toBe(true)
			T.expect(r.events).toBe(false)
			T.expect(r.boosts).toBe(false)
			local m = MatchSim.new(Fixtures.pangea, 61)
			local me = MatchSim.addPlayer(m, 1, "Новичок") :: number
			MatchSim.startLobby(m)
			T.expect(table.find(m.modeOptions, "Tutorial") ~= nil).toBe(true)
			T.expect((MatchSim.applyIntent(m, me, { kind = "modeVote", mode = "Tutorial" }))).toBe(true)
			while m.phase ~= "Play" do
				MatchSim.step(m, DT)
			end
			T.expect(m.mode).toBe("Tutorial")
			T.expect(#m.nations).toBe(Config.Tutorial.Nations)
			T.expect(m.victory).toBe(false)
			for _, n in m.nations do
				if n.isBot then
					T.expect(n.botLevel).toBe("Novice")
					T.expect(n.personality).toBe("Peaceful")
				end
			end
		end
	)

	T.it(
		"шаги по порядку: старт → расширение → войска → город → здание → союз; в конце — tutorialDone",
		function()
			local m = MatchSim.new(Fixtures.pangea, 62)
			local me = MatchSim.addPlayer(m, 1, "Новичок") :: number
			m.forcedMode = "Tutorial"
			MatchSim.startPick(m)
			while m.phase ~= "Play" do
				MatchSim.step(m, DT)
			end
			for _, n in m.nations do
				m.botNextThink[n.id] = math.huge -- боты не мешают
			end
			MatchSim.step(m, DT)
			T.expect(stepsOf(m)).toEqual({ 1 }) -- старт
			local n = m.nations[me]
			-- Расширение: даём земли в ExpandMul раз больше стартовой.
			local need = m.tutorialStart * Config.Tutorial.ExpandMul
			local g = m.grid
			for i = 0, g.size - 1 do
				if Grid.cellsOf(g, me) >= need then
					break
				end
				if Grid.isCapturable(g, i) and Grid.getOwner(g, i) == 0 and not Grid.isCity(g, i) then
					Grid.setOwner(g, i, me)
				end
			end
			Forces.add(n.home, INF, 100) -- войска
			MatchSim.step(m, DT)
			T.expect(stepsOf(m)).toEqual({ 2, 3 })
			-- Город: чужая столица переходит к игроку.
			local bot = if me == 1 then 2 else 1
			local cap = m.nations[bot].capital :: number
			Grid.setOwner(g, cap, me)
			MatchSim.step(m, DT)
			T.expect(m.tutorialStep).toBe(5)
			-- Здание и союз.
			local province = MapData.getProvince(m.map, n.capital :: number)
			Buildings.place(m.buildings, "Factory", (m.provinces.list[province] :: any).center, province)
			Grid.setOwner(g, (m.provinces.list[province] :: any).center, me)
			MatchSim.refreshOwned(m)
			MatchSim.clearBuildingsCache(m)
			MatchSim.step(m, DT)
			T.expect(m.tutorialStep).toBe(6)
			local ally = 3
			T.expect((MatchSim.offer(m, me, ally, "alliance"))).toBe(true)
			for _ = 1, 30 * Config.Sim.TickRate do
				MatchSim.step(m, DT)
				if Diplomacy.allied(m.diplo, me, ally) then
					break
				end
			end
			T.expect(Diplomacy.allied(m.diplo, me, ally)).toBe(true) -- бот в обучении соглашается
			MatchSim.step(m, DT)
			T.expect(m.tutorialStep).toBe(#Config.Tutorial.Steps + 1)
		end
	)
end)
