--!strict
--!native
--[[
	Fronts — бой на фронте (GDD §6.7). Чистый модуль: считает перевес, потери, опыт и снабжение;
	клетки по исходу боя захватывает Expansion.advanceFront.

	Оборона фронта = доля гарнизона защитника (по длине этого фронта среди всех фронтов против него)
	+ войска его встречного фронта на той же границе. Сила защиты × бонус «на своей земле» × защита
	местности вдоль фронта. Атака без снабжения слабее и тает.
	Перевес = атака / оборона: > 1 — фронт идёт (скорость — кривая Combat.SpeedCurve, §15м), ≤ 1 — стоит.
	«Сверхдержава» (§15м): giant(доля суши) 0..1 — её фронт быстрее и теряет меньше, фронты против неё быстрее.
	Потери: каждая сторона теряет пропорционально силе противника (LossRate), с разбросом ±DamageSpread.
]]

local Config = require("./Config")
local Forces = require("./Forces")
local Grid = require("./Grid")
local MapData = require("./MapData")
local Rng = require("./Rng")
local Types = require("./Types")

type Grid = Grid.Grid
type MapData = MapData.MapData
type Attack = Types.Attack
type Forces = Types.Forces

export type Defense = {
	home: Forces, -- гарнизон защитника (весь)
	share: number, -- доля гарнизона на этом фронте (0..1); котёл защитника её уменьшает
	counter: Forces?, -- войска встречного фронта защитника на этой границе
	bonus: number?, -- множитель обороны (укреплённая линия, §6.9)
	armor: number?, -- защита танков защитника × (технология «Тяжёлая броня», §6.14)
	giantAttacker: number?, -- §15м: насколько атакующий — сверхдержава (0..1): его потери меньше
}

export type BattleResult = {
	ratio: number, -- атака / оборона (math.huge — обороны нет)
	fighting: boolean, -- у защитника есть войска на этом фронте
	lostAttacker: number, -- силы потеряно за этот шаг (бой и нехватка снабжения)
	lostDefender: number,
}

local Fronts = {}

-- Равномерная выборка до n клеток фронта.
local function sample(front: { number }, n: number): { number }
	if #front <= n then
		return front
	end
	local out: { number } = {}
	local step = #front / n
	for k = 0, n - 1 do
		table.insert(out, front[math.floor(k * step) + 1])
	end
	return out
end

-- Есть ли снабжение: средняя по выборке клеток фронта дистанция до ближайшего своего города
-- не больше SupplyRange (масштаб по ширине карты, эталон 512). friends — чьи ещё города снабжают
-- (союзники, вассалы, сюзерен, §8.1).
function Fronts.supplied(
	g: Grid,
	cities: { number },
	attacker: number,
	front: { number },
	friends: { [number]: boolean }?,
	rangeMul: number? -- технология «Снабжение» (§6.14): дальность ×
): boolean
	if #front == 0 then
		return true
	end
	local w = g.width
	local mine: { number } = {}
	for _, c in cities do
		local owner = Grid.getOwner(g, c)
		if owner == attacker or (friends ~= nil and owner ~= 0 and friends[owner]) then
			table.insert(mine, c)
		end
	end
	if #mine == 0 then
		return false
	end
	local range = Config.Combat.SupplyRange * w / Config.UnitsReferenceMapWidth * (rangeMul or 1)
	local sum, n = 0, 0
	for _, i in sample(front, Config.Combat.SupplySamples) do
		local best = math.huge
		for _, c in mine do
			best = math.min(best, (i % w - c % w) ^ 2 + (i // w - c // w) ^ 2)
		end
		sum += math.sqrt(best)
		n += 1
	end
	return sum / n <= range
end

-- Средняя защита местности вдоль фронта (§6.1); клетки за рекой (river) — с бонусом берега RiverBankDefense,
-- клетки провинций с укреплением защитника — ×fortified(cell) (Buildings.fortMul: 1 — нет укрепления).
function Fronts.terrainDefense(
	map: MapData,
	front: { number },
	river: { [number]: boolean }?,
	fortified: ((cell: number) -> number)?
): number
	local list = sample(front, Config.Combat.SupplySamples)
	if #list == 0 then
		return 1
	end
	local sum = 0
	for _, i in list do
		local d = Config.Terrain[MapData.getTerrain(map, i)].defense
		if river ~= nil and river[i] then
			d *= Config.Combat.RiverBankDefense
		end
		if fortified ~= nil then
			d *= fortified(i)
		end
		sum += d
	end
	return sum / #list
end

-- Бой на фронте за dt игровых секунд: потери и опыт обеих сторон. Возвращает перевес.
-- applyLosses = false — только посчитать перевес (встречный фронт пары уже воевал в этом тике).
function Fronts.battle(
	attack: Attack,
	defense: Defense,
	terrainDef: number,
	rng: Rng.Rng,
	dt: number,
	applyLosses: boolean
): BattleResult
	local cfg = Config.Combat
	local supplyMul = if attack.supplied then 1 else cfg.UnsuppliedPowerMul
	-- Состав противника для контр-типов: гарнизонная доля + встречный фронт.
	local defenders = Forces.new()
	for kind, s in defense.home do
		defenders[kind].strength = s.strength * defense.share
		defenders[kind].xp = s.xp
	end
	local counter = defense.counter
	if counter ~= nil then
		for kind, s in counter do
			Forces.add(defenders, kind, s.strength, s.xp)
		end
	end

	local attackPower = Forces.power(attack.forces, defenders, "attack") * supplyMul
	local homeDef = Forces.power(defense.home, attack.forces, "defense", defense.armor) * defense.share
	local counterDef = if counter ~= nil then Forces.power(counter, attack.forces, "defense", defense.armor) else 0
	local defensePower = (homeDef + counterDef) * cfg.DefenderHomeBonus * terrainDef * (defense.bonus or 1)

	local fighting = defensePower > 0
	local ratio = if fighting then attackPower / defensePower else math.huge
	local lostA, lostD = 0, 0

	if applyLosses and fighting then
		local spreadA = 1 + (Rng.nextFloat(rng) * 2 - 1) * cfg.DamageSpread
		local spreadD = 1 + (Rng.nextFloat(rng) * 2 - 1) * cfg.DamageSpread
		local toAttacker = defensePower
			* cfg.LossRate
			* dt
			* spreadA
			* (1 + (cfg.Giant.AttackerLossMin - 1) * (defense.giantAttacker or 0))
		local toDefender = attackPower * cfg.LossRate * dt * spreadD
		lostA = Forces.applyDamage(attack.forces, toAttacker)
		-- Урон защитнику делится между гарнизоном и встречным фронтом по их вкладу в оборону.
		local homeShare = if homeDef + counterDef > 0 then homeDef / (homeDef + counterDef) else 1
		lostD = Forces.applyDamage(defense.home, toDefender * homeShare)
		if counter ~= nil then
			lostD += Forces.applyDamage(counter, toDefender * (1 - homeShare))
		end
		Forces.gainXp(attack.forces, lostD)
		Forces.gainXp(defense.home, lostA * homeShare)
		if counter ~= nil then
			Forces.gainXp(counter, lostA * (1 - homeShare))
		end
	end
	if applyLosses and not attack.supplied then
		local before = Forces.total(attack.forces)
		Forces.attrition(attack.forces, cfg.OutOfSupplyLossPerSec * dt)
		lostA += before - Forces.total(attack.forces)
	end
	return { ratio = ratio, fighting = fighting, lostAttacker = lostA, lostDefender = lostD }
end

-- Скорость по перевесу (§15м): кривая Combat.SpeedCurve, между точками — по прямой, после последней — насыщение.
function Fronts.speedOf(ratio: number): number
	local curve = Config.Combat.SpeedCurve
	local first = curve[1]
	if ratio <= first[1] then
		return first[2]
	end
	for k = 2, #curve do
		local p, q = curve[k - 1], curve[k]
		if ratio <= q[1] then
			return p[2] + (q[2] - p[2]) * (ratio - p[1]) / (q[1] - p[1])
		end
	end
	return curve[#curve][2]
end

-- «Сверхдержава» (§15м): доля державы во всей захватываемой суше → 0..1 (плавно от FromShare до FullShare).
function Fronts.giant(share: number): number
	local g = Config.Combat.Giant
	local t = math.clamp((share - g.FromShare) / (g.FullShare - g.FromShare), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Множитель скорости фронта по перевесу и составу войск (танки быстрее, звёзды ускоряют); giantAttacker и
-- giantDefender — Fronts.giant атакующего и цели (§15м).
function Fronts.advanceMul(attack: Attack, ratio: number, giantAttacker: number?, giantDefender: number?): number
	local cfg = Config.Combat
	local speed = Fronts.speedOf(ratio)
	if speed <= 0 then
		return 0
	end
	local giant = (1 + (cfg.Giant.AttackerSpeedMax - 1) * (giantAttacker or 0))
		* (1 + (cfg.Giant.DefenderSpeedMax - 1) * (giantDefender or 0))
	return speed
		* cfg.FrontSpeedMul
		* giant
		* Forces.speedFactor(attack.forces)
		* (1 + Forces.avgStars(attack.forces) * cfg.VeteranStarBonus)
end

return table.freeze(Fronts)
