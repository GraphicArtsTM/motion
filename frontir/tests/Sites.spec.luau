--!strict
-- Стройка с лесами (§15ч Ч5а): новое здание не работает до конца стройки, у сети дорог — быстрее, событие built.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")

local DT = 1 / Config.Sim.TickRate
local W, H = 512, 24 -- ширина 512 — эталонная (дальность связи без масштаба)

local function solo(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 7)
	m.victory = false
	MatchSim.addPlayer(m, 1, "N1")
	m.phase = "Play"
	for y = 1, H - 2 do
		for x = 1, 200 do
			Grid.setOwner(m.grid, y * W + x, 1)
		end
	end
	for _, cell in m.cityOf do
		Grid.setCity(m.grid, cell, false)
	end
	table.clear(m.cityOf)
	local n = m.nations[1]
	n.colorIndex = 1
	n.capital = 12 * W + 10
	n.money = 1e6
	Grid.setCity(m.grid, n.capital :: number, true)
	m.cityOf[-1] = n.capital :: number
	return m
end

local function build(m: MatchSim.Match, x: number): number
	local cell = 12 * W + x
	T.expect((MatchSim.applyIntent(m, 1, { kind = "build", building = "Factory", cell = cell }))).toBe(true)
	return cell
end

T.describe("Стройка с лесами (§15ч Ч5а)", function()
	T.it(
		"новое здание — леса: не работает, пока не пройдёт время; потом событие built и работает",
		function()
			local m = solo()
			local cell = build(m, 120)
			T.expect(MatchSim.isDisabled(m, cell)).toBe(true)
			T.expect(MatchSim.ownedOf(m, 1).factories).toBe(0)
			T.expect(MatchSim.hasSite(m, 1)).toBe(true)
			local site = m.sites[cell]
			local built = false
			for _ = 1, math.ceil((site.total / m.speed + 1) * Config.Sim.TickRate) do
				MatchSim.step(m, DT)
				for _, e in MatchSim.takeEvents(m) do
					if e.kind == "built" and e.cell == cell then
						built = e.nation == 1 and e.building == "Factory"
					end
				end
			end
			T.expect(built).toBe(true)
			T.expect(m.sites[cell]).toBe(nil)
			T.expect(MatchSim.ownedOf(m, 1).factories).toBe(1)
			-- Улучшение — сразу, без лесов.
			T.expect((MatchSim.applyIntent(m, 1, { kind = "build", building = "Factory", cell = cell }))).toBe(true)
			T.expect(m.sites[cell]).toBe(nil)
			T.expect(m.buildings.byCell[cell].level).toBe(2)
		end
	)

	T.it(
		"у сети дорог (станция или столица в дальности связи) — время × NetworkMul; клиент считает так же",
		function()
			local m = solo()
			local near = build(m, 35) -- 25 клеток от столицы
			local far = build(m, 150) -- 140 клеток: вне сети
			local cfg = Config.Build.Site
			T.expect(m.sites[near].total).toBe(cfg.Default * cfg.NetworkMul)
			T.expect(m.sites[far].total).toBe(cfg.Default)
			T.expect(MatchSim.siteSec(m, 1, "MissileSilo", far)).toBe(Buildings.siteSec("MissileSilo", false))
			-- Клиент: столица и сеть — те же; стройки приходят в world.
			local cs = ClientState.new(W, H)
			cs.nations[1] = { capital = m.nations[1].capital } :: any
			T.expect(ClientState.nearRailNetwork(cs, 1, near)).toBe(true)
			T.expect(ClientState.nearRailNetwork(cs, 1, far)).toBe(false)
			ClientState.applyWorld(cs, MatchStats.world(m, 1), 0)
			local left, frac = ClientState.siteAt(cs, far, 0)
			T.expect(left).toBe(cfg.Default)
			T.expect(frac).toBe(0)
			T.expect((ClientState.siteAt(cs, 12 * W + 60, 0))).toBe(nil)
		end
	)

	T.it(
		"снесли стройку — леса забыты; F4 «Достроить всё» — всё работает сразу",
		function()
			local m = solo()
			local a = build(m, 120)
			local b = build(m, 160)
			Buildings.remove(m.buildings, a, MapData.getProvince(m.map, a))
			MatchSim.step(m, DT)
			T.expect(m.sites[a]).toBe(nil)
			T.expect(m.sites[b] ~= nil).toBe(true)
			MatchSim.finishSites(m)
			T.expect((next(m.sites))).toBe(nil)
			T.expect(MatchSim.ownedOf(m, 1).factories).toBe(1)
			T.expect(MatchSim.hasSite(m, 1)).toBe(false)
		end
	)
end)
