--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Economy = require("../src/shared/Economy")
local Grid = require("../src/shared/Grid")
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")

T.describe("Grid", function()
	T.it("вода и реки не захватываются", function()
		local g = Grid.new(TinyMap.fromRows({ "~.r^f" }))
		T.expect(Grid.isCapturable(g, 0)).toBe(false)
		T.expect(Grid.isCapturable(g, 1)).toBe(true)
		T.expect(Grid.isCapturable(g, 2)).toBe(false)
		T.expect(Grid.isCapturable(g, 3)).toBe(true)
		T.expect(g.capturableCount).toBe(3)
	end)

	T.it(
		"счётчики и множества границ совпадают с пересчётом с нуля после тысяч случайных смен",
		function()
			local map = TinyMap.plains(24, 18)
			local g = Grid.new(map)
			local rng = Rng.new(11)
			for _ = 1, 4000 do
				local i = Rng.range(rng, 0, g.size - 1)
				if Grid.isCapturable(g, i) then
					Grid.setOwner(g, i, Rng.range(rng, 0, 3))
				end
			end
			local counts: { [number]: number } = {}
			for i = 0, g.size - 1 do
				local o = Grid.getOwner(g, i)
				if o ~= 0 then
					counts[o] = (counts[o] or 0) + 1
				end
				local inSet = o ~= 0 and Grid.borderCells(g, o)[i] == true
				T.expect(inSet).toBe(Grid.isBorderCell(g, i))
			end
			for nation = 1, 3 do
				T.expect(Grid.cellsOf(g, nation)).toBe(counts[nation] or 0)
				for i in Grid.borderCells(g, nation) do
					T.expect(Grid.getOwner(g, i)).toBe(nation)
				end
			end
		end
	)

	T.it(
		"журнал изменений: без повторов, по возрастанию, очищается",
		function()
			local g = Grid.new(TinyMap.plains(10, 10))
			Grid.setOwner(g, 55, 1)
			Grid.setOwner(g, 12, 2)
			Grid.setOwner(g, 55, 2)
			Grid.setOwner(g, 33, 0) -- уже 0 — не изменение
			T.expect(Grid.takeChanges(g)).toEqual({ 12, 55 })
			T.expect(#Grid.takeChanges(g)).toBe(0)
		end
	)

	T.it("соседи державы: ничья земля и другие державы", function()
		local g = Grid.new(TinyMap.plains(10, 6))
		Grid.setOwner(g, 2 * 10 + 2, 1)
		Grid.setOwner(g, 2 * 10 + 3, 2)
		local adj = Grid.adjacentOwners(g, 1)
		T.expect(adj[0] ~= nil).toBe(true)
		T.expect(adj[2]).toBe(1)
	end)
end)

T.describe("Economy: люди", function()
	T.it(
		"логистический рост: быстрее всего в середине, не выше максимума",
		function()
			local max = 10000
			local low = Economy.growthPerSec(500, max)
			local mid = Economy.growthPerSec(5000, max)
			local high = Economy.growthPerSec(9500, max)
			T.expect(mid > low and mid > high).toBe(true)
			local p = 100
			for _ = 1, 2000 do
				p = Economy.grow(p, max, 0.1)
				T.expect(p <= max).toBe(true)
			end
			T.expect(p).toBeNear(max, 1)
		end
	)

	T.it("с нуля держава восстанавливается", function()
		T.expect(Economy.grow(0, 2000, 1) > 0).toBe(true)
	end)

	T.it(
		"излишек после потери земли тает к максимуму, но не ниже",
		function()
			local p = Economy.grow(5000, 3000, 1)
			T.expect(p < 5000 and p >= 3000).toBe(true)
		end
	)

	T.it("максимум растёт с территорией", function()
		T.expect(Economy.maxPeople(0)).toBe(Config.People.BaseMax)
		T.expect(Economy.maxPeople(100)).toBe(Config.People.BaseMax + 100 * Config.People.PerCell)
	end)
end)
