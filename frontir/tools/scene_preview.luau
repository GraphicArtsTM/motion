--!strict
--[[
	Превью картинок-шапок окон (§15л ч.8): все сцены SceneArt столбиком, ×3 без сглаживания, с подписями-ключами.
	Запуск из frontir/:  lune run tools/scene_preview docs/previews/ui-scenes.png
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Palette = require("../src/shared/Palette")
local SceneArt = require("../src/shared/SceneArt")
local Png = require("./lib/Png")

local S, GAP, COLS = 3, 6, 2
local cw, ch = SceneArt.W * S, SceneArt.H * S
local rows = math.ceil(#SceneArt.Keys / COLS)
local W, H = COLS * (cw + GAP) + GAP, rows * (ch + GAP) + GAP
local out = buffer.create(W * H * 3)
local bg = Palette.rgb("Ink")
for i = 0, W * H - 1 do
	buffer.writeu8(out, i * 3, bg.r)
	buffer.writeu8(out, i * 3 + 1, bg.g)
	buffer.writeu8(out, i * 3 + 2, bg.b)
end
for k, key in SceneArt.Keys do
	local px = SceneArt.paint(key)
	local ox = GAP + ((k - 1) % COLS) * (cw + GAP)
	local oy = GAP + ((k - 1) // COLS) * (ch + GAP)
	for y = 0, ch - 1 do
		for x = 0, cw - 1 do
			local si = ((y // S) * SceneArt.W + x // S) * 4
			local di = ((oy + y) * W + ox + x) * 3
			buffer.writeu8(out, di, buffer.readu8(px, si))
			buffer.writeu8(out, di + 1, buffer.readu8(px, si + 1))
			buffer.writeu8(out, di + 2, buffer.readu8(px, si + 2))
		end
	end
end
local file = process.args[1] or "build/ui-scenes.png"
fs.writeFile(file, Png.encodeRgb(W, H, out))
print(string.format("→ %s (%d×%d, сцен %d)", file, W, H, #SceneArt.Keys))
