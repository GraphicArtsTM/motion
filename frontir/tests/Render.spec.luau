--!strict
local fs = require("@lune/fs")

local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local CameraMath = require("../src/shared/CameraMath")
local Config = require("../src/shared/Config")
local MapPaint = require("../src/shared/MapPaint")
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

	T.it("все пиксели — цвета палитры", function()
		local allowed: { [number]: boolean } = {}
		for _, s in Palette.Swatches do
			allowed[Palette.pack(Palette.rgb(s.name))] = true
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
	end)

	T.it("глубина воды: у берега мель, вдали глубина", function()
		local shallows = Palette.pack(Palette.rgb("Shallows"))
		local abyss = Palette.pack(Palette.rgb("Abyss"))
		local function packedAt(i: number): number
			local o = i * 4
			return buffer.readu8(colors, o) * 65536 + buffer.readu8(colors, o + 1) * 256 + buffer.readu8(colors, o + 2)
		end
		T.expect(packedAt(0)).toBe(abyss) -- угол карты — открытое море
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
		T.expect(s.zoom).toBe(2)
		local ox, oy = CameraMath.canvasOffset(s)
		T.expect(ox).toBe((1280 - W * 2) // 2)
		T.expect(oy).toBe((720 - H * 2) // 2)
	end)

	T.it("на телефоне карта влезает при зуме ×1", function()
		local s = CameraMath.new(W, H, 844, 390)
		T.expect(s.zoom).toBe(1)
		T.expect(W * s.zoom <= 844 and H * s.zoom <= 390).toBe(true)
	end)

	T.it("зум ограничен диапазоном из Config и всегда целый", function()
		local s = CameraMath.new(W, H, 1280, 720)
		CameraMath.zoomAt(s, 100, 640, 360)
		T.expect(s.zoom).toBe(Config.Render.ZoomMax)
		CameraMath.zoomAt(s, -5, 640, 360)
		T.expect(s.zoom).toBe(Config.Render.ZoomMin)
		CameraMath.zoomAt(s, 4.4, 640, 360)
		T.expect(s.zoom).toBe(4)
	end)

	T.it(
		"зум к курсору: клетка под курсором остаётся под курсором",
		function()
			local s = CameraMath.new(W, H, 1280, 720)
			CameraMath.zoomAt(s, 6, 640, 360)
			local sx, sy = 700, 300
			local wx, wy = CameraMath.screenToWorld(s, sx, sy)
			CameraMath.zoomAt(s, 9, sx, sy)
			local wx2, wy2 = CameraMath.screenToWorld(s, sx, sy)
			T.expect(wx2).toBeNear(wx, 1e-9)
			T.expect(wy2).toBeNear(wy, 1e-9)
		end
	)

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
		local s2 = CameraMath.new(W, H, 1280, 720)
		T.expect((CameraMath.cellAt(s2, 1, 1))).toBe(nil) -- поле вне карты
	end)
end)
