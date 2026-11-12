--!strict
--[[
	Economy — экономика державы. Этап 2: люди (GDD §6.3).
	Люди растут по логистической кривой: быстрее всего при среднем заполнении, медленно у нуля и у максимума.
	Максимум растёт с территорией. Деньги и нефть — этап 4.
]]

local Config = require("./Config")

local Economy = {}

-- Максимум людей при данном числе клеток.
-- Максимум людей: база, клетки (без котлов — их передаёт вызывающий) и уровни своих городов.
function Economy.maxPeople(cells: number, cityLevels: number?): number
	local cfg = Config.People
	return cfg.BaseMax + cfg.PerCell * cells + (cityLevels or 0) * Config.Economy.CityMaxPeoplePerLevel
end

-- Доход денег в секунду (§6.8): налог с клеток, уровни городов и заводы (§15д: factoryIncome); заводы ур. 3
-- дают долю incomeBonus ко всему доходу (§15х ч.6, с районами; доли складываются).
function Economy.income(cells: number, cityLevels: number, factoryIncome: number?, incomeBonus: number?): number
	local cfg = Config.Economy
	local base = cfg.TaxPerCellPerSec * cells + cfg.CityIncomePerLevel * cityLevels + (factoryIncome or 0)
	return base * (1 + (incomeBonus or 0))
end

-- Нефть в секунду с вышек (rigs — число вышек или сумма множителей их уровней, §15д).
function Economy.oilIncome(rigs: number): number
	return Config.Oil.PerRigPerSec * rigs
end

-- Содержание войск в секунду за всю силу (гарнизон и фронты).
function Economy.upkeep(strength: number): number
	return Config.Economy.UpkeepPerStrengthPerSec * strength
end

-- Прирост людей в секунду (может быть отрицательным, если людей больше максимума).
function Economy.growthPerSec(people: number, max: number): number
	local cfg = Config.People
	if people > max then
		return -(people - max) * cfg.OverflowDecayPerSec
	end
	return cfg.GrowthRate * people * (1 - people / max) + cfg.MinGrowthPerSec * (1 - people / max)
end

-- Люди через dt секунд. growthMul — множитель положительного прироста (усталость от войны, §6.7а).
function Economy.grow(people: number, max: number, dt: number, growthMul: number?): number
	local growth = Economy.growthPerSec(people, max)
	if growth > 0 and growthMul ~= nil then
		growth *= growthMul
	end
	local nextPeople = people + growth * dt
	if people <= max then
		nextPeople = math.min(nextPeople, max)
	else
		nextPeople = math.max(nextPeople, max)
	end
	return math.max(0, nextPeople)
end

return table.freeze(Economy)
