--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Base64 = require("../src/shared/Base64")
local Config = require("../src/shared/Config")
local MapData = require("../src/shared/MapData")
local MapFormat = require("../src/shared/MapFormat")
local PangeaModule = require("../maps/Pangea")

local map = Fixtures.pangea

local function smallMap(): MapData.MapData
	local m = MapData.new("Test", 7, 5, 3)
	for i = 0, 14 do
		MapData.setTerrain(m, i, i % 3)
		MapData.setProvince(m, i, if i < 7 then 0 else 300 + i)
	end
	return m
end

T.describe("MapFormat", function()
	T.it("маленькая карта туда и обратно", function()
		local m = smallMap()
		local back = MapFormat.decode(MapFormat.encode(m), m.name, m.seed)
		T.expect(MapData.equals(m, back)).toBe(true)
	end)

	T.it("«Пангея» туда и обратно через модуль (base64 по частям)", function()
		local chunks = MapFormat.toChunks(map, Config.MapFile.ChunkChars)
		for _, chunk in chunks do
			T.expect(#chunk <= Config.MapFile.ChunkChars).toBe(true)
		end
		local back = MapFormat.fromModule({
			name = map.name,
			seed = map.seed,
			width = map.width,
			height = map.height,
			formatVersion = MapFormat.FORMAT_VERSION,
			data = chunks,
		})
		T.expect(MapData.equals(map, back)).toBe(true)
	end)

	T.it("RLE реально сжимает карту", function()
		local bytes = buffer.len(MapFormat.encode(map))
		T.expect(bytes < map.width * map.height * 3 / 8).toBe(true)
	end)

	T.it("порча данных — понятная ошибка, а не мусор", function()
		local good = MapFormat.encode(smallMap())
		local function corrupted(offset: number, value: number): buffer
			local b = buffer.create(buffer.len(good))
			buffer.copy(b, 0, good)
			buffer.writeu8(b, offset, value)
			return b
		end
		T.expect(function()
			MapFormat.decode(corrupted(0, 0), "x", 0) -- сигнатура
		end).toThrow()
		T.expect(function()
			MapFormat.decode(corrupted(4, 99), "x", 0) -- версия
		end).toThrow()
		T.expect(function()
			MapFormat.decode(corrupted(9, 0), "x", 0) -- длина слоя
		end).toThrow()
		T.expect(function()
			MapFormat.decode(buffer.create(5), "x", 0) -- короче заголовка
		end).toThrow()
		local cut = buffer.create(buffer.len(good) - 1)
		buffer.copy(cut, 0, good, 0, buffer.len(cut))
		T.expect(function()
			MapFormat.decode(cut, "x", 0)
		end).toThrow()
	end)

	T.it("неизвестная местность в данных — ошибка", function()
		local m = smallMap()
		MapData.setTerrain(m, 4, 200)
		T.expect(function()
			MapFormat.decode(MapFormat.encode(m), "x", 0)
		end).toThrow()
	end)

	T.it(
		"закоммиченный maps/Pangea.luau совпадает с генератором (иначе: lune run tools/genmap Pangea)",
		function()
			-- Модуль — обычная таблица без необязательных полей (provinceNames только у реальных карт).
			local fromFile = MapFormat.fromModule(PangeaModule :: any)
			T.expect(MapData.equals(fromFile, map)).toBe(true)
			T.expect(PangeaModule.seed).toBe(Config.MapGen.Pangea.Seed)
		end
	)

	T.it("base64 модуля карты валиден целиком", function()
		local data = Base64.decode(table.concat(PangeaModule.data))
		T.expect(buffer.len(data) > 17).toBe(true)
	end)
end)
