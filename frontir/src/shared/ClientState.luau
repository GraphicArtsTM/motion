--!strict
--[[
	ClientState — что клиент знает о матче: копия владельцев клеток, державы, фаза, статистика.
	Собирается только из сообщений сервера (Net/Protocol + таблица info), поэтому у всех клиентов
	одинаковые границы (критерий этапа 2). Чистый модуль: тест прогоняет матч через сериализацию
	и сравнивает копию клиента с сеткой сервера побайтно.
]]

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
}

export type ApplyResult = "snapshot" | "delta" | "stats" | "partial" | "ignored"

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
	return colorsChanged
end

-- Применяет бинарное сообщение. Возвращает, что это было, и изменённые клетки (для дельты).
function ClientState.applyBuffer(cs: ClientState, b: buffer): (ApplyResult, { number }?)
	local kind = Protocol.kind(b)
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
