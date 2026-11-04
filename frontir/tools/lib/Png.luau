--!strict
--[[
	Png — запись PNG (RGB, 8 бит) для Lune-инструментов: превью палитры и партий в docs/.
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

return table.freeze(Png)
