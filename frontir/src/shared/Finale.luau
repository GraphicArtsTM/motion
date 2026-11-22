--!strict
--[[
	Finale — кульминация матча (GDD §15й Й3). Чистый модуль: идёт ли финал и почему — «лидер близко» (блок лидера
	отстаёт от доли для победы меньше чем на Finale.Margin; погаснет, только если откатился ещё на Hysteresis) или
	«время» (до лимита меньше Finale.Sec); последние CountdownSec — обратный отсчёт. Одно правило и для сервера
	(«Все против лидера» — MatchSim.stepFinale), и для клиента (баннер, полоса, контур лидера), и для музыки.
]]

local Config = require("./Config")
local Modes = require("./Modes")

export type Reason = "near" | "time"

export type Facts = {
	victoryShare: number, -- доля суши для победы (0..1)
	leaderShare: number, -- доля суши блока лидера (0..1)
	timeLeft: number?, -- секунд матча до лимита (nil — без лимита)
	nearAllowed: boolean, -- бывает ли в режиме финал «лидер близко» (Finale.nearAllowed)
}

export type State = {
	on: boolean,
	reason: Reason?,
	countdown: boolean, -- последние CountdownSec секунд
	urgent: boolean, -- последние UrgentSec секунд
}

local Finale = {}

-- Финал «лидер близко» — там, где побеждает доля суши одного блока (не «Команды», не «Охота», не «Обучение»).
function Finale.nearAllowed(rules: Modes.Rules): boolean
	return not rules.teams and not rules.capitalHunt and not rules.tutorial
end

-- Состояние финала; wasNear — шёл ли финал «лидер близко» до этого (запас Hysteresis, чтобы не мигал).
function Finale.state(f: Facts, wasNear: boolean): State
	local cfg = Config.Finale
	local margin = cfg.Margin + (if wasNear then cfg.Hysteresis else 0)
	local near = f.nearAllowed and f.victoryShare > 0 and f.leaderShare >= f.victoryShare - margin
	local left = f.timeLeft
	local time = left ~= nil and left <= cfg.Sec
	return {
		on = near or time,
		reason = if near then "near" elseif time then "time" else nil,
		countdown = left ~= nil and left <= cfg.CountdownSec,
		urgent = left ~= nil and left <= cfg.UrgentSec,
	}
end

-- Множитель фронта attacker против target в финале «лидер близко»: bloc — держава-лидер, союзники и вассалы.
function Finale.coalitionMul(bloc: { [number]: boolean }?, attacker: number, target: number): number
	if bloc == nil or bloc[attacker] or not bloc[target] then
		return 1
	end
	return Config.Finale.CoalitionSpeed
end

return table.freeze(Finale)
