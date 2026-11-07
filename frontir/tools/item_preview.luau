--!strict
--[[
	Превью картинок предметов (§15л ч.9): все картинки ItemArt сеткой, ×3 без сглаживания, с подписями-ключами.
	Запуск из frontir/:  lune run tools/item_preview docs/previews/ui-items.png
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Palette = require("../src/shared/Palette")
local ItemArt = require("../src/shared/ItemArt")
local Png = require("./lib/Png")

local S, GAP, COLS = 3, 6, 8
local cw, ch = ItemArt.W * S, ItemArt.H * S
local Config = require("../src/shared/Config")
local keys = table.clone(ItemArt.Keys)
for _, kind in Config.Buildable do
	table.insert(keys, "building." .. kind)
end
for i = 1, 4 do
	table.insert(keys, "nation." .. (i * 5))
end
local rows = math.ceil(#keys / COLS)
local W, H = COLS * (cw + GAP) + GAP, rows * (ch + GAP) + GAP
local out = buffer.create(W * H * 3)
local bg = Palette.rgb("Ink")
for i = 0, W * H - 1 do
	buffer.writeu8(out, i * 3, bg.r)
	buffer.writeu8(out, i * 3 + 1, bg.g)
	buffer.writeu8(out, i * 3 + 2, bg.b)
end
for k, key in keys do
	local px = ItemArt.paint(key)
	local ox = GAP + ((k - 1) % COLS) * (cw + GAP)
	local oy = GAP + ((k - 1) // COLS) * (ch + GAP)
	for y = 0, ch - 1 do
		for x = 0, cw - 1 do
			local si = ((y // S) * ItemArt.W + x // S) * 4
			local di = ((oy + y) * W + ox + x) * 3
			buffer.writeu8(out, di, buffer.readu8(px, si))
			buffer.writeu8(out, di + 1, buffer.readu8(px, si + 1))
			buffer.writeu8(out, di + 2, buffer.readu8(px, si + 2))
		end
	end
end
local file = process.args[1] or "build/ui-items.png"
fs.writeFile(file, Png.encodeRgb(W, H, out))
print(string.format("→ %s (%d×%d, картинок %d)", file, W, H, #keys))
