--!strict
--[[
	Wars — войны и мир между державами (GDD §6.7а). Чистый модуль: состояние войн, мобилизация, журнал
	захваченной в войне земли, потери, предложения мира, запрет на новую войну после мира, усталость.
	Решения (кто может объявить, что делать с фронтами) принимает MatchSim.

	- Между державами по умолчанию мир. declare → мобилизация Config.War.MobilizationSec → активная война.
	- Журнал taken: клетка → прежний владелец для клеток, взятых в этой войне одной стороной у другой.
	  Белый мир возвращает такие клетки, «забрать захваченное» — оставляет.
	- После мира пара не может снова объявить войну Config.War.PeaceCooldownSec секунд.
	- Усталость: через WearinessAfterSec самой долгой текущей войны — штраф к приросту людей.
	Время — игровое (simTime), поэтому всё ускоряется вместе с Match.Speed.
]]

local Config = require("./Config")
local Grid = require("./Grid")
local Types = require("./Types")

type Grid = Grid.Grid

export type WarState = "mobilizing" | "active"
export type PeaceTerms = Types.PeaceTerms

export type Proposal = {
	from: number,
	terms: PeaceTerms,
	madeAt: number, -- simTime
	expiresAt: number,
}

export type War = {
	a: number, -- кто объявил
	b: number,
	state: WarState,
	declaredAt: number, -- simTime
	activeAt: number, -- simTime конца мобилизации
	taken: { [number]: number }, -- клетка → прежний владелец (a или b)
	lossesA: number, -- силы потеряно стороной a
	lossesB: number,
	proposal: Proposal?,
	lastProposal: { [number]: number }, -- держава → simTime её последнего предложения мира
}

export type WarSet = {
	list: { War },
	byPair: { [number]: War },
	cooldown: { [number]: number }, -- пара → simTime, до которого нельзя объявить войну
}

local Wars = {}

local function pairKey(a: number, b: number): number
	return math.min(a, b) * 65536 + math.max(a, b)
end

function Wars.new(): WarSet
	return { list = {}, byPair = {}, cooldown = {} }
end

-- Война между a и b (в мобилизации или идущая) или nil.
function Wars.find(ws: WarSet, a: number, b: number): War?
	return ws.byPair[pairKey(a, b)]
end

-- Идёт ли между a и b активная война (мобилизация закончилась): можно открывать фронты.
function Wars.isActive(ws: WarSet, a: number, b: number): boolean
	local w = ws.byPair[pairKey(a, b)]
	return w ~= nil and w.state == "active"
end

-- Сколько ещё секунд a и b не могут объявить друг другу войну после мира.
function Wars.cooldownLeft(ws: WarSet, a: number, b: number, now: number): number
	local untilTime = ws.cooldown[pairKey(a, b)]
	return if untilTime ~= nil then math.max(0, untilTime - now) else 0
end

-- Можно ли a объявить войну b сейчас. Причина отказа — код для клиента (reject.*).
function Wars.canDeclare(ws: WarSet, a: number, b: number, now: number): (boolean, string?)
	if a == b then
		return false, "self"
	end
	if Wars.find(ws, a, b) ~= nil then
		return false, "alreadyAtWar"
	end
	if Wars.cooldownLeft(ws, a, b, now) > 0 then
		return false, "peaceCooldown"
	end
	return true, nil
end

function Wars.declare(ws: WarSet, a: number, b: number, now: number): War
	local war: War = {
		a = a,
		b = b,
		state = "mobilizing",
		declaredAt = now,
		activeAt = now + Config.War.MobilizationSec,
		taken = {},
		lossesA = 0,
		lossesB = 0,
		proposal = nil,
		lastProposal = {},
	}
	table.insert(ws.list, war)
	ws.byPair[pairKey(a, b)] = war
	return war
end

-- Сторона войны, противоположная nation.
function Wars.enemyOf(war: War, nation: number): number
	return if war.a == nation then war.b else war.a
end

-- Шаг времени: кончилась мобилизация — война становится активной; истёкшие предложения мира снимаются.
-- Возвращает войны, которые только что начались, и войны, где предложение истекло (с этим предложением).
function Wars.update(ws: WarSet, now: number): ({ War }, { { war: War, proposal: Proposal } })
	local started: { War } = {}
	local expired: { { war: War, proposal: Proposal } } = {}
	for _, war in ws.list do
		if war.state == "mobilizing" and now >= war.activeAt then
			war.state = "active"
			table.insert(started, war)
		end
		local p = war.proposal
		if p ~= nil and now >= p.expiresAt then
			war.proposal = nil
			table.insert(expired, { war = war, proposal = p })
		end
	end
	return started, expired
end

-- Журнал захвата: клетка cell перешла от old к new. Если между ними война — запоминаем прежнего владельца;
-- клетка вернулась к прежнему владельцу — забываем.
function Wars.record(ws: WarSet, cell: number, old: number, new: number)
	if old == 0 or new == 0 then
		return
	end
	local war = ws.byPair[pairKey(old, new)]
	if war == nil then
		return
	end
	local original = war.taken[cell]
	if original == nil then
		war.taken[cell] = old
	elseif original == new then
		war.taken[cell] = nil
	end
end

-- Потери силы стороной nation в войне.
function Wars.addLosses(war: War, nation: number, lost: number)
	if lost <= 0 then
		return
	end
	if nation == war.a then
		war.lossesA += lost
	elseif nation == war.b then
		war.lossesB += lost
	end
end

-- Сколько клеток взято в этой войне и сейчас удерживается: a у b и b у a.
function Wars.takenCells(war: War, g: Grid): (number, number)
	local byA, byB = 0, 0
	for cell, original in war.taken do
		local owner = Grid.getOwner(g, cell)
		if original == war.b and owner == war.a then
			byA += 1
		elseif original == war.a and owner == war.b then
			byB += 1
		end
	end
	return byA, byB
end

-- Белый мир: клетки, взятые в войне и всё ещё удерживаемые захватчиком, возвращаются прежнему владельцу
-- (если он жив — alive(id)). Возвращает число возвращённых клеток.
function Wars.returnTaken(war: War, g: Grid, alive: (id: number) -> boolean): number
	local cells: { number } = {}
	for cell in war.taken do
		table.insert(cells, cell)
	end
	table.sort(cells) -- детерминированный порядок
	local count = 0
	for _, cell in cells do
		local original = war.taken[cell]
		local captor = Wars.enemyOf(war, original)
		if Grid.getOwner(g, cell) == captor and alive(original) then
			Grid.setOwner(g, cell, original)
			count += 1
		end
	end
	table.clear(war.taken)
	return count
end

-- Конец войны: убрать её и (если cooldown) запретить новую войну этой паре на PeaceCooldownSec.
function Wars.finish(ws: WarSet, war: War, now: number, cooldown: boolean)
	local key = pairKey(war.a, war.b)
	ws.byPair[key] = nil
	local i = table.find(ws.list, war)
	if i ~= nil then
		table.remove(ws.list, i)
	end
	if cooldown then
		ws.cooldown[key] = now + Config.War.PeaceCooldownSec
	end
end

-- Все войны державы (для выбывания и ботов).
function Wars.of(ws: WarSet, nation: number): { War }
	local out: { War } = {}
	for _, war in ws.list do
		if war.a == nation or war.b == nation then
			table.insert(out, war)
		end
	end
	return out
end

-- Штраф усталости к приросту людей (0..WearinessMaxPenalty) по самой долгой активной войне державы.
function Wars.weariness(ws: WarSet, nation: number, now: number): number
	local cfg = Config.War
	local longest = 0
	for _, war in ws.list do
		if war.state == "active" and (war.a == nation or war.b == nation) then
			longest = math.max(longest, now - war.activeAt)
		end
	end
	if longest < cfg.WearinessAfterSec then
		return 0
	end
	local minutes = (longest - cfg.WearinessAfterSec) / 60
	return math.min(cfg.WearinessMaxPenalty, cfg.WearinessPenalty + cfg.WearinessPenaltyPerMin * minutes)
end

return table.freeze(Wars)
