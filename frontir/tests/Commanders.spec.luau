--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local ClientState = require("../src/shared/ClientState")
local Commanders = require("../src/shared/Commanders")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local Fog = require("../src/shared/Fog")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")
local Tech = require("../src/shared/Tech")
local Types = require("../src/shared/Types")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
local cfg = Config.Commanders
-- Карта 160×32: море по краю (кольцо воды > Naval.MinSeaCells), держава 1 — x 1..60, держава 2 — x 61..120,
-- дальше — ничья земля. Провинции — полосы по 10 клеток.
local W, H = 160, 32

local function duo(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 9)
	m.victory = false
	MatchSim.addPlayer(m, 1, "N1")
	MatchSim.addPlayer(m, 2, "N2")
	m.phase = "Play"
	for y = 1, H - 2 do
		for x = 1, 120 do
			Grid.setOwner(m.grid, y * W + x, if x <= 60 then 1 else 2)
		end
	end
	local caps = { 16 * W + 5, 16 * W + 115 }
	for _, n in m.nations do
		n.colorIndex = n.id
		n.people = 50000
		n.money = 100000
		n.oil = 5000
		n.capital = caps[n.id]
		Grid.setCity(m.grid, caps[n.id], true)
		m.cityOf[-n.id] = caps[n.id]
		Forces.add(n.home, INF, 3000)
	end
	return m
end

local function runFor(m: MatchSim.Match, seconds: number)
	for _ = 1, math.floor(seconds * Config.Sim.TickRate + 0.5) do
		MatchSim.step(m, DT)
	end
end

local function use(m: MatchSim.Match, id: number, slot: number, cell: number?, percent: number?): (boolean, string?)
	return MatchSim.applyIntent(m, id, { kind = "ability", slot = slot, cell = cell, percent = percent })
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

-- Фронт attacker → target у границы x=60 с готовой линией (как после stepAttacks).
local function frontOf(m: MatchSim.Match, attacker: number, target: number, strength: number): Types.Attack
	local forces = Forces.new()
	Forces.add(forces, INF, strength)
	local line: { number } = {}
	for y = 10, 22 do
		table.insert(line, y * W + (if target == 2 then 61 else 60))
	end
	local a: Types.Attack = {
		attacker = attacker,
		target = target,
		troops = 0,
		focus = 16 * W + 60,
		forces = forces,
		supplied = true,
		ratio = 1,
		fighting = false,
		lastAdvance = m.simTime,
		line = line,
	}
	table.insert(m.attacks, a)
	return a
end

local function count(m: MatchSim.Match, id: number): number
	return Grid.cellsOf(m.grid, id)
end

T.describe("Генералы: выбор и пассивки", function()
	T.it(
		"выбор в лобби и выборе старта, в игре — нельзя; по умолчанию Маршал; боты — по личности",
		function()
			local m = duo()
			T.expect(Commanders.of(m.commanders, 1)).toBe("Marshal")
			m.phase = "Lobby"
			T.expect((MatchSim.applyIntent(m, 1, { kind = "commander", commander = "Scout" }))).toBe(true)
			m.phase = "Pick"
			T.expect((MatchSim.applyIntent(m, 1, { kind = "commander", commander = "Engineer" }))).toBe(true)
			m.phase = "Play"
			local ok, reason = MatchSim.applyIntent(m, 1, { kind = "commander", commander = "Admiral" })
			T.expect(ok).toBe(false)
			T.expect(reason).toBe("phase")
			T.expect(Commanders.of(m.commanders, 1)).toBe("Engineer")
			MatchSim.setBot(m, 2, "Normal", "Admiral")
			T.expect(Commanders.of(m.commanders, 2)).toBe("Admiral")
			MatchSim.setBot(m, 2, "Normal", "Cunning")
			T.expect(Commanders.of(m.commanders, 2)).toBe("Scout")
			T.expect(Commanders.forPersonality("Trader")).toBe("Engineer")
			T.expect(Commanders.forPersonality("Aggressor")).toBe("Marshal")
			-- Намерения.
			local c = Intents.parse("commander", { commander = "Admiral" })
			T.expect(c ~= nil and c.kind == "commander").toBe(true)
			T.expect((Intents.parse("commander", { commander = "Pirate" }))).toBe(nil)
			local a = Intents.parse("ability", { slot = 2, cell = 10, percent = 0.3 })
			T.expect(a ~= nil and a.kind == "ability" and a.slot == 2).toBe(true)
			T.expect((Intents.parse("ability", { slot = 3 }))).toBe(nil)
			T.expect((Intents.parse("ability", { slot = 1, percent = 2 }))).toBe(nil)
			T.expect((Intents.parse("ability", { slot = 1, cell = -4 }))).toBe(nil)
		end
	)

	T.it(
		"Маршал — танки, Адмирал — корабли (с «Верфями» тоже), Инженер — здания дешевле",
		function()
			local m = duo()
			local tanks = Forces.kindIndex("Tanks") :: number
			T.expect(MatchSim.unitCost(m, 1, tanks)).toBeNear(Config.Units.Tanks.cost * (1 - cfg.TankDiscount), 1e-6)
			T.expect(MatchSim.unitCost(m, 1, INF)).toBe(Config.Units.Infantry.cost)
			Commanders.choose(m.commanders, 1, "Admiral")
			T.expect(MatchSim.unitCost(m, 1, tanks)).toBe(Config.Units.Tanks.cost)
			local ship = Config.Units.Transport.cost
			T.expect(MatchSim.shipCost(m, 1, "Transport")).toBeNear(ship * (1 - cfg.ShipDiscount), 1e-6)
			Tech.grant(m.tech, 1, "Fleet", 1)
			T.expect(MatchSim.shipCost(m, 1, "Transport"))
				.toBeNear(ship * (1 - cfg.ShipDiscount) * (1 - Config.Tech.ShipyardDiscount), 1e-6)

			Commanders.choose(m.commanders, 1, "Engineer")
			local n = m.nations[1]
			local money = n.money
			local cell = m.provinces.list[3].center
			T.expect((MatchSim.applyIntent(m, 1, { kind = "build", building = "Factory", cell = cell }))).toBe(true)
			T.expect(money - n.money).toBeNear(Config.Buildings.Factory.cost * (1 - cfg.BuildDiscount), 1e-6)
		end
	)

	T.it(
		"Разведчик видит дальше (клиент и сервер), порты Адмирала — +2 клетки обзора",
		function()
			local m = duo()
			local friends = { [1] = true }
			local function visible(sources: Fog.Sources): number
				local fs = Fog.new(W, H)
				Fog.compute(fs, m.grid.owner, sources)
				local n = 0
				for i = 0, W * H - 1 do
					n += buffer.readu8(fs.visible, i)
				end
				return n
			end
			local plain = visible({ friends = friends, fronts = {}, radars = {} })
			local scout = visible({ friends = friends, fronts = {}, radars = {}, visionMul = cfg.VisionMul })
			T.expect(scout > plain).toBe(true)
			-- Порт у края своей земли (x=58): обзор за границей дальше на PortVision.
			local port = 16 * W + 60
			local admiral = visible({ friends = friends, fronts = {}, radars = {}, ports = { port } })
			T.expect(admiral > plain).toBe(true)

			local function blocks(): number
				local n = 0
				for _ in MatchStats.vision(m, 1).blocks do
					n += 1
				end
				return n
			end
			local before = blocks()
			Commanders.choose(m.commanders, 1, "Scout")
			T.expect(blocks() >= before).toBe(true)
		end
	)
end)

T.describe("Генералы: способности", function()
	T.it(
		"перезарядка: Прорыв ×1.5 на 15 с, повтор — отказ, событие в ленте; F4 сбрасывает",
		function()
			local m = duo()
			T.expect((use(m, 1, 2))).toBe(true)
			T.expect(MatchSim.surgeMul(m, 1)).toBe(cfg.SurgeMul)
			T.expect(MatchSim.surgeMul(m, 2)).toBe(1)
			local ok, reason = use(m, 1, 2)
			T.expect(ok).toBe(false)
			T.expect(reason).toBe("cooldown")
			local e = events(m, "ability")
			T.expect(#e).toBe(1)
			T.expect(e[1].ability).toBe("Surge")
			runFor(m, cfg.SurgeSec + 0.5)
			T.expect(MatchSim.surgeMul(m, 1)).toBe(1)
			T.expect(Commanders.left(m.commanders, 1, 2, m.simTime) > 0).toBe(true)
			T.expect((DevTools.resetCooldowns(m, 1))).toBe(true)
			T.expect((use(m, 1, 2))).toBe(true)
			-- Вне игры — нельзя.
			m.phase = "Over"
			T.expect(select(2, use(m, 1, 1, 16 * W + 61))).toBe("phase")
		end
	)

	T.it(
		"Авиаудар: фронт врага в круге теряет 25%, оборона врага у круга ×0.7 на 15 с; без врага — отказ",
		function()
			local m = duo()
			DevTools.warNow(m, 1, 2)
			local enemyFront = frontOf(m, 2, 1, 1000)
			local myFront = frontOf(m, 1, 2, 1000)
			local ok, reason = use(m, 1, 1, 16 * W + 20) -- своя земля, врага рядом нет
			T.expect(ok).toBe(false)
			T.expect(reason).toBe("noEnemy")
			T.expect((use(m, 1, 1, 16 * W + 61))).toBe(true)
			T.expect(Forces.total(enemyFront.forces)).toBeNear(1000 * (1 - cfg.StrikeLoss), 1e-6)
			T.expect(Forces.total(myFront.forces)).toBe(1000)
			T.expect(MatchSim.abilityDefenseMul(m, myFront)).toBe(cfg.StrikeDefenseMul)
			T.expect(MatchSim.abilityDefenseMul(m, enemyFront)).toBe(1)
			m.simTime += cfg.StrikeSec + 1
			runFor(m, DT)
			T.expect(MatchSim.abilityDefenseMul(m, myFront)).toBe(1)
		end
	)

	T.it(
		"Морской десант (Адмирал): плацдарм на чужом берегу без кораблей; не берег — отказ",
		function()
			local m = duo()
			Commanders.choose(m.commanders, 1, "Admiral")
			local n = m.nations[1]
			local before, home = count(m, 1), Forces.total(n.home)
			local ok, reason = use(m, 1, 1, 16 * W + 140, 0.3) -- ничья земля, но далеко от моря
			T.expect(ok).toBe(false)
			T.expect(reason).toBe("notCoast")
			T.expect((use(m, 1, 1, 1 * W + 140, 0.3))).toBe(true) -- ничья земля у моря
			T.expect(count(m, 1) > before).toBe(true)
			T.expect(Forces.total(n.home)).toBeNear(home * 0.7, 1e-6)
			-- Своя клетка — не цель.
			DevTools.resetCooldowns(m, 1)
			T.expect(select(2, use(m, 1, 1, 1 * W + 30, 0.3))).toBe("target")
		end
	)

	T.it(
		"Воздушный десант (Инженер): не больше 20% пехоты, плацдарм r=3 в любой точке; мало войск — отказ",
		function()
			local m = duo()
			Commanders.choose(m.commanders, 1, "Engineer")
			DevTools.warNow(m, 1, 2)
			local n = m.nations[1]
			local before2 = count(m, 2)
			T.expect((use(m, 1, 2, 16 * W + 100, 1))).toBe(true) -- вглубь врага
			T.expect(n.home[INF].strength).toBeNear(3000 * (1 - cfg.AirdropShare), 1e-6)
			T.expect(count(m, 2) < before2).toBe(true)
			local opened = false
			for _, a in m.attacks do
				if a.attacker == 1 and a.target == 2 then
					opened = true
				end
			end
			T.expect(opened).toBe(true)
			DevTools.resetCooldowns(m, 1)
			n.home[INF].strength = 100
			T.expect(select(2, use(m, 1, 2, 16 * W + 140, 1))).toBe("noTroops")
			T.expect(n.home[INF].strength).toBe(100)
		end
	)

	T.it(
		"Укрепрайон: своя провинция, оборона ×2 на линиях у неё; чужая клетка — отказ",
		function()
			local m = duo()
			Commanders.choose(m.commanders, 1, "Engineer")
			DevTools.warNow(m, 1, 2)
			local enemyFront = frontOf(m, 2, 1, 1000) -- линия по x=60 (провинция 7 державы 1)
			T.expect(select(2, use(m, 1, 1, 16 * W + 80))).toBe("notOwner")
			T.expect((use(m, 1, 1, 16 * W + 60))).toBe(true)
			T.expect(MatchSim.abilityDefenseMul(m, enemyFront)).toBe(cfg.FortMul)
		end
	)

	T.it(
		"Блокада (Адмирал): порты врага в круге выведены из строя на 30 с; нет порта — отказ",
		function()
			local m = duo()
			Commanders.choose(m.commanders, 1, "Admiral")
			DevTools.warNow(m, 1, 2)
			T.expect(select(2, use(m, 1, 2, 16 * W + 90))).toBe("noEnemy")
			local p = m.provinces.list[9]
			Buildings.place(m.buildings, "Port", p.center, 9)
			MatchSim.refreshOwned(m)
			T.expect((use(m, 1, 2, p.center))).toBe(true)
			T.expect(MatchSim.isDisabled(m, p.center)).toBe(true)
			runFor(m, cfg.BlockadeSec + 1)
			T.expect(MatchSim.isDisabled(m, p.center)).toBe(false)
		end
	)

	T.it(
		"Разведчик: вспышка — всё видно 10 с; пропаганда −30 стабильности врагу",
		function()
			local m = duo()
			Commanders.choose(m.commanders, 1, "Scout")
			DevTools.warNow(m, 1, 2)
			runFor(m, Config.Stability.UpdateSec + 0.5) -- стабильность провинций посчитана
			T.expect((use(m, 1, 1))).toBe(true)
			T.expect(MatchSim.revealing(m, 1)).toBe(true)
			T.expect(MatchStats.commander(m, 1).reveal).toBe(cfg.RevealSec)
			local p = MapData.getProvince(m.map, 16 * W + 95)
			local before = m.stability.provinces[p].value
			T.expect((use(m, 1, 2, 16 * W + 95))).toBe(true)
			T.expect(m.stability.provinces[p].value).toBe(math.max(0, before - cfg.PropagandaLoss))
			-- Свои провинции не трогает.
			local mine = MapData.getProvince(m.map, 16 * W + 55)
			T.expect(m.stability.provinces[mine].owner).toBe(1)
			runFor(m, cfg.RevealSec + 1)
			T.expect(MatchSim.revealing(m, 1)).toBe(false)
		end
	)

	T.it(
		"боты применяют способности в войне; F4: следующий генерал, бот — способности по вам",
		function()
			local m = duo()
			MatchSim.setBot(m, 2, "General", "Aggressor")
			DevTools.warNow(m, 1, 2)
			frontOf(m, 2, 1, 2000)
			local used = 0
			for _ = 1, 60 do
				runFor(m, 1)
				used += #events(m, "ability")
				if used > 0 then
					break
				end
			end
			T.expect(used > 0).toBe(true)

			local m2 = duo()
			MatchSim.setBot(m2, 2, "Normal", "Cunning") -- Разведчик
			T.expect((DevTools.botAbility(m2, 2, 1))).toBe(true)
			T.expect(MatchSim.revealing(m2, 2)).toBe(true)
			T.expect((DevTools.nextCommander(m2, 1))).toBe(true)
			T.expect(Commanders.of(m2.commanders, 1)).toBe("Admiral")
		end
	)

	T.it(
		"сообщение commander: генерал, перезарядки, эффекты; клиент не верит мусору",
		function()
			local m = duo()
			use(m, 1, 2)
			local msg = MatchStats.commander(m, 1)
			T.expect(msg.commander).toBe("Marshal")
			T.expect(msg.left[2]).toBe(cfg.Cooldown.Marshal[2])
			T.expect(msg.left[1]).toBe(0)
			T.expect(msg.surge).toBe(cfg.SurgeSec)
			local cs = ClientState.new(W, H)
			ClientState.applyCommander(cs, msg, 0)
			T.expect(cs.commander.left[2]).toBe(cfg.Cooldown.Marshal[2])
			ClientState.applyCommander(cs, { kind = "commander", commander = "Pirate", left = { 1, 2 } }, 0)
			T.expect(cs.commander.commander).toBe("Marshal")
			ClientState.applyCommander(cs, { kind = "commander", commander = "Scout", left = { "x" }, reveal = 5 }, 0)
			T.expect(cs.commander.commander).toBe("Scout")
			T.expect(cs.commander.left[1]).toBe(0)
			T.expect(ClientState.revealLeft(cs, 2) > 0).toBe(true)
		end
	)
end)
