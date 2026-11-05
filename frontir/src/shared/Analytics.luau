--!strict
--[[
	Analytics — что отправлять в аналитику Roblox (GDD §15, этап 10в). Чистый модуль: собирает записи из матча,
	отправляет их сервер (Services/Telemetry через AnalyticsService). До трёх полей на запись — столько custom-полей
	у события в Roblox.

	- MatchEnd — длина матча (минуты); поля: режим, карта, причина победы.
	- Commander — выбор генерала игроком в начале игры (значение 1); поля: генерал, режим.
	- Leave — игрок вышел (минута матча); поля: фаза, режим, место по суше.
	- TutorialSkip — вышел из обучения, не пройдя его (номер шага).
	- Воронка обучения: шаги 1..N (Config.Tutorial.Steps) и N+1 — «пройдено».
]]

local Config = require("./Config")
local Grid = require("./Grid")
local MatchSim = require("./MatchSim")

type Match = MatchSim.Match

export type Record = { name: string, value: number, fields: { string } }
export type FunnelStep = { step: number, name: string }

local Analytics = {}

local function minutes(m: Match): number
	return math.floor(m.time / 60 * 10 + 0.5) / 10
end

-- Место державы по суше среди живых (1 — больше всех); выбывшая — последнее.
function Analytics.placeOf(m: Match, id: number): number
	local n = m.nations[id]
	if n == nil or not n.alive then
		return #m.nations
	end
	local mine = Grid.cellsOf(m.grid, id)
	local place = 1
	for _, other in m.nations do
		if other.alive and other.id ~= id and Grid.cellsOf(m.grid, other.id) > mine then
			place += 1
		end
	end
	return place
end

function Analytics.matchEnd(m: Match): Record
	local reason = if m.result ~= nil then (m.result :: any).reason else "none"
	return { name = "MatchEnd", value = minutes(m), fields = { m.rules.mode, m.map.name, tostring(reason) } }
end

-- Генералы игроков-людей (userId ~= nil) в начале игры.
function Analytics.commanders(m: Match, commanderOf: (id: number) -> string): { { nation: number, record: Record } }
	local out: { { nation: number, record: Record } } = {}
	for _, n in m.nations do
		if n.userId ~= nil and not n.isBot then
			table.insert(out, {
				nation = n.id,
				record = { name = "Commander", value = 1, fields = { commanderOf(n.id), m.rules.mode } },
			})
		end
	end
	return out
end

-- Игрок державы id выходит: где и когда. В обучении, не пройдя его, — ещё TutorialSkip.
function Analytics.leave(m: Match, id: number): { Record }
	local out: { Record } = {
		{
			name = "Leave",
			value = minutes(m),
			fields = { m.phase, m.rules.mode, tostring(Analytics.placeOf(m, id)) },
		},
	}
	if m.rules.tutorial and m.phase == "Play" and m.tutorialStep <= #Config.Tutorial.Steps then
		table.insert(out, { name = "TutorialSkip", value = m.tutorialStep, fields = { m.rules.mode } })
	end
	return out
end

-- Шаг воронки обучения из события матча (nil — событие не про обучение).
function Analytics.funnel(e: any): FunnelStep?
	if type(e) ~= "table" then
		return nil
	end
	local steps = Config.Tutorial.Steps
	if e.kind == "tutorial" and type(e.step) == "number" and steps[e.step] ~= nil then
		return { step = e.step, name = steps[e.step] } -- пройден шаг e.step
	elseif e.kind == "tutorialDone" then
		return { step = #steps + 1, name = "done" }
	end
	return nil
end

return table.freeze(Analytics)
