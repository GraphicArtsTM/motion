--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local BotBrain = require("../src/shared/BotBrain")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local EventFeed = require("../src/shared/EventFeed")
local Diplomacy = require("../src/shared/Diplomacy")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")
local Passage = require("../src/shared/Passage")
local Types = require("../src/shared/Types")
local Wars = require("../src/shared/Wars")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
local W, H, STRIP = 45, 12, 5

-- Три державы в ряд (как в Diplomacy.spec): 1 — запад, 2 — середина, 3 — восток. 1 и 3 не граничат.
local function trio(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for y = 1, H - 2 do
		for x = 1, W - 2 do
			MapData.setProvince(map, y * W + x, x // STRIP + 1)
		end
	end
	local m = MatchSim.new(map, 3)
	m.victory = false
	for k = 1, 3 do
		MatchSim.addPlayer(m, k, "N" .. k)
	end
	m.phase = "Play"
	for y = 1, H - 2 do
		for x = 1, W - 2 do
			Grid.setOwner(m.grid, y * W + x, math.min(3, x // (STRIP * 3) + 1))
		end
	end
	for _, n in m.nations do
		n.colorIndex = n.id
		n.people = 5000
		n.capital = 6 * W + (n.id - 1) * STRIP * 3 + 2
		Grid.setCity(m.grid, n.capital :: number, true)
		m.cityOf[-n.id] = n.capital :: number
	end
	return m
end

local function runFor(m: MatchSim.Match, seconds: number)
	for _ = 1, math.floor(seconds * Config.Sim.TickRate + 0.5) do
		MatchSim.step(m, DT)
	end
end

local function count(events: { MatchSim.MatchEvent }, kind: string): number
	local c = 0
	for _, e in events do
		if e.kind == kind then
			c += 1
		end
	end
	return c
end

-- Собирает события за шаги (m.events очищается каждый шаг).
local function collect(m: MatchSim.Match, simSec: number): { MatchSim.MatchEvent }
	local all: { MatchSim.MatchEvent } = {}
	local untilTime = m.simTime + simSec
	local guard = 0
	while m.simTime < untilTime and guard < 100000 do
		MatchSim.step(m, DT)
		for _, e in m.events do
			table.insert(all, e)
		end
		table.clear(m.events) -- как сервер после рассылки
		guard += 1
	end
	return all
end

local function offer(m: MatchSim.Match, from: number, to: number, kind: Types.OfferKind)
	return MatchSim.applyIntent(m, from, { kind = "offer", target = to, offer = kind })
end

local function reply(m: MatchSim.Match, who: number, from: number, accept: boolean)
	return MatchSim.applyIntent(m, who, { kind = "offerReply", target = from, accept = accept })
end

-- 1 и 2 — союз с полным доверием, 1 воюет с 3 (активная война), у 1 дома пехота.
local function trusted(): MatchSim.Match
	local m = trio()
	Diplomacy.sign(m.diplo, "alliance", 1, 2, m.simTime)
	Diplomacy.setTrust(m.diplo, 1, 2, true, m.simTime)
	local war = Wars.declare(m.wars, 1, 3, m.simTime)
	war.state = "active"
	war.activeAt = m.simTime
	Forces.add(m.nations[1].home, INF, 600, 0)
	return m
end

T.describe("Два уровня союза (§15у)", function()
	T.it(
		"полное доверие: только союзнику, не раньше TrustAfterSec; снять — союз остаётся",
		function()
			local m = trio()
			T.expect(select(2, offer(m, 1, 2, "trust"))).toBe("needAlliance")
			T.expect((offer(m, 1, 2, "alliance"))).toBe(true)
			T.expect((reply(m, 2, 1, true))).toBe(true)
			T.expect(Diplomacy.allied(m.diplo, 1, 2)).toBe(true)
			T.expect(Diplomacy.trusted(m.diplo, 1, 2)).toBe(false)
			T.expect(select(2, offer(m, 2, 1, "trust"))).toBe("trustTooEarly")
			-- Союз длится TrustAfterSec — можно (предлагает 2: у 1 ещё пауза после предложения союза).
			local t = Diplomacy.treaty(m.diplo, 1, 2) :: Diplomacy.Treaty
			t.since -= Config.Alliance.TrustAfterSec
			T.expect((offer(m, 2, 1, "trust"))).toBe(true)
			T.expect((reply(m, 1, 2, true))).toBe(true)
			T.expect(Diplomacy.trusted(m.diplo, 1, 2)).toBe(true)
			T.expect(Diplomacy.trustedOf(m.diplo, 2)[1]).toBe(1)
			T.expect(select(2, Diplomacy.canOffer(m.diplo, 1, 2, "trust", m.simTime + 999))).toBe("already")
			-- Снять доверие — сразу, союз остаётся (частичное доверие).
			T.expect((MatchSim.applyIntent(m, 2, { kind = "distrust", target = 1 }))).toBe(true)
			T.expect(Diplomacy.trusted(m.diplo, 1, 2)).toBe(false)
			T.expect(Diplomacy.allied(m.diplo, 1, 2)).toBe(true)
			T.expect(select(2, MatchSim.applyIntent(m, 2, { kind = "distrust", target = 1 }))).toBe("noTrust")
			-- Новый союз (sign поверх) — без доверия; сеть передаёт trust.
			Diplomacy.setTrust(m.diplo, 1, 2, true, m.simTime)
			local MatchStats = require("../src/shared/Net/MatchStats")
			local msg = MatchStats.diplo(m)
			T.expect(msg.treaties[1].trust).toBe(true)
			-- Разбор намерений.
			local parsed = Intents.parse("offer", { target = 2, offer = "trust" }) :: Types.OfferIntent
			T.expect(parsed.offer).toBe("trust")
			local d = Intents.parse("distrust", { target = 2 }) :: Types.DistrustIntent
			T.expect(d.target).toBe(2)
			T.expect(select(2, Intents.parse("distrust", { target = 0 }))).toBe("bad target")
		end
	)

	T.it(
		"удар через союзника: войска идут через его землю, выходят к врагу, плацдарм и фронт, не котёл",
		function()
			local m = trusted()
			local before = Forces.total(m.nations[1].home)
			-- Общей границы с 3 нет — атака без точки идёт через союзника (к столице врага).
			T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 3, percent = 0.5 }))).toBe(true)
			T.expect(#m.passages).toBe(1)
			local p = m.passages[1]
			-- Событие для стрелки на карте: откуда и куда.
			local started: any = nil
			for _, e in m.events do
				if e.kind == "passageStarted" then
					started = e
				end
			end
			T.expect(started ~= nil and started.from == p.from and started.cell == p.exit).toBe(true)
			T.expect(p.ally).toBe(2)
			T.expect(Grid.getOwner(m.grid, p.exit)).toBe(3)
			T.expect(Grid.getOwner(m.grid, p.from)).toBe(1)
			T.expect(math.abs(Forces.total(m.nations[1].home) - before / 2) < 1).toBe(true)
			-- В пути — тоже «на фронте» (сила державы не пропадает).
			T.expect(math.abs(Forces.total(MatchSim.frontForces(m, 1)) - before / 2) < 1).toBe(true)
			local travel = p.arriveAt - m.simTime
			T.expect(travel >= Config.Alliance.PassageMinSec and travel <= Config.Alliance.PassageMaxSec).toBe(true)
			local events = collect(m, travel + 0.5)
			T.expect(count(events, "passageArrived")).toBe(1)
			T.expect(#m.passages).toBe(0)
			-- Плацдарм: клетки 1 за землёй 2 (восточнее x = 29) и фронт против 3.
			local beyond = 0
			for y = 1, H - 2 do
				for x = 30, W - 2 do
					if Grid.getOwner(m.grid, y * W + x) == 1 then
						beyond += 1
					end
				end
			end
			T.expect(beyond > 0).toBe(true)
			local front = false
			for _, a in m.attacks do
				front = front or (a.attacker == 1 and a.target == 3)
			end
			T.expect(front).toBe(true)
			-- Кусок за союзником касается его земли — не котёл (не сдаётся).
			runFor(m, Config.Pocket.CheckEverySec * 3 + 1)
			local pockets = m.pockets[1]
			T.expect(pockets == nil or pockets.cells == 0).toBe(true)
			T.expect(MatchSim.allyCorridor(m, 1, { p.exit })).toBe(true)
		end
	)

	T.it(
		"без полного доверия — нельзя; снять доверие в пути — войска домой; не больше MaxPassages",
		function()
			local m = trusted()
			Diplomacy.setTrust(m.diplo, 1, 2, false, m.simTime)
			MatchSim.applyIntent(m, 1, { kind = "attack", target = 3, percent = 0.2 })
			T.expect(#m.passages).toBe(0)
			T.expect(MatchSim.passageRoute(m, 1, 3, m.nations[3].capital :: number)).toBe(nil)
			-- С доверием — идут; доверие сняли — возвращаются домой целиком.
			Diplomacy.setTrust(m.diplo, 1, 2, true, m.simTime)
			local home = Forces.total(m.nations[1].home)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 3, percent = 0.3 }))).toBe(true)
			T.expect((MatchSim.applyIntent(m, 2, { kind = "distrust", target = 1 }))).toBe(true)
			local events = collect(m, 0.5)
			T.expect(count(events, "passageReturned")).toBe(1)
			T.expect(count(events, "passageArrived")).toBe(0)
			T.expect(math.abs(Forces.total(m.nations[1].home) - home) < 1).toBe(true)
			-- Отрядов в пути — не больше MaxPassages.
			Diplomacy.setTrust(m.diplo, 1, 2, true, m.simTime)
			for _ = 1, Config.Alliance.MaxPassages do
				T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 3, percent = 0.2 }))).toBe(true)
			end
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "attack", target = 3, percent = 0.2 })))
				.toBe("tooManyPassages")
			-- Мир — отряды домой.
			local war = Wars.find(m.wars, 1, 3) :: Wars.War
			Wars.finish(m.wars, war, m.simTime, false)
			local back = collect(m, 0.5)
			T.expect(count(back, "passageReturned")).toBe(Config.Alliance.MaxPassages)
		end
	)

	T.it(
		"Passage: место выхода у границы союзника ближе к точке; время в пути в пределах",
		function()
			local m = trusted()
			-- Точка удара на юге земли 3 — выход ближе к ней (южнее), чем к северу.
			local south = (H - 2) * W + 35
			local route = MatchSim.passageRoute(m, 1, 3, south) :: Passage.Route
			T.expect(route.exit % W).toBe(30) -- первая колонна 3 у границы 2
			T.expect(route.exit // W).toBe(H - 2)
			T.expect(route.from % W).toBe(14) -- последняя колонна 1 у границы 2
			T.expect(Passage.travelSec(0, W)).toBe(Config.Alliance.PassageMinSec)
			T.expect(Passage.travelSec(1e6, W)).toBe(Config.Alliance.PassageMaxSec)
			-- Клик далеко от своей границы, через союзника ближе — тоже через союзника (не по своей линии).
			local war = Wars.find(m.wars, 1, 3) :: Wars.War
			T.expect(war.state).toBe("active")
		end
	)

	T.it(
		"боты: принимают и предлагают полное доверие, вступают в войну за союзником и бьют через него",
		function()
			local base: BotBrain.OfferView = {
				kind = "trust",
				myPower = 100,
				fromPower = 100,
				fromTraitor = false,
				fromIsLeader = false,
				threat = false,
				atWarElsewhere = false,
				allies = 1,
			}
			-- Верный (loyalty ≥ BotTrustLoyalty) соглашается; лидеру и предателю — нет.
			T.expect(BotBrain.answerOffer(base, BotBrain.profile("Normal", "Peaceful"))).toBe(true)
			local leader = table.clone(base)
			leader.fromIsLeader = true
			T.expect(BotBrain.answerOffer(leader, BotBrain.profile("Normal", "Peaceful"))).toBe(false)
			local traitor = table.clone(base)
			traitor.fromTraitor = true
			T.expect(BotBrain.answerOffer(traitor, BotBrain.profile("Normal", "Peaceful"))).toBe(false)

			-- Бот 1 с полным доверием к 2, у 2 война с 3: бот 1 вступает и бьёт через 2.
			local m = trio()
			Diplomacy.sign(m.diplo, "alliance", 1, 2, m.simTime)
			Diplomacy.setTrust(m.diplo, 1, 2, true, m.simTime)
			local war = Wars.declare(m.wars, 2, 3, m.simTime)
			war.state = "active"
			MatchSim.setBot(m, 1, "General", "Peaceful")
			Forces.add(m.nations[1].home, INF, 2000, 0)
			local events = collect(m, 120)
			local declared, started = false, false
			for _, e in events do
				declared = declared or (e.kind == "warDeclared" and e.nation == 1 and e.target == 3)
				started = started or (e.kind == "passageStarted" and e.nation == 1 and e.target == 3)
			end
			T.expect(declared).toBe(true)
			T.expect(started).toBe(true)
		end
	)

	T.it(
		"доступы: снабжение, ПВО, порты и общий обзор — только при полном доверии; все узнают о союзах",
		function()
			local m = trio()
			Diplomacy.sign(m.diplo, "alliance", 1, 2, m.simTime)
			-- Частичное доверие: союзник — «друг» (видна сила, победа вместе), но не «друг по доверию».
			T.expect(Diplomacy.friends(m.diplo, 1)[2]).toBe(true)
			T.expect(Diplomacy.trustFriends(m.diplo, 1)[2]).toBe(nil)
			local before = 0
			for _ in MatchStats.vision(m, 1).blocks do
				before += 1
			end
			T.expect(MatchStats.vision(m, 1).friends[2]).toBe(true) -- фронты союзника видны
			Diplomacy.setTrust(m.diplo, 1, 2, true, m.simTime)
			T.expect(Diplomacy.trustFriends(m.diplo, 1)[2]).toBe(true)
			local after = 0
			for _ in MatchStats.vision(m, 1).blocks do
				after += 1
			end
			T.expect(after > before).toBe(true) -- общий обзор: земля союзника
			-- Вассал и сюзерен — как полное доверие.
			Diplomacy.setVassal(m.diplo, 3, 1, m.simTime)
			T.expect(Diplomacy.trustFriends(m.diplo, 1)[3]).toBe(true)
			T.expect(Diplomacy.trustFriends(m.diplo, 3)[1]).toBe(true)
			-- Лента: союз и доверие чужих держав — важное для всех.
			T.expect(EventFeed.level({ kind = "offerAccepted", nation = 5, target = 6, offer = "alliance" }, 1, {}))
				.toBe("important")
			T.expect(EventFeed.level({ kind = "offerAccepted", nation = 5, target = 6, offer = "trust" }, 1, {}))
				.toBe("important")
			T.expect(EventFeed.level({ kind = "trustRemoved", nation = 5, target = 6 }, 1, {})).toBe("important")
			T.expect(EventFeed.level({ kind = "offerAccepted", nation = 5, target = 6, offer = "pact" }, 1, {}))
				.toBe("background")
		end
	)

	T.it("F4: союзник с полным доверием и враг за ним", function()
		local m = trio()
		local ok, _, ally, enemy = DevTools.trustAlly(m, 1)
		T.expect(ok).toBe(true)
		T.expect(ally).toBe(2)
		T.expect(enemy).toBe(3)
		T.expect(Diplomacy.trusted(m.diplo, 1, 2)).toBe(true)
		T.expect(Wars.isActive(m.wars, 1, 3)).toBe(true)
		-- У средней державы «за союзником» никого нет.
		local m2 = trio()
		T.expect((DevTools.trustAlly(m2, 2))).toBe(false)
	end)
end)
