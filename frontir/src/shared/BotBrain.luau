--!strict
--[[
	BotBrain — решения простого бота (уровни и личности — этап 5).
	Бот видит только то, что видел бы игрок (BotView), и отвечает тем же намерением (Intent), что и игрок:
	никаких читов (GDD §9).

	- Иногда нанимает юниты (очередь не длиннее Bots.MaxQueue).
	- Людей мало (меньше AttackWhenFill от максимума) — копит.
	- Рядом ничья земля — расширяется на неё людьми (NeutralPercent); войска в той же доле идут
	  следом и берут ничейные города.
	- Ничьей земли нет — открывает фронт против соседа с самым слабым гарнизоном, если отправит
	  войск в NationAdvantage раз сильнее его гарнизона.
]]

local Config = require("./Config")
local Forces = require("./Forces")
local Rng = require("./Rng")
local Types = require("./Types")

type Rng = Rng.Rng

export type Neighbour = { id: number, people: number, power: number }

export type BotView = {
	people: number,
	maxPeople: number,
	attacks: number, -- активных атак и фронтов
	queue: number, -- юнитов в очереди найма
	power: number, -- сила гарнизона (войска дома)
	hasCapital: boolean,
	hasNeutral: boolean, -- рядом есть ничья земля, которую можно взять
	neighbours: { Neighbour }, -- соседние державы
}

local BotBrain = {}

-- Через сколько секунд бот подумает снова.
function BotBrain.nextThinkDelay(rng: Rng): number
	local cfg = Config.Bots
	return cfg.ThinkMinSec + Rng.nextFloat(rng) * (cfg.ThinkMaxSec - cfg.ThinkMinSec)
end

-- Какой юнит нанять: пехота чаще, танки и артиллерия реже.
local HIRE_ORDER: { Types.LandUnit } = { "Infantry", "Infantry", "Infantry", "Tanks", "Tanks", "Artillery" }

function BotBrain.decide(view: BotView, rng: Rng): Types.Intent?
	local cfg = Config.Bots
	if
		view.hasCapital
		and view.queue < cfg.MaxQueue
		and view.people >= view.maxPeople * cfg.HireWhenFill
		and Rng.nextFloat(rng) < cfg.HireChance
	then
		local unit: Types.LandUnit = HIRE_ORDER[Rng.range(rng, 1, #HIRE_ORDER)]
		local kind = Forces.kindIndex(unit) :: number
		if view.people >= Forces.stats(kind).people then
			return { kind = "hire", unit = unit }
		end
	end
	if view.attacks >= cfg.MaxAttacks then
		return nil
	end
	if view.hasNeutral then
		if view.people < view.maxPeople * cfg.AttackWhenFill then
			return nil
		end
		-- Если атака на ничью землю уже идёт, MatchSim сольёт отряды — это подкрепление.
		return { kind = "attack", target = 0, percent = cfg.NeutralPercent }
	end
	local weakest: Neighbour? = nil
	for _, n in view.neighbours do
		if weakest == nil or n.power < weakest.power then
			weakest = n
		end
	end
	local send = view.power * cfg.FrontPercent
	if weakest ~= nil and send >= math.max(Config.Forces.MinFrontStrength, weakest.power * cfg.NationAdvantage) then
		return { kind = "attack", target = weakest.id, percent = cfg.FrontPercent }
	end
	return nil
end

return table.freeze(BotBrain)
