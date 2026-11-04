--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local BotBrain = require("../src/shared/BotBrain")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Diplomacy")
local Forces = require("../src/shared/Forces")
local Fronts = require("../src/shared/Fronts")
local ClientState = require("../src/shared/ClientState")
local Grid = require("../src/shared/Grid")
local MatchStats = require("../src/shared/Net/MatchStats")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Rng = require("../src/shared/Rng")
local Types = require("../src/shared/Types")
local Wars = require("../src/shared/Wars")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
local W, H, STRIP = 45, 12, 5 -- карта 45×12, провинции — полосы по 5 клеток

-- Три державы на полосах-провинциях: 1 — провинции 1–3, 2 — 4–6, 3 — 7–9. Города — в центре каждой полосы.
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
		n.capital = 6 * W + (n.id - 1) * STRIP * 3 + 2 -- столица — в первой провинции своей трети
		Grid.setCity(m.grid, n.capital :: number, true)
		m.cityOf[-n.id] = n.capital :: number -- город держится в списке городов (иначе держава выбывает)
	end
	return m
end

local function runFor(m: MatchSim.Match, seconds: number)
	for _ = 1, math.floor(seconds * Config.Sim.TickRate + 0.5) do
		MatchSim.step(m, DT)
	end
end

local function hasEvent(events: { MatchSim.MatchEvent }, kind: string): boolean
	for _, e in events do
		if e.kind == kind then
			return true
		end
	end
	return false
end

local function offer(m: MatchSim.Match, from: number, to: number, kind: Types.OfferKind, province: number?)
	return MatchSim.applyIntent(m, from, { kind = "offer", target = to, offer = kind, province = province })
end

local function reply(m: MatchSim.Match, who: number, from: number, accept: boolean)
	return MatchSim.applyIntent(m, who, { kind = "offerReply", target = from, accept = accept })
end

T.describe("Договоры", function()
	T.it(
		"пакт: заключить, срок, разрыв раньше срока — «Предатель»",
		function()
			local m = trio()
			T.expect((offer(m, 1, 2, "pact3"))).toBe(true)
			T.expect(select(2, offer(m, 1, 2, "pact5"))).toBe("offerPending")
			T.expect((reply(m, 2, 1, true))).toBe(true)
			local t = Diplomacy.treaty(m.diplo, 1, 2) :: Diplomacy.Treaty
			T.expect(t.kind).toBe("pact")
			T.expect(t.untilTime).toBe(m.simTime + 3 * 60)
			-- Срок вышел — снова мир, без метки.
			runFor(m, 3 * 60 + 0.5)
			T.expect(Diplomacy.treaty(m.diplo, 1, 2)).toBe(nil)
			T.expect(Diplomacy.isTraitor(m.diplo, 1, m.simTime)).toBe(false)
			-- Новый пакт и разрыв раньше срока: через 15 с договора нет, разорвавший — «Предатель».
			offer(m, 2, 1, "pact5")
			reply(m, 1, 2, true)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "breakTreaty", target = 2 }))).toBe(true)
			MatchSim.takeEvents(m)
			runFor(m, Config.Diplomacy.BreakWarningSec + 0.2)
			T.expect(Diplomacy.treaty(m.diplo, 1, 2)).toBe(nil)
			T.expect(Diplomacy.isTraitor(m.diplo, 1, m.simTime)).toBe(true)
			T.expect(hasEvent(MatchSim.takeEvents(m), "treatyBroken")).toBe(true)
			-- Метка держится TraitorSec.
			runFor(m, Config.Diplomacy.TraitorSec)
			T.expect(Diplomacy.isTraitor(m.diplo, 1, m.simTime)).toBe(false)
		end
	)

	T.it(
		"союз: до двух союзников, разрыв с предупреждением без метки, война союзнику — предательство",
		function()
			local m = trio()
			offer(m, 1, 2, "alliance")
			reply(m, 2, 1, true)
			T.expect(Diplomacy.allied(m.diplo, 1, 2)).toBe(true)
			T.expect(select(2, offer(m, 1, 2, "alliance"))).toBe("already")
			-- Чистый разрыв.
			MatchSim.applyIntent(m, 2, { kind = "breakTreaty", target = 1 })
			runFor(m, Config.Diplomacy.BreakWarningSec + 0.2)
			T.expect(Diplomacy.allied(m.diplo, 1, 2)).toBe(false)
			T.expect(Diplomacy.isTraitor(m.diplo, 2, m.simTime)).toBe(false)
			-- Снова союз, потом удар в спину: договор рвётся сразу, метка, война идёт, союзникам — запись.
			runFor(m, Config.Diplomacy.OfferRetrySec)
			offer(m, 1, 2, "alliance")
			reply(m, 2, 1, true)
			offer(m, 3, 2, "alliance")
			reply(m, 2, 3, true)
			T.expect(#Diplomacy.alliesOf(m.diplo, 2)).toBe(2)
			MatchSim.takeEvents(m)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "declare", target = 2 }))).toBe(true)
			local events = MatchSim.takeEvents(m)
			T.expect(hasEvent(events, "betrayal")).toBe(true)
			T.expect(hasEvent(events, "allyAttacked")).toBe(true)
			T.expect(Diplomacy.allied(m.diplo, 1, 2)).toBe(false)
			T.expect(Diplomacy.isTraitor(m.diplo, 1, m.simTime)).toBe(true)
			T.expect(Wars.find(m.wars, 1, 2) ~= nil).toBe(true)
			-- С тем, с кем воюешь, договоров нет.
			T.expect(select(2, offer(m, 1, 2, "pact3"))).toBe("atWar")
		end
	)

	T.it(
		"капитуляция: слабый — вассал, дань сюзерену, независимость не раньше VassalRebelSec",
		function()
			local m = trio()
			Forces.add(m.nations[1].home, INF, 3000)
			Forces.add(m.nations[2].home, INF, 300)
			MatchSim.applyIntent(m, 1, { kind = "declare", target = 2 })
			runFor(m, Config.War.MobilizationSec + 0.2)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "peace", target = 2, terms = "capitulate" })))
				.toBe("notWeakEnough")
			T.expect((MatchSim.applyIntent(m, 2, { kind = "peace", target = 1, terms = "capitulate" }))).toBe(true)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "peaceReply", target = 2, accept = true }))).toBe(true)
			T.expect(Diplomacy.overlordOf(m.diplo, 2)).toBe(1)
			T.expect(Wars.find(m.wars, 1, 2)).toBe(nil)
			-- Дань: доход вассала — без доли сюзерена, деньги сюзерена растут быстрее своего дохода.
			local before = m.nations[1].money
			runFor(m, 1)
			local e1 = m.economy[1]
			local gained = m.nations[1].money - before
			T.expect(gained > (e1.income - e1.upkeep) * 0.99).toBe(true)
			-- Вассал не воюет с сюзереном, сюзерен — со своим вассалом; союзов вассал не заключает.
			T.expect(select(2, MatchSim.applyIntent(m, 2, { kind = "declare", target = 1 }))).toBe("vassalRebel")
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "declare", target = 2 }))).toBe("ownVassal")
			T.expect(select(2, offer(m, 2, 3, "alliance"))).toBe("vassal")
			T.expect(select(2, MatchSim.applyIntent(m, 2, { kind = "rebel" }))).toBe("tooEarly")
			runFor(m, Config.Diplomacy.VassalRebelSec)
			MatchSim.takeEvents(m)
			T.expect((MatchSim.applyIntent(m, 2, { kind = "rebel" }))).toBe(true)
			T.expect(Diplomacy.overlordOf(m.diplo, 2)).toBe(nil)
			T.expect(Wars.find(m.wars, 1, 2) ~= nil).toBe(true)
			T.expect(hasEvent(MatchSim.takeEvents(m), "independence")).toBe(true)
		end
	)

	T.it(
		"требование: только пограничная провинция без столицы; отдал — клетки переходят, отказ — война",
		function()
			local m = trio()
			-- Провинция 4 — первая у 2 (там столица), 5 и 6 — дальше; у 1 граница с провинцией 4.
			T.expect(select(2, offer(m, 1, 2, "demand", 4))).toBe("capital")
			T.expect(select(2, offer(m, 1, 2, "demand", 6))).toBe("notBorder")
			-- Перенесём столицу 2 в провинцию 6 — теперь провинцию 4 можно требовать.
			m.nations[2].capital = 6 * W + 5 * STRIP + 2
			Grid.setCity(m.grid, m.nations[2].capital :: number, true)
			m.cityOf[-20] = m.nations[2].capital :: number
			T.expect((offer(m, 1, 2, "demand", 4))).toBe(true)
			local center = m.provinces.list[4].center
			T.expect((reply(m, 2, 1, true))).toBe(true)
			T.expect(Grid.getOwner(m.grid, center)).toBe(1)
			for _, cell in m.provinces.list[4].cells do
				T.expect(Grid.getOwner(m.grid, cell)).toBe(1)
			end
			-- Отказ: требующий объявляет войну.
			runFor(m, Config.Diplomacy.OfferRetrySec)
			T.expect((offer(m, 1, 2, "demand", 5))).toBe(true)
			MatchSim.takeEvents(m)
			reply(m, 2, 1, false)
			T.expect(Wars.find(m.wars, 1, 2) ~= nil).toBe(true)
			T.expect(hasEvent(MatchSim.takeEvents(m), "warDeclared")).toBe(true)
		end
	)

	T.it(
		"снабжение от городов союзника; выбывание стирает договоры",
		function()
			local g = trio().grid
			local far = 6 * W + W - 3 -- край карты у державы 3
			local cities = { 6 * W + 2 } -- единственный город — у державы 1, далеко
			T.expect(Fronts.supplied(g, cities, 3, { far })).toBe(false)
			T.expect(Fronts.supplied(g, { 6 * W + W - 5 }, 1, { far }, { [3] = true })).toBe(true)
			local m = trio()
			offer(m, 1, 2, "alliance")
			reply(m, 2, 1, true)
			Diplomacy.removeNation(m.diplo, 2)
			T.expect(#Diplomacy.alliesOf(m.diplo, 1)).toBe(0)
		end
	)

	T.it(
		"совместная победа: суша союза к 60% — победа, союзник — второе место",
		function()
			local m = trio()
			m.victory = true
			offer(m, 1, 3, "alliance")
			reply(m, 3, 1, true)
			-- Держава 2 теряет почти всё: у союза 1+3 больше 60% суши.
			for y = 1, H - 2 do
				for x = STRIP * 3, STRIP * 6 - 1 do
					local i = y * W + x
					if Grid.getOwner(m.grid, i) == 2 and not Grid.isCity(m.grid, i) and x > STRIP * 3 + 2 then
						Grid.setOwner(m.grid, i, if x < STRIP * 4 + 3 then 1 else 3)
					end
				end
			end
			MatchSim.step(m, DT)
			T.expect(m.phase).toBe("Over")
			local result = m.result :: Types.MatchResult
			T.expect(result.reason).toBe("land")
			T.expect(result.coWinners ~= nil and #result.coWinners == 1).toBe(true)
			T.expect(result.places[3]).toBe(2)
		end
	)

	T.it(
		"клиент видит договоры, предложения, предателя и вассала из сообщения diplo",
		function()
			local m = trio()
			offer(m, 1, 2, "alliance")
			reply(m, 2, 1, true)
			offer(m, 3, 1, "pact5")
			MatchSim.applyIntent(m, 3, { kind = "declare", target = 2 }) -- 2 и 3 — без договора: не предательство
			local cs = ClientState.new(W, H)
			cs.myNation = 1
			ClientState.applyDiplo(cs, MatchStats.diplo(m), 10)
			local t = ClientState.treatyBetween(cs, 2, 1) :: ClientState.DiploTreaty
			T.expect(t.kind).toBe("alliance")
			T.expect(#ClientState.alliesOf(cs, 1)).toBe(1)
			T.expect(#cs.diplo.offers).toBe(1)
			T.expect(cs.diplo.offers[1].left).toBe(Config.Diplomacy.OfferSec)
			T.expect(ClientState.diploLeft(cs, 20, 15, 1)).toBe(15)
			T.expect(ClientState.isTraitor(cs, 3, 10, 1)).toBe(false)
			-- 1 предаёт союзника 2.
			MatchSim.applyIntent(m, 1, { kind = "declare", target = 2 })
			ClientState.applyDiplo(cs, MatchStats.diplo(m), 10)
			T.expect(ClientState.isTraitor(cs, 1, 10, 1)).toBe(true)
			T.expect(ClientState.isTraitor(cs, 1, 10 + Config.Diplomacy.TraitorSec, 1)).toBe(false)
			T.expect(cs.diplo.history[#cs.diplo.history].kind).toBe("betrayal")
			-- Плохое сообщение не ломает клиента.
			ClientState.applyDiplo(cs, { kind = "diplo", treaties = 5 }, 11)
			T.expect(#cs.diplo.treaties).toBe(0)
		end
	)

	T.it("намерения договоров проверяются", function()
		T.expect((Intents.parse("offer", { target = 2, offer = "pact3" }))).toEqual({
			kind = "offer",
			target = 2,
			offer = "pact3",
		})
		T.expect(select(2, Intents.parse("offer", { target = 2, offer = "war" }))).toBe("bad offer")
		T.expect(select(2, Intents.parse("offer", { target = 2, offer = "demand" }))).toBe("bad province")
		T.expect((Intents.parse("offerReply", { target = 3, accept = true }))).toEqual({
			kind = "offerReply",
			target = 3,
			accept = true,
		})
		T.expect((Intents.parse("rebel", {}))).toEqual({ kind = "rebel" })
		T.expect(select(2, Intents.parse("breakTreaty", { target = 0 }))).toBe("bad target")
	end)
end)

T.describe("Дипломатия ботов", function()
	local function profile(personality: Types.BotPersonality): BotBrain.Profile
		local p = BotBrain.profile("Normal", personality)
		p.level = table.clone(p.level)
		p.level.mistake = 0
		p.level.buildChance = 0
		return p
	end
	local base: BotBrain.OfferView = {
		kind = "alliance",
		myPower = 1000,
		fromPower = 1000,
		fromTraitor = false,
		fromIsLeader = false,
		threat = true,
		atWarElsewhere = false,
		allies = 0,
	}

	T.it(
		"ответы: союз против общей угрозы, не с предателем и не с лидером; требование — только если слаб",
		function()
			T.expect(BotBrain.answerOffer(base, profile("Peaceful"))).toBe(true)
			local traitor = table.clone(base)
			traitor.fromTraitor = true
			T.expect(BotBrain.answerOffer(traitor, profile("Peaceful"))).toBe(false)
			local leader = table.clone(base)
			leader.fromIsLeader = true
			T.expect(BotBrain.answerOffer(leader, profile("Cunning"))).toBe(false)
			local calm = table.clone(base)
			calm.threat, calm.fromPower = false, 300
			T.expect(BotBrain.answerOffer(calm, profile("Aggressor"))).toBe(false)
			local demand = table.clone(base)
			demand.kind = "demand"
			T.expect(BotBrain.answerOffer(demand, profile("Peaceful"))).toBe(false)
			demand.myPower = 300
			T.expect(BotBrain.answerOffer(demand, profile("Peaceful"))).toBe(true)
		end
	)

	local function view(): BotBrain.BotView
		return {
			people = 900,
			maxPeople = 1000,
			attacks = 0,
			queue = Config.Forces.MaxQueue,
			power = 3000,
			totalPower = 3000,
			hasCapital = true,
			hasNeutral = false,
			neighbours = {},
			wars = {},
			fronts = {},
			money = 0,
			oil = 0,
			economy = { income = 0, oilIncome = 0, upkeep = 0 },
			owned = { factories = 0, markets = 0, rigs = 0, forts = 0, cityLevels = 1 },
			spots = {},
			time = 100,
			allies = 0,
		}
	end
	local function neighbour(id: number, power: number, extra: { [string]: any }?): BotBrain.Neighbour
		local n: BotBrain.Neighbour =
			{ id = id, people = 1, power = power, atWar = false, canDeclare = true, border = 10, share = 0.1 }
		if extra ~= nil then
			for k, v in extra do
				(n :: any)[k] = v
			end
		end
		return n
	end

	T.it(
		"бот зовёт в союз против лидера, Хитрец предаёт слабого союзника, верный вступает в войну",
		function()
			local rng = Rng.new(2)
			-- Союз против лидера (4): самый сильный сосед не лидер — 5.
			local v = view()
			v.power = 100 -- воевать нечем, остаётся дипломатия
			v.leader = 4
			v.neighbours = { neighbour(4, 9000, { canDeclare = false }), neighbour(5, 2000), neighbour(6, 500) }
			local found = false
			for _ = 1, 200 do
				local i = BotBrain.decide(v, rng, profile("Peaceful"), BotBrain.newMemory())
				if i ~= nil and i.kind == "offer" and i.offer == "alliance" and i.target == 5 then
					found = true
				end
			end
			T.expect(found).toBe(true)
			-- Хитрец и слабый союзник рядом.
			local c = view()
			c.neighbours = { neighbour(7, 200, { treaty = "alliance", canDeclare = false }) }
			local betrayed = false
			for _ = 1, 200 do
				local i = BotBrain.decide(c, rng, profile("Cunning"), BotBrain.newMemory())
				if i ~= nil and i.kind == "declare" and i.target == 7 then
					betrayed = true
				end
			end
			T.expect(betrayed).toBe(true)
			-- Миролюбивый не предаёт никогда.
			for _ = 1, 200 do
				local i = BotBrain.decide(c, rng, profile("Peaceful"), BotBrain.newMemory())
				T.expect(i == nil or i.kind ~= "declare").toBe(true)
			end
			-- Союзник воюет с 8, 8 — наш сосед: вступаем.
			local l = view()
			l.allyEnemies = { 8 }
			l.neighbours = { neighbour(8, 5000) }
			local joined = false
			for _ = 1, 50 do
				local i = BotBrain.decide(l, rng, profile("Peaceful"), BotBrain.newMemory())
				if i ~= nil and i.kind == "declare" and i.target == 8 then
					joined = true
				end
			end
			T.expect(joined).toBe(true)
		end
	)

	T.it("в матче боты заключают договоры", function()
		local Fixtures = require("./lib/Fixtures")
		local m = MatchSim.new(Fixtures.pangea, 21)
		m.targetNations = 16
		MatchSim.startPick(m)
		while m.phase ~= "Play" do
			MatchSim.step(m, DT)
		end
		m.victory = false
		local signed = false
		for _ = 1, 400 * Config.Sim.TickRate do
			MatchSim.step(m, DT)
			for _, e in MatchSim.takeEvents(m) do
				if e.kind == "offerAccepted" then
					signed = true
				end
			end
			if signed then
				break
			end
		end
		T.expect(signed).toBe(true)
	end)
end)
