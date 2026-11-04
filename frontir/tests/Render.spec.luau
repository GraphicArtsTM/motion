--!strict
local fs = require("@lune/fs")

local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local CameraMath = require("../src/shared/CameraMath")
local Config = require("../src/shared/Config")
local MapPaint = require("../src/shared/MapPaint")
local NationColors = require("../src/shared/NationColors")
local Palette = require("../src/shared/Palette")
local Types = require("../src/shared/Types")

local map = Fixtures.pangea

T.describe("Palette", function()
	T.it("ровно 32 цвета, имена и hex уникальны", function()
		T.expect(#Palette.Swatches).toBe(32)
		local names, hexes = {}, {}
		for _, s in Palette.Swatches do
			T.expect(names[s.name]).toBe(nil)
			T.expect(hexes[s.hex]).toBe(nil)
			names[s.name] = true
			hexes[s.hex] = true
		end
	end)

	T.it("docs/palette.md совпадает с кодом", function()
		local doc = fs.readFile("docs/palette.md")
		local fromDoc: { [string]: string } = {}
		local count = 0
		for name, hex in string.gmatch(doc, "| %d+ | (%w+) | `#(%x+)` |") do
			fromDoc[name :: string] = string.lower(hex :: string)
			count += 1
		end
		T.expect(count).toBe(#Palette.Swatches)
		for _, s in Palette.Swatches do
			T.expect(fromDoc[s.name]).toBe(s.hex)
		end
	end)

	T.it("docs/palette.png соответствует коду (иначе: lune run tools/palette_preview)", function()
		local png = fs.readFile("docs/palette.png")
		T.expect(string.sub(png, 1, 8)).toBe("\137PNG\r\n\26\n")
		local hexes: { string } = {}
		for _, s in Palette.Swatches do
			table.insert(hexes, s.hex)
		end
		local stamp = "Frontir-Palette\0" .. table.concat(hexes, ",") .. "|" .. table.concat(NationColors.Hex, ",")
		T.expect(string.find(png, stamp, 1, true) ~= nil).toBe(true)
	end)

	T.it("таблица цветов держав в docs/palette.md совпадает с кодом", function()
		local doc = fs.readFile("docs/palette.md")
		local count = 0
		for index, hex, borderHex in string.gmatch(doc, "| (%d+) | `#(%x+)` | `#(%x+)` |") do
			local i = tonumber(index) :: number
			count += 1
			T.expect(hex).toBe(NationColors.Hex[i])
			local b = NationColors.Borders[i]
			T.expect(borderHex).toBe(string.format("%02x%02x%02x", b.r, b.g, b.b))
		end
		T.expect(count).toBe(NationColors.Count)
	end)

	T.it("неизвестный цвет — ошибка", function()
		T.expect(function()
			Palette.rgb("Фиолетовый")
		end).toThrow()
	end)
end)

T.describe("MapPaint", function()
	local depth = MapPaint.waterDepth(map)
	local colors = MapPaint.paint(map, depth)

	T.it("RGBA-буфер на всю карту, альфа 255", function()
		T.expect(buffer.len(colors)).toBe(map.width * map.height * 4)
		for i = 0, map.width * map.height - 1, 13 do
			T.expect(buffer.readu8(colors, i * 4 + 3)).toBe(255)
		end
	end)

	T.it(
		"все пиксели — цвета палитры (или палитры в тени границы провинции)",
		function()
			local allowed: { [number]: boolean } = {}
			local k = Config.Render.ProvinceBorderShade
			for _, s in Palette.Swatches do
				local c = Palette.rgb(s.name)
				allowed[Palette.pack(c)] = true
				allowed[Palette.pack({ r = math.floor(c.r * k), g = math.floor(c.g * k), b = math.floor(c.b * k) })] =
					true
			end
			for i = 0, map.width * map.height - 1 do
				local o = i * 4
				local packed = buffer.readu8(colors, o) * 65536
					+ buffer.readu8(colors, o + 1) * 256
					+ buffer.readu8(colors, o + 2)
				if not allowed[packed] then
					error(string.format("клетка %d: цвет %06x не из палитры", i, packed))
				end
			end
		end
	)

	T.it("глубина воды: у берега мель, вдали глубина", function()
		local shallows = Palette.pack(Palette.rgb("Shallows"))
		local abyss = Palette.pack(Palette.rgb("Abyss"))
		local function packedAt(i: number): number
			local o = i * 4
			return buffer.readu8(colors, o) * 65536 + buffer.readu8(colors, o + 1) * 256 + buffer.readu8(colors, o + 2)
		end
		T.expect(packedAt(0)).toBe(abyss) -- угол карты — открытое море
		-- Все клетки по краю карты — цвет фона вокруг неё: шва между картой и океаном нет.
		local ocean = Palette.pack(Palette.rgb(MapPaint.OceanColorName))
		T.expect(ocean).toBe(abyss)
		for x = 0, map.width - 1 do
			T.expect(packedAt(x)).toBe(ocean)
			T.expect(packedAt((map.height - 1) * map.width + x)).toBe(ocean)
		end
		for y = 0, map.height - 1 do
			T.expect(packedAt(y * map.width)).toBe(ocean)
			T.expect(packedAt(y * map.width + map.width - 1)).toBe(ocean)
		end
		local foundShallow = false
		for i = 0, map.width * map.height - 1 do
			if buffer.readu8(map.terrain, i) == Types.Terrain.Water and buffer.readu16(depth, i * 2) == 1 then
				T.expect(packedAt(i)).toBe(shallows)
				foundShallow = true
				break
			end
		end
		T.expect(foundShallow).toBe(true)
	end)

	T.it("copyRect вырезает чанк построчно", function()
		local x0, y0, cw, ch = 250, 100, 7, 5
		local chunk = MapPaint.copyRect(colors, map.width, x0, y0, cw, ch)
		T.expect(buffer.len(chunk)).toBe(cw * ch * 4)
		for row = 0, ch - 1 do
			for col = 0, cw - 1 do
				local a = buffer.readu32(chunk, (row * cw + col) * 4)
				local b = buffer.readu32(colors, ((y0 + row) * map.width + x0 + col) * 4)
				T.expect(a).toBe(b)
			end
		end
	end)

	T.it("маска бликов — только море нужной глубины", function()
		local mask = MapPaint.sparkleMask(map, depth, Config.Render.SparkleMinDepth)
		local count = 0
		for i = 0, map.width * map.height - 1 do
			if buffer.readu8(mask, i) == 1 then
				count += 1
				T.expect(buffer.readu8(map.terrain, i)).toBe(Types.Terrain.Water)
				T.expect(buffer.readu16(depth, i * 2) >= Config.Render.SparkleMinDepth).toBe(true)
			end
		end
		T.expect(count > 1000).toBe(true)
	end)
end)

T.describe("CameraMath", function()
	local W, H = 512, 320

	T.it("новая камера показывает карту целиком и по центру", function()
		local s = CameraMath.new(W, H, 1280, 720)
		T.expect(s.zoom).toBe(2) -- 2.16 с отступом → целое 2
		local ox, oy = CameraMath.canvasOffset(s)
		T.expect(ox).toBe((1280 - W * 2) // 2)
		T.expect(oy).toBe((720 - H * 2) // 2)
	end)

	T.it(
		"обзорный зум ниже ×2 дробный и почти заполняет экран (случай со скриншота)",
		function()
			local s = CameraMath.new(W, H, 1440, 611)
			T.expect(s.zoom).toBeNear(611 / 320 * Config.Render.FitMargin, 1e-9)
			T.expect(H * s.zoom <= 611 and H * s.zoom >= 611 * 0.9).toBe(true)
		end
	)

	T.it("на телефоне карта влезает целиком", function()
		local s = CameraMath.new(W, H, 844, 390)
		T.expect(W * s.zoom <= 844 and H * s.zoom <= 390).toBe(true)
		T.expect(H * s.zoom >= 390 * 0.9).toBe(true)
	end)

	T.it(
		"зум ограничен: не мельче «всей карты» и не крупнее ZoomMax",
		function()
			local s = CameraMath.new(W, H, 1280, 720)
			CameraMath.zoomAt(s, 100, 640, 360)
			T.expect(s.zoom).toBe(Config.Render.ZoomMax)
			CameraMath.zoomAt(s, -5, 640, 360)
			T.expect(s.zoom).toBe(CameraMath.minZoom(s))
			CameraMath.zoomAt(s, 4.4, 640, 360) -- в анимации зум бывает дробным
			T.expect(s.zoom).toBeNear(4.4, 1e-9)
			T.expect(CameraMath.snapZoom(s, 4.4)).toBe(4)
		end
	)

	T.it(
		"колесо: от ×2 только целые шаги, каждый щелчок меняет зум, туда и обратно",
		function()
			local s = CameraMath.new(W, H, 1440, 611)
			local z = s.zoom
			local up: { number } = {}
			while true do
				local t = CameraMath.wheelTarget(s, z, 1)
				if t == z then
					break
				end
				T.expect(t > z).toBe(true)
				if t >= Config.Render.IntegerZoomFrom then
					T.expect(t).toBe(math.round(t))
				end
				table.insert(up, t)
				z = t
			end
			T.expect(z).toBe(Config.Render.ZoomMax)
			T.expect(up[1]).toBe(Config.Render.IntegerZoomFrom) -- с обзорного 1.83 сразу на ×2
			T.expect(#up <= 10).toBe(true) -- от обзора до ×12 — не больше 10 щелчков
			while true do
				local t = CameraMath.wheelTarget(s, z, -1)
				if t == z then
					break
				end
				T.expect(t < z).toBe(true)
				z = t
			end
			T.expect(z).toBe(CameraMath.minZoom(s))
		end
	)

	T.it(
		"зум к курсору: клетка под курсором остаётся под курсором",
		function()
			local s = CameraMath.new(W, H, 1280, 720)
			CameraMath.zoomAt(s, 6, 640, 360)
			local sx, sy = 700, 300
			local wx, wy = CameraMath.screenToWorld(s, sx, sy)
			for _, z in { 9, 7.37, 12 } do
				CameraMath.zoomAt(s, z, sx, sy)
				local wx2, wy2 = CameraMath.screenToWorld(s, sx, sy)
				T.expect(wx2).toBeNear(wx, 1e-9)
				T.expect(wy2).toBeNear(wy, 1e-9)
			end
		end
	)

	T.it("границы клеток при дробном зуме стыкуются без щелей", function()
		for _, z in { 1.83, 2, 2.7, 11.3 } do
			local prev = CameraMath.cellEdge(z, 0)
			T.expect(prev).toBe(0)
			for c = 1, 600 do
				local e = CameraMath.cellEdge(z, c)
				T.expect(e >= prev).toBe(true)
				T.expect(e - prev <= math.ceil(z)).toBe(true)
				prev = e
			end
		end
	end)

	T.it("панорамирование и границы", function()
		local s = CameraMath.new(W, H, 1280, 720)
		CameraMath.zoomAt(s, 8, 640, 360)
		local x0 = s.x
		CameraMath.pan(s, -80, 0) -- палец влево — карта едет влево, камера вправо
		T.expect(s.x).toBeNear(x0 + 10, 1e-9)
		CameraMath.pan(s, 1e6, 1e6)
		T.expect(s.x).toBeNear(-Config.Render.PanMarginPx / 8, 1e-9)
		T.expect(s.y).toBeNear(-Config.Render.PanMarginPx / 8, 1e-9)
		CameraMath.pan(s, -1e6, -1e6)
		T.expect(s.x).toBeNear(W - 1280 / 8 + Config.Render.PanMarginPx / 8, 1e-9)
	end)

	T.it(
		"смена размера окна не даёт зуму стать мельче «всей карты»",
		function()
			local s = CameraMath.new(W, H, 844, 390)
			local small = s.zoom
			CameraMath.setViewSize(s, 2560, 1440)
			T.expect(s.zoom >= CameraMath.minZoom(s)).toBe(true)
			T.expect(s.zoom > small).toBe(true)
		end
	)

	T.it("клетка под точкой экрана и видимая область", function()
		local s = CameraMath.new(W, H, 1280, 720)
		CameraMath.zoomAt(s, 10, 0, 0)
		CameraMath.centerOn(s, 100, 50)
		local cx, cy = CameraMath.cellAt(s, 640, 360)
		T.expect(cx).toBe(100)
		T.expect(cy).toBe(50)
		local x0, y0, x1, y1 = CameraMath.visibleRect(s)
		T.expect(x0 <= 100 and 100 <= x1 and y0 <= 50 and 50 <= y1).toBe(true)
		T.expect(x1 - x0 + 1 >= 1280 / 10).toBe(true)
		local vx0, vy0, vx1, vy1 = CameraMath.viewRect(CameraMath.new(W, H, 1280, 720))
		T.expect(vx0 < 0 and vy0 < 0 and vx1 >= W and vy1 >= H).toBe(true) -- вокруг карты видно океан
		local s2 = CameraMath.new(W, H, 1280, 720)
		T.expect((CameraMath.cellAt(s2, 1, 1))).toBe(nil) -- поле вне карты
	end)
end)
