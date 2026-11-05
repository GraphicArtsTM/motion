--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Air = require("../src/shared/Air")
local Buildings = require("../src/shared/Buildings")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Tech = require("../src/shared/Tech")
local MatchStats = require("../src/shared/Net/MatchStats")
local Protocol = require("../src/shared/Net/Protocol")
local Types = require("../src/shared/Types")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
local AA = Forces.kindIndex("AntiAir") :: number
local cfg = Config.Air
-- Ширина 512 — эталонная: дальности авиации не масштабируются. Держава 1 — x 1..100, держава 2 — x 101..200,
-- дальше — ничья земля. Провинции — полосы по 10 клеток.
local W, H = 512, 24
local BORDER = 100

local function duo(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 5)
	m.victory = false
	MatchSim.addPlayer(m, 1, "N1")
	MatchSim.addPlayer(m, 2, "N2")
	m.phase = "Play"
	for y = 1, H - 2 do
		for x = 1, 200 do
			Grid.setOwner(m.grid, y * W + x, if x <= BORDER then 1 else 2)
		end
	end
	local caps = { 12 * W + 10, 12 * W + 190 }
	for _, n in m.nations do
		n.colorIndex = n.id
		n.people = 5000
		n.money = 100000
		n.oil = 5000
		n.capital = caps[n.id]
		Grid.setCity(m.grid, caps[n.id], true)
		m.cityOf[-n.id] = caps[n.id]
	end
	return m
end

local function runFor(m: MatchSim.Match, seconds: number)
	for _ = 1, math.floor(seconds * Config.Sim.TickRate + 0.5) do
		MatchSim.step(m, DT)
	end
end

-- Здание kind в провинции с клеткой x (y = 12).
local function place(m: MatchSim.Match, kind: Types.BuildingKind, x: number): number
	local province = x // 10 + 1
	local p = m.provinces.list[province]
	Buildings.place(m.buildings, kind, p.center, province)
	MatchSim.refreshOwned(m)
	return p.center
end

local function hire(m: MatchSim.Match, id: number, kind: Air.PlaneKind, airfield: number): Air.Plane
	T.expect((MatchSim.applyIntent(m, id, { kind = "plane", plane = kind, airfield = airfield }))).toBe(true)
	runFor(m, Air.stats(kind).recruitSec + 0.2)
	local planes = Air.ofNation(m.air, id)
	return planes[#planes]
end

local function frontOf(m: MatchSim.Match, attacker: number, target: number, strength: number, aa: number?): Types.Attack
	local forces = Forces.new()
	Forces.add(forces, INF, strength)
	if aa ~= nil then
		Forces.add(forces, AA, aa)
	end
	local a: Types.Attack = {
		attacker = attacker,
		target = target,
		troops = 0,
		focus = 12 * W + BORDER,
		forces = forces,
		supplied = true,
		ratio = 1,
		fighting = false,
		lastAdvance = m.simTime,
	}
	table.insert(m.attacks, a)
	return a
end

-- Перемирие Совета (§8.2): фронты стоят — линия не уходит из круга налёта и бой не меняет силу.
local function freezeFronts(m: MatchSim.Match)
	table.insert(m.council.active, { kind = "truce", untilTime = m.simTime + 10000, target = nil } :: any)
end

local function events(m: MatchSim.Match, kind: string): { any }
	local out = {}
	for _, e in MatchSim.takeEvents(m) do
		if e.kind == kind then
			table.insert(out, e)
		end
	end
	return out
end

T.describe("Авиация", function()
	T.it(
		"аэродром и найм: самолёт стоит на аэродроме, цена списана",
		function()
			local m = duo()
			-- Без технологии «Авиация» (Флот 3) аэродром не построить (§6.14).
			T.expect((MatchSim.applyIntent(m, 1, { kind = "build", building = "Airfield", cell = 12 * W + 45 })))
				.toBe(false)
			Tech.grant(m.tech, 1, "Fleet", 3)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "build", building = "Airfield", cell = 12 * W + 45 })))
				.toBe(true)
			local airfield = m.provinces.list[45 // 10 + 1].center
			local money = m.nations[1].money
			T.expect((MatchSim.applyIntent(m, 1, { kind = "plane", plane = "Bomber", airfield = airfield }))).toBe(true)
			T.expect(m.nations[1].money).toBe(money - Air.stats("Bomber").cost)
			runFor(m, Air.stats("Bomber").recruitSec + 0.2)
			local planes = Air.ofNation(m.air, 1)
			T.expect(#planes).toBe(1)
			T.expect(planes[1].state).toBe("based")
			T.expect(Air.cellOf(W, planes[1])).toBe(airfield)
			T.expect(select(2, MatchSim.applyIntent(m, 2, { kind = "plane", plane = "Fighter", airfield = airfield })))
				.toBe("needAirfield")
		end
	)

	T.it(
		"налёт: только по врагу и в радиусе; фронт врага теряет силу, его завод выведен из строя на 60 с",
		function()
			local m = duo()
			local airfield = place(m, "Airfield", 75)
			local bomber = hire(m, 1, "Bomber", airfield)
			local factory = place(m, "Factory", 105)
			local target = 12 * W + BORDER + 3
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "raid", cell = target }))).toBe("notAtWar")
			DevTools.warNow(m, 1, 2)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "raid", cell = 12 * W + 199 }))).toBe("outOfRange")
			local enemyFront = frontOf(m, 2, 1, 3000)
			freezeFronts(m)
			runFor(m, 0.2) -- линия фронта (выборка) посчиталась
			local before = Forces.total(enemyFront.forces)
			T.expect(MatchSim.ownedOf(m, 2).factories).toBe(1)
			MatchSim.takeEvents(m)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "raid", cell = target }))).toBe(true)
			T.expect(bomber.state).toBe("flying")
			local flight = 30 / Air.speed("Bomber", W)
			runFor(m, flight + cfg.BombEverySec * (cfg.RaidsPerSortie - 1) + 0.5)
			local raids = events(m, "raid")
			T.expect(#raids).toBe(cfg.RaidsPerSortie)
			T.expect(raids[1].buildings).toBe(1)
			T.expect(MatchSim.isDisabled(m, factory)).toBe(true)
			T.expect(MatchSim.ownedOf(m, 2).factories).toBe(0)
			-- Фронт врага ослаб на налёты (фронты стоят — перемирие).
			T.expect(before - Forces.total(enemyFront.forces) > Air.stats("Bomber").attack * cfg.BombDamage * 2)
				.toBeTruthy()
			-- Вернулся и через минуту завод снова работает.
			runFor(m, 20)
			T.expect(bomber.state).toBe("based")
			runFor(m, cfg.BuildingDisableSec)
			T.expect(MatchSim.isDisabled(m, factory)).toBe(false)
			T.expect(MatchSim.ownedOf(m, 2).factories).toBe(1)
		end
	)

	T.it(
		"ПВО в составе войск: при доле AAFullShare урон с воздуха меньше на AAMaxReduction",
		function()
			T.expect(Air.aaReduction({ 1, 0, 0, 0 })).toBe(0)
			T.expect(Air.aaReduction({ 0.7, 0, 0, 0.3 })).toBeNear(cfg.AAMaxReduction, 1e-9)
			T.expect(Air.aaReduction({ 0.85, 0, 0, 0.15 })).toBeNear(cfg.AAMaxReduction / 2, 1e-9)
			local function lost(aa: number): number
				local m = duo()
				DevTools.warNow(m, 1, 2)
				local airfield = place(m, "Airfield", 75)
				hire(m, 1, "Bomber", airfield)
				local front = frontOf(m, 2, 1, 3000 - aa, aa)
				freezeFronts(m)
				runFor(m, 0.2)
				local before = Forces.total(front.forces)
				MatchSim.applyIntent(m, 1, { kind = "raid", cell = 12 * W + BORDER + 3 })
				runFor(m, 30 / Air.speed("Bomber", W) + 0.3)
				return before - Forces.total(front.forces)
			end
			local plain, covered = lost(0), lost(900)
			T.expect(covered / plain).toBeNear(1 - cfg.AAMaxReduction, 0.05)
		end
	)

	T.it(
		"налёт на линию нашего фронта против врага бьёт его гарнизон",
		function()
			local m = duo()
			DevTools.warNow(m, 1, 2)
			local airfield = place(m, "Airfield", 75)
			hire(m, 1, "Bomber", airfield)
			frontOf(m, 1, 2, 3000)
			freezeFronts(m)
			Forces.add(m.nations[2].home, INF, 5000)
			runFor(m, 0.2)
			local before = Forces.total(m.nations[2].home)
			MatchSim.applyIntent(m, 1, { kind = "raid", cell = 12 * W + BORDER + 2 })
			runFor(m, 30 / Air.speed("Bomber", W) + 0.3)
			local expected = Air.stats("Bomber").attack * cfg.BombDamage * cfg.GarrisonShare
			T.expect(before - Forces.total(m.nations[2].home) >= expected * 0.9).toBeTruthy()
		end
	)

	T.it(
		"истребитель перехватывает бомбардировщик врага; батарея ПВО сбивает самолёт в радиусе",
		function()
			local m = duo()
			DevTools.warNow(m, 1, 2)
			local af1 = place(m, "Airfield", 75)
			local af2 = place(m, "Airfield", 125)
			local fighter = hire(m, 2, "Fighter", af2)
			hire(m, 1, "Bomber", af1)
			MatchSim.takeEvents(m)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "raid", cell = 12 * W + 125 }))).toBe(true)
			runFor(m, 25)
			local shot = events(m, "planeShot")
			T.expect(#shot).toBe(1)
			T.expect(shot[1].nation).toBe(1)
			T.expect(shot[1].by).toBe(2)
			T.expect(fighter.alive).toBe(true)
			-- Батарея ПВО державы 2 у границы: новый бомбардировщик 1 сбит без истребителей.
			local m2 = duo()
			DevTools.warNow(m2, 1, 2)
			local airfield = place(m2, "Airfield", 75)
			place(m2, "AirDefense", 115)
			hire(m2, 1, "Bomber", airfield)
			MatchSim.takeEvents(m2)
			MatchSim.applyIntent(m2, 1, { kind = "raid", cell = 12 * W + 115 })
			runFor(m2, 30)
			T.expect(#events(m2, "planeShot")).toBe(1)
		end
	)

	T.it(
		"сеть AIR и туман: чужой самолёт вдали не уходит; выведенные из строя здания — всем",
		function()
			local m = duo()
			local af2 = place(m, "Airfield", 185)
			local far = hire(m, 2, "Fighter", af2)
			local mine = MatchStats.air(m, 1)
			for _, p in mine.planes do
				T.expect(p.id ~= far.id).toBeTruthy()
			end
			T.expect(#MatchStats.air(m, nil).planes).toBe(1)
			m.air.disabled[af2] = m.simTime + 30
			local msg = MatchStats.air(m, 2)
			local decoded = Protocol.decodeAir(Protocol.encodeAir(msg))
			T.expect(#decoded.planes).toBe(1)
			T.expect(decoded.planes[1].kind).toBe("Fighter")
			T.expect(decoded.planes[1].x).toBeNear(msg.planes[1].x, 1 / 32)
			T.expect(decoded.planes[1].hp).toBeNear(1, 1e-9)
			T.expect(decoded.disabled[1].cell).toBe(af2)
			T.expect(decoded.disabled[1].left).toBe(30)
		end
	)

	T.it(
		"намерения авиации проверяются; панель F4: авиация себе и налёт бота",
		function()
			T.expect((Intents.parse("plane", { plane = "Bomber", airfield = 3 }))).toEqual({
				kind = "plane",
				plane = "Bomber",
				airfield = 3,
			})
			T.expect(select(2, Intents.parse("plane", { plane = "Zeppelin", airfield = 3 }))).toBe("bad plane")
			T.expect(select(2, Intents.parse("cover", { plane = 0, cell = 3 }))).toBe("bad cover")
			local m = duo()
			T.expect((DevTools.airForce(m, 1))).toBe(true)
			T.expect(#Air.ofNation(m.air, 1)).toBe(2)
			frontOf(m, 1, 2, 3000)
			runFor(m, 0.2)
			T.expect((DevTools.botRaid(m, 2, 1))).toBe(true)
			local bombers = Air.ofNation(m.air, 2)
			T.expect(#bombers).toBe(1)
			T.expect(bombers[1].state).toBe("flying")
		end
	)
	T.it(
		"бот-Агрессор в войне: аэродром, бомбардировщик и налёт на линию фронта",
		function()
			local m = duo()
			MatchSim.setBot(m, 1, "Normal", "Aggressor")
			Tech.grant(m.tech, 1, "Fleet", 3)
			local n = m.nations[1]
			place(m, "Factory", 5)
			DevTools.warNow(m, 1, 2)
			frontOf(m, 2, 1, 2000)
			freezeFronts(m)
			local raided = false
			for _ = 1, 180 do
				runFor(m, 1)
				n.money = math.max(n.money, 30000)
				n.oil = math.max(n.oil, 500)
				for _, e in MatchSim.takeEvents(m) do
					if e.kind == "raid" and e.nation == 1 then
						raided = true
					end
				end
				if raided then
					break
				end
			end
			T.expect(#MatchSim.buildingsOf(m, "Airfield") >= 1).toBeTruthy()
			T.expect(raided).toBe(true)
		end
	)

	T.it(
		"Генерал под бомбами: нанимает истребители и прикрывает место налёта; сбитый самолёт — с координатами",
		function()
			local m = duo()
			MatchSim.setBot(m, 2, "General", "Peaceful")
			local general = m.nations[2]
			place(m, "Airfield", 135) -- аэродром Генерала: место налёта в радиусе его авиации
			local airfield = place(m, "Airfield", 75)
			local bomber = hire(m, 1, "Bomber", airfield)
			DevTools.warNow(m, 1, 2)
			frontOf(m, 2, 1, 2000)
			freezeFronts(m)
			runFor(m, 0.2)
			local target = 12 * W + BORDER + 3
			T.expect((MatchSim.applyIntent(m, 1, { kind = "raid", cell = target }))).toBe(true)
			local covered, shot = false, nil :: any
			for _ = 1, 120 do
				runFor(m, 1)
				general.money = math.max(general.money, 30000)
				general.oil = math.max(general.oil, 500)
				for _, e in MatchSim.takeEvents(m) do
					if e.kind == "planeShot" and shot == nil then
						shot = e
					end
				end
				for _, p in Air.ofNation(m.air, 2) do
					if p.kind == "Fighter" and p.cover == m.bombedCell[2] then
						covered = true
					end
				end
				if covered and shot ~= nil then
					break
				end
				-- Бомбардировщик вернулся — снова в налёт, пока Генерал не прикроет.
				if bomber.state == "based" then
					MatchSim.applyIntent(m, 1, { kind = "raid", cell = target })
				end
			end
			T.expect(m.bombedCell[2] ~= nil).toBe(true)
			T.expect(covered).toBe(true)
			T.expect(shot ~= nil).toBe(true)
			T.expect(type(shot.x) == "number" and type(shot.y) == "number").toBe(true)
		end
	)
end)
