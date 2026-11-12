--!strict
-- Контуры подсветок карты (§15х ч.8).
local T = require("./lib/TestKit")
local MapOutline = require("../src/shared/MapOutline")
local TerritoryPaint = require("../src/shared/TerritoryPaint")
local Config = require("../src/shared/Config")

-- Карта 10×6: держава 1 — квадрат 2..5 × 1..4, держава 2 — отдельный кусок 8..9 × 0..1, ещё кусок 1 — клетка (8, 4).
local W, H = 10, 6
local owners = buffer.create(W * H * 2)
local function set(x: number, y: number, o: number)
	buffer.writeu16(owners, (y * W + x) * 2, o)
end
for y = 1, 4 do
	for x = 2, 5 do
		set(x, y, 1)
	end
end
for y = 0, 1 do
	for x = 8, 9 do
		set(x, y, 2)
	end
end
set(8, 4, 1)
local function ownerAt(i: number): number
	return buffer.readu16(owners, i * 2)
end

T.describe("Контуры карты (§15х ч.8)", function()
	T.it("шаг выборки растёт с размером кадра", function()
		T.expect(MapOutline.stride(100, 100, 40000)).toBe(1)
		T.expect(MapOutline.stride(1000, 1000, 40000)).toBe(5)
		T.expect(MapOutline.stride(0, 0, 0)).toBe(1)
	end)

	T.it(
		"контур державы: только клетки края, в прямоугольнике, не больше max",
		function()
			local all = MapOutline.outline(ownerAt, W, H, 1, 0, 0, W - 1, H - 1, 1, 100)
			-- Квадрат 4×4: края — 12 клеток, плюс одинокая клетка (8, 4).
			T.expect(#all).toBe(13)
			for _, i in all do
				T.expect(ownerAt(i)).toBe(1)
				local x, y = i % W, i // W
				T.expect(not (x >= 3 and x <= 4 and y >= 2 and y <= 3)).toBe(true) -- середина квадрата — не край
			end
			T.expect(#MapOutline.outline(ownerAt, W, H, 1, 0, 0, 5, 5, 1, 100)).toBe(12)
			T.expect(#MapOutline.outline(ownerAt, W, H, 1, 0, 0, W - 1, H - 1, 1, 5)).toBe(5)
			T.expect(#MapOutline.outline(ownerAt, W, H, 0, 0, 0, W - 1, H - 1, 1, 100)).toBe(0)
		end
	)

	T.it(
		"связный кусок: только свой кусок, край, центр; предел клеток",
		function()
			local c = MapOutline.component(ownerAt, W, H, 3 * W + 3, 1000)
			T.expect(#c.cells).toBe(16)
			T.expect(#c.edge).toBe(12)
			T.expect(c.full).toBe(true)
			T.expect(math.abs(c.cx - 4) < 1e-9 and math.abs(c.cy - 3) < 1e-9).toBe(true)
			local lone = MapOutline.component(ownerAt, W, H, 4 * W + 8, 1000)
			T.expect(#lone.cells).toBe(1)
			local cut = MapOutline.component(ownerAt, W, H, 3 * W + 3, 5)
			T.expect(#cut.cells).toBe(5)
			T.expect(cut.full).toBe(false)
			T.expect(#MapOutline.component(ownerAt, W, H, 0, 1000).cells).toBe(0) -- ничья клетка
		end
	)

	T.it(
		"граница в 2 клетки: внешняя — 1, следующая — 2, середина — 0",
		function()
			T.expect(Config.Render.BorderWidth).toBe(2)
			T.expect(TerritoryPaint.borderDepth(owners, W, H, 1 * W + 2)).toBe(1)
			-- Квадрат 4×4: все внутренние клетки на расстоянии 2 от края.
			T.expect(TerritoryPaint.borderDepth(owners, W, H, 2 * W + 3)).toBe(2)
			local big = buffer.create(9 * 9 * 2)
			for i = 0, 80 do
				buffer.writeu16(big, i * 2, 3)
			end
			T.expect(TerritoryPaint.borderDepth(big, 9, 9, 4 * 9 + 4)).toBe(0)
			T.expect(TerritoryPaint.borderDepth(big, 9, 9, 2 * 9 + 4)).toBe(0)
			T.expect(TerritoryPaint.borderDepth(big, 9, 9, 1 * 9 + 4)).toBe(2) -- край карты рядом
		end
	)
end)
