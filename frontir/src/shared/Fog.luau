--!strict
--[[
	Fog — туман войны (GDD §6.11, §12, этап 7а). Чистый модуль: клиент считает свой обзор, сервер — грубый
	фильтр чужих фронтов (блоками), превью рисует карту так же, как клиент.

	Обзор (клиент): земля державы и её друзей (союзники, вассалы, сюзерен) + TerritoryVision клеток, их линии
	фронтов + ArmyVision, их радары + RadarVision. Расстояние — фаска 5/7 (почти круг): за шаг по стороне −5,
	по диагонали −7. Считается за два прохода (вперёд и назад) в прямоугольнике вокруг источников.

	Вне обзора клиент рисует последнего увиденного владельца (known) и темнее; seen — клетку хоть раз видели
	(здания там показываются).
]]

local Config = require("./Config")

local ORTHO, DIAG = 5, 7 -- цена шага фаски (×5 к клеткам)

export type FogState = {
	width: number,
	height: number,
	size: number,
	vision: buffer, -- u8: остаток обзора + 1 (0 — не видно); рабочий буфер
	visible: buffer, -- u8: 1 — клетка в обзоре
	known: buffer, -- u16: последний увиденный владелец
	seen: buffer, -- u8: 1 — клетку хоть раз видели
	-- Прямоугольник, где в прошлый раз были видимые клетки (вне его всё 0); x0 > x1 — пусто.
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	all: boolean, -- видно всё (зритель, туман выключен, не фаза игры); так начинается каждый матч
}

-- Что даёт обзор. friends — набор держав (сама держава, союзники, вассалы, сюзерен);
-- fronts — пары (наша, чужая): клетки нашей у границы с чужой — линия фронта; radars — клетки радаров друзей.
export type Sources = {
	friends: { [number]: boolean },
	fronts: { { mine: number, other: number } },
	radars: { number },
	ships: { number }?, -- клетки кораблей друзей (обзор Naval.ShipVision, этап 7б-1)
}

local Fog = {}

function Fog.new(width: number, height: number): FogState
	local size = width * height
	return {
		width = width,
		height = height,
		size = size,
		vision = buffer.create(size),
		visible = buffer.create(size),
		known = buffer.create(size * 2),
		seen = buffer.create(size),
		x0 = 1,
		y0 = 1,
		x1 = 0,
		y1 = 0,
		all = true,
	}
end

function Fog.isVisible(fs: FogState, i: number): boolean
	return fs.all or buffer.readu8(fs.visible, i) == 1
end

function Fog.wasSeen(fs: FogState, i: number): boolean
	return fs.all or buffer.readu8(fs.seen, i) == 1
end

function Fog.knownOwner(fs: FogState, i: number): number
	return buffer.readu16(fs.known, i * 2)
end

-- Видно всё: known = настоящие владельцы. Возвращает true, если режим сменился (перерисовать всю карту).
function Fog.revealAll(fs: FogState, owners: buffer): boolean
	if fs.all then
		return false
	end
	buffer.copy(fs.known, 0, owners, 0, fs.size * 2)
	buffer.fill(fs.seen, 0, 1)
	fs.all = true
	return true
end

-- Дельта сетки: в обзоре known обновляется сразу. Возвращает клетки, которые надо перерисовать.
function Fog.applyDelta(fs: FogState, owners: buffer, cells: { number }): { number }
	local out: { number } = {}
	for _, i in cells do
		if fs.all or buffer.readu8(fs.visible, i) == 1 then
			local o = buffer.readu16(owners, i * 2)
			if buffer.readu16(fs.known, i * 2) ~= o then
				buffer.writeu16(fs.known, i * 2, o)
				table.insert(out, i)
			end
		end
	end
	return out
end

-- Пересчёт обзора. Возвращает: перерисовать всю карту (было «видно всё») и клетки, у которых сменилась
-- видимость или известный владелец (после «видно всё» список пустой — перерисовывается всё).
function Fog.compute(fs: FogState, owners: buffer, sources: Sources): (boolean, { number })
	local w, h, size = fs.width, fs.height, fs.size
	local cfg = Config.Fog
	local vision = fs.vision
	local friends = sources.friends
	local territory = cfg.TerritoryVision * ORTHO + 1
	local army = cfg.ArmyVision * ORTHO + 1
	local radar = cfg.RadarVision * ORTHO + 1
	local reach = math.max(cfg.TerritoryVision, cfg.ArmyVision, cfg.RadarVision)

	-- Флаги владельцев: 1 — друг, 2 — друг с фронтом; пары фронта — по ключу mine * 65536 + other.
	local flag: { [number]: number } = {}
	for id in friends do
		flag[id] = 1
	end
	local frontPair: { [number]: boolean } = {}
	for _, f in sources.fronts do
		if friends[f.mine] then
			flag[f.mine] = 2
			frontPair[f.mine * 65536 + f.other] = true
		end
	end

	-- 1. Источники и прямоугольник вокруг них. Старые значения обнуляем только в прошлом прямоугольнике.
	if fs.x0 <= fs.x1 then
		for y = fs.y0, fs.y1 do
			buffer.fill(vision, y * w + fs.x0, 0, fs.x1 - fs.x0 + 1)
		end
	end
	local bx0, by0, bx1, by1 = w, h, -1, -1
	for i = 0, size - 1 do
		local o = buffer.readu16(owners, i * 2)
		if o ~= 0 then
			local f = flag[o]
			if f ~= nil then
				local v = territory
				if f == 2 then
					-- Клетка у границы с тем, с кем идёт бой, — линия фронта.
					local x, key = i % w, o * 65536
					if
						(x > 0 and frontPair[key + buffer.readu16(owners, (i - 1) * 2)])
						or (x < w - 1 and frontPair[key + buffer.readu16(owners, (i + 1) * 2)])
						or (i >= w and frontPair[key + buffer.readu16(owners, (i - w) * 2)])
						or (i + w < size and frontPair[key + buffer.readu16(owners, (i + w) * 2)])
					then
						v = army
					end
				end
				buffer.writeu8(vision, i, v)
				local x, y = i % w, i // w
				if x < bx0 then
					bx0 = x
				end
				if x > bx1 then
					bx1 = x
				end
				if y < by0 then
					by0 = y
				end
				if y > by1 then
					by1 = y
				end
			end
		end
	end
	local function point(cell: number, value: number)
		if cell >= 0 and cell < size then
			buffer.writeu8(vision, cell, math.max(buffer.readu8(vision, cell), value))
			local x, y = cell % w, cell // w
			bx0, by0 = math.min(bx0, x), math.min(by0, y)
			bx1, by1 = math.max(bx1, x), math.max(by1, y)
		end
	end
	for _, cell in sources.radars do
		point(cell, radar)
	end
	local shipValue = Config.Naval.ShipVision * ORTHO + 1
	local ships: { number } = sources.ships or {}
	for _, cell in ships do
		point(cell, shipValue)
	end
	if bx1 >= 0 then
		bx0, by0 = math.max(0, bx0 - reach), math.max(0, by0 - reach)
		bx1, by1 = math.min(w - 1, bx1 + reach), math.min(h - 1, by1 + reach)
	end

	-- 2. Фаска: проход вперёд (сверху-слева) и назад (снизу-справа) в прямоугольнике.
	if bx1 >= 0 then
		for y = by0, by1 do
			local row = y * w
			for x = bx0, bx1 do
				local i = row + x
				local v = buffer.readu8(vision, i)
				if x > bx0 then
					local n = buffer.readu8(vision, i - 1) - ORTHO
					if n > v then
						v = n
					end
				end
				if y > by0 then
					local n = buffer.readu8(vision, i - w) - ORTHO
					if n > v then
						v = n
					end
					if x > bx0 then
						n = buffer.readu8(vision, i - w - 1) - DIAG
						if n > v then
							v = n
						end
					end
					if x < bx1 then
						n = buffer.readu8(vision, i - w + 1) - DIAG
						if n > v then
							v = n
						end
					end
				end
				if v > 0 then
					buffer.writeu8(vision, i, v)
				end
			end
		end
		for y = by1, by0, -1 do
			local row = y * w
			for x = bx1, bx0, -1 do
				local i = row + x
				local v = buffer.readu8(vision, i)
				if x < bx1 then
					local n = buffer.readu8(vision, i + 1) - ORTHO
					if n > v then
						v = n
					end
				end
				if y < by1 then
					local n = buffer.readu8(vision, i + w) - ORTHO
					if n > v then
						v = n
					end
					if x < bx1 then
						n = buffer.readu8(vision, i + w + 1) - DIAG
						if n > v then
							v = n
						end
					end
					if x > bx0 then
						n = buffer.readu8(vision, i + w - 1) - DIAG
						if n > v then
							v = n
						end
					end
				end
				if v > 0 then
					buffer.writeu8(vision, i, v)
				end
			end
		end
	end

	-- 3. Сравнить с прошлым обзором в объединении прямоугольников; обновить known и seen.
	-- После «видно всё» — вся карта: visible там ещё прошлый, известный владелец уже настоящий.
	local changed: { number } = {}
	local wasAll = fs.all
	fs.all = false
	local ux0, uy0, ux1, uy1
	if wasAll then
		ux0, uy0, ux1, uy1 = 0, 0, w - 1, h - 1
	elseif fs.x0 > fs.x1 then
		ux0, uy0, ux1, uy1 = bx0, by0, bx1, by1
	elseif bx1 < 0 then
		ux0, uy0, ux1, uy1 = fs.x0, fs.y0, fs.x1, fs.y1
	else
		ux0, uy0 = math.min(fs.x0, bx0), math.min(fs.y0, by0)
		ux1, uy1 = math.max(fs.x1, bx1), math.max(fs.y1, by1)
	end
	if ux1 >= ux0 then
		local visible, known, seen = fs.visible, fs.known, fs.seen
		for y = uy0, uy1 do
			local row = y * w
			for x = ux0, ux1 do
				local i = row + x
				local now = if x >= bx0
						and x <= bx1
						and y >= by0
						and y <= by1
						and buffer.readu8(vision, i) > 0
					then 1
					else 0
				local flip = now ~= buffer.readu8(visible, i)
				if flip then
					buffer.writeu8(visible, i, now)
				end
				if now == 1 then
					buffer.writeu8(seen, i, 1)
					local o = buffer.readu16(owners, i * 2)
					if buffer.readu16(known, i * 2) ~= o then
						buffer.writeu16(known, i * 2, o)
						flip = true
					end
				end
				if flip and not wasAll then
					table.insert(changed, i)
				end
			end
		end
	end
	fs.x0, fs.y0, fs.x1, fs.y1 = bx0, by0, bx1, by1
	if bx1 < 0 then
		fs.x0, fs.y0, fs.x1, fs.y1 = 1, 1, 0, 0
	end
	return wasAll, changed
end

-- Сервер (§12): грубый обзор блоками BlockSize. Блоки с пограничными клетками друзей — с соседями на
-- ceil(ArmyVision / BlockSize) блоков, блоки радаров — на ceil(RadarVision / BlockSize). Возвращает набор блоков.
function Fog.visionBlocks(
	width: number,
	height: number,
	borderCells: { { [number]: boolean } },
	radars: { number },
	ships: { number }?
): { [number]: boolean }
	local cfg = Config.Fog
	local bs = cfg.BlockSize
	local bw, bh = math.ceil(width / bs), math.ceil(height / bs)
	local base: { [number]: number } = {} -- блок → радиус расширения в блоках
	local near = math.ceil(math.max(cfg.TerritoryVision, cfg.ArmyVision) / bs)
	local far = math.ceil(cfg.RadarVision / bs)
	for _, set in borderCells do
		for i in set do
			local b = (i // width) // bs * bw + (i % width) // bs
			if (base[b] or -1) < near then
				base[b] = near
			end
		end
	end
	for _, i in radars do
		local b = (i // width) // bs * bw + (i % width) // bs
		if (base[b] or -1) < far then
			base[b] = far
		end
	end
	local shipReach = math.ceil(Config.Naval.ShipVision / bs)
	local shipCells: { number } = ships or {}
	for _, i in shipCells do
		local b = (i // width) // bs * bw + (i % width) // bs
		if (base[b] or -1) < shipReach then
			base[b] = shipReach
		end
	end
	local out: { [number]: boolean } = {}
	for b, r in base do
		local bx, by = b % bw, b // bw
		for y = math.max(0, by - r), math.min(bh - 1, by + r) do
			for x = math.max(0, bx - r), math.min(bw - 1, bx + r) do
				out[y * bw + x] = true
			end
		end
	end
	return out
end

-- Блок клетки (для проверки линии фронта по visionBlocks).
function Fog.blockOf(width: number, i: number): number
	local bs = Config.Fog.BlockSize
	local bw = math.ceil(width / bs)
	return (i // width) // bs * bw + (i % width) // bs
end

-- Линия фронта в грубом обзоре: хоть одна клетка из выборки в видимом блоке.
function Fog.lineVisible(width: number, blocks: { [number]: boolean }, line: { number }?): boolean
	if line == nil then
		return false
	end
	for _, i in line do
		if blocks[Fog.blockOf(width, i)] then
			return true
		end
	end
	return false
end

return table.freeze(Fog)
