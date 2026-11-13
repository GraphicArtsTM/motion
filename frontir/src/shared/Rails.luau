--!strict
--!native
--[[
	Rails — железные дороги державы (§15ч Ч1). Чистый модуль: сеть строится из станций и правила проходимости.
	- Станции — свои город (и столица), завод, порт. Пары станций не дальше Rail.LinkRange (на ширину 512) — от близких
	  к дальним; связь ставится, если станции ещё в разных сетях или у обеих меньше Rail.MaxDegree дорог.
	- Путь — A* по 8 соседям: своя земля (цена 1), клетка реки — мост (Rail.BridgeCost, не длиннее BridgeMaxCells
	  подряд); длина пути не больше прямой × Rail.MaxPathMul. Предел поиска — Rail.MaxNodes клеток.
	- Прежние пути переиспользуются, пока все их клетки проходимы (intact); пары без пути ждут Rail.RetryFailedSec.
	- Сеть со столицей — «главная»: её станции снабжают фронт и успокаивают дальние провинции (MatchSim).
]]

local Config = require("./Config")

export type Station = { cell: number, kind: string }
export type Link = { a: number, b: number, path: { number }, bridges: number }
export type Net = {
	links: { Link },
	comp: { [number]: number }, -- клетка станции → номер сети
	main: number?, -- номер сети со столицей
	connected: { [number]: boolean }, -- станции главной сети
	cells: { [number]: number }, -- клетка дороги → 1 или 2 (рельсы, шпала / промежуток по очереди), 3 (мост)
	failed: { [string]: number }, -- пара без пути → когда пробовали
	signature: string,
	kinds: { [number]: string }, -- §15ч Ч2: клетка станции → вид (City, Factory, Port, OilRig)
}
-- passable(cell) → цена клетки (nil — нельзя), river(cell) — клетка реки (мост).
export type Context = {
	width: number,
	height: number,
	passable: (cell: number) -> number?,
	river: (cell: number) -> boolean,
	now: number,
}

local Rails = {}

local SQRT2 = math.sqrt(2)
local DX = { 1, -1, 0, 0, 1, 1, -1, -1 }
local DY = { 0, 0, 1, -1, 1, -1, 1, -1 }

-- Дальность связи в клетках этой карты.
function Rails.range(width: number): number
	return Config.Rail.LinkRange * width / Config.UnitsReferenceMapWidth
end

local function pairKey(a: number, b: number): string
	return if a < b then a .. ":" .. b else b .. ":" .. a
end

-- Путь от a до b (обе — клетки станций, проходимость концов не проверяется). nil — нет пути.
function Rails.path(ctx: Context, a: number, b: number): ({ number }?, number)
	local w = ctx.width
	local ax, ay, bx, by = a % w, a // w, b % w, b // w
	local straight = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
	local maxLen = straight * Config.Rail.MaxPathMul + 2
	local function h(i: number): number
		local dx, dy = math.abs(i % w - bx), math.abs(i // w - by)
		return math.max(dx, dy) + (SQRT2 - 1) * math.min(dx, dy)
	end
	-- Бинарная куча по f.
	local heapF: { number } = {}
	local heapI: { number } = {}
	local function push(f: number, i: number)
		local k = #heapF + 1
		heapF[k], heapI[k] = f, i
		while k > 1 do
			local p = k // 2
			if heapF[p] <= heapF[k] then
				break
			end
			heapF[p], heapF[k] = heapF[k], heapF[p]
			heapI[p], heapI[k] = heapI[k], heapI[p]
			k = p
		end
	end
	local function pop(): number
		local top = heapI[1]
		local n = #heapF
		heapF[1], heapI[1] = heapF[n], heapI[n]
		heapF[n], heapI[n] = nil :: any, nil :: any
		n -= 1
		local k = 1
		while true do
			local l, r = 2 * k, 2 * k + 1
			local m = k
			if l <= n and heapF[l] < heapF[m] then
				m = l
			end
			if r <= n and heapF[r] < heapF[m] then
				m = r
			end
			if m == k then
				break
			end
			heapF[m], heapF[k] = heapF[k], heapF[m]
			heapI[m], heapI[k] = heapI[k], heapI[m]
			k = m
		end
		return top
	end
	local gScore: { [number]: number } = { [a] = 0 }
	local steps: { [number]: number } = { [a] = 0 }
	local from: { [number]: number } = {}
	local closed: { [number]: boolean } = {}
	push(h(a), a)
	local visited = 0
	while #heapF > 0 do
		local i = pop()
		if i == b then
			local path: { number } = {}
			local c: number? = b
			while c ~= nil do
				table.insert(path, 1, c)
				c = from[c]
			end
			-- Мост не длиннее BridgeMaxCells клеток реки подряд.
			local run, bridges = 0, 0
			for _, cell in path do
				if ctx.river(cell) then
					run += 1
					bridges += 1
					if run > Config.Rail.BridgeMaxCells then
						return nil, 0
					end
				else
					run = 0
				end
			end
			return path, bridges
		end
		if not closed[i] then
			closed[i] = true
			visited += 1
			if visited > Config.Rail.MaxNodes then
				return nil, 0
			end
			local x, y = i % w, i // w
			local gi = gScore[i]
			for d = 1, 8 do
				local nx, ny = x + DX[d], y + DY[d]
				if nx >= 0 and ny >= 0 and nx < w and ny < ctx.height then
					local j = ny * w + nx
					if not closed[j] then
						local cost = if j == b then 1 else ctx.passable(j)
						if cost ~= nil then
							local step = if d > 4 then SQRT2 else 1
							local s = steps[i] + step
							if s <= maxLen then
								local g = gi + step * cost
								local old = gScore[j]
								if old == nil or g < old then
									gScore[j] = g
									steps[j] = s
									from[j] = i
									push(g + h(j), j)
								end
							end
						end
					end
				end
			end
		end
	end
	return nil, 0
end

-- Все клетки пути (кроме станций на концах) ещё проходимы.
function Rails.intact(ctx: Context, link: Link): boolean
	local n = #link.path
	for k = 2, n - 1 do
		if ctx.passable(link.path[k]) == nil then
			return false
		end
	end
	return true
end

-- Подпись набора станций и столицы: та же — сеть не перестраивать (если дороги целы).
function Rails.signature(stations: { Station }, capital: number?): string
	local cells: { number } = {}
	for _, s in stations do
		table.insert(cells, s.cell)
	end
	table.sort(cells)
	return tostring(capital or 0) .. "|" .. table.concat(cells, ",")
end

-- Все ли дороги сети целы (клетки проходимы).
function Rails.allIntact(ctx: Context, net: Net): boolean
	for _, link in net.links do
		if not Rails.intact(ctx, link) then
			return false
		end
	end
	return true
end

-- Сеть державы. prev — прежняя сеть (пути переиспользуются, неудачные пары ждут RetryFailedSec).
function Rails.build(stations: { Station }, capital: number?, ctx: Context, prev: Net?): Net
	local cfg = Config.Rail
	local w = ctx.width
	local range = Rails.range(w)
	local old: { [string]: Link } = {}
	local failed: { [string]: number } = {}
	if prev ~= nil then
		for _, link in prev.links do
			old[pairKey(link.a, link.b)] = link
		end
		for key, t in prev.failed do
			if ctx.now - t < cfg.RetryFailedSec then
				failed[key] = t
			end
		end
	end
	-- Пары в пределах дальности — от близких к дальним.
	type Pair = { a: number, b: number, d: number }
	local pairs: { Pair } = {}
	for i = 1, #stations do
		local a = stations[i].cell
		for j = i + 1, #stations do
			local b = stations[j].cell
			local d = math.sqrt((a % w - b % w) ^ 2 + (a // w - b // w) ^ 2)
			if d <= range then
				table.insert(pairs, { a = a, b = b, d = d })
			end
		end
	end
	table.sort(pairs, function(p: Pair, q: Pair): boolean
		if p.d ~= q.d then
			return p.d < q.d
		end
		return pairKey(p.a, p.b) < pairKey(q.a, q.b)
	end)
	-- Сети — объединение множеств.
	local parent: { [number]: number } = {}
	for _, s in stations do
		parent[s.cell] = s.cell
	end
	local function find(x: number): number
		while parent[x] ~= x do
			parent[x] = parent[parent[x]]
			x = parent[x]
		end
		return x
	end
	local degree: { [number]: number } = {}
	local links: { Link } = {}
	for _, p in pairs do
		local ra, rb = find(p.a), find(p.b)
		local da, db = degree[p.a] or 0, degree[p.b] or 0
		-- Кольцо внутри одной сети — только короткое (не дальше половины дальности) и без «паутины» (MaxDegree).
		local loop = ra == rb and da > 0 and db > 0 and da < cfg.MaxDegree and db < cfg.MaxDegree and p.d <= range * 0.5
		if ra ~= rb or loop then
			local key = pairKey(p.a, p.b)
			local link: Link? = nil
			local reuse = old[key]
			if reuse ~= nil and Rails.intact(ctx, reuse) then
				link = reuse
			elseif failed[key] == nil then
				local path, bridges = Rails.path(ctx, p.a, p.b)
				if path ~= nil then
					link = { a = p.a, b = p.b, path = path, bridges = bridges }
				else
					failed[key] = ctx.now
				end
			end
			if link ~= nil then
				table.insert(links, link)
				parent[ra] = rb
				degree[p.a] = da + 1
				degree[p.b] = db + 1
			end
		end
	end
	-- Номера сетей, главная, клетки дорог.
	local comp: { [number]: number } = {}
	for _, s in stations do
		comp[s.cell] = find(s.cell)
	end
	local main = if capital ~= nil then comp[capital] else nil
	local connected: { [number]: boolean } = {}
	if main ~= nil then
		for cell, c in comp do
			if c == main then
				connected[cell] = true
			end
		end
	end
	local isStation: { [number]: boolean } = {}
	local kinds: { [number]: string } = {}
	for _, s in stations do
		isStation[s.cell] = true
		kinds[s.cell] = s.kind
	end
	local cells: { [number]: number } = {}
	for _, link in links do
		for k, cell in link.path do
			if not isStation[cell] then
				cells[cell] = if ctx.river(cell) then 3 else 1 + (k % 2)
			end
		end
	end
	return {
		links = links,
		comp = comp,
		main = main,
		connected = connected,
		cells = cells,
		failed = failed,
		signature = Rails.signature(stations, capital),
		kinds = kinds,
	}
end

-- Пустая сеть (у державы нет станций).
function Rails.empty(): Net
	return { links = {}, comp = {}, main = nil, connected = {}, cells = {}, failed = {}, signature = "", kinds = {} }
end

-- Путь сжато для сети: начальная клетка и строка направлений «0»–«7» (DX/DY), клиент разворачивает обратно.
function Rails.encode(path: { number }, width: number): (number, string)
	local parts: { string } = {}
	for k = 2, #path do
		local a, b = path[k - 1], path[k]
		local dx, dy = b % width - a % width, b // width - a // width
		for d = 1, 8 do
			if DX[d] == dx and DY[d] == dy then
				table.insert(parts, tostring(d - 1))
				break
			end
		end
	end
	return path[1], table.concat(parts)
end

function Rails.decode(start: number, dirs: string, width: number): { number }
	local path = { start }
	local cell = start
	for k = 1, #dirs do
		local d = (string.byte(dirs, k) - 48) + 1
		local dx, dy = DX[d], DY[d]
		if dx == nil then
			break
		end
		cell = (cell // width + dy) * width + (cell % width + dx)
		table.insert(path, cell)
	end
	return path
end

return table.freeze(Rails)
