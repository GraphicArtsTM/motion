--!strict
--[[
	Hints — подсказки «что делать дальше» (§15д ч.5: «как игра»). Чистый модуль: по тому, что видит игрок
	(Facts), выбирает одну подсказку — первую по порядку, условие которой выполнено и которую игрок не закрыл.
	Подсказка уходит сама, когда сделано (условие перестало выполняться). В обучении — не показываются
	(там свой ведущий, UI/TutorialPanel). Тексты — Strings «hint.<ключ>».
]]

local Config = require("./Config")

export type Facts = {
	time: number, -- секунд матча
	tutorial: boolean,
	attacks: number, -- своих атак и фронтов
	people: number,
	maxPeople: number,
	money: number,
	barracks: number, -- лучший уровень казарм
	factories: number,
	cityLevels: number, -- сумма уровней своих городов
	cities: number, -- своих городов
	troops: number, -- сила войск дома
	atWar: boolean,
	bombed: boolean, -- нас недавно бомбили
	batteries: number, -- своих батарей ПВО
	lowStability: boolean, -- есть провинции ниже LowBelow
}

local Hints = {}

-- Порядок важен: сверху — то, что нужно раньше.
Hints.Order = table.freeze({
	"expand",
	"barracks",
	"factory",
	"hire",
	"city",
	"tanks",
	"defense",
	"stability",
	"war",
}) :: { string }

local function want(key: string, f: Facts): boolean
	local cfg = Config.Hints
	local stats = Config.Buildings :: any
	if key == "expand" then
		return f.attacks == 0 and f.people >= f.maxPeople * cfg.ExpandFill and f.time < cfg.EarlySec
	elseif key == "barracks" then
		return f.barracks == 0 and f.money >= stats.Barracks.cost
	elseif key == "factory" then
		return f.factories == 0 and f.money >= stats.Factory.cost
	elseif key == "hire" then
		return f.barracks > 0 and f.troops < cfg.FewTroops and f.money >= Config.Units.Infantry.cost
	elseif key == "city" then
		return f.cities > 0 and f.cityLevels <= f.cities and f.money >= stats.City.cost
	elseif key == "tanks" then
		return f.barracks == 1 and f.atWar
	elseif key == "defense" then
		return f.bombed and f.batteries == 0
	elseif key == "stability" then
		return f.lowStability
	elseif key == "war" then
		return not f.atWar and f.time >= cfg.WarAfterSec and f.troops >= cfg.WarTroops
	end
	return false
end

-- Подсказка для игрока: ключ или nil. dismissed — закрытые игроком в этом матче.
function Hints.pick(f: Facts, dismissed: { [string]: boolean }): string?
	if f.tutorial then
		return nil
	end
	for _, key in Hints.Order do
		if not dismissed[key] and want(key, f) then
			return key
		end
	end
	return nil
end

return table.freeze(Hints)
