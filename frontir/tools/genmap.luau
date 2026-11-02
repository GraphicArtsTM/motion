--!strict
--[[
	Генерация и упаковка выдуманной карты.
	Запуск из frontir/:  lune run tools/genmap Pangea
	Пишет maps/<Имя>.luau (ModuleScript для Roblox) и build/<Имя>.bmp (превью, в git не идёт).
	Параметры карты — Config.MapGen.<Имя>.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Config = require("../src/shared/Config")
local MapData = require("../src/shared/MapData")
local MapFormat = require("../src/shared/MapFormat")
local MapGen = require("../src/shared/MapGen")
local MapPaint = require("../src/shared/MapPaint")
local Types = require("../src/shared/Types")

local name = process.args[1] or Config.Match.DefaultMap
local params = (Config.MapGen :: any)[name] :: Types.MapGenParams?
if params == nil then
	print("Неизвестная карта: " .. name)
	process.exit(1)
	return
end

local started = os.clock()
local map, stats = MapGen.generate(params)
local genSec = os.clock() - started

-- Модуль карты.
local chunks = MapFormat.toChunks(map, Config.MapFile.ChunkChars)
local lines: { string } = {
	"--!strict",
	"-- @generated tools/genmap.luau — не редактировать вручную. Пересоздать: lune run tools/genmap "
		.. name,
	"return {",
	string.format("\tname = %q,", map.name),
	string.format("\tseed = %d,", map.seed),
	string.format("\twidth = %d,", map.width),
	string.format("\theight = %d,", map.height),
	string.format("\tformatVersion = %d,", MapFormat.FORMAT_VERSION),
	"\tdata = {",
}
for _, chunk in chunks do
	table.insert(lines, string.format('\t\t"%s",', chunk))
end
table.insert(lines, "\t},")
table.insert(lines, "}")
table.insert(lines, "")
local source = table.concat(lines, "\n")
fs.writeFile("maps/" .. name .. ".luau", source)

-- Превью BMP (24 бит, строки снизу вверх).
local colors = MapPaint.paint(map)
local w, h = map.width, map.height
local rowSize = (w * 3 + 3) // 4 * 4
local bmp = buffer.create(54 + rowSize * h)
buffer.writestring(bmp, 0, "BM")
buffer.writeu32(bmp, 2, buffer.len(bmp))
buffer.writeu32(bmp, 10, 54)
buffer.writeu32(bmp, 14, 40)
buffer.writei32(bmp, 18, w)
buffer.writei32(bmp, 22, h)
buffer.writeu16(bmp, 26, 1)
buffer.writeu16(bmp, 28, 24)
buffer.writeu32(bmp, 34, rowSize * h)
for y = 0, h - 1 do
	local row = 54 + (h - 1 - y) * rowSize
	for x = 0, w - 1 do
		local src = (y * w + x) * 4
		buffer.writeu8(bmp, row + x * 3, buffer.readu8(colors, src + 2))
		buffer.writeu8(bmp, row + x * 3 + 1, buffer.readu8(colors, src + 1))
		buffer.writeu8(bmp, row + x * 3 + 2, buffer.readu8(colors, src))
	end
end
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile("build/" .. name .. ".bmp", bmp)

local names: { [number]: string } = {}
for terrainName, id in Types.Terrain :: { [string]: number } do
	names[id] = terrainName
end
print(string.format("Карта %s %d×%d, сид %d, генерация %.2f с", name, w, h, map.seed, genSec))
print(
	string.format(
		"Суша %.1f%%, островов %d, озёр %d, рек %d",
		stats.landShare * 100,
		stats.islands,
		stats.lakes,
		stats.rivers
	)
)
local counts = MapData.terrainCounts(map)
for _, id in Types.TerrainIds do
	print(string.format("  %-10s %6d клеток", names[id], counts[id] or 0))
end
print(string.format("Модуль: maps/%s.luau, %d байт, строк base64: %d", name, #source, #chunks))
