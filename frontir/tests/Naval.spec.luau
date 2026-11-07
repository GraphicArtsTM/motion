--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local Diplomacy = require("../src/shared/Diplomacy")
local Fleet = require("../src/shared/Fleet")
local Types = require("../src/shared/Types")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Modes = require("../src/shared/Modes")
local MatchStats = require("../src/shared/Net/MatchStats")
local Protocol = require("../src/shared/Net/Protocol")
local Naval = require("../src/shared/Naval")
local Wars = require("../src/shared/Wars")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
local cfg = Config.Naval
-- Ширина 512 — эталонная: дальности флота не масштабируются. Два острова через пролив:
-- левый x 2..60 (держава 1), правый x 100..160 (держава 2 или ничей), остальное — море.
local W, H = 512, 24
local LEFT0, LEFT1, RIGHT0, RIGHT1 = 2, 60, 100, 160

local function provinceAt(x: number, y: number): number
	local band = if y < 8 then 0 elseif y < 16 then 1 else 2
	if x <= LEFT1 then
		return 7 * band + x // 10 + 1
	end
	return 21 + 7 * band + (x - RIGHT0) // 10 + 1
end

local function islands(rightOwner: number): MatchSim.Match
	local rows: { string } = {}
	for y = 0, H - 1 do
		local row = table.create(W, "~")
		if y >= 2 and y <= H - 3 then
			for x = LEFT0, LEFT1 do
				row[x + 1] = "."
			end
			for x = RIGHT0, RIGHT1 do
				row[x + 1] = "."
			end
		end
		table.insert(rows, table.concat(row))
	end
	local map = TinyMap.fromRows(rows)
	-- Провинции: блоки 10 клеток по x, три ряда по y; средний ряд внутри острова — без выхода к морю.
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, provinceAt(i % W, i // W))
		end
	end
	local m = MatchSim.new(map, 7)
	m.victory = false
	MatchSim.addPlayer(m, 1, "N1")
	MatchSim.addPlayer(m, 2, "N2")
	m.phase = "Play"
	for i = 0, W * H - 1 do
		local x = i % W
		if MapData.getTerrain(map, i) ~= 0 then
			if x <= LEFT1 then
				Grid.setOwner(m.grid, i, 1)
			elseif rightOwner ~= 0 then
				Grid.setOwner(m.grid, i, rightOwner)
			end
		end
	end
	local caps = { 12 * W + 10, 12 * W + 150 }
	for _, n in m.nations do
		n.colorIndex = n.id
		n.people = 5000
		n.money = 50000
		n.oil = 2000
		n.capital = caps[n.id]
		Grid.setCity(m.grid, caps[n.id], true)
		m.cityOf[-n.id] = caps[n.id]
	end
	if rightOwner == 0 then
		m.nations[2].alive = false
	end
	return m
end

local function runFor(m: MatchSim.Match, seconds: number)
	for _ = 1, math.floor(seconds * Config.Sim.TickRate + 0.5) do
		MatchSim.step(m, DT)
	end
end

-- Порт державы в провинции у берега, обращённого к проливу (x 60 у левого, x 100 у правого).
local function port(m: MatchSim.Match, id: number): number
	local province = if id == 1 then provinceAt(LEFT1, 12) else provinceAt(RIGHT0, 12)
	local p = m.provinces.list[province]
	Buildings.place(m.buildings, "Port", p.center, province)
	MatchSim.refreshOwned(m)
	return p.center
end

local function eventsOf(m: MatchSim.Match, kind: string): { any }
	local out = {}
	for _, e in MatchSim.takeEvents(m) do
		if e.kind == kind then
			table.insert(out, e)
		end
	end
	return out
end

local function hire(m: MatchSim.Match, id: number, kind: Types.ShipKind, at: number): Fleet.Ship
	T.expect((MatchSim.applyIntent(m, id, { kind = "ship", ship = kind, port = at }))).toBe(true)
	runFor(m, Fleet.stats(kind).recruitSec + 0.2)
	local ships = Fleet.ofNation(m.fleet, id)
	return ships[#ships]
end

T.describe("Флот", function()
	T.it(
		"десант на другой берег (§15д): нажатие на ничий остров — корабль сам плывёт и высаживается, без порта",
		function()
			local m = islands(0)
			local n = m.nations[1]
			local target = 12 * W + 130 -- середина правого острова
			T.expect(MatchSim.overSea(m, 1, target)).toBe(true)
			T.expect(MatchSim.overSea(m, 1, 12 * W + 30)).toBe(false) -- свой остров
			T.expect(#MatchSim.portsOf(m, 1)).toBe(0)
			local people = n.people
			T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 0, percent = 0.5, focus = target })))
				.toBe(true)
			T.expect(Fleet.boats(m.fleet, 1)).toBe(1)
			T.expect(Fleet.count(m.fleet, 1)).toBe(0) -- в лимит кораблей порта не входит
			T.expect(n.people < people).toBe(true)
			local events = MatchSim.takeEvents(m)
			local launched = false
			for _, e in events do
				launched = launched or e.kind == "boatLaunched"
			end
			T.expect(launched).toBe(true)
			runFor(m, 60)
			T.expect(Fleet.boats(m.fleet, 1)).toBe(0) -- высадился и исчез
			local mine = 0
			for x = RIGHT0, RIGHT1 do
				if Grid.getOwner(m.grid, 12 * W + x) == 1 then
					mine += 1
				end
			end
			T.expect(mine > 0).toBe(true)
		end
	)

	T.it(
		"десант на вражеский остров в войне: войска плывут фронтом; лимит десантов; нет берега у моря — отказ",
		function()
			local m = islands(2)
			local n = m.nations[1]
			Forces.add(n.home, INF, 3000)
			DevTools.warNow(m, 1, 2)
			local target = 12 * W + 120
			T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 0.2, focus = target })))
				.toBe(true)
			for _ = 2, cfg.MaxBoats do
				MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 0.1, focus = target })
			end
			T.expect(Fleet.boats(m.fleet, 1)).toBe(cfg.MaxBoats)
			T.expect(
				select(2, MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 0.1, focus = target }))
			)
				.toBe("tooManyBoats")
			-- Фронт открывается после высадки; без гарнизона у врага он может взять остров целиком (§15м — быстро).
			local front = false
			for _ = 1, 60 do
				runFor(m, 1)
				for _, a in m.attacks do
					front = front or (a.attacker == 1 and a.target == 2)
				end
			end
			T.expect(front).toBe(true)
			-- Земля на острове за морем (без города и порта) не сдаётся как котёл — снабжается морем.
			T.expect(Grid.getOwner(m.grid, 12 * W + RIGHT0) == 1 or Grid.getOwner(m.grid, 3 * W + RIGHT0) == 1)
				.toBe(true)
			-- Без своего берега у моря — отказ (свежий матч: остров врага могли уже взять целиком).
			m = islands(2)
			Forces.add(m.nations[1].home, INF, 3000)
			DevTools.warNow(m, 1, 2)
			for i = 0, W * H - 1 do
				if Grid.getOwner(m.grid, i) == 1 then
					Grid.setOwner(m.grid, i, 0)
				end
			end
			Grid.setOwner(m.grid, 12 * W + 30, 1) -- одна клетка в глубине острова, провинции не наши
			T.expect(
				select(2, MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 0.1, focus = target }))
			)
				.toBe("noCoast")
		end
	)

	T.it("море, причалы и путь по воде без суши", function()
		local m = islands(2)
		local s = m.sea
		local coastal = s.docks[provinceAt(LEFT1, 12)]
		T.expect(coastal ~= nil).toBeTruthy()
		T.expect(Naval.seaAt(s, coastal :: number) > 0).toBeTruthy()
		-- Путь от причала левого острова до моря у правого — вокруг ничего нет, но точки только по морю.
		local to = 12 * W + RIGHT0 - 1
		local path = Naval.path(s, coastal :: number, to) :: { number }
		T.expect(path ~= nil).toBeTruthy()
		T.expect(path[#path]).toBe(to)
		local prev = coastal :: number
		for _, p in path do
			local x0, y0, x1, y1 = prev % W, prev // W, p % W, p // W
			local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
			for k = 0, steps do
				local x = x0 + math.round((x1 - x0) * k / math.max(1, steps))
				local y = y0 + math.round((y1 - y0) * k / math.max(1, steps))
				T.expect(Naval.seaAt(s, y * W + x) > 0).toBeTruthy()
			end
			prev = p
		end
		-- В обход острова: от моря севернее левого острова к морю южнее — путь есть.
		T.expect(Naval.path(s, 0 * W + 30, (H - 1) * W + 30) ~= nil).toBeTruthy()
	end)

	T.it(
		"порт — только у моря; найм корабля стоит денег, корабль встаёт у причала",
		function()
			local m = islands(2)
			local inland, coast = provinceAt(30, 12), provinceAt(LEFT1, 12)
			T.expect(m.sea.docks[inland]).toBe(nil)
			local build = { kind = "build", building = "Port", cell = m.provinces.list[inland].center }
			T.expect(select(2, MatchSim.applyIntent(m, 1, build :: any))).toBe("needCoast")
			build.cell = m.provinces.list[coast].center
			T.expect((MatchSim.applyIntent(m, 1, build :: any))).toBe(true)
			local at = m.provinces.list[coast].center
			local money = m.nations[1].money
			T.expect((MatchSim.applyIntent(m, 1, { kind = "ship", ship = "Transport", port = at }))).toBe(true)
			T.expect(m.nations[1].money).toBe(money - Fleet.stats("Transport").cost)
			T.expect(#Fleet.ofNation(m.fleet, 1)).toBe(0) -- ещё строится
			runFor(m, Fleet.stats("Transport").recruitSec + 0.2)
			local ship = Fleet.ofNation(m.fleet, 1)[1]
			T.expect(ship.state).toBe("docked")
			T.expect(ship.home).toBe(at)
			T.expect(Fleet.cellOf(W, ship)).toBe(m.sea.docks[coast])
			-- Чужой порт и не порт — нельзя.
			T.expect(select(2, MatchSim.applyIntent(m, 2, { kind = "ship", ship = "Destroyer", port = at })))
				.toBe("needPort")
		end
	)

	T.it(
		"высадка на ничью землю: плацдарм, атака людьми и войсками, транспорт вернулся",
		function()
			local m = islands(0)
			local at = port(m, 1)
			local ship = hire(m, 1, "Transport", at)
			Forces.add(m.nations[1].home, INF, 2000)
			local target = 12 * W + RIGHT0
			T.expect((MatchSim.applyIntent(m, 1, { kind = "land", port = at, target = target, percent = 0.5 })))
				.toBe(true)
			T.expect(Fleet.cargoPower(ship)).toBeNear(cfg.TransportCapacity, 1) -- 50% от 2000 = 1000
			T.expect(ship.people).toBeNear(math.min(cfg.TransportPeople, 2500), 1)
			MatchSim.takeEvents(m)
			runFor(m, 25)
			T.expect(Grid.getOwner(m.grid, target)).toBe(1)
			local landed = eventsOf(m, "landed")
			T.expect(#landed).toBe(1)
			T.expect(landed[1].target).toBe(0)
			-- На правом острове растёт своя земля (атака ничьей земли).
			T.expect(Grid.provinceCells(m.grid, provinceAt(RIGHT0 + 10, 12), 1) > 0).toBeTruthy()
			runFor(m, 30)
			T.expect(ship.state).toBe("docked")
			T.expect(ship.cargo).toBe(nil)
		end
	)

	T.it(
		"высадка на берег врага — только в войне; войска открывают фронт, плацдарм берёт землю",
		function()
			local m = islands(2)
			local at = port(m, 1)
			hire(m, 1, "Transport", at)
			Forces.add(m.nations[1].home, INF, 2000)
			local target = 12 * W + RIGHT0
			T.expect(
				select(2, MatchSim.applyIntent(m, 1, { kind = "land", port = at, target = target, percent = 0.5 }))
			)
				.toBe("notAtWar")
			DevTools.warNow(m, 1, 2)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "land", port = at, target = target, percent = 0.5 })))
				.toBe(true)
			runFor(m, 25)
			T.expect(Grid.getOwner(m.grid, target)).toBe(1)
			local front = nil
			for _, a in m.attacks do
				if a.attacker == 1 and a.target == 2 then
					front = a
				end
			end
			T.expect(front ~= nil).toBeTruthy()
			local war = Wars.find(m.wars, 1, 2) :: Wars.War
			local byA = Wars.takenCells(war, m.grid)
			T.expect(byA > 0).toBeTruthy()
		end
	)

	T.it("эсминец топит транспорт врага вместе с войсками", function()
		local m = islands(2)
		local at1, at2 = port(m, 1), port(m, 2)
		hire(m, 1, "Transport", at1)
		local destroyer = hire(m, 2, "Destroyer", at2)
		DevTools.warNow(m, 1, 2)
		-- Эсминец посреди пролива.
		T.expect((MatchSim.applyIntent(m, 2, { kind = "patrol", ship = destroyer.id, cell = 12 * W + 80 }))).toBe(true)
		runFor(m, 10)
		T.expect(destroyer.state).toBe("patrol")
		Forces.add(m.nations[1].home, INF, 1000)
		MatchSim.applyIntent(m, 1, { kind = "land", port = at1, target = 12 * W + RIGHT0, percent = 0.5 })
		MatchSim.takeEvents(m)
		runFor(m, 20)
		local sunk = eventsOf(m, "shipSunk")
		T.expect(#sunk).toBe(1)
		T.expect(sunk[1].nation).toBe(1)
		T.expect(sunk[1].lost > 0).toBeTruthy()
		T.expect(#Fleet.ofNation(m.fleet, 1)).toBe(0)
	end)

	T.it(
		"обстрел берега: фронт врага у моря в радиусе эсминца теряет силу",
		function()
			local function frontLeft(withDestroyer: boolean): number
				local m = islands(2)
				DevTools.warNow(m, 1, 2)
				local at2 = port(m, 2)
				if withDestroyer then
					local d = hire(m, 2, "Destroyer", at2)
					MatchSim.applyIntent(m, 2, { kind = "patrol", ship = d.id, cell = 12 * W + RIGHT0 - 3 })
					runFor(m, 3)
				end
				-- Плацдарм 1 на берегу 2 и фронт с войсками против 2.
				for y = 10, 14 do
					for x = RIGHT0, RIGHT0 + 3 do
						Grid.setOwner(m.grid, y * W + x, 1)
					end
				end
				local forces = Forces.new()
				Forces.add(forces, INF, 3000)
				table.insert(m.attacks, {
					attacker = 1,
					target = 2,
					troops = 0,
					focus = 12 * W + RIGHT0 + 6,
					forces = forces,
					supplied = true,
					ratio = 1,
					fighting = false,
					lastAdvance = m.simTime,
				})
				runFor(m, 5)
				return Forces.total(forces)
			end
			local calm, shelled = frontLeft(false), frontLeft(true)
			T.expect(shelled < calm - 0.5 * Fleet.stats("Destroyer").attack * cfg.ShoreDamage * 4).toBeTruthy()
		end
	)

	T.it(
		"блокада: эсминец врага у причала — порт не строит корабли и не снабжает",
		function()
			local m = islands(2)
			local at1, at2 = port(m, 1), port(m, 2)
			local destroyer = hire(m, 2, "Destroyer", at2)
			DevTools.warNow(m, 1, 2)
			local dock1 = m.sea.docks[provinceAt(LEFT1, 12)] :: number
			T.expect(#MatchSim.seaSupplySets(m, 1)).toBe(1)
			MatchSim.applyIntent(m, 2, { kind = "patrol", ship = destroyer.id, cell = dock1 + 2 })
			MatchSim.takeEvents(m)
			runFor(m, 15)
			T.expect(m.fleet.blocked[at1]).toBe(true)
			T.expect(#eventsOf(m, "blockade")).toBe(1)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "ship", ship = "Transport", port = at1 })))
				.toBe("blockaded")
			T.expect(#MatchSim.seaSupplySets(m, 1)).toBe(0)
		end
	)

	T.it(
		"плацдарм за морем у берега не сдаётся (§15д) — с портом и без",
		function()
			local function beachhead(withPort: boolean): boolean
				local m = islands(2)
				DevTools.warNow(m, 1, 2)
				if withPort then
					port(m, 1)
				end
				-- Плацдарм державы 1 на правом острове: кусок у берега без города.
				for y = 10, 14 do
					for x = RIGHT0, RIGHT0 + 3 do
						Grid.setOwner(m.grid, y * W + x, 1)
					end
				end
				runFor(m, Config.Pocket.SurrenderSec + 8)
				return Grid.getOwner(m.grid, 12 * W + RIGHT0) == 1
			end
			T.expect(beachhead(true)).toBe(true)
			T.expect(beachhead(false)).toBe(true)
			-- Окружение на своём массиве суши по-прежнему котёл — тест «котёл» в Economy.spec.
		end
	)

	T.it(
		"бот-Флотоводец: порт, транспорт и высадка на ничий остров",
		function()
			local m = islands(0)
			MatchSim.setBot(m, 1, "Normal", "Admiral")
			local n = m.nations[1]
			n.money = 100000
			Buildings.place(m.buildings, "Factory", m.provinces.list[1].center, 1)
			Forces.add(n.home, INF, 2000)
			local landed = false
			for _ = 1, 120 do
				runFor(m, 1)
				n.money = math.max(n.money, 20000)
				for _, e in MatchSim.takeEvents(m) do
					if e.kind == "landed" and e.nation == 1 then
						landed = true
					end
				end
				if landed then
					break
				end
			end
			T.expect(#MatchSim.portsOf(m, 1)).toBe(1)
			T.expect(landed).toBe(true)
		end
	)

	T.it(
		"намерения флота проверяются; панель F4 даёт порт и флот",
		function()
			T.expect((Intents.parse("ship", { ship = "Transport", port = 5 })))
				.toEqual({ kind = "ship", ship = "Transport", port = 5 })
			T.expect(select(2, Intents.parse("ship", { ship = "Battleship", port = 5 }))).toBe("bad ship")
			T.expect(select(2, Intents.parse("land", { port = 1, target = 2, percent = 500 }))).toBe("bad percent")
			T.expect(select(2, Intents.parse("patrol", { ship = 0, cell = 2 }))).toBe("bad patrol")
			local m = islands(2)
			T.expect((DevTools.navy(m, 1))).toBe(true)
			local ships = Fleet.ofNation(m.fleet, 1)
			T.expect(#ships).toBe(2)
			T.expect(#MatchSim.portsOf(m, 1)).toBe(1)
		end
	)
	T.it(
		"сеть: SHIPS кодируется без потерь; чужой корабль вне обзора не уходит, груз — только своим",
		function()
			local m = islands(2)
			m.rules = Modes.withFog("Ffa") -- туман на карте — только в «Мгле» (§6.11а)
			local at1, at2 = port(m, 1), port(m, 2)
			local t = hire(m, 1, "Transport", at1)
			local d = hire(m, 2, "Destroyer", at2)
			Forces.add(m.nations[1].home, INF, 800)
			DevTools.warNow(m, 1, 2)
			MatchSim.applyIntent(m, 1, { kind = "ship", ship = "Destroyer", port = at1 })
			local mine = MatchStats.ships(m, 1)
			T.expect(#mine.queue).toBe(1)
			-- Эсминец 2 у своего причала (x ≈ 99) далеко от земли и кораблей 1 (x ≤ 61): державе 1 не виден.
			local ids: { number } = {}
			for _, s in mine.ships do
				table.insert(ids, s.id)
			end
			T.expect(table.find(ids, t.id) ~= nil).toBeTruthy()
			T.expect(table.find(ids, d.id)).toBe(nil)
			-- Зритель видит всё; держава 2 видит свой эсминец, но не груз чужого транспорта.
			T.expect(#MatchStats.ships(m, nil).ships).toBe(2)
			local decoded = Protocol.decodeShips(Protocol.encodeShips(mine))
			T.expect(#decoded.ships).toBe(#mine.ships)
			T.expect(decoded.ships[1].x).toBeNear(mine.ships[1].x, 1 / 32)
			T.expect(decoded.ships[1].kind).toBe(mine.ships[1].kind)
			T.expect(decoded.queue[1].kind).toBe("Destroyer")
			-- Транспорт с грузом подплывает к врагу: держава 2 видит его, но без груза.
			MatchSim.applyIntent(m, 1, { kind = "land", port = at1, target = 12 * W + RIGHT0, percent = 0.5 })
			-- Подходит к берегу врага (в обзор державы 2), пока эсминец его не потопил.
			for _ = 1, 100 do
				if t.x >= 90 or not t.alive then
					break
				end
				runFor(m, 0.1)
			end
			T.expect(t.alive).toBe(true)
			local theirs = MatchStats.ships(m, 2)
			local seen = false
			for _, s in theirs.ships do
				if s.id == t.id then
					seen = true
					T.expect(s.cargo).toBe(0)
				end
			end
			T.expect(seen).toBe(true)
		end
	)
end)

T.describe("Торговые суда (§15е)", function()
	local tc = Config.TradeShips

	T.it(
		"порт сам отправляет судно в порт другой державы; доплыло — деньги обоим",
		function()
			local m = islands(2)
			local p1, p2 = port(m, 1), port(m, 2)
			local before1, before2 = m.nations[1].money, m.nations[2].money
			runFor(m, tc.EverySec + 1)
			local merchants = 0
			for _, s in m.fleet.ships do
				if s.alive and s.kind == "Merchant" then
					merchants += 1
					local trade = s.trade :: Fleet.Trade
					T.expect(trade.to == p1 or trade.to == p2).toBe(true)
					T.expect(trade.value >= tc.BaseMoney).toBe(true)
				end
			end
			T.expect(merchants).toBe(2) -- по судну из каждого порта
			T.expect(Fleet.count(m.fleet, 1)).toBe(0) -- торговые суда не в лимите кораблей
			local got: { any } = {}
			for _ = 1, 600 do
				MatchSim.step(m, DT)
				for _, e in MatchSim.takeEvents(m) do
					if e.kind == "tradeDelivered" then
						table.insert(got, e)
					end
				end
				if #got >= 2 then
					break
				end
			end
			T.expect(#got).toBe(2)
			local paid = got[1].amount + got[2].amount
			-- Каждая доставка — обоим; содержание и доход за это время тоже идут, поэтому сверяем с запасом.
			T.expect(m.nations[1].money - before1 >= paid * 0.9 - 2000).toBe(true)
			T.expect(m.nations[2].money - before2 >= paid * 0.9 - 2000).toBe(true)
			T.expect(got[1].cell == p1 or got[1].cell == p2).toBe(true)
		end
	)

	T.it(
		"с войной (и объявленной) и с эмбарго — не торгуют; сеть знает вид Merchant",
		function()
			local m = islands(2)
			port(m, 1)
			port(m, 2)
			T.expect(MatchSim.canTrade(m, 1, 2)).toBe(true)
			Diplomacy.setEmbargo(m.diplo, 2, 1, true, m.simTime)
			T.expect(MatchSim.canTrade(m, 1, 2)).toBe(false)
			Diplomacy.setEmbargo(m.diplo, 2, 1, false, m.simTime)
			T.expect(MatchSim.canTrade(m, 1, 2)).toBe(true)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "declare", target = 2 }))).toBe(true)
			T.expect(MatchSim.canTrade(m, 1, 2)).toBe(false)
			runFor(m, tc.EverySec + 1)
			T.expect(Fleet.merchants(m.fleet, 1) + Fleet.merchants(m.fleet, 2)).toBe(0)
			-- Вид судна проходит по сети.
			local ship = Fleet.spawn(m.fleet, W, 1, "Merchant", port(m, 1), 12 * W + 61)
			local msg = MatchStats.ships(m, 1, nil)
			local decoded = Protocol.decodeShips(Protocol.encodeShips(msg))
			local found = false
			for _, s in decoded.ships do
				if s.id == ship.id then
					found = s.kind == "Merchant"
				end
			end
			T.expect(found).toBe(true)
		end
	)

	T.it(
		"пиратство: эсминец врага топит торговое судно и забирает долю груза",
		function()
			local m = islands(2)
			local p1 = port(m, 1)
			local p2 = port(m, 2)
			T.expect((MatchSim.applyIntent(m, 2, { kind = "declare", target = 1 }))).toBe(true)
			runFor(m, Config.War.MobilizationSec + 0.2)
			T.expect(Wars.isActive(m.wars, 1, 2)).toBe(true)
			local dock1 = m.sea.docks[MapData.getProvince(m.map, p1)] :: number
			local merchant = Fleet.spawn(m.fleet, W, 1, "Merchant", p1, dock1)
			merchant.trade = { from = p1, to = p2, partner = 2, value = 1000 }
			local destroyer = Fleet.spawn(m.fleet, W, 2, "Destroyer", p2, dock1)
			destroyer.state = "patrol"
			local before = m.nations[2].money
			local sunk: any = nil
			for _ = 1, 300 do
				MatchSim.step(m, DT)
				for _, e in MatchSim.takeEvents(m) do
					if e.kind == "merchantSunk" then
						sunk = e
					end
				end
				if sunk ~= nil then
					break
				end
			end
			T.expect(sunk ~= nil).toBe(true)
			T.expect(sunk.by).toBe(2)
			T.expect(sunk.amount).toBe(math.floor(1000 * tc.PiracyShare))
			T.expect(m.nations[2].money - before >= sunk.amount - 3000).toBe(true)
		end
	)
end)
