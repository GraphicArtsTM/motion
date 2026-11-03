--!strict
--[[
	Economy — экономика державы. Этап 2: люди (GDD §6.3).
	Люди растут по логистической кривой: быстрее всего при среднем заполнении, медленно у нуля и у максимума.
	Максимум растёт с территорией. Деньги и нефть — этап 4.
]]

local Config = require("./Config")

local Economy = {}

-- Максимум людей при данном числе клеток.
function Economy.maxPeople(cells: number): number
	local cfg = Config.People
	return cfg.BaseMax + cfg.PerCell * cells
end

-- Прирост людей в секунду (может быть отрицательным, если людей больше максимума).
function Economy.growthPerSec(people: number, max: number): number
	local cfg = Config.People
	if people > max then
		return -(people - max) * cfg.OverflowDecayPerSec
	end
	return cfg.GrowthRate * people * (1 - people / max) + cfg.MinGrowthPerSec * (1 - people / max)
end

-- Люди через dt секунд.
function Economy.grow(people: number, max: number, dt: number): number
	local nextPeople = people + Economy.growthPerSec(people, max) * dt
	if people <= max then
		nextPeople = math.min(nextPeople, max)
	else
		nextPeople = math.max(nextPeople, max)
	end
	return math.max(0, nextPeople)
end

return table.freeze(Economy)
