--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local TinyMap = require("./lib/TinyMap")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Expansion = require("../src/shared/Expansion")
local Forces = require("../src/shared/Forces")
local Fronts = require("../src/shared/Fronts")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Wars = require("../src/shared/Wars")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
local TANKS = Forces.kindIndex("Tanks") :: number

-- Две страны на карте w×12 (по умолчанию 40): левая половина — 1, правая — 2, города у краёв. Войны нет.
local function pair(rows: { string }?): (MatchSim.Match, number, number)
	local map = if rows ~= nil then TinyMap.fromRows(rows) else TinyMap.plains(40, 12)
	local w = map.width
	local m = MatchSim.new(map, 9)
	m.victory = false -- крошечная карта: 60% суши набирается сразу
	MatchSim.addPlayer(m, 1, "A")
	MatchSim.addPlayer(m, 2, "B")
	m.phase = "Play"
	for y = 1, map.height - 2 do
		for x = 1, w - 2 do
			local i = y * w + x
			if Grid.isCapturable(m.grid, i) then
				Grid.setOwner(m.grid, i, if x < w // 2 then 1 else 2)
			end
		end
	end
	local cityA, cityB = 6 * w + 3, 6 * w + w - 4
	for k, c in { cityA, cityB } do
		Grid.setCity(m.grid, c, true)
		m.cityOf[-k] = c
	end
	m.nations[1].capital, m.nations[2].capital = cityA, cityB
	for _, n in m.nations do
		n.colorIndex = n.id
		n.people = 5000
	end
	return m, cityA, cityB
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

-- Объявить войну и дождаться конца мобилизации.
local function goToWar(m: MatchSim.Match, a: number, b: number)
	assert(MatchSim.applyIntent(m, a, { kind = "declare", target = b }))
	runFor(m, Config.War.MobilizationSec + 0.2)
end

T.describe("Война и мир", function()
	T.it(
		"по умолчанию мир: страну не атаковать, её окружённые куски граница людей не берёт",
		function()
			local m = pair()
			Forces.add(m.nations[1].home, INF, 3000)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 })))
				.toBe("notAtWar")
			-- Кусок страны 2 посреди ничьей земли рядом с 1: окружение его не заберёт.
			local w = m.grid.width
			for y = 1, 10 do
				for x = 10, 19 do
					Grid.setOwner(m.grid, y * w + x, 0)
				end
			end
			local piece = 5 * w + 14
			Grid.setOwner(m.grid, piece, 2)
			MatchSim.applyIntent(m, 1, { kind = "attack", target = 0, percent = 1 })
			runFor(m, 20)
			T.expect(Grid.getOwner(m.grid, piece)).toBe(2)
		end
	)

	T.it(
		"объявление: мобилизация 15 с — обе стороны ждут, событие в ленте; потом бой",
		function()
			local m = pair()
			Forces.add(m.nations[1].home, TANKS, 3000)
			Forces.add(m.nations[2].home, INF, 500)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "declare", target = 2 }))).toBe(true)
			T.expect(hasEvent(MatchSim.takeEvents(m), "warDeclared")).toBe(true)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 })))
				.toBe("mobilizing")
			T.expect(select(2, MatchSim.applyIntent(m, 2, { kind = "attack", target = 1, percent = 1 })))
				.toBe("mobilizing")
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "declare", target = 2 }))).toBe("alreadyAtWar")
			runFor(m, Config.War.MobilizationSec - 1)
			T.expect(Wars.isActive(m.wars, 1, 2)).toBe(false)
			runFor(m, 1.2)
			T.expect(Wars.isActive(m.wars, 1, 2)).toBe(true)
			T.expect(hasEvent(MatchSim.takeEvents(m), "warStarted")).toBe(true)
			local cells = Grid.cellsOf(m.grid, 1)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 }))).toBe(true)
			runFor(m, 3)
			T.expect(Grid.cellsOf(m.grid, 1) > cells).toBe(true)
			-- Потери и захваченная земля копятся в войне.
			local war = Wars.find(m.wars, 1, 2) :: Wars.War
			local byA = Wars.takenCells(war, m.grid)
			T.expect(byA).toBe(Grid.cellsOf(m.grid, 1) - cells)
			T.expect(war.lossesA + war.lossesB > 0).toBe(true)
		end
	)

	T.it(
		"белый мир возвращает взятую землю; после мира 60 с нельзя снова объявить войну",
		function()
			local m = pair()
			Forces.add(m.nations[1].home, TANKS, 3000)
			Forces.add(m.nations[2].home, INF, 300)
			local cells2 = Grid.cellsOf(m.grid, 2)
			goToWar(m, 1, 2)
			MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 })
			runFor(m, 3)
			T.expect(Grid.cellsOf(m.grid, 2) < cells2).toBe(true)
			T.expect((MatchSim.applyIntent(m, 2, { kind = "peace", target = 1, terms = "white" }))).toBe(true)
			T.expect(select(2, MatchSim.applyIntent(m, 2, { kind = "peace", target = 1, terms = "keep" })))
				.toBe("peacePending")
			T.expect(select(2, MatchSim.applyIntent(m, 2, { kind = "peaceReply", target = 1, accept = true }))).toBe(
				"noProposal" -- отвечает не тот, кому предложили
			)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "peaceReply", target = 2, accept = true }))).toBe(true)
			T.expect(Wars.find(m.wars, 1, 2)).toBe(nil)
			T.expect(Grid.cellsOf(m.grid, 2)).toBe(cells2)
			T.expect(#m.attacks).toBe(0) -- фронты закрыты, войска дома
			T.expect(Forces.total(m.nations[1].home) > 0).toBe(true)
			T.expect(hasEvent(MatchSim.takeEvents(m), "peace")).toBe(true)
			T.expect(select(2, MatchSim.applyIntent(m, 2, { kind = "declare", target = 1 }))).toBe("peaceCooldown")
			runFor(m, Config.War.PeaceCooldownSec + 0.2)
			T.expect((MatchSim.applyIntent(m, 2, { kind = "declare", target = 1 }))).toBe(true)
		end
	)

	T.it(
		"«забрать захваченное» оставляет землю; отказ и истёкшее предложение; сильному капитулировать нельзя",
		function()
			local m = pair()
			Forces.add(m.nations[1].home, TANKS, 3000)
			Forces.add(m.nations[2].home, INF, 300)
			goToWar(m, 1, 2)
			MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 })
			runFor(m, 3)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "peace", target = 2, terms = "capitulate" })))
				.toBe("notWeakEnough")
			MatchSim.applyIntent(m, 1, { kind = "peace", target = 2, terms = "keep" })
			MatchSim.takeEvents(m)
			T.expect((MatchSim.applyIntent(m, 2, { kind = "peaceReply", target = 1, accept = false }))).toBe(true)
			T.expect(hasEvent(MatchSim.takeEvents(m), "peaceRejected")).toBe(true)
			T.expect(Wars.find(m.wars, 1, 2) ~= nil).toBe(true)
			-- Фронт отводим, чтобы за 20 с ожидания он не добил страну 2.
			MatchSim.applyIntent(m, 1, { kind = "cancel", target = 2 })
			MatchSim.applyIntent(m, 1, { kind = "peace", target = 2, terms = "keep" })
			runFor(m, Config.War.PeaceReplySec + 0.2)
			local war = Wars.find(m.wars, 1, 2) :: Wars.War
			T.expect(war.proposal).toBe(nil) -- истекло
			MatchSim.applyIntent(m, 1, { kind = "peace", target = 2, terms = "keep" })
			local mine = Grid.cellsOf(m.grid, 1)
			MatchSim.applyIntent(m, 2, { kind = "peaceReply", target = 1, accept = true })
			T.expect(Grid.cellsOf(m.grid, 1)).toBe(mine)
			T.expect(Wars.find(m.wars, 1, 2)).toBe(nil)
		end
	)

	T.it("бот сам отвечает на предложение мира", function()
		local m = pair()
		m.nations[2].isBot = true
		Forces.add(m.nations[1].home, TANKS, 3000)
		goToWar(m, 1, 2)
		MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 })
		runFor(m, 5)
		-- Бот слабее и потерял землю — белый мир ему выгоден.
		MatchSim.applyIntent(m, 1, { kind = "peace", target = 2, terms = "white" })
		runFor(m, Config.War.BotReplyDelaySec + 0.5)
		T.expect(Wars.find(m.wars, 1, 2)).toBe(nil)
	end)

	T.it("усталость: через 5 минут войны прирост людей меньше", function()
		local m = pair()
		goToWar(m, 1, 2)
		local war = Wars.find(m.wars, 1, 2) :: Wars.War
		T.expect(Wars.weariness(m.wars, 1, m.simTime)).toBe(0)
		war.activeAt = m.simTime - Config.War.WearinessAfterSec - 120
		local w = Wars.weariness(m.wars, 1, m.simTime)
		T.expect(w).toBeNear(Config.War.WearinessPenalty + 2 * Config.War.WearinessPenaltyPerMin, 1e-6)
		war.activeAt = m.simTime - 10000
		T.expect(Wars.weariness(m.wars, 2, m.simTime)).toBe(Config.War.WearinessMaxPenalty)
		-- Прирост с усталостью меньше.
		local max = Economy.maxPeople(Grid.cellsOf(m.grid, 1))
		local calm = Economy.grow(1000, max, 1)
		local tired = Economy.grow(1000, max, 1, 1 - Config.War.WearinessMaxPenalty)
		T.expect(tired - 1000).toBeNear((calm - 1000) * (1 - Config.War.WearinessMaxPenalty), 1e-6)
	end)

	T.it("выбывание кончает войну", function()
		local m = pair()
		goToWar(m, 1, 2)
		local w = m.grid.width
		-- У страны 2 забрали все города.
		Grid.setOwner(m.grid, 6 * w + w - 4, 1)
		MatchSim.step(m, DT)
		T.expect(m.nations[2].alive).toBe(false)
		T.expect(Wars.find(m.wars, 1, 2)).toBe(nil)
	end)

	T.it("намерения войны и мира проверяются", function()
		T.expect((Intents.parse("declare", { target = 0 }))).toBe(nil)
		T.expect((Intents.parse("declare", { target = 3 })) ~= nil).toBe(true)
		T.expect((Intents.parse("peace", { target = 3, terms = "everything" }))).toBe(nil)
		T.expect((Intents.parse("peace", { target = 3, terms = "white" })) ~= nil).toBe(true)
		T.expect((Intents.parse("peaceReply", { target = 3, accept = "yes" }))).toBe(nil)
		T.expect((Intents.parse("peaceReply", { target = 3, accept = false })) ~= nil).toBe(true)
	end)
end)

T.describe("Реки", function()
	-- Река по середине карты: слева страна 1, справа 2.
	local function riverRows(): { string }
		local rows: { string } = { string.rep("~", 30) }
		for _ = 1, 10 do
			table.insert(rows, "~" .. string.rep(".", 14) .. "r" .. string.rep(".", 13) .. "~")
		end
		table.insert(rows, string.rep("~", 30))
		return rows
	end

	T.it("граница людей реку не переходит, фронт — переходит", function()
		local m = pair(riverRows())
		local list, _, river = Expansion.frontier(m.grid, 1, 2, true)
		T.expect(#list).toBe(0) -- без реки соседства нет
		list, _, river = Expansion.frontier(m.grid, 1, 2, true, m.map)
		T.expect(#list).toBe(10)
		for _, i in list do
			T.expect(river[i]).toBe(true)
		end
		Forces.add(m.nations[1].home, TANKS, 4000)
		T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "declare", target = 2 }))).toBe(nil)
		runFor(m, Config.War.MobilizationSec + 0.2)
		T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 }))).toBe(true)
		local before = Grid.cellsOf(m.grid, 1)
		runFor(m, 20)
		T.expect(Grid.cellsOf(m.grid, 1) > before).toBe(true)
		-- Река осталась ничьей: фронт её перешёл, а не захватил.
		T.expect(Grid.getOwner(m.grid, 5 * 30 + 15)).toBe(0)
		T.expect(MapData.getTerrain(m.map, 5 * 30 + 15)).toBe(require("../src/shared/Types").Terrain.River)
	end)

	T.it(
		"за рекой фронт идёт медленнее, защитник на берегу сильнее",
		function()
			local function captured(rows: { string }?): number
				local m = pair(rows)
				Forces.add(m.nations[1].home, TANKS, 6000)
				-- Защитник с гарнизоном: перевес умеренный, скорость не упирается в насыщение кривой (§15м).
				Forces.add(m.nations[2].home, INF, 1500)
				goToWar(m, 1, 2)
				MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 })
				local before = Grid.cellsOf(m.grid, 1)
				runFor(m, 3)
				return Grid.cellsOf(m.grid, 1) - before
			end
			local plainRows: { string } = { string.rep("~", 30) }
			for _ = 1, 10 do
				table.insert(plainRows, "~" .. string.rep(".", 28) .. "~")
			end
			table.insert(plainRows, string.rep("~", 30))
			local overRiver, overPlain = captured(riverRows()), captured(plainRows)
			T.expect(overRiver < overPlain).toBe(true)
			local m = pair(riverRows())
			local list, _, river = Expansion.frontier(m.grid, 1, 2, true, m.map)
			local base = Fronts.terrainDefense(m.map, list)
			T.expect(Fronts.terrainDefense(m.map, list, river)).toBeNear(base * Config.Combat.RiverBankDefense, 1e-9)
		end
	)
end)

T.describe("Войны ботов на «Пангее»", function()
	T.it(
		"боты объявляют войны и воюют только после мобилизации",
		function()
			local m = MatchSim.new(Fixtures.pangea, 31)
			MatchSim.startPick(m)
			while m.phase ~= "Play" do
				MatchSim.step(m, DT)
			end
			local declared, fronts = false, false
			for _ = 1, 300 * Config.Sim.TickRate do
				MatchSim.step(m, DT)
				if hasEvent(MatchSim.takeEvents(m), "warDeclared") then
					declared = true
				end
				for _, a in m.attacks do
					if a.target ~= 0 then
						fronts = true
						T.expect(Wars.isActive(m.wars, a.attacker, a.target)).toBe(true)
					end
				end
			end
			T.expect(declared).toBe(true)
			T.expect(fronts).toBe(true)
		end
	)
end)

T.describe("«Первый удар» (§15б)", function()
	T.it(
		"объявивший войну первые OpeningSec после мобилизации наступает быстрее; защитник — нет",
		function()
			local m = pair()
			goToWar(m, 1, 2)
			local war = Wars.find(m.wars, 1, 2) :: Wars.War
			T.expect(war.state).toBe("active")
			local c = Config.Combat
			T.expect(MatchSim.openingMul(m, war, 1)).toBe(c.OpeningSpeedMul)
			T.expect(MatchSim.openingMul(m, war, 2)).toBe(1)
			runFor(m, c.OpeningSec + 0.5)
			T.expect(MatchSim.openingMul(m, war, 1)).toBe(1)
			T.expect(c.OpeningSpeedMul > 1 and c.OpeningSpeedMul <= 1.5).toBe(true)
		end
	)
end)
