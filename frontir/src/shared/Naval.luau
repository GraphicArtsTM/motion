--!strict
--[[
	Naval — море и морские пути (GDD §6.12, этап 7б-1). Чистый модуль без Roblox API.

	Море (SeaMap) считается из карты один раз, одинаково на сервере и клиенте:
	- sea: u16 на клетку — номер моря (связная вода не меньше Naval.MinSeaCells; озёра меньше — 0);
	- docks: провинция → клетка моря у её берега, ближайшая к центру провинции (причал порта);
	  у провинции без выхода к морю причала нет — порт там не построить.
	Путь корабля ищется в два шага (поиск сразу по клеткам на «Европе» занимал до 280 мс):
	1. грубо — A* по узлам «связный кусок моря внутри блока NavBlock×NavBlock» (узлы соседних блоков связаны,
	   если их клетки касаются стороной);
	2. точно — A* по клеткам моря (8 направлений, по диагонали — только если обе соседние по стороне клетки тоже
	   море), но только внутри коридора из узлов грубого пути.
	Путь выходит чуть длиннее кратчайшего — для кораблей это нормально.
]]

local Config = require("./Config")
local Heap = require("./Heap")
local MapData = require("./MapData")
local Provinces = require("./Provinces")
local Types = require("./Types")

type MapData = MapData.MapData

export type SeaMap = {
	width: number,
	height: number,
	size: number,
	sea: buffer, -- u16: номер моря, 0 — суша или маленькое озеро
	land: buffer, -- u32: номер массива суши (связная суша по стороне; 0 — вода) — «другой берег» (§15д)
	docks: { [number]: number }, -- провинция → клетка-причал
	-- Навигация: узел клетки (u32, 0 — нет), центры узлов и их соседи.
	node: buffer,
	nodeX: { number },
	nodeY: { number },
	links: { { number } },
	-- Рабочие буферы точного поиска (создаются при первом поиске — клиенту не нужны).
	stamp: buffer?,
	cost: buffer?,
	parent: buffer?,
	stampValue: number,
	lastNodes: number, -- сколько клеток раскрыл последний точный поиск (для замеров)
	reach: { [number]: { [number]: boolean } }, -- причал → берег (суша), до которого по воде не дальше SeaSupplyRange
}

local Naval = {}

local WATER = Types.Terrain.Water
local ORTHO, DIAG = 5, 7

-- Заливка по стороне от start: клетки, для которых accept(j, x, y) истинно; mark(j) помечает клетку.
-- Клетки куска — в queue.
local function flood(
	w: number,
	size: number,
	start: number,
	queue: { number },
	accept: (j: number, x: number, y: number) -> boolean,
	mark: (j: number) -> ()
)
	table.clear(queue)
	queue[1] = start
	mark(start)
	local head = 1
	while head <= #queue do
		local i = queue[head]
		head += 1
		local x, y = i % w, i // w
		if x > 0 and accept(i - 1, x - 1, y) then
			mark(i - 1)
			table.insert(queue, i - 1)
		end
		if x < w - 1 and accept(i + 1, x + 1, y) then
			mark(i + 1)
			table.insert(queue, i + 1)
		end
		if i >= w and accept(i - w, x, y - 1) then
			mark(i - w)
			table.insert(queue, i - w)
		end
		if i + w < size and accept(i + w, x, y + 1) then
			mark(i + w)
			table.insert(queue, i + w)
		end
	end
end

function Naval.buildSea(map: MapData, provinces: Provinces.ProvinceSet): SeaMap
	local w, h = map.width, map.height
	local size = w * h
	local terrain = map.terrain
	local sea = buffer.create(size * 2)
	local visited = buffer.create(size)
	local queue: { number } = {}
	local nextSea = 0

	-- 1. Моря: связная вода не меньше MinSeaCells.
	local function waterAccept(j: number, _x: number, _y: number): boolean
		return buffer.readu8(visited, j) == 0 and buffer.readu8(terrain, j) == WATER
	end
	local function markVisited(j: number)
		buffer.writeu8(visited, j, 1)
	end
	for start = 0, size - 1 do
		if buffer.readu8(visited, start) == 0 and buffer.readu8(terrain, start) == WATER then
			flood(w, size, start, queue, waterAccept, markVisited)
			if #queue >= Config.Naval.MinSeaCells then
				nextSea += 1
				for _, i in queue do
					buffer.writeu16(sea, i * 2, nextSea)
				end
			end
		end
	end

	-- 1б. Массивы суши (§15д): цель на другом массиве — десант на корабле.
	local land = buffer.create(size * 4)
	local nextLand = 0
	local function landAccept(j: number, _x: number, _y: number): boolean
		return buffer.readu32(land, j * 4) == 0 and buffer.readu8(terrain, j) ~= WATER
	end
	local function markLand(j: number)
		buffer.writeu32(land, j * 4, nextLand)
	end
	for start = 0, size - 1 do
		if buffer.readu32(land, start * 4) == 0 and buffer.readu8(terrain, start) ~= WATER then
			nextLand += 1
			flood(w, size, start, queue, landAccept, markLand)
		end
	end

	-- 2. Причалы: клетка моря у суши провинции, ближайшая к её центру.
	local docks: { [number]: number } = {}
	for _, p in provinces.list do
		local cx, cy = p.center % w, p.center // w
		local best, bestD = -1, math.huge
		for _, i in p.cells do
			local x = i % w
			for k = 1, 4 do
				local j = if k == 1
					then (if x > 0 then i - 1 else -1)
					elseif k == 2 then (if x < w - 1 then i + 1 else -1)
					elseif k == 3 then i - w
					else i + w
				if j >= 0 and j < size and buffer.readu16(sea, j * 2) ~= 0 then
					local dx, dy = j % w - cx, j // w - cy
					local d = dx * dx + dy * dy
					if d < bestD or (d == bestD and j < best) then
						best, bestD = j, d
					end
				end
			end
		end
		if best >= 0 then
			docks[p.id] = best
		end
	end

	-- 3. Узлы навигации: связные куски моря внутри блоков.
	local block = Config.Naval.NavBlock
	local node = buffer.create(size * 4)
	local nodeX, nodeY = {}, {}
	local bx0, by0, bx1, by1, seaId, current = 0, 0, 0, 0, 0, 0
	local blockQueue: { number } = {}
	local function nodeAccept(j: number, x: number, y: number): boolean
		return x >= bx0
			and x <= bx1
			and y >= by0
			and y <= by1
			and buffer.readu16(sea, j * 2) == seaId
			and buffer.readu32(node, j * 4) == 0
	end
	local function markNode(j: number)
		buffer.writeu32(node, j * 4, current)
	end
	for by = 0, h - 1, block do
		for bx = 0, w - 1, block do
			bx0, by0, bx1, by1 = bx, by, math.min(w, bx + block) - 1, math.min(h, by + block) - 1
			for y = by0, by1 do
				for x = bx0, bx1 do
					local start = y * w + x
					seaId = buffer.readu16(sea, start * 2)
					if seaId ~= 0 and buffer.readu32(node, start * 4) == 0 then
						current = #nodeX + 1
						-- Своя маленькая очередь: очистка большой (после морей) стоила бы проход по ней каждый раз.
						flood(w, size, start, blockQueue, nodeAccept, markNode)
						local sx, sy = 0, 0
						for _, i in blockQueue do
							sx += i % w
							sy += i // w
						end
						nodeX[current] = sx / #blockQueue
						nodeY[current] = sy / #blockQueue
					end
				end
			end
		end
	end
	local count = #nodeX
	local links: { { number } } = table.create(count)
	for n = 1, count do
		links[n] = {}
	end
	local linked: { [number]: boolean } = {}
	for i = 0, size - 1 do
		local a = buffer.readu32(node, i * 4)
		if a ~= 0 then
			for k = 1, 2 do
				local j = if k == 1 then (if i % w < w - 1 then i + 1 else -1) else i + w
				if j >= 0 and j < size then
					local b = buffer.readu32(node, j * 4)
					if b ~= 0 and b ~= a then
						local key = math.min(a, b) * (count + 1) + math.max(a, b)
						if not linked[key] then
							linked[key] = true
							table.insert(links[a], b)
							table.insert(links[b], a)
						end
					end
				end
			end
		end
	end

	return {
		width = w,
		height = h,
		size = size,
		sea = sea,
		land = land,
		docks = docks,
		node = node,
		nodeX = nodeX,
		nodeY = nodeY,
		links = links,
		stamp = nil,
		cost = nil,
		parent = nil,
		stampValue = 0,
		lastNodes = 0,
		reach = {},
	}
end

-- Номер моря клетки (0 — не море).
function Naval.seaAt(s: SeaMap, i: number): number
	if i < 0 or i >= s.size then
		return 0
	end
	return buffer.readu16(s.sea, i * 2)
end

-- Номер массива суши клетки (0 — вода).
function Naval.landAt(s: SeaMap, i: number): number
	if i < 0 or i >= s.size then
		return 0
	end
	return buffer.readu32(s.land, i * 4)
end

-- Ближайшая к cell клетка моря не дальше reach клеток (в квадрате), в море seaId (nil или 0 — в любом).
function Naval.waterNear(s: SeaMap, cell: number, reach: number, seaId: number?): number?
	local w = s.width
	local cx, cy = cell % w, cell // w
	local best: number? = nil
	local bestD = math.huge
	for dy = -reach, reach do
		for dx = -reach, reach do
			local x, y = cx + dx, cy + dy
			if x >= 0 and y >= 0 and x < w and y < s.height then
				local j = y * w + x
				local id = buffer.readu16(s.sea, j * 2)
				if id ~= 0 and (seaId == nil or seaId == 0 or id == seaId) then
					local d = dx * dx + dy * dy
					if d < bestD then
						best, bestD = j, d
					end
				end
			end
		end
	end
	return best
end

-- Берег (клетки суши у моря), до которого от причала dock по воде не дальше Naval.SeaSupplyRange (на ширине 512).
-- Считается один раз на причал (обход моря в ширину), дальше — из кеша.
function Naval.coastReach(s: SeaMap, dock: number): { [number]: boolean }
	local cached = s.reach[dock]
	if cached ~= nil then
		return cached
	end
	local w, size = s.width, s.size
	local range = math.floor(Config.Naval.SeaSupplyRange * w / Config.UnitsReferenceMapWidth)
	local seaId = Naval.seaAt(s, dock)
	local out: { [number]: boolean } = {}
	local dist: { [number]: number } = { [dock] = 0 }
	local queue = { dock }
	local head = 1
	while head <= #queue do
		local i = queue[head]
		head += 1
		local d = dist[i]
		local x = i % w
		for k = 1, 4 do
			local j = if k == 1
				then (if x > 0 then i - 1 else -1)
				elseif k == 2 then (if x < w - 1 then i + 1 else -1)
				elseif k == 3 then i - w
				else i + w
			if j >= 0 and j < size and dist[j] == nil then
				if buffer.readu16(s.sea, j * 2) == seaId then
					if d + 1 <= range then
						dist[j] = d + 1
						table.insert(queue, j)
					end
				elseif buffer.readu16(s.sea, j * 2) == 0 then
					out[j] = true -- суша (или озеро) у этой воды
				end
			end
		end
	end
	s.reach[dock] = out
	return out
end

-- Есть ли рядом с клеткой (не дальше near) берег из одного из наборов coastReach.
function Naval.nearCoast(s: SeaMap, cell: number, near: number, sets: { { [number]: boolean } }): boolean
	if #sets == 0 then
		return false
	end
	local w = s.width
	local cx, cy = cell % w, cell // w
	for dy = -near, near do
		local y = cy + dy
		if y >= 0 and y < s.height then
			for dx = -near, near do
				local x = cx + dx
				if x >= 0 and x < w then
					local j = y * w + x
					for _, set in sets do
						if set[j] then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

-- Грубый путь: узлы навигации от a до b (коридор точного поиска) или nil.
local function corridor(s: SeaMap, a: number, b: number): { [number]: boolean }?
	local cost: { [number]: number } = { [a] = 0 }
	local parent: { [number]: number } = {}
	local done: { [number]: boolean } = {}
	local bx, by = s.nodeX[b], s.nodeY[b]
	local heap = Heap.new(256)
	Heap.push(heap, 0, a)
	local found = false
	while not Heap.isEmpty(heap) do
		local n = Heap.pop(heap)
		if done[n] then
			continue
		end
		done[n] = true
		if n == b then
			found = true
			break
		end
		local nx, ny, base = s.nodeX[n], s.nodeY[n], cost[n]
		for _, m in s.links[n] do
			if not done[m] then
				local dx, dy = s.nodeX[m] - nx, s.nodeY[m] - ny
				local c = base + math.sqrt(dx * dx + dy * dy)
				local old = cost[m]
				if old == nil or c < old then
					cost[m] = c
					parent[m] = n
					local hx, hy = bx - s.nodeX[m], by - s.nodeY[m]
					Heap.push(heap, c + math.sqrt(hx * hx + hy * hy), m)
				end
			end
		end
	end
	if not found then
		return nil
	end
	-- Коридор — только узлы грубого пути: они связаны по цепочке, поэтому точный путь внутри есть всегда.
	local out: { [number]: boolean } = {}
	local cur = b
	while true do
		out[cur] = true
		if cur == a then
			break
		end
		cur = parent[cur]
	end
	return out
end

-- Путь по морю от клетки from до клетки to (обе — одно море). Возвращает точки поворота (без from, последняя —
-- to) или nil, если пути нет или точный поиск упёрся в Naval.PathMaxNodes.
function Naval.path(s: SeaMap, from: number, to: number): { number }?
	local seaId = Naval.seaAt(s, from)
	if seaId == 0 or Naval.seaAt(s, to) ~= seaId then
		return nil
	end
	if from == to then
		return { to }
	end
	local node = s.node
	local lane = corridor(s, buffer.readu32(node, from * 4), buffer.readu32(node, to * 4))
	s.lastNodes = 0
	if lane == nil then
		return nil
	end
	local inLane = lane :: { [number]: boolean }
	local w, size = s.width, s.size
	if s.stamp == nil then
		s.stamp = buffer.create(size * 4)
		s.cost = buffer.create(size * 4)
		s.parent = buffer.create(size * 4)
	end
	local stamp, cost, parent = s.stamp :: buffer, s.cost :: buffer, s.parent :: buffer
	s.stampValue += 2
	if s.stampValue >= 4294967290 then
		buffer.fill(stamp, 0, 0)
		s.stampValue = 2
	end
	local open, closed = s.stampValue - 1, s.stampValue -- метки «в куче» и «раскрыта»
	local weight = Config.Naval.PathWeight
	local tx, ty = to % w, to // w
	local heap = Heap.new(1024)

	local cur, base = 0, 0
	local function relax(j: number, step: number)
		local st = buffer.readu32(stamp, j * 4)
		if st == closed then
			return
		end
		local c = base + step
		if st ~= open or c < buffer.readu32(cost, j * 4) then
			buffer.writeu32(stamp, j * 4, open)
			buffer.writeu32(cost, j * 4, c)
			buffer.writeu32(parent, j * 4, cur)
			local dx, dy = math.abs(j % w - tx), math.abs(j // w - ty)
			local lo = if dx < dy then dx else dy
			local hi = if dx < dy then dy else dx
			Heap.push(heap, c + (DIAG * lo + ORTHO * (hi - lo)) * weight, j)
		end
	end

	buffer.writeu32(stamp, from * 4, open)
	buffer.writeu32(cost, from * 4, 0)
	buffer.writeu32(parent, from * 4, from)
	Heap.push(heap, 0, from)
	local nodes = 0
	local maxNodes = Config.Naval.PathMaxNodes
	local found = false
	while not Heap.isEmpty(heap) do
		local i = Heap.pop(heap)
		if buffer.readu32(stamp, i * 4) == closed then
			continue
		end
		buffer.writeu32(stamp, i * 4, closed)
		nodes += 1
		if i == to then
			found = true
			break
		end
		if nodes > maxNodes then
			break
		end
		cur, base = i, buffer.readu32(cost, i * 4)
		local x = i % w
		local left = x > 0 and inLane[buffer.readu32(node, (i - 1) * 4)] == true
		local right = x < w - 1 and inLane[buffer.readu32(node, (i + 1) * 4)] == true
		local up = i >= w and inLane[buffer.readu32(node, (i - w) * 4)] == true
		local down = i + w < size and inLane[buffer.readu32(node, (i + w) * 4)] == true
		if left then
			relax(i - 1, ORTHO)
		end
		if right then
			relax(i + 1, ORTHO)
		end
		if up then
			relax(i - w, ORTHO)
			if left and inLane[buffer.readu32(node, (i - w - 1) * 4)] then
				relax(i - w - 1, DIAG)
			end
			if right and inLane[buffer.readu32(node, (i - w + 1) * 4)] then
				relax(i - w + 1, DIAG)
			end
		end
		if down then
			relax(i + w, ORTHO)
			if left and inLane[buffer.readu32(node, (i + w - 1) * 4)] then
				relax(i + w - 1, DIAG)
			end
			if right and inLane[buffer.readu32(node, (i + w + 1) * 4)] then
				relax(i + w + 1, DIAG)
			end
		end
	end
	s.lastNodes = nodes
	if not found then
		return nil
	end
	-- Обратный ход; оставляем только точки поворота.
	local cells: { number } = {}
	local c = to
	while c ~= from do
		table.insert(cells, c)
		c = buffer.readu32(parent, c * 4)
	end
	local out: { number } = {}
	local prevDir: number? = nil
	local prev = from
	for k = #cells, 1, -1 do
		local cell = cells[k]
		local dir = cell - prev
		if prevDir ~= nil and dir ~= prevDir then
			table.insert(out, prev)
		end
		prevDir = dir
		prev = cell
	end
	table.insert(out, to)
	return out
end

return table.freeze(Naval)
