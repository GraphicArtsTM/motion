--!strict
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local NationColors = require("../src/shared/NationColors")
local Palette = require("../src/shared/Palette")
local Rng = require("../src/shared/Rng")

type Rgb = Palette.Rgb

-- sRGB → CIE Lab (D65), для проверки различимости цветов.
local function lab(c: Rgb): (number, number, number)
	local function lin(v: number): number
		v /= 255
		return if v <= 0.04045 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
	end
	local r, g, b = lin(c.r), lin(c.g), lin(c.b)
	local x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	local y = 0.2126 * r + 0.7152 * g + 0.0722 * b
	local z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	local function f(t: number): number
		return if t > 0.008856 then t ^ (1 / 3) else 7.787 * t + 16 / 116
	end
	local fx, fy, fz = f(x), f(y), f(z)
	return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)
end

local function deltaE(a: Rgb, b: Rgb): number
	local l1, a1, b1 = lab(a)
	local l2, a2, b2 = lab(b)
	return math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end

-- Проверяет главное правило: K ближайших по старту держав — другого цвета.
local function checkNearestDistinct(starts: { NationColors.StartPoint }, colors: { number }, k: number)
	for i = 1, #starts do
		local order: { number } = {}
		for j = 1, #starts do
			if j ~= i then
				table.insert(order, j)
			end
		end
		table.sort(order, function(a: number, b: number): boolean
			local da = (starts[i].x - starts[a].x) ^ 2 + (starts[i].y - starts[a].y) ^ 2
			local db = (starts[i].x - starts[b].x) ^ 2 + (starts[i].y - starts[b].y) ^ 2
			if da ~= db then
				return da < db
			end
			return a < b
		end)
		for r = 1, math.min(k, #order) do
			if colors[order[r]] == colors[i] then
				error(
					string.format(
						"держава %d и её %d-й сосед %d одного цвета %d",
						i,
						r,
						order[r],
						colors[i]
					)
				)
			end
		end
	end
end

local function randomStarts(seed: number, n: number, w: number, h: number): { NationColors.StartPoint }
	local rng = Rng.new(seed)
	local out: { NationColors.StartPoint } = {}
	for _ = 1, n do
		table.insert(out, { x = Rng.range(rng, 0, w - 1), y = Rng.range(rng, 0, h - 1) })
	end
	return out
end

T.describe("NationColors: набор", function()
	T.it("24 цвета, не из палитры и все разные", function()
		T.expect(NationColors.Count).toBe(24)
		local paletteHex: { [string]: boolean } = {}
		for _, s in Palette.Swatches do
			paletteHex[s.hex] = true
		end
		local seen: { [string]: boolean } = {}
		for _, hex in NationColors.Hex do
			T.expect(paletteHex[hex]).toBe(nil)
			T.expect(seen[hex]).toBe(nil)
			seen[hex] = true
		end
	end)

	T.it("любые два цвета хорошо различимы (ΔE76 ≥ 25)", function()
		for i = 1, NationColors.Count do
			for j = i + 1, NationColors.Count do
				local d = deltaE(NationColors.Colors[i], NationColors.Colors[j])
				if d < 25 then
					error(
						string.format(
							"цвета %s и %s слишком похожи: ΔE %.1f",
							NationColors.Hex[i],
							NationColors.Hex[j],
							d
						)
					)
				end
			end
		end
	end)

	T.it("граница — цвет × BorderShade", function()
		local k = Config.Nations.BorderShade
		T.expect(k).toBeNear(0.55)
		for i, c in NationColors.Colors do
			local b = NationColors.Borders[i]
			T.expect(b.r).toBe(math.floor(c.r * k))
			T.expect(b.g).toBe(math.floor(c.g * k))
			T.expect(b.b).toBe(math.floor(c.b * k))
		end
	end)
end)

T.describe("NationColors.assign", function()
	T.it("до 24 держав — все цвета разные", function()
		for seed = 1, 20 do
			local colors = NationColors.assign(randomStarts(seed, 24, 512, 320))
			local seen: { [number]: boolean } = {}
			for _, c in colors do
				T.expect(seen[c]).toBe(nil)
				seen[c] = true
			end
		end
	end)

	T.it(
		"60 держав, случайные расстановки: ближайшие соседи никогда не совпадают",
		function()
			for seed = 1, 60 do
				local starts = randomStarts(seed * 7919, 60, 1024, 512)
				checkNearestDistinct(starts, NationColors.assign(starts), Config.Nations.DistinctNearest)
			end
		end
	)

	T.it("60 держав кучками и сеткой (худшие случаи)", function()
		-- Кучки: 6 тесных групп по 10 держав.
		local rng = Rng.new(5)
		local clusters: { NationColors.StartPoint } = {}
		for g = 0, 5 do
			for _ = 1, 10 do
				table.insert(clusters, { x = g * 150 + Rng.range(rng, 0, 12), y = 200 + Rng.range(rng, 0, 12) })
			end
		end
		checkNearestDistinct(clusters, NationColors.assign(clusters), Config.Nations.DistinctNearest)
		-- Ровная сетка 10×6: много одинаковых расстояний.
		local grid: { NationColors.StartPoint } = {}
		for y = 0, 5 do
			for x = 0, 9 do
				table.insert(grid, { x = x * 40, y = y * 40 })
			end
		end
		checkNearestDistinct(grid, NationColors.assign(grid), Config.Nations.DistinctNearest)
	end)

	T.it(
		"повторы цветов разнесены: одинаковые цвета дальше, чем ближайшие соседи",
		function()
			local starts = randomStarts(77, 60, 1024, 512)
			local colors = NationColors.assign(starts)
			local sameMin, anyMin = math.huge, math.huge
			for i = 1, 60 do
				for j = i + 1, 60 do
					local d = math.sqrt((starts[i].x - starts[j].x) ^ 2 + (starts[i].y - starts[j].y) ^ 2)
					anyMin = math.min(anyMin, d)
					if colors[i] == colors[j] then
						sameMin = math.min(sameMin, d)
					end
				end
			end
			T.expect(sameMin > anyMin * 3).toBe(true)
		end
	)

	T.it("детерминированность и крайние случаи", function()
		local starts = randomStarts(3, 40, 512, 320)
		T.expect(NationColors.assign(starts)).toEqual(NationColors.assign(starts))
		T.expect(#NationColors.assign({})).toBe(0)
		T.expect(NationColors.assign({ { x = 1, y = 1 } })[1]).toBe(1)
	end)
end)
