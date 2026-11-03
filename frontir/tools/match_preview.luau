--!strict
--[[
	Превью партии: прогоняет матч на карте без игроков-людей (только боты) и рисует территории
	теми же функциями, что и клиент (MapPaint + TerritoryPaint). Для проверки формы границ, цветов и темпа.
	Запуск из frontir/:  lune run tools/match_preview [секунд=75] [сид=12345] [держав=Config]
	Пишет build/match.bmp (в git не идёт) и печатает доли суши.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapGen = require("../src/shared/MapGen")
local MapPaint = require("../src/shared/MapPaint")
local MatchSim = require("../src/shared/MatchSim")
local TerritoryPaint = require("../src/shared/TerritoryPaint")

local seconds = tonumber(process.args[1]) or 75
local seed = tonumber(process.args[2]) or 12345

local map = MapGen.generate(Config.MapGen.Pangea)
local m = MatchSim.new(map, seed)
MatchSim.startPick(m)
local dt = 1 / Config.Sim.TickRate
while m.phase ~= "Play" do
	MatchSim.step(m, dt)
end
for _ = 1, math.floor(seconds * Config.Sim.TickRate) do
	MatchSim.step(m, dt)
end

local terrain = MapPaint.paint(map)
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
local function colorOf(owner: number): number
	local n = m.nations[owner]
	return if n ~= nil then n.colorIndex else 0
end
for y = 0, h - 1 do
	local row = 54 + (h - 1 - y) * rowSize
	for x = 0, w - 1 do
		local r, g, b = TerritoryPaint.cellColor(terrain, m.grid.owner, w, h, y * w + x, colorOf, 0)
		buffer.writeu8(bmp, row + x * 3, b)
		buffer.writeu8(bmp, row + x * 3 + 1, g)
		buffer.writeu8(bmp, row + x * 3 + 2, r)
	end
end
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile("build/match.bmp", bmp)

print(string.format("Партия %d с, сид %d → build/match.bmp", seconds, seed))
for _, n in m.nations do
	print(
		string.format(
			"  %d %-12s цвет %2d  суша %5.1f%%  люди %8.0f%s",
			n.id,
			n.name,
			n.colorIndex,
			Grid.cellsOf(m.grid, n.id) / m.grid.capturableCount * 100,
			n.people,
			if n.alive then "" else "  (пала)"
		)
	)
end
