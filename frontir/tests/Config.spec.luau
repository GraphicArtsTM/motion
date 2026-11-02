--!strict
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Types = require("../src/shared/Types")

-- Config.Units — запись (record); для перебора в тестах смотрим на неё как на словарь.
local unitsByKind: { [string]: Types.UnitStats } = Config.Units :: any

T.describe("Config", function()
	T.it("заморожен целиком", function()
		T.expect(table.isfrozen(Config)).toBe(true)
		T.expect(table.isfrozen(Config.Sim)).toBe(true)
		T.expect(table.isfrozen(Config.Units.Infantry)).toBe(true)
		T.expect(function()
			(Config.Sim :: any).TickRate = 99
		end).toThrow()
	end)

	T.it("тик сервера 10 Гц (§12)", function()
		T.expect(Config.Sim.TickRate).toBe(10)
	end)

	T.it("зум ×1–×12 и чанк — степень двойки не больше 1024 (§3)", function()
		T.expect(Config.Render.ZoomMin).toBe(1)
		T.expect(Config.Render.ZoomMax).toBe(12)
		local c = Config.Render.ChunkSize
		T.expect(c > 0 and bit32.band(c, c - 1) == 0 and c <= 1024).toBe(true)
	end)

	T.it("у каждого типа местности есть параметры (§6.1)", function()
		for _, id in Types.TerrainIds do
			local stats = Config.Terrain[id]
			T.expect(stats ~= nil).toBe(true)
			if id == Types.Terrain.Water then
				T.expect(stats.borderPassable).toBe(false)
				T.expect(stats.armySpeed).toBe(0) -- по воде только флот
			elseif id == Types.Terrain.River then
				-- §4: реки не пускают границу, армии идут с замедлением
				T.expect(stats.borderPassable).toBe(false)
				T.expect(stats.armySpeed > 0 and stats.armySpeed < 1).toBe(true)
			else
				T.expect(stats.borderPassable).toBe(true)
				T.expect(stats.captureCost > 0).toBe(true)
				T.expect(stats.armySpeed > 0 and stats.armySpeed <= 1).toBe(true)
			end
		end
	end)

	T.it("TerrainIds совпадает с перечислением Terrain", function()
		local count = 0
		for _, id in Types.Terrain :: { [string]: number } do
			count += 1
			T.expect(table.find(Types.TerrainIds, id) ~= nil).toBe(true)
		end
		T.expect(count).toBe(#Types.TerrainIds)
	end)

	T.it("id местности влезают в байт и уникальны", function()
		local seen: { [number]: boolean } = {}
		for _, id in Types.TerrainIds do
			T.expect(id >= 0 and id <= 255).toBe(true)
			T.expect(seen[id]).toBe(nil)
			seen[id] = true
		end
	end)

	T.it("у юнитов положительные цена и скорость (§7)", function()
		for _, u in unitsByKind do
			T.expect(u.cost > 0).toBe(true)
			T.expect(u.speed > 0).toBe(true)
			T.expect(u.oil >= 0).toBe(true)
		end
	end)

	T.it("юнит требует только существующее здание", function()
		for _, u in unitsByKind do
			if u.requires ~= nil then
				T.expect((Config.Buildings :: any)[u.requires] ~= nil).toBe(true)
			end
		end
	end)

	T.it("цели победы — доли от 0 до 1", function()
		T.expect(Config.Match.VictoryLandShareFfa).toBeNear(0.6)
		T.expect(Config.Match.VictoryLandShareTeams).toBeNear(0.7)
	end)
end)
