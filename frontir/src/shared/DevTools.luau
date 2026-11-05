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
	- airForce: аэродром в своей провинции (если нет), истребитель и бомбардировщик (§6.13, этап 7б-2).
	- botRaid: выбранный бот (война сразу) получает аэродром и бомбардировщик и бомбит ваш фронт или город.
	- researchAll: все доступные уровни трёх веток сразу (закрытые до этапа 7г — нет) (§6.14, этап 7в-1).
	- finishResearch: текущее исследование заканчивается на следующем шаге (событие в ленте как обычно).
	- resetCooldowns: обе способности генерала готовы (§6.15, этап 7в-2).
	- nextCommander: следующий генерал по кругу (и в игре — для проверки всех способностей).
	- botAbility: выбранный бот (война сразу, перезарядки сброшены) применяет обе способности по вам.
	Ускорение времени — в MatchService (шагов симуляции за кадр больше).
]]

local Config = require("./Config")
local Buildings = require("./Buildings")
local Commanders = require("./Commanders")
local Diplomacy = require("./Diplomacy")
local Air = require("./Air")
local Fleet = require("./Fleet")
local Grid = require("./Grid")
local MapData = require("./MapData")
local Forces = require("./Forces")
local MatchSim = require("./MatchSim")
local Stability = require("./Stability")
local Tech = require("./Tech")
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

-- Аэродром державы (работающий, первый) или новый даром в её провинции; nearTo — предпочесть ближайший к клетке.
local function ensureAirfield(m: Match, id: number, nearTo: number?): number?
	local w = m.grid.width
	for _, a in MatchSim.buildingsOf(m, "Airfield") do
		if a.owner == id then
			return a.cell
		end
	end
	local best: number? = nil
	local bestD = math.huge
	for _, p in m.provinces.list do
		if Grid.getOwner(m.grid, p.center) == id and m.buildings.byProvince[p.id] == nil then
			local d = if nearTo ~= nil then (p.center % w - nearTo % w) ^ 2 + (p.center // w - nearTo // w) ^ 2 else 0
			if d < bestD then
				best, bestD = p.center, d
			end
			if nearTo == nil then
				break
			end
		end
	end
	if best ~= nil then
		Buildings.place(m.buildings, "Airfield", best, MapData.getProvince(m.map, best))
		MatchSim.refreshOwned(m)
	end
	return best
end

function DevTools.airForce(m: Match, id: number): (boolean, string?)
	local n = m.nations[id]
	if n == nil or not n.alive then
		return false, "dead"
	end
	local airfield = ensureAirfield(m, id, n.capital)
	if airfield == nil then
		return false, "occupied"
	end
	Air.spawn(m.air, m.grid.width, id, "Fighter", airfield)
	Air.spawn(m.air, m.grid.width, id, "Bomber", airfield)
	return true, nil
end

function DevTools.botRaid(m: Match, bot: number, player: number): (boolean, string?)
	local ok, reason = DevTools.warNow(m, bot, player)
	if not ok then
		return false, reason
	end
	-- Цель: линия фронта против бота или ближайший к боту город игрока.
	local target: number? = nil
	for _, a in m.attacks do
		if (a.attacker == player and a.target == bot) or (a.attacker == bot and a.target == player) then
			if a.line ~= nil and #(a.line :: { number }) > 0 then
				target = (a.line :: { number })[1]
			end
		end
	end
	local botCapital = m.nations[bot].capital
	if target == nil then
		local w = m.grid.width
		local bestD = math.huge
		for _, cell in m.cityOf do
			if Grid.getOwner(m.grid, cell) == player and botCapital ~= nil then
				local d = (cell % w - botCapital % w) ^ 2 + (cell // w - botCapital // w) ^ 2
				if d < bestD then
					target, bestD = cell, d
				end
			end
		end
	end
	if target == nil then
		return false, "target"
	end
	local airfield = ensureAirfield(m, bot, target)
	if airfield == nil then
		return false, "occupied"
	end
	Air.spawn(m.air, m.grid.width, bot, "Bomber", airfield)
	return MatchSim.applyIntent(m, bot, { kind = "raid", cell = target })
end

function DevTools.resetCooldowns(m: Match, id: number): (boolean, string?)
	local n = m.nations[id]
	if n == nil or not n.alive then
		return false, "dead"
	end
	Commanders.resetCooldowns(m.commanders, id)
	return true, nil
end

function DevTools.nextCommander(m: Match, id: number): (boolean, string?)
	local n = m.nations[id]
	if n == nil then
		return false, "dead"
	end
	local list = Types.CommanderIds
	local k = table.find(list, Commanders.of(m.commanders, id)) or 0
	Commanders.choose(m.commanders, id, list[k % #list + 1])
	Commanders.resetCooldowns(m.commanders, id)
	m.infoDirty = true
	return true, nil
end

-- Бот bot применяет обе способности по игроку player: цель — линия фронта между ними или клетка у города игрока.
function DevTools.botAbility(m: Match, bot: number, player: number): (boolean, string?)
	local ok, reason = DevTools.warNow(m, bot, player)
	if not ok then
		return false, reason
	end
	local b = m.nations[bot]
	Commanders.resetCooldowns(m.commanders, bot)
	local g = m.grid
	local target: number? = nil
	for _, a in m.attacks do
		if (a.attacker == player and a.target == bot) or (a.attacker == bot and a.target == player) then
			if a.line ~= nil and #(a.line :: { number }) > 0 then
				target = (a.line :: { number })[1]
			end
		end
	end
	if target == nil then
		local best = math.huge
		local cap = b.capital or 0
		local w = g.width
		for _, c in m.cityOf do
			if Grid.getOwner(g, c) == player then
				local d = (c % w - cap % w) ^ 2 + (c // w - cap // w) ^ 2
				if d < best then
					Grid.forNeighbours(g, c, function(j)
						if Grid.getOwner(g, j) == player and not Grid.isCity(g, j) then
							target, best = j, d
						end
					end)
				end
			end
		end
	end
	if target == nil then
		return false, "target"
	end
	local used = 0
	for slot = 1, 2 do
		local ability = Commanders.ability(Commanders.of(m.commanders, bot), slot)
		local cell = if ability == "Fortify" then b.capital else target
		if MatchSim.useAbility(m, b, slot, cell, 0.3) then
			used += 1
		end
	end
	return used > 0, if used > 0 then nil else "target"
end

function DevTools.researchAll(m: Match, id: number): (boolean, string?)
	local n = m.nations[id]
	if n == nil or not n.alive then
		return false, "dead"
	end
	m.tech.research[id] = nil
	for _, b in Tech.Branches do
		local branch: Tech.Branch = b :: any
		for level = 1, #Config.Tech.Cost do
			if not Tech.isLocked(branch, level) then
				Tech.grant(m.tech, id, branch, level)
			end
		end
	end
	return true, nil
end

function DevTools.finishResearch(m: Match, id: number): (boolean, string?)
	local r = m.tech.research[id]
	if r == nil then
		return false, "noResearch"
	end
	r.left = 0
	return true, nil
end

return table.freeze(DevTools)
