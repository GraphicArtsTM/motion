--!strict
-- Экономика 2.0 (GDD §15д ч.2): роли зданий, рост цены, уровни, районы, содержание, снос.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local Economy = require("../src/shared/Economy")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")

local DT = 1 / Config.Sim.TickRate
local W, H = 128, 64
local cfg = Config.Build

-- Две державы на полосах-провинциях по 10 клеток: 1 — x 1..60, 2 — x 61..120. Столица 1 — (5, 8).
local function duo(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 13)
	m.victory = false
	MatchSim.addPlayer(m, 1, "N1")
	MatchSim.addPlayer(m, 2, "N2")
	m.phase = "Play"
	for y = 1, H - 2 do
		for x = 1, 120 do
			Grid.setOwner(m.grid, y * W + x, if x <= 60 then 1 else 2)
		end
	end
	local caps = { 8 * W + 5, 8 * W + 115 }
	for _, n in m.nations do
		n.colorIndex = n.id
		n.people = 1000
		n.money = 1e6
		n.oil = 1000
		n.capital = caps[n.id]
		Grid.setCity(m.grid, caps[n.id], true)
		m.cityOf[-n.id] = caps[n.id]
	end
	MatchSim.refreshOwned(m)
	return m
end

local function build(m: MatchSim.Match, kind: string, cell: number): (boolean, string?)
	return MatchSim.applyIntent(m, 1, { kind = "build", building = kind :: any, cell = cell })
end

T.describe("Экономика 2.0 (§15д)", function()
	T.it(
		"рост цены: каждое следующее здание типа дороже на CostStep, считаются уровни; другие типы — нет",
		function()
			local m = duo()
			local base = Config.Buildings.Factory.cost
			local far = 40 * W + 30 -- вне района столицы
			T.expect((MatchSim.buildPrice(m, 1, "Factory", far))).toBe(base)
			T.expect((build(m, "Factory", far))).toBe(true)
			T.expect((MatchSim.buildPrice(m, 1, "Factory", 40 * W + 40))).toBeNear(base * (1 + cfg.CostStep), 1e-6)
			-- Улучшение: ур. 2 по UpgradeMul[2], потом новый завод — уже +2 шага.
			T.expect((build(m, "Factory", far))).toBe(true)
			T.expect((MatchSim.buildPrice(m, 1, "Factory", 40 * W + 40))).toBeNear(base * (1 + 2 * cfg.CostStep), 1e-6)
			T.expect((MatchSim.buildPrice(m, 1, "Market", 40 * W + 40))).toBe(Config.Buildings.Market.cost)
			-- Держава 2 платит свою цену.
			T.expect((MatchSim.buildPrice(m, 2, "Factory", 40 * W + 100))).toBe(base)
			-- Ограничения на число нет: десять заводов подряд (не вплотную) строятся.
			for k = 1, 10 do
				T.expect((build(m, "Factory", (20 + (k % 2) * 4) * W + 4 * k + 10))).toBe(true)
			end
		end
	)

	T.it(
		"роли: завод — деньги, жильё — люди, казармы — линии и техника; содержание зданий",
		function()
			local m = duo()
			local far = 40 * W + 30
			local function owned(): Buildings.Owned
				return MatchSim.ownedOf(m, 1)
			end
			T.expect((build(m, "Factory", far))).toBe(true)
			T.expect(owned().factoryIncome).toBe(Config.Buildings.Factory.income)
			T.expect((build(m, "Factory", far))).toBe(true)
			T.expect(owned().factoryIncome).toBe(2 * Config.Buildings.Factory.income)
			local maxBefore = MatchSim.maxPeopleOf(m, 1)
			T.expect((build(m, "Housing", 40 * W + 40))).toBe(true)
			T.expect(MatchSim.maxPeopleOf(m, 1) - maxBefore).toBe(Config.Buildings.Housing.people)
			T.expect(MatchSim.recruitLines(m, 1)).toBe(1)
			T.expect((build(m, "Barracks", 50 * W + 30))).toBe(true)
			T.expect(MatchSim.recruitLines(m, 1)).toBe(2)
			T.expect(owned().barracksLevel).toBe(1)
			-- Содержание: цена × UpkeepShare за уровень, входит в расходы.
			local want = Buildings.upkeepOf("Factory", 2)
				+ Buildings.upkeepOf("Housing", 1)
				+ Buildings.upkeepOf("Barracks", 1)
			T.expect(owned().upkeep).toBeNear(want, 1e-9)
			MatchSim.step(m, DT)
			T.expect(m.economy[1].upkeep >= want).toBe(true)
			-- Доход с заводом больше, чем без него (те же клетки и города).
			local e = Economy.income(Grid.cellsOf(m.grid, 1), owned().cityLevels, 0, owned().factoryIncome, 0)
			T.expect(e - Economy.income(Grid.cellsOf(m.grid, 1), owned().cityLevels, 0))
				.toBeNear(owned().factoryIncome, 1e-6)
		end
	)

	T.it(
		"район: здание рядом со своим городом сильнее на DistrictPerCityLevel за уровень города",
		function()
			local m = duo()
			local cap = m.nations[1].capital :: number
			local near = cap + cfg.MinGap + 1 -- в районе столицы (ур. 1)
			T.expect((build(m, "Factory", near))).toBe(true)
			local income = Config.Buildings.Factory.income
			T.expect(MatchSim.ownedOf(m, 1).factoryIncome).toBeNear(income * (1 + cfg.DistrictPerCityLevel), 1e-9)
			-- Город ур. 2 — район сильнее.
			T.expect((build(m, "City", cap))).toBe(true)
			T.expect(MatchSim.ownedOf(m, 1).factoryIncome).toBeNear(income * (1 + 2 * cfg.DistrictPerCityLevel), 1e-9)
		end
	)

	T.it(
		"снос: доля цены назад; нельзя у фронта врага и чужое; город не сносится",
		function()
			local m = duo()
			local far = 40 * W + 20
			T.expect((build(m, "Market", far))).toBe(true)
			local money = m.nations[1].money
			T.expect((MatchSim.applyIntent(m, 1, { kind = "demolish", cell = far }))).toBe(true)
			T.expect(m.nations[1].money - money).toBeNear(Config.Buildings.Market.cost * cfg.DemolishRefund, 1e-6)
			T.expect(m.buildings.byCell[far]).toBe(nil)
			-- У границы с врагом в войне — нельзя.
			local border = 40 * W + 58
			T.expect((build(m, "Market", border))).toBe(true)
			DevTools.warNow(m, 1, 2)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "demolish", cell = border }))).toBe("nearFront")
			T.expect(select(2, MatchSim.applyIntent(m, 2, { kind = "demolish", cell = far + 4 }))).toBe("notOwner")
			local cap = m.nations[1].capital :: number
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "demolish", cell = cap }))).toBe("notOwner")
		end
	)

	T.it(
		"удар (§15д ч.3): −1 уровень, город не ниже 1, ур. 1 — выключено; 30 с защиты; налёт ловит заряд ПВО",
		function()
			local m = duo()
			DevTools.warNow(m, 1, 2)
			local far = 40 * W + 30
			T.expect((build(m, "Factory", far))).toBe(true)
			T.expect((build(m, "Factory", far))).toBe(true) -- ур. 2
			local cap = m.nations[1].capital :: number
			T.expect((build(m, "City", cap))).toBe(true) -- город ур. 2
			local plane: any = { owner = 2 }
			MatchSim.bomb(m, plane, far)
			T.expect(m.buildings.byCell[far].level).toBe(1)
			-- Защита: повторный налёт сразу — уровень не падает и здание не выключается.
			MatchSim.bomb(m, plane, far)
			T.expect(m.buildings.byCell[far].level).toBe(1)
			T.expect(MatchSim.isDisabled(m, far)).toBe(false)
			-- После защиты здание ур. 1 — выключено (не разрушено).
			m.simTime += Config.Defense.ProtectSec + 1
			MatchSim.bomb(m, plane, far)
			T.expect(m.buildings.byCell[far] ~= nil).toBe(true)
			T.expect(MatchSim.isDisabled(m, far)).toBe(true)
			-- Город: −1 уровень, не ниже 1.
			MatchSim.bomb(m, plane, cap)
			T.expect(Buildings.cityLevel(m.buildings, cap)).toBe(1)
			m.simTime += Config.Defense.ProtectSec + 1
			MatchSim.bomb(m, plane, cap)
			T.expect(Buildings.cityLevel(m.buildings, cap)).toBe(1)
			-- Батарея ПВО ур. 2 рядом с заводом: два налёта перехвачены, третий — нет.
			local target = 20 * W + 30
			T.expect((build(m, "Factory", target))).toBe(true)
			T.expect((build(m, "Factory", target))).toBe(true)
			local battery = 20 * W + 36
			T.expect((build(m, "AirDefense", battery))).toBe(true)
			T.expect((build(m, "AirDefense", battery))).toBe(true)
			T.expect((MatchSim.batteryCharges(m, battery))).toBe(2)
			m.simTime += Config.Defense.ProtectSec + 1
			local function raidAndCount(): number
				MatchSim.takeEvents(m)
				MatchSim.bomb(m, plane, target)
				local n = 0
				for _, e in MatchSim.takeEvents(m) do
					if e.kind == "raidIntercepted" then
						n += 1
					end
				end
				return n
			end
			T.expect(raidAndCount()).toBe(1)
			T.expect(raidAndCount()).toBe(1)
			T.expect(raidAndCount()).toBe(0)
			T.expect(m.buildings.byCell[target].level).toBe(1)
			-- Заряд восстанавливается через RechargeSec.
			m.simTime += Config.Defense.RechargeSec + 1
			T.expect((MatchSim.batteryCharges(m, battery)) >= 1).toBe(true)
		end
	)

	T.it(
		"захват (§15д ч.3): здание перешло врагу — −1 уровень, ур. 1 — выключено",
		function()
			local m = duo()
			local far = 40 * W + 30
			T.expect((build(m, "Factory", far))).toBe(true)
			T.expect((build(m, "Factory", far))).toBe(true)
			local market = 40 * W + 40
			T.expect((build(m, "Market", market))).toBe(true)
			MatchSim.step(m, DT)
			Grid.setOwner(m.grid, far, 2)
			Grid.setOwner(m.grid, market, 2)
			MatchSim.step(m, DT)
			T.expect(m.buildings.byCell[far].level).toBe(1)
			T.expect(MatchSim.isDisabled(m, market)).toBe(true)
			T.expect(MatchSim.ownedOf(m, 2).factories).toBe(1)
		end
	)

	T.it(
		"основать город (§15д ч.4): своя земля вдали от городов, цена растёт с числом основанных, имя по клетке",
		function()
			local m = duo()
			local spot = 40 * W + 30
			local price = (MatchSim.buildPrice(m, 1, "City", spot)) :: number
			T.expect(price).toBe(Config.Cities.FoundCost)
			local money = m.nations[1].money
			T.expect((build(m, "City", spot))).toBe(true)
			T.expect(m.nations[1].money).toBe(money - price)
			T.expect(Grid.isCity(m.grid, spot)).toBe(true)
			T.expect(MatchSim.foundedOf(m, 1)).toBe(1)
			T.expect(table.find(MatchSim.cities(m), spot) ~= nil).toBe(true)
			local founded = false
			for _, e in MatchSim.takeEvents(m) do
				founded = founded or (e.kind == "cityFounded" and e.cell == spot)
			end
			T.expect(founded).toBe(true)
			-- Второй — дороже на FoundStep; рядом с городом — нельзя; на чужой земле — нельзя.
			T.expect((MatchSim.buildPrice(m, 1, "City", 20 * W + 30)))
				.toBe(Config.Cities.FoundCost * (1 + Config.Cities.FoundStep))
			T.expect(select(2, build(m, "City", spot + 5))).toBe("cityTooClose")
			T.expect(select(2, build(m, "City", 40 * W + 100))).toBe("notOwner")
			-- Новый город улучшается, как любой (уровень 2).
			T.expect((build(m, "City", spot))).toBe(true)
			T.expect(Buildings.cityLevel(m.buildings, spot)).toBe(2)
			-- Имя основанного города — одинаковое на сервере и клиенте (по клетке).
			local Provinces = require("../src/shared/Provinces")
			local a = Provinces.foundedName(m.map, spot)
			local b = Provinces.foundedName(m.map, spot)
			T.expect(a.ru ~= "" and a.ru == b.ru and a.en == b.en).toBe(true)
		end
	)
end)
