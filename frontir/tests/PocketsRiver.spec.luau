--!strict
-- §15х ч.8: река не режет державу на котлы (котёл — земля, окружённая чужой землёй, а не рекой).
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Grid = require("../src/shared/Grid")
local Pockets = require("../src/shared/Pockets")

local function noCity(): boolean
	return false
end

T.describe("Котлы и реки (§15х ч.8)", function()
	T.it("земля за рекой связана со столицей — не котёл", function()
		local map = TinyMap.fromRows({
			"~~~~~~~~~~~~~~",
			"~....r.......~",
			"~....r.......~",
			"~....r....~~~~",
			"~~~~~~~~~~~~~~",
		})
		local g = Grid.new(map)
		local w = map.width
		for y = 1, 3 do
			for x = 1, 12 do
				if Grid.isCapturable(g, y * w + x) then
					Grid.setOwner(g, y * w + x, 1)
				end
			end
		end
		local result = Pockets.compute(g, 1, 2 * w + 2, noCity, 0, nil)
		T.expect(#result.pockets).toBe(0)
	end)

	T.it("река шире RiverMaxWidth — уже не мост; кусок за ней — котёл", function()
		local map = TinyMap.fromRows({
			"~~~~~~~~~~~~",
			"~..rrrr....~",
			"~..rrrr....~",
			"~~~~~~~~~~~~",
		})
		local g = Grid.new(map)
		local w = map.width
		for y = 1, 2 do
			for x = 1, 10 do
				if Grid.isCapturable(g, y * w + x) then
					Grid.setOwner(g, y * w + x, 1)
				end
			end
		end
		local result = Pockets.compute(g, 1, 1 * w + 1, noCity, 0, nil)
		T.expect(#result.pockets).toBe(1)
	end)

	T.it(
		"через реку на чужую землю — не мост: кусок, окружённый врагом, остаётся котлом",
		function()
			local map = TinyMap.fromRows({
				"~~~~~~~~~~",
				"~...r....~",
				"~...r....~",
				"~~~~~~~~~~",
			})
			local g = Grid.new(map)
			local w = map.width
			for y = 1, 2 do
				for x = 1, 8 do
					if Grid.isCapturable(g, y * w + x) then
						Grid.setOwner(g, y * w + x, if x <= 3 then 1 elseif x <= 6 then 2 else 1)
					end
				end
			end
			local result = Pockets.compute(g, 1, 1 * w + 1, noCity, 0, nil)
			T.expect(#result.pockets).toBe(1)
			T.expect(result.cells).toBe(4)
		end
	)
end)
