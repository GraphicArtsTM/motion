--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Buildings = require("../src/shared/Buildings")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Diplomacy")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local Lobbies = require("../src/shared/Lobbies")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Modes = require("../src/shared/Modes")
local Profile = require("../src/shared/Profile")

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
			m.lobbyVotes = true -- §15ф Ф1: вариант «Обучение» — в голосовании
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
		"шаги по порядку: старт → расширение → войска → здание → город → удар → союз; в конце — tutorialDone",
		function()
			T.expect(Config.Tutorial.Steps)
				.toEqual({ "start", "expand", "hire", "build", "city", "strike", "alliance" })
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
			-- Здание.
			local province = MapData.getProvince(m.map, n.capital :: number)
			Buildings.place(m.buildings, "Factory", (m.provinces.list[province] :: any).center, province)
			Grid.setOwner(g, (m.provinces.list[province] :: any).center, me)
			MatchSim.refreshOwned(m)
			MatchSim.clearBuildingsCache(m)
			MatchSim.step(m, DT)
			T.expect(stepsOf(m)).toEqual({ 4 })
			-- Город: чужая столица переходит к игроку.
			local bot = if me == 1 then 2 else 1
			local cap = m.nations[bot].capital :: number
			Grid.setOwner(g, cap, me)
			MatchSim.step(m, DT)
			T.expect(stepsOf(m)).toEqual({ 5 })
			-- Удар: пока генерал не бил — шаг стоит; удар без цели (или по своей клетке) — шаг пройден.
			MatchSim.step(m, DT)
			T.expect(m.tutorialStep).toBe(6)
			local okAny = false
			for slot = 1, 2 do
				if not okAny then
					okAny = (MatchSim.useAbility(m, n, slot, n.capital, 0.1))
				end
			end
			T.expect(okAny).toBe(true)
			MatchSim.step(m, DT)
			T.expect(m.tutorialStep).toBe(7)
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

T.describe("Обучение 2.0 (§15ь Л4)", function()
	T.it(
		"из хаба: запрос «обучение» — свой сервер одного игрока, карта и режим обучения; переживает переход",
		function()
			local r = Lobbies.request({ tutorial = true }) :: Lobbies.Request
			T.expect(r ~= nil).toBe(true)
			T.expect(r.map).toBe(Config.Tutorial.Map)
			T.expect(r.mode).toBe("Tutorial")
			T.expect(r.solo).toBe(true)
			-- На сервере матча данные перехода разбираются ещё раз.
			local again = Lobbies.request({ map = r.map, mode = r.mode, solo = r.solo, level = r.level })
			T.expect(again ~= nil and again.mode == "Tutorial").toBe(true)
			-- Обучение не в общем списке: без «одному» его не поднять.
			T.expect(Lobbies.request({ map = "Europe", mode = "Tutorial" })).toBe(nil)
			T.expect(table.find(Config.MapVote.Pool, Config.Tutorial.Map) ~= nil).toBe(true)
		end
	)

	T.it(
		"профиль: «уже спросили» — по ответу и у прошедших; переживает запись",
		function()
			local d = Profile.new()
			T.expect(d.tutorialAsked).toBe(false)
			T.expect((Profile.setPrefs(d, { tutorialAsked = true }))).toBe(true)
			T.expect(Profile.migrate(d).tutorialAsked).toBe(true)
			local old = Profile.new()
			old.tutorialDone = true
			local raw = table.clone(old) :: any
			raw.tutorialAsked = nil -- профиль до §15ь Л4
			T.expect(Profile.migrate(raw).tutorialAsked).toBe(true)
			local fresh = table.clone(Profile.new()) :: any
			fresh.tutorialAsked = nil
			T.expect(Profile.migrate(fresh).tutorialAsked).toBe(false)
		end
	)

	T.it(
		"подсветка: у каждого шага (кроме старта) есть цель на ПК и на телефоне",
		function()
			for _, kind in Config.Tutorial.Steps do
				if kind ~= "start" then
					T.expect((Config.Tutorial.Focus :: any)[kind] ~= nil).toBe(true)
					T.expect((Config.Tutorial.PhoneFocus :: any)[kind] ~= nil).toBe(true)
				end
			end
		end
	)
end)
