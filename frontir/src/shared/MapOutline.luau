--!strict
--[[
	MapOutline — контуры на карте для подсветок (GDD §15х ч.8), без Roblox API.
	- stride(w, h, maxScan) — шаг выборки, чтобы прямоугольник w × h смотрелся не больше чем за maxScan клеток;
	- outline(ownerAt, mapW, mapH, owner, x0, y0, x1, y1, stride, max) — клетки owner на краю его земли
	  (сосед из 4 — чужой, ничей, вода или край карты) в прямоугольнике, равномерно не больше max;
	- component(ownerAt, mapW, mapH, start, maxCells) — связный кусок земли владельца клетки start (4 соседа):
	  клетки (не больше maxCells), клетки края и центр (среднее по клеткам).
	- spread(list, max) — равномерно не больше max элементов списка (порядок сохраняется).
]]

local MapOutline = {}

export type Component = {
	cells: { number },
	edge: { number },
	cx: number, -- центр (клетки, с половиной)
	cy: number,
	full: boolean, -- кусок найден целиком (не упёрлись в maxCells)
}

local DX = { -1, 1, 0, 0 }
local DY = { 0, 0, -1, 1 }

function MapOutline.stride(w: number, h: number, maxScan: number): number
	local area = math.max(1, w) * math.max(1, h)
	return math.max(1, math.ceil(math.sqrt(area / math.max(1, maxScan))))
end

function MapOutline.spread<T>(list: { T }, max: number): { T }
	if #list <= max then
		return list
	end
	local out: { T } = {}
	for k = 1, max do
		table.insert(out, list[math.floor((k - 0.5) * #list / max) + 1])
	end
	return out
end

local function isEdge(ownerAt: (number) -> number, w: number, h: number, x: number, y: number, owner: number): boolean
	for k = 1, 4 do
		local nx, ny = x + DX[k], y + DY[k]
		if nx < 0 or ny < 0 or nx >= w or ny >= h or ownerAt(ny * w + nx) ~= owner then
			return true
		end
	end
	return false
end

function MapOutline.outline(
	ownerAt: (number) -> number,
	w: number,
	h: number,
	owner: number,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	stride: number,
	max: number
): { number }
	local out: { number } = {}
	if owner == 0 then
		return out
	end
	x0, y0 = math.max(0, math.floor(x0)), math.max(0, math.floor(y0))
	x1, y1 = math.min(w - 1, math.floor(x1)), math.min(h - 1, math.floor(y1))
	local step = math.max(1, math.floor(stride))
	for y = y0, y1, step do
		for x = x0, x1, step do
			local i = y * w + x
			if ownerAt(i) == owner and isEdge(ownerAt, w, h, x, y, owner) then
				table.insert(out, i)
			end
		end
	end
	return MapOutline.spread(out, max)
end

function MapOutline.component(
	ownerAt: (number) -> number,
	w: number,
	h: number,
	start: number,
	maxCells: number
): Component
	local owner = ownerAt(start)
	local cells: { number } = {}
	local edge: { number } = {}
	if owner == 0 or start < 0 or start >= w * h then
		return { cells = cells, edge = edge, cx = start % w + 0.5, cy = start // w + 0.5, full = true }
	end
	local seen: { [number]: boolean } = { [start] = true }
	cells[1] = start
	local head = 1
	local sx, sy = 0, 0
	local full = true
	while head <= #cells do
		local i = cells[head]
		head += 1
		local x, y = i % w, i // w
		sx += x
		sy += y
		if isEdge(ownerAt, w, h, x, y, owner) then
			table.insert(edge, i)
		end
		for k = 1, 4 do
			local nx, ny = x + DX[k], y + DY[k]
			if nx >= 0 and ny >= 0 and nx < w and ny < h then
				local j = ny * w + nx
				if not seen[j] and ownerAt(j) == owner then
					seen[j] = true
					if #cells >= maxCells then
						full = false
					else
						table.insert(cells, j)
					end
				end
			end
		end
	end
	local n = math.max(1, #cells)
	return { cells = cells, edge = edge, cx = sx / n + 0.5, cy = sy / n + 0.5, full = full }
end

return table.freeze(MapOutline)
