--!strict
--[[
	Превью партии: прогоняет матч на карте без игроков-людей (только боты) и рисует территории
	теми же функциями, что и клиент (MapPaint + TerritoryPaint). Для проверки формы границ, цветов и темпа.
	Запуск из frontir/:  lune run tools/match_preview [секунд=75] [сид=12345] [файл=build/match.png]
	Картинка ×2 (PNG). Превью для отчёта этапа: lune run tools/match_preview 75 12345 docs/previews/stage-N.png
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapGen = require("../src/shared/MapGen")
local MapPaint = require("../src/shared/MapPaint")
local MatchSim = require("../src/shared/MatchSim")
local TerritoryPaint = require("../src/shared/TerritoryPaint")
local Png = require("./lib/Png")

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

local out = process.args[3] or "build/match.png"
local SCALE = 2
local terrain = MapPaint.paint(map)
local w, h = map.width, map.height
local W, H = w * SCALE, h * SCALE
local pixels = buffer.create(W * H * 3)
local function colorOf(owner: number): number
	local n = m.nations[owner]
	return if n ~= nil then n.colorIndex else 0
end
for y = 0, h - 1 do
	for x = 0, w - 1 do
		local r, g, b = TerritoryPaint.cellColor(terrain, m.grid.owner, w, h, y * w + x, colorOf, 0)
		for dy = 0, SCALE - 1 do
			for dx = 0, SCALE - 1 do
				local o = ((y * SCALE + dy) * W + x * SCALE + dx) * 3
				buffer.writeu8(pixels, o, r)
				buffer.writeu8(pixels, o + 1, g)
				buffer.writeu8(pixels, o + 2, b)
			end
		end
	end
end
local dir = string.match(out, "^(.*)/[^/]*$")
if dir ~= nil and not fs.isDir(dir) then
	fs.writeDir(dir)
end
fs.writeFile(
	out,
	Png.encodeRgb(W, H, pixels, { ["Frontir-Preview"] = string.format("seconds=%d seed=%d", seconds, seed) })
)

print(string.format("Партия %d с, сид %d → %s", seconds, seed, out))
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
