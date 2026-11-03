--!strict
--[[
	Fronts — бой на фронте (GDD §6.7). Чистый модуль: считает перевес, потери, опыт и снабжение;
	клетки по исходу боя захватывает Expansion.advanceFront.

	Оборона фронта = доля гарнизона защитника (по длине этого фронта среди всех фронтов против него)
	+ войска его встречного фронта на той же границе. Сила защиты × бонус «на своей земле» × защита
	местности вдоль фронта. Атака без снабжения слабее и тает.
	Перевес = атака / оборона: > 1 — фронт идёт (к FullSpeedRatio — с полной скоростью), ≤ 1 — стоит.
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
	share: number, -- доля гарнизона на этом фронте (0..1)
	counter: Forces?, -- войска встречного фронта защитника на этой границе
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
-- не больше SupplyRange (масштаб по ширине карты, эталон 512).
function Fronts.supplied(g: Grid, cities: { number }, attacker: number, front: { number }): boolean
	if #front == 0 then
		return true
	end
	local w = g.width
	local mine: { number } = {}
	for _, c in cities do
		if Grid.getOwner(g, c) == attacker then
			table.insert(mine, c)
		end
	end
	if #mine == 0 then
		return false
	end
	local range = Config.Combat.SupplyRange * w / Config.UnitsReferenceMapWidth
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

-- Средняя защита местности вдоль фронта (§6.1); клетки за рекой (river) — с бонусом берега RiverBankDefense.
function Fronts.terrainDefense(map: MapData, front: { number }, river: { [number]: boolean }?): number
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
	local homeDef = Forces.power(defense.home, attack.forces, "defense") * defense.share
	local counterDef = if counter ~= nil then Forces.power(counter, attack.forces, "defense") else 0
	local defensePower = (homeDef + counterDef) * cfg.DefenderHomeBonus * terrainDef

	local fighting = defensePower > 0
	local ratio = if fighting then attackPower / defensePower else math.huge
	local lostA, lostD = 0, 0

	if applyLosses and fighting then
		local spreadA = 1 + (Rng.nextFloat(rng) * 2 - 1) * cfg.DamageSpread
		local spreadD = 1 + (Rng.nextFloat(rng) * 2 - 1) * cfg.DamageSpread
		local toAttacker = defensePower * cfg.LossRate * dt * spreadA
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

-- Множитель скорости фронта по перевесу и составу войск (танки быстрее, звёзды ускоряют).
function Fronts.advanceMul(attack: Attack, ratio: number): number
	local cfg = Config.Combat
	if ratio <= 1 then
		return 0
	end
	local mul = math.clamp((ratio - 1) / (cfg.FullSpeedRatio - 1), 0, 1) * cfg.FrontSpeedMul
	if ratio >= cfg.BreakthroughRatio then
		mul *= cfg.BreakthroughMul
	end
	return mul * Forces.speedFactor(attack.forces) * (1 + Forces.avgStars(attack.forces) * cfg.VeteranStarBonus)
end

return table.freeze(Fronts)
