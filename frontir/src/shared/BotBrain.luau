--!strict
--[[
	BotBrain — решения простого бота (уровни и личности — этап 5).
	Бот видит только то, что видел бы игрок (BotView), и отвечает тем же намерением (Intent), что и игрок:
	никаких читов (GDD §9).

	- Иногда нанимает юниты (очередь не длиннее Bots.MaxQueue).
	- Долго воюет и сильно слабее врага — просит мира (белый, а если сам взял больше — «забрать захваченное»).
	- Идёт война — открывает или подкрепляет фронт против самого слабого врага, если войск хватает.
	- Людей мало (меньше AttackWhenFill от максимума) — копит.
	- Рядом ничья земля — расширяется на неё людьми (NeutralPercent); войска в той же доле идут
	  следом и берут ничейные города.
	- Ничьей земли нет и войн меньше MaxWars — объявляет войну соседу с самым слабым гарнизоном,
	  если отправит войск в NationAdvantage раз сильнее его гарнизона (§6.7а).
	- На предложение мира отвечает answerPeace: соглашается, если слабее врага.
]]

local Config = require("./Config")
local Forces = require("./Forces")
local Rng = require("./Rng")
local Types = require("./Types")

type Rng = Rng.Rng

export type Neighbour = {
	id: number,
	people: number,
	power: number, -- гарнизон соседа
	atWar: boolean, -- с ним идёт активная война (можно открыть фронт)
	canDeclare: boolean, -- можно объявить ему войну (нет войны и запрета после мира)
}

-- Война бота глазами бота.
export type WarView = {
	enemy: number,
	active: boolean, -- мобилизация закончилась
	age: number, -- секунд активной войны
	myGain: number, -- клеток взято у врага в этой войне
	theirGain: number, -- клеток враг взял у нас
	theirPower: number, -- вся сила врага (гарнизон и фронты)
	canPropose: boolean, -- нет висящего предложения и давно не просили
}

export type BotView = {
	people: number,
	maxPeople: number,
	attacks: number, -- активных атак и фронтов
	queue: number, -- юнитов в очереди найма
	power: number, -- сила гарнизона (войска дома)
	totalPower: number, -- гарнизон и фронты
	hasCapital: boolean,
	hasNeutral: boolean, -- рядом есть ничья земля, которую можно взять
	neighbours: { Neighbour }, -- соседние державы
	wars: { WarView },
}

-- Что бот знает, отвечая на предложение мира.
export type PeaceOffer = {
	terms: Types.PeaceTerms,
	myGain: number,
	theirGain: number,
	myPower: number,
	theirPower: number,
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
	-- Мир: долгая война, а мы сильно слабее.
	for _, war in view.wars do
		if
			war.active
			and war.canPropose
			and war.age >= cfg.MinWarSec
			and view.totalPower < war.theirPower * cfg.PeaceWhenWeaker
		then
			local terms: Types.PeaceTerms = if war.myGain > war.theirGain then "keep" else "white"
			return { kind = "peace", target = war.enemy, terms = terms }
		end
	end
	if view.attacks >= cfg.MaxAttacks then
		return nil
	end
	local send = view.power * cfg.FrontPercent
	-- Война идёт — фронт против самого слабого врага.
	local enemy: Neighbour? = nil
	for _, n in view.neighbours do
		if n.atWar and (enemy == nil or n.power < enemy.power) then
			enemy = n
		end
	end
	if enemy ~= nil and send >= Config.Forces.MinFrontStrength then
		return { kind = "attack", target = enemy.id, percent = cfg.FrontPercent }
	end
	if view.hasNeutral then
		if view.people < view.maxPeople * cfg.AttackWhenFill then
			return nil
		end
		-- Если атака на ничью землю уже идёт, MatchSim сольёт отряды — это подкрепление.
		return { kind = "attack", target = 0, percent = cfg.NeutralPercent }
	end
	-- Ничьей земли нет — объявить войну самому слабому соседу, если войск хватает.
	if #view.wars >= cfg.MaxWars then
		return nil
	end
	local weakest: Neighbour? = nil
	for _, n in view.neighbours do
		if n.canDeclare and (weakest == nil or n.power < weakest.power) then
			weakest = n
		end
	end
	if weakest ~= nil and send >= math.max(Config.Forces.MinFrontStrength, weakest.power * cfg.NationAdvantage) then
		return { kind = "declare", target = weakest.id }
	end
	return nil
end

-- Ответ бота на предложение мира.
function BotBrain.answerPeace(offer: PeaceOffer): boolean
	local cfg = Config.Bots
	if offer.terms == "capitulate" then
		return false
	end
	if offer.terms == "white" then
		-- Белый мир вернёт всё взятое: выгоден тому, кто проигрывает.
		return offer.myPower < offer.theirPower * cfg.AcceptWhiteWhenWeaker or offer.theirGain > offer.myGain
	end
	-- «Забрать захваченное»: соглашаемся, если сами взяли не меньше или сильно слабее.
	return offer.myGain >= offer.theirGain or offer.myPower < offer.theirPower * cfg.AcceptKeepWhenWeaker
end

return table.freeze(BotBrain)
