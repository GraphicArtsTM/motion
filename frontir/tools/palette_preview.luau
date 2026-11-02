--!strict
--[[
	Превью палитры: docs/palette.png — 32 цвета палитры с именами и hex, ниже 24 цвета держав
	с тёмным оттенком границы. Запуск из frontir/:  lune run tools/palette_preview

	В PNG пишется текстовый блок Frontir-Palette со всеми hex — тест Palette.spec проверяет по нему,
	что картинка соответствует текущему коду (поменял цвета — перезапусти инструмент).
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local NationColors = require("../src/shared/NationColors")
local Palette = require("../src/shared/Palette")

type Rgb = Palette.Rgb

-- Пиксельный шрифт 5×7: только то, что нужно для подписей (заглавные латинские буквы, цифры, '#').
local GLYPHS: { [string]: { string } } = {
	A = { ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
	B = { "####.", "#...#", "#...#", "####.", "#...#", "#...#", "####." },
	C = { ".###.", "#...#", "#....", "#....", "#....", "#...#", ".###." },
	D = { "####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####." },
	E = { "#####", "#....", "#....", "####.", "#....", "#....", "#####" },
	F = { "#####", "#....", "#....", "####.", "#....", "#....", "#...." },
	G = { ".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####" },
	H = { "#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
	I = { ".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###." },
	J = { "..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.." },
	K = { "#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#" },
	L = { "#....", "#....", "#....", "#....", "#....", "#....", "#####" },
	M = { "#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#" },
	N = { "#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#" },
	O = { ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###." },
	P = { "####.", "#...#", "#...#", "####.", "#....", "#....", "#...." },
	Q = { ".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#" },
	R = { "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#" },
	S = { ".####", "#....", "#....", ".###.", "....#", "....#", "####." },
	T = { "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.." },
	U = { "#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###." },
	V = { "#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.." },
	W = { "#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#." },
	X = { "#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#" },
	Y = { "#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.." },
	Z = { "#####", "....#", "...#.", "..#..", ".#...", "#....", "#####" },
	["0"] = { ".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###." },
	["1"] = { "..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###." },
	["2"] = { ".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####" },
	["3"] = { "#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###." },
	["4"] = { "...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#." },
	["5"] = { "#####", "#....", "####.", "....#", "....#", "#...#", ".###." },
	["6"] = { "..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###." },
	["7"] = { "#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..." },
	["8"] = { ".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###." },
	["9"] = { ".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.." },
	["#"] = { ".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#." },
	[" "] = { ".....", ".....", ".....", ".....", ".....", ".....", "....." },
}

local SCALE = 2
local GLYPH_W = (5 + 1) * SCALE
local GLYPH_H = 7 * SCALE

local CELL_W, SWATCH_H = 128, 40
local CELL_H = SWATCH_H + 2 * GLYPH_H + 16
local COLS = 8
local NATION_W, NATION_COLS = 84, 12
local NATION_H = 30 + 12 + GLYPH_H + 10
local MARGIN = 16

local width = MARGIN * 2 + math.max(CELL_W * COLS, NATION_W * NATION_COLS)
local paletteRows = math.ceil(#Palette.Swatches / COLS)
local nationRows = math.ceil(NationColors.Count / NATION_COLS)
local height = MARGIN + GLYPH_H + 10 + paletteRows * CELL_H + 12 + GLYPH_H + 10 + nationRows * NATION_H + MARGIN

local pixels = buffer.create(width * height * 3)

local function rect(x: number, y: number, w: number, h: number, c: Rgb)
	for yy = math.max(0, y), math.min(height, y + h) - 1 do
		for xx = math.max(0, x), math.min(width, x + w) - 1 do
			local o = (yy * width + xx) * 3
			buffer.writeu8(pixels, o, c.r)
			buffer.writeu8(pixels, o + 1, c.g)
			buffer.writeu8(pixels, o + 2, c.b)
		end
	end
end

local function text(x: number, y: number, s: string, c: Rgb)
	local upper = string.upper(s)
	for i = 1, #upper do
		local glyph = GLYPHS[string.sub(upper, i, i)] or GLYPHS[" "]
		for row = 1, 7 do
			for col = 1, 5 do
				if string.sub(glyph[row], col, col) == "#" then
					rect(x + (i - 1) * GLYPH_W + (col - 1) * SCALE, y + (row - 1) * SCALE, SCALE, SCALE, c)
				end
			end
		end
	end
end

-- Светлая или тёмная подпись поверх цвета — что читается лучше.
local function contrast(c: Rgb): Rgb
	local luma = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	return if luma > 140 then Palette.rgb("Ink") else Palette.rgb("White")
end

rect(0, 0, width, height, Palette.rgb("Ink"))
local y = MARGIN
text(MARGIN, y, "PALETTE 32", Palette.rgb("Gold"))
y += GLYPH_H + 10
for i, swatch in Palette.Swatches do
	local col = (i - 1) % COLS
	local row = (i - 1) // COLS
	local x0 = MARGIN + col * CELL_W
	local y0 = y + row * CELL_H
	local c = Palette.rgb(swatch.name)
	rect(x0 - 1, y0 - 1, CELL_W - 6, SWATCH_H + 2, Palette.rgb("Steel")) -- рамка: Ink на фоне Ink иначе не видно
	rect(x0, y0, CELL_W - 8, SWATCH_H, c)
	text(x0, y0 + SWATCH_H + 4, swatch.name, Palette.rgb("White"))
	text(x0, y0 + SWATCH_H + 6 + GLYPH_H, "#" .. swatch.hex, Palette.rgb("Mist"))
end
y += paletteRows * CELL_H + 12
text(MARGIN, y, "NATIONS 24  COLOR AND BORDER", Palette.rgb("Gold"))
y += GLYPH_H + 10
for i = 1, NationColors.Count do
	local col = (i - 1) % NATION_COLS
	local row = (i - 1) // NATION_COLS
	local x0 = MARGIN + col * NATION_W
	local y0 = y + row * NATION_H
	local c = NationColors.Colors[i]
	rect(x0, y0, NATION_W - 6, 30, c)
	rect(x0, y0 + 30, NATION_W - 6, 12, NationColors.Borders[i])
	text(x0 + 4, y0 + 8, tostring(i), contrast(c))
	text(x0, y0 + 44, NationColors.Hex[i], Palette.rgb("Mist"))
end

-- PNG: сигнатура, IHDR, tEXt, IDAT (zlib), IEND.
local crcTable: { number } = table.create(256, 0)
for n = 0, 255 do
	local c = n
	for _ = 1, 8 do
		if bit32.band(c, 1) == 1 then
			c = bit32.bxor(0xEDB88320, bit32.rshift(c, 1))
		else
			c = bit32.rshift(c, 1)
		end
	end
	crcTable[n + 1] = c
end

local function crc32(s: string): number
	local c = 0xFFFFFFFF
	for i = 1, #s do
		c = bit32.bxor(crcTable[bit32.band(bit32.bxor(c, string.byte(s, i)), 0xFF) + 1], bit32.rshift(c, 8))
	end
	return bit32.bxor(c, 0xFFFFFFFF)
end

local function u32be(n: number): string
	return string.char(
		bit32.band(bit32.rshift(n, 24), 0xFF),
		bit32.band(bit32.rshift(n, 16), 0xFF),
		bit32.band(bit32.rshift(n, 8), 0xFF),
		bit32.band(n, 0xFF)
	)
end

local function chunk(kind: string, data: string): string
	return u32be(#data) .. kind .. data .. u32be(crc32(kind .. data))
end

local rows: { string } = table.create(height)
for yy = 0, height - 1 do
	rows[yy + 1] = "\0" .. buffer.readstring(pixels, yy * width * 3, width * 3)
end
local raw = table.concat(rows)

local hexes: { string } = {}
for _, swatch in Palette.Swatches do
	table.insert(hexes, swatch.hex)
end
local stamp = table.concat(hexes, ",") .. "|" .. table.concat(NationColors.Hex, ",")

local png = "\137PNG\r\n\26\n"
	.. chunk("IHDR", u32be(width) .. u32be(height) .. string.char(8, 2, 0, 0, 0))
	.. chunk("tEXt", "Frontir-Palette\0" .. stamp)
	.. chunk("IDAT", serde.compress("zlib", raw))
	.. chunk("IEND", "")

fs.writeFile("docs/palette.png", png)
print(string.format("docs/palette.png: %d×%d, %d байт", width, height, #png))
