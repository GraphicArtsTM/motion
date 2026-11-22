--!strict
--[[
	MatchTasks — задачи матча (GDD §15й Й1): у игрока-человека всегда одна короткая задача с таймером и наградой.
	Чистый модуль: какие задачи можно дать по фактам о державе (их собирает MatchSim), выбор по весам, награда
	с серией, итог (выполнено / не успели). Время — игровое (simTime). Числа — Config.Tasks.
]]

local Config = require("./Config")
local Rng = require("./Rng")

type Rng = Rng.Rng

export type Kind = "City" | "Land" | "Build" | "Front"

export type Task = {
	id: number, -- номер задачи у державы (растёт)
	kind: Kind,
	cell: number, -- City: клетка города; иначе 0
	target: number, -- Front: враг; City: хозяин города в момент выдачи (0 — ничей); иначе 0
	building: string, -- Build: вид здания; иначе ""
	need: number, -- Land: клеток всего; Front: клеток у врага; City / Build: 1
	base: number, -- Front: сколько клеток врага уже было взято до выдачи; Land: клеток в момент выдачи
	have: number, -- прогресс (обновляет MatchSim)
	startAt: number,
	deadline: number,
	reward: number, -- денег за выполнение (с серией на момент выдачи)
}

export type State = {
	task: Task?,
	nextAt: number, -- simTime, раньше которого новую задачу не выдаём
	streak: number, -- выполнено подряд
	lastKind: Kind?,
	done: number,
	failed: number,
	nextId: number,
}

-- Что MatchSim знает о державе для выбора задачи.
export type Facts = {
	now: number,
	cells: number,
	totalLand: number,
	neutralNear: boolean, -- у границы есть ничья земля
	cities: { { cell: number, owner: number } }, -- города, которые можно взять сейчас, ближние первыми
	missing: { string }, -- каких зданий из Tasks.Build.Order нет (в том же порядке)
	enemies: { { id: number, taken: number } }, -- активные войны и сколько клеток врага уже взято
	income: number, -- денег в секунду
}

export type Outcome = "active" | "done" | "failed"

local MatchTasks = {}

MatchTasks.Kinds = table.freeze({ "City", "Land", "Build", "Front" } :: { Kind })

function MatchTasks.new(): State
	return {
		task = nil,
		nextAt = Config.Tasks.FirstSec,
		streak = 0,
		lastKind = nil,
		done = 0,
		failed = 0,
		nextId = 1,
	}
end

-- Какие виды задач можно дать сейчас (в порядке MatchTasks.Kinds).
function MatchTasks.options(facts: Facts): { Kind }
	local cfg = Config.Tasks
	local out: { Kind } = {}
	for _, kind: Kind in MatchTasks.Kinds do
		local ok = false
		if kind == "City" then
			ok = #facts.cities > 0
		elseif kind == "Land" then
			ok = facts.neutralNear and facts.cells + MatchTasks.landStep(facts) <= facts.totalLand
		elseif kind == "Build" then
			ok = #facts.missing > 0 and facts.now <= cfg.Build.UntilSec
		elseif kind == "Front" then
			ok = #facts.enemies > 0
		end
		if ok then
			table.insert(out, kind)
		end
	end
	return out
end

-- Сколько клеток добавить для задачи «Земля».
function MatchTasks.landStep(facts: Facts): number
	local cfg = Config.Tasks.Land
	return math.max(cfg.MinCells, math.ceil(facts.totalLand * cfg.Add))
end

-- Сколько клеток врага отбить для задачи «Фронт».
function MatchTasks.frontStep(cells: number): number
	local cfg = Config.Tasks.Front
	return math.max(cfg.MinCells, math.ceil(cells * cfg.Share))
end

-- Множитель серии: каждая выполненная подряд +Step, не больше Max.
function MatchTasks.streakMul(streak: number): number
	local cfg = Config.Tasks.Streak
	return math.min(cfg.Max, 1 + cfg.Step * math.max(0, streak))
end

-- Награда за задачу вида kind при доходе income (в секунду) и серии streak. Целые деньги, округление до 10.
function MatchTasks.reward(kind: Kind, income: number, streak: number): number
	local cfg = Config.Tasks.Reward
	local base = math.max(cfg.Min, math.max(0, income) * cfg.IncomeSec)
	local value = base * (cfg.KindMul[kind] or 1) * MatchTasks.streakMul(streak)
	return math.floor(value / 10 + 0.5) * 10
end

-- Срок задачи вида kind, игровых секунд.
function MatchTasks.duration(kind: Kind): number
	return (Config.Tasks :: any)[kind].Sec
end

-- Выбор вида по весам; прежний вид — только если других нет.
local function pickKind(options: { Kind }, last: Kind?, rng: Rng): Kind?
	local pool: { Kind } = {}
	for _, k: Kind in options do
		if k ~= last then
			table.insert(pool, k)
		end
	end
	if #pool == 0 then
		pool = options
	end
	if #pool == 0 then
		return nil
	end
	local weights: { [string]: number } = Config.Tasks.Weights :: any
	local sum = 0
	for _, k: Kind in pool do
		sum += weights[k] or 0
	end
	if sum <= 0 then
		return pool[1]
	end
	local r = Rng.nextFloat(rng) * sum
	for _, k: Kind in pool do
		r -= weights[k] or 0
		if r < 0 then
			return k
		end
	end
	return pool[#pool]
end

-- Новая задача, если пора и есть из чего выбрать (иначе nil, state не меняется, кроме nextAt при пустом выборе).
function MatchTasks.choose(state: State, facts: Facts, rng: Rng): Task?
	if state.task ~= nil or facts.now < state.nextAt then
		return nil
	end
	local kind: Kind? = pickKind(MatchTasks.options(facts), state.lastKind, rng)
	if kind == nil then
		state.nextAt = facts.now + Config.Tasks.RetrySec
		return nil
	end
	local task: Task = {
		id = state.nextId,
		kind = kind,
		cell = 0,
		target = 0,
		building = "",
		need = 1,
		base = 0,
		have = 0,
		startAt = facts.now,
		deadline = facts.now + MatchTasks.duration(kind),
		reward = MatchTasks.reward(kind, facts.income, state.streak),
	}
	if kind == "City" then
		local n = math.min(#facts.cities, Config.Tasks.City.Pick)
		local c = facts.cities[Rng.range(rng, 1, n)]
		task.cell = c.cell
		task.target = c.owner
	elseif kind == "Land" then
		task.base = facts.cells
		task.need = facts.cells + MatchTasks.landStep(facts)
		task.have = facts.cells
	elseif kind == "Build" then
		task.building = facts.missing[1]
	elseif kind == "Front" then
		local e = facts.enemies[Rng.range(rng, 1, #facts.enemies)]
		task.target = e.id
		task.base = e.taken
		task.need = MatchTasks.frontStep(facts.cells)
	end
	state.nextId += 1
	state.task = task
	state.lastKind = kind
	return task
end

-- Итог задачи: выполнена (have ≥ need), время вышло или ещё идёт.
function MatchTasks.status(task: Task, now: number): Outcome
	if task.have >= task.need then
		return "done"
	elseif now >= task.deadline then
		return "failed"
	end
	return "active"
end

-- Закрыть задачу: done — серия +1, иначе с начала. Следующая — через GapSec.
function MatchTasks.finish(state: State, done: boolean, now: number)
	if done then
		state.streak += 1
		state.done += 1
	else
		state.streak = 0
		state.failed += 1
	end
	state.task = nil
	state.nextAt = now + Config.Tasks.GapSec
end

-- Пропустить: как провал (серия с начала), но без счёта в «не успели».
function MatchTasks.skip(state: State, now: number): boolean
	if state.task == nil then
		return false
	end
	state.streak = 0
	state.task = nil
	state.nextAt = now + Config.Tasks.GapSec
	return true
end

return table.freeze(MatchTasks)
