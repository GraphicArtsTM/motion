--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local Config = require("../src/shared/Config")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
-- Две державы на полосах-провинциях по 10 клеток: 1 — x 1..60, 2 — x 61..120.
local W, H = 128, 64 -- побольше земли: доход покрывает содержание нанятых

local function duo(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 11)
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
		n.people = 50000
		n.money = 0
		n.oil = 0
		n.capital = caps[n.id]
		Grid.setCity(m.grid, caps[n.id], true)
		m.cityOf[-n.id] = caps[n.id]
	end
	return m
end

local function factories(m: MatchSim.Match, id: number, count: number)
	for k = 1, count do
		local province = (id - 1) * 6 + k
		-- Допустимая клетка провинции (§15г): центр может совпасть с городом — тогда рядом.
		local spot = MatchSim.buildSpot(m, id, "Factory", m.provinces.list[province].center)
		Buildings.place(m.buildings, "Factory", spot, province)
	end
	MatchSim.refreshOwned(m)
end

local function runFor(m: MatchSim.Match, seconds: number)
	for _ = 1, math.floor(seconds * Config.Sim.TickRate + 0.5) do
		MatchSim.step(m, DT)
	end
end

T.describe("Найм (правка перед 7в-2)", function()
	T.it(
		"линии найма: 1 + заводы + уровни городов / CityLevelsPerLine, не больше MaxRecruitLines; готовятся одновременно",
		function()
			local m = duo()
			T.expect(MatchSim.recruitLines(m, 1)).toBe(1)
			factories(m, 1, 2)
			T.expect(MatchSim.recruitLines(m, 1)).toBe(3)
			factories(m, 2, 5)
			T.expect(MatchSim.recruitLines(m, 2)).toBe(6)
			-- Уровни своих городов тоже дают линии; больше MaxRecruitLines — нет.
			local owned = MatchSim.ownedOf(m, 2)
			owned.cityLevels = 3 * Config.Forces.CityLevelsPerLine
			T.expect(MatchSim.recruitLines(m, 2)).toBe(Config.Forces.MaxRecruitLines)
			MatchSim.refreshOwned(m)

			local n = m.nations[1]
			n.money = 100000
			n.home = Forces.new()
			for _ = 1, 4 do
				T.expect((MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Infantry" }))).toBe(true)
			end
			-- Три линии: за время одного юнита (с бонусом завода) готовы трое, четвёртый — ещё нет.
			local sec = Forces.stats(INF).recruitSec * (1 - Config.Buildings.Factory.recruitSpeedBonus)
			runFor(m, sec + 0.2)
			T.expect(n.home[INF].strength).toBe(3 * Forces.stats(INF).strength)
			T.expect(#n.queue).toBe(1)
			runFor(m, sec)
			T.expect(n.home[INF].strength).toBe(4 * Forces.stats(INF).strength)
		end
	)

	T.it(
		"бот с большим запасом денег в мире нанимает войска: заводы-линии ускоряют найм, деньги тратятся",
		function()
			local function hiredWith(count: number): (number, number)
				local m = duo()
				MatchSim.setBot(m, 2, "General", "Aggressor")
				factories(m, 2, count)
				local n = m.nations[2]
				n.money = 500000
				n.home = Forces.new()
				runFor(m, 60)
				-- Нанятые — дома и на фронтах (бот может пойти на ничью землю).
				return Forces.total(n.home) + Forces.total(MatchSim.frontForces(m, 2)), n.money
			end
			local single = hiredWith(0)
			local hired, money = hiredWith(3)
			-- Одна линия (как было) — около 26 юнитов за минуту; с тремя заводами (4 линии) — в 1.5+ раза больше.
			T.expect(hired >= 1.5 * single).toBe(true)
			T.expect(hired >= 40 * Forces.stats(INF).strength).toBe(true)
			T.expect(money < 500000).toBe(true) -- тратит больше, чем зарабатывает
		end
	)
end)
