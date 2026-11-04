--!strict
--[[
	DevTools — действия панели разработчика (F4, только в Studio). Чистый модуль: сервер зовёт его, только если
	RunService:IsStudio(), в опубликованной игре канала для этих действий нет. Тестируется в Lune.

	- grant: дать себе войска (каждого типа), людей, деньги и нефть.
	- forceOffer: бот присылает игроку предложение (союз, пакт, торговля) или требование провинции.
	- warNow / peaceNow: война сразу без мобилизации / белый мир сразу.
	- botWar: бот объявляет войну игроку (если они союзники или в пакте — это предательство бота).
	- councilNow: Совет держав собирается сейчас.
	- endMatch: до лимита времени матча остаётся Dev.EndLeadSec секунд.
	- setStability: все провинции державы — сразу Dev.StabilityLow или Dev.StabilityHigh (§6.10, этап 7а).
	- revoltNow: восстание в самой нестабильной своей провинции, кроме столицы.
	Туман вкл/выкл для себя — в MatchService (кому слать все фронты) и на клиенте.
	- navy: порт в своей прибрежной провинции (если нет) и у причала транспорт с эсминцем (§6.12, этап 7б-1).
	- botLanding: выбранный бот (война сразу) получает порт, транспорт и войска и высаживается на ваш берег.
	Ускорение времени — в MatchService (шагов симуляции за кадр больше).
]]

local Config = require("./Config")
local Buildings = require("./Buildings")
local Diplomacy = require("./Diplomacy")
local Fleet = require("./Fleet")
local Grid = require("./Grid")
local MapData = require("./MapData")
local Forces = require("./Forces")
local MatchSim = require("./MatchSim")
local Stability = require("./Stability")
local Types = require("./Types")
local Wars = require("./Wars")

type Match = MatchSim.Match

export type Grant = "forces" | "people" | "money"
export type ForcedOffer = "alliance" | "pact" | "trade" | "demand"

local DevTools = {}

function DevTools.grant(m: Match, id: number, what: Grant): (boolean, string?)
	local n = m.nations[id]
	if n == nil or not n.alive then
		return false, "dead"
	end
	local cfg = Config.Dev
	if what == "forces" then
		for kind in Types.LandUnits do
			Forces.add(n.home, kind, cfg.GrantForces)
		end
	elseif what == "people" then
		n.people += cfg.GrantPeople
	else
		n.money += cfg.GrantMoney
		n.oil += cfg.GrantOil
	end
	return true, nil
end

-- Провинция игрока на границе с ботом (не со столицей) — что бот потребует.
function DevTools.demandProvince(m: Match, bot: number, player: number): number?
	for _, p in m.provinces.list do
		if MatchSim.demandable(m, bot, player, p.id) then
			return p.id
		end
	end
	return nil
end

function DevTools.forceOffer(m: Match, bot: number, player: number, kind: ForcedOffer): (boolean, string?)
	-- Панель не ждёт паузы между предложениями.
	m.diplo.lastOffer[bot * 65536 + player] = nil
	local offer: Types.OfferKind = if kind == "pact" then "pact5" else kind
	local province: number? = nil
	if kind == "demand" then
		province = DevTools.demandProvince(m, bot, player)
		if province == nil then
			return false, "notBorder"
		end
	end
	return MatchSim.offer(m, bot, player, offer, province)
end

-- Война a против b сразу, без мобилизации (договор между ними — предательство a).
function DevTools.warNow(m: Match, a: number, b: number): (boolean, string?)
	local na, nb = m.nations[a], m.nations[b]
	if na == nil or nb == nil or not na.alive or not nb.alive or a == b then
		return false, "target"
	end
	-- Вассалитет мешает войне — для проверки снимаем его.
	if Diplomacy.overlordOf(m.diplo, a) == b or Diplomacy.overlordOf(m.diplo, b) == a then
		Diplomacy.free(m.diplo, if Diplomacy.overlordOf(m.diplo, a) == b then a else b, m.simTime, false)
	end
	local war = Wars.find(m.wars, a, b)
	if war == nil then
		MatchSim.declareWar(m, a, b)
		war = Wars.find(m.wars, a, b)
	end
	if war ~= nil and war.state ~= "active" then
		war.state = "active"
		war.activeAt = m.simTime
		table.insert(m.events, { kind = "warStarted", nation = war.a, target = war.b })
	end
	return true, nil
end

function DevTools.peaceNow(m: Match, a: number, b: number): (boolean, string?)
	local war = Wars.find(m.wars, a, b)
	if war == nil then
		return false, "notAtWar"
	end
	MatchSim.makePeace(m, war, "white")
	return true, nil
end

function DevTools.councilNow(m: Match): (boolean, string?)
	if m.council.vote ~= nil then
		return false, "phase"
	end
	m.council.nextAt = m.simTime
	return true, nil
end

function DevTools.endMatch(m: Match): (boolean, string?)
	if m.phase ~= "Play" then
		return false, "phase"
	end
	m.time = math.max(m.time, Config.Match.TimeLimitSec - Config.Dev.EndLeadSec)
	return true, nil
end

function DevTools.setStability(m: Match, id: number, high: boolean): (boolean, string?)
	local n = m.nations[id]
	if n == nil or not n.alive then
		return false, "dead"
	end
	-- Хозяева провинций могли смениться с прошлого пересчёта — пересчитать сейчас.
	m.stability.nextUpdateAt = 0
	Stability.update(m.stability, MatchSim.stabilityContext(m))
	Stability.setAll(m.stability, id, if high then Config.Dev.StabilityHigh else Config.Dev.StabilityLow)
	m.stability.nextUpdateAt = 0 -- итоги (доход, средняя) — сразу
	return true, nil
end

function DevTools.revoltNow(m: Match, id: number): (boolean, string?)
	local n = m.nations[id]
	if n == nil or not n.alive then
		return false, "dead"
	end
	local capital = if n.capital ~= nil then buffer.readu16(m.grid.province, n.capital * 2) else 0
	local best: number? = nil
	local bestValue = math.huge
	for _, e in Stability.provincesOf(m.stability, id) do
		if e.province ~= capital and e.value < bestValue then
			best, bestValue = e.province, e.value
		end
	end
	if best == nil then
		return false, "noProvince"
	end
	MatchSim.revolt(m, best, id)
	return true, nil
end

-- Порт державы (первый) или новый даром в её прибрежной провинции (центр — её). Возвращает клетку порта.
local function ensurePort(m: Match, id: number): number?
	local ports = MatchSim.portsOf(m, id)
	if #ports > 0 then
		return ports[1].cell
	end
	for _, p in m.provinces.list do
		if
			m.sea.docks[p.id] ~= nil
			and Grid.getOwner(m.grid, p.center) == id
			and m.buildings.byProvince[p.id] == nil
		then
			Buildings.place(m.buildings, "Port", p.center, p.id)
			MatchSim.refreshOwned(m)
			return p.center
		end
	end
	return nil
end

function DevTools.navy(m: Match, id: number): (boolean, string?)
	local n = m.nations[id]
	if n == nil or not n.alive then
		return false, "dead"
	end
	local port = ensurePort(m, id)
	if port == nil then
		return false, "needCoast"
	end
	local dock = m.sea.docks[MapData.getProvince(m.map, port)] :: number
	Fleet.spawn(m.fleet, m.grid.width, id, "Transport", port, dock)
	Fleet.spawn(m.fleet, m.grid.width, id, "Destroyer", port, dock)
	return true, nil
end

function DevTools.botLanding(m: Match, bot: number, player: number): (boolean, string?)
	local ok, reason = DevTools.warNow(m, bot, player)
	if not ok then
		return false, reason
	end
	local port = ensurePort(m, bot)
	if port == nil then
		return false, "needCoast"
	end
	local dock = m.sea.docks[MapData.getProvince(m.map, port)] :: number
	local coast = MatchSim.coastOf(m, player, dock)
	if coast == nil then
		return false, "notCoast"
	end
	Fleet.spawn(m.fleet, m.grid.width, bot, "Transport", port, dock)
	local n = m.nations[bot]
	Forces.add(n.home, 1, Config.Naval.TransportCapacity)
	return MatchSim.applyIntent(m, bot, { kind = "land", port = port, target = coast, percent = 1 })
end

return table.freeze(DevTools)
