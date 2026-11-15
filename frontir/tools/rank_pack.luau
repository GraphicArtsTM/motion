--!strict
--[[
	Погоны званий (§15ю, картинки геймдизайнера) без загрузки в Roblox: assets/ranks/rank1…11.png (RGBA, прозрачный
	фон) → вписаны в W×H по центру → у каждого своя палитра (median cut, до MAX_COLORS цветов) и индекс 0 — прозрачно →
	src/shared/RankData.luau (base64). Рисует игра через EditableImage (UI/IconImage.rank), чистый модуль — RankArt.
	Запуск из frontir/:  lune run tools/rank_pack [превью=build/ranks_pack.png]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Base64 = require("../src/shared/Base64")
local Png = require("./lib/Png")

local W, H, MAX_COLORS = 60, 128, 127
local PREVIEW = process.args[1] or "build/ranks_pack.png"

type Px = { number } -- r, g, b

-- Вписать в W×H с сохранением пропорций; пиксель — среднее непрозрачных в квадрате, прозрачно, если их меньше
-- половины. Возвращает список пикселей (nil — прозрачно).
local function fit(img: Png.Image): { [number]: Px }
	local out: { [number]: Px } = {}
	local s = math.max(img.width / W, img.height / H)
	local dw, dh = img.width / s, img.height / s
	local ox, oy = (W - dw) / 2, (H - dh) / 2
	for ty = 0, H - 1 do
		for tx = 0, W - 1 do
			local sx0, sx1 = (tx - ox) * s, (tx + 1 - ox) * s
			local sy0, sy1 = (ty - oy) * s, (ty + 1 - oy) * s
			local x0, x1 = math.max(0, math.floor(sx0)), math.min(img.width - 1, math.ceil(sx1) - 1)
			local y0, y1 = math.max(0, math.floor(sy0)), math.min(img.height - 1, math.ceil(sy1) - 1)
			local r, g, b, n, all = 0, 0, 0, 0, 0
			for y = y0, y1 do
				for x = x0, x1 do
					local o = (y * img.width + x) * 4
					all += 1
					if buffer.readu8(img.rgba, o + 3) >= 128 then
						r += buffer.readu8(img.rgba, o)
						g += buffer.readu8(img.rgba, o + 1)
						b += buffer.readu8(img.rgba, o + 2)
						n += 1
					end
				end
			end
			if all > 0 and n * 2 >= all then
				out[ty * W + tx + 1] = { math.round(r / n), math.round(g / n), math.round(b / n) }
			end
		end
	end
	return out
end

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
		boxes[bestBox] = table.move(box, 1, half, 1, {})
		table.insert(boxes, table.move(box, half + 1, #box, 1, {}))
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

type Packed = { rank: number, palette: { Px }, indices: buffer }
local packed: { Packed } = {}
for rank = 1, 11 do
	local path = string.format("assets/ranks/rank%d.png", rank)
	if fs.isFile(path) then
		local px = fit(Png.decode(fs.readFile(path)))
		local opaque: { Px } = {}
		for _, p in px do
			table.insert(opaque, p)
		end
		local palette = medianCut(opaque)
		local indices = buffer.create(W * H) -- 0 — прозрачно, k — palette[k]
		for i = 1, W * H do
			local p = px[i]
			if p ~= nil then
				buffer.writeu8(indices, i - 1, nearest(palette, p))
			end
		end
		table.insert(packed, { rank = rank, palette = palette, indices = indices })
	end
end

local lines: { string } = {
	"--!strict",
	"--[[",
	"\tRankData — погоны званий (§15ю). Сделано tools/rank_pack из assets/ranks — руками не править.",
	"\tpalette — цвета подряд по 6 hex-знаков; data — base64 индексов (0 — прозрачно, k — k-й цвет палитры).",
	"]]",
	"",
	"local RankData = {}",
	"",
	string.format("RankData.W = %d", W),
	string.format("RankData.H = %d", H),
	"",
	"-- stylua: ignore",
	"RankData.Ranks = table.freeze({",
}
for _, c in packed do
	local hex: { string } = {}
	for _, p in c.palette do
		table.insert(hex, string.format("%02x%02x%02x", p[1], p[2], p[3]))
	end
	table.insert(lines, string.format("\t[%d] = table.freeze({", c.rank))
	table.insert(lines, string.format('\t\tpalette = "%s",', table.concat(hex)))
	table.insert(lines, string.format('\t\tdata = "%s",', Base64.encode(c.indices)))
	table.insert(lines, "\t}),")
end
table.insert(lines, "}) :: { [number]: { palette: string, data: string } }")
table.insert(lines, "")
table.insert(lines, "return table.freeze(RankData)")
table.insert(lines, "")
fs.writeFile("src/shared/RankData.luau", table.concat(lines, "\n"))

-- Превью ×2 на тёмном фоне, в ряд.
local scale, pad = 2, 8
local PW, PH = #packed * (W * scale + pad) + pad, H * scale + 2 * pad
local pix = buffer.create(PW * PH * 3)
for i = 0, PW * PH - 1 do
	buffer.writeu8(pix, i * 3, 26)
	buffer.writeu8(pix, i * 3 + 1, 30)
	buffer.writeu8(pix, i * 3 + 2, 48)
end
for n, c in packed do
	local ox = pad + (n - 1) * (W * scale + pad)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local k = buffer.readu8(c.indices, y * W + x)
			if k > 0 then
				local p = c.palette[k]
				for sy = 0, scale - 1 do
					for sx = 0, scale - 1 do
						local i = ((pad + y * scale + sy) * PW + ox + x * scale + sx) * 3
						buffer.writeu8(pix, i, p[1])
						buffer.writeu8(pix, i + 1, p[2])
						buffer.writeu8(pix, i + 2, p[3])
					end
				end
			end
		end
	end
end
fs.writeFile(PREVIEW, Png.encodeRgb(PW, PH, pix))
print(string.format("погонов %d, %d×%d → src/shared/RankData.luau, превью %s", #packed, W, H, PREVIEW))
