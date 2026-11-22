--!strict
-- Реки — водные пути (§15ч Ч4): пристань, путь по реке, свой берег, водный путь в матче.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Rails = require("../src/shared/Rails")
local Types = require("../src/shared/Types")

-- Чистый модуль: поле 128×40, река — строка y = 20 (x 5..120), всё остальное — своя земля.
local W, H = 128, 40
local function at(x: number, y: number): number
	return y * W + x
end
local function field(bankFrom: number?): Rails.Context
	local function river(cell: number): boolean
		return cell // W == 20 and cell % W >= 5 and cell % W <= 120
	end
	return {
		width = W,
		height = H,
		now = 0,
		river = river,
		bank = function(cell: number): boolean
			return bankFrom == nil or cell % W < bankFrom -- дальше bankFrom берег чужой
		end,
		passable = function(cell: number): number?
			return if river(cell) then Config.Rail.BridgeCost else 1
		end,
	}
end

T.describe("Реки — водные пути (§15ч Ч4)", function()
	T.it(
		"станции у реки дальше дальности связи (но в WaterRangeMul) — путь по реке; клетки реки — водный путь",
		function()
			local range = Rails.range(W)
			local a, b = at(10, 19), at(10 + math.floor(range * 1.8), 19)
			local net = Rails.build({ { cell = a, kind = "City" }, { cell = b, kind = "Factory" } }, a, field(nil), nil)
			T.expect(#net.links).toBe(1)
			local link = net.links[1]
			T.expect(link.water).toBe(true)
			T.expect(net.connected[b]).toBe(true)
			local path = link.path
			T.expect(path[1]).toBe(a)
			T.expect(path[#path]).toBe(b)
			local river = 0
			for k = 2, #path do
				local dx, dy = math.abs(path[k] % W - path[k - 1] % W), math.abs(path[k] // W - path[k - 1] // W)
				T.expect(dx <= 1 and dy <= 1).toBe(true) -- подряд: путь сжимается Rails.encode
				if path[k] // W == 20 then
					river += 1
					T.expect(net.cells[path[k]]).toBe(4)
				end
			end
			T.expect(river > 0).toBe(true)
			-- Берег за серединой стал чужим — водный путь не цел.
			T.expect(Rails.intact(field(nil), link)).toBe(true)
			T.expect(Rails.intact(field(15), link)).toBe(false)
		end
	)

	T.it(
		"без своего берега (bank) и далеко от реки — водного пути нет",
		function()
			local range = Rails.range(W)
			local a, b = at(10, 19), at(10 + math.floor(range * 1.8), 19)
			local ctx = field(nil)
			ctx.bank = nil
			local net = Rails.build({ { cell = a, kind = "City" }, { cell = b, kind = "Factory" } }, a, ctx, nil)
			T.expect(#net.links).toBe(0)
			-- Станция далеко от реки (не пристань).
			local far =
				Rails.build({ { cell = a, kind = "City" }, { cell = at(25, 5), kind = "Factory" } }, a, field(nil), nil)
			T.expect(#far.links).toBe(0)
		end
	)

	-- Матч: поле 512×24, река — строка y = 12 (x 5..400), держава 1 — x 1..300.
	local MW, MH = 512, 24
	local function match(): MatchSim.Match
		local map = TinyMap.plains(MW, MH)
		for i = 0, MW * MH - 1 do
			if MapData.getTerrain(map, i) ~= 0 then
				MapData.setProvince(map, i, (i % MW) // 10 + 1)
				if i // MW == 12 and i % MW >= 5 and i % MW <= 400 then
					MapData.setTerrain(map, i, Types.Terrain.River)
				end
			end
		end
		local m = MatchSim.new(map, 7)
		m.victory = false
		MatchSim.addPlayer(m, 1, "N1")
		m.phase = "Play"
		for y = 1, MH - 2 do
			for x = 1, 300 do
				if y ~= 12 then
					Grid.setOwner(m.grid, y * MW + x, 1)
				end
			end
		end
		for _, cell in m.cityOf do
			Grid.setCity(m.grid, cell, false)
		end
		table.clear(m.cityOf)
		local n = m.nations[1]
		n.colorIndex = 1
		n.capital = 11 * MW + 10
		Grid.setCity(m.grid, n.capital :: number, true)
		m.cityOf[-1] = n.capital :: number
		return m
	end

	T.it(
		"в матче: завод у реки за дальностью связи — в главной сети по реке; клиент видит водный путь; враг на берегу — путь рвётся",
		function()
			local m = match()
			local factory = 11 * MW + 10 + math.floor(Rails.range(MW) * 1.6)
			Buildings.place(m.buildings, "Factory", factory, MapData.getProvince(m.map, factory))
			MatchSim.refreshOwned(m)
			m.rails.nextAt = 0
			MatchSim.step(m, 1 / Config.Sim.TickRate)
			T.expect(MatchSim.railConnected(m, 1, factory)).toBe(true)
			T.expect(m.rails.nets[1].links[1].water).toBe(true)
			local cs = ClientState.new(MW, MH)
			ClientState.applyRails(cs, MatchSim.railsMessage(m, true), function(cell: number): boolean
				return MapData.getTerrain(m.map, cell) == Types.Terrain.River
			end, 0)
			T.expect(cs.rails.waterway[12 * MW + 40]).toBe(1)
			T.expect(cs.rails.cells[12 * MW + 40]).toBe(nil) -- на реке не рельсы
			T.expect(cs.rails.nets[1].water[1]).toBe(true)
			-- Оба берега на участке x 40..44 — чужие (ничьи): водный путь рвётся.
			for x = 40, 44 do
				Grid.setOwner(m.grid, 11 * MW + x, 0)
				Grid.setOwner(m.grid, 13 * MW + x, 0)
			end
			m.rails.nextAt = 0
			MatchSim.step(m, 1 / Config.Sim.TickRate)
			T.expect(MatchSim.railConnected(m, 1, factory)).toBe(false)
		end
	)
end)
