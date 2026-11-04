--!strict
--[[
	MapGen — генератор выдуманных карт по сиду (GDD §4). Чистый модуль: работает в Lune (tools/genmap)
	и на сервере (случайные карты, этап 8). Один и тот же набор параметров даёт побайтно одну карту.

	Шаги:
	1. Высота = fbm-шум минус затухание к краям; порог подбирается так, чтобы суши было LandShare.
	2. Мелкие острова тонут, мелкие внутренние лужи засыпаются.
	3. Горы и холмы — по «гребневому» шуму с поправкой на высоту (доли от суши).
	4. Биомы: тундра у полюсов (верх и низ карты), пустыня в сухих тёплых местах, лес во влажных.
	5. Озёра — пятна воды вдали от моря.
	6. Реки — линии от гор и холмов к ближайшей воде (4-связные, чтобы граница их не перепрыгивала).
	7. Провинции (этап 3): затравки по суше на расстоянии друг от друга, рост от них по «стоимости пути»
	   (холмы, горы и реки дороже, плюс шум — границы ложатся по хребтам и рекам и не выглядят ячейками),
	   мелкие провинции сливаются с соседом, с которым у них самая длинная граница. Вода — без провинции (0).
]]

local MapData = require("./MapData")
local Noise = require("./Noise")
local Heap = require("./Heap")
local Rng = require("./Rng")
local Types = require("./Types")

type MapData = MapData.MapData

export type GenStats = {
	landShare: number,
	provinces: number,
	islands: number,
	lakes: number,
	rivers: number,
}

local T = Types.Terrain
local UNREACHED = 65535

local MapGen = {}

-- Значение q-квантиля (0..1) набора чисел.
local function quantile(values: { number }, q: number): number
	local sorted = table.clone(values)
	table.sort(sorted)
	local idx = math.clamp(math.floor(q * #sorted) + 1, 1, #sorted)
	return sorted[idx]
end

-- Вызывает fn(j) для 4 соседей клетки i в пределах карты.
local function forNeighbours4(w: number, h: number, i: number, fn: (j: number) -> ())
	local x = i % w
	local y = i // w
	if x > 0 then
		fn(i - 1)
	end
	if x < w - 1 then
		fn(i + 1)
	end
	if y > 0 then
		fn(i - w)
	end
	if y < h - 1 then
		fn(i + w)
	end
end

-- Компоненты связности (4 соседа) клеток, для которых mask[i] == value.
-- Возвращает метки (u32 на клетку, 0 — не входит), размеры и касание края карты по меткам.
local function components(w: number, h: number, mask: buffer, value: number): (buffer, { number }, { boolean })
	local n = w * h
	local labels = buffer.create(n * 4)
	local sizes: { number } = {}
	local touchesEdge: { boolean } = {}
	local queue: { number } = table.create(1024)
	for start = 0, n - 1 do
		if buffer.readu8(mask, start) == value and buffer.readu32(labels, start * 4) == 0 then
			local label = #sizes + 1
			local size = 0
			local edge = false
			buffer.writeu32(labels, start * 4, label)
			local head, tail = 1, 1
			queue[1] = start
			while head <= tail do
				local i = queue[head]
				head += 1
				size += 1
				local x = i % w
				local y = i // w
				if x == 0 or y == 0 or x == w - 1 or y == h - 1 then
					edge = true
				end
				forNeighbours4(w, h, i, function(j)
					if buffer.readu8(mask, j) == value and buffer.readu32(labels, j * 4) == 0 then
						buffer.writeu32(labels, j * 4, label)
						tail += 1
						queue[tail] = j
					end
				end)
			end
			sizes[label] = size
			touchesEdge[label] = edge
		end
	end
	return labels, sizes, touchesEdge
end

-- Расстояние (в шагах по 4 соседям) от клеток-источников по проходимым клеткам. u16, UNREACHED — не дошли.
local function distanceField(
	w: number,
	h: number,
	isSource: (i: number) -> boolean,
	isPassable: (i: number) -> boolean
): buffer
	local n = w * h
	local dist = buffer.create(n * 2)
	buffer.fill(dist, 0, 255)
	local queue: { number } = table.create(n)
	local tail = 0
	for i = 0, n - 1 do
		if isSource(i) then
			buffer.writeu16(dist, i * 2, 0)
			tail += 1
			queue[tail] = i
		end
	end
	local head = 1
	while head <= tail do
		local i = queue[head]
		head += 1
		local d = buffer.readu16(dist, i * 2) + 1
		forNeighbours4(w, h, i, function(j)
			if buffer.readu16(dist, j * 2) == UNREACHED and isPassable(j) then
				buffer.writeu16(dist, j * 2, math.min(d, UNREACHED - 1))
				tail += 1
				queue[tail] = j
			end
		end)
	end
	return dist
end

function MapGen.generate(p: Types.MapGenParams): (MapData, GenStats)
	local w, h = p.Width, p.Height
	local n = w * h
	local seed = p.Seed
	local map = MapData.new(p.Name, seed, w, h)
	local terrain = map.terrain

	-- 1. Высота и порог суши.
	local elev: { number } = table.create(n, 0)
	local cx, cy = (w - 1) / 2, (h - 1) / 2
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local e = Noise.fbm(x / p.NoiseScale, y / p.NoiseScale, seed, p.Octaves, p.Lacunarity, p.Gain)
			local dx = (x - cx) / (w / 2)
			local dy = (y - cy) / (h / 2)
			e -= p.FalloffStrength * math.sqrt(dx * dx + dy * dy) ^ p.FalloffPower
			if math.min(x, y, w - 1 - x, h - 1 - y) < p.EdgeWater then
				e = -math.huge
			end
			elev[y * w + x + 1] = e
		end
	end
	local threshold = quantile(elev, 1 - p.LandShare)
	local landMask = buffer.create(n) -- 1 — суша
	for i = 0, n - 1 do
		if elev[i + 1] >= threshold and elev[i + 1] > -math.huge then
			buffer.writeu8(landMask, i, 1)
		end
	end

	-- 2. Острова и лужи.
	local landLabels, landSizes = components(w, h, landMask, 1)
	local largest = 0
	for label, size in landSizes do
		if largest == 0 or size > landSizes[largest] then
			largest = label
		end
	end
	local islands = 0
	for label, size in landSizes do
		if label == largest or size >= p.MinIslandCells then
			islands += 1
		end
	end
	for i = 0, n - 1 do
		local label = buffer.readu32(landLabels, i * 4)
		if label ~= 0 and label ~= largest and landSizes[label] < p.MinIslandCells then
			buffer.writeu8(landMask, i, 0)
		end
	end
	local waterLabels, waterSizes, waterEdge = components(w, h, landMask, 0)
	for i = 0, n - 1 do
		local label = buffer.readu32(waterLabels, i * 4)
		if label ~= 0 and not waterEdge[label] and waterSizes[label] < p.FillHoleCells then
			buffer.writeu8(landMask, i, 1)
		end
	end

	-- 3. Горы и холмы: доли от суши по «гребневому» шуму с поправкой на высоту.
	local maxElev = threshold
	for i = 0, n - 1 do
		if buffer.readu8(landMask, i) == 1 and elev[i + 1] > maxElev then
			maxElev = elev[i + 1]
		end
	end
	local elevRange = math.max(maxElev - threshold, 1e-9)
	local relief: { number } = table.create(n, 0)
	local landRelief: { number } = {}
	for i = 0, n - 1 do
		if buffer.readu8(landMask, i) == 1 then
			local x, y = i % w, i // w
			local ridge = Noise.ridged(x / p.RidgeScale, y / p.RidgeScale, seed + 1013, 4, 2.0, 0.5)
			local height = math.clamp((elev[i + 1] - threshold) / elevRange, 0, 1)
			local r = p.RidgeWeight * ridge + (1 - p.RidgeWeight) * height
			relief[i + 1] = r
			table.insert(landRelief, r)
		end
	end
	local mountainAt = quantile(landRelief, 1 - p.MountainShare)
	local hillAt = quantile(landRelief, 1 - p.MountainShare - p.HillShare)

	-- 4. Биомы.
	for i = 0, n - 1 do
		if buffer.readu8(landMask, i) == 1 then
			local x, y = i % w, i // w
			local r = relief[i + 1]
			-- Широта с шумовым «дрожанием», чтобы границы тундры и пустынь не были прямыми линиями.
			local jitter = Noise.fbm(x / p.MoistureScale * 1.7, y / p.MoistureScale * 1.7, seed + 3001, 3, 2.0, 0.5)
			local lat = math.abs(y - cy) / (h / 2) + (jitter - 0.5) * p.LatitudeJitter
			local t: number
			if r >= mountainAt then
				t = T.Mountains
			elseif r >= hillAt then
				t = T.Hills
			elseif lat >= p.TundraLatitude then
				t = T.Tundra
			else
				local moisture = Noise.fbm(x / p.MoistureScale, y / p.MoistureScale, seed + 2027, 4, 2.0, 0.5)
				if moisture <= p.DesertMoistureMax and lat <= p.DesertLatitudeMax then
					t = T.Desert
				elseif moisture >= p.ForestMoistureMin then
					t = T.Forest
				else
					t = T.Plains
				end
			end
			buffer.writeu8(terrain, i, t)
		else
			buffer.writeu8(terrain, i, T.Water)
		end
	end

	local function isWater(i: number): boolean
		return buffer.readu8(terrain, i) == T.Water
	end
	local function isLand(i: number): boolean
		return buffer.readu8(terrain, i) ~= T.Water
	end

	-- 5. Озёра.
	local rng = Rng.new(seed + 4099)
	local seaDist = distanceField(w, h, isWater, isLand)
	local lakes = 0
	local attempts = 0
	while lakes < p.LakeCount and attempts < p.LakeCount * 40 do
		attempts += 1
		local start = Rng.range(rng, 0, n - 1)
		local st = buffer.readu8(terrain, start)
		if
			(st == T.Plains or st == T.Forest or st == T.Tundra)
			and buffer.readu16(seaDist, start * 2) >= p.LakeCoastGap + 3
		then
			local target = Rng.range(rng, p.LakeMinCells, p.LakeMaxCells)
			local cells: { number } = {}
			local frontier: { number } = { start }
			local seen: { [number]: boolean } = { [start] = true }
			while #cells < target and #frontier > 0 do
				local k = Rng.range(rng, 1, #frontier)
				local i = frontier[k]
				frontier[k] = frontier[#frontier]
				frontier[#frontier] = nil
				local ti = buffer.readu8(terrain, i)
				if ti ~= T.Water and ti ~= T.Mountains and buffer.readu16(seaDist, i * 2) >= p.LakeCoastGap then
					table.insert(cells, i)
					forNeighbours4(w, h, i, function(j)
						if not seen[j] then
							seen[j] = true
							table.insert(frontier, j)
						end
					end)
				end
			end
			-- Озеро не должно слиться с уже существующей водой (клетки самого озера ещё суша).
			local touchesWater = false
			for _, i in cells do
				forNeighbours4(w, h, i, function(j)
					if isWater(j) then
						touchesWater = true
					end
				end)
			end
			if #cells >= p.LakeMinCells and not touchesWater then
				for _, i in cells do
					buffer.writeu8(terrain, i, T.Water)
				end
				lakes += 1
			end
		end
	end

	-- Пятна озёр могут оставить внутри себя островки в 1–3 клетки — топим их.
	local afterLakes = buffer.create(n)
	for i = 0, n - 1 do
		if isLand(i) then
			buffer.writeu8(afterLakes, i, 1)
		end
	end
	local lakeLabels, lakeIslandSizes = components(w, h, afterLakes, 1)
	local mainland = 0
	for label, size in lakeIslandSizes do
		if mainland == 0 or size > lakeIslandSizes[mainland] then
			mainland = label
		end
	end
	for i = 0, n - 1 do
		local label = buffer.readu32(lakeLabels, i * 4)
		if label ~= 0 and label ~= mainland and lakeIslandSizes[label] < p.MinIslandCells then
			buffer.writeu8(terrain, i, T.Water)
		end
	end

	-- 6. Реки: от гор и холмов вниз по расстоянию до воды.
	local waterDist = distanceField(w, h, isWater, isLand)
	local rivers = 0
	attempts = 0
	while rivers < p.RiverCount and attempts < p.RiverCount * 60 do
		attempts += 1
		local start = Rng.range(rng, 0, n - 1)
		local st = buffer.readu8(terrain, start)
		local startDist = buffer.readu16(waterDist, start * 2)
		if (st == T.Mountains or st == T.Hills) and startDist >= p.RiverMinLength and startDist ~= UNREACHED then
			local path: { number } = { start }
			local inPath: { [number]: boolean } = { [start] = true }
			local ok = false
			local cur = start
			while #path <= p.RiverMaxLength do
				local d = buffer.readu16(waterDist, cur * 2)
				if d <= 1 then
					ok = true
					break
				end
				local down: { number } = {}
				local side: { number } = {}
				local joins: number? = nil
				forNeighbours4(w, h, cur, function(j)
					if inPath[j] or isWater(j) then
						return
					end
					if buffer.readu8(terrain, j) == T.River then
						joins = j
						return
					end
					local dj = buffer.readu16(waterDist, j * 2)
					if dj == d - 1 then
						table.insert(down, j)
					elseif dj == d then
						table.insert(side, j)
					end
				end)
				if joins ~= nil then
					ok = true -- приток: влился в другую реку
					break
				end
				local nextCell: number
				if #side > 0 and Rng.nextFloat(rng) < p.RiverMeander then
					nextCell = side[Rng.range(rng, 1, #side)]
				elseif #down > 0 then
					nextCell = down[Rng.range(rng, 1, #down)]
				else
					break
				end
				table.insert(path, nextCell)
				inPath[nextCell] = true
				cur = nextCell
			end
			if ok and #path >= p.RiverMinLength then
				for k = 2, #path do
					buffer.writeu8(terrain, path[k], T.River)
				end
				rivers += 1
			end
		end
	end

	local provinces = MapGen.generateProvinces(map, p, Rng.new(seed + 6007))

	local land = 0
	for i = 0, n - 1 do
		if isLand(i) then
			land += 1
		end
	end

	return map,
		{
			landShare = land / n,
			provinces = provinces,
			islands = islands,
			lakes = lakes,
			rivers = rivers,
		}
end

-- 7. Провинции: заполняет map.province (u16, 1..P на суше, 0 на воде). Возвращает число провинций.
function MapGen.generateProvinces(map: MapData, p: Types.ProvinceParams, rng: Rng.Rng): number
	local w, h = map.width, map.height
	local n = w * h
	local T = Types.Terrain
	local terrain = map.terrain
	local function isLand(i: number): boolean
		return buffer.readu8(terrain, i) ~= T.Water
	end

	-- Затравки: в каждом куске суши — пропорционально его площади, на расстоянии друг от друга.
	local landMask = buffer.create(n)
	for i = 0, n - 1 do
		if isLand(i) then
			buffer.writeu8(landMask, i, 1)
		end
	end
	local labels, sizes = components(w, h, landMask, 1)
	local cellsOf: { { number } } = {}
	for label = 1, #sizes do
		cellsOf[label] = table.create(sizes[label])
	end
	for i = 0, n - 1 do
		local label = buffer.readu32(labels, i * 4)
		if label ~= 0 then
			table.insert(cellsOf[label], i)
		end
	end
	local spacing = math.sqrt(p.ProvinceTargetCells) * p.ProvinceSeedSpacing
	local seeds: { number } = {}
	for label = 1, #sizes do
		local cells = cellsOf[label]
		local want = math.max(1, math.floor(#cells / p.ProvinceTargetCells + 0.5))
		local mine: { number } = {}
		for _ = 1, want * 80 do
			if #mine >= want then
				break
			end
			local c = cells[Rng.range(rng, 1, #cells)]
			if buffer.readu8(terrain, c) ~= T.River then
				local ok = true
				local cx, cy = c % w, c // w
				for _, s in mine do
					if (s % w - cx) ^ 2 + (s // w - cy) ^ 2 < spacing * spacing then
						ok = false
						break
					end
				end
				if ok then
					table.insert(mine, c)
				end
			end
		end
		if #mine == 0 then
			table.insert(mine, cells[1])
		end
		for _, s in mine do
			table.insert(seeds, s)
		end
	end

	-- Рост от затравок (Dijkstra): клетка достаётся затравке с самым «дешёвым» путём.
	local function cost(i: number): number
		local t = buffer.readu8(terrain, i)
		local base = if t == T.Mountains
			then p.ProvinceMountainCost
			elseif t == T.Hills then p.ProvinceHillCost
			elseif t == T.River then p.ProvinceRiverCost
			else 1
		local nx, ny = i % w / p.ProvinceNoiseScale, i // w / p.ProvinceNoiseScale
		return base * (1 + Noise.value2(nx, ny, map.seed + 5003) * p.ProvinceNoise)
	end
	local province = map.province
	local dist: { number } = table.create(n, math.huge)
	local heap = Heap.new(n)
	for k, s in seeds do
		dist[s + 1] = 0
		buffer.writeu16(province, s * 2, k)
		Heap.push(heap, 0, s)
	end
	while not Heap.isEmpty(heap) do
		local i, d = Heap.pop(heap)
		if d <= dist[i + 1] then
			local owner = buffer.readu16(province, i * 2)
			local ci = cost(i)
			forNeighbours4(w, h, i, function(j)
				if isLand(j) then
					local nd = d + (ci + cost(j)) / 2
					if nd < dist[j + 1] then
						dist[j + 1] = nd
						buffer.writeu16(province, j * 2, owner)
						Heap.push(heap, nd, j)
					end
				end
			end)
		end
	end

	-- Слияние мелких провинций с соседом по самой длинной общей границе (острова остаются).
	local members: { [number]: { number } } = {}
	for i = 0, n - 1 do
		local id = buffer.readu16(province, i * 2)
		if id ~= 0 then
			local list = members[id]
			if list == nil then
				list = {}
				members[id] = list
			end
			table.insert(list, i)
		end
	end
	local changed = true
	while changed do
		changed = false
		local smallest, smallestSize = 0, math.huge
		for id, list in members do
			if #list < p.ProvinceMinCells and #list < smallestSize then
				-- Есть ли сосед? У острова соседей нет — он остаётся отдельной провинцией.
				local hasNeighbour = false
				for _, i in list do
					forNeighbours4(w, h, i, function(j)
						local o = buffer.readu16(province, j * 2)
						if o ~= 0 and o ~= id then
							hasNeighbour = true
						end
					end)
					if hasNeighbour then
						break
					end
				end
				if hasNeighbour then
					smallest, smallestSize = id, #list
				end
			end
		end
		if smallest ~= 0 then
			local shared: { [number]: number } = {}
			for _, i in members[smallest] do
				forNeighbours4(w, h, i, function(j)
					local o = buffer.readu16(province, j * 2)
					if o ~= 0 and o ~= smallest then
						shared[o] = (shared[o] or 0) + 1
					end
				end)
			end
			local target, best = 0, -1
			for o, count in shared do
				if count > best or (count == best and o < target) then
					target, best = o, count
				end
			end
			for _, i in members[smallest] do
				buffer.writeu16(province, i * 2, target)
				table.insert(members[target], i)
			end
			members[smallest] = nil
			changed = true
		end
	end

	-- Перенумерация 1..P по первой клетке (детерминированно).
	local remap: { [number]: number } = {}
	local count = 0
	for i = 0, n - 1 do
		local id = buffer.readu16(province, i * 2)
		if id ~= 0 then
			local newId = remap[id]
			if newId == nil then
				count += 1
				newId = count
				remap[id] = newId
			end
			buffer.writeu16(province, i * 2, newId)
		end
	end
	return count
end

-- Экспорт для тестов и инструментов.
MapGen.components = components
MapGen.distanceField = distanceField

-- Связные куски клеток со значением value в маске (4-соседство): метки (u32 на клетку), размеры и
-- касается ли кусок края карты. Нужно и генератору реальных карт (tools/realmap).
MapGen.components = components

return table.freeze(MapGen)
