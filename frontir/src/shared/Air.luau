--!strict
--[[
	Air — авиация (GDD §6.13, этап 7б-2). Чистый модуль: самолёты, полёт по прямой, налёты по таймеру, перехват
	истребителями, батареи ПВО. Правила вокруг (найм, что бомбят, выход зданий из строя) — в MatchSim.

	Самолёт — точка (x, y) в клетках. Состояния:
	- based — стоит на аэродроме base;
	- flying — летит к точке (gx, gy): бомбардировщик — к цели, истребитель — к точке прикрытия или за целью;
	- raiding — бомбардировщик над целью: налёт раз в BombEverySec, всего RaidsPerSortie;
	- returning — летит на аэродром base.
]]

local Config = require("./Config")
local Types = require("./Types")

export type PlaneKind = "Fighter" | "Bomber"
export type PlaneState = "based" | "flying" | "raiding" | "returning"

export type Plane = {
	id: number,
	owner: number,
	kind: PlaneKind,
	x: number,
	y: number,
	hp: number,
	state: PlaneState,
	base: number, -- клетка аэродрома (здания)
	gx: number, -- куда летит
	gy: number,
	target: number?, -- бомбардировщик: клетка цели налёта
	raidsLeft: number,
	nextRaidAt: number,
	cover: number, -- истребитель: клетка, вокруг которой прикрывает
	chase: number?, -- истребитель: id самолёта, за которым гонится
	alive: boolean,
}

export type Build = { kind: PlaneKind, airfield: number, left: number }

export type AirState = {
	planes: { Plane },
	nextId: number,
	queues: { [number]: { Build } },
	disabled: { [number]: number }, -- клетка здания → до какого игрового времени выведено из строя
	version: number, -- растёт, когда меняется набор выведенных из строя зданий
}

-- Что случилось за шаг (MatchSim превращает в события и правила).
export type Happening =
	{ kind: "raid", plane: Plane, cell: number } -- бомбардировщик сбросил бомбы на клетку cell
	| { kind: "shot", plane: Plane, by: number } -- самолёт сбит

local Air = {}

function Air.new(): AirState
	return { planes = {}, nextId = 1, queues = {}, disabled = {}, version = 0 }
end

function Air.stats(kind: PlaneKind): Types.UnitStats
	return (Config.Units :: any)[kind]
end

function Air.maxHp(kind: PlaneKind): number
	return if kind == "Fighter" then Config.Air.FighterHp else Config.Air.BomberHp
end

-- Масштаб расстояний «на ширине 512» к этой карте.
function Air.scale(width: number): number
	return width / Config.UnitsReferenceMapWidth
end

function Air.speed(kind: PlaneKind, width: number): number
	return Air.stats(kind).speed * Air.scale(width) * Config.Air.SpeedMul
end

function Air.cellOf(width: number, p: Plane): number
	return math.floor(p.y) * width + math.floor(p.x)
end

local function center(width: number, cell: number): (number, number)
	return cell % width + 0.5, cell // width + 0.5
end

function Air.ofNation(as: AirState, owner: number): { Plane }
	local out: { Plane } = {}
	for _, p in as.planes do
		if p.alive and p.owner == owner then
			table.insert(out, p)
		end
	end
	return out
end

function Air.count(as: AirState, owner: number): number
	local q = as.queues[owner]
	return #Air.ofNation(as, owner) + (if q ~= nil then #q else 0)
end

function Air.byId(as: AirState, id: number): Plane?
	for _, p in as.planes do
		if p.alive and p.id == id then
			return p
		end
	end
	return nil
end

function Air.spawn(as: AirState, width: number, owner: number, kind: PlaneKind, airfield: number): Plane
	local x, y = center(width, airfield)
	local plane: Plane = {
		id = as.nextId,
		owner = owner,
		kind = kind,
		x = x,
		y = y,
		hp = Air.maxHp(kind),
		state = "based",
		base = airfield,
		gx = x,
		gy = y,
		target = nil,
		raidsLeft = 0,
		nextRaidAt = 0,
		cover = airfield,
		chase = nil,
		alive = true,
	}
	as.nextId = as.nextId % 65535 + 1
	table.insert(as.planes, plane)
	return plane
end

-- Свободный бомбардировщик державы, ближайший к клетке (стоит на аэродроме).
function Air.idleBomber(as: AirState, width: number, owner: number, cell: number): Plane?
	local tx, ty = center(width, cell)
	local best: Plane? = nil
	local bestD = math.huge
	for _, p in as.planes do
		if p.alive and p.owner == owner and p.kind == "Bomber" and p.state == "based" then
			local dx, dy = p.x - tx, p.y - ty
			local d = dx * dx + dy * dy
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	return best
end

-- Вылет бомбардировщика на налёт по клетке cell.
function Air.sortie(p: Plane, width: number, cell: number)
	p.target = cell
	p.gx, p.gy = center(width, cell)
	p.state = "flying"
	p.raidsLeft = Config.Air.RaidsPerSortie
end

-- Истребитель прикрывает клетку cell (летит туда и держится там).
function Air.coverAt(p: Plane, width: number, cell: number)
	p.cover = cell
	p.chase = nil
	p.gx, p.gy = center(width, cell)
	p.state = if cell == p.base then "returning" else "flying"
end

-- Шаг к точке (gx, gy); true — долетел.
local function fly(p: Plane, width: number, simDt: number): boolean
	local dx, dy = p.gx - p.x, p.gy - p.y
	local d = math.sqrt(dx * dx + dy * dy)
	local step = Air.speed(p.kind, width) * simDt
	if d <= step then
		p.x, p.y = p.gx, p.gy
		return true
	end
	p.x += dx / d * step
	p.y += dy / d * step
	return false
end

local function dist2(a: Plane, x: number, y: number): number
	local dx, dy = a.x - x, a.y - y
	return dx * dx + dy * dy
end

-- Шаг авиации на simDt: истребители выбирают цель, все летят, бомбардировщики делают налёты, бой в воздухе,
-- батареи ПВО (клетка, хозяин) стреляют. now — игровое время.
function Air.step(
	as: AirState,
	width: number,
	simDt: number,
	now: number,
	atWar: (a: number, b: number) -> boolean,
	batteries: { { cell: number, owner: number } },
	happenings: { Happening }
)
	local cfg = Config.Air
	local scale = Air.scale(width)
	local intercept2 = (cfg.InterceptRadius * scale) ^ 2
	local gun2 = (cfg.GunRange * scale) ^ 2
	-- Истребители: цель — бомбардировщик врага в круге прикрытия (ближайший), иначе — истребитель врага рядом.
	for _, f in as.planes do
		if f.alive and f.kind == "Fighter" then
			local cx, cy = center(width, f.cover)
			local best: Plane? = nil
			local bestD = math.huge
			for _, e in as.planes do
				if e.alive and e.owner ~= f.owner and atWar(f.owner, e.owner) then
					local inCover = dist2(e, cx, cy) <= intercept2
					if inCover then
						local d = dist2(e, f.x, f.y) * (if e.kind == "Bomber" then 0.25 else 1)
						if d < bestD then
							best, bestD = e, d
						end
					end
				end
			end
			if best ~= nil then
				f.chase = best.id
				f.gx, f.gy = best.x, best.y
				f.state = "flying"
			elseif f.chase ~= nil then
				f.chase = nil
				Air.coverAt(f, width, f.cover)
			end
		end
	end
	-- Полёт и налёты.
	for _, p in as.planes do
		if p.alive then
			if p.state == "flying" or p.state == "returning" then
				local arrived = fly(p, width, simDt)
				if arrived then
					if p.state == "returning" then
						p.state = "based"
					elseif p.kind == "Bomber" and p.target ~= nil then
						p.state = "raiding"
						p.nextRaidAt = now
					elseif p.kind == "Fighter" and p.chase == nil then
						p.state = if p.cover == p.base then "based" else "flying"
					end
				end
			end
			if p.state == "raiding" and now >= p.nextRaidAt then
				table.insert(happenings, { kind = "raid", plane = p, cell = p.target :: number })
				p.raidsLeft -= 1
				p.nextRaidAt = now + cfg.BombEverySec
				if p.raidsLeft <= 0 then
					p.target = nil
					p.state = "returning"
					p.gx, p.gy = center(width, p.base)
				end
			end
		end
	end
	-- Бой в воздухе: истребитель бьёт цель погони в радиусе стрельбы; батареи ПВО — самолёты врага в радиусе.
	local damage: { [Plane]: { amount: number, by: number } } = {}
	local function hit(target: Plane, amount: number, by: number)
		local e = damage[target]
		if e == nil then
			damage[target] = { amount = amount, by = by }
		else
			e.amount += amount
		end
	end
	for _, f in as.planes do
		if f.alive and f.kind == "Fighter" and f.chase ~= nil then
			local t: Plane? = nil
			for _, e in as.planes do
				if e.alive and e.id == f.chase then
					t = e
				end
			end
			if t ~= nil and dist2(t, f.x, f.y) <= gun2 then
				local defense = math.max(0.1, Air.stats(t.kind).defense)
				hit(t, Air.stats("Fighter").attack * cfg.AirDamage / defense * simDt, f.owner)
			end
		end
	end
	local battery2 = Config.Buildings.AirDefense.radius ^ 2
	for _, b in batteries do
		local bx, by = center(width, b.cell)
		for _, e in as.planes do
			if e.alive and e.owner ~= b.owner and atWar(b.owner, e.owner) and dist2(e, bx, by) <= battery2 then
				hit(e, cfg.BatteryDamage * simDt, b.owner)
			end
		end
	end
	for plane, e in damage do
		plane.hp -= e.amount
		if plane.hp <= 0 and plane.alive then
			plane.alive = false
			table.insert(happenings, { kind = "shot", plane = plane, by = e.by })
		end
	end
end

-- Самолёты без своего аэродрома: перелёт на ближайший (nearest(owner, x, y) → клетка или nil — тогда потерян).
function Air.rebase(
	as: AirState,
	width: number,
	hasAirfield: (cell: number, owner: number) -> boolean,
	nearest: (owner: number, x: number, y: number) -> number?
)
	for _, p in as.planes do
		if p.alive and not hasAirfield(p.base, p.owner) then
			local other = nearest(p.owner, p.x, p.y)
			if other == nil then
				p.alive = false
			else
				p.base = other
				if p.cover ~= other and not hasAirfield(p.cover, p.owner) then
					p.cover = other
				end
				if p.state == "based" or p.state == "returning" then
					p.state = "returning"
					p.gx, p.gy = center(width, other)
				end
			end
		end
	end
end

-- Выведенные из строя здания: истёкшие — снова работают. Возвращает true, если набор изменился.
function Air.repair(as: AirState, now: number): boolean
	local changed = false
	for cell, untilTime in as.disabled do
		if now >= untilTime then
			as.disabled[cell] = nil
			changed = true
		end
	end
	if changed then
		as.version += 1
	end
	return changed
end

function Air.isDisabled(as: AirState, cell: number, now: number): boolean
	local t = as.disabled[cell]
	return t ~= nil and now < t
end

function Air.cleanup(as: AirState, alive: (owner: number) -> boolean)
	local k = 1
	while k <= #as.planes do
		local p = as.planes[k]
		if not p.alive or not alive(p.owner) then
			p.alive = false
			table.remove(as.planes, k)
		else
			k += 1
		end
	end
	for owner in as.queues do
		if not alive(owner) then
			as.queues[owner] = nil
		end
	end
end

-- Доля урона с воздуха, которую гасит ПВО в составе войск (0..AAMaxReduction).
function Air.aaReduction(mix: { number }): number
	local cfg = Config.Air
	local aa = mix[4] or 0 -- Types.LandUnits[4] = AntiAir
	return cfg.AAMaxReduction * math.min(1, aa / cfg.AAFullShare)
end

return table.freeze(Air)
