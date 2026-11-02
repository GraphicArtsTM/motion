--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Config = require("../src/shared/Config")
local MapData = require("../src/shared/MapData")
local MapGen = require("../src/shared/MapGen")
local Types = require("../src/shared/Types")

local Terrain = Types.Terrain
local params = Config.MapGen.Pangea
local map = Fixtures.pangea
local stats = Fixtures.pangeaStats
local w, h = map.width, map.height

local function isLand(i: number): boolean
	return buffer.readu8(map.terrain, i) ~= Terrain.Water
end

T.describe("MapGen «Пангея»", function()
	T.it("размер и имя из Config", function()
		T.expect(w).toBe(params.Width)
		T.expect(h).toBe(params.Height)
		T.expect(map.name).toBe("Pangea")
	end)

	T.it("тот же сид — побайтно та же карта", function()
		local again = MapGen.generate(params)
		T.expect(MapData.equals(map, again)).toBe(true)
	end)

	T.it("другой сид — другая карта", function()
		local p = table.clone(params)
		p.Seed += 1
		local other = MapGen.generate(p)
		T.expect(MapData.equals(map, other)).toBe(false)
	end)

	T.it("доля суши близка к заданной", function()
		T.expect(stats.landShare).toBeNear(params.LandShare, 0.03)
	end)

	T.it("по краям карты только вода", function()
		for x = 0, w - 1 do
			for _, y in { 0, params.EdgeWater - 1, h - params.EdgeWater, h - 1 } do
				T.expect(isLand(y * w + x)).toBe(false)
			end
		end
		for y = 0, h - 1 do
			for _, x in { 0, w - 1 } do
				T.expect(isLand(y * w + x)).toBe(false)
			end
		end
	end)

	T.it(
		"один материк: крупнейший кусок суши — не меньше 95% суши",
		function()
			local mask = buffer.create(w * h)
			local land = 0
			for i = 0, w * h - 1 do
				if isLand(i) then
					buffer.writeu8(mask, i, 1)
					land += 1
				end
			end
			local _, sizes = MapGen.components(w, h, mask, 1)
			local largest = 0
			for _, size in sizes do
				largest = math.max(largest, size)
			end
			T.expect(largest / land >= 0.95).toBe(true)
			for _, size in sizes do
				T.expect(size == largest or size >= params.MinIslandCells).toBe(true)
			end
		end
	)

	T.it("есть все типы местности", function()
		local counts = MapData.terrainCounts(map)
		for _, id in Types.TerrainIds do
			T.expect((counts[id] or 0) > 0).toBe(true)
		end
	end)

	T.it("горы и холмы — заданные доли суши", function()
		local counts = MapData.terrainCounts(map)
		local land = w * h - counts[Terrain.Water]
		-- Озёра и реки съедают немного суши, поэтому допуск 2 п.п.
		T.expect(counts[Terrain.Mountains] / land).toBeNear(params.MountainShare, 0.02)
		T.expect(counts[Terrain.Hills] / land).toBeNear(params.HillShare, 0.02)
	end)

	T.it("озёра: есть внутренние водоёмы, не связанные с морем", function()
		local mask = buffer.create(w * h)
		for i = 0, w * h - 1 do
			if not isLand(i) then
				buffer.writeu8(mask, i, 1)
			end
		end
		local _, _, touchesEdge = MapGen.components(w, h, mask, 1)
		local inland = 0
		for _, edge in touchesEdge do
			if not edge then
				inland += 1
			end
		end
		T.expect(stats.lakes).toBe(params.LakeCount)
		T.expect(inland >= params.LakeCount).toBe(true)
	end)

	T.it("реки 4-связны и каждая доходит до воды", function()
		T.expect(stats.rivers).toBe(params.RiverCount)
		local mask = buffer.create(w * h)
		for i = 0, w * h - 1 do
			if buffer.readu8(map.terrain, i) == Terrain.River then
				buffer.writeu8(mask, i, 1)
			end
		end
		local labels, sizes = MapGen.components(w, h, mask, 1)
		local reachesWater: { [number]: boolean } = {}
		for i = 0, w * h - 1 do
			local label = buffer.readu32(labels, i * 4)
			if label ~= 0 then
				local x, y = i % w, i // w
				for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local nx, ny = x + d[1], y + d[2]
					if MapData.inBounds(map, nx, ny) and not isLand(ny * w + nx) then
						reachesWater[label] = true
					end
				end
			end
		end
		for label in sizes do
			T.expect(reachesWater[label]).toBe(true)
		end
	end)

	T.it("провинций пока нет (этап 3)", function()
		for i = 0, w * h - 1, 97 do
			T.expect(MapData.getProvince(map, i)).toBe(0)
		end
	end)
end)
