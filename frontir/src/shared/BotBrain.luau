--!strict
--[[
	BotBrain — решения простого бота (этап 2; уровни и личности — этап 5).
	Бот видит только то, что видел бы игрок (BotView), и отвечает тем же намерением (Intent), что и игрок:
	никаких читов (GDD §9).

	- Людей мало (меньше AttackWhenFill от максимума) — копит.
	- Рядом ничья земля — расширяется на неё (NeutralPercent).
	- Ничьей земли нет — бьёт самого слабого соседа, если сильнее его в NationAdvantage раз.
]]

local Config = require("./Config")
local Rng = require("./Rng")
local Types = require("./Types")

type Rng = Rng.Rng

export type Neighbour = { id: number, people: number }

export type BotView = {
	people: number,
	maxPeople: number,
	attacks: number, -- активных атак
	hasNeutral: boolean, -- рядом есть ничья земля
	neighbours: { Neighbour }, -- соседние державы
}

local BotBrain = {}

-- Через сколько секунд бот подумает снова.
function BotBrain.nextThinkDelay(rng: Rng): number
	local cfg = Config.Bots
	return cfg.ThinkMinSec + Rng.nextFloat(rng) * (cfg.ThinkMaxSec - cfg.ThinkMinSec)
end

function BotBrain.decide(view: BotView, _rng: Rng): Types.Intent?
	local cfg = Config.Bots
	if view.attacks >= cfg.MaxAttacks or view.people < view.maxPeople * cfg.AttackWhenFill then
		return nil
	end
	if view.hasNeutral then
		-- Если атака на ничью землю уже идёт, MatchSim сольёт отряды — это подкрепление.
		return { kind = "attack", target = 0, percent = cfg.NeutralPercent }
	end
	local weakest: Neighbour? = nil
	for _, n in view.neighbours do
		if weakest == nil or n.people < weakest.people then
			weakest = n
		end
	end
	if weakest ~= nil and view.people >= weakest.people * cfg.NationAdvantage then
		return { kind = "attack", target = weakest.id, percent = cfg.NationPercent }
	end
	return nil
end

return table.freeze(BotBrain)
