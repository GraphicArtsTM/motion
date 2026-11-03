--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local TinyMap = require("./lib/TinyMap")
local BotBrain = require("../src/shared/BotBrain")
local Config = require("../src/shared/Config")
local Expansion = require("../src/shared/Expansion")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MatchSim = require("../src/shared/MatchSim")
local NameGen = require("../src/shared/NameGen")
local RateLimiter = require("../src/shared/RateLimiter")
local Rng = require("../src/shared/Rng")
local StartPositions = require("../src/shared/StartPositions")
local Types = require("../src/shared/Types")

type Nation = Types.Nation

local DT = 1 / Config.Sim.TickRate

local function nation(id: number, people: number): Nation
	return {
		id = id,
		name = "N" .. id,
		nameEn = "N" .. id,
		isBot = false,
		userId = nil,
		colorIndex = id,
		capital = nil,
		people = people,
		alive = true,
	}
end

-- Прогоняет матч на «Пангее» с playerCount игроками до фазы Play (все стартуют автоматически).
local function startedMatch(seed: number, playerCount: number): MatchSim.Match
	local m = MatchSim.new(Fixtures.pangea, seed)
	for k = 1, playerCount do
		MatchSim.addPlayer(m, 1000 + k, "Игрок" .. k)
	end
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, DT)
	end
	return m
end

T.describe("StartPositions", function()
	local g = Grid.new(Fixtures.pangea)

	T.it(
		"вода, слишком близко, слишком маленький круг — нельзя",
		function()
			T.expect(select(2, StartPositions.check(g, 0, {}))).toBe("NotLand")
			T.expect(select(2, StartPositions.check(g, -1, {}))).toBe("OutOfMap")
			T.expect(select(2, StartPositions.check(g, 1.5, {}))).toBe("OutOfMap")
			local rng = Rng.new(3)
			local a = StartPositions.autoPick(g, {}, rng) :: number
			T.expect((StartPositions.check(g, a, {}))).toBe(true)
			T.expect(select(2, StartPositions.check(g, a + 1, { a }))).toBe("TooClose")
			-- Мыс: клетка суши среди воды.
			local tiny = Grid.new(TinyMap.fromRows({ "~~~~~~~~~", "~~~~.~~~~", "~~~~~~~~~" }))
			T.expect(select(2, StartPositions.check(tiny, 13, {}))).toBe("TooSmall")
		end
	)

	T.it(
		"автостарты для 20 держав: все валидны и далеко друг от друга",
		function()
			local rng = Rng.new(5)
			local picks: { number } = {}
			for _ = 1, 20 do
				local p = StartPositions.autoPick(g, picks, rng)
				T.expect(p ~= nil).toBe(true)
				table.insert(picks, p :: number)
			end
			local minD = math.huge
			for i = 1, #picks do
				for j = i + 1, #picks do
					local dx = picks[i] % g.width - picks[j] % g.width
					local dy = picks[i] // g.width - picks[j] // g.width
					minD = math.min(minD, math.sqrt(dx * dx + dy * dy))
				end
			end
			T.expect(minD >= Config.Start.MinDistance).toBe(true)
		end
	)

	T.it("круг старта — связная суша в радиусе", function()
		local cell = StartPositions.autoPick(g, {}, Rng.new(9)) :: number
		local circle = StartPositions.circle(g, cell, Config.Start.Radius)
		T.expect(#circle > 20).toBe(true)
		for _, i in circle do
			T.expect(Grid.isCapturable(g, i)).toBe(true)
			local dx, dy = i % g.width - cell % g.width, i // g.width - cell // g.width
			T.expect(dx * dx + dy * dy <= Config.Start.Radius ^ 2).toBe(true)
		end
	end)
end)

T.describe("NameGen", function()
	T.it(
		"тысячи имён: RU и EN, ни одного реального государства, без повторов среди занятых",
		function()
			local rng = Rng.new(1)
			local taken: { [string]: boolean } = {}
			for _ = 1, 200 do
				local n = NameGen.generate(rng, taken)
				T.expect(taken[n.ru]).toBe(nil)
				taken[n.ru] = true
			end
			for _ = 1, 3000 do
				local n = NameGen.generate(rng)
				T.expect(#n.ru > 0 and #n.en > 0).toBe(true)
				T.expect(NameGen.isDenied(n.ru)).toBe(false)
			end
			T.expect(NameGen.isDenied("Корея")).toBe(true)
		end
	)
end)

T.describe("Expansion", function()
	T.it(
		"захват ничьей земли тратит людей по стоимости местности",
		function()
			local map = TinyMap.fromRows({ "~~~~~~~~", "~..^^^^~", "~..^^^^~", "~~~~~~~~" })
			local g = Grid.new(map)
			local nations = { nation(1, 0) }
			Grid.setOwner(g, 1 * 8 + 1, 1)
			local attack: Types.Attack = { attacker = 1, target = 0, troops = 1000 }
			local spent = 0
			for tick = 1, 40 do
				local before = attack.troops
				local done = Expansion.advance(map, g, nations, attack, tick, 7)
				spent += before - attack.troops
				if done then
					break
				end
			end
			-- Захвачены все 11 клеток: 3 равнины × 1.0 + 8 гор × 2.5.
			T.expect(Grid.cellsOf(g, 1)).toBe(12)
			local mountain = Config.Terrain[Types.Terrain.Mountains].captureCost
			T.expect(spent)
				.toBeNear(3 * Config.Expansion.NeutralCellCost + 8 * mountain * Config.Expansion.NeutralCellCost, 1e-9)
		end
	)

	T.it("река и вода — непреодолимая граница", function()
		local map = TinyMap.fromRows({ "~~~~~~~", "~..r..~", "~..r..~", "~..r..~", "~~~~~~~" })
		local g = Grid.new(map)
		Grid.setOwner(g, 1 * 7 + 1, 1)
		local attack: Types.Attack = { attacker = 1, target = 0, troops = 1000 }
		for tick = 1, 50 do
			if Expansion.advance(map, g, { nation(1, 0) }, attack, tick, 1) then
				break
			end
		end
		T.expect(Grid.cellsOf(g, 1)).toBe(6) -- только левый берег
		T.expect(Grid.getOwner(g, 1 * 7 + 4)).toBe(0)
		T.expect(Expansion.hasFrontier(g, 1, 0)).toBe(false)
	end)

	T.it(
		"фронт идёт с заданной скоростью, а не захватывает всё сразу",
		function()
			local map = TinyMap.plains(60, 60)
			local g = Grid.new(map)
			Grid.setOwner(g, 30 * 60 + 30, 1)
			local attack: Types.Attack = { attacker = 1, target = 0, troops = 1e9 }
			for tick = 1, 50 do
				local front = Expansion.frontier(g, 1, 0)
				local before = Grid.cellsOf(g, 1)
				Expansion.advance(map, g, { nation(1, 0) }, attack, tick, 3)
				local share = Config.Expansion.FrontAdvancePerSec / Config.Sim.TickRate
				T.expect(Grid.cellsOf(g, 1) - before <= math.ceil(#front * share)).toBe(true)
			end
			-- За 5 секунд радиус вырос примерно на FrontAdvancePerSec × 5 клеток (ромб/круг, с запасом).
			local r = Config.Expansion.FrontAdvancePerSec * 5
			T.expect(Grid.cellsOf(g, 1) <= (2 * r + 3) ^ 2).toBe(true)
			T.expect(Grid.cellsOf(g, 1) >= r * r).toBe(true)
		end
	)

	T.it("точка focus тянет атаку в свою сторону", function()
		local map = TinyMap.plains(80, 20)
		local g = Grid.new(map)
		for y = 8, 11 do
			Grid.setOwner(g, y * 80 + 40, 1)
		end
		local attack: Types.Attack = { attacker = 1, target = 0, troops = 1e9, focus = 10 * 80 + 78 }
		for tick = 1, 30 do
			Expansion.advance(map, g, { nation(1, 0) }, attack, tick, 5)
		end
		local east, west = 0, 0
		for i = 0, g.size - 1 do
			if Grid.getOwner(g, i) == 1 then
				if i % 80 > 40 then
					east += 1
				elseif i % 80 < 40 then
					west += 1
				end
			end
		end
		T.expect(east > west * 2).toBe(true)
	end)

	T.it(
		"атака на державу: стоимость растёт с плотностью, защитник теряет людей и землю",
		function()
			local cheap = Expansion.cellCost(1, nation(2, 100), 100)
			local dense = Expansion.cellCost(1, nation(2, 1000), 100)
			T.expect(dense > cheap).toBe(true)
			T.expect(Expansion.cellCost(1, nil, 0)).toBe(Config.Expansion.NeutralCellCost)

			local map = TinyMap.plains(20, 6)
			local g = Grid.new(map)
			for x = 1, 18 do
				for y = 1, 4 do
					Grid.setOwner(g, y * 20 + x, if x <= 9 then 1 else 2)
				end
			end
			local nations = { nation(1, 0), nation(2, 200) }
			local attack: Types.Attack = { attacker = 1, target = 2, troops = 500 }
			for tick = 1, 10 do
				Expansion.advance(map, g, nations, attack, tick, 2)
			end
			T.expect(Grid.cellsOf(g, 1) > 36).toBe(true)
			T.expect(nations[2].people < 200).toBe(true)
			T.expect(attack.troops < 500).toBe(true)
		end
	)
end)

T.describe("Intents и RateLimiter", function()
	T.it(
		"клиенту не доверяем: типы, NaN, бесконечность, дроби, диапазоны",
		function()
			T.expect((Intents.parse("pick", { cell = 10 }))).toEqual({ kind = "pick", cell = 10 })
			T.expect((Intents.parse("pick", { cell = 1.5 }))).toBe(nil)
			T.expect((Intents.parse("pick", { cell = 0 / 0 }))).toBe(nil)
			T.expect((Intents.parse("pick", "10"))).toBe(nil)
			T.expect((Intents.parse(5, {}))).toBe(nil)
			T.expect((Intents.parse("nuke", {}))).toBe(nil)
			T.expect((Intents.parse("attack", { target = 2, percent = 0.3 })) ~= nil).toBe(true)
			T.expect((Intents.parse("attack", { target = 2, percent = 1.5 }))).toBe(nil)
			T.expect((Intents.parse("attack", { target = 2, percent = 0 }))).toBe(nil)
			T.expect((Intents.parse("attack", { target = 2, percent = math.huge }))).toBe(nil)
			T.expect((Intents.parse("attack", { target = -1, percent = 0.3 }))).toBe(nil)
			T.expect((Intents.parse("attack", { target = 2, percent = 0.3, focus = "x" }))).toBe(nil)
			T.expect((Intents.parse("cancel", { target = 0 }))).toEqual({ kind = "cancel", target = 0 })
		end
	)

	T.it(
		"лимит запросов: всплеск до ёмкости, потом по скорости пополнения",
		function()
			local rl = RateLimiter.new(5, 2, 0)
			for _ = 1, 5 do
				T.expect(RateLimiter.allow(rl, 0)).toBe(true)
			end
			T.expect(RateLimiter.allow(rl, 0)).toBe(false)
			T.expect(RateLimiter.allow(rl, 0.5)).toBe(true) -- +1 жетон за полсекунды
			T.expect(RateLimiter.allow(rl, 0.5)).toBe(false)
			T.expect(rl.dropped).toBe(2)
		end
	)
end)

T.describe("BotBrain", function()
	local rng = Rng.new(1)
	T.it(
		"копит, расширяется на ничью землю, бьёт слабого соседа",
		function()
			local base = { people = 100, maxPeople = 1000, attacks = 0, hasNeutral = true, neighbours = {} }
			T.expect(BotBrain.decide(base, rng)).toBe(nil) -- мало людей
			local rich = table.clone(base)
			rich.people = 900
			local i = BotBrain.decide(rich, rng)
			T.expect(i ~= nil and i.kind == "attack" and i.target == 0).toBe(true)
			local war = table.clone(rich)
			war.hasNeutral = false
			war.neighbours = { { id = 3, people = 2000 }, { id = 4, people = 300 } }
			local j = BotBrain.decide(war, rng)
			T.expect(j ~= nil and j.kind == "attack" and j.target == 4).toBe(true)
			war.neighbours = { { id = 3, people = 2000 } }
			T.expect(BotBrain.decide(war, rng)).toBe(nil) -- слишком сильный сосед
		end
	)
end)

T.describe("MatchSim", function()
	T.it(
		"выбор старта: свой выбор, проверки, автостарт, боты до TargetNations, цвета, круги",
		function()
			local m = MatchSim.new(Fixtures.pangea, 42)
			local a = MatchSim.addPlayer(m, 1, "Аня") :: number
			local b = MatchSim.addPlayer(m, 2, "Боря") :: number
			T.expect((MatchSim.applyIntent(m, a, { kind = "pick", cell = 1000 }))).toBe(false) -- ещё ожидание
			MatchSim.startPick(m)
			local cell = StartPositions.autoPick(m.grid, {}, Rng.new(1)) :: number
			T.expect((MatchSim.applyIntent(m, a, { kind = "pick", cell = cell }))).toBe(true)
			local ok, err = MatchSim.applyIntent(m, b, { kind = "pick", cell = cell + 2 })
			T.expect(ok).toBe(false)
			T.expect(err).toBe("TooClose")
			T.expect(select(2, MatchSim.applyIntent(m, b, { kind = "pick", cell = 0 }))).toBe("NotLand")
			local steps = 0
			while m.phase ~= "Play" do
				MatchSim.step(m, DT)
				steps += 1
			end
			T.expect(steps).toBe(Config.Match.StartPickSec * Config.Sim.TickRate)
			T.expect(#m.nations).toBe(Config.Match.TargetNations)
			T.expect(m.nations[a].capital).toBe(cell)
			local colors: { [number]: boolean } = {}
			for _, n in m.nations do
				T.expect(n.capital ~= nil).toBe(true)
				T.expect(colors[n.colorIndex]).toBe(nil)
				colors[n.colorIndex] = true
				T.expect(Grid.cellsOf(m.grid, n.id) > 20).toBe(true)
				T.expect(Grid.getOwner(m.grid, n.capital :: number)).toBe(n.id)
				T.expect(n.people).toBe(Config.People.Start)
				T.expect(n.isBot).toBe(n.id > 2)
			end
			T.expect((MatchSim.applyIntent(m, a, { kind = "pick", cell = cell }))).toBe(false) -- выбор закончен
		end
	)

	T.it("атака: проверки и отмена с возвратом людей", function()
		local m = startedMatch(7, 1)
		local me = m.nations[1]
		T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "attack", target = 1, percent = 0.3 }))).toBe("self")
		T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "attack", target = 99, percent = 0.3 }))).toBe("target")
		T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 0.3 })))
			.toBe("notAdjacent")
		local before = me.people
		T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 0, percent = 0.5 }))).toBe(true)
		T.expect(me.people).toBeNear(before * 0.5, 1e-6)
		T.expect(MatchSim.troopsOf(m, 1)).toBeNear(before * 0.5, 1e-6)
		-- Повторная атака на ту же цель — подкрепление, а не вторая атака.
		T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 0, percent = 0.5 }))).toBe(true)
		local count = 0
		for _, att in m.attacks do
			if att.attacker == 1 then
				count += 1
			end
		end
		T.expect(count).toBe(1)
		local total = me.people + MatchSim.troopsOf(m, 1)
		T.expect((MatchSim.applyIntent(m, 1, { kind = "cancel", target = 0 }))).toBe(true)
		T.expect(me.people).toBeNear(total, 1e-6)
		T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "cancel", target = 0 }))).toBe("noAttack")
	end)

	T.it("игрок растёт, боты расширяются сами", function()
		local m = startedMatch(11, 2)
		local start: { [number]: number } = {}
		for _, n in m.nations do
			start[n.id] = Grid.cellsOf(m.grid, n.id)
		end
		MatchSim.applyIntent(m, 1, { kind = "attack", target = 0, percent = 0.4 })
		for _ = 1, 60 * Config.Sim.TickRate do
			MatchSim.step(m, DT)
		end
		for _, n in m.nations do
			if n.isBot then
				T.expect(Grid.cellsOf(m.grid, n.id) > start[n.id] * 5).toBe(true)
			end
		end
		T.expect(Grid.cellsOf(m.grid, 1) > start[1]).toBe(true)
	end)

	T.it("один и тот же сид — одна и та же партия", function()
		local function run(): string
			local m = startedMatch(99, 0)
			for _ = 1, 30 * Config.Sim.TickRate do
				MatchSim.step(m, DT)
			end
			return buffer.tostring(m.grid.owner)
		end
		T.expect(run() == run()).toBe(true)
	end)

	T.it("держава без земли выбывает, её атаки снимаются", function()
		local map = TinyMap.plains(30, 6)
		local m = MatchSim.new(map, 1)
		MatchSim.addPlayer(m, 1, "A")
		MatchSim.addPlayer(m, 2, "B")
		m.phase = "Play"
		for x = 1, 28 do
			for y = 1, 4 do
				Grid.setOwner(m.grid, y * 30 + x, if x <= 25 then 1 else 2)
			end
		end
		m.nations[1].people = 100000
		m.nations[2].people = 10
		m.nations[1].colorIndex, m.nations[2].colorIndex = 1, 2
		m.nations[2].capital = 2 * 30 + 27
		m.nations[1].capital = 2 * 30 + 5
		MatchSim.applyIntent(m, 2, { kind = "attack", target = 1, percent = 0.9 })
		T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 0.5 }))).toBe(true)
		for _ = 1, 100 do
			MatchSim.step(m, DT)
		end
		T.expect(m.nations[2].alive).toBe(false)
		T.expect(Grid.cellsOf(m.grid, 2)).toBe(0)
		for _, att in m.attacks do
			T.expect(att.attacker ~= 2 and att.target ~= 2).toBe(true)
		end
		local events = MatchSim.takeEvents(m)
		local eliminated = false
		for _, e in events do
			if e.kind == "eliminated" and e.nation == 2 then
				eliminated = true
			end
		end
		T.expect(eliminated).toBe(true)
	end)

	T.it("ушедший игрок становится ботом и продолжает играть", function()
		local m = startedMatch(5, 2)
		MatchSim.removePlayer(m, 2)
		T.expect(m.nations[2].isBot).toBe(true)
		local before = Grid.cellsOf(m.grid, 2)
		for _ = 1, 30 * Config.Sim.TickRate do
			MatchSim.step(m, DT)
		end
		T.expect(Grid.cellsOf(m.grid, 2) > before).toBe(true)
	end)

	T.it("бюджет тика на «Пангее» с 6 державами (замер)", function()
		local m = startedMatch(3, 0)
		local worst, total, ticks = 0, 0, 0
		for _ = 1, 90 * Config.Sim.TickRate do
			local t0 = os.clock()
			MatchSim.step(m, DT)
			local ms = (os.clock() - t0) * 1000
			worst = math.max(worst, ms)
			total += ms
			ticks += 1
		end
		print(string.format("      тик: средний %.2f мс, худший %.2f мс", total / ticks, worst))
		T.expect(total / ticks < Config.Sim.ServerTickBudgetMs).toBe(true)
	end)
end)
