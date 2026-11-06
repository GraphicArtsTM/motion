--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Analytics = require("../src/shared/Analytics")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local RenderBudget = require("../src/shared/RenderBudget")

local W, H = 96, 16

local function trio(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 21)
	m.victory = false
	MatchSim.addPlayer(m, 1, "N1")
	MatchSim.addPlayer(m, 2, "N2")
	MatchSim.addPlayer(m, 3, "N3")
	m.phase = "Play"
	-- Суша: 1 — x 1..50, 2 — 51..70, 3 — 71..80.
	for y = 1, H - 2 do
		for x = 1, 80 do
			Grid.setOwner(m.grid, y * W + x, if x <= 50 then 1 elseif x <= 70 then 2 else 3)
		end
	end
	return m
end

T.describe("Аналитика (этап 10в)", function()
	T.it(
		"Leave: минута, фаза, режим, место по суше; выбывший — последний",
		function()
			local m = trio()
			m.time = 125
			local records = Analytics.leave(m, 2)
			T.expect(#records).toBe(1)
			local r = records[1]
			T.expect(r.name).toBe("Leave")
			T.expect(r.value).toBeNear(2.1, 1e-9)
			T.expect(r.fields[1]).toBe("Play")
			T.expect(r.fields[2]).toBe(m.rules.mode)
			T.expect(r.fields[3]).toBe("2")
			T.expect(Analytics.placeOf(m, 1)).toBe(1)
			T.expect(Analytics.placeOf(m, 3)).toBe(3)
			m.nations[1].alive = false
			T.expect(Analytics.placeOf(m, 1)).toBe(#m.nations)
		end
	)

	T.it(
		"MatchEnd, Commander, MatchResult: длина, генерал и место только у людей; не больше трёх полей",
		function()
			local m = trio()
			m.time = 600
			local e = Analytics.matchEnd(m)
			T.expect(e.name).toBe("MatchEnd")
			T.expect(e.value).toBe(10)
			T.expect(e.fields[2]).toBe(m.map.name)
			MatchSim.setBot(m, 3, "Normal", "Trader")
			local list = Analytics.commanders(m, function(id: number): string
				return if id == 1 then "Scout" else "Marshal"
			end)
			T.expect(#list).toBe(2)
			T.expect(list[1].record.fields[1]).toBe("Scout")
			-- Итог: генерал и место у людей; место — из итогов матча, без итогов — по суше.
			local results = Analytics.results(m, function(id: number): string
				return if id == 1 then "Scout" else "Marshal"
			end)
			T.expect(#results).toBe(2)
			local r1 = results[1].record
			T.expect(r1.name).toBe("MatchResult")
			T.expect(r1.value).toBe(1)
			T.expect(r1.fields[1]).toBe("Scout")
			T.expect(r1.fields[2]).toBe("1")
			T.expect(r1.fields[3]).toBe(m.rules.mode)
			m.result = { winner = 2, reason = "land", places = { 2, 3, 1 }, times = {}, shares = {} } :: any
			T.expect(Analytics.finalPlace(m, 1)).toBe(3)
			T.expect(Analytics.results(m, function(): string
				return "Scout"
			end)[2].record.value).toBe(1)
			for _, rec in { e, list[1].record, r1, Analytics.leave(m, 1)[1] } do
				T.expect(#rec.fields <= 3).toBe(true)
			end
		end
	)

	T.it(
		"обучение: шаги воронки из событий, выход до конца — TutorialSkip",
		function()
			local steps = Config.Tutorial.Steps
			local s1 = Analytics.funnel({ kind = "tutorial", nation = 1, step = 1 })
			T.expect(s1 ~= nil and s1.step == 1 and s1.name == steps[1]).toBe(true)
			local done = Analytics.funnel({ kind = "tutorialDone", nation = 1 })
			T.expect(done ~= nil and done.step == #steps + 1).toBe(true)
			T.expect(Analytics.funnel({ kind = "tutorial", step = 99 })).toBe(nil)
			T.expect(Analytics.funnel({ kind = "warDeclared" })).toBe(nil)
			T.expect(Analytics.funnel("junk")).toBe(nil)
			local m = trio()
			local rules = table.clone(m.rules)
			rules.tutorial = true
			m.rules = rules
			m.tutorialStep = 3
			local records = Analytics.leave(m, 1)
			T.expect(#records).toBe(2)
			T.expect(records[2].name).toBe("TutorialSkip")
			T.expect(records[2].value).toBe(3)
		end
	)
end)

T.describe("Мелкие решения (сводная правка, часть 3)", function()
	T.it(
		"обучение — только на «Скандинавии»: на другой карте сервер её меняет",
		function()
			local m = trio()
			T.expect(MatchSim.tutorialMap(m)).toBe(nil) -- не обучение
			local rules = table.clone(m.rules)
			rules.tutorial = true
			m.rules = rules
			T.expect(MatchSim.tutorialMap(m)).toBe(Config.Tutorial.Map)
			T.expect(Config.Tutorial.Map).toBe("Scandinavia");
			(m.map :: any).name = "Scandinavia"
			T.expect(MatchSim.tutorialMap(m)).toBe(nil)
		end
	)
end)

T.describe("Телефон (этап 10в)", function()
	T.it("пределы эффектов: на телефоне меньше, на ПК — обычные", function()
		T.expect(RenderBudget.isPhone(true, false)).toBe(true)
		T.expect(RenderBudget.isPhone(true, true)).toBe(false)
		T.expect(RenderBudget.isPhone(false, true)).toBe(false)
		for _, name in { "MaxUnitsOnScreen", "MaxParticles", "MaxCraters" } do
			local pc = (Config.Render.Battle :: any)[name]
			T.expect(RenderBudget.limit(name, false)).toBe(pc)
			T.expect(RenderBudget.limit(name, true) < pc).toBe(true)
		end
		T.expect(RenderBudget.limit("SparkleMax", false)).toBe(Config.Render.SparkleMax)
		T.expect(RenderBudget.limit("SparkleMax", true) < Config.Render.SparkleMax).toBe(true)
	end)
end)
