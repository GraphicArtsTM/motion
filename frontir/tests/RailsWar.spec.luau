--!strict
-- Война и логистика (§15ч Ч3в): мост рушится от удара и чинится, обрыв виден, поезд у фронта гибнет, бот бьёт по мосту.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Types = require("../src/shared/Types")
local Wars = require("../src/shared/Wars")

local DT = 1 / Config.Sim.TickRate
-- Ширина 512 — эталонная. Держава 1 — x 1..150 (река — столбец x 60), держава 2 — x 151..300.
local W, H = 512, 24
local RIVER = 60
local CAP1, CAP2 = 12 * W + 40, 12 * W + 250

local function setup(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
			if i % W == RIVER and i // W > 0 and i // W < H - 1 then
				MapData.setTerrain(map, i, Types.Terrain.River)
			end
		end
	end
	local m = MatchSim.new(map, 7)
	m.victory = false
	MatchSim.addPlayer(m, 1, "N1")
	MatchSim.addPlayer(m, 2, "N2")
	m.phase = "Play"
	for y = 1, H - 2 do
		for x = 1, 300 do
			if x ~= RIVER then
				Grid.setOwner(m.grid, y * W + x, if x <= 150 then 1 else 2)
			end
		end
	end
	for _, cell in m.cityOf do
		Grid.setCity(m.grid, cell, false)
	end
	table.clear(m.cityOf)
	for id, cap in { [1] = CAP1, [2] = CAP2 } do
		local n = m.nations[id]
		n.colorIndex = id
		n.capital = cap
		Grid.setCity(m.grid, cap, true)
		m.cityOf[-id] = cap
	end
	return m
end

local function place(m: MatchSim.Match, kind: Types.BuildingKind, x: number): number
	local p = m.provinces.list[x // 10 + 1]
	Buildings.place(m.buildings, kind, p.center, p.id)
	MatchSim.refreshOwned(m)
	return p.center
end

local function recompute(m: MatchSim.Match): { any }
	m.rails.nextAt = 0
	MatchSim.step(m, DT)
	return MatchSim.takeEvents(m)
end

local function activeWar(m: MatchSim.Match)
	local war = Wars.declare(m.wars, 2, 1, m.simTime)
	war.state = "active"
end

local function bridgeOf(m: MatchSim.Match, id: number): number?
	for cell, kind in m.rails.nets[id].cells do
		if kind == 3 then
			return cell
		end
	end
	return nil
end

T.describe("Война и логистика (§15ч Ч3в)", function()
	T.it(
		"удар рушит мост: дорога через реку рвётся, обрыв в ленте, клиент видит мост; через BridgeRepairSec — снова",
		function()
			local m = setup()
			local factory = place(m, "Factory", 75)
			recompute(m)
			T.expect(MatchSim.railConnected(m, 1, factory)).toBe(true)
			local bridge = bridgeOf(m, 1)
			T.expect(bridge ~= nil).toBe(true)
			-- Удар по чужому (держава 2) — мосты державы 1 целы; по державе 1 — рушатся.
			T.expect(MatchSim.hitBridges(m, bridge :: number, 3, function(o: number): boolean
				return o == 2
			end)).toBe(0)
			T.expect(MatchSim.hitBridges(m, bridge :: number, 3, function(o: number): boolean
				return o == 1
			end) > 0).toBe(true)
			local events = recompute(m)
			local cut = nil
			for _, e in events do
				if e.kind == "railCut" and e.nation == 1 then
					cut = e
				end
			end
			T.expect(cut ~= nil).toBe(true)
			T.expect(cut.bridge).toBe(true)
			T.expect(MatchSim.railConnected(m, 1, factory)).toBe(false)
			-- Клиент: мост разрушен, починят через ≈ BridgeRepairSec / скорость матча.
			local cs = ClientState.new(W, H)
			cs.speed = m.speed
			ClientState.applyRails(cs, MatchSim.railsMessage(m, true), function(cell: number): boolean
				return MapData.getTerrain(m.map, cell) == Types.Terrain.River
			end, 0)
			local left = ClientState.bridgeRepairIn(cs, bridge :: number, 0)
			T.expect(left ~= nil).toBe(true)
			T.expect(math.abs((left :: number) - Config.Rail.BridgeRepairSec / m.speed) < 1).toBe(true)
			-- Ремонт.
			for _ = 1, math.ceil((Config.Rail.BridgeRepairSec / m.speed + 2) * Config.Sim.TickRate) do
				MatchSim.step(m, DT)
			end
			recompute(m)
			T.expect((next(m.rails.damaged))).toBe(nil)
			T.expect(MatchSim.railConnected(m, 1, factory)).toBe(true)
		end
	)

	T.it(
		"поезд у фронта (земля врага в войне ближе WarZoneCells) гибнет",
		function()
			local m = setup()
			-- Завод в тылу, свой город у самой границы с державой 2 — поезд едет к фронту.
			local function town(match: MatchSim.Match)
				local cell = 12 * W + 145
				Grid.setCity(match.grid, cell, true)
				match.cityOf[-3] = cell
			end
			town(m)
			place(m, "Factory", 125)
			recompute(m)
			activeWar(m)
			-- Враг подошёл вплотную к городу (через клетку).
			for y = 1, H - 2 do
				for x = 147, 150 do
					Grid.setOwner(m.grid, y * W + x, 2)
				end
			end
			local lost = false
			for _ = 1, math.floor((Config.Rail.TrainEverySec + 8) * Config.Sim.TickRate) do
				MatchSim.step(m, DT)
				for _, e in MatchSim.takeEvents(m) do
					if e.kind == "trainGone" and e.nation == 1 and e.war == true then
						lost = true
					end
				end
			end
			T.expect(lost).toBe(true)
			-- Без войны поезд доезжает.
			local calm = setup()
			town(calm)
			place(calm, "Factory", 125)
			recompute(calm)
			T.expect(MatchSim.inWarZone(calm, 1, 12 * W + 148)).toBe(false)
			T.expect(MatchSim.inWarZone(m, 1, 12 * W + 148)).toBe(true)
			T.expect(MatchSim.inWarZone(m, 1, 12 * W + 100)).toBe(false)
		end
	)

	T.it(
		"враг видит мост: прицел — клетка державы-цели рядом с мостом (налёт и ракета её примут)",
		function()
			local m = setup()
			place(m, "Factory", 75)
			recompute(m)
			activeWar(m)
			local bridge = bridgeOf(m, 1) :: number
			local aim = MatchSim.enemyBridge(m, m.nations[2], nil)
			T.expect(aim ~= nil).toBe(true)
			local a = aim :: number
			T.expect(Grid.getOwner(m.grid, a)).toBe(1)
			T.expect(math.abs(a % W - bridge % W) <= 2 and math.abs(a // W - bridge // W) <= 2).toBe(true)
			-- Без войны — целей нет.
			local calm = setup()
			place(calm, "Factory", 75)
			recompute(calm)
			T.expect(MatchSim.enemyBridge(calm, calm.nations[2], nil)).toBe(nil)
		end
	)
end)
