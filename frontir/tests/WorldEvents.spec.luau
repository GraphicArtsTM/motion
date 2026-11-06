--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local Council = require("../src/shared/Council")
local DevTools = require("../src/shared/DevTools")
local Fleet = require("../src/shared/Fleet")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")
local Rng = require("../src/shared/Rng")
local Stability = require("../src/shared/Stability")
local Tech = require("../src/shared/Tech")
local Types = require("../src/shared/Types")
local WorldEvents = require("../src/shared/WorldEvents")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
local TANKS = Forces.kindIndex("Tanks") :: number
local ev = Config.Events
local silo = Config.Buildings.MissileSilo
-- Карта 160×32: море по краю, держава 1 — x 1..60, держава 2 — x 61..120, дальше — ничья земля.
local W, H = 160, 32

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

local function events(m: MatchSim.Match, kind: string): { any }
	local out = {}
	for _, e in MatchSim.takeEvents(m) do
		if e.kind == kind then
			table.insert(out, e)
		end
	end
	return out
end

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

T.describe("Случайные события", function()
	T.it(
		"расписание: первое через FirstSec, дальше MinGap..MaxGap; выбор по весам и с фильтром",
		function()
			local st = WorldEvents.new()
			local rng = Rng.new(3)
			T.expect(WorldEvents.due(st, 0, rng)).toBe(false)
			T.expect(st.nextAt).toBe(ev.FirstSec)
			T.expect(WorldEvents.due(st, ev.FirstSec - 1, rng)).toBe(false)
			T.expect(WorldEvents.due(st, ev.FirstSec, rng)).toBe(true)
			local gap = st.nextAt - ev.FirstSec
			T.expect(gap >= ev.MinGapSec and gap <= ev.MaxGapSec).toBe(true)
			local seen: { [string]: boolean } = {}
			for _ = 1, 200 do
				seen[WorldEvents.pick(rng) :: string] = true
			end
			for _, kind in WorldEvents.Kinds do
				T.expect(seen[kind]).toBe(true)
			end
			T.expect(WorldEvents.pick(rng, function(k: string): boolean
				return k == "Harvest"
			end)).toBe("Harvest")
			-- В партии: первое событие — на FirstSec.
			local m = duo()
			runFor(m, ev.FirstSec + 1)
			T.expect(#events(m, "worldEvent")).toBe(1)
		end
	)

	T.it(
		"нефтяная лихорадка: новое нефтяное поле, на нём можно ставить вышку",
		function()
			local m = duo()
			for _, p in m.provinces.list do
				(p :: any).oil = false
			end
			T.expect(MatchSim.worldEvent(m, "OilRush")).toBe(true)
			local p = m.world.oilExtra[1]
			T.expect(p ~= nil).toBe(true)
			T.expect(m.provinces.list[p].oil).toBe(true)
			local e = events(m, "worldEvent")
			T.expect(e[1].event).toBe("OilRush")
			T.expect(e[1].province).toBe(p)
			local owner = Grid.getOwner(m.grid, m.provinces.list[p].center)
			if owner ~= 0 then
				T.expect(
					(
						MatchSim.applyIntent(
							m,
							owner,
							{ kind = "build", building = "OilRig", cell = m.provinces.list[p].center }
						)
					)
				).toBe(true)
			end
		end
	)

	T.it(
		"шторм: круг на море, корабль не входит в него и стоит внутри до конца шторма",
		function()
			local m = duo()
			T.expect(MatchSim.worldEvent(m, "Storm")).toBe(true)
			local storm = m.world.storm :: WorldEvents.Storm
			T.expect(storm.radius).toBe(ev.StormRadius * W / Config.UnitsReferenceMapWidth)
			T.expect(WorldEvents.inStorm(m.world, W, storm.cell % W + 0.5, storm.cell // W + 0.5, m.simTime)).toBe(true)
			-- Корабль идёт сквозь шторм: стоит у края.
			local fs = Fleet.new()
			local ship = Fleet.spawn(fs, W, 1, "Transport", 0, storm.cell)
			ship.x, ship.y = storm.cell % W + 0.5 - storm.radius - 2, storm.cell // W + 0.5
			ship.path = { storm.cell }
			ship.step = 1
			ship.state = "moving"
			local blocked = function(x: number, y: number): boolean
				return WorldEvents.inStorm(m.world, W, x, y, m.simTime)
			end
			local x0 = ship.x
			Fleet.move(fs, W, 5, {}, blocked)
			T.expect(ship.x).toBe(x0)
			runFor(m, ev.StormSec + 1)
			T.expect(m.world.storm).toBe(nil)
			Fleet.move(fs, W, 1, {}, blocked)
			T.expect(ship.x > x0).toBe(true)
		end
	)

	T.it("урожай: прирост людей ×1.2 на 60 с", function()
		local function grown(harvest: boolean): number
			local m = duo()
			m.nations[1].people = 1000
			if harvest then
				MatchSim.worldEvent(m, "Harvest")
			end
			runFor(m, 0.5)
			return m.nations[1].people - 1000
		end
		local plain, rich = grown(false), grown(true)
		T.expect(rich / plain).toBeNear(ev.HarvestMul, 0.03)
	end)

	T.it(
		"наёмники: ставки (мин., шаг, деньги), бот перебивает, победитель платит и получает войска 2★",
		function()
			local m = duo()
			MatchSim.setBot(m, 2, "Normal", "Trader")
			-- Предел бота ровно минимальная ставка: доля денег BotBidShare × bidShare Торговца.
			local trader = Config.BotPersonalities.Trader :: any
			m.nations[2].money = ev.MercMinBid / (ev.BotBidShare * (trader.bidShare or 1))
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "bid", amount = 5000 }))).toBe("noAuction")
			MatchSim.worldEvent(m, "Mercenaries")
			local a = m.world.auction :: WorldEvents.Auction
			T.expect(a.topId).toBe(2) -- бот поставил сразу
			T.expect(a.top).toBe(ev.MercMinBid)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "bid", amount = a.top }))).toBe("lowBid")
			local n = m.nations[1]
			local myBid = ev.MercMinBid + ev.MercStep
			n.money = myBid - 1
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "bid", amount = myBid }))).toBe("noMoney")
			n.money = 100000
			T.expect((MatchSim.applyIntent(m, 1, { kind = "bid", amount = myBid }))).toBe(true)
			-- Бот перебил бы, но его предел — минимальная ставка: ставка остаётся за игроком.
			T.expect(a.topId).toBe(1)
			local inf = n.home[INF].strength
			runFor(m, ev.AuctionSec + 0.5)
			T.expect(m.world.auction).toBe(nil)
			T.expect(n.money >= 100000 - myBid and n.money < 100000 - myBid + 1000).toBe(true) -- ставка списана (+ доход)
			T.expect(n.home[INF].strength).toBeNear(inf + ev.MercStrength * 2 / 3, 1e-6)
			T.expect(n.home[TANKS].strength).toBeNear(ev.MercStrength / 3, 1e-6)
			T.expect(Forces.stars(n.home[TANKS])).toBe(ev.MercStars)
			local e = events(m, "mercs")
			T.expect(e[#e].nation).toBe(1)
		end
	)

	T.it("восстание у лидера и перебежчики к слабейшему", function()
		local m = duo()
		for x = 121, 158 do
			for y = 1, H - 2 do
				Grid.setOwner(m.grid, y * W + x, 2) -- держава 2 — лидер
			end
		end
		runFor(m, Config.Stability.UpdateSec + 0.5)
		MatchSim.takeEvents(m)
		T.expect(MatchSim.worldEvent(m, "Revolt")).toBe(true)
		local revolts = MatchSim.takeEvents(m)
		local revolted = false
		for _, e in revolts do
			if e.kind == "revolt" and e.nation == 2 then
				revolted = true
			end
		end
		T.expect(revolted).toBe(true)
		local weak = m.nations[1].home[INF].strength
		T.expect(MatchSim.worldEvent(m, "Defectors")).toBe(true)
		T.expect(m.nations[1].home[INF].strength).toBe(weak + ev.DefectorStrength)
	end)
end)

T.describe("Ракетная шахта", function()
	T.it(
		"пуск: нужна шахта и война; перезарядка; запрет Совета; удар через 10 с — круг ничей, фронты −50%",
		function()
			local m = duo()
			local n = m.nations[1]
			local target = 16 * W + 90
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "missile", cell = target }))).toBe("needSilo")
			-- Строить шахту — только с «Ракетной шахтой» (Войска-4).
			local p = m.provinces.list[3]
			T.expect(
				select(2, MatchSim.applyIntent(m, 1, { kind = "build", building = "MissileSilo", cell = p.center }))
			)
				.toBe("needTech")
			Tech.grant(m.tech, 1, "Army", 4)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "build", building = "MissileSilo", cell = p.center })))
				.toBe(true)
			T.expect(MatchSim.ownedOf(m, 1).silos).toBe(1)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "missile", cell = target }))).toBe("notAtWar")
			DevTools.warNow(m, 1, 2)
			Council.addActive(m.council, "superweaponBan", m.simTime + 10)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "missile", cell = target }))).toBe("banned")
			m.council.active = {}
			local front = frontOf(m, 2, 1, 1000)
			local lineCell = (front.line :: { number })[5] + 1 -- клетка врага у линии фронта
			T.expect((MatchSim.applyIntent(m, 1, { kind = "missile", cell = lineCell }))).toBe(true)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "missile", cell = target }))).toBe("cooldown")
			local launched = events(m, "missileLaunched")
			T.expect(#launched).toBe(1)
			T.expect(launched[1].impactIn).toBe(silo.warningSec)
			runFor(m, silo.warningSec - 0.5)
			T.expect(Grid.getOwner(m.grid, lineCell)).toBe(2)
			runFor(m, 1)
			T.expect(Grid.getOwner(m.grid, lineCell)).toBe(0)
			T.expect(Forces.total(front.forces) <= 500 + 1e-6).toBe(true)
			local hit = events(m, "missileHit")
			T.expect(#hit).toBe(1)
			T.expect(hit[1].cells > 50).toBe(true)
			T.expect(MatchStats.world(m, 1).missileLeft > 0).toBe(true)
			local _ = n
		end
	)

	T.it(
		"удар по столице — столица потеряна; сеть ПВО (Флот-4) сбивает ракеты над своей батареей",
		function()
			local m = duo()
			DevTools.silo(m, 1)
			DevTools.warNow(m, 1, 2)
			local cap2 = m.nations[2].capital :: number
			T.expect((MatchSim.applyIntent(m, 1, { kind = "missile", cell = cap2 }))).toBe(true)
			runFor(m, silo.warningSec + 0.5)
			T.expect(Grid.getOwner(m.grid, cap2)).toBe(0)
			T.expect(m.nations[2].capital ~= cap2).toBe(true)
			-- Заряды ПВО (§15д ч.3, без случайности): батарея ур. 1 + «Сеть ПВО» — 2 заряда: две ракеты подряд
			-- сбиты, третья (заряды ещё не восстановились) — попадает.
			Tech.grant(m.tech, 2, "Fleet", 4)
			local p = m.provinces.list[10]
			Buildings.place(m.buildings, "AirDefense", p.center, 10)
			MatchSim.refreshOwned(m)
			T.expect(select(2, MatchSim.batteryCharges(m, p.center))).toBe(2)
			local results: { string } = {}
			for _ = 1, 3 do
				m.missileReady[1] = nil
				MatchSim.applyIntent(m, 1, { kind = "missile", cell = p.center + 1 })
				runFor(m, silo.warningSec + 0.2)
				table.insert(results, if #events(m, "missileShot") > 0 then "shot" else "hit")
				Grid.setOwner(m.grid, p.center + 1, 2)
				Grid.setOwner(m.grid, p.center, 2)
			end
			T.expect(table.concat(results, ",")).toBe("shot,shot,hit")
		end
	)

	T.it(
		"боты: строят шахту с технологией и пускают ракеты в войне; F4 — событие сейчас, шахта, ракета бота",
		function()
			local m = duo()
			MatchSim.setBot(m, 2, "General", "Aggressor")
			Tech.grant(m.tech, 2, "Army", 4)
			m.nations[2].money = 200000
			DevTools.warNow(m, 2, 1)
			frontOf(m, 2, 1, 3000)
			local launched = 0
			for _ = 1, 90 do
				runFor(m, 1)
				m.nations[2].money = math.max(m.nations[2].money, 200000)
				launched += #events(m, "missileLaunched")
				if launched > 0 then
					break
				end
			end
			T.expect(MatchSim.ownedOf(m, 2).silos).toBe(1)
			T.expect(launched > 0).toBe(true)

			local m2 = duo()
			T.expect((DevTools.eventNow(m2))).toBe(true)
			T.expect(#events(m2, "worldEvent")).toBe(1)
			T.expect((DevTools.botMissile(m2, 2, 1))).toBe(true)
			T.expect(#m2.missiles).toBe(1)
		end
	)

	T.it(
		"сеть: намерения bid и missile; сообщение world и разбор на клиенте",
		function()
			local b = Intents.parse("bid", { amount = 2500.7 })
			T.expect(b ~= nil and b.kind == "bid" and b.amount == 2500).toBe(true)
			T.expect((Intents.parse("bid", { amount = -5 }))).toBe(nil)
			T.expect((Intents.parse("missile", { cell = "x" }))).toBe(nil)
			local m = duo()
			MatchSim.worldEvent(m, "Storm")
			MatchSim.worldEvent(m, "Mercenaries")
			MatchSim.worldEvent(m, "OilRush")
			local msg = MatchStats.world(m, 1)
			T.expect(msg.storm ~= nil).toBe(true)
			T.expect(msg.auction ~= nil and msg.auction.minBid == ev.MercMinBid).toBe(true)
			local cs = ClientState.new(W, H)
			local fresh = ClientState.applyWorld(cs, msg, 0)
			T.expect(#fresh).toBe(1)
			T.expect(#ClientState.applyWorld(cs, msg, 1)).toBe(0) -- уже известно
			T.expect(cs.world.storm ~= nil).toBe(true)
			ClientState.applyWorld(cs, "junk", 2)
			T.expect(cs.world.storm ~= nil).toBe(true)
			local _ = Stability
		end
	)
end)
