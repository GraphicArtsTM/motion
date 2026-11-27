--!strict
-- §15ъ Ч3: настройки игрока — плотность интерфейса и автоответы «всегда нет» (сервер отклоняет сам).
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local Diplomacy = require("../src/shared/Diplomacy")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Profile = require("../src/shared/Profile")
local Wars = require("../src/shared/Wars")

local W, H = 96, 24

local function duo(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 12 + 1)
		end
	end
	local m = MatchSim.new(map, 3)
	m.victory = false
	MatchSim.addPlayer(m, 1, "A")
	MatchSim.addPlayer(m, 2, "B")
	m.phase = "Play"
	for y = 1, H - 2 do
		for x = 1, 80 do
			Grid.setOwner(m.grid, y * W + x, if x <= 40 then 1 else 2)
		end
	end
	local caps = { 12 * W + 10, 12 * W + 70 }
	for _, n in m.nations do
		n.colorIndex = n.id
		n.capital = caps[n.id]
		Grid.setCity(m.grid, caps[n.id], true)
		m.cityOf[-n.id] = caps[n.id]
	end
	return m
end

local function has(events: { any }, kind: string): any
	for _, e in events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

T.describe("Автоответы и плотность (§15ъ Ч3)", function()
	T.it(
		"профиль: плотность и «всегда нет» — только из списков; сброс; переживают запись",
		function()
			local d = Profile.new()
			T.expect(d.hudDensity).toBe("normal")
			T.expect((Profile.setPrefs(d, { density = "min" }))).toBe(true)
			T.expect((Profile.setPrefs(d, { density = "huge" }))).toBe(false)
			T.expect(d.hudDensity).toBe("min")
			T.expect((Profile.setPrefs(d, { autoNo = "pact5", on = true }))).toBe(true)
			T.expect((Profile.setPrefs(d, { autoNo = "demand", on = true }))).toBe(false) -- отказ — война
			T.expect((Profile.setPrefs(d, { autoNo = "peace", on = true }))).toBe(true)
			local back = Profile.migrate(d)
			T.expect(back.hudDensity).toBe("min")
			T.expect(back.autoNo.pact5).toBe(true)
			T.expect(back.autoNo.peace).toBe(true)
			T.expect(back.autoNo.demand).toBe(nil)
			T.expect((Profile.setPrefs(d, { resetAutoNo = true }))).toBe(true)
			T.expect((next(d.autoNo))).toBe(nil)
			T.expect((Profile.setPrefs(d, "x"))).toBe(false)
		end
	)

	T.it(
		"пакт игроку с «всегда нет» — сервер отклоняет сразу; без автоответа — ждёт ответа",
		function()
			local m = duo()
			T.expect((MatchSim.applyIntent(m, 1, { kind = "offer", target = 2, offer = "pact5" }))).toBe(true)
			T.expect(Diplomacy.offerBetween(m.diplo, 1, 2) ~= nil).toBe(true)
			local m2 = duo()
			MatchSim.setAutoNo(m2, 2, { pact5 = true, demand = true })
			T.expect(m2.autoNo[2].demand).toBe(nil) -- требования автоответом не отклоняются
			MatchSim.takeEvents(m2)
			T.expect((MatchSim.applyIntent(m2, 1, { kind = "offer", target = 2, offer = "pact5" }))).toBe(true)
			T.expect(Diplomacy.offerBetween(m2.diplo, 1, 2)).toBe(nil)
			T.expect(has(MatchSim.takeEvents(m2), "offerMade") ~= nil).toBe(true)
		end
	)

	T.it(
		"мир игроку с «мир — всегда нет» — отказ сразу, войну можно продолжать",
		function()
			local m = duo()
			DevTools.warNow(m, 1, 2)
			MatchSim.setAutoNo(m, 2, { peace = true })
			MatchSim.takeEvents(m)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "peace", target = 2, terms = "white" }))).toBe(true)
			local events = MatchSim.takeEvents(m)
			local rejected = has(events, "peaceRejected")
			T.expect(rejected ~= nil).toBe(true)
			T.expect(rejected.nation).toBe(2)
			local war = Wars.find(m.wars, 1, 2)
			T.expect(war ~= nil).toBe(true)
			T.expect((war :: any).proposal).toBe(nil)
			T.expect(table.find(Config.Hud.AutoNoKinds, "demand")).toBe(nil)
		end
	)
end)
