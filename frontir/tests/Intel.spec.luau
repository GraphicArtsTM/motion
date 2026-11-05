--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Diplomacy")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")
local Protocol = require("../src/shared/Net/Protocol")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
local cfg = Config.Intel
-- Карта 160×32: держава 1 — x 1..50, держава 2 — 51..100, держава 3 — 101..150, провинции по 10 клеток.
local W, H = 160, 32

local function trio(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 21)
	m.victory = false
	for k = 1, 3 do
		MatchSim.addPlayer(m, k, "N" .. k)
	end
	m.phase = "Play"
	for y = 1, H - 2 do
		for x = 1, 150 do
			Grid.setOwner(m.grid, y * W + x, (x - 1) // 50 + 1)
		end
	end
	for _, n in m.nations do
		n.colorIndex = n.id
		n.money = 10000
		local cap = 16 * W + (n.id - 1) * 50 + 25
		n.capital = cap
		Grid.setCity(m.grid, cap, true)
		Forces.add(n.home, INF, 1000 * n.id)
	end
	Grid.takeChanges(m.grid)
	MatchSim.refreshOwned(m)
	return m
end

local function nationStats(s: Protocol.Stats, id: number): Protocol.NationStats
	for _, n in s.nations do
		if n.id == id then
			return n
		end
	end
	error("нет державы " .. id)
end

T.describe("Разведка и скрытая мощь (§6.11а)", function()
	T.it(
		"карта открыта вне «Мглы»; чужая мощь — «?», своя и союзника — числа, оценка — степень двойки",
		function()
			local m = trio()
			T.expect(MatchStats.fogOn(m)).toBe(false)
			Diplomacy.sign(m.diplo, "alliance", 1, 3, 0)
			local known = MatchSim.knownSet(m, 1) :: { [number]: boolean }
			T.expect(known[1]).toBe(true)
			T.expect(known[3]).toBe(true)
			T.expect(known[2] == true).toBe(false)
			local full = MatchStats.build(m, 0, 0)
			local s = Protocol.decodeStats(Protocol.encodeStats(MatchStats.forViewer(m, full, 1, nil, known)))
			local mine, enemy, ally = nationStats(s, 1), nationStats(s, 2), nationStats(s, 3)
			T.expect(mine.power > 0).toBe(true)
			T.expect(ally.power > 0).toBe(true)
			T.expect(enemy.troops).toBe(-1)
			T.expect(enemy.power < 0).toBe(true)
			local real = nationStats(full, 2).power
			local shown = -enemy.power
			T.expect(shown >= real / math.sqrt(2) - 1 and shown <= real * math.sqrt(2) + 1).toBe(true)
			T.expect(math.log(shown, 2) % 1).toBeNear(0)
			T.expect(MatchStats.hidden(0) < 0).toBe(true)
			-- Сила сторон в войне — тоже «?».
			MatchSim.declareWar(m, 1, 2)
			local wars = MatchStats.wars(m, known)
			T.expect(wars.wars[1].powerB).toBe(-1)
			T.expect(wars.wars[1].powerA > 0).toBe(true)
			T.expect(MatchStats.wars(m, nil).wars[1].powerB > 0).toBe(true)
		end
	)

	T.it(
		"разведка: $2000, мощь видна 90 с, цели — событие; друзей и без денег — отказ",
		function()
			local m = trio()
			T.expect((Intents.parse("intel", { target = 2 }))).toEqual({ kind = "intel", target = 2 })
			T.expect((Intents.parse("intel", { target = "x" }))).toBe(nil)
			local money = m.nations[1].money
			T.expect((MatchSim.applyIntent(m, 1, { kind = "intel", target = 2 }))).toBe(true)
			T.expect(m.nations[1].money).toBeNear(money - cfg.Cost)
			local events = MatchSim.takeEvents(m)
			local found = false
			for _, e in events do
				if e.kind == "intel" and e.nation == 1 and (e :: any).target == 2 then
					found = true
				end
			end
			T.expect(found).toBe(true)
			T.expect(MatchSim.knows(m, 1, 2)).toBe(true)
			T.expect(MatchSim.knows(m, 2, 1)).toBe(false) -- разведка в одну сторону
			-- Через 90 с игрового времени — снова «?».
			m.simTime += cfg.DurationSec + 1
			T.expect(MatchSim.knows(m, 1, 2)).toBe(false)
			-- Союзника разведывать незачем, без денег — нельзя.
			Diplomacy.sign(m.diplo, "alliance", 1, 3, m.simTime)
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "intel", target = 3 }))).toBe("already")
			m.nations[1].money = cfg.Cost - 1
			T.expect(select(2, MatchSim.applyIntent(m, 1, { kind = "intel", target = 2 }))).toBe("noMoney")
		end
	)

	T.it("радар — постоянная разведка державы в его радиусе", function()
		local m = trio()
		-- Радар державы 1 у границы с 2 (x = 45); держава 3 (x ≥ 101) — дальше 25 клеток.
		local province = 45 // 10 + 1
		local p = m.provinces.list[province]
		Buildings.place(m.buildings, "Radar", p.center, province)
		MatchSim.refreshOwned(m)
		MatchSim.step(m, DT)
		T.expect(MatchSim.knows(m, 1, 2)).toBe(true)
		T.expect(MatchSim.knows(m, 1, 3)).toBe(false)
		-- Радар выведен из строя — разведки нет (после пересчёта).
		m.air.disabled[p.center] = m.simTime + 100
		m.nextRadarIntelAt = 0
		MatchSim.step(m, DT)
		T.expect(MatchSim.knows(m, 1, 2)).toBe(false)
	end)
end)
