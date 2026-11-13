--!strict
--[[
	Карточки ударов (§15ш Ш8) — гладкие картинки геймдизайнера, не пиксель-арт: PNG из assets/cards/*.png
	(3:2) → W×H, у каждой своя палитра до MaxColors цветов (median cut) → src/shared/CardData.luau
	(палитра hex + индексы base64; рисует игра через EditableImage — загрузка в Roblox не нужна).
	Исключение из «только палитра docs/palette.md» — решение геймдизайнера (GDD §15ш Ш8).
	Запуск из frontir/:  lune run tools/card_pack [превью=build/cards_pack.png]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Base64 = require("../src/shared/Base64")
local Png = require("./lib/Png")

local W, H, MAX_COLORS = 144, 96, 128
local PREVIEW = process.args[1] or "build/cards_pack.png"

type Px = { number } -- r, g, b

local function downscale(img: Png.Image): { Px }
	local out: { Px } = table.create(W * H)
	local bx, by = img.width / W, img.height / H
	for ty = 0, H - 1 do
		for tx = 0, W - 1 do
			local x0, x1 = math.floor(tx * bx), math.max(math.floor(tx * bx), math.floor((tx + 1) * bx) - 1)
			local y0, y1 = math.floor(ty * by), math.max(math.floor(ty * by), math.floor((ty + 1) * by) - 1)
			local r, g, b, n = 0, 0, 0, 0
			for y = y0, y1 do
				for x = x0, x1 do
					local o = (y * img.width + x) * 4
					r += buffer.readu8(img.rgba, o)
					g += buffer.readu8(img.rgba, o + 1)
					b += buffer.readu8(img.rgba, o + 2)
					n += 1
				end
			end
			out[ty * W + tx + 1] = { math.round(r / n), math.round(g / n), math.round(b / n) }
		end
	end
	return out
end

-- Median cut: делим коробку с самым широким разбросом канала пополам по медиане, пока цветов меньше MAX_COLORS.
local function medianCut(pixels: { Px }): { Px }
	local boxes: { { Px } } = { table.clone(pixels) }
	while #boxes < MAX_COLORS do
		local bestBox, bestCh, bestRange = 0, 1, -1
		for k, box in boxes do
			if #box > 1 then
				for ch = 1, 3 do
					local lo, hi = 255, 0
					for _, p in box do
						lo, hi = math.min(lo, p[ch]), math.max(hi, p[ch])
					end
					if hi - lo > bestRange then
						bestBox, bestCh, bestRange = k, ch, hi - lo
					end
				end
			end
		end
		if bestBox == 0 or bestRange <= 0 then
			break
		end
		local box = boxes[bestBox]
		table.sort(box, function(a: Px, b: Px): boolean
			return a[bestCh] < b[bestCh]
		end)
		local half = #box // 2
		local left, right = table.move(box, 1, half, 1, {}), table.move(box, half + 1, #box, 1, {})
		boxes[bestBox] = left
		table.insert(boxes, right)
	end
	local palette: { Px } = {}
	for _, box in boxes do
		local r, g, b = 0, 0, 0
		for _, p in box do
			r += p[1]
			g += p[2]
			b += p[3]
		end
		table.insert(palette, { math.round(r / #box), math.round(g / #box), math.round(b / #box) })
	end
	return palette
end

local function nearest(palette: { Px }, p: Px): number
	local best, bestD = 1, math.huge
	for k, c in palette do
		local dr, dg, db = p[1] - c[1], p[2] - c[2], p[3] - c[3]
		local d = 2 * dr * dr + 4 * dg * dg + 3 * db * db
		if d < bestD then
			best, bestD = k, d
		end
	end
	return best
end

local files = fs.readDir("assets/cards")
table.sort(files)
type Packed = { name: string, palette: { Px }, indices: buffer }
local packed: { Packed } = {}
for _, file in files do
	local name = string.match(file, "^(.+)%.png$")
	if name ~= nil then
		local pixels = downscale(Png.decode(fs.readFile("assets/cards/" .. file)))
		local palette = medianCut(pixels)
		local indices = buffer.create(W * H)
		for i, p in pixels do
			buffer.writeu8(indices, i - 1, nearest(palette, p) - 1)
		end
		table.insert(packed, { name = name, palette = palette, indices = indices })
		print(name, #palette)
	end
end

local lines: { string } = {
	"--!strict",
	"--[[",
	"\tCardData — карточки ударов (§15ш Ш8). Сделано tools/card_pack из assets/cards — руками не править.",
	"\tpalette — цвета подряд по 6 hex-знаков; data — base64 индексов (байт на пиксель, строки сверху вниз).",
	"]]",
	"",
	"local CardData = {}",
	"",
	string.format("CardData.W = %d", W),
	string.format("CardData.H = %d", H),
	"",
	"-- stylua: ignore",
	"CardData.Cards = table.freeze({",
}
for _, c in packed do
	local hex: { string } = {}
	for _, p in c.palette do
		table.insert(hex, string.format("%02x%02x%02x", p[1], p[2], p[3]))
	end
	table.insert(lines, string.format("\t%s = table.freeze({", c.name))
	table.insert(lines, string.format('\t\tpalette = "%s",', table.concat(hex)))
	table.insert(lines, string.format('\t\tdata = "%s",', Base64.encode(c.indices)))
	table.insert(lines, "\t}),")
end
table.insert(lines, "})")
table.insert(lines, "")
table.insert(lines, "return table.freeze(CardData)")
table.insert(lines, "")
fs.writeFile("src/shared/CardData.luau", table.concat(lines, "\n"))

-- Превью: карточки ×2, по две в ряд.
local cols, scale, pad = 2, 2, 8
local cw, ch = W * scale + pad, H * scale + pad
local rowsN = math.ceil(#packed / cols)
local PW, PH = cols * cw + pad, rowsN * ch + pad
local pix = buffer.create(PW * PH * 3)
for n, c in packed do
	local ox, oy = pad + ((n - 1) % cols) * cw, pad + ((n - 1) // cols) * ch
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local p = c.palette[buffer.readu8(c.indices, y * W + x) + 1]
			for sy = 0, scale - 1 do
				for sx = 0, scale - 1 do
					local i = ((oy + y * scale + sy) * PW + ox + x * scale + sx) * 3
					buffer.writeu8(pix, i, p[1])
					buffer.writeu8(pix, i + 1, p[2])
					buffer.writeu8(pix, i + 2, p[3])
				end
			end
		end
	end
end
fs.writeFile(PREVIEW, Png.encodeRgb(PW, PH, pix))
print(
	string.format("карточек %d, %d×%d → src/shared/CardData.luau, превью %s", #packed, W, H, PREVIEW)
)
