--!strict
--[[
	Картинки на карте — города и корабли (GDD §15ы Ы4) — гладко, как карточки, а не пиксель-арт палитры:
	PNG из assets/icons/{buildings,units} (512×512, прозрачный фон) →
	- обрезка пустых полей (рамка непрозрачных пикселей): корабль занимает всю ширину, город — весь жетон;
	- плавное уменьшение (среднее по квадрату с учётом прозрачности) до стороны не больше MAX по большей оси;
	- тёмный контур OUTLINE пикселей вокруг силуэта — читается на любой земле и воде;
	- своя палитра до MAX_COLORS цветов (median cut) + прозрачность каждого пикселя отдельно.
	→ src/shared/MapArtData.luau (+ части MapArtData1…N; руками не править), рисует игра через EditableImage
	(UI/IconImage.mapArt), чистый модуль — MapArt. Исключение из «только палитра» — как у карточек (GDD §15ы Ы4).
	Запуск из frontir/:  lune run tools/map_art_pack [превью=build/map_art_pack.png]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Base64 = require("../src/shared/Base64")
local Png = require("./lib/Png")

local MAX, MAX_COLORS, OUTLINE, PAD = 96, 96, 2, 3
local INK = { 11, 14, 26 } -- Ink палитры (docs/palette.md): контур
local OUTLINE_ALPHA = 215
local PREVIEW = process.args[1] or "build/map_art_pack.png"
local PER_PART = 4

-- Что упаковать: имя → папка (имя картинки = имя иконки в IconData).
local SOURCES: { { name: string, dir: string } } = {
	{ name = "City", dir = "assets/icons/buildings" },
	{ name = "City1", dir = "assets/icons/buildings" },
	{ name = "City2", dir = "assets/icons/buildings" },
	{ name = "City3", dir = "assets/icons/buildings" },
	{ name = "City4", dir = "assets/icons/buildings" },
	{ name = "City5", dir = "assets/icons/buildings" },
	{ name = "CityCapital", dir = "assets/icons/buildings" },
	{ name = "Destroyer", dir = "assets/icons/units" },
	{ name = "Transport", dir = "assets/icons/units" },
	{ name = "Merchant", dir = "assets/icons/units" },
}

type Px = { number } -- r, g, b
type Packed = { name: string, w: number, h: number, palette: { Px }, indices: buffer, alpha: buffer }

local function alphaAt(img: Png.Image, x: number, y: number): number
	return buffer.readu8(img.rgba, (y * img.width + x) * 4 + 3)
end

-- Рамка непрозрачных пикселей (альфа ≥ 32).
local function bounds(img: Png.Image): (number, number, number, number)
	local x0, y0, x1, y1 = img.width, img.height, -1, -1
	for y = 0, img.height - 1 do
		for x = 0, img.width - 1 do
			if alphaAt(img, x, y) >= 32 then
				x0, y0 = math.min(x0, x), math.min(y0, y)
				x1, y1 = math.max(x1, x), math.max(y1, y)
			end
		end
	end
	return x0, y0, x1, y1
end

-- Уменьшение рамки (x0..x1, y0..y1) в w×h с полями PAD: цвет — среднее с весом прозрачности, альфа — средняя.
local function shrink(img: Png.Image, x0: number, y0: number, sw: number, sh: number, w: number, h: number)
	local rgb: { Px } = table.create(w * h)
	local alpha = buffer.create(w * h)
	local iw, ih = w - 2 * PAD, h - 2 * PAD
	local bx, by = sw / iw, sh / ih
	for ty = 0, h - 1 do
		for tx = 0, w - 1 do
			local ix, iy = tx - PAD, ty - PAD
			local r, g, b, a, n = 0, 0, 0, 0, 0
			if ix >= 0 and iy >= 0 and ix < iw and iy < ih then
				local sx0 = x0 + math.floor(ix * bx)
				local sx1 = math.max(sx0, x0 + math.floor((ix + 1) * bx) - 1)
				local sy0 = y0 + math.floor(iy * by)
				local sy1 = math.max(sy0, y0 + math.floor((iy + 1) * by) - 1)
				for y = sy0, math.min(sy1, img.height - 1) do
					for x = sx0, math.min(sx1, img.width - 1) do
						local o = (y * img.width + x) * 4
						local pa = buffer.readu8(img.rgba, o + 3)
						r += buffer.readu8(img.rgba, o) * pa
						g += buffer.readu8(img.rgba, o + 1) * pa
						b += buffer.readu8(img.rgba, o + 2) * pa
						a += pa
						n += 1
					end
				end
			end
			local i = ty * w + tx
			if a > 0 then
				rgb[i + 1] = { math.round(r / a), math.round(g / a), math.round(b / a) }
			else
				rgb[i + 1] = { 0, 0, 0 }
			end
			buffer.writeu8(alpha, i, if n > 0 then math.round(a / n) else 0)
		end
	end
	return rgb, alpha
end

-- Тёмный контур: прозрачные пиксели рядом с силуэтом (в круге OUTLINE) — Ink с прозрачностью OUTLINE_ALPHA.
local function outline(rgb: { Px }, alpha: buffer, w: number, h: number)
	local solid = buffer.create(w * h)
	for i = 0, w * h - 1 do
		buffer.writeu8(solid, i, if buffer.readu8(alpha, i) >= 140 then 1 else 0)
	end
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local i = y * w + x
			local a = buffer.readu8(alpha, i)
			if a < 200 then
				local near = false
				for dy = -OUTLINE, OUTLINE do
					for dx = -OUTLINE, OUTLINE do
						local nx, ny = x + dx, y + dy
						if
							dx * dx + dy * dy <= OUTLINE * OUTLINE
							and nx >= 0
							and ny >= 0
							and nx < w
							and ny < h
							and buffer.readu8(solid, ny * w + nx) == 1
						then
							near = true
						end
					end
				end
				if near then
					-- Смешать «под» картинку: край картинки остаётся, за ним — контур.
					local k = a / 255
					local p = rgb[i + 1]
					rgb[i + 1] = {
						math.round(p[1] * k + INK[1] * (1 - k)),
						math.round(p[2] * k + INK[2] * (1 - k)),
						math.round(p[3] * k + INK[3] * (1 - k)),
					}
					buffer.writeu8(alpha, i, math.max(a, OUTLINE_ALPHA))
				end
			end
		end
	end
end

-- Median cut по видимым пикселям.
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

local packed: { Packed } = {}
for _, src in SOURCES do
	local path = src.dir .. "/" .. src.name .. ".png"
	if not fs.isFile(path) then
		print("нет картинки", path)
		continue
	end
	local img = Png.decode(fs.readFile(path))
	local x0, y0, x1, y1 = bounds(img)
	local sw, sh = x1 - x0 + 1, y1 - y0 + 1
	local s = math.max(sw, sh) / (MAX - 2 * PAD)
	local w = math.max(1, math.round(sw / s)) + 2 * PAD
	local h = math.max(1, math.round(sh / s)) + 2 * PAD
	local rgb, alpha = shrink(img, x0, y0, sw, sh, w, h)
	outline(rgb, alpha, w, h)
	local visible: { Px } = {}
	for i, p in rgb do
		if buffer.readu8(alpha, i - 1) > 0 then
			table.insert(visible, p)
		end
	end
	local palette = medianCut(visible)
	local indices = buffer.create(w * h)
	for i, p in rgb do
		buffer.writeu8(indices, i - 1, nearest(palette, p) - 1)
	end
	table.insert(packed, { name = src.name, w = w, h = h, palette = palette, indices = indices, alpha = alpha })
	print(string.format("%s %d×%d, цветов %d", src.name, w, h, #palette))
end

-- Части по PER_PART картинок; индекс MapArtData подключает их строками require.
local MODULE = "MapArtData"
local partCount = math.max(1, math.ceil(#packed / PER_PART))
for _, f in fs.readDir("src/shared") do
	if string.match(f, "^" .. MODULE .. "%d+%.luau$") then
		fs.removeFile("src/shared/" .. f)
	end
end
local ENTRY = "{ w: number, h: number, palette: string, data: string, alpha: string }"
for part = 1, partCount do
	local lines: { string } = {
		"--!strict",
		string.format(
			"-- %s%d — часть картинок на карте. Сделано tools/map_art_pack из assets/icons — руками не править.",
			MODULE,
			part
		),
		"",
		"-- stylua: ignore",
		"return table.freeze({",
	}
	for n = (part - 1) * PER_PART + 1, math.min(#packed, part * PER_PART) do
		local c = packed[n]
		local hex: { string } = {}
		for _, p in c.palette do
			table.insert(hex, string.format("%02x%02x%02x", p[1], p[2], p[3]))
		end
		table.insert(lines, string.format("\t%s = table.freeze({", c.name))
		table.insert(lines, string.format("\t\tw = %d,", c.w))
		table.insert(lines, string.format("\t\th = %d,", c.h))
		table.insert(lines, string.format('\t\tpalette = "%s",', table.concat(hex)))
		table.insert(lines, string.format('\t\tdata = "%s",', Base64.encode(c.indices)))
		table.insert(lines, string.format('\t\talpha = "%s",', Base64.encode(c.alpha)))
		table.insert(lines, "\t}),")
	end
	table.insert(lines, string.format("}) :: { [string]: %s }", ENTRY))
	table.insert(lines, "")
	fs.writeFile(string.format("src/shared/%s%d.luau", MODULE, part), table.concat(lines, "\n"))
end
local index: { string } = {
	"--!strict",
	"--[[",
	"\tMapArtData — картинки на карте: города и корабли (GDD §15ы Ы4). Сделано tools/map_art_pack из assets/icons —",
	"\tруками не править. w × h — размер; palette — цвета по 6 hex-знаков; data — base64 индексов (байт на пиксель,",
	"\tстроки сверху вниз); alpha — base64 прозрачности (байт на пиксель). Картинки лежат частями, здесь — сборка.",
	"]]",
	"",
	string.format("export type Art = %s", ENTRY),
	"",
	"local arts: { [string]: Art } = {}",
	"for _, part in {",
}
for part = 1, partCount do
	table.insert(index, string.format('\trequire("./%s%d"),', MODULE, part))
end
table.insert(index, "} :: { { [string]: Art } } do")
table.insert(index, "\tfor name, art in part do")
table.insert(index, "\t\tarts[name] = art")
table.insert(index, "\tend")
table.insert(index, "end")
table.insert(index, "")
table.insert(index, "return table.freeze({ Arts = table.freeze(arts) })")
table.insert(index, "")
fs.writeFile(string.format("src/shared/%s.luau", MODULE), table.concat(index, "\n"))

-- Превью ×2 на светлой траве и тёмной воде (как на карте): слева — трава, справа — вода.
local scale, pad = 2, 8
local cellW = MAX * scale + pad
local PW = #packed * cellW + pad
local PH = 2 * (MAX * scale + pad) + pad
local pix = buffer.create(PW * PH * 3)
local GRASS, SEA = { 104, 160, 62 }, { 14, 32, 64 }
for row = 0, 1 do
	local bg = if row == 0 then GRASS else SEA
	for y = 0, MAX * scale + pad - 1 do
		for x = 0, PW - 1 do
			local i = ((row * (MAX * scale + pad) + y) * PW + x) * 3
			buffer.writeu8(pix, i, bg[1])
			buffer.writeu8(pix, i + 1, bg[2])
			buffer.writeu8(pix, i + 2, bg[3])
		end
	end
	for n, c in packed do
		local ox = pad + (n - 1) * cellW + (MAX - c.w) * scale // 2
		local oy = row * (MAX * scale + pad) + pad + (MAX - c.h) * scale // 2
		for y = 0, c.h - 1 do
			for x = 0, c.w - 1 do
				local a = buffer.readu8(c.alpha, y * c.w + x) / 255
				local p = c.palette[buffer.readu8(c.indices, y * c.w + x) + 1]
				for sy = 0, scale - 1 do
					for sx = 0, scale - 1 do
						local i = ((oy + y * scale + sy) * PW + ox + x * scale + sx) * 3
						for ch = 0, 2 do
							local under = buffer.readu8(pix, i + ch)
							buffer.writeu8(pix, i + ch, math.round(p[ch + 1] * a + under * (1 - a)))
						end
					end
				end
			end
		end
	end
end
fs.writeFile(PREVIEW, Png.encodeRgb(PW, PH, pix))
print(
	string.format(
		"картинок %d → src/shared/%s.luau (+%d частей), превью %s",
		#packed,
		MODULE,
		partCount,
		PREVIEW
	)
)
