--!strict
--[[
	Превью партии: прогоняет матч на карте без игроков-людей (только боты) и рисует территории
	теми же функциями, что и клиент (MapPaint + TerritoryPaint). Для проверки формы границ, цветов и темпа.
	Запуск из frontir/:  lune run tools/match_preview [секунд=75] [сид=12345] [файл=build/match.png]
	Картинка (PNG): сверху вся карта ×2 с городами и юнитами вдоль фронтов (как на клиенте на зуме ×2),
	снизу — крупно самый большой бой (как на зуме ×8: юниты крупнее, вспышки и разрывы).
	Превью для отчёта этапа: lune run tools/match_preview 75 12345 docs/previews/stage-N.png
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Config = require("../src/shared/Config")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local MapGen = require("../src/shared/MapGen")
local MapPaint = require("../src/shared/MapPaint")
local MatchSim = require("../src/shared/MatchSim")
local TerritoryPaint = require("../src/shared/TerritoryPaint")
local NationColors = require("../src/shared/NationColors")
local Palette = require("../src/shared/Palette")
local Rng = require("../src/shared/Rng")
local Types = require("../src/shared/Types")
local UnitSprites = require("../src/shared/UnitSprites")
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
local terrain = MapPaint.paint(map)
local w, h = map.width, map.height
local g = m.grid
local ink = Palette.rgb("Ink")
local white = Palette.rgb("White")
local mist = Palette.rgb("Mist")
local gold = Palette.rgb("Gold")
local orange = Palette.rgb("Orange")
local red = Palette.rgb("Red")

local function colorOf(owner: number): number
	local n = m.nations[owner]
	return if n ~= nil then n.colorIndex else 0
end
local function ownerRgb(owner: number): Palette.Rgb
	local ci = colorOf(owner)
	return if ci >= 1 then NationColors.Colors[ci] else mist
end

-- Фронты с войсками и их линии: клетки атакующего у границы с целью и клетки цели напротив
-- (тот же разбор, что в клиентском Render/FrontLayer, только по всей карте).
type Front = { attack: Types.Attack, power: number, mix: { number }, own: { number }, enemy: { number } }
local fronts: { Front } = {}
local pairIndex: { [number]: number } = {}
for _, a in m.attacks do
	local power = Forces.total(a.forces)
	if a.target ~= 0 and power > 0 then
		table.insert(fronts, { attack = a, power = power, mix = Forces.composition(a.forces), own = {}, enemy = {} })
		pairIndex[a.attacker * 65536 + a.target] = #fronts
	end
end
for i = 0, w * h - 1 do
	local o = Grid.getOwner(g, i)
	if o ~= 0 then
		Grid.forNeighbours(g, i, function(j: number)
			local p = Grid.getOwner(g, j)
			if p ~= o then
				local k = pairIndex[o * 65536 + p]
				if k ~= nil then
					table.insert(fronts[k].own, i)
				end
				local back = pairIndex[p * 65536 + o]
				if back ~= nil then
					table.insert(fronts[back].enemy, i)
				end
			end
		end)
	end
end

-- Рисует область карты (клетки x0..x0+cw-1, y0..y0+ch-1) в картинку со сдвигом (ox, oy):
-- клетка = cell пикселей, пиксель спрайта = sprite пикселей.
local function renderRegion(
	pixels: buffer,
	W: number,
	H: number,
	ox: number,
	oy: number,
	x0: number,
	y0: number,
	cw: number,
	ch: number,
	cell: number,
	sprite: number,
	bursts: number
)
	local function rect(px: number, py: number, pw: number, ph: number, c: Palette.Rgb)
		local left, top = math.max(ox, px), math.max(oy, py)
		local right, bottom = math.min(ox + cw * cell, px + pw), math.min(oy + ch * cell, py + ph)
		for yy = top, math.min(H, bottom) - 1 do
			for xx = left, math.min(W, right) - 1 do
				local o = (yy * W + xx) * 3
				buffer.writeu8(pixels, o, c.r)
				buffer.writeu8(pixels, o + 1, c.g)
				buffer.writeu8(pixels, o + 2, c.b)
			end
		end
	end
	local function inRegion(i: number): boolean
		local x, y = i % w, i // w
		return x >= x0 and x < x0 + cw and y >= y0 and y < y0 + ch
	end
	local function px(i: number): (number, number)
		return ox + (i % w - x0) * cell, oy + (i // w - y0) * cell
	end
	-- Территории.
	for y = y0, y0 + ch - 1 do
		for x = x0, x0 + cw - 1 do
			local r, gg, b = TerritoryPaint.cellColor(terrain, g.owner, w, h, y * w + x, colorOf, 0)
			rect(ox + (x - x0) * cell, oy + (y - y0) * cell, cell, cell, { r = r, g = gg, b = b })
		end
	end
	-- Города: квадрат цвета владельца с белой точкой.
	local citySize = math.max(8, cell * 2)
	for _, c in MatchSim.cities(m) do
		if inRegion(c) then
			local cx, cy = px(c)
			cx += cell // 2
			cy += cell // 2
			local half = citySize // 2
			rect(cx - half - 1, cy - half - 1, citySize + 2, citySize + 2, ink)
			rect(cx - half, cy - half, citySize, citySize, ownerRgb(Grid.getOwner(g, c)))
			rect(cx - 1, cy - 1, 2, 2, white)
		end
	end
	-- Юниты вдоль линий фронтов (тот же предел и та же раскладка, что у клиента).
	local function unit(kind: string, owner: number, i: number, unsupplied: boolean)
		local cx, cy = px(i)
		local left = cx + cell // 2 - UnitSprites.Width * sprite // 2
		local top = cy + cell - UnitSprites.Height * sprite
		local body = ownerRgb(owner)
		local outline = if unsupplied then red else ink
		local shape = UnitSprites.Shapes[kind]
		-- Обводка в 1 пиксель, как UIStroke у клиента.
		for _, p in shape do
			if not p.ink then
				rect(left + p.x * sprite - 1, top + p.y * sprite - 1, p.w * sprite + 2, p.h * sprite + 2, outline)
			end
		end
		for _, p in shape do
			rect(left + p.x * sprite, top + p.y * sprite, p.w * sprite, p.h * sprite, if p.ink then ink else body)
		end
	end
	local function visible(list: { number }): { number }
		local outList: { number } = {}
		for _, i in list do
			if inRegion(i) then
				table.insert(outList, i)
			end
		end
		return outList
	end
	local cfg = Config.Render
	local budget = cfg.FrontSpritesTotal
	local perFront = math.min(cfg.FrontSpritesPerFront, math.max(4, math.floor(budget / math.max(1, #fronts))))
	local rng = Rng.new(seed)
	for _, f in fronts do
		local a = f.attack
		local hasCounter = pairIndex[a.target * 65536 + a.attacker] ~= nil
		local target = m.nations[a.target]
		local defended = not hasCounter and target ~= nil and Forces.total(target.home) > 0
		local nAttack = if defended then math.ceil(perFront * 0.65) else perFront
		local own = UnitSprites.spread(visible(f.own), math.min(nAttack, budget))
		for idx, i in own do
			unit(UnitSprites.kindAt(f.mix, idx, #own), a.attacker, i, not a.supplied)
		end
		budget -= #own
		local enemyLine = visible(f.enemy)
		if defended then
			local enemy = UnitSprites.spread(enemyLine, math.min(perFront - nAttack, budget))
			for _, i in enemy do
				unit(Types.LandUnits[1], a.target, i, false)
			end
			budget -= #enemy
		end
		-- Бой: вспышки выстрелов и разрывы на линии.
		if a.fighting and #enemyLine > 0 then
			for _ = 1, bursts do
				local i = enemyLine[Rng.range(rng, 1, #enemyLine)]
				local cx, cy = px(i)
				local big = Rng.nextFloat(rng) < 0.35
				local size = if big then math.max(3, cell * 2) else math.max(2, cell)
				local c = if not big then gold elseif Rng.nextFloat(rng) < 0.5 then orange else red
				rect(cx + Rng.range(rng, 0, cell) - size // 2, cy + Rng.range(rng, 0, cell) - size // 2, size, size, c)
			end
		end
	end
end

-- Самый большой бой — для крупного плана.
local hottest: Front? = nil
for _, f in fronts do
	if f.attack.fighting and #f.enemy > 0 and (hottest == nil or f.power > hottest.power) then
		hottest = f
	end
end

local SCALE = 2
local ZOOM = 8
local W = w * SCALE
local mapH = h * SCALE
local cropW = W // ZOOM
local cropH = if hottest ~= nil then 44 else 0
local H = mapH + (if cropH > 0 then 4 + cropH * ZOOM else 0)
local pixels = buffer.create(W * H * 3)
renderRegion(pixels, W, H, 0, 0, 0, 0, w, h, SCALE, UnitSprites.scaleFor(SCALE), 4)
if hottest ~= nil then
	-- Центр крупного плана — средняя точка линии фронта.
	local sx, sy = 0, 0
	for _, i in hottest.enemy do
		sx += i % w
		sy += i // w
	end
	local cx, cy = sx // #hottest.enemy, sy // #hottest.enemy
	local x0 = math.clamp(cx - cropW // 2, 0, w - cropW)
	local y0 = math.clamp(cy - cropH // 2, 0, h - cropH)
	local strip = { r = ink.r, g = ink.g, b = ink.b }
	for yy = mapH, mapH + 3 do
		for xx = 0, W - 1 do
			local o = (yy * W + xx) * 3
			buffer.writeu8(pixels, o, strip.r)
			buffer.writeu8(pixels, o + 1, strip.g)
			buffer.writeu8(pixels, o + 2, strip.b)
		end
	end
	renderRegion(pixels, W, H, 0, mapH + 4, x0, y0, cropW, cropH, ZOOM, UnitSprites.scaleFor(ZOOM), 30)
end

local dir = string.match(out, "^(.*)/[^/]*$")
if dir ~= nil and not fs.isDir(dir) then
	fs.writeDir(dir)
end
fs.writeFile(
	out,
	Png.encodeRgb(W, H, pixels, { ["Frontir-Preview"] = string.format("seconds=%d seed=%d", seconds, seed) })
)

print(
	string.format(
		"Партия %d с, сид %d → %s, фронтов с войсками %d",
		seconds,
		seed,
		out,
		#fronts
	)
)
for _, n in m.nations do
	print(
		string.format(
			"  %d %-12s цвет %2d  суша %5.1f%%  люди %8.0f  гарнизон %6.0f%s",
			n.id,
			n.name,
			n.colorIndex,
			Grid.cellsOf(g, n.id) / g.capturableCount * 100,
			n.people,
			Forces.total(n.home),
			if n.alive then "" else "  (пала)"
		)
	)
end
for _, f in fronts do
	local a = f.attack
	print(
		string.format(
			"  фронт %d → %d: сила %.0f, перевес %s%s%s",
			a.attacker,
			a.target,
			f.power,
			if a.ratio == math.huge then "∞" else string.format("%.2f", a.ratio),
			if a.fighting then ", бой" else "",
			if a.supplied then "" else ", без снабжения"
		)
	)
end
