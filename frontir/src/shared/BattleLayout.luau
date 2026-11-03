--!strict
--[[
	BattleLayout — где стоят юниты в бою на линии фронта (GDD §6.7б). Общий для клиента (Render/FrontLayer)
	и превью партии (tools/match_preview), поэтому чистые функции без Roblox API.

	scan — один проход по прямоугольнику клеток: для каждой пары «атакующий → цель» собирает линию фронта
	с обеих сторон: свои клетки у границы и единичный шаг к врагу (4 направления). Линия видна и через реку:
	клетка у реки, за которой (не дальше Combat.RiverMaxWidth клеток) — враг.

	place — раскладывает n юнитов стороны вдоль её линии:
	- у точки главного удара (focus) юнитов больше (вес — Expansion.focusWeight, как у самого фронта);
	- типы перемешаны вдоль линии в пропорциях состава (mix);
	- пехота и ПВО стоят в половине ничейной полосы от границы, танки — чуть ближе к врагу, артиллерия —
	  в тылу (Render.Battle.ArtilleryBack); отход в тыл идёт только по своей земле.
	Координаты — в клетках (дробные, центр клетки = x + 0.5).
]]

local Config = require("./Config")
local Expansion = require("./Expansion")
local Types = require("./Types")

export type LinePoint = { cell: number, dx: number, dy: number } -- своя клетка у фронта и шаг к врагу
export type Slot = { x: number, y: number, kind: string, dx: number, dy: number, anchor: number }

local BattleLayout = {}

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local GOLDEN = 0.6180339887498949

-- Владелец клетки за рекой в направлении (dx, dy) от клетки (x, y) или 0.
local function acrossRiver(
	ownerAt: (i: number) -> number,
	isRiver: (i: number) -> boolean,
	w: number,
	h: number,
	x: number,
	y: number,
	dx: number,
	dy: number
): number
	local cx, cy = x + dx, y + dy
	for _ = 1, Config.Combat.RiverMaxWidth do
		if cx < 0 or cy < 0 or cx >= w or cy >= h or not isRiver(cy * w + cx) then
			break
		end
		cx += dx
		cy += dy
	end
	if cx < 0 or cy < 0 or cx >= w or cy >= h or (cx == x + dx and cy == y + dy) then
		return 0
	end
	local i = cy * w + cx
	return if isRiver(i) then 0 else ownerAt(i)
end

-- Линии фронтов в прямоугольнике [x0..x1]×[y0..y1] с шагом stride. pairIndex[attacker * 65536 + target] = k.
-- Возвращает для каждого k линию атакующего (его клетки, шаг к цели) и линию цели (её клетки, шаг к атакующему).
function BattleLayout.scan(
	ownerAt: (i: number) -> number,
	isRiver: (i: number) -> boolean,
	w: number,
	h: number,
	rect: { x0: number, y0: number, x1: number, y1: number },
	stride: number,
	pairIndex: { [number]: number },
	count: number
): ({ { LinePoint } }, { { LinePoint } })
	local attackers: { { LinePoint } } = {}
	local defenders: { { LinePoint } } = {}
	local seenA: { { [number]: boolean } } = {}
	local seenD: { { [number]: boolean } } = {}
	for k = 1, count do
		attackers[k], defenders[k], seenA[k], seenD[k] = {}, {}, {}, {}
	end
	for y = rect.y0, rect.y1, stride do
		for x = rect.x0, rect.x1, stride do
			local i = y * w + x
			local o = ownerAt(i)
			if o ~= 0 then
				for _, d in DIRS do
					local nx, ny = x + d[1], y + d[2]
					if nx >= 0 and ny >= 0 and nx < w and ny < h then
						local j = ny * w + nx
						local p = ownerAt(j)
						if p == 0 and isRiver(j) then
							p = acrossRiver(ownerAt, isRiver, w, h, x, y, d[1], d[2])
						end
						if p ~= o and p ~= 0 then
							local k = pairIndex[o * 65536 + p]
							if k ~= nil and not seenA[k][i] then
								seenA[k][i] = true
								table.insert(attackers[k], { cell = i, dx = d[1], dy = d[2] })
							end
							local back = pairIndex[p * 65536 + o]
							if back ~= nil and not seenD[back][i] then
								seenD[back][i] = true
								table.insert(defenders[back], { cell = i, dx = d[1], dy = d[2] })
							end
						end
					end
				end
			end
		end
	end
	return attackers, defenders
end

-- Сколько юнитов рисовать для силы power (не больше предела на фронт).
function BattleLayout.unitsFor(power: number): number
	local cfg = Config.Render.Battle
	if power <= 0 then
		return 0
	end
	return math.clamp(math.ceil(power / cfg.StrengthPerUnit), 1, cfg.MaxUnitsPerFront)
end

-- Тип юнита k по составу mix: доли перемешаны вдоль линии (последовательность золотого сечения),
-- поэтому рядом стоят разные типы, а в сумме пропорции как у состава.
function BattleLayout.kindAt(mix: { number }, k: number): string
	local total = 0
	for _, share in mix do
		total += share
	end
	if total <= 0 then
		return Types.LandUnits[1]
	end
	local u = ((k * GOLDEN) % 1) * total
	local acc = 0
	for kind, share in mix do
		acc += share
		if u < acc then
			return Types.LandUnits[kind]
		end
	end
	return Types.LandUnits[1]
end

-- Насколько клеток от границы в тыл стоит юнит этого типа.
function BattleLayout.backFor(kind: string): number
	local cfg = Config.Render.Battle
	-- Пехота стоит в половине ничейной полосы от границы, сторона против стороны — через всю полосу.
	local front = cfg.NoMansLand / 2
	if kind == "Artillery" then
		return cfg.ArtilleryBack
	elseif kind == "Tanks" then
		return math.max(0, front - 0.5)
	end
	return front
end

-- Раскладка n юнитов стороны owner вдоль линии line (см. шапку).
function BattleLayout.place(
	line: { LinePoint },
	n: number,
	mix: { number },
	focus: number?,
	ownerAt: (i: number) -> number,
	owner: number,
	w: number,
	h: number
): { Slot }
	local out: { Slot } = {}
	if #line == 0 or n <= 0 then
		return out
	end
	-- Веса точек линии: у главного удара больше.
	local weights: { number } = table.create(#line)
	local total = 0
	for k, p in line do
		local wgt = 1
		if focus ~= nil then
			local px, py = p.cell % w, p.cell // w
			wgt = Expansion.focusWeight(p.dx, p.dy, focus % w - px, focus // w - py)
		end
		weights[k] = wgt
		total += wgt
	end
	-- Систематическая выборка по накопленному весу: детерминированно и равномерно.
	local idx, acc = 1, weights[1]
	for s = 1, n do
		local target = (s - 0.5) / n * total
		while acc < target and idx < #line do
			idx += 1
			acc += weights[idx]
		end
		local p = line[idx]
		local kind = BattleLayout.kindAt(mix, s)
		local back = BattleLayout.backFor(kind)
		-- Отходим в тыл по своей земле, но не дальше back клеток.
		local px, py = p.cell % w, p.cell // w
		local steps = 0
		while steps < math.ceil(back) do
			local nx, ny = px - p.dx * (steps + 1), py - p.dy * (steps + 1)
			if nx < 0 or ny < 0 or nx >= w or ny >= h or ownerAt(ny * w + nx) ~= owner then
				break
			end
			steps += 1
		end
		local dist = math.min(back, steps)
		-- Соседние юниты на одной клетке линии чуть разводим поперёк фронта.
		local side = ((s * GOLDEN) % 1 - 0.5) * 0.8
		table.insert(out, {
			x = px + 0.5 - p.dx * dist + p.dy * side,
			y = py + 0.5 - p.dy * dist + p.dx * side,
			kind = kind,
			dx = p.dx,
			dy = p.dy,
			anchor = p.cell,
		})
	end
	return out
end

return table.freeze(BattleLayout)
