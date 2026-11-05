--!strict
--[[
	Fleet — корабли державы на воде (GDD §6.12, этап 7б-1). Чистый модуль: состояние кораблей, очередь поиска
	путей, движение, бой кораблей и блокада портов. Правила вокруг (найм, высадка, снабжение, обстрел берега)
	решает MatchSim; что нужно о матче — через аргументы-функции.

	Корабль — точка (x, y) в клетках (центр клетки i — i % w + 0.5). Состояния:
	- docked — стоит у причала порта home;
	- planning — ждёт поиска пути (сервер ищет не больше Naval.PathsPerTick путей за тик);
	- moving — идёт по точкам пути к dest; по прибытии: land — высадка (MatchSim), return — в порт, patrol — стоит;
	- patrol — эсминец стоит в точке патруля.
]]

local Config = require("./Config")
local Forces = require("./Forces")
local Naval = require("./Naval")
local Types = require("./Types")

export type ShipKind = "Transport" | "Destroyer"
export type ShipState = "docked" | "planning" | "moving" | "patrol"
export type ShipOrder = "land" | "patrol" | "return"

export type Ship = {
	id: number,
	owner: number,
	kind: ShipKind,
	x: number,
	y: number,
	hp: number,
	state: ShipState,
	order: ShipOrder?,
	dest: number, -- клетка моря, куда идёт (или где стоит)
	path: { number }?, -- точки пути (клетки)
	step: number, -- индекс следующей точки
	target: number?, -- высадка: клетка берега
	home: number?, -- клетка порта (здания), у которого стоит
	cargo: Types.Forces?, -- войска на борту транспорта
	people: number, -- люди на борту
	alive: boolean,
}

export type Build = { kind: ShipKind, port: number, left: number }

export type FleetState = {
	ships: { Ship },
	nextId: number,
	queues: { [number]: { Build } }, -- держава → очередь кораблей
	blocked: { [number]: boolean }, -- клетка порта → заблокирован
	version: number, -- растёт, когда меняется блокада
}

-- Что произошло за шаг (MatchSim превращает в события и правила).
export type Happening =
	{ kind: "arrived", ship: Ship }
	| { kind: "sunk", ship: Ship, by: number }
	| { kind: "noPath", ship: Ship }

local Fleet = {}

Fleet.Kinds = table.freeze({ "Transport", "Destroyer" } :: { ShipKind })

function Fleet.new(): FleetState
	return { ships = {}, nextId = 1, queues = {}, blocked = {}, version = 0 }
end

function Fleet.stats(kind: ShipKind): Types.UnitStats
	return (Config.Units :: any)[kind]
end

function Fleet.maxHp(kind: ShipKind): number
	return if kind == "Transport" then Config.Naval.TransportHp else Config.Naval.DestroyerHp
end

-- Клетка корабля.
function Fleet.cellOf(width: number, ship: Ship): number
	return math.floor(ship.y) * width + math.floor(ship.x)
end

function Fleet.ofNation(fs: FleetState, owner: number): { Ship }
	local out: { Ship } = {}
	for _, s in fs.ships do
		if s.alive and s.owner == owner then
			table.insert(out, s)
		end
	end
	return out
end

-- Сколько кораблей у державы (с очередью).
function Fleet.count(fs: FleetState, owner: number): number
	local q = fs.queues[owner]
	return #Fleet.ofNation(fs, owner) + (if q ~= nil then #q else 0)
end

-- Новый корабль у причала dock порта port.
function Fleet.spawn(fs: FleetState, width: number, owner: number, kind: ShipKind, port: number, dock: number): Ship
	local row = dock // width -- StyLua 2.6 падает на «//» внутри конструктора таблицы
	local ship: Ship = {
		id = fs.nextId,
		owner = owner,
		kind = kind,
		x = dock % width + 0.5,
		y = row + 0.5,
		hp = Fleet.maxHp(kind),
		state = "docked",
		order = nil,
		dest = dock,
		path = nil,
		step = 1,
		target = nil,
		home = port,
		cargo = nil,
		people = 0,
		alive = true,
	}
	fs.nextId = fs.nextId % 65535 + 1
	table.insert(fs.ships, ship)
	return ship
end

function Fleet.byId(fs: FleetState, id: number): Ship?
	for _, s in fs.ships do
		if s.alive and s.id == id then
			return s
		end
	end
	return nil
end

-- Приказ: идти к клетке моря dest (путь ищется в очереди). order — что делать по прибытии.
function Fleet.order(ship: Ship, order: ShipOrder, dest: number)
	ship.order = order
	ship.dest = dest
	ship.path = nil
	ship.step = 1
	ship.state = "planning"
	ship.home = nil
end

-- Свободный транспорт у порта port (стоит у причала без груза).
function Fleet.idleTransport(fs: FleetState, owner: number, port: number): Ship?
	for _, s in fs.ships do
		if s.alive and s.owner == owner and s.kind == "Transport" and s.state == "docked" and s.home == port then
			return s
		end
	end
	return nil
end

-- Поиск путей: не больше PathsPerTick за вызов, по очереди (кто дольше ждёт — первым: порядок списка).
function Fleet.planPaths(fs: FleetState, sea: Naval.SeaMap, happenings: { Happening })
	local budget = Config.Naval.PathsPerTick
	for _, ship in fs.ships do
		if budget <= 0 then
			break
		end
		if ship.alive and ship.state == "planning" then
			budget -= 1
			local from = Fleet.cellOf(sea.width, ship)
			if Naval.seaAt(sea, from) == 0 then
				-- Корабль у самого берега мог оказаться на клетке без моря (после округления) — ищем рядом.
				from = Naval.waterNear(sea, from, 2) or from
			end
			local path = Naval.path(sea, from, ship.dest)
			if path == nil then
				ship.state = "patrol"
				ship.order = nil
				table.insert(happenings, { kind = "noPath", ship = ship })
			else
				ship.path = path
				ship.step = 1
				ship.state = "moving"
			end
		end
	end
end

-- Скорость корабля в клетках за игровую секунду на этой карте.
function Fleet.speed(kind: ShipKind, width: number): number
	return Fleet.stats(kind).speed * width / Config.UnitsReferenceMapWidth * Config.Naval.SpeedMul
end

-- Движение по пути на simDt.
function Fleet.move(fs: FleetState, width: number, simDt: number, happenings: { Happening })
	for _, ship in fs.ships do
		if ship.alive and ship.state == "moving" and ship.path ~= nil then
			local path = ship.path :: { number }
			local left = Fleet.speed(ship.kind, width) * simDt
			while left > 0 and ship.step <= #path do
				local p = path[ship.step]
				local tx, ty = p % width + 0.5, p // width + 0.5
				local dx, dy = tx - ship.x, ty - ship.y
				local d = math.sqrt(dx * dx + dy * dy)
				if d <= left then
					ship.x, ship.y = tx, ty
					left -= d
					ship.step += 1
				else
					ship.x += dx / d * left
					ship.y += dy / d * left
					left = 0
				end
			end
			if ship.step > #path then
				ship.path = nil
				ship.state = "patrol"
				table.insert(happenings, { kind = "arrived", ship = ship })
			end
		end
	end
end

local function dist2(a: Ship, b: Ship): number
	local dx, dy = a.x - b.x, a.y - b.y
	return dx * dx + dy * dy
end

-- Бой кораблей: эсминец бьёт ближайший корабль врага в радиусе. Урон в секунду — атака × ShipDamage / защита цели.
function Fleet.fight(
	fs: FleetState,
	width: number,
	simDt: number,
	atWar: (a: number, b: number) -> boolean,
	happenings: { Happening }
)
	local range = Config.Naval.DestroyerRange * width / Config.UnitsReferenceMapWidth
	local range2 = range * range
	local damage: { [Ship]: { amount: number, by: number } } = {}
	for _, d in fs.ships do
		if d.alive and d.kind == "Destroyer" then
			local best: Ship? = nil
			local bestD = range2
			for _, t in fs.ships do
				if t.alive and t.owner ~= d.owner and atWar(d.owner, t.owner) then
					local dd = dist2(d, t)
					-- Сначала транспорты (их топят), потом эсминцы.
					local weight = if t.kind == "Transport" then dd * 0.25 else dd
					if dd <= range2 and weight < bestD then
						best, bestD = t, weight
					end
				end
			end
			if best ~= nil then
				local stats = Fleet.stats(best.kind)
				local amount = Fleet.stats("Destroyer").attack * Config.Naval.ShipDamage / math.max(0.1, stats.defense)
				local entry = damage[best]
				if entry == nil then
					damage[best] = { amount = amount * simDt, by = d.owner }
				else
					entry.amount += amount * simDt
				end
			end
		end
	end
	for ship, e in damage do
		ship.hp -= e.amount
		if ship.hp <= 0 and ship.alive then
			ship.alive = false
			table.insert(happenings, { kind = "sunk", ship = ship, by = e.by })
		end
	end
end

-- Блокада: порт (клетка здания → причал, хозяин) заблокирован, если рядом с причалом эсминец врага.
-- Возвращает true, если набор заблокированных портов изменился.
function Fleet.updateBlockade(
	fs: FleetState,
	width: number,
	ports: { { cell: number, dock: number, owner: number } },
	atWar: (a: number, b: number) -> boolean
): boolean
	local range = Config.Naval.BlockadeRange * width / Config.UnitsReferenceMapWidth
	local range2 = range * range
	local now: { [number]: boolean } = {}
	for _, p in ports do
		local px, py = p.dock % width + 0.5, p.dock // width + 0.5
		for _, d in fs.ships do
			if d.alive and d.kind == "Destroyer" and d.state ~= "planning" and atWar(d.owner, p.owner) then
				local dx, dy = d.x - px, d.y - py
				if dx * dx + dy * dy <= range2 then
					now[p.cell] = true
					break
				end
			end
		end
	end
	local changed = false
	for cell in now do
		if not fs.blocked[cell] then
			changed = true
		end
	end
	for cell in fs.blocked do
		if not now[cell] then
			changed = true
		end
	end
	fs.blocked = now
	if changed then
		fs.version += 1
	end
	return changed
end

-- Убрать потопленные корабли и корабли выбывших.
function Fleet.cleanup(fs: FleetState, alive: (owner: number) -> boolean)
	local k = 1
	while k <= #fs.ships do
		local s = fs.ships[k]
		if not s.alive or not alive(s.owner) then
			s.alive = false
			table.remove(fs.ships, k)
		else
			k += 1
		end
	end
	for owner in fs.queues do
		if not alive(owner) then
			fs.queues[owner] = nil
		end
	end
end

-- Сила груза транспорта.
function Fleet.cargoPower(ship: Ship): number
	return if ship.cargo ~= nil then Forces.total(ship.cargo) else 0
end

return table.freeze(Fleet)
