--!strict
-- Железные дороги в матче (§15ч Ч1): сеть появляется сама, снабжает фронт, сообщение клиенту, стабильность.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Rails = require("../src/shared/Rails")
local Stability = require("../src/shared/Stability")
local Trains = require("../src/shared/Trains")
local Types = require("../src/shared/Types")

local DT = 1 / Config.Sim.TickRate
-- Ширина 512 — эталонная (дальность связи без масштаба). Держава 1 — x 1..150; провинции — полосы по 10 клеток.
local W, H = 512, 24

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
		for x = 1, 150 do
			Grid.setOwner(m.grid, y * W + x, 1)
		end
	end
	-- Только столица: нейтральные города провинций на своей земле тоже были бы станциями.
	for _, cell in m.cityOf do
		Grid.setCity(m.grid, cell, false)
	end
	table.clear(m.cityOf)
	local n = m.nations[1]
	n.colorIndex = 1
	n.capital = 12 * W + 10
	Grid.setCity(m.grid, n.capital :: number, true)
	m.cityOf[-1] = n.capital :: number
	return m
end

-- Здание в провинции с клеткой x (центр провинции).
local function place(m: MatchSim.Match, kind: Types.BuildingKind, x: number): number
	local province = x // 10 + 1
	local p = m.provinces.list[province]
	Buildings.place(m.buildings, kind, p.center, province)
	MatchSim.refreshOwned(m)
	return p.center
end

local function recompute(m: MatchSim.Match)
	m.rails.nextAt = 0
	MatchSim.step(m, DT)
end

T.describe("Железные дороги в матче (§15ч Ч1)", function()
	T.it(
		"столица и завод рядом — дорога сама; завод в главной сети снабжает; клиент получает рельсы",
		function()
			local m = solo()
			local factory = place(m, "Factory", 35)
			recompute(m)
			local net = m.rails.nets[1]
			T.expect(net ~= nil).toBe(true)
			T.expect(#(net :: Rails.Net).links).toBe(1)
			T.expect(MatchSim.railConnected(m, 1, factory)).toBe(true)
			T.expect(table.find(m.rails.supply, factory) ~= nil).toBe(true)
			-- Клиент: те же клетки рельсов и станция в главной сети.
			local cs = ClientState.new(W, H)
			local changed = ClientState.applyRails(cs, MatchSim.railsMessage(m, true), function(cell: number): boolean
				return MapData.getTerrain(m.map, cell) == Types.Terrain.River
			end)
			T.expect(#changed > 0).toBe(true)
			for cell in (net :: Rails.Net).cells do
				T.expect(cs.rails.cells[cell] ~= nil).toBe(true)
			end
			T.expect(ClientState.railConnected(cs, 1, factory)).toBe(true)
			-- Разница с прошлого раза: сеть сменилась — есть; второй раз подряд — пусто.
			T.expect(MatchSim.railsMessage(m, false).nations["1"] ~= nil).toBe(true)
			T.expect((next(MatchSim.railsMessage(m, false).nations))).toBe(nil)
		end
	)

	T.it(
		"завод дальше дальности связи — без дороги и без снабжения",
		function()
			local m = solo()
			local far = place(m, "Factory", 10 + Config.Rail.LinkRange + 25)
			recompute(m)
			T.expect(MatchSim.railConnected(m, 1, far)).toBe(false)
			T.expect(table.find(m.rails.supply, far)).toBe(nil)
		end
	)

	T.it(
		"дорогу перерезали — сеть перестроена, завод больше не в главной сети",
		function()
			local m = solo()
			local factory = place(m, "Factory", 35)
			recompute(m)
			-- Поперёк поля между столицей и заводом — ничья полоса: обход невозможен.
			for y = 0, H - 1 do
				Grid.setOwner(m.grid, y * W + 22, 0)
			end
			recompute(m)
			T.expect(MatchSim.railConnected(m, 1, factory)).toBe(false)
			T.expect(table.find(m.rails.supply, factory)).toBe(nil)
		end
	)

	T.it(
		"стабильность: провинция со станцией главной сети — штраф за удалённость меньше",
		function()
			local m = solo()
			local province = 130 // 10 + 1
			local before = Stability.target(MatchSim.stabilityContext(m), province, 1)
			m.rails.provinces[1] = { [province] = true }
			local after = Stability.target(MatchSim.stabilityContext(m), province, 1)
			T.expect(after > before).toBe(true)
		end
	)

	-- §15ч Ч2 Поезда и грузы.
	local function runFor(m: MatchSim.Match, seconds: number)
		for _ = 1, math.floor(seconds * Config.Sim.TickRate + 0.5) do
			MatchSim.step(m, DT)
		end
	end
	local function eventsOf(m: MatchSim.Match, kind: string): { any }
		local out: { any } = {}
		for _, e in m.events do
			if e.kind == kind then
				table.insert(out, e)
			end
		end
		return out
	end

	T.it(
		"завод на дороге отправляет поезд к столице; остановка платит; поезд доезжает",
		function()
			local m = solo()
			place(m, "Factory", 35)
			recompute(m)
			m.events = {}
			local started: { any } = {}
			local stops: { any } = {}
			local gone: { any } = {}
			-- Первый поезд — через TrainEverySec; едет 25 клеток со скоростью TrainSpeed.
			for _ = 1, math.floor((Config.Rail.TrainEverySec + 8) * Config.Sim.TickRate) do
				MatchSim.step(m, DT)
				for _, e in eventsOf(m, "trainStarted") do
					table.insert(started, e)
				end
				for _, e in eventsOf(m, "trainStop") do
					table.insert(stops, e)
				end
				for _, e in eventsOf(m, "trainGone") do
					table.insert(gone, e)
				end
				m.events = {}
			end
			T.expect(#started >= 1).toBe(true)
			T.expect(#stops >= 1).toBe(true)
			T.expect(stops[1].cell).toBe(m.nations[1].capital)
			T.expect(stops[1].amount).toBe(Trains.stopMoney("City", Buildings.cityLevel(m.buildings, stops[1].cell)))
			T.expect(#gone >= 1).toBe(true)
			T.expect(gone[1].lost).toBe(false)
		end
	)

	T.it(
		"дорогу впереди перерезали — поезд пропадает без оплаты",
		function()
			local m = solo()
			place(m, "Factory", 35)
			recompute(m)
			runFor(m, Config.Rail.TrainEverySec + 0.2)
			local id = next(m.rails.trains)
			T.expect(id ~= nil).toBe(true)
			-- Ничья полоса поперёк поля у столицы: путь впереди не свой.
			for y = 0, H - 1 do
				Grid.setOwner(m.grid, y * W + 14, 0)
			end
			m.events = {}
			runFor(m, 1)
			T.expect(m.rails.trains[id :: number]).toBe(nil)
			local lost = eventsOf(m, "trainGone")
			T.expect(#lost >= 1 and lost[1].lost == true).toBe(true)
			T.expect(#eventsOf(m, "trainStop")).toBe(0)
		end
	)

	T.it("нефтяная вышка в главной сети — нефти больше", function()
		local m = solo()
		local rig = place(m, "OilRig", 35)
		recompute(m)
		T.expect(MatchSim.railConnected(m, 1, rig)).toBe(true)
		T.expect((m.rails.rigBonus[1] or 0) > 0).toBe(true)
	end)
end)
