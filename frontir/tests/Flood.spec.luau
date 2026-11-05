--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Config = require("../src/shared/Config")
local Flood = require("../src/shared/Flood")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Modes = require("../src/shared/Modes")

local DT = 1 / Config.Sim.TickRate

local function level(levels: buffer, w: number, x: number, y: number): number
	return buffer.readu16(levels, (y * w + x) * 2)
end

T.describe("Потоп (§5.3)", function()
	T.it(
		"высота — взвешенное расстояние до воды; горы не тонут; за горами — в обход",
		function()
			local map = TinyMap.fromRows({
				"~~~~~~~~~~",
				"~..hh^^..~",
				"~..ff^^..~",
				"~~~~~~~~~~",
			})
			local w = map.width
			local levels = Flood.levels(map)
			T.expect(level(levels, w, 0, 0)).toBe(0) -- вода
			T.expect(level(levels, w, 1, 1)).toBe(10) -- равнина у воды
			T.expect(level(levels, w, 3, 1)).toBe(30) -- холм у воды
			T.expect(level(levels, w, 5, 1)).toBe(Flood.NEVER) -- горы не тонут
			T.expect(level(levels, w, 3, 2)).toBe(15) -- лес у воды
			T.expect(level(levels, w, 7, 2)).toBe(10)
			T.expect(Flood.levels(map)).toBe(levels) -- кеш на карту
		end
	)

	T.it(
		"ступени: порог растёт с шириной карты; sinking — только новые клетки",
		function()
			local cfg = Config.Flood
			T.expect(Flood.threshold(512, 1)).toBe(cfg.StepCells * 10)
			T.expect(Flood.threshold(1024, 2)).toBe(cfg.StepCells * 10 * 2 * 2)
			local map = TinyMap.plains(30, 30)
			local levels = Flood.levels(map)
			local first = Flood.sinking(levels, map.width, 0, 1)
			local second = Flood.sinking(levels, map.width, 1, 2)
			T.expect(#first > 0).toBe(true)
			T.expect(#second > 0).toBe(true)
			for _, i in second do
				T.expect(table.find(first, i)).toBe(nil)
			end
		end
	)

	T.it(
		"в матче: клетки ничьи и незахватываемые, города и здания исчезают, без городов — выбывание",
		function()
			local map = TinyMap.plains(80, 20)
			for i = 0, map.width * map.height - 1 do
				if MapData.getTerrain(map, i) ~= 0 then
					MapData.setProvince(map, i, (i % map.width) // 10 + 1)
				end
			end
			local m = MatchSim.new(map, 5)
			MatchSim.addPlayer(m, 1, "A")
			MatchSim.addPlayer(m, 2, "B")
			m.forcedMode = "Flood"
			MatchSim.startPick(m)
			T.expect(m.rules.flood).toBe(true)
			-- Держава 1 — у самой воды, держава 2 — в глубине суши.
			T.expect((MatchSim.applyIntent(m, 1, { kind = "pick", cell = 10 * 80 + 6 }))).toBe(true)
			T.expect((MatchSim.applyIntent(m, 2, { kind = "pick", cell = 10 * 80 + 70 }))).toBe(true)
			MatchSim.finishPick(m)
			m.victory = false
			local land = m.grid.capturableCount
			local coast = 1 * 80 + 5 -- клетка у воды
			Grid.setOwner(m.grid, coast, 1)
			-- Ступень по часам матча.
			m.time = Config.Flood.EverySec
			MatchSim.step(m, DT)
			T.expect(m.flood.step).toBe(1)
			T.expect(Grid.isCapturable(m.grid, coast)).toBe(false)
			T.expect(Grid.getOwner(m.grid, coast)).toBe(0)
			T.expect(m.grid.capturableCount < land).toBe(true)
			local sawEvent = false
			for _, e in MatchSim.takeEvents(m) do
				if e.kind == "flood" then
					sawEvent = true
				end
			end
			T.expect(sawEvent).toBe(true)
			-- Поднимаем воду, пока столица 1 не утонет: город исчез, держава выбыла (других городов нет).
			local capital = m.nations[1].capital :: number
			while Grid.isCapturable(m.grid, capital) and m.flood.step < Config.Flood.MaxSteps do
				MatchSim.floodStep(m)
			end
			T.expect(Grid.isCity(m.grid, capital)).toBe(false)
			MatchSim.step(m, DT)
			T.expect(m.nations[1].alive).toBe(false)
			T.expect(m.nations[2].alive).toBe(true)
			-- Больше MaxSteps вода не поднимается.
			while m.flood.step < Config.Flood.MaxSteps do
				MatchSim.floodStep(m)
			end
			T.expect(MatchSim.floodStep(m)).toBe(0)
			T.expect(Modes.rules("Flood").flood).toBe(true)
		end
	)
end)
