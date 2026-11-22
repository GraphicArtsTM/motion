--!strict
-- Морские линии (§15ч Ч6): свои порты через море — одна сеть; эсминец врага закрывает линию; стык с союзником морем.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Diplomacy")
local Fleet = require("../src/shared/Fleet")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Types = require("../src/shared/Types")
local Wars = require("../src/shared/Wars")

local DT = 1 / Config.Sim.TickRate
-- Ширина 512 — эталонная. Пролив — столбцы x 100..139: остров A — x 1..99, остров B — x 140..300.
local W, H = 512, 24
local STRAIT0, STRAIT1 = 100, 139
-- Провинции — полосы по 10 клеток, номера подряд (без пролива).
local function provinceOf(x: number): number
	return if x < STRAIT0 then x // 10 + 1 else x // 10 + 1 - (STRAIT1 + 1 - STRAIT0) // 10
end

local function islands(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		local x = i % W
		if MapData.getTerrain(map, i) ~= Types.Terrain.Water then
			if x >= STRAIT0 and x <= STRAIT1 then
				MapData.setTerrain(map, i, Types.Terrain.Water)
				MapData.setProvince(map, i, 0)
			else
				MapData.setProvince(map, i, provinceOf(x))
			end
		end
	end
	local m = MatchSim.new(map, 7)
	m.victory = false
	MatchSim.addPlayer(m, 1, "N1")
	MatchSim.addPlayer(m, 2, "N2")
	m.phase = "Play"
	for _, cell in m.cityOf do
		Grid.setCity(m.grid, cell, false)
	end
	table.clear(m.cityOf)
	return m
end

local function own(m: MatchSim.Match, id: number, x0: number, x1: number)
	for y = 1, H - 2 do
		for x = x0, x1 do
			Grid.setOwner(m.grid, y * W + x, id)
		end
	end
end

local function capital(m: MatchSim.Match, id: number, cell: number)
	local n = m.nations[id]
	n.colorIndex = id
	n.capital = cell
	Grid.setCity(m.grid, cell, true)
	m.cityOf[-id] = cell
end

-- Здание в провинции с клеткой x (центр провинции).
local function place(m: MatchSim.Match, kind: Types.BuildingKind, x: number): number
	local p = m.provinces.list[provinceOf(x)]
	Buildings.place(m.buildings, kind, p.center, p.id)
	MatchSim.refreshOwned(m)
	return p.center
end

local function recompute(m: MatchSim.Match)
	m.rails.nextAt = 0
	MatchSim.step(m, DT)
end

local function seaLink(m: MatchSim.Match, id: number): boolean
	for _, link in m.rails.nets[id].links do
		if link.sea then
			return true
		end
	end
	return false
end

T.describe("Морские линии (§15ч Ч6)", function()
	T.it(
		"два своих порта через пролив — морская линия: завод за морем в главной сети; клиент видит линию на море",
		function()
			local m = islands()
			own(m, 1, 1, 99)
			own(m, 1, 140, 250)
			capital(m, 1, 12 * W + 70)
			place(m, "Port", 95)
			place(m, "Port", 145)
			local factory = place(m, "Factory", 175)
			recompute(m)
			T.expect(seaLink(m, 1)).toBe(true)
			T.expect(MatchSim.railConnected(m, 1, factory)).toBe(true)
			-- Клиент: клетки пролива на линии — морская линия, не рельсы.
			local cs = ClientState.new(W, H)
			ClientState.applyRails(
				cs,
				MatchSim.railsMessage(m, true),
				function(cell: number): boolean
					return MapData.getTerrain(m.map, cell) == Types.Terrain.River
				end,
				0,
				function(cell: number): boolean
					return MapData.getTerrain(m.map, cell) == Types.Terrain.Water
				end
			)
			local onSea = 0
			for cell in cs.rails.seaway do
				T.expect(cs.rails.cells[cell]).toBe(nil)
				onSea += 1
			end
			T.expect(onSea > 0).toBe(true)
		end
	)

	T.it(
		"эсминец врага в войне у линии — линия закрыта, завод за морем без дороги к столице",
		function()
			local m = islands()
			own(m, 1, 1, 99)
			own(m, 1, 140, 250)
			own(m, 2, 260, 300)
			capital(m, 1, 12 * W + 70)
			capital(m, 2, 12 * W + 280)
			place(m, "Port", 95)
			place(m, "Port", 145)
			local factory = place(m, "Factory", 175)
			recompute(m)
			T.expect(MatchSim.railConnected(m, 1, factory)).toBe(true)
			local war = Wars.declare(m.wars, 2, 1, m.simTime)
			war.state = "active"
			local ship = Fleet.spawn(m.fleet, W, 2, "Destroyer", 12 * W + 280, 12 * W + 120)
			ship.x, ship.y = 120.5, 12.5
			T.expect(MatchSim.seaBlocked(m, 1, 12 * W + 120)).toBe(true)
			T.expect(MatchSim.seaBlocked(m, 2, 12 * W + 120)).toBe(false) -- свой эсминец не закрывает
			recompute(m)
			T.expect(MatchSim.railConnected(m, 1, factory)).toBe(false)
			-- Ушёл — линия снова.
			ship.alive = false
			m.rails.nextAt = 0
			for _ = 1, math.ceil((Config.Rail.RetryFailedSec / m.speed + 2) * Config.Sim.TickRate) do
				MatchSim.step(m, DT)
			end
			recompute(m)
			T.expect(MatchSim.railConnected(m, 1, factory)).toBe(true)
		end
	)

	T.it(
		"союзник с полным доверием за морем — стык морем между портами",
		function()
			local m = islands()
			own(m, 1, 1, 99)
			own(m, 2, 140, 250)
			capital(m, 1, 12 * W + 70)
			capital(m, 2, 12 * W + 175)
			place(m, "Port", 95)
			place(m, "Port", 145)
			Diplomacy.sign(m.diplo, "alliance", 1, 2, m.simTime)
			Diplomacy.setTrust(m.diplo, 1, 2, true, m.simTime)
			recompute(m)
			recompute(m)
			local list = MatchSim.junctionsOf(m, 1)
			T.expect(#list).toBe(1)
			T.expect(m.rails.junctions[list[1].key].sea).toBe(true)
		end
	)
end)
