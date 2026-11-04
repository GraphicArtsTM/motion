--!strict
--[[
	Превью партии: прогоняет матч на карте без игроков-людей (только боты) и рисует территории
	теми же функциями, что и клиент (MapPaint + TerritoryPaint). Для проверки формы границ, цветов и темпа.
	Запуск из frontir/:  lune run tools/match_preview [секунд=75] [сид=12345] [файл=build/match.png]
	                     [карта=Config.Match.DefaultMap] [держав=Config.Match.TargetNations]
	Карта — модуль из maps/ (реальные карты пишет tools/realmap; «Pangea» — тестовая).
	Картинка (PNG): сверху вся карта ×2 с городами и юнитами вдоль фронтов (как на клиенте на зуме ×2),
	снизу — крупно бой (как на зуме ×8): если есть бой через реку — он, иначе самый большой. Юниты стоят
	по той же раскладке, что у клиента (Shared.BattleLayout): ничейная полоса, артиллерия в тылу; снаряды
	по дуге, разрывы, воронки и дым — как кадр боя.
	Превью для отчёта этапа: lune run tools/match_preview 75 12345 docs/previews/stage-N.png
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local BattleLayout = require("../src/shared/BattleLayout")
local BuildingSprites = require("../src/shared/BuildingSprites")
local Config = require("../src/shared/Config")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MapFormat = require("../src/shared/MapFormat")
local MapPaint = require("../src/shared/MapPaint")
local MatchSim = require("../src/shared/MatchSim")
local MinimapPaint = require("../src/shared/MinimapPaint")
local TerritoryPaint = require("../src/shared/TerritoryPaint")
local NationColors = require("../src/shared/NationColors")
local Palette = require("../src/shared/Palette")
local Rng = require("../src/shared/Rng")
local Types = require("../src/shared/Types")
local UnitSprites = require("../src/shared/UnitSprites")
local Png = require("./lib/Png")

local seconds = tonumber(process.args[1]) or 75
local seed = tonumber(process.args[2]) or 12345

local mapName = process.args[4] or Config.Match.DefaultMap
local map = MapFormat.fromModule((require :: any)("../maps/" .. mapName) :: MapFormat.MapModule)
local m = MatchSim.new(map, seed)
m.targetNations = tonumber(process.args[5]) or Config.Match.TargetNations
MatchSim.startPick(m)
local dt = 1 / Config.Sim.TickRate
while m.phase ~= "Play" do
	MatchSim.step(m, dt)
end
local declared, peaces = 0, 0
local resolutions: { string } = {}
local transfers, councils = 0, 0
for _ = 1, math.floor(seconds * Config.Sim.TickRate) do
	MatchSim.step(m, dt)
	for _, e in MatchSim.takeEvents(m) do
		if e.kind == "warDeclared" then
			declared += 1
		elseif e.kind == "peace" then
			peaces += 1
		elseif e.kind == "resolution" then
			table.insert(resolutions, string.format("%d:%02d %s", m.time // 60, math.floor(m.time % 60), e.resolution))
		elseif e.kind == "councilClosed" then
			councils += 1
		elseif e.kind == "transfer" then
			transfers += 1
		end
	end
	if m.phase == "Over" then
		break -- матч кончился (победа или лимит времени) — картинка на момент победы
	end
end

local result = m.result
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
local basalt = Palette.rgb("Basalt")
local riverId = Types.Terrain.River

local function colorOf(owner: number): number
	local n = m.nations[owner]
	return if n ~= nil then n.colorIndex else 0
end
local function ownerRgb(owner: number): Palette.Rgb
	local ci = colorOf(owner)
	return if ci >= 1 then NationColors.Colors[ci] else mist
end
local function ownerAt(i: number): number
	return Grid.getOwner(g, i)
end
local function isRiver(i: number): boolean
	return MapData.getTerrain(map, i) == riverId
end

-- Фронты с войсками и их линии по всей карте (тот же разбор, что у клиента).
type Front = { attack: Types.Attack, power: number, mix: { number } }
local fronts: { Front } = {}
local pairIndex: { [number]: number } = {}
for _, a in m.attacks do
	local power = Forces.total(a.forces)
	if a.target ~= 0 and power > 0 then
		table.insert(fronts, { attack = a, power = power, mix = Forces.composition(a.forces) })
		pairIndex[a.attacker * 65536 + a.target] = #fronts
	end
end
-- Юниты каждой стороны в прямоугольнике rect (как у клиента: он раскладывает только видимую часть линии):
-- войска фронта; напротив — встречный фронт или доля гарнизона.
type Side = { owner: number, slots: { BattleLayout.Slot }, front: number, attackerSide: boolean }
type Lines = { { BattleLayout.LinePoint } }
local against: { [number]: number } = {}
for _, f in fronts do
	against[f.attack.target] = (against[f.attack.target] or 0) + 1
end
local function buildSides(rect: { x0: number, y0: number, x1: number, y1: number }): ({ Side }, Lines, Lines)
	local lineA, lineD = BattleLayout.scan(ownerAt, isRiver, w, h, rect, 1, pairIndex, #fronts)
	local visibleFronts = 0
	for k = 1, #fronts do
		if #lineA[k] > 0 or #lineD[k] > 0 then
			visibleFronts += 1
		end
	end
	local cap = math.max(4, math.floor(Config.Render.Battle.MaxUnitsOnScreen / (math.max(1, visibleFronts) * 2)))
	local out: { Side } = {}
	for k, f in fronts do
		local a = f.attack
		local n = math.min(BattleLayout.unitsFor(f.power), cap)
		local slots = BattleLayout.place(lineA[k], n, f.mix, a.focus, ownerAt, a.attacker, w, h)
		table.insert(out, { owner = a.attacker, slots = slots, front = k, attackerSide = true })
		local target = m.nations[a.target]
		local hasCounter = pairIndex[a.target * 65536 + a.attacker] ~= nil
		if not hasCounter and target ~= nil and Forces.total(target.home) > 0 then
			local share = Forces.total(target.home) / math.max(1, against[a.target] or 1)
			local nd = math.min(BattleLayout.unitsFor(share), cap)
			local mix = Forces.composition(target.home)
			local def = BattleLayout.place(lineD[k], nd, mix, nil, ownerAt, a.target, w, h)
			table.insert(out, { owner = a.target, slots = def, front = k, attackerSide = false })
		end
	end
	return out, lineA, lineD
end
local sides, lineA, lineD = buildSides({ x0 = 0, y0 = 0, x1 = w - 1, y1 = h - 1 })

-- Сколько точек линии фронта k проходит по реке (клетка у реки, враг за ней).
local function riverPoints(k: number): number
	local count = 0
	for _, p in lineA[k] do
		local x, y = p.cell % w + p.dx, p.cell // w + p.dy
		if x >= 0 and y >= 0 and x < w and y < h and isRiver(y * w + x) then
			count += 1
		end
	end
	return count
end

-- Рисует область карты (клетки x0..x0+cw-1, y0..y0+ch-1) в картинку со сдвигом (ox, oy):
-- клетка = cell пикселей, пиксель спрайта = sprite пикселей. fx — кадр боя: снаряды, разрывы, воронки, дым.
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
	fx: boolean,
	sides: { Side },
	lineD: Lines
)
	local right, bottom = math.min(W, ox + cw * cell), math.min(H, oy + ch * cell)
	local function blend(px: number, py: number, pw: number, ph: number, c: Palette.Rgb, alpha: number)
		for yy = math.max(oy, py), math.min(bottom, py + ph) - 1 do
			for xx = math.max(ox, px), math.min(right, px + pw) - 1 do
				local o = (yy * W + xx) * 3
				local r0, g0, b0 = buffer.readu8(pixels, o), buffer.readu8(pixels, o + 1), buffer.readu8(pixels, o + 2)
				buffer.writeu8(pixels, o, math.round(r0 + (c.r - r0) * alpha))
				buffer.writeu8(pixels, o + 1, math.round(g0 + (c.g - g0) * alpha))
				buffer.writeu8(pixels, o + 2, math.round(b0 + (c.b - b0) * alpha))
			end
		end
	end
	local function rect(px: number, py: number, pw: number, ph: number, c: Palette.Rgb)
		blend(px, py, pw, ph, c, 1)
	end
	local function inRegion(x: number, y: number): boolean
		return x >= x0 and x < x0 + cw and y >= y0 and y < y0 + ch
	end
	-- Клетки (дробные) → пиксели.
	local function px(x: number, y: number): (number, number)
		return ox + math.round((x - x0) * cell), oy + math.round((y - y0) * cell)
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
		local cx, cy = c % w, c // w
		if inRegion(cx, cy) then
			local sx, sy = px(cx + 0.5, cy + 0.5)
			local half = citySize // 2
			rect(sx - half - 1, sy - half - 1, citySize + 2, citySize + 2, ink)
			rect(sx - half, sy - half, citySize, citySize, ownerRgb(Grid.getOwner(g, c)))
			rect(sx - 1, sy - 1, 2, 2, white)
		end
	end
	-- Здания и нефтяные поля (как у клиента, Render/BuildingLayer): значок над центром провинции.
	local iconScale = if cell >= 6 then 2 else 1
	local function icon(kind: string, at: number, owner: number)
		local x, y = at % w, at // w
		if not inRegion(x, y) then
			return
		end
		local sx, sy = px(x + 0.5, y)
		local size = BuildingSprites.Size * iconScale
		local left, top = sx - size // 2, sy - size
		local body = ownerRgb(owner)
		for _, p in BuildingSprites.Shapes[kind] do
			if not p.ink then
				rect(
					left + p.x * iconScale - 1,
					top + p.y * iconScale - 1,
					p.w * iconScale + 2,
					p.h * iconScale + 2,
					ink
				)
			end
		end
		for _, p in BuildingSprites.Shapes[kind] do
			rect(
				left + p.x * iconScale,
				top + p.y * iconScale,
				p.w * iconScale,
				p.h * iconScale,
				if p.ink then ink else body
			)
		end
	end
	for _, prov in m.provinces.list do
		local b = m.buildings.byCell[prov.center]
		if prov.oil and (b == nil or b.kind ~= "OilRig") then
			icon("OilField", prov.center, 0)
		end
	end
	for at, b in m.buildings.byCell do
		if b.kind == "City" then
			local x, y = at % w, at // w
			if inRegion(x, y) then
				local sx, sy = px(x + 0.5, y)
				for k = 1, b.level - 1 do
					rect(
						sx + 4 * iconScale + (k - 1) * 3 * iconScale,
						sy - 2 * iconScale,
						2 * iconScale,
						2 * iconScale,
						gold
					)
				end
			end
		else
			icon(b.kind, at, Grid.getOwner(g, at))
		end
	end
	local rng = Rng.new(seed + cell)
	local bcfg = Config.Render.Battle
	-- Кадр боя: последние CraterSec секунд обстрела. Каждая пушка стреляет раз в ~3 с: её прошлые снаряды
	-- оставили воронки (старые — без огня, но дымят), последние — ещё горят, один снаряд в полёте.
	type Point = { x: number, y: number }
	type Blast = { x: number, y: number, age: number }
	local blasts: { Blast } = {}
	local arcs: { { from: Point, to: Point, t: number } } = {}
	local flashes: { Point } = {}
	if fx then
		local shots = math.floor(bcfg.CraterSec / ((bcfg.ArtilleryFireMinSec + bcfg.ArtilleryFireMaxSec) / 2))
		for _, side in sides do
			local f = fronts[side.front]
			if f.attack.fighting then
				-- Цели: юниты другой стороны этой пары стран (свой фронт, встречный фронт или гарнизон).
				local enemyOwner = if side.owner == f.attack.attacker then f.attack.target else f.attack.attacker
				local enemies: { BattleLayout.Slot } = {}
				for _, other in sides do
					local of = fronts[other.front].attack
					local samePair = (of.attacker == side.owner and of.target == enemyOwner)
						or (of.attacker == enemyOwner and of.target == side.owner)
					if other.owner == enemyOwner and samePair then
						for _, sl in other.slots do
							table.insert(enemies, sl)
						end
					end
				end
				for _, sl in side.slots do
					if #enemies > 0 and inRegion(sl.x, sl.y) then
						if sl.kind == "Artillery" then
							for shot = 1, shots do
								local target = enemies[Rng.range(rng, 1, #enemies)]
								table.insert(blasts, {
									x = target.x + Rng.nextFloat(rng) * 3 - 1.5,
									y = target.y + Rng.nextFloat(rng) * 3 - 1.5,
									age = (shot - 1) / shots, -- 0 — только что, 1 — 20 с назад
								})
							end
							local target = enemies[Rng.range(rng, 1, #enemies)]
							table.insert(arcs, {
								from = { x = sl.x, y = sl.y - 0.4 },
								to = { x = target.x, y = target.y },
								t = 0.35 + Rng.nextFloat(rng) * 0.4,
							})
						elseif Rng.nextFloat(rng) < 0.4 then
							table.insert(flashes, { x = sl.x + sl.dx * 1.2, y = sl.y + sl.dy * 1.2 - 0.3 })
						end
					end
				end
			end
		end
		-- Воронки (старые снизу), дым над ними, свежие разрывы — огнём.
		table.sort(blasts, function(p: Blast, q: Blast): boolean
			return p.age > q.age
		end)
		for _, bl in blasts do
			local sx, sy = px(bl.x, bl.y)
			local size = math.round(cell * 1.6)
			blend(sx - size // 2, sy - size // 2, size, size, basalt, 0.85)
			local inner = math.round(cell * 0.8)
			blend(sx - inner // 2, sy - inner // 2, inner, inner, ink, 0.7)
		end
		for _, bl in blasts do
			local sx, sy = px(bl.x, bl.y)
			local thick = 1 - bl.age * 0.7
			for puff = 1, 4 do
				local ps = math.round(cell * (1 + puff * 0.5))
				local dy = math.round(cell * puff * 0.8)
				local dx = math.round(cell * (Rng.nextFloat(rng) - 0.5) * 1.2)
				blend(sx - ps // 2 + dx, sy - ps // 2 - dy, ps, ps, mist, (0.5 - puff * 0.09) * thick)
			end
		end
		for _, bl in blasts do
			if bl.age < 0.2 then
				local sx, sy = px(bl.x, bl.y)
				local s1, s2, s3 = math.round(cell * 2.8), math.round(cell * 1.7), math.round(cell * 0.7)
				blend(sx - s1 // 2, sy - s1 // 2, s1, s1, orange, 0.85)
				rect(sx - s2 // 2, sy - s2 // 2, s2, s2, red)
				rect(sx - s3 // 2, sy - s3 // 2, s3, s3, gold)
			end
		end
	end
	-- Юниты (как у клиента: якорь 0.5 × 0.75, смотрят на врага, без снабжения — красная обводка).
	for _, side in sides do
		local f = fronts[side.front]
		local unsupplied = side.attackerSide and not f.attack.supplied
		local body = ownerRgb(side.owner)
		local outline = if unsupplied then red else ink
		for _, sl in side.slots do
			if inRegion(sl.x, sl.y) then
				local sx, sy = px(sl.x, sl.y)
				local left = sx - UnitSprites.Width * sprite // 2
				local top = sy - math.round(UnitSprites.Height * sprite * 0.75)
				local flip = sl.dx < 0
				local shape = UnitSprites.Shapes[sl.kind]
				for _, p in shape do
					if not p.ink then
						local x = if flip then UnitSprites.Width - p.x - p.w else p.x
						rect(left + x * sprite - 1, top + p.y * sprite - 1, p.w * sprite + 2, p.h * sprite + 2, outline)
					end
				end
				for _, p in shape do
					local x = if flip then UnitSprites.Width - p.x - p.w else p.x
					rect(left + x * sprite, top + p.y * sprite, p.w * sprite, p.h * sprite, if p.ink then ink else body)
				end
			end
		end
	end
	-- Выстрелы пехоты и танков.
	for _, fl in flashes do
		local sx, sy = px(fl.x, fl.y)
		local s = math.max(2, math.round(cell * 0.5))
		rect(sx - s // 2, sy - s // 2, s, s, gold)
	end
	-- Снаряды в полёте: пунктир дуги и сам снаряд.
	for _, arc in arcs do
		local range = math.sqrt((arc.to.x - arc.from.x) ^ 2 + (arc.to.y - arc.from.y) ^ 2)
		local function at(t: number): (number, number)
			local x = arc.from.x + (arc.to.x - arc.from.x) * t
			local y = arc.from.y + (arc.to.y - arc.from.y) * t - Config.Render.Battle.ShellArc * range * 4 * t * (1 - t)
			return px(x, y)
		end
		for k = 1, 14 do
			local t = k / 15
			if t < arc.t then
				local sx, sy = at(t)
				blend(sx - 1, sy - 1, 3, 3, white, 0.35 + 0.4 * t / arc.t)
			end
		end
		local sx, sy = at(arc.t)
		local s = math.max(3, math.round(cell * 0.5))
		rect(sx - s // 2, sy - s // 2, s, s, ink)
		rect(sx - s // 2, sy - s // 2 - 1, s, 1, gold)
	end
	-- На всей карте — только отметки боёв на линиях.
	if not fx then
		for _, side in sides do
			local f = fronts[side.front]
			if f.attack.fighting and side.attackerSide then
				for _ = 1, 3 do
					local line = lineD[side.front]
					if #line > 0 then
						local p = line[Rng.range(rng, 1, #line)]
						local sx, sy = px(p.cell % w + 0.5, p.cell // w + 0.5)
						rect(sx - 2, sy - 2, 4, 4, if Rng.nextFloat(rng) < 0.5 then orange else red)
					end
				end
			end
		end
	end
end

-- Крупный план: бой через реку, если он есть, иначе самый большой бой.
local closeUp: number? = nil
local bestScore = -1
for k, f in fronts do
	if f.attack.fighting and #lineA[k] > 0 then
		local score = riverPoints(k) * 1e6 + f.power
		if score > bestScore then
			closeUp, bestScore = k, score
		end
	end
end

local SCALE = 2
local ZOOM = 8
local W = w * SCALE
local mapH = h * SCALE
local cropW = W // ZOOM
local cropH = if closeUp ~= nil then 44 else 0
local H = mapH + (if cropH > 0 then 4 + cropH * ZOOM else 0)
local pixels = buffer.create(W * H * 3)
renderRegion(pixels, W, H, 0, 0, 0, 0, w, h, SCALE, UnitSprites.scaleFor(SCALE), false, sides, lineD)
if closeUp ~= nil then
	-- Центр крупного плана — средняя точка линии фронта (на реке — её речной участок).
	local sx, sy, n = 0, 0, 0
	local river = riverPoints(closeUp) > 0
	for _, p in lineA[closeUp] do
		local x, y = p.cell % w, p.cell // w
		local nx, ny = x + p.dx, y + p.dy
		if not river or (nx >= 0 and ny >= 0 and nx < w and ny < h and isRiver(ny * w + nx)) then
			sx += x
			sy += y
			n += 1
		end
	end
	local cx, cy = sx // math.max(1, n), sy // math.max(1, n)
	local x0 = math.clamp(cx - cropW // 2, 0, w - cropW)
	local y0 = math.clamp(cy - cropH // 2, 0, h - cropH)
	for yy = mapH, mapH + 3 do
		for xx = 0, W - 1 do
			local o = (yy * W + xx) * 3
			buffer.writeu8(pixels, o, ink.r)
			buffer.writeu8(pixels, o + 1, ink.g)
			buffer.writeu8(pixels, o + 2, ink.b)
		end
	end
	-- Как у клиента на этом зуме: юниты раскладываются только по видимой части линии.
	local cropRect = { x0 = x0, y0 = y0, x1 = x0 + cropW - 1, y1 = y0 + cropH - 1 }
	local cropSides, _, cropLineD = buildSides(cropRect)
	local zoomScale = UnitSprites.scaleFor(ZOOM)
	renderRegion(pixels, W, H, 0, mapH + 4, x0, y0, cropW, cropH, ZOOM, zoomScale, true, cropSides, cropLineD)
end

-- HUD v1 поверх карты: мини-карта справа снизу (MinimapPaint, как у клиента) и график доли суши за матч
-- (как на экране результатов, лучшие Render.ResultsChartLines держав).
local function put(x: number, y: number, c: Palette.Rgb)
	if x >= 0 and y >= 0 and x < W and y < mapH then
		local o = (y * W + x) * 3
		buffer.writeu8(pixels, o, c.r)
		buffer.writeu8(pixels, o + 1, c.g)
		buffer.writeu8(pixels, o + 2, c.b)
	end
end
local function frame(x0: number, y0: number, fw: number, fh: number, c: Palette.Rgb)
	for x = x0 - 1, x0 + fw do
		put(x, y0 - 1, c)
		put(x, y0 + fh, c)
	end
	for y = y0 - 1, y0 + fh do
		put(x0 - 1, y, c)
		put(x0 + fw, y, c)
	end
end
-- Договоры (§8.1): союз — голубая линия между столицами, вассалитет — золотая, «Предатель» — красная рамка
-- вокруг столицы.
do
	local skyRgb = Palette.rgb("Sky")
	local function capitalPx(id: number): (number?, number?)
		local n = m.nations[id]
		local cap = if n ~= nil then n.capital else nil
		if cap == nil or not n.alive then
			return nil, nil
		end
		return (cap % w) * SCALE + 1, (cap // w) * SCALE + 1
	end
	local function line(a: number, b: number, c: Palette.Rgb, dashed: boolean?)
		local x0, y0 = capitalPx(a)
		local x1, y1 = capitalPx(b)
		if x0 == nil or y0 == nil or x1 == nil or y1 == nil then
			return
		end
		local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
		for k = 0, steps do
			local x = math.round(x0 + (x1 - x0) * k / steps)
			local y = math.round(y0 + (y1 - y0) * k / steps)
			if not dashed or (k // 4) % 2 == 0 then
				put(x, y, c)
				put(x + 1, y, c)
			end
		end
	end
	-- Торговые соглашения (§8.2) — пунктир цвета светлого тумана.
	for key in m.diplo.trade do
		local a = key // 65536
		line(a, key % 65536, mist, true)
	end
	for _, t in m.diplo.treaties do
		if t.kind == "alliance" then
			line(t.a, t.b, skyRgb)
		end
	end
	for vassal, v in m.diplo.vassals do
		line(vassal, v.overlord, gold)
	end
	for id, untilTime in m.diplo.traitors do
		local x, y = capitalPx(id)
		if x ~= nil and y ~= nil and untilTime > m.simTime then
			frame(x - 5, y - 5, 11, 11, red)
		end
	end
end
do
	local mw, mh = MinimapPaint.size(w, h, Config.Render.MinimapSide)
	local mini = MinimapPaint.paint(terrain, g.owner, w, h, mw, mh, function(owner: number)
		local ci = colorOf(owner)
		if ci < 1 then
			return nil, nil, nil
		end
		local c = NationColors.Colors[ci]
		return c.r, c.g, c.b
	end)
	local mx, my = W - mw - 12, mapH - mh - 12
	for y = 0, mh - 1 do
		for x = 0, mw - 1 do
			local o = (y * mw + x) * 4
			put(
				mx + x,
				my + y,
				{ r = buffer.readu8(mini, o), g = buffer.readu8(mini, o + 1), b = buffer.readu8(mini, o + 2) }
			)
		end
	end
	frame(mx, my, mw, mh, basalt)
end
if result ~= nil and #result.times >= 2 then
	local cw, ch = 240, 150
	local cx0, cy0 = 16, mapH - ch - 16
	for y = cy0, cy0 + ch - 1 do
		for x = cx0, cx0 + cw - 1 do
			put(x, y, ink)
		end
	end
	frame(cx0, cy0, cw, ch, gold)
	local times = result.times
	local t0, t1 = times[1], math.max(times[#times], times[1] + 1)
	local top = 10
	local shown: { number } = {}
	for place = 1, math.min(#result.places, Config.Render.ResultsChartLines) do
		local id = result.places[place]
		table.insert(shown, id)
		for _, v in result.shares[id] do
			top = math.max(top, v)
		end
	end
	for order = #shown, 1, -1 do
		local id = shown[order]
		local list = result.shares[id]
		local c = ownerRgb(id)
		local px0, py0 = nil :: number?, nil :: number?
		for k, v in list do
			local x = cx0 + 2 + math.round((times[k] - t0) / (t1 - t0) * (cw - 5))
			local y = cy0 + ch - 3 - math.round(v / top * (ch - 6))
			if px0 ~= nil and py0 ~= nil then
				-- Отрезок: шагаем по большей оси.
				local steps = math.max(math.abs(x - px0), math.abs(y - py0), 1)
				for s = 0, steps do
					local xx = math.round(px0 + (x - px0) * s / steps)
					local yy = math.round(py0 + (y - py0) * s / steps)
					put(xx, yy, c)
					put(xx, yy + 1, c)
				end
			end
			px0, py0 = x, y
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

print(
	string.format(
		"Партия %d с, сид %d → %s, фронтов с войсками %d, войн объявлено %d, миров %d, идёт войн %d",
		seconds,
		seed,
		out,
		#fronts,
		declared,
		peaces,
		#m.wars.list
	)
)
for _, n in m.nations do
	print(
		string.format(
			"  %d %-12s %-8s %-9s цвет %2d  суша %5.1f%%  люди %8.0f  гарнизон %6.0f  $%7.0f нефть %4.0f  здания %s%s",
			n.id,
			n.name,
			n.botLevel or "игрок",
			n.personality or "",
			n.colorIndex,
			Grid.cellsOf(g, n.id) / g.capturableCount * 100,
			n.people,
			Forces.total(n.home),
			n.money,
			n.oil,
			(function(): string
				local o = MatchSim.ownedOf(m, n.id)
				return string.format("з%d р%d в%d у%d г%d", o.factories, o.markets, o.rigs, o.forts, o.cityLevels)
			end)(),
			if n.alive then "" else "  (пала)"
		)
	)
end
do
	local parts: { string } = {}
	for _, t in m.diplo.treaties do
		table.insert(
			parts,
			string.format("%s %d–%d", if t.kind == "alliance" then "союз" else "пакт", t.a, t.b)
		)
	end
	for vassal, v in m.diplo.vassals do
		table.insert(parts, string.format("вассал %d→%d", vassal, v.overlord))
	end
	for id, untilTime in m.diplo.traitors do
		if untilTime > m.simTime then
			table.insert(parts, string.format("предатель %d", id))
		end
	end
	local hist: { string } = {}
	for _, e in m.diplo.history do
		table.insert(hist, string.format("%s %d/%d", e.kind, e.a, e.b))
	end
	local deals = 0
	for _ in m.diplo.trade do
		deals += 1
	end
	print("  ДОГОВОРЫ: " .. (if #parts > 0 then table.concat(parts, ", ") else "нет"))
	print(
		string.format(
			"  ТОРГОВЛЯ И СОВЕТ: соглашений %d, переводов %d, Советов %d, резолюции: %s",
			deals,
			transfers,
			councils,
			if #resolutions > 0 then table.concat(resolutions, ", ") else "нет"
		)
	)
	print("  ИСТОРИЯ: " .. table.concat(hist, ", "))
end
if result ~= nil then
	local winner = m.nations[result.winner]
	print(
		string.format(
			"  ИТОГ на %d:%02d: победа %s (%s); места: %s",
			math.floor(m.time / 60),
			math.floor(m.time % 60),
			if winner ~= nil then winner.name else "?",
			result.reason,
			table.concat(
				(function(): { string }
					local names: { string } = {}
					for place, id in result.places do
						table.insert(names, string.format("%d.%s", place, m.nations[id].name))
					end
					return names
				end)(),
				" "
			)
		)
	)
end
for k, f in fronts do
	local a = f.attack
	print(
		string.format(
			"  фронт %d → %d: сила %.0f, перевес %s%s%s%s%s",
			a.attacker,
			a.target,
			f.power,
			if a.ratio == math.huge then "∞" else string.format("%.2f", a.ratio),
			if a.fighting then ", бой" else "",
			if a.supplied then "" else ", без снабжения",
			if riverPoints(k) > 0 then string.format(", через реку (%d)", riverPoints(k)) else "",
			if k == closeUp then "  ← крупный план" else ""
		)
	)
end
