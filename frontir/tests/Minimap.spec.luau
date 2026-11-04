--!strict
local T = require("./lib/TestKit")
local MinimapPaint = require("../src/shared/MinimapPaint")

-- Карта 4×2: местность — серый номер клетки, владельцы: клетка 1 у державы 7, клетка 6 у державы 9 (без цвета).
local function sample(): (buffer, buffer)
	local terrain = buffer.create(8 * 4)
	local owners = buffer.create(8 * 2)
	for i = 0, 7 do
		buffer.writeu8(terrain, i * 4, i * 10)
		buffer.writeu8(terrain, i * 4 + 1, i * 10)
		buffer.writeu8(terrain, i * 4 + 2, i * 10)
		buffer.writeu8(terrain, i * 4 + 3, 255)
	end
	buffer.writeu16(owners, 1 * 2, 7)
	buffer.writeu16(owners, 6 * 2, 9)
	return terrain, owners
end

local function colorOf(owner: number): (number?, number?, number?)
	if owner == 7 then
		return 200, 50, 25
	end
	return nil, nil, nil
end

local function pixel(out: buffer, w: number, x: number, y: number): { number }
	local o = (y * w + x) * 4
	return { buffer.readu8(out, o), buffer.readu8(out, o + 1), buffer.readu8(out, o + 2), buffer.readu8(out, o + 3) }
end

T.describe("Мини-карта", function()
	T.it("размер вписан в квадрат с пропорциями карты", function()
		local w, h = MinimapPaint.size(1000, 500, 200)
		T.expect(w).toBe(200)
		T.expect(h).toBe(100)
		w, h = MinimapPaint.size(300, 900, 200)
		T.expect(w).toBe(67)
		T.expect(h).toBe(200)
		w, h = MinimapPaint.size(4000, 1, 200)
		T.expect(h).toBe(1)
	end)

	T.it(
		"в размер карты: территории цветом державы, остальное — местность, без цвета — местность",
		function()
			local terrain, owners = sample()
			local out = MinimapPaint.paint(terrain, owners, 4, 2, 4, 2, colorOf)
			T.expect(pixel(out, 4, 0, 0)).toEqual({ 0, 0, 0, 255 })
			T.expect(pixel(out, 4, 1, 0)).toEqual({ 200, 50, 25, 255 })
			T.expect(pixel(out, 4, 2, 1)).toEqual({ 60, 60, 60, 255 })
			T.expect(pixel(out, 4, 3, 1)).toEqual({ 70, 70, 70, 255 })
		end
	)

	T.it(
		"уменьшение вдвое берёт клетки по сетке, без выхода за край",
		function()
			local terrain, owners = sample()
			local out = MinimapPaint.paint(terrain, owners, 4, 2, 2, 1, colorOf)
			T.expect(buffer.len(out)).toBe(2 * 1 * 4)
			-- Пиксель (0,0) — клетка (1,1) = 5, пиксель (1,0) — клетка (3,1) = 7.
			T.expect(pixel(out, 2, 0, 0)).toEqual({ 50, 50, 50, 255 })
			T.expect(pixel(out, 2, 1, 0)).toEqual({ 70, 70, 70, 255 })
			-- Увеличение тоже не выходит за край.
			local big = MinimapPaint.paint(terrain, owners, 4, 2, 9, 5, colorOf)
			T.expect(buffer.len(big)).toBe(9 * 5 * 4)
			T.expect(pixel(big, 9, 8, 4)).toEqual({ 70, 70, 70, 255 })
		end
	)
end)
