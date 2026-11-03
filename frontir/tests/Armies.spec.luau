--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local TinyMap = require("./lib/TinyMap")
local Armies = require("../src/shared/Armies")
local Config = require("../src/shared/Config")
local Expansion = require("../src/shared/Expansion")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MapGen = require("../src/shared/MapGen")
local MatchSim = require("../src/shared/MatchSim")
local Pathfind = require("../src/shared/Pathfind")
local Rng = require("../src/shared/Rng")
local Types = require("../src/shared/Types")

local DT = 1 / Config.Sim.TickRate

-- Маленькая карта с провинциями (параметры «Пангеи», но провинции мелкие).
local function provincedMap(rows: { string }, target: number): MapData.MapData
	local map = TinyMap.fromRows(rows)
	local params = table.clone(Config.MapGen.Pangea)
	params.ProvinceTargetCells = target
	params.ProvinceMinCells = math.max(4, target // 4)
	MapGen.generateProvinces(map, params, Rng.new(1))
	return map
end

local function plainsRows(w: number, h: number): { string }
	local rows: { string } = {}
	for y = 1, h do
		table.insert(rows, if y == 1 or y == h then string.rep("~", w) else "~" .. string.rep(".", w - 2) .. "~")
	end
	return rows
end

-- Матч на маленькой карте сразу в фазе игры. У каждой державы — одна клетка в нижнем правом углу
-- (через две друг от друга), чтобы держава не «выбыла» в первом же тике.
local function tinyMatch(map: MapData.MapData, nations: number): MatchSim.Match
	local m = MatchSim.new(map, 1)
	for k = 1, nations do
		MatchSim.addPlayer(m, k, "N" .. k)
	end
	m.phase = "Play"
	for _, n in m.nations do
		n.colorIndex = n.id
		n.people = 100000
		Grid.setOwner(m.grid, (map.height - 2) * map.width + map.width - 2 - 3 * (n.id - 1), n.id)
	end
	return m
end

local function runFor(m: MatchSim.Match, seconds: number)
	for _ = 1, math.floor(seconds * Config.Sim.TickRate) do
		MatchSim.step(m, DT)
	end
end

T.describe("Pathfind", function()
	T.it("обходит озеро и не ходит по воде", function()
		local map = TinyMap.fromRows({
			"~~~~~~~~~",
			"~.......~",
			"~..~~~..~",
			"~..~~~..~",
			"~.......~",
			"~~~~~~~~~",
		})
		local w = map.width
		local path = Pathfind.find(map, 2 * w + 1, 3 * w + 7) :: { number }
		T.expect(path ~= nil).toBe(true)
		for _, c in path do
			T.expect(Pathfind.passable(map, c)).toBe(true)
		end
		T.expect(path[#path]).toBe(3 * w + 7)
		T.expect(Pathfind.find(map, 2 * w + 1, 2 * w + 4)).toBe(nil) -- в воду нельзя
	end)

	T.it("на остров пешком не дойти", function()
		local map = TinyMap.fromRows({ "~~~~~~~", "~..~..~", "~~~~~~~" })
		T.expect(Pathfind.find(map, 8, 11)).toBe(nil)
	end)

	T.it("по диагонали не срезает угол через воду", function()
		local map = TinyMap.fromRows({ "~~~~", "~.~~", "~~.~", "~~~~" })
		T.expect(Pathfind.find(map, 5, 10)).toBe(nil)
	end)

	T.it("обходит горы, если обход недлинный", function()
		-- Напрямую: 3 равнины + 2 горы по 1/0.45 ≈ 7.4; обход поверху ≈ 6.7.
		local map = TinyMap.fromRows({
			"~~~~~~~~~~",
			"~........~",
			"~...^^...~",
			"~...^^...~",
			"~~~~~~~~~~",
		})
		local w = map.width
		local path = Pathfind.find(map, 3 * w + 2, 3 * w + 7) :: { number }
		for _, c in path do
			T.expect(MapData.getTerrain(map, c) ~= Types.Terrain.Mountains).toBe(true)
		end
	end)
end)

T.describe("Armies: движение и захват", function()
	T.it(
		"скорость: клеток в секунду = Units.speed × ширина / 512 × местность",
		function()
			local map = provincedMap(plainsRows(60, 8), 400)
			local m = tinyMatch(map, 1)
			local a = Armies.new(1, 1, "Infantry", 4 * 60 + 2, map.width)
			a.state = "idle"
			table.insert(m.armies, a)
			Armies.setPath(a, Pathfind.find(map, a.cell, 4 * 60 + 57) :: { number })
			local x0 = a.x
			runFor(m, 2)
			local expected = Armies.baseSpeed(map, "Infantry") * 2
			T.expect(a.x - x0).toBeNear(expected, 0.05)
			-- Match.Speed ускоряет и армии.
			local m2 = tinyMatch(map, 1)
			m2.speed = 2
			local b = Armies.new(1, 1, "Infantry", 4 * 60 + 2, map.width)
			b.state = "idle"
			table.insert(m2.armies, b)
			Armies.setPath(b, Pathfind.find(map, b.cell, 4 * 60 + 57) :: { number })
			runFor(m2, 2)
			T.expect(b.x - x0).toBeNear(expected * 2, 0.1)
		end
	)

	T.it(
		"армия заливает провинцию волной от себя и заканчивает захват",
		function()
			local map = provincedMap(plainsRows(30, 14), 600) -- одна провинция на всю сушу
			local m = tinyMatch(map, 1)
			local start = 7 * 30 + 15
			local a = Armies.new(1, 1, "Infantry", start, map.width)
			a.state = "idle"
			table.insert(m.armies, a)
			MatchSim.step(m, DT)
			T.expect(a.state).toBe("capture")
			-- Волна круглая: обычное расстояние до армии в очереди не убывает.
			local w = map.width
			local prev = 0
			for _, c in a.captureQueue do
				local d = (c % w + 0.5 - a.x) ^ 2 + (c // w + 0.5 - a.y) ^ 2
				T.expect(d >= prev).toBe(true)
				prev = d
			end
			local total = a.captureTotal
			runFor(m, total / Config.Units.Infantry.captureRate + 1)
			T.expect(a.state).toBe("idle")
			T.expect(Grid.cellsOf(m.grid, 1)).toBe(m.grid.capturableCount)
		end
	)

	T.it("чужой город в провинции замедляет захват", function()
		local map = provincedMap(plainsRows(30, 14), 600)
		local function captureTime(withCity: boolean): number
			local m = tinyMatch(map, 1)
			local province = MapData.getProvince(map, 7 * 30 + 15)
			if withCity then
				m.cityOf[province] = 3 * 30 + 3
				Grid.setCity(m.grid, 3 * 30 + 3, true)
			else
				m.cityOf[province] = nil
			end
			local a = Armies.new(1, 1, "Infantry", 7 * 30 + 15, map.width)
			a.state = "idle"
			table.insert(m.armies, a)
			local ticks = 0
			repeat
				MatchSim.step(m, DT)
				ticks += 1
			until (a.state == "idle" and ticks > 2) or ticks > 10000
			return ticks
		end
		local fast, slow = captureTime(false), captureTime(true)
		-- Пока город не взят, захват идёт в 1/CityCaptureSlowdown раз медленнее; после — с обычной скоростью.
		T.expect(slow > fast * 1.6 and slow <= fast / Config.Armies.CityCaptureSlowdown + 2).toBe(true)
	end)

	T.it("город не берёт ползущая граница, а армия — берёт", function()
		local map = provincedMap(plainsRows(20, 8), 400)
		local m = tinyMatch(map, 2)
		local city = 4 * 20 + 10
		Grid.setCity(m.grid, city, true)
		m.cityOf[MapData.getProvince(map, city)] = city
		Grid.setOwner(m.grid, city, 2)
		Grid.setOwner(m.grid, 4 * 20 + 9, 1)
		-- Держава 2 — только город: ползущая граница его не возьмёт.
		T.expect(Expansion.hasFrontier(m.grid, 1, 2)).toBe(false)
		-- Окружённый кусок с городом не переходит.
		T.expect(Expansion.captureEnclaves(m.grid, m.nations, 1, { 4 * 20 + 9 }, 1)).toBe(0)
		local a = Armies.new(1, 1, "Infantry", 4 * 20 + 9, map.width)
		a.state = "idle"
		table.insert(m.armies, a)
		runFor(m, 30)
		T.expect(Grid.getOwner(m.grid, city)).toBe(1)
	end)

	T.it(
		"армия взяла столицу: столица переезжает в ближайший свой город, событие",
		function()
			local map = provincedMap(plainsRows(40, 10), 60)
			local m = tinyMatch(map, 2)
			local capital = 5 * 40 + 30
			local spare = 5 * 40 + 3 -- в другой провинции, далеко от армии
			for _, c in { capital, spare } do
				Grid.setCity(m.grid, c, true)
				m.cityOf[MapData.getProvince(map, c)] = c
				Grid.setOwner(m.grid, c, 2)
			end
			m.nations[2].capital = capital
			local a = Armies.new(1, 1, "Tanks", capital, map.width) -- стоит прямо в провинции столицы
			a.state = "idle"
			table.insert(m.armies, a)
			runFor(m, 20)
			T.expect(Grid.getOwner(m.grid, capital)).toBe(1)
			T.expect(m.nations[2].capital).toBe(spare)
			local found = false
			for _, e in MatchSim.takeEvents(m) do
				if e.kind == "capitalLost" and e.nation == 2 and e.by == 1 then
					found = true
				end
			end
			T.expect(found).toBe(true)
		end
	)
end)

T.describe("Армии в матче: намерения", function()
	T.it(
		"найм: стоит людей, время найма, появляется в столице, предел армий",
		function()
			local map = provincedMap(plainsRows(40, 10), 60)
			local m = tinyMatch(map, 1)
			local me = m.nations[1]
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Infantry" }))).toBe("noCapital")
			local capital = 5 * 40 + 5
			me.capital = capital
			Grid.setOwner(m.grid, capital, 1)
			local before = me.people
			T.expect((MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Tanks" }))).toBe(true)
			T.expect(me.people).toBe(before - Config.Units.Tanks.people)
			local a = m.armies[1]
			T.expect(a.state).toBe("recruit")
			T.expect(a.cell).toBe(capital)
			runFor(m, Config.Units.Tanks.recruitSec + 0.2)
			T.expect(a.state ~= "recruit").toBe(true)
			for _ = 2, Config.Armies.MaxPerNation do
				MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Infantry" })
			end
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Infantry" }))).toBe("tooManyArmies")
			me.people = 1
			m.armies = {}
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Infantry" }))).toBe("noTroops")
		end
	)

	T.it(
		"приказы: идти (и захватить на месте), стоп, чужие армии не слушаются",
		function()
			local map = provincedMap(plainsRows(40, 10), 60)
			local m = tinyMatch(map, 2)
			local a = Armies.new(1, 1, "Infantry", 5 * 40 + 3, map.width)
			a.state = "idle"
			table.insert(m.armies, a)
			local target = 5 * 40 + 30
			T.expect(select(2, MatchSim.applyIntent(m, 2, { kind = "move", armies = { 1 }, cell = target })))
				.toBe("noArmy")
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "move", armies = { 1 }, cell = 0 }))).toBe("noPath")
			T.expect((MatchSim.applyIntent(m, 1, { kind = "move", armies = { 1 }, cell = target }))).toBe(true)
			T.expect(a.state).toBe("move")
			-- На карте шириной 40 пехота идёт 2.4 × 40/512 ≈ 0.19 клетки/с (GDD §7: скорость масштабируется).
			runFor(m, 27 / Armies.baseSpeed(map, "Infantry") + 20)
			T.expect(a.cell).toBe(target)
			-- Пришла — захватила провинцию, в которой стоит.
			local province = MapData.getProvince(map, target)
			for _, c in m.provinces.list[province].cells do
				if Grid.isCapturable(m.grid, c) then
					T.expect(Grid.getOwner(m.grid, c)).toBe(1)
				end
			end
			T.expect((MatchSim.applyIntent(m, 1, { kind = "move", armies = { 1 }, cell = 5 * 40 + 2 }))).toBe(true)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "stop", armies = { 1 } }))).toBe(true)
			T.expect(a.state ~= "move").toBe(true)
		end
	)

	T.it("«авто» сама берёт соседние провинции одну за другой", function()
		local map = provincedMap(plainsRows(60, 14), 60)
		local m = tinyMatch(map, 1)
		local a = Armies.new(1, 1, "Tanks", 7 * 60 + 30, map.width)
		a.state = "idle"
		table.insert(m.armies, a)
		T.expect((MatchSim.applyIntent(m, 1, { kind = "auto", armies = { 1 }, on = true }))).toBe(true)
		runFor(m, 120)
		local owned: { [number]: boolean } = {}
		for _, p in m.provinces.list do
			local all = true
			for _, c in p.cells do
				if Grid.isCapturable(m.grid, c) and Grid.getOwner(m.grid, c) ~= 1 then
					all = false
				end
			end
			if all then
				owned[p.id] = true
			end
		end
		local count = 0
		for _ in owned do
			count += 1
		end
		T.expect(count >= 4).toBe(true)
	end)

	T.it("разбор намерений армий", function()
		T.expect((Intents.parse("hire", { unit = "Tanks" }))).toEqual({ kind = "hire", unit = "Tanks" })
		T.expect((Intents.parse("hire", { unit = "Bomber" }))).toBe(nil) -- авиация — этап 7
		T.expect((Intents.parse("move", { armies = { 1, 2 }, cell = 5 }))).toEqual({
			kind = "move",
			armies = { 1, 2 },
			cell = 5,
		})
		T.expect((Intents.parse("move", { armies = {}, cell = 5 }))).toBe(nil)
		T.expect((Intents.parse("move", { armies = { 1.5 }, cell = 5 }))).toBe(nil)
		T.expect((Intents.parse("move", { armies = { x = 1 }, cell = 5 }))).toBe(nil)
		local many = {}
		for k = 1, Config.Armies.MaxOrderArmies + 1 do
			many[k] = k
		end
		T.expect((Intents.parse("stop", { armies = many }))).toBe(nil)
		T.expect((Intents.parse("auto", { armies = { 1 }, on = "yes" }))).toBe(nil)
		T.expect((Intents.parse("auto", { armies = { 1 }, on = true })) ~= nil).toBe(true)
	end)
end)

T.describe("Армии на «Пангее»", function()
	T.it(
		"боты нанимают армии, армии в «авто» берут города; одинаковый сид — одна партия",
		function()
			local function run(): (MatchSim.Match, string)
				local m = MatchSim.new(Fixtures.pangea, 77)
				MatchSim.startPick(m)
				while m.phase ~= "Play" do
					MatchSim.step(m, DT)
				end
				runFor(m, 150)
				return m, buffer.tostring(m.grid.owner)
			end
			local m, a = run()
			local _, b = run()
			T.expect(a == b).toBe(true)
			T.expect(#m.armies > 0).toBe(true)
			local ownedCities = 0
			for _, cell in m.cityOf do
				local owner = Grid.getOwner(m.grid, cell)
				if owner ~= 0 and m.nations[owner].capital ~= cell then
					ownedCities += 1
				end
			end
			T.expect(ownedCities > 0).toBe(true)
			-- Сразу после старта все города, кроме столиц, ничьи: круг старта города не захватывает.
			local fresh = MatchSim.new(Fixtures.pangea, 77)
			MatchSim.startPick(fresh)
			while fresh.phase ~= "Play" do
				MatchSim.step(fresh, DT)
			end
			for _, cell in fresh.cityOf do
				local owner = Grid.getOwner(fresh.grid, cell)
				if owner ~= 0 then
					T.expect(fresh.nations[owner].capital).toBe(cell)
				end
			end
			-- Столица каждой живой державы — её город.
			for _, n in m.nations do
				if n.alive and n.capital ~= nil then
					T.expect(Grid.isCity(m.grid, n.capital)).toBe(true)
					T.expect(Grid.getOwner(m.grid, n.capital)).toBe(n.id)
				end
			end
		end
	)
end)
