--!strict
--[[
	Превью пиксельного вида интерфейса (§15л ч.4): lune run tools/ui_preview docs/previews/ui-pixel.png
	Рисует окно и кнопки по тем же правилам, что и игра (src/shared/PixelSkin): обычное, наведение, нажатие;
	текст — пиксельный шрифт tools/lib/PixelFont (в игре — шрифт интерфейса Roblox).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Palette = require("../src/shared/Palette")
local PixelSkin = require("../src/shared/PixelSkin")
local PixelFont = require("./lib/PixelFont")
local Png = require("./lib/Png")

local out = process.args[1] or "build/ui-pixel.png"
local W, H = 760, 440
local px = buffer.create(W * H * 3)

local function fill(x: number, y: number, w: number, h: number, color: string)
	local c = Palette.rgb(color)
	for yy = math.max(0, y), math.min(H - 1, y + h - 1) do
		for xx = math.max(0, x), math.min(W - 1, x + w - 1) do
			local i = (yy * W + xx) * 3
			buffer.writeu8(px, i, c.r)
			buffer.writeu8(px, i + 1, c.g)
			buffer.writeu8(px, i + 2, c.b)
		end
	end
end

local function draw(rects: { PixelSkin.Rect }, ox: number, oy: number)
	for _, r in rects do
		fill(ox + r.x, oy + r.y, r.w, r.h, r.color)
	end
end

local SCALE = 2
local function textWidth(text: string, scale: number): number
	return (utf8.len(text) or 0) * (PixelFont.W + 1) * scale
end
local function text(s: string, x: number, y: number, color: string, scale: number)
	local k = 0
	for _, code in utf8.codes(s) do
		local g = PixelFont.glyph(utf8.char(code))
		for gy = 1, PixelFont.H do
			for gx = 1, PixelFont.W do
				if string.sub(g[gy], gx, gx) == "#" then
					fill(x + (k * (PixelFont.W + 1) + gx - 1) * scale, y + (gy - 1) * scale, scale, scale, color)
				end
			end
		end
		k += 1
	end
end
local function button(label: string, x: number, y: number, w: number, h: number, face: string, state: any, ink: string)
	draw(PixelSkin.button(w, h, face, state), x, y)
	local dy = if state == "pressed" then 1 else 0
	text(
		label,
		x + math.floor((w - textWidth(label, SCALE)) / 2),
		y + math.floor((h - PixelFont.H * SCALE) / 2) + dy,
		ink,
		SCALE
	)
end

-- Фон — «карта» за затемнением.
fill(0, 0, W, H, "Abyss")
for k = 0, 9 do
	fill(40 + k * 70, 30 + (k % 3) * 120, 60, 90, if k % 2 == 0 then "Forest" else "Pine")
end

-- Окно.
draw(PixelSkin.panel(700, 380, "Night"), 30, 30)
text("ФРОНТИР", 50, 48, "Gold", 4)
text("ПИКСЕЛЬНЫЕ КНОПКИ: ОБЫЧНАЯ / НАВЕДЕНИЕ / НАЖАТИЕ", 50, 92, "Mist", 1)

local rows: { { label: string, face: string, ink: string } } = {
	{ label = "В БОЙ", face = "Gold", ink = "Ink" },
	{ label = "Магазин", face = "Slate", ink = "White" },
	{ label = "Войти", face = "Forest", ink = "White" },
	{ label = "Главное меню", face = "Plum", ink = "White" },
}
for r, row in rows do
	for s, state in { "normal", "hover", "pressed" } do
		button(row.label, 54 + (s - 1) * 225, 116 + (r - 1) * 62, 200, 44, row.face, state, row.ink)
	end
end
-- Карточка внутри окна.
draw(PixelSkin.panel(650, 30, "Slate"), 54, 368)
text("Код матча: K7Q2MD", 66, 376, "Gold", SCALE)

fs.writeFile(out, Png.encodeRgb(W, H, px))
print(string.format("→ %s (%d×%d)", out, W, H))
