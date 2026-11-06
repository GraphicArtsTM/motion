--!strict
--!native
--[[
	WarFx — расчёты для зрелищной войны (GDD §15б). Чистый модуль: клиент рисует, тест проверяет.
	- borderSamples: клетки державы a, соседние с державой b, в прямоугольнике (общая граница — для вспышки при
	  объявлении войны и начале наступления). Не больше max, равномерно по найденным.
	- frontArrows: стрелки наступления — куски линии фронта нападающего против цели, для каждого точка (центр куска)
	  и направление «от нападающего к цели».
	- captures: клетки, которые только что перешли от одной державы к другой (вспышка захвата); помнит владельцев.
]]

local WarFx = {}

export type Arrow = { x: number, y: number, dx: number, dy: number, cells: number }

local DX = { -1, 1, 0, 0 }
local DY = { 0, 0, -1, 1 }

-- Обходит клетки a у границы с b (шаг stride) и зовёт visit(i, x, y, dx, dy) — (dx, dy) — куда соседняя клетка b.
local function eachBorder(
	ownerAt: (number) -> number,
	w: number,
	h: number,
	a: number,
	b: number,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	stride: number,
	visit: (i: number, x: number, y: number, dx: number, dy: number) -> ()
)
	x0, y0 = math.max(0, x0), math.max(0, y0)
	x1, y1 = math.min(w - 1, x1), math.min(h - 1, y1)
	local step = math.max(1, math.floor(stride))
	for y = y0, y1, step do
		for x = x0, x1, step do
			local i = y * w + x
			if ownerAt(i) == a then
				local sx, sy = 0, 0
				for k = 1, 4 do
					local nx, ny = x + DX[k], y + DY[k]
					if nx >= 0 and ny >= 0 and nx < w and ny < h and ownerAt(ny * w + nx) == b then
						sx += DX[k]
						sy += DY[k]
					end
				end
				-- Соседи b на противоположных сторонах (узкий перешеек) гасят направление — клетка всё равно на границе.
				local touches = sx ~= 0 or sy ~= 0
				if not touches then
					for k = 1, 4 do
						local nx, ny = x + DX[k], y + DY[k]
						if nx >= 0 and ny >= 0 and nx < w and ny < h and ownerAt(ny * w + nx) == b then
							touches = true
							break
						end
					end
				end
				if touches then
					visit(i, x, y, sx, sy)
				end
			end
		end
	end
end

-- Общая граница: клетки a, соседние с b, не больше max (равномерно по найденным).
function WarFx.borderSamples(
	ownerAt: (number) -> number,
	w: number,
	h: number,
	a: number,
	b: number,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	stride: number,
	max: number
): { number }
	local all: { number } = {}
	eachBorder(ownerAt, w, h, a, b, x0, y0, x1, y1, stride, function(i: number)
		table.insert(all, i)
	end)
	if #all <= max then
		return all
	end
	local out: { number } = {}
	for k = 1, max do
		table.insert(out, all[math.floor((k - 0.5) * #all / max) + 1])
	end
	return out
end

-- Стрелки наступления attacker → target: граница делится по длине на куски (не меньше minCells клеток выборки,
-- не больше maxArrows кусков); у каждого — центр и среднее направление к цели (единичный вектор).
function WarFx.frontArrows(
	ownerAt: (number) -> number,
	w: number,
	h: number,
	attacker: number,
	target: number,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	stride: number,
	maxArrows: number,
	minCells: number
): { Arrow }
	type Cell = { x: number, y: number, dx: number, dy: number }
	local cells: { Cell } = {}
	local sdx, sdy = 0, 0
	eachBorder(
		ownerAt,
		w,
		h,
		attacker,
		target,
		x0,
		y0,
		x1,
		y1,
		stride,
		function(_i: number, x: number, y: number, dx: number, dy: number)
			table.insert(cells, { x = x + 0.5, y = y + 0.5, dx = dx, dy = dy })
			sdx += dx
			sdy += dy
		end
	)
	if #cells < minCells then
		return {}
	end
	-- Вдоль линии — перпендикуляр к общему направлению; по нему режем на куски.
	local len = math.sqrt(sdx * sdx + sdy * sdy)
	local tx, ty = if len > 0 then -sdy / len else 1, if len > 0 then sdx / len else 0
	table.sort(cells, function(p: Cell, q: Cell): boolean
		return p.x * tx + p.y * ty < q.x * tx + q.y * ty
	end)
	local parts = math.clamp(#cells // minCells, 1, maxArrows)
	local out: { Arrow } = {}
	for k = 1, parts do
		local from = math.floor((k - 1) * #cells / parts) + 1
		local to = math.floor(k * #cells / parts)
		local cx, cy, ax, ay = 0, 0, 0, 0
		for j = from, to do
			local c = cells[j]
			cx += c.x
			cy += c.y
			ax += c.dx
			ay += c.dy
		end
		local n = to - from + 1
		local alen = math.sqrt(ax * ax + ay * ay)
		if alen <= 0 then
			ax, ay, alen = sdx, sdy, math.max(len, 1e-6)
		end
		if alen > 0 and n > 0 then
			table.insert(out, { x = cx / n, y = cy / n, dx = ax / alen, dy = ay / alen, cells = n })
		end
	end
	return out
end

-- Владельцы клеток, которые помнит клиент для вспышек захвата (u8 на клетку).
function WarFx.newMemory(size: number): buffer
	return buffer.create(size)
end

-- Запомнить всех владельцев (снимок).
function WarFx.remember(memory: buffer, ownerAt: (number) -> number)
	for i = 0, buffer.len(memory) - 1 do
		buffer.writeu8(memory, i, math.clamp(ownerAt(i), 0, 255))
	end
end

-- Изменённые клетки → те, что перешли от одной державы к другой (ничья земля и вода не считаются).
function WarFx.captures(memory: buffer, cells: { number }, ownerAt: (number) -> number): { number }
	local out: { number } = {}
	local size = buffer.len(memory)
	for _, i in cells do
		if i >= 0 and i < size then
			local old = buffer.readu8(memory, i)
			local new = math.clamp(ownerAt(i), 0, 255)
			if old ~= 0 and new ~= 0 and old ~= new then
				table.insert(out, i)
			end
			buffer.writeu8(memory, i, new)
		end
	end
	return out
end

-- Яркость стрелки 0..1: побеждающий фронт и «Первый удар» — ярче.
function WarFx.arrowStrength(ratio: number, fullSpeedRatio: number, opening: boolean): number
	local r = if ratio == math.huge then 1 else math.clamp((ratio - 1) / math.max(fullSpeedRatio - 1, 1e-6), 0, 1)
	return math.clamp(0.35 + 0.65 * r + (if opening then 0.3 else 0), 0, 1)
end

return table.freeze(WarFx)
