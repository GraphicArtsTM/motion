--!strict
--!native
--[[
	Flood — режим «Потоп» (GDD §5.3, этап 8в). Чистый модуль, одинаковый на сервере, клиенте и в превью:
	- levels(map): «высота» клетки суши — взвешенное расстояние до воды (×10, u16): равнина, пустыня, река — 10
	  за клетку, тундра — 12, лес — 15, холмы — 30; горы не тонут (NEVER). Вода — 0. Алгоритм Дейкстры с
	  корзинами (веса — малые целые), считается один раз на карту.
	- threshold(width, step): до какой высоты вода дошла на ступени step (на картах шире 512 — больше).
	- sinking(levels, width, from, to): клетки, которые уходят под воду при подъёме со ступени from на to.
	Сама карта не меняется: утонувшие клетки сервер делает ничьими и незахватываемыми, клиент красит водой.
]]

local Config = require("./Config")
local MapData = require("./MapData")
local Palette = require("./Palette")

type MapData = MapData.MapData

local Flood = {}

Flood.NEVER = 65535

local cache: { [MapData]: buffer } = setmetatable({}, { __mode = "k" }) :: any

-- Высоты всех клеток (u16 на клетку). Кешируется на карту.
function Flood.levels(map: MapData): buffer
	local cached = cache[map]
	if cached ~= nil then
		return cached
	end
	local w, h = map.width, map.height
	local size = w * h
	local levels = buffer.create(size * 2)
	buffer.fill(levels, 0, 255)
	local cost: { [number]: number } = Config.Flood.Cost
	local maxCost = 0
	for _, c in cost do
		maxCost = math.max(maxCost, c)
	end
	-- Корзины по расстоянию по модулю (maxCost + 1): в каждой — список клеток.
	local ring = maxCost + 1
	local buckets: { { number } } = {}
	for k = 1, ring do
		buckets[k] = {}
	end
	local pending = 0
	local terrain = map.terrain
	for i = 0, size - 1 do
		if buffer.readu8(terrain, i) == 0 then
			buffer.writeu16(levels, i * 2, 0)
			table.insert(buckets[1], i)
			pending += 1
		end
	end
	local d = 0
	while pending > 0 do
		local bucket = buckets[d % ring + 1]
		local k = 1
		while k <= #bucket do
			local i = bucket[k]
			k += 1
			if buffer.readu16(levels, i * 2) == d then
				local x = i % w
				for n = 1, 4 do
					local j = if n == 1
						then (if x > 0 then i - 1 else -1)
						elseif n == 2 then (if x < w - 1 then i + 1 else -1)
						elseif n == 3 then i - w
						else i + w
					if j >= 0 and j < size then
						local c = cost[buffer.readu8(terrain, j)]
						if c ~= nil then
							local nd = math.min(d + c, Flood.NEVER - 1)
							if nd < buffer.readu16(levels, j * 2) then
								buffer.writeu16(levels, j * 2, nd)
								table.insert(buckets[nd % ring + 1], j)
								pending += 1
							end
						end
					end
				end
			end
		end
		pending -= #bucket
		table.clear(bucket)
		d += 1
	end
	cache[map] = levels
	return levels
end

-- До какой высоты дошла вода на ступени step.
function Flood.threshold(width: number, step: number): number
	return step * Config.Flood.StepCells * 10 * math.max(1, width / 512)
end

-- Клетки суши, которые уходят под воду при подъёме со ступени from на to (from < to).
function Flood.sinking(levels: buffer, width: number, from: number, to: number): { number }
	local lo, hi = Flood.threshold(width, from), Flood.threshold(width, to)
	local out: { number } = {}
	for i = 0, buffer.len(levels) // 2 - 1 do
		local v = buffer.readu16(levels, i * 2)
		if v > lo and v <= hi and v ~= 0 then
			table.insert(out, i)
		end
	end
	return out
end

-- Красит утонувшие клетки (ступени from → to) водой в буфере цветов карты (RGBA, как MapPaint.paint).
-- Возвращает эти клетки — клиенту перерисовать, превью — ничего.
function Flood.paint(colors: buffer, levels: buffer, width: number, from: number, to: number): { number }
	local water = Palette.rgb("Shallows")
	local cells = Flood.sinking(levels, width, from, to)
	for _, i in cells do
		local o = i * 4
		buffer.writeu8(colors, o, water.r)
		buffer.writeu8(colors, o + 1, water.g)
		buffer.writeu8(colors, o + 2, water.b)
	end
	return cells
end

return table.freeze(Flood)
