--!strict
--[[
	ClientState — что клиент знает о матче: копия владельцев клеток, державы, фаза, статистика.
	Собирается только из сообщений сервера (Net/Protocol + таблица info), поэтому у всех клиентов
	одинаковые границы (критерий этапа 2). Чистый модуль: тест прогоняет матч через сериализацию
	и сравнивает копию клиента с сеткой сервера побайтно.
]]

local Config = require("./Config")
local Protocol = require("./Net/Protocol")
local Types = require("./Types")

export type NationInfo = {
	id: number,
	name: string,
	nameEn: string,
	colorIndex: number,
	capital: number?,
	isBot: boolean,
	alive: boolean,
}

-- Таблица, которую сервер шлёт при смене фазы и состава держав.
export type Info = {
	kind: "info",
	phase: Types.Phase,
	phaseLeft: number, -- секунд до конца фазы выбора
	time: number, -- секунд с начала игры
	myNation: number?, -- держава этого игрока (nil — зритель)
	nations: { NationInfo },
	cities: { number }?, -- клетки городов (владелец — по сетке)
}

-- Армия на клиенте: текущая позиция с сервера и предыдущая — для плавного движения между тиками.
export type ClientArmy = Protocol.ArmyView & {
	prevX: number,
	prevY: number,
	updatedAt: number,
}

export type ApplyResult = "snapshot" | "delta" | "stats" | "armies" | "partial" | "ignored"

export type ClientState = {
	width: number,
	height: number,
	size: number,
	owners: buffer,
	hasSnapshot: boolean,
	snapshotTick: number,
	assembler: Protocol.Assembler,
	nations: { [number]: NationInfo },
	phase: Types.Phase,
	phaseEndsAt: number, -- по часам клиента
	timeAt: number, -- момент (часы клиента), когда пришло time
	time: number,
	myNation: number?,
	stats: Protocol.Stats?,
	cities: { number },
	armies: { [number]: ClientArmy },
}

local ClientState = {}

function ClientState.new(width: number, height: number): ClientState
	return {
		width = width,
		height = height,
		size = width * height,
		owners = buffer.create(width * height * 2),
		hasSnapshot = false,
		snapshotTick = -1,
		assembler = Protocol.newAssembler(),
		nations = {},
		phase = "Waiting",
		phaseEndsAt = 0,
		timeAt = 0,
		time = 0,
		myNation = nil,
		stats = nil,
		cities = {},
		armies = {},
	}
end

function ClientState.ownerAt(cs: ClientState, i: number): number
	return buffer.readu16(cs.owners, i * 2)
end

-- Индекс цвета державы (1..24) или 0, если цвета ещё нет.
function ClientState.colorIndexOf(cs: ClientState, owner: number): number
	local n = cs.nations[owner]
	return if n ~= nil then n.colorIndex else 0
end

-- Применяет info. Возвращает true, если поменялись цвета держав (нужна полная перерисовка).
function ClientState.applyInfo(cs: ClientState, info: Info, now: number): boolean
	local colorsChanged = false
	local fresh: { [number]: NationInfo } = {}
	for _, n in info.nations do
		local old = cs.nations[n.id]
		if old == nil or old.colorIndex ~= n.colorIndex then
			colorsChanged = true
		end
		fresh[n.id] = n
	end
	cs.nations = fresh
	cs.phase = info.phase
	cs.phaseEndsAt = now + info.phaseLeft
	cs.time = info.time
	cs.timeAt = now
	cs.myNation = info.myNation
	if info.cities ~= nil then
		cs.cities = info.cities
	end
	return colorsChanged
end

-- Применяет бинарное сообщение. Возвращает, что это было, и изменённые клетки (для дельты).
-- now — часы клиента (для плавного движения армий).
function ClientState.applyBuffer(cs: ClientState, b: buffer, now: number?): (ApplyResult, { number }?)
	local kind = Protocol.kind(b)
	if kind == Protocol.ARMIES then
		local _, list = Protocol.decodeArmies(b)
		local t = now or 0
		local fresh: { [number]: ClientArmy } = {}
		for _, a in list do
			local old = cs.armies[a.id]
			local army = a :: ClientArmy
			-- Плавно едем от того места, где армия сейчас нарисована.
			if old ~= nil then
				army.prevX, army.prevY = ClientState.armyPosition(old, t)
			else
				army.prevX, army.prevY = a.x, a.y
			end
			army.updatedAt = t
			fresh[a.id] = army
		end
		cs.armies = fresh
		return "armies", nil
	end
	if kind == Protocol.SNAPSHOT then
		local owners = Protocol.assemble(cs.assembler, Protocol.decodeSnapshotPart(b), cs.size)
		if owners == nil then
			return "partial", nil
		end
		cs.owners = owners
		cs.hasSnapshot = true
		cs.snapshotTick = cs.assembler.tick
		return "snapshot", nil
	elseif kind == Protocol.DELTA then
		local d = Protocol.decodeDelta(b, cs.size)
		if not cs.hasSnapshot or d.tick <= cs.snapshotTick then
			return "ignored", nil -- изменения уже вошли в снимок
		end
		for k, i in d.cells do
			buffer.writeu16(cs.owners, i * 2, d.owners[k])
		end
		return "delta", d.cells
	elseif kind == Protocol.STATS then
		cs.stats = Protocol.decodeStats(b)
		return "stats", nil
	end
	return "ignored", nil
end

-- Позиция армии в момент now: от предыдущей к текущей за один тик сервера.
function ClientState.armyPosition(a: ClientArmy, now: number): (number, number)
	local f = math.clamp((now - a.updatedAt) * Config.Sim.TickRate, 0, 1)
	return a.prevX + (a.x - a.prevX) * f, a.prevY + (a.y - a.prevY) * f
end

-- Статистика державы из последнего сообщения STATS.
function ClientState.statsOf(cs: ClientState, nationId: number): Protocol.NationStats?
	local s = cs.stats
	if s == nil then
		return nil
	end
	for _, n in s.nations do
		if n.id == nationId then
			return n
		end
	end
	return nil
end

return table.freeze(ClientState)
