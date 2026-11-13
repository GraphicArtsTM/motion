--!strict
--[[
	Stability — стабильность провинций и восстания (GDD §6.10, этап 7а). Чистый модуль: что нужно знать о матче,
	MatchSim передаёт через Context (войны, столицы, здания, метки), поэтому модуль не зависит от MatchSim.

	- Хозяин провинции — у кого её город; без города — у кого больше половины её клеток (§6.5).
	- Целевая стабильность: база и поправки (Config.Stability); текущая идёт к ней на ChangePerSec в секунду.
	- Провинция взята у другой державы — стабильность сразу не выше CaptureStart и поправка «недавний захват»;
	  новая провинция с ничьей земли начинает с SettleStart.
	- Ниже LowBelow — доход провинции меньше (summary: lowCells, lowCityLevels).
	- Ниже RevoltBelow RevoltDelaySec секунд подряд — восстание (§15д: таймер, а не шанс; update возвращает
	  список, начало отсчёта — в st.warnings); провинция столицы не восстаёт. Само восстание (клетки ничьи, город повстанцев) делает MatchSim, а модуль помечает провинцию
	  «Повстанцы» на RebelSec.
]]

local Config = require("./Config")
local Grid = require("./Grid")
local Provinces = require("./Provinces")
local Rng = require("./Rng")

type Grid = Grid.Grid

export type ProvinceState = {
	owner: number, -- 0 — хозяина нет (провинцию помним, чтобы отличить захват от заселения)
	lastOwner: number, -- последний хозяин (не 0); -1 — повстанцы
	value: number, -- текущая стабильность 0..100
	target: number, -- целевая (последний пересчёт)
	capturedAt: number?, -- когда взята у другой державы (поправка «недавний захват»)
	lowSince: number?, -- с какого момента ниже RevoltBelow (отсчёт до восстания, §15д)
}

export type Rebels = { province: number, from: number, untilTime: number }

-- Итог по державе: средняя стабильность (по клеткам своих провинций) и что даёт меньше дохода.
export type Summary = {
	average: number,
	provinces: number,
	lowCells: number, -- клеток державы в её провинциях ниже LowBelow
	lowCityLevels: number, -- уровней её городов в таких провинциях
}

export type State = {
	provinces: { [number]: ProvinceState },
	rebels: { [number]: Rebels }, -- провинция → повстанцы
	summary: { [number]: Summary },
	nextUpdateAt: number,
	nextRevoltAt: number,
	version: number, -- растёт при изменении повстанцев (рассылка)
	warnings: { { province: number, owner: number } }, -- начался отсчёт до восстания (MatchSim забирает в события)
}

-- Что модуль знает о матче.
export type Context = {
	grid: Grid,
	provinces: Provinces.ProvinceSet,
	cityOf: { [number]: number }, -- провинция → клетка города
	rng: Rng.Rng,
	now: number, -- игровое время
	capitalOf: (nation: number) -> number?,
	cityLevel: (cell: number) -> number,
	fort: (province: number, owner: number) -> boolean,
	atWar: (nation: number) -> boolean,
	weariness: (nation: number) -> number, -- 0..0.5 (Wars.weariness)
	traitor: (nation: number) -> boolean,
	bonus: ((nation: number) -> number)?, -- прибавка к целевой (технология «Порядок», §6.14)
	-- §15ч Ч1: в провинции станция, связанная дорогой со столицей, — штраф за удалённость × Rail.ConnectedDistanceMul.
	railConnected: ((province: number, owner: number) -> boolean)?,
}

export type Revolt = { province: number, owner: number }

local Stability = {}

function Stability.new(): State
	return {
		provinces = {},
		rebels = {},
		summary = {},
		nextUpdateAt = 0,
		nextRevoltAt = 0,
		version = 0,
		warnings = {},
	}
end

-- Хозяин провинции p по сетке: владелец города, иначе держава с больше чем половиной клеток (или 0).
function Stability.ownerOf(ctx: Context, p: number): number
	local g = ctx.grid
	local city = ctx.cityOf[p]
	if city ~= nil then
		local o = Grid.getOwner(g, city)
		if o ~= 0 then
			return o
		end
	end
	local province = ctx.provinces.list[p]
	local need = if province ~= nil then province.capturable else 0
	for owner, count in Grid.provinceOwners(g, p) do
		if count * 2 > need then
			return owner
		end
	end
	return 0
end

-- Расстояние от клетки a до b в клетках, приведённое к ширине DistanceRefWidth.
local function distance(g: Grid, a: number, b: number): number
	local w = g.width
	local dx, dy = a % w - b % w, a // w - b // w
	return math.sqrt(dx * dx + dy * dy) * Config.Stability.DistanceRefWidth / w
end

-- Целевая стабильность провинции p у хозяина owner (§6.10).
function Stability.target(ctx: Context, p: number, owner: number, capturedAt: number?): number
	local cfg = Config.Stability
	local province = ctx.provinces.list[p]
	local value = cfg.Base
	local capital = ctx.capitalOf(owner)
	if capital ~= nil and province ~= nil then
		if buffer.readu16(ctx.grid.province, capital * 2) == p then
			value += cfg.Capital
		else
			local d = distance(ctx.grid, capital, province.center)
			local penalty = math.min(cfg.DistanceMax, cfg.DistancePenalty * d / cfg.DistanceCells)
			local connected = ctx.railConnected
			if connected ~= nil and connected(p, owner) then
				penalty *= Config.Rail.ConnectedDistanceMul -- дорога до столицы (§15ч Ч1)
			end
			value -= penalty
		end
	end
	if ctx.atWar(owner) then
		value += cfg.War
	else
		value += cfg.Peace
	end
	value += cfg.WearinessMul * ctx.weariness(owner)
	if capturedAt ~= nil then
		local left = 1 - (ctx.now - capturedAt) / cfg.RecentCaptureSec
		if left > 0 then
			value += cfg.RecentCapture * left
		end
	end
	if ctx.traitor(owner) then
		value += cfg.Traitor
	end
	if ctx.bonus ~= nil then
		value += ctx.bonus(owner)
	end
	local city = ctx.cityOf[p]
	if city ~= nil and Grid.getOwner(ctx.grid, city) == owner then
		value += cfg.CityPerLevel * ctx.cityLevel(city)
	end
	if ctx.fort(p, owner) then
		value += cfg.Fort
	end
	return math.clamp(value, 0, 100)
end

-- Провинция капитала державы (или 0).
local function capitalProvince(ctx: Context, owner: number): number
	local capital = ctx.capitalOf(owner)
	return if capital ~= nil then buffer.readu16(ctx.grid.province, capital * 2) else 0
end

-- Пересчёт раз в UpdateSec: хозяева, целевая и текущая стабильность, итоги по державам, восстания.
-- Возвращает восстания этого шага (MatchSim делает провинции ничьими и зовёт Stability.revolt).
function Stability.update(st: State, ctx: Context): { Revolt }
	local cfg = Config.Stability
	local revolts: { Revolt } = {}
	if ctx.now < st.nextUpdateAt then
		return revolts
	end
	local dt = if st.nextUpdateAt > 0 then ctx.now - st.nextUpdateAt + cfg.UpdateSec else cfg.UpdateSec
	st.nextUpdateAt = ctx.now + cfg.UpdateSec

	-- Повстанцы, у которых вышел срок.
	for p, r in st.rebels do
		if ctx.now >= r.untilTime then
			st.rebels[p] = nil
			st.version += 1
		end
	end

	local summary: { [number]: Summary } = {}
	local weights: { [number]: number } = {}
	for _, province in ctx.provinces.list do
		local p = province.id
		local owner = Stability.ownerOf(ctx, p)
		local s = st.provinces[p]
		if owner == 0 then
			if s ~= nil then
				s.owner = 0
			end
			continue
		end
		local fresh = s == nil
		if s == nil then
			s = {
				owner = owner,
				lastOwner = owner,
				value = cfg.SettleStart,
				target = cfg.SettleStart,
				capturedAt = nil,
			}
			st.provinces[p] = s
		elseif s.owner ~= owner then
			if s.lastOwner ~= owner then
				-- Взята у другой державы или у повстанцев: сразу CaptureStart, к целевой — со следующего пересчёта.
				s.value = math.min(s.value, cfg.CaptureStart)
				s.capturedAt = ctx.now
				fresh = true
			end
			s.owner = owner
			s.lastOwner = owner
		end
		s.target = Stability.target(ctx, p, owner, s.capturedAt)
		local step = if fresh then 0 else cfg.ChangePerSec * dt -- новая и только что взятая — без шага
		if s.value < s.target then
			s.value = math.min(s.target, s.value + step)
		else
			s.value = math.max(s.target, s.value - step)
		end

		local cells = Grid.provinceCells(ctx.grid, p, owner)
		local sum = summary[owner]
		if sum == nil then
			sum = { average = 0, provinces = 0, lowCells = 0, lowCityLevels = 0 }
			summary[owner] = sum
		end
		sum.provinces += 1
		sum.average += s.value * cells
		weights[owner] = (weights[owner] or 0) + cells
		if s.value < cfg.LowBelow then
			sum.lowCells += cells
			local city = ctx.cityOf[p]
			if city ~= nil and Grid.getOwner(ctx.grid, city) == owner then
				sum.lowCityLevels += ctx.cityLevel(city)
			end
		end
	end
	for owner, sum in summary do
		local w = weights[owner] or 0
		sum.average = if w > 0 then sum.average / w else 0
	end
	st.summary = summary

	-- Восстания (§15д): провинция ниже RevoltBelow RevoltDelaySec секунд подряд (не столица, не уже повстанцы).
	-- Без случайности: начало отсчёта — предупреждение хозяину (st.warnings), поднял стабильность — отсчёт сброшен.
	for _, province in ctx.provinces.list do
		local p = province.id
		local s = st.provinces[p]
		if s ~= nil then
			local low = s.owner ~= 0
				and s.value < cfg.RevoltBelow
				and st.rebels[p] == nil
				and capitalProvince(ctx, s.owner) ~= p
			if not low then
				s.lowSince = nil
			elseif s.lowSince == nil then
				s.lowSince = ctx.now
				table.insert(st.warnings, { province = p, owner = s.owner })
			elseif ctx.now - (s.lowSince :: number) >= cfg.RevoltDelaySec then
				s.lowSince = nil
				table.insert(revolts, { province = p, owner = s.owner })
			end
		end
	end
	return revolts
end

-- Провинция p восстала против owner: «Повстанцы» на RebelSec; вернувший её — захват (CaptureStart).
function Stability.revolt(st: State, p: number, owner: number, now: number)
	st.rebels[p] = { province = p, from = owner, untilTime = now + Config.Stability.RebelSec }
	local s = st.provinces[p]
	if s ~= nil then
		s.owner = 0
		s.lastOwner = -1
	end
	st.version += 1
end

function Stability.isRebel(st: State, p: number): boolean
	return st.rebels[p] ~= nil
end

-- Стабильность провинции (nil — у провинции нет хозяина).
function Stability.valueOf(st: State, p: number): number?
	local s = st.provinces[p]
	return if s ~= nil and s.owner ~= 0 then s.value else nil
end

-- Все провинции державы со стабильностью (по возрастанию id).
function Stability.provincesOf(st: State, owner: number): { { province: number, value: number } }
	local out: { { province: number, value: number } } = {}
	for p, s in st.provinces do
		if s.owner == owner then
			table.insert(out, { province = p, value = s.value })
		end
	end
	table.sort(out, function(a, b): boolean
		return a.province < b.province
	end)
	return out
end

-- Итог по державе (средняя, клетки с низким доходом); держава без провинций — нули.
function Stability.summaryOf(st: State, owner: number): Summary
	return st.summary[owner] or { average = 0, provinces = 0, lowCells = 0, lowCityLevels = 0 }
end

-- Панель разработчика: все провинции державы — сразу value.
function Stability.setAll(st: State, owner: number, value: number)
	for _, s in st.provinces do
		if s.owner == owner then
			s.value = math.clamp(value, 0, 100)
		end
	end
end

-- Держава выбыла: её провинции забываем (новый хозяин — заселение).
function Stability.removeNation(st: State, owner: number)
	for p, s in st.provinces do
		if s.owner == owner or s.lastOwner == owner then
			st.provinces[p] = nil
		end
	end
	st.summary[owner] = nil
end

return table.freeze(Stability)
