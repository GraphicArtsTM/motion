--!strict
--[[
	Превью погонов «Пути командира» (§15щ Щ2): 11 ступеней ×8 на фоне панели — из Shared.Ranks (как в игре).
	Запуск из frontir/:  lune run tools/epaulette_preview [файл=docs/previews/epaulettes.png]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Palette = require("../src/shared/Palette")
local Png = require("./lib/Png")
local Ranks = require("../src/shared/Ranks")

local OUT = process.args[1] or "docs/previews/epaulettes.png"
local SCALE, PAD = 8, 12
local cell = Ranks.IconSize * SCALE
local W, H = Ranks.Count * (cell + PAD) + PAD, cell + 2 * PAD
local pix = buffer.create(W * H * 3)
local bg = Palette.rgb("Night")
for i = 0, W * H - 1 do
	buffer.writeu8(pix, i * 3, bg.r)
	buffer.writeu8(pix, i * 3 + 1, bg.g)
	buffer.writeu8(pix, i * 3 + 2, bg.b)
end
for rank = 1, Ranks.Count do
	local ox = PAD + (rank - 1) * (cell + PAD)
	for _, part in Ranks.icon(rank) do
		local c = Palette.rgb(part.color)
		for y = part.y * SCALE, (part.y + part.h) * SCALE - 1 do
			for x = part.x * SCALE, (part.x + part.w) * SCALE - 1 do
				local i = ((PAD + y) * W + ox + x) * 3
				buffer.writeu8(pix, i, c.r)
				buffer.writeu8(pix, i + 1, c.g)
				buffer.writeu8(pix, i + 2, c.b)
			end
		end
	end
end
fs.writeFile(OUT, Png.encodeRgb(W, H, pix))
print("погоны → " .. OUT)
