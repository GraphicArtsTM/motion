--!strict
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Expansion = require("../src/shared/Expansion")
local Grid = require("../src/shared/Grid")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")

local DT = 1 / Config.Sim.TickRate

-- Кешированная линия совпадает со свежим пересчётом: те же клетки, касания и «за рекой».
local function sameAsFresh(m: MatchSim.Match): (boolean, string?)
	Expansion.syncCache(m.frontCache, m.grid)
	for _, c in m.frontCache.lines do
		local list, touching, river = Expansion.frontier(m.grid, c.attacker, c.target, c.cities, c.map)
		local line = c.line
		if #list ~= #line.list then
			return false,
				string.format("%d→%d: клеток %d, в кеше %d", c.attacker, c.target, #list, #line.list)
		end
		for _, cell in list do
			if line.touching[cell] ~= touching[cell] then
				return false,
					string.format(
						"%d→%d: клетка %d касаний %s, в кеше %s",
						c.attacker,
						c.target,
						cell,
						tostring(touching[cell]),
						tostring(line.touching[cell])
					)
			end
			if (line.river[cell] == true) ~= (river[cell] == true) then
				return false,
					string.format(
						"%d→%d: клетка %d «за рекой» не совпадает",
						c.attacker,
						c.target,
						cell
					)
			end
			if (line.index :: { [number]: number })[cell] == nil or line.list[(line.index :: any)[cell]] ~= cell then
				return false,
					string.format("%d→%d: индекс клетки %d сбит", c.attacker, c.target, cell)
			end
		end
	end
	return true, nil
end

T.describe("Кеш линий фронта", function()
	T.it(
		"в партии ботов на «Европе» кеш всегда совпадает со свежим пересчётом (реки, города, окружения)",
		function()
			local map = MapFormat.fromModule((require :: any)("../maps/Europe") :: MapFormat.MapModule)
			local m = MatchSim.new(map, 777)
			m.targetNations = 16
			MatchSim.startPick(m)
			while m.phase ~= "Play" do
				MatchSim.step(m, DT)
			end
			m.victory = false
			local checks, lines = 0, 0
			for tick = 1, 150 * Config.Sim.TickRate do
				MatchSim.step(m, DT)
				Grid.takeChanges(m.grid)
				MatchSim.takeEvents(m)
				if tick % 25 == 0 then
					local ok, why = sameAsFresh(m)
					if not ok then
						error(why)
					end
					checks += 1
					for _ in m.frontCache.lines do
						lines += 1
					end
				end
			end
			T.expect(checks > 0).toBe(true)
			T.expect(lines > 0).toBe(true)
		end
	)

	T.it(
		"«Потоп»: клетки уходят под воду — кеш линий совпадает со свежим пересчётом (§5.3)",
		function()
			local map = MapFormat.fromModule((require :: any)("../maps/Mediterranean") :: MapFormat.MapModule)
			local m = MatchSim.new(map, 91)
			m.targetNations = 10
			MatchSim.startPick(m)
			while m.phase ~= "Play" do
				MatchSim.step(m, DT)
			end
			m.victory = false
			local land = m.grid.capturableCount
			for tick = 1, 90 * Config.Sim.TickRate do
				MatchSim.step(m, DT)
				Grid.takeChanges(m.grid)
				MatchSim.takeEvents(m)
				if tick % (20 * Config.Sim.TickRate) == 0 then
					MatchSim.floodStep(m)
					local ok, why = sameAsFresh(m)
					if not ok then
						error(why)
					end
				end
			end
			T.expect(m.flood.step).toBe(4)
			T.expect(m.grid.capturableCount < land).toBe(true)
		end
	)
end)
