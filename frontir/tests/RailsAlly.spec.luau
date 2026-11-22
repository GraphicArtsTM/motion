--!strict
-- Стык дорог с союзником (§15ч Ч3б): появляется при полном доверии, рвётся войной, эмбарго и снятием доверия;
-- поезда к союзнику платят обоим.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Diplomacy")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Types = require("../src/shared/Types")
local Wars = require("../src/shared/Wars")

local DT = 1 / Config.Sim.TickRate
-- Ширина 512 — эталонная. Держава 1 — x 1..150, держава 2 — x 151..300; провинции — полосы по 10 клеток.
local W, H = 512, 24
local CAP1, CAP2 = 12 * W + 140, 12 * W + 165

local function duo(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 7)
	m.victory = false
	MatchSim.addPlayer(m, 1, "N1")
	MatchSim.addPlayer(m, 2, "N2")
	m.phase = "Play"
	for y = 1, H - 2 do
		for x = 1, 300 do
			Grid.setOwner(m.grid, y * W + x, if x <= 150 then 1 else 2)
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

local function trust(m: MatchSim.Match)
	Diplomacy.sign(m.diplo, "alliance", 1, 2, m.simTime)
	Diplomacy.setTrust(m.diplo, 1, 2, true, m.simTime)
end

local function recompute(m: MatchSim.Match)
	m.rails.nextAt = 0
	MatchSim.step(m, DT)
end

local function junction(m: MatchSim.Match): boolean
	return #MatchSim.junctionsOf(m, 1) > 0
end

T.describe("Стык с союзником (§15ч Ч3б)", function()
	T.it(
		"полное доверие — стык между ближайшими станциями сам; союз без доверия — нет; клиент знает станции стыка",
		function()
			local m = duo()
			Diplomacy.sign(m.diplo, "alliance", 1, 2, m.simTime)
			recompute(m)
			T.expect(junction(m)).toBe(false)
			Diplomacy.setTrust(m.diplo, 1, 2, true, m.simTime)
			recompute(m)
			T.expect(junction(m)).toBe(true)
			local j = MatchSim.junctionsOf(m, 1)[1]
			T.expect(j.mine).toBe(CAP1)
			T.expect(j.theirs).toBe(CAP2)
			T.expect(j.ally).toBe(2)
			T.expect(MatchSim.junctionsOf(m, 2)[1].mine).toBe(CAP2)
			local cs = ClientState.new(W, H)
			ClientState.applyRails(cs, MatchSim.railsMessage(m, true), function(cell: number): boolean
				return MapData.getTerrain(m.map, cell) == Types.Terrain.River
			end)
			T.expect(ClientState.railJunction(cs, 1, CAP1)).toBe(2)
			T.expect(ClientState.railJunction(cs, 2, CAP2)).toBe(1)
			T.expect(cs.rails.cells[12 * W + 152] ~= nil).toBe(true) -- рельсы стыка между столицами
		end
	)

	T.it("рвут стык: снятое доверие, эмбарго, война", function()
		local m = duo()
		trust(m)
		recompute(m)
		T.expect(junction(m)).toBe(true)
		Diplomacy.setTrust(m.diplo, 1, 2, false, m.simTime)
		recompute(m)
		T.expect(junction(m)).toBe(false)
		Diplomacy.setTrust(m.diplo, 1, 2, true, m.simTime)
		recompute(m)
		T.expect(junction(m)).toBe(true)
		Diplomacy.setEmbargo(m.diplo, 1, 2, true, m.simTime)
		recompute(m)
		T.expect(junction(m)).toBe(false)
		Diplomacy.setEmbargo(m.diplo, 1, 2, false, m.simTime)
		recompute(m)
		T.expect(junction(m)).toBe(true)
		Wars.declare(m.wars, 1, 2, m.simTime)
		recompute(m)
		T.expect(junction(m)).toBe(false)
	end)

	T.it(
		"завод на сети со стыком шлёт поезда к союзнику: конечная платит обоим; доверие сняли — поезд в пути пропал",
		function()
			local m = duo()
			trust(m)
			local p = m.provinces.list[115 // 10 + 1]
			Buildings.place(m.buildings, "Factory", p.center, p.id)
			MatchSim.refreshOwned(m)
			recompute(m)
			local allyTrain: number? = nil
			local paid: { [number]: number } = {}
			for _ = 1, math.floor(120 * Config.Sim.TickRate) do
				MatchSim.step(m, DT)
				for _, e in MatchSim.takeEvents(m) do
					if e.kind == "trainStarted" and e.ally == 2 and allyTrain == nil then
						allyTrain = e.id
					elseif e.kind == "trainStop" and e.id == allyTrain and e.cell == CAP2 then
						paid[e.nation] = e.amount
					end
				end
				if paid[1] ~= nil and paid[2] ~= nil then
					break
				end
			end
			T.expect(allyTrain ~= nil).toBe(true)
			T.expect(paid[1]).toBe(Config.Rail.AllyTradeMoney)
			T.expect(paid[2]).toBe(Config.Rail.AllyTradeMoney)
			-- Следующий поезд к союзнику; доверие сняли, пока он в пути, — пропадает.
			local id: number? = nil
			for _ = 1, math.floor(240 * Config.Sim.TickRate) do
				MatchSim.step(m, DT)
				for _, e in MatchSim.takeEvents(m) do
					if e.kind == "trainStarted" and e.ally == 2 then
						id = e.id
					end
				end
				if id ~= nil then
					break
				end
			end
			T.expect(id ~= nil).toBe(true)
			-- Ждём, пока поезд въедет на землю союзника (дальше x 150), потом снимаем доверие.
			local tr = m.rails.trains[id :: number]
			while tr ~= nil and tr.cells[math.floor(tr.pos)] % W <= 152 do
				MatchSim.step(m, DT)
				MatchSim.takeEvents(m)
				tr = m.rails.trains[id :: number]
			end
			T.expect(tr ~= nil).toBe(true)
			Diplomacy.setTrust(m.diplo, 1, 2, false, m.simTime)
			local lost = false
			for _ = 1, math.floor(3 * Config.Sim.TickRate) do
				m.rails.nextAt = math.min(m.rails.nextAt, m.simTime)
				MatchSim.step(m, DT)
				for _, e in MatchSim.takeEvents(m) do
					if e.kind == "trainGone" and e.id == id then
						lost = e.lost
					end
				end
			end
			T.expect(lost).toBe(true)
		end
	)
end)
