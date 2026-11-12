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
local MapFormat = require("../src/shared/MapFormat")
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
			T.expect(hit[1].cells > 0).toBe(true)
			T.expect(hit[1].radius).toBe(MatchSim.warheadRadius(m, "missile")) -- §15р: радиус — в событии для клиента
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

T.describe("Ядерные удары (§15ж)", function()
	T.it(
		"атомная: цена, удар только по врагу, своя земля цела, заражение не даёт брать землю",
		function()
			local m = duo()
			DevTools.silo(m, 1)
			DevTools.warNow(m, 1, 2)
			local atom = Config.Nukes.Atom
			local r = MatchSim.warheadRadius(m, "atom")
			T.expect(r >= 3).toBe(true)
			-- Цель у самой границы: часть круга — своя земля (x ≤ 60), она не задевается.
			local target = 16 * W + 62
			m.nations[1].money = 0
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "missile", cell = target, warhead = "atom" })))
				.toBe("noMoney")
			m.nations[1].money = 100000
			local garrison = Forces.total(m.nations[2].home)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "missile", cell = target, warhead = "atom" }))).toBe(true)
			T.expect(m.nations[1].money).toBe(100000 - atom.cost)
			local launched = events(m, "missileLaunched")
			T.expect(launched[1].warhead).toBe("atom")
			T.expect(launched[1].impactIn).toBe(atom.warningSec)
			runFor(m, atom.warningSec + 0.5)
			T.expect(Grid.getOwner(m.grid, target)).toBe(0)
			T.expect(Grid.getOwner(m.grid, 16 * W + 60)).toBe(1) -- своя клетка в круге цела
			T.expect(Forces.total(m.nations[2].home) < garrison).toBe(true)
			T.expect(MatchSim.inFallout(m, target)).toBe(true)
			T.expect(#(MatchStats.world(m, 1).fallout or {})).toBe(1)
			-- Заражённую ничью землю нельзя взять: цена клетки — бесконечность, расширение её пропускает.
			runFor(m, atom.falloutSec + 1)
			T.expect(MatchSim.inFallout(m, target)).toBe(false)
		end
	)

	T.it(
		"водородная — только с Войска-4; ПВО сбивает бомбу, если хватает зарядов, иначе заряды целы",
		function()
			local m = duo()
			DevTools.silo(m, 1)
			DevTools.warNow(m, 1, 2)
			local target = 16 * W + 100
			Tech.removeNation(m.tech, 1) -- F4 «шахта» даёт всё; оставим Войска-3
			Tech.grant(m.tech, 1, "Army", 3)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "missile", cell = target, warhead = "hydrogen" })))
				.toBe("needTech")
			-- Батарея ур. 1 у цели: 1 заряд — на атомную (нужно 2) не хватает, заряд не тратится, бомба падает.
			local p = m.provinces.list[11]
			Buildings.place(m.buildings, "AirDefense", p.center, 11)
			MatchSim.refreshOwned(m)
			T.expect((MatchSim.batteryCharges(m, p.center))).toBe(1)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "missile", cell = p.center + 1, warhead = "atom" })))
				.toBe(true)
			runFor(m, Config.Nukes.Atom.warningSec + 0.5)
			T.expect(#events(m, "nukeHit")).toBe(1)
			-- «Сеть ПВО» (+1 заряд) и новая батарея: 2 заряда — атомная сбита, оба заряда потрачены.
			Tech.grant(m.tech, 2, "Fleet", 4)
			local q = m.provinces.list[10]
			Buildings.place(m.buildings, "AirDefense", q.center, 10)
			MatchSim.refreshOwned(m)
			Grid.setOwner(m.grid, q.center + 1, 2)
			m.missileReady[1] = nil
			local before = (MatchSim.batteryCharges(m, q.center))
			T.expect(before >= 2).toBe(true)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "missile", cell = q.center + 1, warhead = "atom" })))
				.toBe(true)
			runFor(m, Config.Nukes.Atom.warningSec + 0.5)
			T.expect(#events(m, "missileShot")).toBe(1)
			T.expect((MatchSim.batteryCharges(m, q.center))).toBe(before - 2)
			-- С Войска-4 водородная разрешена.
			Tech.grant(m.tech, 1, "Army", 4)
			m.missileReady[1] = nil
			-- Цель — любая клетка врага (§15р: круги прошлых ударов зависят от размера держав).
			local enemyCell = 16 * W + 110
			for i = 0, W * H - 1 do
				if Grid.getOwner(m.grid, i) == 2 then
					enemyCell = i
					break
				end
			end
			T.expect((MatchSim.applyIntent(m, 1, { kind = "missile", cell = enemyCell, warhead = "hydrogen" })))
				.toBe(true)
			T.expect(MatchSim.warheadRadius(m, "hydrogen") > MatchSim.warheadRadius(m, "atom")).toBe(true)
		end
	)

	T.it(
		"§15р: радиус бомб — по средней живой державе, в пределах 0.4–1.0 прежнего; ракета постоянная",
		function()
			local function match(mapName: string, nations: number): MatchSim.Match
				local map = MapFormat.fromModule((require :: any)("../maps/" .. mapName) :: MapFormat.MapModule)
				local m = MatchSim.new(map, 1)
				m.targetNations = nations
				return m
			end
			local function oldRadius(m: MatchSim.Match, nuke: any): number
				return nuke.radius * m.grid.width / Config.UnitsReferenceMapWidth
			end
			local function expected(m: MatchSim.Match, nuke: any, perNation: number): number
				local old = oldRadius(m, nuke)
				local r = math.sqrt(nuke.area * perNation / math.pi)
				return math.round(math.clamp(r, old * Config.Nukes.RadiusMinScale, old * Config.Nukes.RadiusMaxScale))
			end
			local atomCfg, hydrogenCfg = Config.Nukes.Atom, Config.Nukes.Hydrogen
			-- До начала игры — суша карты / держав матча.
			local eu = match("Europe", 12)
			T.expect(MatchSim.warheadRadius(eu, "missile")).toBe(Config.Buildings.MissileSilo.strikeRadius)
			T.expect(MatchSim.warheadRadius(eu, "atom")).toBe(expected(eu, atomCfg, eu.grid.capturableCount / 12))
			T.expect(MatchSim.warheadRadius(eu, "hydrogen"))
				.toBe(expected(eu, hydrogenCfg, eu.grid.capturableCount / 12))
			-- «Мир», 24 державы: держава мельче — круг меньше прежнего, но не меньше нижнего предела; ракета та же.
			local w = match("World", 24)
			local wAtom = MatchSim.warheadRadius(w, "atom")
			T.expect(wAtom < oldRadius(w, atomCfg)).toBe(true)
			T.expect(wAtom >= math.floor(oldRadius(w, atomCfg) * Config.Nukes.RadiusMinScale)).toBe(true)
			T.expect(MatchSim.warheadRadius(w, "hydrogen") > wAtom).toBe(true)
			T.expect(MatchSim.warheadRadius(w, "missile")).toBe(Config.Buildings.MissileSilo.strikeRadius)
			-- Дуэль: средняя держава огромна — круг не больше прежнего (верхний предел 1.0).
			local duel = match("Europe", 2)
			T.expect(MatchSim.warheadRadius(duel, "atom")).toBe(math.round(oldRadius(duel, atomCfg)))
			-- В игре — средняя суша живых держав: две державы по 10 000 клеток.
			MatchSim.addPlayer(eu, 1, "A")
			MatchSim.addPlayer(eu, 2, "B")
			local given = { 0, 0 }
			for i = 0, eu.grid.size - 1 do
				if Grid.isCapturable(eu.grid, i) then
					local k = if given[1] < 10000 then 1 elseif given[2] < 10000 then 2 else 0
					if k == 0 then
						break
					end
					Grid.setOwner(eu.grid, i, k)
					given[k] += 1
				end
			end
			T.expect(MatchSim.warheadRadius(eu, "atom")).toBe(expected(eu, atomCfg, 10000))
		end
	)

	T.it(
		"эмодзи: картинка из списка, не чаще Emoji.MinGapSec; разбор намерения",
		function()
			local m = duo()
			T.expect((Intents.parse("emoji", { target = 2, emoji = 1 }))).toBeTruthy()
			T.expect((Intents.parse("emoji", { target = 2, emoji = #Config.Emoji.List + 1 }))).toBe(nil)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "emoji", target = 2, emoji = 3 }))).toBe(true)
			local got = events(m, "emoji")
			T.expect(#got).toBe(1)
			T.expect(got[1].emoji).toBe(3)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "emoji", target = 2, emoji = 1 }))).toBe("tooSoon")
			runFor(m, Config.Emoji.MinGapSec + 0.1)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "emoji", target = 2, emoji = 1 }))).toBe(true)
		end
	)
end)

T.describe("Дальняя ПВО и «часы судного дня» (§15з → §15х ч.6)", function()
	T.it(
		"ПВО ур. 3 — дальняя: сбивает ракету, ур. N — N зарядов; ур. 3 открывает Флот-3",
		function()
			local m = duo()
			DevTools.silo(m, 1)
			DevTools.warNow(m, 1, 2)
			local p = m.provinces.list[12]
			Buildings.place(m.buildings, "AirDefense", p.center, 12)
			m.buildings.byCell[p.center].level = 2
			T.expect(MatchSim.levelAllows(m, 2, "AirDefense", 3)).toBe(false)
			Tech.grant(m.tech, 2, "Fleet", 3)
			T.expect(MatchSim.levelAllows(m, 2, "AirDefense", 3)).toBe(true)
			m.buildings.byCell[p.center].level = 3
			MatchSim.refreshOwned(m)
			T.expect(MatchSim.ownedOf(m, 2).longRange).toBe(1)
			T.expect((MatchSim.batteryCharges(m, p.center))).toBe(3 * Config.Defense.ChargesPerLevel)
			-- Цель в 9 клетках от ПВО у столицы врага (x 115): сбита, потрачен один заряд.
			local target = 16 * W + 106
			T.expect((MatchSim.applyIntent(m, 1, { kind = "missile", cell = target }))).toBe(true)
			runFor(m, silo.warningSec + 0.5)
			local shot = events(m, "missileShot")
			T.expect(#shot).toBe(1)
			T.expect(shot[1].at).toBe(p.center)
			T.expect((MatchSim.batteryCharges(m, p.center))).toBe(3 * Config.Defense.ChargesPerLevel - 1)
			T.expect(Config.Buildings.AirDefense.longRadius > Config.Buildings.AirDefense.radius).toBe(true)
		end
	)

	T.it(
		"планка растёт волнами; держава ниже планки 30 с распадается, самая большая — никогда",
		function()
			local m = duo()
			local cfg = Config.Doomsday
			T.expect(m.rules.doomsday).toBe(true)
			local start = m.rules.timeLimitSec * cfg.StartShare
			m.time = start - 1
			T.expect((MatchSim.doomBar(m))).toBe(0)
			m.time = start + cfg.WaveSec + 1
			local bar, wave = MatchSim.doomBar(m)
			T.expect(wave).toBe(2)
			T.expect(bar).toBe(cfg.Shares[2])
			-- Держава 2 почти без земли: оставим ей 3 клетки у столицы.
			for y = 1, H - 2 do
				for x = 61, 120 do
					Grid.setOwner(m.grid, y * W + x, 0)
				end
			end
			local cap2 = m.nations[2].capital :: number
			Grid.setOwner(m.grid, cap2, 2)
			Grid.setOwner(m.grid, cap2 + 1, 2)
			Grid.setOwner(m.grid, cap2 - 1, 2)
			m.doomCheckAt = 0
			MatchSim.stepDoomsday(m)
			local warned = events(m, "doomWarning")
			T.expect(#warned).toBe(1)
			T.expect(warned[1].nation).toBe(2)
			T.expect(m.nations[1].alive).toBe(true) -- самая большая не под угрозой
			T.expect(#(MatchStats.world(m, 1).doom :: any).marked).toBe(1)
			m.time += cfg.GraceSec + 1
			m.doomCheckAt = 0
			MatchSim.stepDoomsday(m)
			T.expect(m.nations[2].alive).toBe(false)
			T.expect(#events(m, "doomCollapse")).toBe(1)
			T.expect(Grid.getOwner(m.grid, cap2)).toBe(0)
		end
	)

	T.it("нет в «Обучении» и «Дуэли»; мобилизация 5 с", function()
		local Modes = require("../src/shared/Modes")
		T.expect(Modes.rules("Tutorial").doomsday).toBe(false)
		T.expect(Modes.rules("Duel").doomsday).toBe(false)
		T.expect(Modes.rules("Ffa").doomsday).toBe(true)
		T.expect(Config.War.MobilizationSec).toBe(5)
	end)
end)
