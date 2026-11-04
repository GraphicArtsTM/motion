--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local TinyMap = require("./lib/TinyMap")
local BotBrain = require("../src/shared/BotBrain")
local Config = require("../src/shared/Config")
local Expansion = require("../src/shared/Expansion")
local Forces = require("../src/shared/Forces")
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
		home = Forces.new(),
		queue = {},
		money = 0,
		oil = 0,
	}
end

-- Атака с пустыми войсками (для тестов захвата людьми).
local function attackOf(attacker: number, target: number, troops: number, focus: number?): Types.Attack
	return {
		attacker = attacker,
		target = target,
		troops = troops,
		focus = focus,
		forces = Forces.new(),
		supplied = true,
		ratio = math.huge,
		fighting = false,
		lastAdvance = 0,
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
			-- Коридор в одну клетку: окружённых кусков (они переходят бесплатно) здесь не бывает.
			local map = TinyMap.fromRows({ "~~~~~~~~~~~~~~", "~....^^^^^^^^~", "~~~~~~~~~~~~~~" })
			local g = Grid.new(map)
			local nations = { nation(1, 0), nation(2, 0) }
			Grid.setOwner(g, 1 * 14 + 1, 1)
			-- Третья сторона в конце коридора, иначе последняя клетка «окружится» и перейдёт без оплаты.
			Grid.setOwner(g, 1 * 14 + 12, 2)
			local attack: Types.Attack = attackOf(1, 0, 1000)
			local spent = 0
			for tick = 1, 400 do
				local before = attack.troops
				-- Без войны чужие куски не окружаются (§6.7а).
				local done = Expansion.advance(map, g, nations, attack, tick, 7, DT, {
					canTake = function(owner: number): boolean
						return owner == 0
					end,
				})
				spent += before - attack.troops
				if done then
					break
				end
			end
			-- Захвачены все 10 ничьих клеток: 3 равнины × 1.0 + 7 гор × 2.5 (конец коридора — у третьей державы).
			T.expect(Grid.cellsOf(g, 1)).toBe(11)
			local mountain = Config.Terrain[Types.Terrain.Mountains].captureCost
			T.expect(spent)
				.toBeNear(3 * Config.Expansion.NeutralCellCost + 7 * mountain * Config.Expansion.NeutralCellCost, 1e-9)
		end
	)

	T.it("река и вода — непреодолимая граница", function()
		local map = TinyMap.fromRows({ "~~~~~~~", "~..r..~", "~..r..~", "~..r..~", "~~~~~~~" })
		local g = Grid.new(map)
		Grid.setOwner(g, 1 * 7 + 1, 1)
		local attack: Types.Attack = attackOf(1, 0, 1000)
		for tick = 1, 50 do
			if Expansion.advance(map, g, { nation(1, 0) }, attack, tick, 1, DT) then
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
			local attack: Types.Attack = attackOf(1, 0, 1e9)
			-- В среднем за тик берётся доля FrontAdvancePerSec / TickRate клеток фронта (плюс щели и дыры).
			local expected, got = 0, 0
			for tick = 1, 50 do
				local front = Expansion.frontier(g, 1, 0)
				local before = Grid.cellsOf(g, 1)
				Expansion.advance(map, g, { nation(1, 0) }, attack, tick, 3, DT)
				expected += #front * Config.Expansion.FrontAdvancePerSec / Config.Sim.TickRate
				got += Grid.cellsOf(g, 1) - before
			end
			T.expect(got <= expected * 1.8).toBe(true)
			T.expect(got >= expected * 0.5).toBe(true)
			-- За 5 секунд радиус вырос примерно на FrontAdvancePerSec × 5 клеток (ромб/круг, с запасом).
			local r = Config.Expansion.FrontAdvancePerSec * 5
			T.expect(Grid.cellsOf(g, 1) <= (2 * r + 3) ^ 2).toBe(true)
			T.expect(Grid.cellsOf(g, 1) >= r * r).toBe(true)
		end
	)

	T.it("точка focus ускоряет свою сторону, но идёт вся граница", function()
		local map = TinyMap.plains(80, 20)
		local g = Grid.new(map)
		for y = 8, 11 do
			Grid.setOwner(g, y * 80 + 40, 1)
		end
		local attack: Types.Attack = attackOf(1, 0, 1e9, 10 * 80 + 78)
		for tick = 1, 30 do
			Expansion.advance(map, g, { nation(1, 0) }, attack, tick, 5, DT)
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
		T.expect(east > west * 1.3).toBe(true)
		T.expect(west > 0).toBe(true) -- дальняя от клика сторона тоже растёт
	end)

	T.it("клетка ничьей земли стоит людей по местности", function()
		T.expect(Expansion.cellCost(1)).toBe(Config.Expansion.NeutralCellCost)
		T.expect(Expansion.cellCost(2.5)).toBe(2.5 * Config.Expansion.NeutralCellCost)
	end)
end)

T.describe("Expansion: без дыр", function()
	-- Карта 12×7: атакующий 1 вокруг куска ничьей земли / державы 2.
	local function ring(): (any, any)
		local map = TinyMap.plains(12, 7)
		local g = Grid.new(map)
		for y = 1, 5 do
			for x = 1, 10 do
				Grid.setOwner(g, y * 12 + x, 1)
			end
		end
		return map, g
	end

	T.it(
		"окружённый кусок ничьей земли переходит к окружившему",
		function()
			local _, g = ring()
			for _, i in { 3 * 12 + 5, 3 * 12 + 6, 2 * 12 + 6 } do
				Grid.setOwner(g, i, 0)
			end
			local got = Expansion.captureEnclaves(g, { nation(1, 0) }, 1, { 3 * 12 + 4 }, 1)
			T.expect(got).toBe(3)
			T.expect(Grid.getOwner(g, 3 * 12 + 6)).toBe(1)
		end
	)

	T.it(
		"окружённый кусок державы переходит, защитник теряет людей",
		function()
			local _, g = ring()
			for _, i in { 3 * 12 + 5, 3 * 12 + 6 } do
				Grid.setOwner(g, i, 2)
			end
			local nations = { nation(1, 0), nation(2, 100) }
			nations[2].capital = 1 * 12 + 1 -- столица далеко (и не в этом куске)
			T.expect(Expansion.captureEnclaves(g, nations, 1, { 3 * 12 + 4 }, 1)).toBe(2)
			T.expect(nations[2].people < 100).toBe(true)
		end
	)

	T.it(
		"кусок со столицей и кусок у третьей державы не окружаются",
		function()
			local _, g = ring()
			Grid.setOwner(g, 3 * 12 + 5, 2)
			local nations = { nation(1, 0), nation(2, 100), nation(3, 100) }
			nations[2].capital = 3 * 12 + 5
			T.expect(Expansion.captureEnclaves(g, nations, 1, { 3 * 12 + 4 }, 1)).toBe(0)
			Grid.setOwner(g, 3 * 12 + 7, 2)
			Grid.setOwner(g, 3 * 12 + 8, 3) -- сосед — третья держава
			T.expect(Expansion.captureEnclaves(g, nations, 1, { 3 * 12 + 6 }, 100)).toBe(0)
		end
	)

	T.it(
		"щель в одну клетку закрывается первой, даже если фокус в другой стороне",
		function()
			local map = TinyMap.plains(30, 9)
			local g = Grid.new(map)
			for y = 1, 7 do
				for x = 1, 10 do
					if not (x == 10 and y == 4) then
						Grid.setOwner(g, y * 30 + x, 1)
					end
				end
			end
			-- (10, 4) — «зуб» в границе: три соседа наши. Фокус далеко справа.
			local attack: Types.Attack = attackOf(1, 0, 1e9, 4 * 30 + 28)
			Expansion.advance(map, g, { nation(1, 0) }, attack, 1, 1, DT)
			T.expect(Grid.getOwner(g, 4 * 30 + 10)).toBe(1)
		end
	)

	T.it(
		"долгая атака с фокусом не оставляет дыр внутри территории",
		function()
			local m = startedMatch(31, 1)
			local me = m.nations[1]
			local far = (m.grid.height // 2) * m.grid.width + m.grid.width // 2
			for _ = 1, 40 do
				MatchSim.applyIntent(m, 1, { kind = "attack", target = 0, percent = 0.5, focus = far })
				for _ = 1, 10 do
					MatchSim.step(m, DT)
				end
			end
			-- Ничья захватываемая клетка, у которой все 4 соседа наши (или вода), — это дыра.
			-- Ничейный город — не дыра: его берут только войска (§6.5).
			local holes = 0
			for i in Grid.borderCells(m.grid, me.id) do
				Grid.forNeighbours(m.grid, i, function(j)
					if
						Grid.getOwner(m.grid, j) == 0
						and Grid.isCapturable(m.grid, j)
						and not Grid.isCity(m.grid, j)
					then
						local mine = 0
						Grid.forNeighbours(m.grid, j, function(k)
							if Grid.getOwner(m.grid, k) == me.id or not Grid.isCapturable(m.grid, k) then
								mine += 1
							end
						end)
						if mine == 4 then
							holes += 1
						end
					end
				end)
			end
			T.expect(holes).toBe(0)
		end
	)
end)

T.describe("Match.Speed", function()
	T.it(
		"множитель скорости ускоряет игровое время, а часы матча — нет",
		function()
			T.expect(Config.Match.Speed > 0).toBe(true)
			local slow = startedMatch(8, 0)
			local fast = startedMatch(8, 0)
			fast.speed = 2
			for _ = 1, 10 * Config.Sim.TickRate do
				MatchSim.step(slow, DT)
				MatchSim.step(fast, DT)
			end
			T.expect(fast.time).toBeNear(slow.time, 1e-9)
			T.expect(fast.simTime).toBeNear(slow.simTime * 2, 1e-6)
			local cellsSlow, cellsFast = 0, 0
			for _, n in slow.nations do
				cellsSlow += Grid.cellsOf(slow.grid, n.id)
				cellsFast += Grid.cellsOf(fast.grid, n.id)
			end
			T.expect(cellsFast > cellsSlow).toBe(true)
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
	-- Обычный бот без ошибок (пропуск хода по Config.BotLevels.Normal.mistake мешал бы проверкам).
	local normal = BotBrain.profile("Normal", "Admiral")
	normal.level = table.clone(normal.level)
	normal.level.mistake = 0
	local function view(): BotBrain.BotView
		return {
			people = 100,
			maxPeople = 1000,
			attacks = 0,
			queue = Config.Forces.MaxQueue, -- очередь полна — найм не мешает проверять атаки
			power = 0,
			hasCapital = true,
			hasNeutral = true,
			neighbours = {},
			totalPower = 0,
			wars = {},
			money = 1e6,
			oil = 1e4,
			economy = { income = 1000, oilIncome = 0, upkeep = 0 },
			owned = { factories = 1, markets = 2, rigs = 3, forts = 0, cityLevels = 1 },
			spots = {},
		}
	end
	local function neighbour(id: number, power: number, atWar: boolean?): BotBrain.Neighbour
		return { id = id, people = 1, power = power, atWar = atWar == true, canDeclare = atWar ~= true }
	end

	T.it("копит, расширяется на ничью землю, нанимает войска", function()
		T.expect(BotBrain.decide(view(), rng, normal)).toBe(nil) -- мало людей
		local rich = view()
		rich.people = 900
		local i = BotBrain.decide(rich, rng, normal)
		T.expect(i ~= nil and i.kind == "attack" and i.target == 0).toBe(true)
		local hiring = view()
		hiring.people = 900
		hiring.queue = 0
		local hired = false
		for _ = 1, 50 do
			local h = BotBrain.decide(hiring, rng, normal)
			if h ~= nil and h.kind == "hire" then
				hired = true
			end
		end
		T.expect(hired).toBe(true)
	end)

	T.it(
		"без ничьей земли объявляет войну слабому соседу, сильного не трогает, в войне открывает фронт",
		function()
			local war = view()
			war.people = 900
			war.hasNeutral = false
			war.power = 2000
			war.neighbours = { neighbour(3, 5000), neighbour(4, 300) }
			local j = BotBrain.decide(war, rng, normal)
			T.expect(j ~= nil and j.kind == "declare" and j.target == 4).toBe(true)
			war.neighbours = { neighbour(3, 5000) }
			T.expect(BotBrain.decide(war, rng, normal)).toBe(nil)
			-- Война с 4 идёт — фронт против него.
			war.neighbours = { neighbour(3, 5000), neighbour(4, 300, true) }
			local k = BotBrain.decide(war, rng, normal)
			T.expect(k ~= nil and k.kind == "attack" and k.target == 4).toBe(true)
			war.power = 0 -- без войск ни войны, ни фронта
			war.neighbours = { neighbour(4, 0) }
			T.expect(BotBrain.decide(war, rng, normal)).toBe(nil)
		end
	)

	T.it(
		"долгая проигранная война — просит мира; на мир соглашается, если слабее",
		function()
			local v = view()
			-- Слабее врага (меньше 0.6 его силы), но не безнадёжно.
			v.people, v.hasNeutral, v.power, v.totalPower = 900, false, 0, 1500
			v.neighbours = { neighbour(4, 3000, true) }
			v.wars = {
				{
					enemy = 4,
					active = true,
					age = Config.BotLevels.Normal.peaceAfterSec + 1,
					myGain = 0,
					theirGain = 50,
					theirPower = 3000,
					canPropose = true,
					proposedBefore = false,
				},
			}
			local p = BotBrain.decide(v, rng, normal)
			T.expect(p ~= nil and p.kind == "peace" and p.target == 4 and p.terms == "white").toBe(true)
			-- Белый мир не приняли — второй раз готов отдать захваченное.
			v.wars[1].proposedBefore = true
			local again = BotBrain.decide(v, rng, normal)
			T.expect(again ~= nil and again.kind == "peace" and again.terms == "keep").toBe(true)
			-- Совсем слабый — сразу готов отдать захваченное.
			v.wars[1].proposedBefore = false
			v.totalPower = 100
			local desperate = BotBrain.decide(v, rng, normal)
			T.expect(desperate ~= nil and desperate.kind == "peace" and desperate.terms == "keep").toBe(true)
			local offer =
				{ terms = "white" :: Types.PeaceTerms, myGain = 0, theirGain = 50, myPower = 100, theirPower = 3000 }
			T.expect(BotBrain.answerPeace(offer)).toBe(true)
			-- Сильный и сам взял больше — белый мир (вернуть взятое) не нужен.
			local strong =
				{ terms = "white" :: Types.PeaceTerms, myGain = 50, theirGain = 0, myPower = 3000, theirPower = 100 }
			T.expect(BotBrain.answerPeace(strong)).toBe(false)
			strong.terms = "keep"
			T.expect(BotBrain.answerPeace(strong)).toBe(true)
			strong.terms = "capitulate" -- вассал платит дань (§8.1) — бот принимает
			T.expect(BotBrain.answerPeace(strong)).toBe(true)
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
		-- Без войны страну атаковать нельзя (§6.7а).
		T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 0.3 }))).toBe("notAtWar")
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

	T.it(
		"держава выбывает, когда пал последний город: земля ничья, событие в ленте",
		function()
			local m = startedMatch(17, 0)
			local victim = m.nations[2]
			local cities: { number } = {}
			for _, cell in m.cityOf do
				if Grid.getOwner(m.grid, cell) == victim.id then
					table.insert(cities, cell)
				end
			end
			T.expect(#cities >= 1).toBe(true)
			local cellsBefore = Grid.cellsOf(m.grid, victim.id)
			-- Отдаём все города жертвы соседу 1 — как будто их взял фронт.
			for _, cell in cities do
				Grid.setOwner(m.grid, cell, 1)
			end
			MatchSim.step(m, DT)
			T.expect(victim.alive).toBe(false)
			T.expect(cellsBefore > 1).toBe(true)
			T.expect(Grid.cellsOf(m.grid, victim.id)).toBe(0)
			local events = MatchSim.takeEvents(m)
			local found = false
			for _, e in events do
				if e.kind == "eliminated" and e.nation == victim.id and e.by == 1 then
					found = true
				end
			end
			T.expect(found).toBe(true)
			for _, att in m.attacks do
				T.expect(att.attacker ~= victim.id and att.target ~= victim.id).toBe(true)
			end
		end
	)

	T.it(
		"пока остался хоть один город — держава жива, столица переезжает",
		function()
			local m = startedMatch(19, 0)
			local victim = m.nations[3]
			-- Даём жертве второй город рядом со столицей (её же клетка).
			local capital = victim.capital :: number
			local spare: number? = nil
			for i in Grid.borderCells(m.grid, victim.id) do
				if i ~= capital and not Grid.isCity(m.grid, i) then
					spare = i
					break
				end
			end
			local extra = spare :: number
			Grid.setCity(m.grid, extra, true)
			m.cityOf[-1] = extra -- искусственный город вне провинций
			Grid.setOwner(m.grid, capital, 1)
			MatchSim.step(m, DT)
			T.expect(victim.alive).toBe(true)
			T.expect(victim.capital).toBe(extra)
		end
	)

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
