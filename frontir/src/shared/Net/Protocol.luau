--!strict
--[[
	Protocol — бинарные сообщения сервер → клиент (GDD §12). Чистый модуль, тестируется в Lune.
	Все сообщения — buffer, первый байт — тип. Идут по одному RemoteEvent, поэтому порядок сохраняется.

	SNAPSHOT (1) — полный снимок владельцев клеток, частями не больше Config.Net.SnapshotPartBytes:
	  u8 тип, u32 тик, u16 номер части, u16 всего частей, u32 длина всех данных, данные части.
	  Данные: RLE владельцев — [varint длина серии][u16 владелец]...
	DELTA (2) — изменения за тик:
	  u8 тип, u32 тик, varint число клеток, затем по клеткам в порядке возрастания индекса:
	  varint (шаг от прошлой клетки × 2 + флаг «владелец тот же, что у прошлой»), [u16 владелец, если флаг 0].
	  Фронт атаки — это много соседних клеток одного владельца, поэтому клетка стоит ~1–2 байта.
	STATS (3) — всем, Config.Net.StatsHz раз в секунду: держава и атаки/фронты (HUD, лидеры, рисование фронтов):
	  u8 тип, f32 время тика (мс), u16 изменено клеток, u8 число держав,
	  по державе: u8 id, f32 люди, f32 максимум, u32 клеток, f32 люди в атаках, f32 сила гарнизона,
	  f32 сила на фронтах, u8 городов;
	  u16 число атак, по атаке: u8 атакующий, u8 цель, f32 люди, f32 сила войск, 4 × u8 доли типов (×255),
	  u8 флаги (бит 0 — снабжение, бит 1 — идёт бой), u8 перевес × 32 (255 — обороны нет).
	FORCES (5) — только владельцу, с той же частотой: свои войска по типам и очередь найма:
	  u8 тип, по типу (Types.LandUnits): f32 сила дома, f32 опыт дома, f32 сила на фронтах;
	  u8 длина очереди, по юниту: u8 тип, f32 осталось секунд.
]]

local Config = require("../Config")
local Types = require("../Types")

local Protocol = {}

Protocol.SNAPSHOT = 1
Protocol.DELTA = 2
Protocol.STATS = 3
Protocol.FORCES = 5

export type NationStats = {
	id: number,
	people: number,
	maxPeople: number,
	cells: number,
	troops: number,
	power: number, -- сила гарнизона
	frontPower: number, -- сила войск на фронтах
	cities: number,
}

export type AttackStats = {
	attacker: number,
	target: number,
	troops: number,
	power: number, -- сила войск атаки
	mix: { number }, -- доли типов войск (Types.LandUnits), сумма ≈ 1
	supplied: boolean,
	fighting: boolean,
	ratio: number, -- перевес (math.huge — обороны нет)
}

export type Stats = {
	tickMs: number,
	changed: number,
	nations: { NationStats },
	attacks: { AttackStats },
}

export type KindForces = { home: number, xp: number, front: number }
export type QueueItem = { kind: number, left: number }
export type MyForces = { kinds: { KindForces }, queue: { QueueItem } }

export type Delta = {
	tick: number,
	cells: { number },
	owners: { number },
}

export type SnapshotPart = {
	tick: number,
	part: number,
	parts: number,
	total: number,
	data: buffer,
}

-- Растущий буфер для записи.
type Writer = { buf: buffer, pos: number }

local function writer(initial: number): Writer
	return { buf = buffer.create(math.max(16, initial)), pos = 0 }
end

local function ensure(w: Writer, extra: number)
	local need = w.pos + extra
	local len = buffer.len(w.buf)
	if need <= len then
		return
	end
	local newLen = len
	while newLen < need do
		newLen *= 2
	end
	local b = buffer.create(newLen)
	buffer.copy(b, 0, w.buf, 0, w.pos)
	w.buf = b
end

local function u8(w: Writer, v: number)
	ensure(w, 1)
	buffer.writeu8(w.buf, w.pos, v)
	w.pos += 1
end

local function u16(w: Writer, v: number)
	ensure(w, 2)
	buffer.writeu16(w.buf, w.pos, v)
	w.pos += 2
end

local function u32(w: Writer, v: number)
	ensure(w, 4)
	buffer.writeu32(w.buf, w.pos, v)
	w.pos += 4
end

local function f32(w: Writer, v: number)
	ensure(w, 4)
	buffer.writef32(w.buf, w.pos, v)
	w.pos += 4
end

local function varint(w: Writer, v: number)
	while v >= 128 do
		u8(w, v % 128 + 128)
		v = v // 128
	end
	u8(w, v)
end

local function finish(w: Writer): buffer
	local out = buffer.create(w.pos)
	buffer.copy(out, 0, w.buf, 0, w.pos)
	return out
end

-- Чтение с проверкой границ: порченое сообщение — ошибка, а не мусор.
type Reader = { buf: buffer, pos: number, len: number }

local function reader(b: buffer, pos: number?): Reader
	return { buf = b, pos = pos or 0, len = buffer.len(b) }
end

local function need(r: Reader, n: number)
	if r.pos + n > r.len then
		error("Protocol: сообщение обрывается", 3)
	end
end

local function ru8(r: Reader): number
	need(r, 1)
	local v = buffer.readu8(r.buf, r.pos)
	r.pos += 1
	return v
end

local function ru16(r: Reader): number
	need(r, 2)
	local v = buffer.readu16(r.buf, r.pos)
	r.pos += 2
	return v
end

local function ru32(r: Reader): number
	need(r, 4)
	local v = buffer.readu32(r.buf, r.pos)
	r.pos += 4
	return v
end

local function rf32(r: Reader): number
	need(r, 4)
	local v = buffer.readf32(r.buf, r.pos)
	r.pos += 4
	return v
end

local function rvarint(r: Reader): number
	local value, mult = 0, 1
	while true do
		local b = ru8(r)
		value += (b % 128) * mult
		if b < 128 then
			return value
		end
		mult *= 128
		if mult > 2 ^ 35 then
			error("Protocol: слишком длинный varint", 3)
		end
	end
end

-- Тип сообщения (первый байт) или nil для пустого буфера.
function Protocol.kind(b: buffer): number?
	if buffer.len(b) == 0 then
		return nil
	end
	return buffer.readu8(b, 0)
end

-- SNAPSHOT ---------------------------------------------------------------------------------

-- Снимок владельцев (u16 на клетку, count клеток) → части сообщения.
function Protocol.encodeSnapshot(tick: number, owners: buffer, count: number): { buffer }
	local w = writer(1024)
	local i = 0
	while i < count do
		local value = buffer.readu16(owners, i * 2)
		local run = 1
		while i + run < count and buffer.readu16(owners, (i + run) * 2) == value do
			run += 1
		end
		varint(w, run)
		u16(w, value)
		i += run
	end
	local data = finish(w)
	local total = buffer.len(data)
	local partSize = Config.Net.SnapshotPartBytes
	local parts = math.max(1, math.ceil(total / partSize))
	local out: { buffer } = {}
	for p = 0, parts - 1 do
		local from = p * partSize
		local len = math.min(partSize, total - from)
		local m = buffer.create(13 + len)
		buffer.writeu8(m, 0, Protocol.SNAPSHOT)
		buffer.writeu32(m, 1, tick)
		buffer.writeu16(m, 5, p)
		buffer.writeu16(m, 7, parts)
		buffer.writeu32(m, 9, total)
		buffer.copy(m, 13, data, from, len)
		table.insert(out, m)
	end
	return out
end

function Protocol.decodeSnapshotPart(b: buffer): SnapshotPart
	local r = reader(b)
	if ru8(r) ~= Protocol.SNAPSHOT then
		error("Protocol: не снимок", 2)
	end
	local tick, part, parts, total = ru32(r), ru16(r), ru16(r), ru32(r)
	if parts == 0 or part >= parts then
		error("Protocol: неверный номер части снимка", 2)
	end
	local data = buffer.create(r.len - r.pos)
	buffer.copy(data, 0, b, r.pos, r.len - r.pos)
	return { tick = tick, part = part, parts = parts, total = total, data = data }
end

-- Сборщик снимка из частей. add() возвращает владельцев (u16 на клетку), когда собраны все части.
export type Assembler = { tick: number, parts: { [number]: buffer }, received: number, expected: number }

function Protocol.newAssembler(): Assembler
	return { tick = -1, parts = {}, received = 0, expected = 0 }
end

function Protocol.assemble(a: Assembler, part: SnapshotPart, count: number): buffer?
	if part.tick ~= a.tick then
		a.tick = part.tick
		a.parts = {}
		a.received = 0
		a.expected = part.parts
	end
	if a.parts[part.part] == nil then
		a.parts[part.part] = part.data
		a.received += 1
	end
	if a.received < a.expected then
		return nil
	end
	local total = 0
	for p = 0, a.expected - 1 do
		total += buffer.len(a.parts[p])
	end
	if total ~= part.total then
		error("Protocol: снимок собран не той длины", 2)
	end
	local data = buffer.create(total)
	local pos = 0
	for p = 0, a.expected - 1 do
		local chunk = a.parts[p]
		buffer.copy(data, pos, chunk, 0, buffer.len(chunk))
		pos += buffer.len(chunk)
	end
	local owners = buffer.create(count * 2)
	local r = reader(data)
	local i = 0
	while i < count do
		local run = rvarint(r)
		local value = ru16(r)
		if run == 0 or i + run > count then
			error("Protocol: серия снимка за пределами карты", 2)
		end
		for k = i, i + run - 1 do
			buffer.writeu16(owners, k * 2, value)
		end
		i += run
	end
	if r.pos ~= r.len then
		error("Protocol: лишние байты в снимке", 2)
	end
	a.parts = {}
	a.received = 0
	return owners
end

-- DELTA ------------------------------------------------------------------------------------

-- cells — индексы по возрастанию (как отдаёт Grid.takeChanges), owners — текущие владельцы сетки.
function Protocol.encodeDelta(tick: number, cells: { number }, owners: buffer): buffer
	local w = writer(16 + #cells * 2)
	u8(w, Protocol.DELTA)
	u32(w, tick)
	varint(w, #cells)
	local prev = -1
	local prevOwner = -1
	for _, i in cells do
		local owner = buffer.readu16(owners, i * 2)
		local gap = i - prev
		if owner == prevOwner then
			varint(w, gap * 2 + 1)
		else
			varint(w, gap * 2)
			u16(w, owner)
		end
		prev, prevOwner = i, owner
	end
	return finish(w)
end

function Protocol.decodeDelta(b: buffer, count: number): Delta
	local r = reader(b)
	if ru8(r) ~= Protocol.DELTA then
		error("Protocol: не дельта", 2)
	end
	local tick = ru32(r)
	local n = rvarint(r)
	if n > count then
		error("Protocol: в дельте больше клеток, чем на карте", 2)
	end
	local cells: { number } = table.create(n)
	local owners: { number } = table.create(n)
	local prev = -1
	local prevOwner = -1
	for _ = 1, n do
		local v = rvarint(r)
		local gap = v // 2
		if gap == 0 then
			error("Protocol: клетки дельты не по возрастанию", 2)
		end
		local i = prev + gap
		if i >= count then
			error("Protocol: клетка дельты за пределами карты", 2)
		end
		local owner = if v % 2 == 1 then prevOwner else ru16(r)
		if owner < 0 then
			error("Protocol: дельта начинается с «того же владельца»", 2)
		end
		table.insert(cells, i)
		table.insert(owners, owner)
		prev, prevOwner = i, owner
	end
	if r.pos ~= r.len then
		error("Protocol: лишние байты в дельте", 2)
	end
	return { tick = tick, cells = cells, owners = owners }
end

-- STATS ------------------------------------------------------------------------------------

local RATIO_SCALE = 32
local KINDS = #Types.LandUnits

function Protocol.encodeStats(s: Stats): buffer
	local w = writer(32 + #s.nations * 26 + #s.attacks * 16)
	u8(w, Protocol.STATS)
	f32(w, s.tickMs)
	u16(w, math.clamp(s.changed, 0, 65535))
	u8(w, #s.nations)
	for _, n in s.nations do
		u8(w, n.id)
		f32(w, n.people)
		f32(w, n.maxPeople)
		u32(w, n.cells)
		f32(w, n.troops)
		f32(w, n.power)
		f32(w, n.frontPower)
		u8(w, math.clamp(n.cities, 0, 255))
	end
	u16(w, math.min(#s.attacks, 65535))
	for k = 1, math.min(#s.attacks, 65535) do
		local a = s.attacks[k]
		u8(w, a.attacker)
		u8(w, a.target)
		f32(w, a.troops)
		f32(w, a.power)
		for kind = 1, KINDS do
			u8(w, math.clamp(math.round((a.mix[kind] or 0) * 255), 0, 255))
		end
		u8(w, (if a.supplied then 1 else 0) + (if a.fighting then 2 else 0))
		u8(w, if a.ratio == math.huge then 255 else math.clamp(math.round(a.ratio * RATIO_SCALE), 0, 254))
	end
	return finish(w)
end

function Protocol.decodeStats(b: buffer): Stats
	local r = reader(b)
	if ru8(r) ~= Protocol.STATS then
		error("Protocol: не статистика", 2)
	end
	local tickMs, changed = rf32(r), ru16(r)
	local nations: { NationStats } = {}
	-- Поля читаем по одному в локальные переменные: порядок чтения из буфера важен.
	for _ = 1, ru8(r) do
		local id = ru8(r)
		local people = rf32(r)
		local maxPeople = rf32(r)
		local cells = ru32(r)
		local troops = rf32(r)
		local power = rf32(r)
		local frontPower = rf32(r)
		local cities = ru8(r)
		table.insert(nations, {
			id = id,
			people = people,
			maxPeople = maxPeople,
			cells = cells,
			troops = troops,
			power = power,
			frontPower = frontPower,
			cities = cities,
		})
	end
	local attacks: { AttackStats } = {}
	for _ = 1, ru16(r) do
		local attacker = ru8(r)
		local target = ru8(r)
		local troops = rf32(r)
		local power = rf32(r)
		local mix: { number } = {}
		for kind = 1, KINDS do
			mix[kind] = ru8(r) / 255
		end
		local flags = ru8(r)
		local ratioByte = ru8(r)
		table.insert(attacks, {
			attacker = attacker,
			target = target,
			troops = troops,
			power = power,
			mix = mix,
			supplied = flags % 2 == 1,
			fighting = (flags // 2) % 2 == 1,
			ratio = if ratioByte == 255 then math.huge else ratioByte / RATIO_SCALE,
		})
	end
	if r.pos ~= r.len then
		error("Protocol: лишние байты в статистике", 2)
	end
	return { tickMs = tickMs, changed = changed, nations = nations, attacks = attacks }
end

-- FORCES -----------------------------------------------------------------------------------

function Protocol.encodeForces(f: MyForces): buffer
	local w = writer(8 + KINDS * 12 + #f.queue * 5)
	u8(w, Protocol.FORCES)
	for kind = 1, KINDS do
		local k = f.kinds[kind]
		f32(w, k.home)
		f32(w, k.xp)
		f32(w, k.front)
	end
	u8(w, math.min(#f.queue, 255))
	for i = 1, math.min(#f.queue, 255) do
		u8(w, f.queue[i].kind)
		f32(w, f.queue[i].left)
	end
	return finish(w)
end

function Protocol.decodeForces(b: buffer): MyForces
	local r = reader(b)
	if ru8(r) ~= Protocol.FORCES then
		error("Protocol: не войска", 2)
	end
	local kinds: { KindForces } = {}
	for kind = 1, KINDS do
		local home = rf32(r)
		local xp = rf32(r)
		local front = rf32(r)
		kinds[kind] = { home = home, xp = xp, front = front }
	end
	local queue: { QueueItem } = {}
	for _ = 1, ru8(r) do
		local kind = ru8(r)
		local left = rf32(r)
		if kind < 1 or kind > KINDS then
			error("Protocol: неизвестный тип юнита", 2)
		end
		table.insert(queue, { kind = kind, left = left })
	end
	if r.pos ~= r.len then
		error("Protocol: лишние байты в войсках", 2)
	end
	return { kinds = kinds, queue = queue }
end

return table.freeze(Protocol)
