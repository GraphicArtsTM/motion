--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local BotBrain = require("../src/shared/BotBrain")
local Buildings = require("../src/shared/Buildings")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local Diplomacy = require("../src/shared/Diplomacy")
local Forces = require("../src/shared/Forces")
local Fronts = require("../src/shared/Fronts")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")
local Rng = require("../src/shared/Rng")
local Stability = require("../src/shared/Stability")
local Tech = require("../src/shared/Tech")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
local TANKS = Forces.kindIndex("Tanks") :: number
local cfg = Config.Tech
-- Две державы на полосах-провинциях по 10 клеток: 1 — x 1..60, 2 — x 61..120.
local W, H = 128, 16

local function duo(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 7)
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

local function research(m: MatchSim.Match, id: number, branch: Tech.Branch): (boolean, string?)
	return MatchSim.applyIntent(m, id, { kind = "research", branch = branch })
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

-- Вид бота для выбора технологии: только то, что нужно techChoice.
local function techView(levels: { Army: number, Economy: number, Fleet: number }, money: number?): any
	return {
		money = money or 1e6,
		tech = { Army = levels.Army, Economy = levels.Economy, Fleet = levels.Fleet, researching = false },
	}
end

T.describe("Технологии", function()
	T.it(
		"исследование: деньги сразу, одно за раз, уровень через Sec, событие в ленте",
		function()
			local m = duo()
			local n = m.nations[1]
			local money = n.money
			T.expect((research(m, 1, "Army"))).toBe(true)
			T.expect(n.money).toBe(money - cfg.Cost[1])
			local ok, reason = research(m, 1, "Economy")
			T.expect(ok).toBe(false)
			T.expect(reason).toBe("researching")
			runFor(m, cfg.Sec[1] - 1)
			T.expect(Tech.level(m.tech, 1, "Army")).toBe(0)
			runFor(m, 1.5)
			T.expect(Tech.level(m.tech, 1, "Army")).toBe(1)
			local done = events(m, "researched")
			T.expect(#done).toBe(1)
			T.expect(done[1].nation).toBe(1)
			T.expect(done[1].branch).toBe("Army")
			T.expect(done[1].level).toBe(1)
			-- Следующий уровень — дороже.
			money = n.money
			T.expect((research(m, 1, "Army"))).toBe(true)
			T.expect(m.tech.research[1].level).toBe(2)
			T.expect(m.tech.research[1].total).toBe(cfg.Sec[2])
			T.expect(math.floor(money - n.money + 0.5)).toBe(cfg.Cost[2])
		end
	)

	T.it(
		"закрытые уровни, изученная ветка, нет денег; чужая держава не затронута",
		function()
			local m = duo()
			Tech.grant(m.tech, 1, "Army", cfg.Locked.Army - 1)
			local ok, reason = research(m, 1, "Army")
			T.expect(ok).toBe(false)
			T.expect(reason).toBe("techLocked")
			Tech.grant(m.tech, 1, "Economy", #cfg.Cost)
			ok, reason = research(m, 1, "Economy")
			T.expect(ok).toBe(false)
			T.expect(reason).toBe("techMaxed")
			m.nations[1].money = cfg.Cost[1] - 1
			ok, reason = research(m, 1, "Fleet")
			T.expect(ok).toBe(false)
			T.expect(reason).toBe("noMoney")
			T.expect(m.tech.research[1]).toBe(nil)
			T.expect(Tech.level(m.tech, 2, "Army")).toBe(0)
			T.expect(Tech.isLocked("Fleet", cfg.Locked.Fleet)).toBe(true)
			T.expect(Tech.isLocked("Economy", 4)).toBe(false)
		end
	)

	T.it("намерение research проверяется", function()
		local intent = Intents.parse("research", { branch = "Fleet" })
		T.expect(intent ~= nil and intent.kind == "research" and intent.branch == "Fleet").toBe(true)
		local bad, reason = Intents.parse("research", { branch = "Magic" })
		T.expect(bad).toBe(nil)
		T.expect(reason ~= nil).toBe(true)
		T.expect((Intents.parse("research", {}))).toBe(nil)
	end)

	T.it("Учебка: новобранцы с 1★", function()
		local m = duo()
		local n = m.nations[1]
		n.home = Forces.new()
		T.expect((MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Infantry" }))).toBe(true)
		runFor(m, Forces.stats(INF).recruitSec + 0.5)
		T.expect(Forces.stars(n.home[INF])).toBe(0)
		n.home = Forces.new()
		Tech.grant(m.tech, 1, "Army", 1)
		T.expect((MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Infantry" }))).toBe(true)
		runFor(m, Forces.stats(INF).recruitSec + 0.5)
		T.expect(Forces.stars(n.home[INF])).toBe(1)
	end)

	T.it(
		"Снабжение: дальше ×SupplyRangeMul; Тяжёлая броня: танки в обороне ×TankArmor",
		function()
			local m = duo()
			local range = Config.Combat.SupplyRange * W / Config.UnitsReferenceMapWidth
			-- Линия фронта дальше обычной дальности, но ближе увеличенной.
			local x = 5 + math.floor(range * (1 + cfg.SupplyRangeMul) / 2)
			local front = { 8 * W + x }
			local cities = { m.nations[1].capital :: number }
			T.expect(Fronts.supplied(m.grid, cities, 1, front)).toBe(false)
			T.expect(Fronts.supplied(m.grid, cities, 1, front, nil, cfg.SupplyRangeMul)).toBe(true)

			local tanks = Forces.new()
			Forces.add(tanks, TANKS, 100)
			local enemy = Forces.new()
			Forces.add(enemy, INF, 100)
			local plain = Forces.power(tanks, enemy, "defense")
			T.expect(Forces.power(tanks, enemy, "defense", cfg.TankArmor)).toBeNear(plain * cfg.TankArmor, 1e-6)
			T.expect(Forces.power(tanks, enemy, "attack", cfg.TankArmor)).toBe(Forces.power(tanks, enemy, "attack"))
			local inf = Forces.new()
			Forces.add(inf, INF, 100)
			T.expect(Forces.power(inf, enemy, "defense", cfg.TankArmor)).toBe(Forces.power(inf, enemy, "defense"))
		end
	)

	T.it(
		"Налоги, Нефтедобыча, Торговые пути: доход, нефть, бонус соглашений",
		function()
			local m = duo()
			Buildings.place(m.buildings, "OilRig", m.provinces.list[3].center, 3)
			MatchSim.refreshOwned(m)
			Diplomacy.signTrade(m.diplo, 1, 2, m.simTime)
			runFor(m, 0.5)
			local base = m.economy[1].income
			local oil = m.economy[1].oilIncome
			T.expect(oil > 0).toBe(true)
			Tech.grant(m.tech, 1, "Economy", 1)
			runFor(m, 0.5)
			T.expect(m.economy[1].income).toBeNear(base * (1 + cfg.TaxBonus), base * 0.01)
			Tech.grant(m.tech, 1, "Economy", 2)
			runFor(m, 0.5)
			T.expect(m.economy[1].oilIncome).toBeNear(oil * (1 + cfg.OilBonus), 1e-6)
			Tech.grant(m.tech, 1, "Economy", 3)
			runFor(m, 0.5)
			local trade = Config.Trade.AgreementIncome
			local expected = base * (1 + cfg.TaxBonus) * (1 + trade * cfg.TradeMul) / (1 + trade)
			T.expect(m.economy[1].income).toBeNear(expected, base * 0.01)
			-- У второй державы без технологий — как было.
			T.expect(m.economy[2].oilIncome).toBe(0)
		end
	)

	T.it("Порядок: целевая стабильность +OrderStability", function()
		local m = duo()
		local ctx = MatchSim.stabilityContext(m)
		local p = 4 -- не столица
		local before = Stability.target(ctx, p, 1, m.simTime)
		Tech.grant(m.tech, 1, "Economy", 4)
		local after = Stability.target(ctx, p, 1, m.simTime)
		T.expect(after).toBe(math.min(100, before + cfg.OrderStability))
		T.expect(after > before).toBe(true)
	end)

	T.it(
		"Верфи — скидка на корабли; Радар и Авиация открывают здания",
		function()
			local m = duo()
			local full = MatchSim.shipCost(m, 1, "Transport")
			Tech.grant(m.tech, 1, "Fleet", 1)
			T.expect(MatchSim.shipCost(m, 1, "Transport")).toBeNear(full * (1 - cfg.ShipyardDiscount), 1e-6)
			T.expect(MatchSim.shipCost(m, 2, "Transport")).toBe(full)

			local cell = m.provinces.list[3].center
			T.expect(MatchSim.techAllows(m, 1, "Radar")).toBe(false)
			T.expect(MatchSim.techAllows(m, 1, "Airfield")).toBe(false)
			T.expect(MatchSim.techAllows(m, 1, "Factory")).toBe(true)
			T.expect(MatchSim.techAllows(m, 1, "AirDefense")).toBe(true)
			local ok, reason = MatchSim.applyIntent(m, 1, { kind = "build", building = "Radar", cell = cell })
			T.expect(ok).toBe(false)
			T.expect(reason).toBe("needTech")
			Tech.grant(m.tech, 1, "Fleet", 2)
			T.expect(MatchSim.techAllows(m, 1, "Radar")).toBe(true)
			T.expect(MatchSim.techAllows(m, 1, "Airfield")).toBe(false)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "build", building = "Radar", cell = cell }))).toBe(true)
			Tech.grant(m.tech, 1, "Fleet", 3)
			T.expect(MatchSim.techAllows(m, 1, "Airfield")).toBe(true)
		end
	)

	T.it(
		"боты: порядок по личности, Генерал — по очереди, Новичок — случайно; без денег — нет",
		function()
			local rng = Rng.new(1)
			local zero = { Army = 0, Economy = 0, Fleet = 0 }
			T.expect(BotBrain.techChoice(techView(zero), BotBrain.profile("Normal", "Aggressor"), rng)).toBe("Army")
			T.expect(BotBrain.techChoice(techView(zero), BotBrain.profile("Normal", "Trader"), rng)).toBe("Economy")
			T.expect(BotBrain.techChoice(techView(zero), BotBrain.profile("Normal", "Admiral"), rng)).toBe("Fleet")
			-- Войска-4 закрыта: Агрессор после трёх уровней войск — экономика.
			local army3 = { Army = 3, Economy = 0, Fleet = 0 }
			T.expect(BotBrain.techChoice(techView(army3), BotBrain.profile("Normal", "Aggressor"), rng)).toBe("Economy")
			-- Генерал: Учебка → Налоги → Снабжение → Авиация (Флот 1..3) …
			local general = BotBrain.profile("General", "Aggressor")
			T.expect(BotBrain.techChoice(techView(zero), general, rng)).toBe("Army")
			T.expect(BotBrain.techChoice(techView({ Army = 1, Economy = 0, Fleet = 0 }), general, rng)).toBe("Economy")
			T.expect(BotBrain.techChoice(techView({ Army = 1, Economy = 1, Fleet = 0 }), general, rng)).toBe("Army")
			T.expect(BotBrain.techChoice(techView({ Army = 2, Economy = 1, Fleet = 0 }), general, rng)).toBe("Fleet")
			-- Денег меньше цены и запаса — нет.
			local poor = techView(zero, cfg.Cost[1])
			T.expect(BotBrain.techChoice(poor, BotBrain.profile("Normal", "Aggressor"), rng)).toBe(nil)
			-- Новичок: любая открытая ветка; всё изучено — ничего.
			local seen: { [string]: boolean } = {}
			for _ = 1, 40 do
				local b = BotBrain.techChoice(techView(zero), BotBrain.profile("Novice", "Peaceful"), rng)
				if b ~= nil then
					seen[b] = true
				end
			end
			T.expect(seen.Army and seen.Economy and seen.Fleet).toBe(true)
			local full = { Army = 3, Economy = 4, Fleet = 3 }
			T.expect(BotBrain.techChoice(techView(full), BotBrain.profile("Novice", "Peaceful"), rng)).toBe(nil)
		end
	)

	T.it("бот в партии сам исследует и тратит деньги", function()
		local m = duo()
		MatchSim.setBot(m, 2, "Normal", "Trader")
		for _ = 1, 60 do
			runFor(m, 1)
			m.nations[2].money = math.max(m.nations[2].money, 50000)
			if Tech.level(m.tech, 2, "Economy") >= 1 then
				break
			end
		end
		T.expect(Tech.level(m.tech, 2, "Economy") >= 1).toBe(true)
	end)

	T.it(
		"панель F4: изучить всё (кроме закрытых) и закончить исследование; выбывшая держава забыта",
		function()
			local m = duo()
			T.expect((DevTools.finishResearch(m, 1))).toBe(false)
			T.expect((research(m, 1, "Fleet"))).toBe(true)
			T.expect((DevTools.finishResearch(m, 1))).toBe(true)
			runFor(m, DT)
			T.expect(Tech.level(m.tech, 1, "Fleet")).toBe(1)
			T.expect(#events(m, "researched")).toBe(1)
			T.expect((DevTools.researchAll(m, 1))).toBe(true)
			T.expect(Tech.level(m.tech, 1, "Army")).toBe(cfg.Locked.Army - 1)
			T.expect(Tech.level(m.tech, 1, "Economy")).toBe(#cfg.Cost)
			T.expect(Tech.level(m.tech, 1, "Fleet")).toBe(cfg.Locked.Fleet - 1)
			Tech.removeNation(m.tech, 1)
			T.expect(Tech.level(m.tech, 1, "Economy")).toBe(0)
		end
	)

	T.it(
		"сообщение tech: свои уровни и исследование; клиент разбирает и не верит мусору",
		function()
			local m = duo()
			Tech.grant(m.tech, 1, "Economy", 2)
			T.expect((research(m, 1, "Army"))).toBe(true)
			runFor(m, 2)
			local msg = MatchStats.tech(m, 1)
			T.expect(msg.levels.Economy).toBe(2)
			T.expect(msg.levels.Army).toBe(0)
			local r = msg.research
			T.expect(r ~= nil and r.branch == "Army" and r.level == 1 and r.total == cfg.Sec[1]).toBe(true)
			T.expect(r ~= nil and r.left == cfg.Sec[1] - 2).toBe(true)
			T.expect(MatchStats.tech(m, 2).levels.Economy).toBe(0)

			local cs = ClientState.new(W, H)
			ClientState.applyTech(cs, msg)
			T.expect(cs.tech.levels.Economy).toBe(2)
			T.expect(cs.tech.research ~= nil).toBe(true)
			ClientState.applyTech(
				cs,
				{ kind = "tech", levels = { Army = 99, Economy = "x" }, research = { branch = "Z" } }
			)
			T.expect(cs.tech.levels.Army).toBe(#cfg.Cost)
			T.expect(cs.tech.levels.Economy).toBe(0)
			T.expect(cs.tech.research).toBe(nil)
			ClientState.applyTech(cs, "junk")
			T.expect(cs.tech.levels.Army).toBe(#cfg.Cost)
		end
	)
end)
