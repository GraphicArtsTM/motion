--!strict
--[[
	Grid — владельцы клеток во время матча (GDD §6.1, §12).

	- owner: u16 на клетку, 0 — ничья земля (или вода, которую захватить нельзя).
	- capturable: u8 на клетку, 1 — граница державы может сюда прийти (суша, не река).
	- Для каждой державы хранится счётчик клеток и множество «пограничных» клеток: своих клеток,
	  у которых хотя бы один сосед (из 4) чужой. Расширение и боты ходят только по ним — это
	  периметр, а не вся площадь, поэтому тик не зависит от размера державы.
	- Все смены владельца копятся в журнале изменений; сервер раз в тик забирает его и шлёт клиентам.
]]

local Config = require("./Config")
local MapData = require("./MapData")

type MapData = MapData.MapData

export type Grid = {
	width: number,
	height: number,
	size: number,
	owner: buffer,
	capturable: buffer,
	cellCount: { [number]: number },
	border: { [number]: { [number]: boolean } },
	borderOwner: buffer, -- u16: в чьём множестве границы сейчас клетка (0 — ни в чьём)
	changed: { number },
	changedFlag: buffer,
	capturableCount: number,
	-- Служебное для Expansion.captureEnclaves: тик, когда клетка оказалась в «открытом» (не окружённом) куске.
	openStamp: buffer,
	-- u8: 1 — в клетке город. Города не берёт ползущая граница, только армии (GDD §6.5).
	city: buffer,
	-- Счётчик изменений территории каждой державы (котлы пересчитываются, только если она менялась).
	version: { [number]: number },
	-- Служебное для заливок (Pockets): u32 метка на клетку и последнее выданное значение метки.
	stamp: buffer,
	stampValue: number,
}

local Grid = {}

function Grid.new(map: MapData): Grid
	local size = map.width * map.height
	local capturable = buffer.create(size)
	local count = 0
	for i = 0, size - 1 do
		local stats = Config.Terrain[buffer.readu8(map.terrain, i)]
		if stats ~= nil and stats.borderPassable then
			buffer.writeu8(capturable, i, 1)
			count += 1
		end
	end
	return {
		width = map.width,
		height = map.height,
		size = size,
		owner = buffer.create(size * 2),
		capturable = capturable,
		cellCount = {},
		border = {},
		borderOwner = buffer.create(size * 2),
		changed = {},
		changedFlag = buffer.create(size),
		capturableCount = count,
		openStamp = buffer.create(size * 4),
		city = buffer.create(size),
		version = {},
		stamp = buffer.create(size * 4),
		stampValue = 0,
	}
end

function Grid.getOwner(g: Grid, i: number): number
	return buffer.readu16(g.owner, i * 2)
end

function Grid.isCapturable(g: Grid, i: number): boolean
	return buffer.readu8(g.capturable, i) == 1
end

function Grid.isCity(g: Grid, i: number): boolean
	return buffer.readu8(g.city, i) == 1
end

function Grid.setCity(g: Grid, i: number, isCity: boolean)
	buffer.writeu8(g.city, i, if isCity then 1 else 0)
end

function Grid.cellsOf(g: Grid, nation: number): number
	return g.cellCount[nation] or 0
end

-- Вызывает fn(j) для 4 соседей клетки i в пределах карты.
function Grid.forNeighbours(g: Grid, i: number, fn: (j: number) -> ())
	local w = g.width
	local x = i % w
	if x > 0 then
		fn(i - 1)
	end
	if x < w - 1 then
		fn(i + 1)
	end
	if i >= w then
		fn(i - w)
	end
	if i + w < g.size then
		fn(i + w)
	end
end

-- Граница: своя клетка, у которой есть сосед с другим владельцем или край карты.
function Grid.isBorderCell(g: Grid, i: number): boolean
	local o = buffer.readu16(g.owner, i * 2)
	if o == 0 then
		return false
	end
	local w = g.width
	local x = i % w
	if x == 0 or x == w - 1 or i < w or i + w >= g.size then
		return true
	end
	return buffer.readu16(g.owner, (i - 1) * 2) ~= o
		or buffer.readu16(g.owner, (i + 1) * 2) ~= o
		or buffer.readu16(g.owner, (i - w) * 2) ~= o
		or buffer.readu16(g.owner, (i + w) * 2) ~= o
end

local function refreshBorder(g: Grid, i: number)
	local wasIn = buffer.readu16(g.borderOwner, i * 2)
	local o = buffer.readu16(g.owner, i * 2)
	local nowIn = if Grid.isBorderCell(g, i) then o else 0
	if wasIn == nowIn then
		return
	end
	if wasIn ~= 0 then
		local set = g.border[wasIn]
		if set then
			set[i] = nil
		end
	end
	if nowIn ~= 0 then
		local set = g.border[nowIn]
		if set == nil then
			set = {}
			g.border[nowIn] = set
		end
		set[i] = true
	end
	buffer.writeu16(g.borderOwner, i * 2, nowIn)
end

-- Меняет владельца клетки: счётчики, границы, журнал изменений.
function Grid.setOwner(g: Grid, i: number, owner: number)
	local old = buffer.readu16(g.owner, i * 2)
	if old == owner then
		return
	end
	buffer.writeu16(g.owner, i * 2, owner)
	if old ~= 0 then
		g.cellCount[old] = (g.cellCount[old] or 1) - 1
		g.version[old] = (g.version[old] or 0) + 1
	end
	if owner ~= 0 then
		g.cellCount[owner] = (g.cellCount[owner] or 0) + 1
		g.version[owner] = (g.version[owner] or 0) + 1
	end
	refreshBorder(g, i)
	Grid.forNeighbours(g, i, function(j)
		refreshBorder(g, j)
	end)
	if buffer.readu8(g.changedFlag, i) == 0 then
		buffer.writeu8(g.changedFlag, i, 1)
		table.insert(g.changed, i)
	end
end

-- Новая метка для заливки по g.stamp (клетки с другой меткой считаются непосещёнными).
function Grid.newStamp(g: Grid): number
	g.stampValue += 1
	if g.stampValue >= 4294967295 then
		buffer.fill(g.stamp, 0, 0)
		g.stampValue = 1
	end
	return g.stampValue
end

-- Забирает изменённые с прошлого раза клетки (по возрастанию индекса) и очищает журнал.
function Grid.takeChanges(g: Grid): { number }
	local out = g.changed
	g.changed = {}
	for _, i in out do
		buffer.writeu8(g.changedFlag, i, 0)
	end
	table.sort(out)
	return out
end

-- Пограничные клетки державы (множество; не изменять).
function Grid.borderCells(g: Grid, nation: number): { [number]: boolean }
	return g.border[nation] or {}
end

-- Соседи державы по суше: владелец → сколько его захватываемых клеток касается нашей границы.
-- 0 в ответе — рядом есть ничья земля.
function Grid.adjacentOwners(g: Grid, nation: number): { [number]: number }
	local out: { [number]: number } = {}
	local seen: { [number]: boolean } = {}
	for i in Grid.borderCells(g, nation) do
		Grid.forNeighbours(g, i, function(j)
			if not seen[j] and buffer.readu8(g.capturable, j) == 1 then
				local o = buffer.readu16(g.owner, j * 2)
				if o ~= nation then
					seen[j] = true
					out[o] = (out[o] or 0) + 1
				end
			end
		end)
	end
	return out
end

return table.freeze(Grid)
