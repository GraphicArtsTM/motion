--!strict
--[[
	MatchSim — симуляция матча без Roblox API. Сервер (MatchService) только кормит её игроками,
	намерениями и временем, а результаты рассылает. Тесты гоняют её в Lune.

	Фазы (этап 2):
	- Waiting — ждём первого игрока;
	- Pick — Config.Match.StartPickSec секунд игроки выбирают точку старта (GDD §6.2);
	- Play — люди растут, атаки двигают границы, боты думают.
	Лобби, победа и возврат в лобби — этап 4.

	Этап 3а: провинции и нейтральные города (из карты), столица — город; армии нанимаются, ходят
	и захватывают провинции (Armies). Города ползущая граница не берёт — только армии.

	В конце выбора: кто не выбрал — получает точку автоматически, свободные места до
	Config.Match.TargetNations занимают боты, цвета раздаются по точкам старта (NationColors.assign),
	на месте столицы появляется круг клеток.
]]

local Armies = require("./Armies")
local BotBrain = require("./BotBrain")
local Config = require("./Config")
local Economy = require("./Economy")
local Expansion = require("./Expansion")
local Grid = require("./Grid")
local MapData = require("./MapData")
local NameGen = require("./NameGen")
local NationColors = require("./NationColors")
local Pathfind = require("./Pathfind")
local Provinces = require("./Provinces")
local Rng = require("./Rng")
local StartPositions = require("./StartPositions")
local Types = require("./Types")

type Grid = Grid.Grid
type MapData = MapData.MapData
type Rng = Rng.Rng
type Nation = Types.Nation
type Attack = Types.Attack
type Army = Types.Army

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
	provinces: Provinces.ProvinceSet,
	cityOf: { [number]: number }, -- провинция → клетка города (нейтрального, державы или столицы)
	armies: { Army },
	nextArmyId: number,
	armyCtx: Armies.Context,
}

local MatchSim = {}

function MatchSim.new(map: MapData, seed: number): Match
	local grid = Grid.new(map)
	local provinces = Provinces.build(map)
	local cityOf: { [number]: number } = {}
	for _, p in provinces.list do
		local city = p.city
		if city ~= nil then
			cityOf[p.id] = city
			Grid.setCity(grid, city, true)
		end
	end
	local m: Match
	m = {
		map = map,
		grid = grid,
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
		provinces = provinces,
		cityOf = cityOf,
		armies = {},
		nextArmyId = 1,
		armyCtx = {
			map = map,
			grid = grid,
			provinces = provinces,
			nations = {},
			cityOf = cityOf,
			onCapitalLost = function(nation: number, by: number)
				MatchSim.capitalLost(m, nation, by)
			end,
		},
	}
	m.armyCtx.nations = m.nations
	return m
end

-- Все города на карте (клетки) — для клиентов.
function MatchSim.cities(m: Match): { number }
	local out: { number } = {}
	for _, cell in m.cityOf do
		table.insert(out, cell)
	end
	table.sort(out)
	return out
end

-- Ближайший к from город державы или nil.
local function nearestOwnedCity(m: Match, nationId: number, from: number): number?
	local w = m.grid.width
	local best: number? = nil
	local bestD = math.huge
	for _, cell in m.cityOf do
		if Grid.getOwner(m.grid, cell) == nationId then
			local d = (cell % w - from % w) ^ 2 + (cell // w - from // w) ^ 2
			if d < bestD or (d == bestD and best ~= nil and cell < best) then
				best, bestD = cell, d
			end
		end
	end
	return best
end

-- Армия взяла столицу: столица переезжает в ближайший свой город (если он есть).
function MatchSim.capitalLost(m: Match, nationId: number, by: number)
	local n = m.nations[nationId]
	if n == nil or n.capital == nil then
		return
	end
	n.capital = nearestOwnedCity(m, nationId, n.capital)
	table.insert(m.events, { kind = "capitalLost", nation = nationId, by = by })
	m.infoDirty = true
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
		-- Столица — город. В провинции один город: нейтральный город провинции столицы исчезает.
		local cap = n.capital :: number
		local province = MapData.getProvince(m.map, cap)
		local oldCity = m.cityOf[province]
		if oldCity ~= nil and oldCity ~= cap then
			Grid.setCity(m.grid, oldCity, false)
		end
		m.cityOf[province] = cap
		Grid.setCity(m.grid, cap, true)
		for _, cell in StartPositions.circle(m.grid, cap, Config.Start.Radius) do
			-- Чужие города в круг не попадают: города берут только армии.
			if Grid.getOwner(m.grid, cell) == 0 and (cell == cap or not Grid.isCity(m.grid, cell)) then
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

	if intent.kind == "hire" then
		local count = 0
		for _, a in m.armies do
			if a.owner == nationId then
				count += 1
			end
		end
		if count >= Config.Armies.MaxPerNation then
			return false, "tooManyArmies"
		end
		local capital = n.capital
		if capital == nil then
			return false, "noCapital"
		end
		local stats = Armies.stats(intent.unit)
		if n.people < stats.people then
			return false, "noTroops"
		end
		n.people -= stats.people
		local army = Armies.new(m.nextArmyId, nationId, intent.unit, capital, m.grid.width)
		army.auto = n.isBot
		m.nextArmyId += 1
		table.insert(m.armies, army)
		return true, nil
	end

	if intent.kind == "move" or intent.kind == "stop" or intent.kind == "auto" then
		local mine: { Army } = {}
		local ids: { number } = intent.armies
		for _, id in ids do
			for _, a in m.armies do
				if a.id == id and a.owner == nationId and a.state ~= "recruit" then
					table.insert(mine, a)
				end
			end
		end
		if #mine == 0 then
			return false, "noArmy"
		end
		if intent.kind == "stop" then
			for _, a in mine do
				a.auto = false
				Armies.stop(a)
			end
			return true, nil
		elseif intent.kind == "auto" then
			for _, a in mine do
				a.auto = intent.on
				if intent.on and a.state == "idle" then
					a.recheckLeft = 0
				end
			end
			return true, nil
		end
		-- move
		if intent.cell >= m.grid.size or not Pathfind.passable(m.map, intent.cell) then
			return false, "noPath"
		end
		local moved = 0
		for _, a in mine do
			local path = Pathfind.find(m.map, a.cell, intent.cell)
			if path ~= nil then
				a.auto = false
				Armies.setPath(a, path)
				moved += 1
			end
		end
		if moved == 0 then
			return false, "noPath"
		end
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
	local armies = 0
	for _, a in m.armies do
		if a.owner == n.id then
			armies += 1
		end
	end
	return {
		people = n.people,
		maxPeople = Economy.maxPeople(Grid.cellsOf(m.grid, n.id)),
		attacks = attacksOf(m, n.id),
		armies = armies,
		hasCapital = n.capital ~= nil,
		hasNeutral = adjacent[0] ~= nil,
		neighbours = neighbours,
	}
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
	-- Армии.
	for _, a in m.armies do
		captured += Armies.step(m.armyCtx, a, simDt)
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
				j = 1
				while j <= #m.armies do
					if m.armies[j].owner == n.id then
						table.remove(m.armies, j)
					else
						j += 1
					end
				end
			elseif n.capital ~= nil and Grid.getOwner(g, n.capital) ~= n.id then
				MatchSim.capitalLost(m, n.id, Grid.getOwner(g, n.capital))
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
