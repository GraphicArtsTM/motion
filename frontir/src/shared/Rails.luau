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
	- §15ч Ч4 водные пути: станция не дальше Rail.DockCells от реки — пристань (причал — ближайшая клетка реки со своим
	  берегом, до него — дорога по суше). Пара без пути по суше, обе с причалами, — путь по реке (поиск в ширину по
	  клеткам реки со своим берегом, ctx.bank), до WaterRangeMul × дальности и WaterPathMul × прямой.
]]

local Config = require("./Config")

export type Station = { cell: number, kind: string }
-- water — §15ч Ч4: связь по реке (клетки реки на пути — водный путь, не мост); sea — §15ч Ч6: морская линия.
export type Link = { a: number, b: number, path: { number }, bridges: number, water: boolean?, sea: boolean? }
export type Net = {
	links: { Link },
	comp: { [number]: number }, -- клетка станции → номер сети
	main: number?, -- номер сети со столицей
	connected: { [number]: boolean }, -- станции главной сети
	-- клетка дороги → 1 или 2 (рельсы, шпала / промежуток по очереди), 3 (мост), 4 (водный путь, §15ч Ч4),
	-- 5 (морская линия, §15ч Ч6)
	cells: { [number]: number },
	failed: { [string]: number }, -- пара без пути → когда пробовали
	signature: string,
	kinds: { [number]: string }, -- §15ч Ч2: клетка станции → вид (City, Factory, Port, OilRig)
}
-- passable(cell) → цена клетки (nil — нельзя), river(cell) — клетка реки (мост). bank(cell) — §15ч Ч4: у клетки реки
-- свой берег (нет — водных путей нет).
export type Context = {
	width: number,
	height: number,
	passable: (cell: number) -> number?,
	river: (cell: number) -> boolean,
	bank: ((cell: number) -> boolean)?,
	-- §15ч Ч6 морские линии: isSea — клетка моря; seaOk — море не закрыто (эсминец врага); seaLink(a, b) — путь между
	-- портами a и b через море (суша до причала, море, суша от причала; клетки подряд) или nil. Нет seaLink — линий нет.
	isSea: ((cell: number) -> boolean)?,
	seaOk: ((cell: number) -> boolean)?,
	seaLink: ((a: number, b: number) -> { number }?)?,
	now: number,
}

local Rails = {}

local SQRT2 = math.sqrt(2)
local DX = { 1, -1, 0, 0, 1, 1, -1, -1 }
local DY = { 0, 0, 1, -1, 1, -1, 1, -1 }

-- §15ч Ч5а: клетка не дальше дальности связи от одной из станций (главная сеть и столица) — «у сети».
function Rails.nearNetwork(stations: { number }, cell: number, width: number): boolean
	local r = Rails.range(width)
	local r2 = r * r
	local x, y = cell % width, cell // width
	for _, s in stations do
		local dx, dy = s % width - x, s // width - y
		if dx * dx + dy * dy <= r2 then
			return true
		end
	end
	return false
end

-- §15ч Ч5б «призрак» дороги: от места spot до ближайшей из станций (главная сеть и столица), как построит сервер —
-- ближайшие в дальности связи, до Rail.JunctionTries попыток. Возвращает путь (или nil), причину ("ok" / "far" —
-- станций в дальности нет / "noPath" — нет пути по своей земле) и расстояние до ближайшей станции (клеток).
function Rails.ghost(ctx: Context, spot: number, stations: { number }): ({ number }?, string, number)
	local w = ctx.width
	local range = Rails.range(w)
	type Cand = { cell: number, d: number }
	local cands: { Cand } = {}
	local nearest = math.huge
	for _, s in stations do
		if s ~= spot then
			local d = math.sqrt((s % w - spot % w) ^ 2 + (s // w - spot // w) ^ 2)
			nearest = math.min(nearest, d)
			if d <= range then
				table.insert(cands, { cell = s, d = d })
			end
		end
	end
	if #cands == 0 then
		return nil, "far", nearest
	end
	table.sort(cands, function(a: Cand, b: Cand): boolean
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.cell < b.cell
	end)
	for k = 1, math.min(#cands, Config.Rail.JunctionTries) do
		local path = Rails.path(ctx, spot, cands[k].cell)
		if path ~= nil then
			return path, "ok", nearest
		end
	end
	return nil, "noPath", nearest
end

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

-- §15ч Ч4: по клетке реки можно плыть: проходима (не у разрушенного моста) и берег свой.
local function waterOk(ctx: Context, cell: number): boolean
	local bank = ctx.bank
	return bank ~= nil and ctx.river(cell) and ctx.passable(cell) ~= nil and bank(cell)
end

-- Все клетки пути (кроме станций на концах) ещё проходимы; у водного пути клетки реки — со своим берегом.
function Rails.intact(ctx: Context, link: Link): boolean
	local n = #link.path
	local water = link.water == true
	local isSea, seaOk = ctx.isSea, ctx.seaOk
	for k = 2, n - 1 do
		local cell = link.path[k]
		if link.sea and isSea ~= nil and isSea(cell) then
			-- §15ч Ч6: море — не закрыто эсминцем врага.
			if seaOk ~= nil and not seaOk(cell) then
				return false
			end
		elseif water and ctx.river(cell) then
			if not waterOk(ctx, cell) then
				return false
			end
		elseif ctx.passable(cell) == nil then
			return false
		end
	end
	return true
end

-- §15ч Ч4: причал станции — ближайшая клетка реки со своим берегом не дальше Rail.DockCells (на ширину 512); равные —
-- меньший номер. nil — станция не у реки.
function Rails.dock(ctx: Context, station: number): number?
	if ctx.bank == nil then
		return nil
	end
	local w, h = ctx.width, ctx.height
	local r = math.max(1, math.floor(Config.Rail.DockCells * w / Config.UnitsReferenceMapWidth + 0.5))
	local sx, sy = station % w, station // w
	local best: number? = nil
	local bestD = math.huge
	for dy = -r, r do
		local y = sy + dy
		if y >= 0 and y < h then
			for dx = -r, r do
				local x = sx + dx
				local d = dx * dx + dy * dy
				if x >= 0 and x < w and d <= r * r then
					local cell = y * w + x
					if (d < bestD or (d == bestD and cell < (best :: number))) and waterOk(ctx, cell) then
						best, bestD = cell, d
					end
				end
			end
		end
	end
	return best
end

-- §15ч Ч4: путь по реке между станциями a и b: суша до причала a, река, суша от причала b. nil — нет.
-- docks — кеш причалов и путей до них (на одну сборку сети).
function Rails.waterPath(
	ctx: Context,
	a: number,
	b: number,
	docks: { [number]: { dock: number, land: { number } } | false }?
): { number }?
	local cache = docks or {}
	local function dockOf(s: number): { dock: number, land: { number } }?
		local hit = cache[s]
		if hit ~= nil then
			return if hit == false then nil else hit
		end
		local dock = Rails.dock(ctx, s)
		local land = if dock ~= nil then Rails.path(ctx, s, dock) else nil
		local entry = if dock ~= nil and land ~= nil then { dock = dock, land = land } else nil
		cache[s] = if entry ~= nil then entry else false
		return entry
	end
	local da, db = dockOf(a), dockOf(b)
	if da == nil or db == nil then
		return nil
	end
	local w = ctx.width
	local straight = math.sqrt((a % w - b % w) ^ 2 + (a // w - b // w) ^ 2)
	local maxSteps = straight * Config.Rail.WaterPathMul + 4
	-- Поиск в ширину по реке от причала a к причалу b.
	local from: { [number]: number } = {}
	local depth: { [number]: number } = { [da.dock] = 0 }
	local queue = { da.dock }
	local head = 1
	local goal = db.dock
	while head <= #queue and depth[goal] == nil do
		local c = queue[head]
		head += 1
		local dc = depth[c]
		if dc >= maxSteps then
			continue
		end
		local x, y = c % w, c // w
		for d = 1, 8 do
			local nx, ny = x + DX[d], y + DY[d]
			if nx >= 0 and ny >= 0 and nx < w and ny < ctx.height then
				local j = ny * w + nx
				if depth[j] == nil and waterOk(ctx, j) then
					depth[j] = dc + 1
					from[j] = c
					table.insert(queue, j)
				end
			end
		end
	end
	if depth[goal] == nil then
		return nil
	end
	local river: { number } = {}
	local c: number? = goal
	while c ~= nil do
		table.insert(river, 1, c)
		c = from[c]
	end
	local path: { number } = table.clone(da.land) -- a … причал a
	for k = 2, #river do
		table.insert(path, river[k])
	end
	for k = #db.land - 1, 1, -1 do -- причал b … b
		table.insert(path, db.land[k])
	end
	return path
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
	-- Пары в пределах дальности — от близких к дальним (§15ч Ч4: с реками — до WaterRangeMul × дальности).
	-- §15ч Ч6: два порта при морских линиях — до SeaRangeMul × дальности.
	local reach = if ctx.bank ~= nil then range * cfg.WaterRangeMul else range
	local seaReach = if ctx.seaLink ~= nil then range * cfg.SeaRangeMul else 0
	local docks: { [number]: { dock: number, land: { number } } | false } = {}
	type Pair = { a: number, b: number, d: number }
	local pairs: { Pair } = {}
	local port: { [number]: boolean } = {}
	for _, s in stations do
		port[s.cell] = s.kind == "Port"
	end
	for i = 1, #stations do
		local a = stations[i].cell
		for j = i + 1, #stations do
			local b = stations[j].cell
			local d = math.sqrt((a % w - b % w) ^ 2 + (a // w - b // w) ^ 2)
			if d <= reach or (port[a] and port[b] and d <= seaReach) then
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
				local path, bridges = nil, 0
				if p.d <= range then
					path, bridges = Rails.path(ctx, p.a, p.b)
				end
				if path ~= nil then
					link = { a = p.a, b = p.b, path = path, bridges = bridges }
				elseif ra ~= rb then
					-- §15ч Ч4: по суше нельзя — по реке (кольца по воде не строим).
					local water = if p.d <= reach then Rails.waterPath(ctx, p.a, p.b, docks) else nil
					if water ~= nil then
						link = { a = p.a, b = p.b, path = water, bridges = 0, water = true }
					end
					-- §15ч Ч6: и не по реке — два порта морем.
					local seaLink = ctx.seaLink
					if link == nil and seaLink ~= nil and port[p.a] and port[p.b] then
						local sea = seaLink(p.a, p.b)
						local candidate: Link? = if sea ~= nil
							then { a = p.a, b = p.b, path = sea, bridges = 0, sea = true }
							else nil
						-- Новый путь тоже не должен идти мимо эсминца врага.
						if candidate ~= nil and Rails.intact(ctx, candidate) then
							link = candidate
						end
					end
				end
				if link == nil then
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
				local river = ctx.river(cell)
				local isSea = ctx.isSea
				cells[cell] = if link.sea
						and isSea ~= nil
						and isSea(cell)
					then 5
					elseif river and link.water then 4
					elseif river then 3
					else 1 + (k % 2)
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
