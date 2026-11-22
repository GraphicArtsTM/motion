--!strict
-- §15ы Ы4: гладкие картинки городов и кораблей на карте — обрезаны по рисунку, в пределах 96 px, с прозрачным фоном.
local T = require("./lib/TestKit")
local MapArt = require("../src/shared/MapArt")

local NAMES = { "City1", "City2", "City3", "City4", "City5", "CityCapital", "Destroyer", "Transport", "Merchant" }

-- Рамка видимых пикселей (альфа ≥ 128).
local function bounds(px: buffer, w: number, h: number): (number, number, number, number)
	local x0, y0, x1, y1 = w, h, -1, -1
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			if buffer.readu8(px, (y * w + x) * 4 + 3) >= 128 then
				x0, y0 = math.min(x0, x), math.min(y0, y)
				x1, y1 = math.max(x1, x), math.max(y1, y)
			end
		end
	end
	return x0, y0, x1, y1
end

T.describe("Картинки на карте (§15ы Ы4)", function()
	T.it(
		"у каждого города и корабля есть гладкая картинка не больше 96 px",
		function()
			for _, name in NAMES do
				T.expect(MapArt.has(name)).toBe(true)
				local w, h = MapArt.size(name)
				T.expect(w > 0 and h > 0 and math.max(w, h) <= 96).toBe(true)
				T.expect(math.max(w, h)).toBe(96) -- большая сторона — во весь размер
			end
		end
	)

	T.it(
		"пустые поля обрезаны: рисунок доходит до края (поле не шире 4 px), углы прозрачны",
		function()
			for _, name in NAMES do
				local w, h = MapArt.size(name)
				local px = MapArt.paint(name) :: buffer
				local x0, y0, x1, y1 = bounds(px, w, h)
				T.expect(math.max(x0, y0, w - 1 - x1, h - 1 - y1) <= 4).toBe(true)
				T.expect(buffer.readu8(px, 3)).toBe(0) -- левый верхний угол прозрачен
			end
		end
	)

	T.it(
		"корабли — во всю ширину: шире, чем выше; зеркало — то же, отражённое",
		function()
			for _, name in { "Destroyer", "Transport", "Merchant" } do
				local w, h = MapArt.size(name)
				T.expect(w >= 1.4 * h).toBe(true)
				local a = MapArt.paint(name) :: buffer
				local b = MapArt.paint(name, true) :: buffer
				for y = 0, h - 1, 7 do
					for x = 0, w - 1, 5 do
						T.expect(buffer.readu32(b, (y * w + x) * 4)).toBe(buffer.readu32(a, (y * w + (w - 1 - x)) * 4))
					end
				end
			end
		end
	)

	T.it("нет картинки — nil и размер 0", function()
		T.expect(MapArt.has("Nope")).toBe(false)
		T.expect(MapArt.paint("Nope")).toBe(nil)
		T.expect((MapArt.size("Nope"))).toBe(0)
	end)
end)

return nil
