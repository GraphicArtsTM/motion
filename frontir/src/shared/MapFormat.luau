--!strict
--[[
	MapFormat — бинарный формат карты (GDD §4) и упаковка в ModuleScript.

	Бинарный буфер, little-endian:
	  0  "FRMP"          4 байта, сигнатура
	  4  u8  версия      FORMAT_VERSION
	  5  u16 ширина
	  7  u16 высота
	  9  u32 длина RLE местности, байт
	  13 u32 длина RLE провинций, байт
	  17 RLE местности:  [varint длина серии][u8 тип местности]...
	  .. RLE провинций:  [varint длина серии][u16 id провинции]...
	varint — беззнаковый LEB128. Серии идут по клеткам в порядке индекса (y * width + x).

	Модуль карты (maps/<Имя>.luau, пишут tools/genmap.luau и tools/realmap.luau) возвращает MapModule:
	  { name, seed, width, height, formatVersion, data = { "<base64>", ... }, provinceNames = { { ru, en }, ... }? }
	Строки data склеиваются и декодируются из base64 в бинарный буфер выше. provinceNames (реальные карты) —
	имена провинций по id; без них имена придумывает Provinces.
]]

local Base64 = require("./Base64")
local MapData = require("./MapData")
local Types = require("./Types")

type MapData = MapData.MapData

export type MapModule = {
	name: string,
	seed: number,
	width: number,
	height: number,
	formatVersion: number,
	data: { string },
	provinceNames: { { string } }?, -- { ru, en } по id провинции
	cities: { { any } }?, -- реальные города (§15д ч.4, tools/realcities): { клетка, ru, en }, крупные — первыми
}

local MAGIC = "FRMP"
local FORMAT_VERSION = 1
local HEADER_SIZE = 17

local MapFormat = {}

MapFormat.FORMAT_VERSION = FORMAT_VERSION

-- Запись varint (LEB128) в буфер; возвращает новую позицию.
local function writeVarint(buf: buffer, pos: number, value: number): number
	local v = value
	while v >= 128 do
		buffer.writeu8(buf, pos, v % 128 + 128)
		pos += 1
		v = v // 128
	end
	buffer.writeu8(buf, pos, v)
	return pos + 1
end

-- Чтение varint; возвращает значение и новую позицию. Не выходит за limit.
local function readVarint(buf: buffer, pos: number, limit: number): (number, number)
	local value = 0
	local mult = 1
	while true do
		if pos >= limit then
			error("MapFormat: обрыв данных внутри varint", 3)
		end
		local b = buffer.readu8(buf, pos)
		pos += 1
		value += (b % 128) * mult
		if b < 128 then
			return value, pos
		end
		mult *= 128
		if mult > 2 ^ 35 then
			error("MapFormat: слишком длинный varint", 3)
		end
	end
end

-- RLE одного слоя (элементы по stride байт). Пишет в out начиная с pos, возвращает новую позицию.
local function encodeLayer(src: buffer, count: number, stride: number, out: buffer, pos: number): number
	local i = 0
	while i < count do
		local value = if stride == 1 then buffer.readu8(src, i) else buffer.readu16(src, i * 2)
		local run = 1
		while i + run < count do
			local nextValue = if stride == 1 then buffer.readu8(src, i + run) else buffer.readu16(src, (i + run) * 2)
			if nextValue ~= value then
				break
			end
			run += 1
		end
		pos = writeVarint(out, pos, run)
		if stride == 1 then
			buffer.writeu8(out, pos, value)
		else
			buffer.writeu16(out, pos, value)
		end
		pos += stride
		i += run
	end
	return pos
end

local function decodeLayer(src: buffer, pos: number, limit: number, count: number, stride: number, dst: buffer)
	local i = 0
	while i < count do
		local run
		run, pos = readVarint(src, pos, limit)
		if run == 0 or i + run > count then
			error("MapFormat: серия RLE выходит за пределы карты", 2)
		end
		if pos + stride > limit then
			error("MapFormat: обрыв данных в слое", 2)
		end
		local value = if stride == 1 then buffer.readu8(src, pos) else buffer.readu16(src, pos)
		pos += stride
		for k = i, i + run - 1 do
			if stride == 1 then
				buffer.writeu8(dst, k, value)
			else
				buffer.writeu16(dst, k * 2, value)
			end
		end
		i += run
	end
	if pos ~= limit then
		error("MapFormat: в слое лишние байты", 2)
	end
end

-- Карта → бинарный буфер.
function MapFormat.encode(map: MapData): buffer
	local count = map.width * map.height
	-- Худший случай: каждая клетка — своя серия (varint до 5 байт + значение).
	local scratch = buffer.create(HEADER_SIZE + count * 6 + count * 7)
	local pos = HEADER_SIZE
	local terrainStart = pos
	pos = encodeLayer(map.terrain, count, 1, scratch, pos)
	local terrainLen = pos - terrainStart
	local provinceStart = pos
	pos = encodeLayer(map.province, count, 2, scratch, pos)
	local provinceLen = pos - provinceStart

	buffer.writestring(scratch, 0, MAGIC)
	buffer.writeu8(scratch, 4, FORMAT_VERSION)
	buffer.writeu16(scratch, 5, map.width)
	buffer.writeu16(scratch, 7, map.height)
	buffer.writeu32(scratch, 9, terrainLen)
	buffer.writeu32(scratch, 13, provinceLen)

	local out = buffer.create(pos)
	buffer.copy(out, 0, scratch, 0, pos)
	return out
end

-- Бинарный буфер → карта. Любая порча данных — ошибка с понятным текстом.
function MapFormat.decode(data: buffer, name: string, seed: number): MapData
	local len = buffer.len(data)
	if len < HEADER_SIZE then
		error("MapFormat: буфер короче заголовка", 2)
	end
	if buffer.readstring(data, 0, 4) ~= MAGIC then
		error("MapFormat: неверная сигнатура", 2)
	end
	local version = buffer.readu8(data, 4)
	if version ~= FORMAT_VERSION then
		error(
			string.format(
				"MapFormat: версия %d не поддерживается (нужна %d)",
				version,
				FORMAT_VERSION
			),
			2
		)
	end
	local width = buffer.readu16(data, 5)
	local height = buffer.readu16(data, 7)
	local terrainLen = buffer.readu32(data, 9)
	local provinceLen = buffer.readu32(data, 13)
	if width == 0 or height == 0 then
		error("MapFormat: нулевой размер карты", 2)
	end
	if HEADER_SIZE + terrainLen + provinceLen ~= len then
		error("MapFormat: длины слоёв не совпадают с размером буфера", 2)
	end
	local map = MapData.new(name, seed, width, height)
	local count = width * height
	local terrainEnd = HEADER_SIZE + terrainLen
	decodeLayer(data, HEADER_SIZE, terrainEnd, count, 1, map.terrain)
	decodeLayer(data, terrainEnd, len, count, 2, map.province)
	local maxTerrain = #Types.TerrainIds - 1
	for i = 0, count - 1 do
		if buffer.readu8(map.terrain, i) > maxTerrain then
			error("MapFormat: неизвестный тип местности в клетке " .. i, 2)
		end
	end
	return map
end

-- Карта → строки base64 по chunkChars символов (для модуля карты).
function MapFormat.toChunks(map: MapData, chunkChars: number): { string }
	assert(
		chunkChars > 0 and chunkChars % 4 == 0,
		"длина строки base64 должна делиться на 4"
	)
	local text = Base64.encode(MapFormat.encode(map))
	local chunks: { string } = {}
	for i = 1, #text, chunkChars do
		table.insert(chunks, string.sub(text, i, i + chunkChars - 1))
	end
	return chunks
end

-- Модуль карты → карта (с проверкой полей модуля).
function MapFormat.fromModule(module: MapModule): MapData
	if module.formatVersion ~= FORMAT_VERSION then
		error(
			string.format(
				"карта %s: версия формата %d, нужна %d",
				module.name,
				module.formatVersion,
				FORMAT_VERSION
			),
			2
		)
	end
	local map = MapFormat.decode(Base64.decode(table.concat(module.data)), module.name, module.seed)
	local names = module.provinceNames
	if names ~= nil then
		local list: { MapData.ProvinceName } = {}
		for id, pair in names do
			list[id] = { ru = pair[1], en = pair[2] }
		end
		map.provinceNames = list
	end
	local cities = module.cities
	if cities ~= nil then
		local list: { MapData.MapCity } = {}
		for _, c in cities do
			table.insert(list, { cell = c[1] :: number, ru = c[2] :: string, en = c[3] :: string })
		end
		map.cities = list
	end
	if map.width ~= module.width or map.height ~= module.height then
		error(
			string.format(
				"карта %s: размер в модуле не совпадает с данными",
				module.name
			),
			2
		)
	end
	return map
end

return table.freeze(MapFormat)
