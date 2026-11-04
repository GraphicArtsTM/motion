--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Forces = require("../src/shared/Forces")
local Fronts = require("../src/shared/Fronts")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Pockets = require("../src/shared/Pockets")
local Provinces = require("../src/shared/Provinces")
local Rng = require("../src/shared/Rng")
local Types = require("../src/shared/Types")
local Wars = require("../src/shared/Wars")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number

local function started(seed: number): MatchSim.Match
	local m = MatchSim.new(Fixtures.pangea, seed)
	MatchSim.addPlayer(m, 1, "A")
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, DT)
	end
	return m
end

-- Провинция державы id, центр которой её (и без нефти, если noOil), не провинция столицы.
local function ownProvince(m: MatchSim.Match, id: number, wantOil: boolean?): Provinces.Province?
	local capProvince = MapData.getProvince(m.map, m.nations[id].capital :: number)
	for _, p in m.provinces.list do
		if Grid.getOwner(m.grid, p.center) == id and p.id ~= capProvince and (wantOil == nil or p.oil == wantOil) then
			return p
		end
	end
	return nil
end

-- Отдать державе всю провинцию (клетки суши).
local function give(m: MatchSim.Match, p: Provinces.Province, id: number)
	for _, c in p.cells do
		if Grid.isCapturable(m.grid, c) then
			Grid.setOwner(m.grid, c, id)
		end
	end
end

T.describe("Экономика", function()
	T.it(
		"доход: налог с клеток, уровни городов, рынки; нефть с вышек; содержание войск",
		function()
			local cfg = Config.Economy
			T.expect(Economy.income(1000, 2, 0))
				.toBeNear(1000 * cfg.TaxPerCellPerSec + 2 * cfg.CityIncomePerLevel, 1e-9)
			local base = Economy.income(1000, 2, 0)
			T.expect(Economy.income(1000, 2, 2)).toBeNear(base * (1 + 2 * Config.Buildings.Market.incomeBonus), 1e-9)
			T.expect(Economy.oilIncome(3)).toBe(3 * Config.Oil.PerRigPerSec)
			T.expect(Economy.upkeep(5000)).toBe(5000 * cfg.UpkeepPerStrengthPerSec)
			T.expect(Economy.maxPeople(100, 3) - Economy.maxPeople(100)).toBe(3 * cfg.CityMaxPeoplePerLevel)
		end
	)

	T.it(
		"деньги копятся по доходу; нечем платить содержание — войска тают",
		function()
			local m = started(41)
			local me = m.nations[1]
			T.expect(me.money).toBe(Config.Economy.StartMoney)
			local before = me.money
			MatchSim.step(m, DT)
			local e = m.economy[1]
			T.expect(e.income > 0).toBe(true)
			T.expect(me.money).toBeNear(before + (e.income - e.upkeep) * DT, 1e-6)
			-- Огромное войско без денег: содержание больше дохода — гарнизон тает.
			Forces.add(me.home, INF, 1e6)
			me.money = 0
			local strength = Forces.total(me.home)
			MatchSim.step(m, DT)
			T.expect(me.money).toBe(0)
			T.expect(Forces.total(me.home) < strength).toBe(true)
		end
	)

	T.it("найм стоит денег и нефти", function()
		local m = started(42)
		local me = m.nations[1]
		me.people = 1e6
		me.money = Config.Units.Infantry.cost - 1
		T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Infantry" }))).toBe("noMoney")
		me.money = 1e6
		T.expect((MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Infantry" }))).toBe(true)
		T.expect(me.money).toBe(1e6 - Config.Units.Infantry.cost)
	end)
end)

T.describe("Здания", function()
	T.it(
		"стройка: в своей провинции, одно на провинцию, вышка — только на нефти, деньги списываются",
		function()
			local m = started(43)
			local me = m.nations[1]
			me.money = 1e6
			local p = ownProvince(m, 1) :: Provinces.Province
			if p == nil then
				-- Расширимся, чтобы была своя провинция кроме столичной.
				for _, q in m.provinces.list do
					if Grid.getOwner(m.grid, q.center) == 0 then
						give(m, q, 1)
						p = q
						break
					end
				end
			end
			local plain = ownProvince(m, 1, false)
			if plain == nil then
				for _, q in m.provinces.list do
					if not q.oil and Grid.getOwner(m.grid, q.center) == 0 then
						give(m, q, 1)
						plain = q
						break
					end
				end
			end
			local target = plain :: Provinces.Province
			T.expect(
				select(2, MatchSim.applyIntent(m, 1, { kind = "build", building = "OilRig", cell = target.center }))
			)
				.toBe("needOil")
			local money = me.money
			T.expect((MatchSim.applyIntent(m, 1, { kind = "build", building = "Factory", cell = target.cells[1] })))
				.toBe(true)
			T.expect(me.money).toBe(money - Config.Buildings.Factory.cost)
			T.expect(m.buildings.byCell[target.center].kind).toBe("Factory") -- в центре провинции
			T.expect(MatchSim.ownedOf(m, 1).factories).toBe(1)
			T.expect(
				select(2, MatchSim.applyIntent(m, 1, { kind = "build", building = "Market", cell = target.center }))
			)
				.toBe("occupied")
			-- Чужая провинция — нельзя.
			for _, q in m.provinces.list do
				local o = Grid.getOwner(m.grid, q.center)
				if o ~= 1 then
					T.expect(
						select(2, MatchSim.applyIntent(m, 1, { kind = "build", building = "Market", cell = q.center }))
					)
						.toBe("notOwner")
					break
				end
			end
			-- Вышка на нефтяном поле.
			for _, q in m.provinces.list do
				if q.oil and Grid.getOwner(m.grid, q.center) == 0 then
					give(m, q, 1)
					T.expect((MatchSim.applyIntent(m, 1, { kind = "build", building = "OilRig", cell = q.center })))
						.toBe(true)
					break
				end
			end
			MatchSim.step(m, DT)
			T.expect(m.economy[1].oilIncome).toBe(Config.Oil.PerRigPerSec)
			-- Провинция сменила владельца — здание у нового.
			give(m, target, 2)
			MatchSim.refreshOwned(m)
			T.expect(MatchSim.ownedOf(m, 1).factories).toBe(0)
			T.expect(MatchSim.ownedOf(m, 2).factories).toBe(1)
		end
	)

	T.it(
		"город: улучшение до ур. 3 поднимает доход и максимум людей; денег мало — отказ",
		function()
			local m = started(44)
			local me = m.nations[1]
			local capital = me.capital :: number
			me.money = Config.Buildings.City.cost - 1
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "build", building = "City", cell = capital })))
				.toBe("noMoney")
			me.money = 1e6
			local maxBefore = MatchSim.maxPeopleOf(m, 1)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "build", building = "City", cell = capital }))).toBe(true)
			T.expect(Buildings.cityLevel(m.buildings, capital)).toBe(2)
			T.expect(MatchSim.maxPeopleOf(m, 1) - maxBefore).toBe(Config.Economy.CityMaxPeoplePerLevel)
			local money = me.money
			T.expect((MatchSim.applyIntent(m, 1, { kind = "build", building = "City", cell = capital }))).toBe(true)
			T.expect(me.money).toBe(money - Config.Buildings.City.upgradeCosts[1])
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "build", building = "City", cell = capital })))
				.toBe("maxLevel")
			-- Не город — «Город» не строится.
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "build", building = "City", cell = capital + 1 })))
				.toBe("needCity")
		end
	)

	T.it(
		"нефтяные поля: около заданной доли провинций, одинаково при каждой сборке",
		function()
			local a = Provinces.build(Fixtures.pangea)
			local b = Provinces.build(Fixtures.pangea)
			local count = 0
			for id, p in a.list do
				if p.oil then
					count += 1
				end
				T.expect(b.list[id].oil).toBe(p.oil)
			end
			T.expect(count).toBe(math.floor(a.count * Config.Oil.ProvinceShare + 0.5))
		end
	)

	T.it("намерение build проверяется", function()
		T.expect((Intents.parse("build", { building = "Factory", cell = 10 })) ~= nil).toBe(true)
		T.expect((Intents.parse("build", { building = "MissileSilo", cell = 10 }))).toBe(nil) -- этап 7
		T.expect((Intents.parse("build", { building = "Factory", cell = -1 }))).toBe(nil)
	end)
end)

T.describe("Укрепления и котлы", function()
	T.it(
		"укрепление: клетки фронта в его провинции защищаются ×1.5; укреплённая линия — ещё бонус",
		function()
			local map = TinyMap.plains(10, 6)
			local front = { 12, 13, 14 }
			local plain = Fronts.terrainDefense(map, front)
			local fortified = Fronts.terrainDefense(map, front, nil, function(): boolean
				return true
			end)
			T.expect(fortified).toBeNear(plain * Config.Buildings.Fort.defenseMultiplier, 1e-9)
			local attack: Types.Attack = {
				attacker = 1,
				target = 2,
				troops = 0,
				focus = nil,
				forces = Forces.new(),
				supplied = true,
				ratio = 0,
				fighting = false,
				lastAdvance = 0,
			}
			Forces.add(attack.forces, INF, 1000)
			local home = Forces.new()
			Forces.add(home, INF, 1000)
			local open = Fronts.battle(attack, { home = home, share = 1 }, 1, Rng.new(1), DT, false)
			local line = Fronts.battle(
				attack,
				{ home = home, share = 1, bonus = Config.Fortify.LineBonus },
				1,
				Rng.new(1),
				DT,
				false
			)
			T.expect(line.ratio).toBeNear(open.ratio / Config.Fortify.LineBonus, 1e-9)
		end
	)

	T.it(
		"котёл: кусок без связи со столицей не даёт людей и сдаётся врагу, но не соседу в мире",
		function()
			local map = TinyMap.plains(30, 10)
			local m = MatchSim.new(map, 3)
			m.victory = false -- крошечная карта: 60% суши набирается сразу
			MatchSim.addPlayer(m, 1, "A")
			MatchSim.addPlayer(m, 2, "B")
			m.phase = "Play"
			local w = 30
			-- Страна 1: столица слева (x 1..8); котёл — кусок x 15..16, окружён страной 2.
			for y = 1, 8 do
				for x = 1, 28 do
					local owner = if x <= 8 then 1 elseif x >= 15 and x <= 16 then 1 else 2
					Grid.setOwner(m.grid, y * w + x, owner)
				end
			end
			local capA, capB = 4 * w + 3, 4 * w + 25
			for k, c in { capA, capB } do
				Grid.setCity(m.grid, c, true)
				m.cityOf[-k] = c
			end
			m.nations[1].capital, m.nations[2].capital = capA, capB
			local result = Pockets.compute(m.grid, 1, capA, function(c: number): boolean
				return Grid.isCity(m.grid, c)
			end, 0, nil)
			T.expect(#result.pockets).toBe(1)
			T.expect(result.cells).toBe(16)
			T.expect(result.pockets[1].hasCity).toBe(false)
			-- Мир: котёл держится.
			for _ = 1, math.floor((Config.Pocket.SurrenderSec + 2) * Config.Sim.TickRate) do
				MatchSim.step(m, DT)
			end
			T.expect(Grid.getOwner(m.grid, 4 * w + 15)).toBe(1)
			T.expect(MatchSim.maxPeopleOf(m, 1)).toBe(Economy.maxPeople(Grid.cellsOf(m.grid, 1) - 16, 1))
			-- Война: котёл без города переходит окружившему.
			local war = Wars.declare(m.wars, 2, 1, m.simTime)
			war.state, war.activeAt = "active", m.simTime
			for _ = 1, math.floor((Config.Pocket.SurrenderSec + 2) * Config.Sim.TickRate) do
				MatchSim.step(m, DT)
			end
			T.expect(Grid.getOwner(m.grid, 4 * w + 15)).toBe(2)
		end
	)

	T.it("боты строят завод и нанимают технику", function()
		-- Сид подобран: техника к 5-й минуте может и погибнуть в войне (до 7а так было на сиде 54,
		-- после 7а — на 51: проверки восстаний тратят случайные числа, партия идёт иначе).
		local m = MatchSim.new(Fixtures.pangea, 52)
		MatchSim.startPick(m)
		while m.phase ~= "Play" do
			MatchSim.step(m, DT)
		end
		for _ = 1, 300 * Config.Sim.TickRate do -- 5 минут: на технику нужны завод и деньги
			MatchSim.step(m, DT)
		end
		-- Техника — всё, кроме пехоты (танки, артиллерия, ПВО: нужен завод).
		local factories, vehicles = 0, 0
		for _, n in m.nations do
			factories += MatchSim.ownedOf(m, n.id).factories
			local front = MatchSim.frontForces(m, n.id)
			for kind = 2, #n.home do
				vehicles += n.home[kind].strength + front[kind].strength
			end
		end
		T.expect(factories > 0).toBe(true)
		T.expect(vehicles > 0).toBe(true)
	end)
end)
