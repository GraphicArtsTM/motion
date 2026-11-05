--!strict
--!native
--[[
	Forces — войска как пул державы (GDD §6.6–6.7). Войска — массив отрядов по типам (Types.LandUnits):
	у каждого суммарная сила и средний опыт. Чистая математика боя на фронте:
	- сила = Σ сила типа × атака/защита типа × ветеранство × контр-тип против состава противника;
	- потери распределяются по типам: кто слабее в защите, тот теряет больше, артиллерия — меньше;
	- опыт растёт от нанесённого урона; звёзды по порогам Config.Combat.StarXp; новобранцы разбавляют опыт.
]]

local Config = require("./Config")
local Types = require("./Types")

type Forces = Types.Forces
type Squad = Types.Squad

local Forces = {}

Forces.KINDS = #Types.LandUnits

local STATS: { Types.UnitStats } = {}
for k, name in Types.LandUnits do
	local u = Config.Units
	STATS[k] = if name == "Tanks"
		then u.Tanks
		elseif name == "Artillery" then u.Artillery
		elseif name == "AntiAir" then u.AntiAir
		else u.Infantry
end

-- strong[a][d] — тип a силён против типа d.
local STRONG: { { [number]: boolean } } = {}
for a, name in Types.LandUnits do
	STRONG[a] = {}
	local list: { string } = (Config.Counters :: any)[name] or {}
	for _, victim in list do
		local d = table.find(Types.LandUnits, victim)
		if d ~= nil then
			STRONG[a][d] = true
		end
	end
end

local ARTILLERY = table.find(Types.LandUnits, "Artillery") :: number

function Forces.new(): Forces
	local f: Forces = {}
	for k = 1, Forces.KINDS do
		f[k] = { strength = 0, xp = 0 }
	end
	return f
end

function Forces.stats(kind: number): Types.UnitStats
	return STATS[kind]
end

function Forces.kindIndex(name: string): number?
	return table.find(Types.LandUnits, name)
end

function Forces.total(f: Forces): number
	local sum = 0
	for _, s in f do
		sum += s.strength
	end
	return sum
end

function Forces.stars(s: Squad): number
	local stars = 0
	for _, need in Config.Combat.StarXp do
		if s.xp >= need then
			stars += 1
		end
	end
	return math.min(stars, Config.Combat.MaxVeteranStars)
end

function Forces.vetMul(s: Squad): number
	return 1 + Forces.stars(s) * Config.Combat.VeteranStarBonus
end

-- Средние звёзды войск (взвешенные по силе) — для скорости фронта.
function Forces.avgStars(f: Forces): number
	local total = Forces.total(f)
	if total <= 0 then
		return 0
	end
	local sum = 0
	for _, s in f do
		sum += Forces.stars(s) * s.strength
	end
	return sum / total
end

-- Добавляет силу в отряд типа kind; опыт усредняется (новобранцы разбавляют ветеранов).
function Forces.add(f: Forces, kind: number, strength: number, xp: number?)
	if strength <= 0 then
		return
	end
	local s = f[kind]
	local total = s.strength + strength
	s.xp = (s.xp * s.strength + (xp or 0) * strength) / total
	s.strength = total
end

-- Забирает долю share (0..1) каждого типа и возвращает её как отдельные войска (с тем же опытом).
function Forces.take(f: Forces, share: number): Forces
	local out = Forces.new()
	local k = math.clamp(share, 0, 1)
	for kind, s in f do
		local part = s.strength * k
		s.strength -= part
		out[kind].strength = part
		out[kind].xp = s.xp
	end
	return out
end

function Forces.merge(into: Forces, from: Forces)
	for kind, s in from do
		Forces.add(into, kind, s.strength, s.xp)
		s.strength = 0
	end
end

-- Доли типов в составе (сумма 1; пустые войска — нули).
function Forces.composition(f: Forces): { number }
	local total = Forces.total(f)
	local out: { number } = {}
	for kind, s in f do
		out[kind] = if total > 0 then s.strength / total else 0
	end
	return out
end

-- Множитель контр-типа для типа kind против состава противника.
local function counterMul(kind: number, enemy: { number }): number
	local mul = 0
	local any = 0
	for d, share in enemy do
		any += share
		mul += share * (if STRONG[kind][d] then Config.Combat.CounterBonus else 1)
	end
	return if any > 0 then mul / any else 1
end

-- Сила войск в атаке ("attack") или обороне ("defense") против войск enemy.
function Forces.power(f: Forces, enemy: Forces, role: "attack" | "defense"): number
	local enemyComp = Forces.composition(enemy)
	local sum = 0
	for kind, s in f do
		if s.strength > 0 then
			local stat = if role == "attack" then STATS[kind].attack else STATS[kind].defense
			sum += s.strength * stat * Forces.vetMul(s) * counterMul(kind, enemyComp)
		end
	end
	return sum
end

-- Темп фронта по составу: скорость типов относительно пехоты (танки быстрее, артиллерия медленнее).
function Forces.speedFactor(f: Forces): number
	local total = Forces.total(f)
	if total <= 0 then
		return 1
	end
	local base = STATS[1].speed
	local sum = 0
	for kind, s in f do
		sum += s.strength / total * STATS[kind].speed / base
	end
	return sum
end

-- Урон войскам: делится по типам — больше достаётся слабым в защите, артиллерии — меньше.
-- Возвращает, сколько силы реально потеряно.
function Forces.applyDamage(f: Forces, damage: number): number
	if damage <= 0 then
		return 0
	end
	local weights: { number } = {}
	local sum = 0
	for kind, s in f do
		local wgt = 0
		if s.strength > 0 then
			wgt = s.strength / math.max(0.05, STATS[kind].defense)
			if kind == ARTILLERY then
				wgt *= Config.Combat.ArtilleryLossMul
			end
		end
		weights[kind] = wgt
		sum += wgt
	end
	if sum <= 0 then
		return 0
	end
	local lost = 0
	for kind, s in f do
		local d = math.min(s.strength, damage * weights[kind] / sum)
		s.strength -= d
		lost += d
	end
	return lost
end

-- Опыт за нанесённый урон: каждому типу пропорционально его вкладу, в «своих силах».
function Forces.gainXp(f: Forces, dealt: number)
	local total = Forces.total(f)
	if total <= 0 or dealt <= 0 then
		return
	end
	for _, s in f do
		if s.strength > 0 then
			s.xp += dealt / total
		end
	end
end

-- Отнимает долю каждого типа (истощение без снабжения): strength × (1 − loss).
function Forces.attrition(f: Forces, loss: number)
	local k = math.clamp(1 - loss, 0, 1)
	for _, s in f do
		s.strength *= k
	end
end

return table.freeze(Forces)
