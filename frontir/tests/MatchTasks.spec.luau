--!strict
-- Задачи матча (§15й Й1): выбор по положению игрока, награда с серией, итог, пропуск, сеть; боты и «Обучение» — без задач.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")
local MatchTasks = require("../src/shared/MatchTasks")
local Modes = require("../src/shared/Modes")
local Rng = require("../src/shared/Rng")
local Wars = require("../src/shared/Wars")

local DT = 1 / Config.Sim.TickRate
local W, H = 64, 24
local CITY = 12 * W + 42 -- ничей город в провинции 5 (соседней со своей землёй)
local FAR_CITY = 12 * W + 58 -- ничей город в провинции 6 (не соседней)

-- Держава 1 владеет x = 1..34 (провинции 1–4), дальше ничья земля; провинция — 10 столбцов.
local function solo(two: boolean?): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 11)
	m.victory = false
	MatchSim.addPlayer(m, 1, "N1")
	if two then
		MatchSim.addPlayer(m, 2, "N2")
	end
	m.phase = "Play"
	for _, cell in m.cityOf do
		Grid.setCity(m.grid, cell, false)
	end
	table.clear(m.cityOf)
	for y = 1, H - 2 do
		for x = 1, 34 do
			Grid.setOwner(m.grid, y * W + x, 1)
		end
	end
	local n = m.nations[1]
	n.colorIndex = 1
	n.capital = 12 * W + 10
	n.money = 1e6
	Grid.setCity(m.grid, n.capital :: number, true)
	m.cityOf[-1] = n.capital :: number
	Grid.setCity(m.grid, CITY, true)
	m.cityOf[5] = CITY
	Grid.setCity(m.grid, FAR_CITY, true)
	m.cityOf[6] = FAR_CITY
	return m
end

local function runFor(m: MatchSim.Match, seconds: number): { MatchSim.MatchEvent }
	local out: { MatchSim.MatchEvent } = {}
	for _ = 1, math.ceil(seconds / m.speed * Config.Sim.TickRate) do
		MatchSim.step(m, DT)
		for _, e in MatchSim.takeEvents(m) do
			table.insert(out, e)
		end
	end
	return out
end

local function find(events: { MatchSim.MatchEvent }, kind: string): any
	for _, e in events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

-- Задача нужного вида: факты державы, где оставлен только этот вид.
local function give(m: MatchSim.Match, kind: MatchTasks.Kind): MatchTasks.Task
	local facts = MatchSim.taskFacts(m, 1)
	if kind ~= "City" then
		facts.cities = {}
	end
	if kind ~= "Land" then
		facts.neutralNear = false
	end
	if kind ~= "Build" then
		facts.missing = {}
	end
	if kind ~= "Front" then
		facts.enemies = {}
	end
	local st = MatchTasks.new()
	st.nextAt = 0
	m.tasks[1] = st
	local task = MatchTasks.choose(st, facts, Rng.new(1)) :: MatchTasks.Task
	T.expect(task.kind).toBe(kind)
	m.taskCheckAt = 0
	return task
end

local function facts(): MatchTasks.Facts
	return {
		now = 100,
		cells = 1000,
		totalLand = 50000,
		neutralNear = true,
		cities = { { cell = 5, owner = 0 } },
		missing = { "Barracks" },
		enemies = { { id = 2, taken = 0 } },
		income = 10,
	}
end

T.describe("Задачи матча: чистые правила (§15й Й1)", function()
	T.it(
		"виды — по положению: город, земля, стройка (до UntilSec), фронт",
		function()
			T.expect(MatchTasks.options(facts())).toEqual({ "City", "Land", "Build", "Front" })
			local f = facts()
			f.cities, f.neutralNear, f.missing, f.enemies = {}, false, {}, {}
			T.expect(MatchTasks.options(f)).toEqual({})
			local late = facts()
			late.now = Config.Tasks.Build.UntilSec + 1
			T.expect(table.find(MatchTasks.options(late), "Build")).toBe(nil)
		end
	)

	T.it(
		"награда: не меньше Min, иначе доход × IncomeSec; серия растёт до ×Max; округление до 10",
		function()
			local r = Config.Tasks.Reward
			T.expect(MatchTasks.reward("Land", 0, 0)).toBe(r.Min)
			T.expect(MatchTasks.reward("Land", 1000, 0)).toBe(1000 * r.IncomeSec)
			T.expect(MatchTasks.reward("Land", 1000, 1)).toBe(1000 * r.IncomeSec * (1 + Config.Tasks.Streak.Step))
			T.expect(MatchTasks.reward("Land", 1000, 100)).toBe(1000 * r.IncomeSec * Config.Tasks.Streak.Max)
			T.expect(MatchTasks.reward("City", 3.33, 0) % 10).toBe(0)
		end
	)

	T.it(
		"до nextAt задач нет; прежний вид не повторяется, если есть другой",
		function()
			local st = MatchTasks.new()
			local f = facts()
			f.now = Config.Tasks.FirstSec - 1
			T.expect(MatchTasks.choose(st, f, Rng.new(3))).toBe(nil)
			local rng = Rng.new(5)
			local last: MatchTasks.Kind? = nil
			for k = 1, 30 do
				local s = MatchTasks.new()
				s.nextAt = 0
				s.lastKind = last
				local task = MatchTasks.choose(s, facts(), rng) :: MatchTasks.Task
				T.expect(task ~= nil and task.kind ~= last).toBe(true)
				T.expect(task.id).toBe(1)
				last = task.kind
				T.expect(k > 0).toBe(true)
			end
		end
	)

	T.it(
		"итог: выполнено — серия +1, провал и пропуск — серия с начала; следующая через GapSec",
		function()
			local st = MatchTasks.new()
			st.nextAt = 0
			local task = MatchTasks.choose(st, facts(), Rng.new(2)) :: MatchTasks.Task
			T.expect(MatchTasks.status(task, task.startAt)).toBe("active")
			task.have = task.need
			T.expect(MatchTasks.status(task, task.startAt)).toBe("done")
			MatchTasks.finish(st, true, 200)
			T.expect(st.streak).toBe(1)
			T.expect(st.task).toBe(nil)
			T.expect(st.nextAt).toBe(200 + Config.Tasks.GapSec)
			st.nextAt = 0
			local second = MatchTasks.choose(st, facts(), Rng.new(4)) :: MatchTasks.Task
			T.expect(MatchTasks.status(second, second.deadline)).toBe("failed")
			T.expect(MatchTasks.skip(st, 300)).toBe(true)
			T.expect(st.streak).toBe(0)
			T.expect(MatchTasks.skip(st, 300)).toBe(false)
		end
	)
end)

T.describe("Задачи матча в симуляции (§15й Й1)", function()
	T.it(
		"игрок получает задачу после FirstSec; город — только в соседней провинции",
		function()
			local m = solo()
			local f = MatchSim.taskFacts(m, 1)
			T.expect(#f.cities).toBe(1)
			T.expect(f.cities[1].cell).toBe(CITY)
			T.expect(f.neutralNear).toBe(true)
			T.expect(f.missing).toEqual(Config.Tasks.Build.Order)
			local events = runFor(m, Config.Tasks.FirstSec + Config.Tasks.CheckSec + 1)
			local e = find(events, "taskNew")
			T.expect(e ~= nil and e.nation == 1).toBe(true)
			T.expect(m.tasks[1].task ~= nil).toBe(true)
		end
	)

	T.it(
		"город взят — выполнено: деньги, событие с клеткой и серией",
		function()
			local m = solo()
			local task = give(m, "City")
			T.expect(task.cell).toBe(CITY)
			local money = m.nations[1].money
			Grid.setOwner(m.grid, CITY, 1)
			local done = find(runFor(m, 1), "taskDone")
			T.expect(done ~= nil and done.cell == CITY and done.streak == 1).toBe(true)
			T.expect(m.nations[1].money >= money + task.reward).toBe(true)
			T.expect(m.tasks[1].task).toBe(nil)
		end
	)

	T.it(
		"стройка — выполнено, когда здание достроено (леса не в счёт)",
		function()
			local m = solo()
			local task = give(m, "Build")
			T.expect(task.building).toBe("Barracks")
			T.expect((MatchSim.applyIntent(m, 1, { kind = "build", building = "Barracks", cell = 12 * W + 20 })))
				.toBe(true)
			T.expect(find(runFor(m, 1), "taskDone")).toBe(nil)
			T.expect(table.find(MatchSim.taskFacts(m, 1).missing, "Barracks")).toBe(nil) -- строится — новой такой не дадут
			MatchSim.finishSites(m)
			T.expect(find(runFor(m, 1), "taskDone") ~= nil).toBe(true)
		end
	)

	T.it(
		"время вышло — не успели, серия с начала; новая — через GapSec",
		function()
			local m = solo()
			local task = give(m, "Land")
			m.tasks[1].streak = 3
			local events = runFor(m, task.deadline - m.simTime + Config.Tasks.CheckSec + 1)
			T.expect(find(events, "taskFailed") ~= nil).toBe(true)
			T.expect(m.tasks[1].streak).toBe(0)
			T.expect(m.tasks[1].failed).toBe(1)
			local next = find(runFor(m, Config.Tasks.GapSec + Config.Tasks.CheckSec + 1), "taskNew")
			T.expect(next ~= nil).toBe(true)
		end
	)

	T.it("фронт: считаются клетки врага, взятые после выдачи", function()
		local m = solo(true)
		local n2 = m.nations[2]
		n2.colorIndex = 2
		for y = 1, H - 2 do
			for x = 35, 62 do
				Grid.setOwner(m.grid, y * W + x, 2)
			end
		end
		n2.capital = CITY
		MatchSim.setBot(m, 2, "Novice", "Peaceful")
		MatchSim.declareWar(m, 1, 2)
		runFor(m, Config.War.MobilizationSec + 1)
		T.expect(Wars.isActive(m.wars, 1, 2)).toBe(true)
		local task = give(m, "Front")
		T.expect(task.target).toBe(2)
		for k = 0, task.need - 1 do
			local cell = (1 + k // 4) * W + 35 + k % 4
			Grid.setOwner(m.grid, cell, 1)
			Wars.record(m.wars, cell, 2, 1)
		end
		T.expect(find(runFor(m, 1), "taskDone") ~= nil).toBe(true)
	end)

	T.it("боты и «Обучение» задач не получают", function()
		local m = solo()
		MatchSim.setBot(m, 1, "Normal")
		runFor(m, Config.Tasks.FirstSec + 2)
		T.expect(m.tasks[1]).toBe(nil)
		local t = solo()
		t.rules = Modes.rules("Tutorial")
		runFor(t, Config.Tasks.FirstSec + 2)
		T.expect(t.tasks[1]).toBe(nil)
	end)

	T.it(
		"павшая держава теряет задачу (карточка не висит над экраном поражения)",
		function()
			local m = solo()
			give(m, "Land")
			m.nations[1].alive = false
			runFor(m, Config.Tasks.CheckSec + 0.5)
			T.expect(m.tasks[1].task).toBe(nil)
		end
	)

	T.it("пропуск — намерение taskSkip; без задачи — noTask", function()
		local intent = Intents.parse("taskSkip", {})
		T.expect(intent ~= nil and intent.kind == "taskSkip").toBe(true)
		local m = solo()
		T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "taskSkip" }))).toBe("noTask")
		give(m, "Land")
		T.expect((MatchSim.applyIntent(m, 1, { kind = "taskSkip" }))).toBe(true)
		T.expect(m.tasks[1].task).toBe(nil)
	end)

	T.it(
		"сеть: таблица task → ClientState (осталось секунд идёт по часам клиента)",
		function()
			local m = solo()
			local task = give(m, "City")
			local cs = ClientState.new(W, H)
			ClientState.applyTask(cs, MatchStats.task(m, 1), 10)
			local got = (cs.task :: ClientState.TaskMessage).task :: ClientState.TaskInfo
			T.expect(got.kind).toBe("City")
			T.expect(got.cell).toBe(CITY)
			T.expect(got.reward).toBe(task.reward)
			T.expect(ClientState.taskLeft(cs, 10)).toBeNear(task.deadline - m.simTime, 1e-6)
			T.expect(ClientState.taskLeft(cs, 15) < ClientState.taskLeft(cs, 10)).toBe(true)
			ClientState.applyTask(cs, { kind = "task", task = { kind = "Bad" } }, 11)
			T.expect((cs.task :: ClientState.TaskMessage).task).toBe(nil)
			-- F4: новая задача и «выполнить»
			MatchSim.newTask(m, 1)
			T.expect(m.tasks[1].task).toBe(nil)
			runFor(m, Config.Tasks.CheckSec + 0.5)
			T.expect(m.tasks[1].task ~= nil).toBe(true)
			T.expect(MatchSim.completeTask(m, 1)).toBe(true)
			T.expect(find(runFor(m, Config.Tasks.CheckSec + 0.5), "taskDone") ~= nil).toBe(true)
		end
	)
end)
