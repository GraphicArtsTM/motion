--!strict
--[[
	MatchSim — симуляция матча без Roblox API. Сервер (MatchService) только кормит её игроками,
	намерениями и временем, а результаты рассылает. Тесты гоняют её в Lune.

	Фазы (этап 2):
	- Waiting — ждём первого игрока;
	- Pick — Config.Match.StartPickSec секунд игроки выбирают точку старта (GDD §6.2);
	- Play — люди растут, атаки двигают границы, боты думают.
	Лобби, победа и возврат в лобби — этап 4.

	В конце выбора: кто не выбрал — получает точку автоматически, свободные места до
	Config.Match.TargetNations занимают боты, цвета раздаются по точкам старта (NationColors.assign),
	на месте столицы появляется круг клеток.
]]

local BotBrain = require("./BotBrain")
local Config = require("./Config")
local Economy = require("./Economy")
local Expansion = require("./Expansion")
local Grid = require("./Grid")
local MapData = require("./MapData")
local NameGen = require("./NameGen")
local NationColors = require("./NationColors")
local Rng = require("./Rng")
local StartPositions = require("./StartPositions")
local Types = require("./Types")

type Grid = Grid.Grid
type MapData = MapData.MapData
type Rng = Rng.Rng
type Nation = Types.Nation
type Attack = Types.Attack

export type MatchEvent =
	{ kind: "eliminated", nation: number, by: number }
	| { kind: "capitalLost", nation: number, by: number }

export type Match = {
	map: MapData,
	grid: Grid,
	rng: Rng,
	seed: number,
	phase: Types.Phase,
	phaseLeft: number, -- секунд до конца фазы выбора
	time: number, -- секунд реального времени с начала фазы Play (часы матча)
	speed: number, -- множитель скорости игрового времени (Config.Match.Speed, «Блиц» — 2)
	simTime: number, -- игровое время: time × speed
	tick: number,
	nations: { Nation },
	attacks: { Attack },
	botNextThink: { [number]: number },
	infoDirty: boolean, -- изменились державы или фаза — разослать клиентам
	events: { MatchEvent },
	lastCaptured: number, -- клеток захвачено за последний тик
}

local MatchSim = {}

function MatchSim.new(map: MapData, seed: number): Match
	return {
		map = map,
		grid = Grid.new(map),
		rng = Rng.new(seed),
		seed = seed,
		phase = "Waiting",
		phaseLeft = 0,
		time = 0,
		speed = Config.Match.Speed,
		simTime = 0,
		tick = 0,
		nations = {},
		attacks = {},
		botNextThink = {},
		infoDirty = true,
		events = {},
		lastCaptured = 0,
	}
end

local function newNation(m: Match, name: string, nameEn: string, isBot: boolean, userId: number?): Nation
	local nation: Nation = {
		id = #m.nations + 1,
		name = name,
		nameEn = nameEn,
		isBot = isBot,
		userId = userId,
		colorIndex = 0,
		capital = nil,
		people = 0,
		alive = true,
	}
	table.insert(m.nations, nation)
	m.infoDirty = true
	return nation
end

-- Добавляет игрока (только до начала игры). Возвращает id державы или nil, если мест нет / игра идёт.
function MatchSim.addPlayer(m: Match, userId: number, name: string): number?
	if m.phase == "Play" or #m.nations >= Config.Match.MaxPlayers then
		return nil
	end
	return newNation(m, name, name, false, userId).id
end

-- Игрок ушёл: его держава остаётся на карте и переходит под управление бота.
function MatchSim.removePlayer(m: Match, nationId: number)
	local n = m.nations[nationId]
	if n == nil then
		return
	end
	n.isBot = true
	n.userId = nil
	m.botNextThink[nationId] = m.simTime + BotBrain.nextThinkDelay(m.rng)
	m.infoDirty = true
end

function MatchSim.startPick(m: Match)
	if m.phase ~= "Waiting" then
		return
	end
	m.phase = "Pick"
	m.phaseLeft = Config.Match.StartPickSec
	m.infoDirty = true
end

local function capitals(m: Match, except: number?): { number }
	local out: { number } = {}
	for _, n in m.nations do
		if n.capital ~= nil and n.id ~= except then
			table.insert(out, n.capital)
		end
	end
	return out
end

-- Конец выбора старта: автостарты, боты, цвета, круги клеток, люди.
function MatchSim.finishPick(m: Match)
	if m.phase == "Play" then
		return
	end
	local taken: { [string]: boolean } = {}
	for _, n in m.nations do
		taken[n.name] = true
	end
	while #m.nations < Config.Match.TargetNations do
		local name = NameGen.generate(m.rng, taken)
		taken[name.ru] = true
		newNation(m, name.ru, name.en, true, nil)
	end
	for _, n in m.nations do
		if n.capital == nil then
			n.capital = StartPositions.autoPick(m.grid, capitals(m), m.rng)
		end
	end

	local starts: { NationColors.StartPoint } = {}
	local order: { Nation } = {}
	for _, n in m.nations do
		local cap = n.capital
		if cap ~= nil then
			-- Координаты считаем отдельно: StyLua 2.6 падает на «//» внутри длинного конструктора таблицы.
			local x, y = cap % m.grid.width, cap // m.grid.width
			table.insert(starts, { x = x, y = y })
			table.insert(order, n)
		else
			n.alive = false -- места на карте не нашлось (крошечная карта)
		end
	end
	local colors = NationColors.assign(starts)
	for k, n in order do
		n.colorIndex = colors[k]
		for _, cell in StartPositions.circle(m.grid, n.capital :: number, Config.Start.Radius) do
			if Grid.getOwner(m.grid, cell) == 0 then
				Grid.setOwner(m.grid, cell, n.id)
			end
		end
		n.people = Config.People.Start
		if n.isBot then
			m.botNextThink[n.id] = BotBrain.nextThinkDelay(m.rng)
		end
	end
	m.phase = "Play"
	m.phaseLeft = 0
	m.time = 0
	m.simTime = 0
	m.infoDirty = true
end

local function findAttack(m: Match, attacker: number, target: number): (number?, Attack?)
	for k, a in m.attacks do
		if a.attacker == attacker and a.target == target then
			return k, a
		end
	end
	return nil, nil
end

local function attacksOf(m: Match, attacker: number): number
	local count = 0
	for _, a in m.attacks do
		if a.attacker == attacker then
			count += 1
		end
	end
	return count
end

-- Применяет намерение державы. Возвращает успех и код ошибки (для клиента и логов).
function MatchSim.applyIntent(m: Match, nationId: number, intent: Types.Intent): (boolean, string?)
	local n = m.nations[nationId]
	if n == nil then
		return false, "noNation"
	end
	if intent.kind == "pick" then
		if m.phase ~= "Pick" then
			return false, "phase"
		end
		local ok, err = StartPositions.check(m.grid, intent.cell, capitals(m, nationId))
		if not ok then
			return false, err
		end
		n.capital = intent.cell
		m.infoDirty = true
		return true, nil
	end

	if m.phase ~= "Play" then
		return false, "phase"
	end
	if not n.alive then
		return false, "dead"
	end

	if intent.kind == "cancel" then
		local k, a = findAttack(m, nationId, intent.target)
		if k == nil or a == nil then
			return false, "noAttack"
		end
		n.people += a.troops
		table.remove(m.attacks, k)
		return true, nil
	end

	-- attack
	local target = intent.target
	if target == nationId then
		return false, "self"
	end
	if target ~= 0 then
		local t = m.nations[target]
		if t == nil or not t.alive then
			return false, "target"
		end
	end
	local focus = intent.focus
	if focus ~= nil and focus >= m.grid.size then
		return false, "focus"
	end
	if not Expansion.hasFrontier(m.grid, nationId, target) then
		return false, "notAdjacent"
	end
	local _, existing = findAttack(m, nationId, target)
	if existing == nil and attacksOf(m, nationId) >= Config.Expansion.MaxAttacks then
		return false, "tooMany"
	end
	local troops = n.people * intent.percent
	if troops < Config.Expansion.MinTroops then
		return false, "noTroops"
	end
	n.people -= troops
	if existing ~= nil then
		existing.troops += troops
		existing.focus = focus
	else
		table.insert(m.attacks, { attacker = nationId, target = target, troops = troops, focus = focus })
	end
	return true, nil
end

-- Что бот «видит» о своей державе.
local function botView(m: Match, n: Nation): BotBrain.BotView
	local adjacent = Grid.adjacentOwners(m.grid, n.id)
	local neighbours: { BotBrain.Neighbour } = {}
	for owner in adjacent do
		if owner ~= 0 then
			local other = m.nations[owner]
			if other ~= nil and other.alive then
				table.insert(neighbours, { id = owner, people = other.people })
			end
		end
	end
	table.sort(neighbours, function(a: BotBrain.Neighbour, b: BotBrain.Neighbour): boolean
		return a.id < b.id
	end)
	return {
		people = n.people,
		maxPeople = Economy.maxPeople(Grid.cellsOf(m.grid, n.id)),
		attacks = attacksOf(m, n.id),
		hasNeutral = adjacent[0] ~= nil,
		neighbours = neighbours,
	}
end

-- Ближайшая к old клетка державы (новая столица после потери старой).
local function nearestOwned(m: Match, nationId: number, old: number): number?
	local g = m.grid
	local ox, oy = old % g.width, old // g.width
	local best: number? = nil
	local bestD = math.huge
	for i = 0, g.size - 1 do
		if Grid.getOwner(g, i) == nationId then
			local d = (i % g.width - ox) ^ 2 + (i // g.width - oy) ^ 2
			if d < bestD then
				best, bestD = i, d
			end
		end
	end
	return best
end

-- Шаг симуляции на dt секунд (сервер зовёт с dt = 1 / TickRate).
function MatchSim.step(m: Match, dt: number)
	if m.phase == "Waiting" then
		return
	elseif m.phase == "Pick" then
		m.phaseLeft -= dt
		if m.phaseLeft <= 0 then
			MatchSim.finishPick(m)
		end
		return
	end

	m.tick += 1
	m.time += dt
	local simDt = dt * m.speed
	m.simTime += simDt
	local g = m.grid

	-- Люди.
	for _, n in m.nations do
		if n.alive then
			n.people = Economy.grow(n.people, Economy.maxPeople(Grid.cellsOf(g, n.id)), simDt)
		end
	end

	-- Атаки.
	local captured = 0
	local k = 1
	while k <= #m.attacks do
		local a = m.attacks[k]
		local done, cells = Expansion.advance(m.map, g, m.nations, a, m.tick, m.seed, simDt)
		captured += cells
		if done then
			local attacker = m.nations[a.attacker]
			attacker.people += math.max(0, a.troops)
			table.remove(m.attacks, k)
		else
			k += 1
		end
	end
	m.lastCaptured = captured

	-- Потеря столицы и выбывание.
	for _, n in m.nations do
		if n.alive then
			if Grid.cellsOf(g, n.id) == 0 then
				n.alive = false
				n.people = 0
				local by = if n.capital ~= nil then Grid.getOwner(g, n.capital) else 0
				table.insert(m.events, { kind = "eliminated", nation = n.id, by = by })
				m.infoDirty = true
				local j = 1
				while j <= #m.attacks do
					local a = m.attacks[j]
					if a.attacker == n.id then
						table.remove(m.attacks, j)
					else
						j += 1
					end
				end
			elseif n.capital ~= nil and Grid.getOwner(g, n.capital) ~= n.id then
				local by = Grid.getOwner(g, n.capital)
				n.capital = nearestOwned(m, n.id, n.capital)
				table.insert(m.events, { kind = "capitalLost", nation = n.id, by = by })
				m.infoDirty = true
			end
		end
	end

	-- Боты.
	for _, n in m.nations do
		local due = m.botNextThink[n.id]
		if n.alive and n.isBot and due ~= nil and m.simTime >= due then
			m.botNextThink[n.id] = m.simTime + BotBrain.nextThinkDelay(m.rng)
			local intent = BotBrain.decide(botView(m, n), m.rng)
			if intent ~= nil then
				MatchSim.applyIntent(m, n.id, intent)
			end
		end
	end
end

-- Забирает накопленные события (для ленты событий).
function MatchSim.takeEvents(m: Match): { MatchEvent }
	local out = m.events
	m.events = {}
	return out
end

-- Людей в атаках у державы (для HUD и статистики).
function MatchSim.troopsOf(m: Match, nationId: number): number
	local sum = 0
	for _, a in m.attacks do
		if a.attacker == nationId then
			sum += a.troops
		end
	end
	return sum
end

return table.freeze(MatchSim)
