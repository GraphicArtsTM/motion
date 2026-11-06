--!strict
--[[
	Превью пиксельного шрифта (сводная правка, часть 3): lune run tools/font_preview docs/previews/font-pixel.png
	Вариант Б — свой bitmap-шрифт 5×7 (tools/lib/PixelFont): алфавиты, цифры и строки интерфейса игры в масштабе ×3
	на панели в цветах палитры. Вариант А (Roblox Enum.Font.Arcade) смотрится в Studio: Config.Render.UiFont = "Arcade".
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Palette = require("../src/shared/Palette")
local PixelFont = require("./lib/PixelFont")
local Png = require("./lib/Png")

local out = process.args[1] or "build/font.png"
local SCALE = 3
local lines: { { text: string, color: string } } = {
	{ text = "ФРОНТИР — FRONTIER", color = "Gold" },
	{ text = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ", color = "White" },
	{ text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789", color = "White" },
	{ text = ".,:!?-+%$()/«»×★", color = "Mist" },
	{ text = "", color = "White" },
	{ text = "Дипломатия (T)   Технологии (Y)", color = "White" },
	{ text = "Деньги: $12 500   Нефть: 340", color = "Gold" },
	{ text = "Война объявлена: Северная держава!", color = "Red" },
	{ text = "Пехота ★★  Танки ★  Сила 2 400", color = "Sky" },
	{ text = "Diplomacy (T)  Money: $12 500", color = "White" },
}
local GAP = 1 -- пиксель между буквами (в масштабе шрифта)
local function width(text: string): number
	local n = utf8.len(text) or 0
	return n * (PixelFont.W + GAP)
end
local maxW = 0
for _, l in lines do
	maxW = math.max(maxW, width(l.text))
end
local PAD = 6
local W = (maxW + PAD * 2) * SCALE
local LINE = PixelFont.H + 4
local H = (#lines * LINE + PAD * 2) * SCALE
local px = buffer.create(W * H * 3)
local bg = Palette.rgb("Night")
local border = Palette.rgb("Steel")
for y = 0, H - 1 do
	for x = 0, W - 1 do
		local c = if x < SCALE or y < SCALE or x >= W - SCALE or y >= H - SCALE then border else bg
		local i = (y * W + x) * 3
		buffer.writeu8(px, i, c.r)
		buffer.writeu8(px, i + 1, c.g)
		buffer.writeu8(px, i + 2, c.b)
	end
end
for row, l in lines do
	local c = Palette.rgb(l.color)
	local x0 = PAD
	local y0 = PAD + (row - 1) * LINE
	local k = 0
	for _, code in utf8.codes(l.text) do
		local g = PixelFont.glyph(utf8.char(code))
		for gy = 1, PixelFont.H do
			local rowBits = g[gy]
			for gx = 1, PixelFont.W do
				if string.sub(rowBits, gx, gx) == "#" then
					for sy = 0, SCALE - 1 do
						for sx = 0, SCALE - 1 do
							local x = (x0 + k * (PixelFont.W + GAP) + gx - 1) * SCALE + sx
							local y = (y0 + gy - 1) * SCALE + sy
							local i = (y * W + x) * 3
							buffer.writeu8(px, i, c.r)
							buffer.writeu8(px, i + 1, c.g)
							buffer.writeu8(px, i + 2, c.b)
						end
					end
				end
			end
		end
		k += 1
	end
end
fs.writeFile(out, Png.encodeRgb(W, H, px))
print(string.format("→ %s (%d×%d)", out, W, H))
