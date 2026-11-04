--!strict
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Types = require("../src/shared/Types")
local Geo = require("../tools/lib/Geo")

-- Окно 10° × 10° на сетку 10 × 10: одна клетка — один градус.
local V: Geo.View = { lon0 = 0, lon1 = 10, lat0 = 0, lat1 = 10, width = 10, height = 10 }

local function count(mask: buffer): number
	local c = 0
	for i = 0, buffer.len(mask) - 1 do
		c += buffer.readu8(mask, i)
	end
	return c
end

T.describe("Geo: реальные карты", function()
	T.it(
		"проекция: долгота вправо, широта вверх, центр клетки туда и обратно",
		function()
			local x, y = Geo.toCell(V, 2.5, 7.5)
			T.expect(x).toBe(2.5)
			T.expect(y).toBe(2.5) -- север наверху
			local lon, lat = Geo.toLonLat(V, 2, 2)
			T.expect(lon).toBe(2.5)
			T.expect(lat).toBe(7.5)
		end
	)

	T.it(
		"многоугольник заливается по центрам клеток, дыра остаётся пустой",
		function()
			local mask = buffer.create(100)
			local outer = { { 1, 1 }, { 9, 1 }, { 9, 9 }, { 1, 9 }, { 1, 1 } }
			local hole = { { 4, 4 }, { 6, 4 }, { 6, 6 }, { 4, 6 }, { 4, 4 } }
			Geo.fillPolygon(mask, V, { outer, hole }, 1)
			T.expect(count(mask)).toBe(64 - 4) -- 8 × 8 без 2 × 2
			T.expect(buffer.readu8(mask, 5 * 10 + 5)).toBe(0) -- в дыре
			T.expect(buffer.readu8(mask, 1 * 10 + 1)).toBe(1)
			T.expect(buffer.readu8(mask, 0)).toBe(0) -- снаружи
		end
	)

	T.it(
		"река рисуется сплошной: соседние клетки линии касаются стороной",
		function()
			local mask = buffer.create(100)
			Geo.drawPolyline(mask, V, { { 0.5, 9.5 }, { 9.5, 0.5 } }, 1) -- диагональ с северо-запада на юго-восток
			for y = 0, 9 do
				for x = 0, 9 do
					if buffer.readu8(mask, y * 10 + x) == 1 and not (x == 9 and y == 9) then
						-- У каждой клетки линии, кроме конца, есть сосед по стороне на линии.
						local neighbours = 0
						for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
							local nx, ny = x + d[1], y + d[2]
							if
								nx >= 0
								and ny >= 0
								and nx < 10
								and ny < 10
								and buffer.readu8(mask, ny * 10 + nx) == 1
							then
								neighbours += 1
							end
						end
						T.expect(neighbours >= 1).toBe(true)
					end
				end
			end
			T.expect(buffer.readu8(mask, 0)).toBe(1) -- северо-западный конец (клетка 0, 0)
			T.expect(buffer.readu8(mask, 9 * 10 + 9)).toBe(1) -- юго-восточный конец (9, 9)
			T.expect(count(mask) >= 19).toBe(true) -- по диагонали без дыр: не меньше 2 × 10 − 1 клеток
		end
	)

	T.it(
		"высоты: среднее по точкам клетки, пустые клетки берут значение соседей",
		function()
			local e = Geo.newElevation(V)
			local csv =
				"latitude,longitude,altitude\ndegrees_north,degrees_east,m\n9.5,0.2,100\n9.5,0.7,300\n0.5,9.5,-50\n"
			T.expect(Geo.addElevationCsv(e, V, csv)).toBe(3)
			Geo.finishElevation(e, V)
			T.expect(e.value[1]).toBe(200) -- клетка (0,0): среднее 100 и 300
			T.expect(e.value[100]).toBe(-50) -- клетка (9,9)
			T.expect(e.value[2]).toBe(200) -- (1,0) пустая — от соседа
		end
	)

	T.it("местность: горы, холмы, пустыня, тундра, лес, равнина", function()
		local cfg = Config.RealMapTerrain
		local Tr = Types.Terrain
		T.expect(Geo.landTerrain(cfg.MountainMeters + 1, 0, false, 45, 0.9)).toBe(Tr.Mountains)
		T.expect(Geo.landTerrain(cfg.MountainBaseMeters + 1, cfg.MountainRelief + 1, false, 45, 0.9)).toBe(Tr.Mountains)
		T.expect(Geo.landTerrain(cfg.HillMeters + 1, 0, false, 45, 0.9)).toBe(Tr.Hills)
		T.expect(Geo.landTerrain(100, cfg.HillRelief + 1, false, 45, 0.9)).toBe(Tr.Hills)
		-- На крупных клетках порог перепада выше: тот же перепад — уже не холмы.
		T.expect(Geo.landTerrain(100, cfg.HillRelief + 1, false, 45, 0.9, 0, 2)).toBe(Tr.Plains)
		T.expect(Geo.landTerrain(100, 0, true, 25, 0.9)).toBe(Tr.Desert)
		T.expect(Geo.landTerrain(100, 0, false, cfg.TundraLatitude + 1, 0.9)).toBe(Tr.Tundra)
		-- Ледяной щит: высоко, но ровно и у полюса — тундра, а не горы.
		T.expect(Geo.landTerrain(2800, 100, false, 72, 0.9)).toBe(Tr.Tundra)
		T.expect(Geo.landTerrain(100, 0, false, 5, 0)).toBe(Tr.Forest) -- тропики, шум ниже доли леса
		T.expect(Geo.landTerrain(100, 0, false, 5, 1)).toBe(Tr.Plains)
		-- Доля леса меняется по широте плавно.
		local a, b = Geo.forestShare(49), Geo.forestShare(51)
		T.expect(math.abs(a - b) < 0.05).toBe(true)
	end)

	T.it(
		"имена провинций — без реальных стран и спорных территорий",
		function()
			T.expect(Geo.isNameAllowed("Альпы", "Alps")).toBe(true)
			T.expect(Geo.isNameAllowed("Сахара", "Sahara")).toBe(true)
			T.expect(Geo.isNameAllowed("Скандинавия", "Scandinavia")).toBe(true)
			T.expect(Geo.isNameAllowed("Канадский щит", "Canadian Shield")).toBe(false)
			T.expect(Geo.isNameAllowed("Великая Китайская равнина", "North China Plain"))
				.toBe(false)
			T.expect(Geo.isNameAllowed("Индийский субконтинент", "Indian subcontinent"))
				.toBe(false)
			T.expect(Geo.isNameAllowed("Исландия", "Iceland")).toBe(false)
			T.expect(Geo.isNameAllowed("Тибетское нагорье", "Tibetan Plateau")).toBe(false)
			T.expect(Geo.isNameAllowed("Крым", "Crimea")).toBe(false)
			T.expect(Geo.isNameAllowed("Соломоновы острова", "Solomon Islands")).toBe(false)
			T.expect(Geo.isNameAllowed("Панамский перешеек", "Isthmus of Panama")).toBe(false)
			T.expect(Geo.isNameAllowed("", "Nameless")).toBe(false)
			T.expect(Geo.cleanName(" горы Эльбу\u{301}рс ")).toBe("горы Эльбурс")
		end
	)
end)
