--!strict
--[[
	Png — запись PNG (RGB, 8 бит) для Lune-инструментов: превью палитры и партий в docs/; чтение PNG
	(8 бит, RGB / RGBA, без чересстрочности) — для tools/icon_pack.
	Сжатие — zlib из @lune/serde, CRC32 — свой. Текстовые блоки tEXt помогают тестам понять,
	соответствует ли картинка текущему коду.
]]

local serde = require("@lune/serde")

local Png = {}

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

-- pixels — RGB по 3 байта, строки сверху вниз. text — блоки tEXt (ключ → значение), порядок по ключу.
function Png.encodeRgb(width: number, height: number, pixels: buffer, text: { [string]: string }?): string
	local rows: { string } = table.create(height)
	for y = 0, height - 1 do
		rows[y + 1] = "\0" .. buffer.readstring(pixels, y * width * 3, width * 3)
	end
	local parts = { "\137PNG\r\n\26\n", chunk("IHDR", u32be(width) .. u32be(height) .. string.char(8, 2, 0, 0, 0)) }
	if text then
		local keys: { string } = {}
		for k in text do
			table.insert(keys, k)
		end
		table.sort(keys)
		for _, k in keys do
			table.insert(parts, chunk("tEXt", k .. "\0" .. text[k]))
		end
	end
	table.insert(parts, chunk("IDAT", serde.compress("zlib", table.concat(rows))))
	table.insert(parts, chunk("IEND", ""))
	return table.concat(parts)
end

local function u32at(s: string, i: number): number
	local a, b, c, d = string.byte(s, i, i + 3)
	return ((a * 256 + b) * 256 + c) * 256 + d
end

export type Image = { width: number, height: number, rgba: buffer } -- RGBA по 4 байта, строки сверху вниз

-- Чтение PNG: 8 бит на канал, RGB (тип 2) или RGBA (тип 6), без чересстрочности; фильтры строк 0–4.
function Png.decode(data: string): Image
	assert(string.sub(data, 1, 8) == "\137PNG\r\n\26\n", "не PNG")
	local pos = 9
	local width, height, colorType = 0, 0, 0
	local idat: { string } = {}
	while pos <= #data do
		local len = u32at(data, pos)
		local kind = string.sub(data, pos + 4, pos + 7)
		local body = string.sub(data, pos + 8, pos + 7 + len)
		if kind == "IHDR" then
			width, height = u32at(body, 1), u32at(body, 5)
			local depth, interlace = string.byte(body, 9), string.byte(body, 13)
			colorType = string.byte(body, 10)
			assert(
				depth == 8 and interlace == 0 and (colorType == 2 or colorType == 6),
				"PNG: нужен 8 бит RGB/RGBA"
			)
		elseif kind == "IDAT" then
			table.insert(idat, body)
		elseif kind == "IEND" then
			break
		end
		pos += 12 + len
	end
	local raw = serde.decompress("zlib", table.concat(idat))
	local bpp = if colorType == 6 then 4 else 3
	local stride = width * bpp
	local cur = buffer.create(stride)
	local prev = buffer.create(stride)
	local out = buffer.create(width * height * 4)
	local p = 1
	for y = 0, height - 1 do
		local filter = string.byte(raw, p)
		p += 1
		for x = 0, stride - 1 do
			local v = string.byte(raw, p + x)
			local left = if x >= bpp then buffer.readu8(cur, x - bpp) else 0
			local up = buffer.readu8(prev, x)
			local ul = if x >= bpp then buffer.readu8(prev, x - bpp) else 0
			if filter == 1 then
				v += left
			elseif filter == 2 then
				v += up
			elseif filter == 3 then
				v += (left + up) // 2
			elseif filter == 4 then
				local pp = left + up - ul
				local pa, pb, pc = math.abs(pp - left), math.abs(pp - up), math.abs(pp - ul)
				v += if pa <= pb and pa <= pc then left elseif pb <= pc then up else ul
			end
			buffer.writeu8(cur, x, v % 256)
		end
		p += stride
		for x = 0, width - 1 do
			local o = (y * width + x) * 4
			buffer.writeu8(out, o, buffer.readu8(cur, x * bpp))
			buffer.writeu8(out, o + 1, buffer.readu8(cur, x * bpp + 1))
			buffer.writeu8(out, o + 2, buffer.readu8(cur, x * bpp + 2))
			buffer.writeu8(out, o + 3, if bpp == 4 then buffer.readu8(cur, x * bpp + 3) else 255)
		end
		cur, prev = prev, cur
	end
	return { width = width, height = height, rgba = out }
end

return table.freeze(Png)
