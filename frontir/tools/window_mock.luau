--!strict
--[[
	Макет окна-витрины (§15л ч.9): «Магазин» на вкладке «Бусты» — шапка-сцена, заголовок, плашки, вкладки, сетка
	карточек (картинка ItemArt, название, цена, кнопки) по размерам UI/CardKit. Текст — пиксельным шрифтом превью
	(в игре — шрифт интерфейса Roblox). Запуск: lune run tools/window_mock docs/previews/ui-shop.png
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local ItemArt = require("../src/shared/ItemArt")
local Palette = require("../src/shared/Palette")
local PixelSkin = require("../src/shared/PixelSkin")
local SceneArt = require("../src/shared/SceneArt")
local Shop = require("../src/shared/Shop")
local Strings = require("../src/shared/Strings")
local PixelFont = require("./lib/PixelFont")
local Png = require("./lib/Png")

local WIN_W, WIN_H = 860, 720
local BANNER_H = 110
local W, H = WIN_W + 40, WIN_H + BANNER_H + 40
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
local function blit(src: buffer, sw: number, sh: number, x: number, y: number, w: number, h: number)
	for yy = 0, h - 1 do
		for xx = 0, w - 1 do
			local si = ((yy * sh // h) * sw + (xx * sw // w)) * 4
			local di = ((y + yy) * W + x + xx) * 3
			buffer.writeu8(px, di, buffer.readu8(src, si))
			buffer.writeu8(px, di + 1, buffer.readu8(src, si + 1))
			buffer.writeu8(px, di + 2, buffer.readu8(src, si + 2))
		end
	end
end
local function text(s: string, x: number, y: number, color: string, scale: number, maxW: number?)
	local k = 0
	for _, code in utf8.codes(s) do
		local cx = x + k * (PixelFont.W + 1) * scale
		if maxW ~= nil and cx + PixelFont.W * scale > x + maxW then
			break
		end
		local g = PixelFont.glyph(utf8.char(code))
		for gy = 1, PixelFont.H do
			for gx = 1, PixelFont.W do
				if string.sub(g[gy], gx, gx) == "#" then
					fill(cx + (gx - 1) * scale, y + (gy - 1) * scale, scale, scale, color)
				end
			end
		end
		k += 1
	end
end
local function frame(x: number, y: number, w: number, h: number, face: string, edge: string)
	fill(x - 2, y - 2, w + 4, h + 4, edge)
	fill(x, y, w, h, face)
end
local function button(label: string, x: number, y: number, w: number, h: number, face: string, ink: string)
	for _, r in PixelSkin.button(w, h, face, "normal") do
		fill(x + r.x, y + r.y, r.w, r.h, r.color)
	end
	text(label, x + 6, y + (h - 14) // 2, ink, 2, w - 10)
end

fill(0, 0, W, H, "Abyss")
local wx, wy = 20, 20 + BANNER_H + 2
blit(SceneArt.paint("shop"), SceneArt.W, SceneArt.H, wx, 20, WIN_W, BANNER_H)
frame(wx, wy, WIN_W, WIN_H, "Night", "Steel")
local function t(key: string): string
	return Strings.get(key, "ru")
end
text(t("shop.title"), wx + 16, wy + 14, "Gold", 3)
text(
	"Бусты — по одному каждого за матч; цена и эффект видны до покупки",
	wx + 16,
	wy + 46,
	"Mist",
	1
)
frame(wx + WIN_W - 250, wy + 14, 90, 30, "Ink", "Gold")
text("12 400", wx + WIN_W - 238, wy + 22, "Gold", 2)
frame(wx + WIN_W - 150, wy + 14, 50, 30, "Ink", "Gold")
text("3", wx + WIN_W - 128, wy + 22, "Gold", 2)
button("x", wx + WIN_W - 60, wy + 12, 44, 44, "Slate", "White")
local tabs = { t("shop.boosts"), t("shop.tabSeason"), t("shop.passes"), t("shop.packs") }
local tx = wx + 16
for k, label in tabs do
	local tw = (utf8.len(label) or 0) * 12 + 32
	button(label, tx, wy + 72, tw, 40, if k == 1 then "Gold" else "Slate", if k == 1 then "Ink" else "White")
	tx += tw + 8
end
local CW, CH = 184, 280
for k, key in Shop.BoostKeys do
	local col, row = (k - 1) % 4, (k - 1) // 4
	local cx, cy = wx + 20 + col * (CW + 10), wy + 132 + row * (CH + 10)
	if cy + CH > wy + WIN_H then
		break
	end
	frame(cx, cy, CW, CH, "Ink", if k <= 2 then "Meadow" else "Steel")
	local artW = CW - 12
	local artH = artW * ItemArt.H // ItemArt.W
	blit(ItemArt.paint("shop." .. key), ItemArt.W, ItemArt.H, cx + 6, cy + 6, artW, artH)
	text(t("shop." .. key), cx + 8, cy + artH + 14, "White", 2, CW - 16)
	text("ОДИН РАЗ ЗА МАТЧ", cx + 8, cy + artH + 40, "Mist", 1, CW - 16)
	text("В ЗАПАСЕ 1, ЖЕТОНОВ 3", cx + 8, cy + artH + 88, "Meadow", 1, CW - 16)
	local bw = (CW - 16 - 12) // 3
	button("ЖЕТОН", cx + 8, cy + CH - 52, bw, 44, "Forest", "White")
	button("x1", cx + 8 + bw + 6, cy + CH - 52, bw, 44, "Slate", "White")
	button("R$45", cx + 8 + 2 * (bw + 6), cy + CH - 52, bw, 44, "Gold", "Ink")
end
local out = process.args[1] or "build/ui-shop.png"
fs.writeFile(out, Png.encodeRgb(W, H, px))
print("→ " .. out)
