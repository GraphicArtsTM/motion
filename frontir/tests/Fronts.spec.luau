--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local TinyMap = require("./lib/TinyMap")
local Config = require("../src/shared/Config")
local Forces = require("../src/shared/Forces")
local Fronts = require("../src/shared/Fronts")
local Grid = require("../src/shared/Grid")
local MatchSim = require("../src/shared/MatchSim")
local Rng = require("../src/shared/Rng")
local Types = require("../src/shared/Types")
local Wars = require("../src/shared/Wars")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
local TANKS = Forces.kindIndex("Tanks") :: number
local ART = Forces.kindIndex("Artillery") :: number

local function forcesOf(inf: number, tanks: number?, art: number?): Types.Forces
	local f = Forces.new()
	Forces.add(f, INF, inf)
	Forces.add(f, TANKS, tanks or 0)
	Forces.add(f, ART, art or 0)
	return f
end

local function frontAttack(forces: Types.Forces): Types.Attack
	return {
		attacker = 1,
		target = 2,
		troops = 0,
		focus = nil,
		forces = forces,
		supplied = true,
		ratio = math.huge,
		fighting = false,
	}
end

-- Две державы на равнине 40×12: 1 — слева, 2 — справа, по одному городу у каждой.
-- Война между a и b сразу активна (мобилизация пропущена).
local function atWar(m: MatchSim.Match, a: number, b: number)
	local war = Wars.declare(m.wars, a, b, m.simTime)
	war.state = "active"
	war.activeAt = m.simTime
end

local function duel(): (MatchSim.Match, number, number)
	local map = TinyMap.plains(40, 12)
	local m = MatchSim.new(map, 5)
	MatchSim.addPlayer(m, 1, "A")
	MatchSim.addPlayer(m, 2, "B")
	m.phase = "Play"
	for x = 1, 38 do
		for y = 1, 10 do
			Grid.setOwner(m.grid, y * 40 + x, if x <= 19 then 1 else 2)
		end
	end
	local cityA, cityB = 6 * 40 + 4, 6 * 40 + 35
	for k, c in { cityA, cityB } do
		Grid.setCity(m.grid, c, true)
		m.cityOf[-k] = c -- города вне провинций (на маленькой карте провинций нет)
	end
	m.nations[1].capital, m.nations[2].capital = cityA, cityB
	for _, n in m.nations do
		n.colorIndex = n.id
		n.people = 5000
	end
	atWar(m, 1, 2)
	return m, cityA, cityB
end

local function runFor(m: MatchSim.Match, seconds: number)
	for _ = 1, math.floor(seconds * Config.Sim.TickRate) do
		MatchSim.step(m, DT)
	end
end

T.describe("Forces", function()
	T.it(
		"пул: добавление разбавляет опыт, доля уходит и возвращается",
		function()
			local f = Forces.new()
			Forces.add(f, INF, 100, 6)
			Forces.add(f, INF, 100, 0)
			T.expect(f[INF].strength).toBe(200)
			T.expect(f[INF].xp).toBeNear(3, 1e-9) -- новобранцы разбавили ветеранов
			local part = Forces.take(f, 0.25)
			T.expect(part[INF].strength).toBeNear(50, 1e-9)
			T.expect(f[INF].strength).toBeNear(150, 1e-9)
			Forces.merge(f, part)
			T.expect(Forces.total(f)).toBeNear(200, 1e-9)
			T.expect(Forces.total(part)).toBe(0)
		end
	)

	T.it(
		"звёзды по порогам опыта, не больше трёх; каждая +30% силы",
		function()
			local thresholds = Config.Combat.StarXp
			T.expect(Forces.stars({ strength = 1, xp = 0 })).toBe(0)
			T.expect(Forces.stars({ strength = 1, xp = thresholds[1] })).toBe(1)
			T.expect(Forces.stars({ strength = 1, xp = 1e9 })).toBe(Config.Combat.MaxVeteranStars)
			T.expect(Forces.vetMul({ strength = 1, xp = thresholds[2] }))
				.toBeNear(1 + 2 * Config.Combat.VeteranStarBonus)
		end
	)

	T.it(
		"контр-типы: танки против пехоты сильнее, чем пехота против пехоты",
		function()
			local enemy = forcesOf(100)
			local tanks = Forces.new()
			Forces.add(tanks, TANKS, 100)
			local inf = forcesOf(100)
			local tankPower = Forces.power(tanks, enemy, "attack") / Config.Units.Tanks.attack
			local infPower = Forces.power(inf, enemy, "attack") / Config.Units.Infantry.attack
			T.expect(tankPower).toBeNear(infPower * Config.Combat.CounterBonus, 1e-6)
		end
	)

	T.it(
		"потери: слабые в защите теряют больше, артиллерия — меньше; темп танков выше",
		function()
			local f = forcesOf(100, 0, 100)
			Forces.applyDamage(f, 60)
			local lostInf = 100 - f[INF].strength
			local lostArt = 100 - f[ART].strength
			-- Артиллерия слабее в защите, но теряет вдвое меньше — итог по формуле весов.
			local wInf = 1 / Config.Units.Infantry.defense
			local wArt = 1 / Config.Units.Artillery.defense * Config.Combat.ArtilleryLossMul
			T.expect(lostArt / lostInf).toBeNear(wArt / wInf, 1e-6)
			T.expect(Forces.speedFactor(forcesOf(0, 100)))
				.toBeNear(Config.Units.Tanks.speed / Config.Units.Infantry.speed)
			T.expect(Forces.speedFactor(Forces.new())).toBe(1)
		end
	)
end)

T.describe("Fronts.battle", function()
	local function battle(att: Types.Forces, home: Types.Forces, share: number?): (Types.Attack, Fronts.BattleResult)
		local a = frontAttack(att)
		local r = Fronts.battle(a, { home = home, share = share or 1, counter = nil }, 1, Rng.new(3), DT, true)
		return a, r
	end

	T.it(
		"без обороны — бесконечный перевес, без потерь, полная скорость",
		function()
			local a, r = battle(forcesOf(500), Forces.new())
			T.expect(r.fighting).toBe(false)
			T.expect(r.ratio).toBe(math.huge)
			T.expect(Forces.total(a.forces)).toBe(500)
			T.expect(Fronts.advanceMul(a, r.ratio) > 0).toBe(true)
		end
	)

	T.it(
		"равные силы: защитник на своей земле сильнее — фронт стоит, обе стороны теряют",
		function()
			local home = forcesOf(1000)
			local a, r = battle(forcesOf(1000), home)
			T.expect(r.fighting).toBe(true)
			T.expect(r.ratio < 1).toBe(true)
			T.expect(Fronts.advanceMul(a, r.ratio)).toBe(0)
			T.expect(Forces.total(a.forces) < 1000).toBe(true)
			T.expect(Forces.total(home) < 1000).toBe(true)
		end
	)

	T.it("сильный фронт идёт; прорыв от BreakthroughRatio быстрее", function()
		local a = frontAttack(forcesOf(1000))
		local slow = Fronts.advanceMul(a, 1.5)
		local full = Fronts.advanceMul(a, Config.Combat.FullSpeedRatio)
		local breakthrough = Fronts.advanceMul(a, Config.Combat.BreakthroughRatio)
		T.expect(slow > 0 and slow < full).toBe(true)
		T.expect(breakthrough).toBeNear(full * Config.Combat.BreakthroughMul, 1e-9)
	end)

	T.it(
		"гарнизон делится по фронтам: на коротком фронте обороны меньше",
		function()
			local _, wide = battle(forcesOf(1000), forcesOf(1000), 1)
			local _, narrow = battle(forcesOf(1000), forcesOf(1000), 0.25)
			T.expect(narrow.ratio).toBeNear(wide.ratio * 4, 1e-6)
		end
	)

	T.it("в долгой войне копится опыт — появляются звёзды", function()
		local a = frontAttack(forcesOf(2000))
		local rng = Rng.new(9)
		for _ = 1, 600 do
			-- Защитника всё время подкрепляют: фронт бьёт и бьёт, копя опыт.
			Fronts.battle(a, { home = forcesOf(500), share = 1, counter = nil }, 1, rng, DT, true)
		end
		T.expect(Forces.total(a.forces) > 0).toBe(true)
		T.expect(Forces.stars(a.forces[INF]) >= 1).toBe(true)
	end)

	T.it("без снабжения — слабее и тает даже без боя", function()
		local supplied = frontAttack(forcesOf(1000))
		local unsupplied = frontAttack(forcesOf(1000))
		unsupplied.supplied = false
		local enemy = forcesOf(100)
		local r1 = Fronts.battle(supplied, { home = forcesOf(100), share = 1, counter = nil }, 1, Rng.new(1), DT, false)
		local r2 = Fronts.battle(unsupplied, { home = enemy, share = 1, counter = nil }, 1, Rng.new(1), DT, false)
		T.expect(r2.ratio).toBeNear(r1.ratio * Config.Combat.UnsuppliedPowerMul, 1e-6)
		Fronts.battle(unsupplied, { home = Forces.new(), share = 1, counter = nil }, 1, Rng.new(1), 1, true)
		T.expect(Forces.total(unsupplied.forces)).toBeNear(1000 * (1 - Config.Combat.OutOfSupplyLossPerSec), 1e-6)
	end)
end)

T.describe("Фронты в матче", function()
	T.it(
		"найм: очередь, время, войска в гарнизоне; очередь не бесконечна",
		function()
			local m = duel()
			local me = m.nations[1]
			local before = me.people
			T.expect((MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Tanks" }))).toBe(true)
			T.expect(me.people).toBe(before - Config.Units.Tanks.people)
			T.expect(#me.queue).toBe(1)
			runFor(m, Config.Units.Tanks.recruitSec + 0.2)
			T.expect(#me.queue).toBe(0)
			T.expect(me.home[TANKS].strength).toBe(Config.Units.Tanks.strength)
			for _ = 1, Config.Forces.MaxQueue do
				MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Infantry" })
			end
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Infantry" }))).toBe("queueFull")
		end
	)

	T.it("без войск напасть на державу нельзя", function()
		local m = duel()
		T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 }))).toBe("noUnits")
	end)

	T.it(
		"сильный фронт берёт землю, затем город; держава без городов выбывает, её земля ничья",
		function()
			local m, _, cityB = duel()
			Forces.add(m.nations[1].home, TANKS, 4000)
			Forces.add(m.nations[1].home, INF, 4000)
			Forces.add(m.nations[2].home, INF, 300)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 }))).toBe(true)
			local cellsB = Grid.cellsOf(m.grid, 2)
			local fought = false
			for _ = 1, 240 * Config.Sim.TickRate do
				MatchSim.step(m, DT)
				for _, a in m.attacks do
					if a.fighting then
						fought = true
					end
				end
				if not m.nations[2].alive then
					break
				end
			end
			T.expect(fought).toBe(true)
			T.expect(m.nations[2].alive).toBe(false)
			T.expect(Grid.getOwner(m.grid, cityB)).toBe(1)
			T.expect(Grid.cellsOf(m.grid, 2)).toBe(0)
			T.expect(Grid.cellsOf(m.grid, 1) > 190).toBe(true)
			T.expect(Grid.cellsOf(m.grid, 1) < 190 + cellsB).toBe(true) -- остаток земли 2 стал ничьим
			-- Войска фронта вернулись домой с опытом.
			T.expect(Forces.total(m.nations[1].home) > 0).toBe(true)
		end
	)

	T.it(
		"равные войска и бонус защитника: фронт стоит, обе стороны тают",
		function()
			local m = duel()
			Forces.add(m.nations[1].home, INF, 2000)
			Forces.add(m.nations[2].home, INF, 2000)
			MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 })
			local cells = Grid.cellsOf(m.grid, 1)
			runFor(m, 20)
			T.expect(Grid.cellsOf(m.grid, 1)).toBe(cells)
			T.expect(Forces.total(m.nations[2].home) < 2000).toBe(true)
		end
	)

	T.it(
		"встречные фронты на одной границе — один бой, двигается сильнейший",
		function()
			local m = duel()
			Forces.add(m.nations[1].home, TANKS, 6000)
			Forces.add(m.nations[2].home, INF, 1500)
			MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 })
			MatchSim.applyIntent(m, 2, { kind = "attack", target = 1, percent = 1 })
			local before1, before2 = Grid.cellsOf(m.grid, 1), Grid.cellsOf(m.grid, 2)
			runFor(m, 15)
			T.expect(Grid.cellsOf(m.grid, 1) > before1).toBe(true)
			T.expect(Grid.cellsOf(m.grid, 2) < before2).toBe(true)
		end
	)

	T.it(
		"ничейный город: людьми не взять, войсками — можно, они теряют силу гарнизона",
		function()
			local map = TinyMap.plains(20, 6)
			local m = MatchSim.new(map, 2)
			MatchSim.addPlayer(m, 1, "A")
			m.phase = "Play"
			local home, neutralCity = 2 * 20 + 2, 2 * 20 + 12
			Grid.setOwner(m.grid, home, 1)
			for k, c in { home, neutralCity } do
				Grid.setCity(m.grid, c, true)
				m.cityOf[-k] = c
			end
			local me = m.nations[1]
			me.capital, me.people = home, 50000
			MatchSim.applyIntent(m, 1, { kind = "attack", target = 0, percent = 1 })
			runFor(m, 30)
			T.expect(Grid.getOwner(m.grid, neutralCity)).toBe(0) -- без войск город стоит
			Forces.add(me.home, INF, 1000)
			me.people = 50000
			MatchSim.applyIntent(m, 1, { kind = "attack", target = 0, percent = 1 })
			runFor(m, 30)
			T.expect(Grid.getOwner(m.grid, neutralCity)).toBe(1)
			T.expect(Forces.total(me.home)).toBeNear(1000 - Config.Combat.NeutralCityGarrison, 1e-6)
		end
	)

	T.it("фронт далеко от своих городов — без снабжения", function()
		local m = duel()
		Forces.add(m.nations[1].home, INF, 3000)
		MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 })
		MatchSim.step(m, DT)
		-- Дальность снабжения масштабируется по ширине карты: 60 × 40/512 ≈ 4.7 клетки,
		-- а фронт (x≈20) в 16 клетках от города A (x=4).
		T.expect(Config.Combat.SupplyRange * 40 / Config.UnitsReferenceMapWidth < 16).toBe(true)
		T.expect(m.attacks[1].supplied).toBe(false)
	end)
end)

T.describe("Фронты на «Пангее»", function()
	T.it(
		"боты нанимают войска и воюют фронтами; одинаковый сид — одна партия",
		function()
			local function run(): (MatchSim.Match, boolean, string)
				local m = MatchSim.new(Fixtures.pangea, 31)
				MatchSim.startPick(m)
				while m.phase ~= "Play" do
					MatchSim.step(m, DT)
				end
				local war = false
				for _ = 1, 300 * Config.Sim.TickRate do
					MatchSim.step(m, DT)
					for _, a in m.attacks do
						if a.target ~= 0 and a.fighting then
							war = true
						end
					end
				end
				return m, war, buffer.tostring(m.grid.owner)
			end
			local m, war, a = run()
			local _, _, b = run()
			T.expect(a == b).toBe(true)
			T.expect(war).toBe(true)
			local anyForces = false
			for _, n in m.nations do
				if n.alive and Forces.total(n.home) + Forces.total(MatchSim.frontForces(m, n.id)) > 0 then
					anyForces = true
				end
			end
			T.expect(anyForces).toBe(true)
		end
	)
end)
