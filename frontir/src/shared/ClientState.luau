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
	cities: { number }?, -- клетки городов (владелец — по сетке)
	buildings: { Types.Building }?, -- все здания и уровни городов (§6.9)
	matchId: number?, -- новый матч — клиент сбрасывает состояние
	targetNations: number?,
	timeLimit: number?, -- лимит времени матча, с
	result: Types.MatchResult?, -- итог (фаза Over)
}

export type ApplyResult = "snapshot" | "delta" | "stats" | "forces" | "wars" | "partial" | "ignored"

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
	myForces: Protocol.MyForces?, -- свои войска (только у игрока с державой)
	wars: Protocol.WarsMessage, -- войны и запреты после мира (§6.7а)
	buildings: { [number]: Types.Building }, -- клетка → здание (владелец — по сетке)
	warsAt: number, -- когда пришли wars (часы клиента; для обратных отсчётов)
	bytes: number, -- принято байт с начала (для F3: байт/с)
	matchId: number,
	targetNations: number,
	timeLimit: number,
	result: Types.MatchResult?,
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
		myForces = nil,
		wars = { wars = {}, cooldowns = {} },
		buildings = {},
		matchId = 0,
		targetNations = 0,
		timeLimit = 0,
		result = nil,
		warsAt = 0,
		bytes = 0,
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
-- Новый матч (другой matchId) — сетка, статистика, войны, здания и войска сбрасываются.
function ClientState.applyInfo(cs: ClientState, info: Info, now: number): boolean
	local colorsChanged = false
	if info.matchId ~= nil and info.matchId ~= cs.matchId then
		if cs.matchId ~= 0 then
			buffer.fill(cs.owners, 0, 0)
			cs.hasSnapshot = false
			cs.snapshotTick = -1
			cs.assembler = Protocol.newAssembler()
			cs.stats = nil
			cs.myForces = nil
			cs.wars = { wars = {}, cooldowns = {} }
			table.clear(cs.buildings)
			colorsChanged = true
		end
		cs.matchId = info.matchId
	end
	cs.targetNations = info.targetNations or cs.targetNations
	cs.timeLimit = info.timeLimit or cs.timeLimit
	cs.result = info.result
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
	if info.buildings ~= nil then
		table.clear(cs.buildings)
		ClientState.applyBuildings(cs, info.buildings)
	end
	return colorsChanged
end

-- Применяет бинарное сообщение. Возвращает, что это было, и изменённые клетки (для дельты).
function ClientState.applyBuffer(cs: ClientState, b: buffer): (ApplyResult, { number }?)
	local kind = Protocol.kind(b)
	cs.bytes += buffer.len(b)
	if kind == Protocol.FORCES then
		cs.myForces = Protocol.decodeForces(b)
		return "forces", nil
	end
	if kind == Protocol.WARS then
		cs.wars = Protocol.decodeWars(b)
		return "wars", nil
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

-- Война между a и b (в мобилизации или идущая) или nil.
function ClientState.warBetween(cs: ClientState, a: number, b: number): Protocol.WarStats?
	for _, war in cs.wars.wars do
		if (war.a == a and war.b == b) or (war.a == b and war.b == a) then
			return war
		end
	end
	return nil
end

-- Войны державы.
function ClientState.warsOf(cs: ClientState, nation: number): { Protocol.WarStats }
	local out: { Protocol.WarStats } = {}
	for _, war in cs.wars.wars do
		if war.a == nation or war.b == nation then
			table.insert(out, war)
		end
	end
	return out
end

-- Сколько секунд (на момент прихода сообщения) a и b ещё не могут объявить друг другу войну.
function ClientState.cooldownBetween(cs: ClientState, a: number, b: number): number
	for _, c in cs.wars.cooldowns do
		if (c.a == a and c.b == b) or (c.a == b and c.b == a) then
			return c.left
		end
	end
	return 0
end

-- Новые здания (сообщение buildings или полный список из info). Неверные записи пропускаются.
function ClientState.applyBuildings(cs: ClientState, list: { any })
	for _, b in list do
		if
			type(b) == "table"
			and type(b.cell) == "number"
			and type(b.kind) == "string"
			and type(b.level) == "number"
		then
			cs.buildings[b.cell] = { kind = b.kind :: Types.BuildingKind, cell = b.cell, level = b.level }
		end
	end
end

-- Уровень города в клетке (1, если не улучшали).
function ClientState.cityLevel(cs: ClientState, cell: number): number
	local b = cs.buildings[cell]
	return if b ~= nil and b.kind == "City" then b.level else 1
end

return table.freeze(ClientState)
