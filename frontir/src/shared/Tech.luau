--!strict
--[[
	Tech — технологии (GDD §6.14, этап 7в-1). Чистый модуль: уровни трёх веток у каждой державы и текущее исследование.
	Уровень ветки изучается только после предыдущего; одновременно — одно исследование. Цена (деньги) и время —
	Config.Tech.Cost / Sec по уровню; что даёт уровень — проверяет MatchSim через Tech.has. Закрытые уровни
	(Config.Tech.Locked) видны, но не изучаются (ракетная шахта и сеть ПВО — этап 7г).
]]

local Config = require("./Config")

export type Branch = "Army" | "Economy" | "Fleet"
export type Levels = { Army: number, Economy: number, Fleet: number }
export type Research = { branch: Branch, level: number, left: number, total: number }

export type TechState = {
	levels: { [number]: Levels },
	research: { [number]: Research },
	version: number, -- растёт при каждом изменении (рассылка)
}

local Tech = {}

local BRANCHES: { Branch } = { "Army", "Economy", "Fleet" }
Tech.Branches = BRANCHES

function Tech.new(): TechState
	return { levels = {}, research = {}, version = 0 }
end

local function levelsOf(ts: TechState, id: number): Levels
	local l = ts.levels[id]
	if l == nil then
		l = { Army = 0, Economy = 0, Fleet = 0 }
		ts.levels[id] = l
	end
	return l
end

function Tech.level(ts: TechState, id: number, branch: Branch): number
	local l = ts.levels[id]
	return if l == nil then 0 else (l :: any)[branch]
end

-- Изучен ли у державы уровень level ветки branch.
function Tech.has(ts: TechState, id: number, branch: Branch, level: number): boolean
	return Tech.level(ts, id, branch) >= level
end

function Tech.isLocked(branch: Branch, level: number): boolean
	local locked = (Config.Tech.Locked :: any)[branch]
	return locked ~= nil and level >= locked
end

-- Следующий уровень ветки, если его можно начать исследовать, иначе nil и причина.
function Tech.next(ts: TechState, id: number, branch: Branch): (number?, string?)
	if ts.research[id] ~= nil then
		return nil, "researching"
	end
	local level = Tech.level(ts, id, branch) + 1
	if level > #Config.Tech.Cost then
		return nil, "techMaxed"
	end
	if Tech.isLocked(branch, level) then
		return nil, "techLocked"
	end
	return level, nil
end

-- Начать исследование уровня level (проверки и оплата — у вызывающего).
function Tech.start(ts: TechState, id: number, branch: Branch, level: number)
	local sec = Config.Tech.Sec[level]
	ts.research[id] = { branch = branch, level = level, left = sec, total = sec }
	ts.version += 1
end

-- Шаг исследований на simDt. Возвращает законченные: { id, branch, level }.
function Tech.step(ts: TechState, simDt: number): { { id: number, branch: Branch, level: number } }
	local done: { { id: number, branch: Branch, level: number } } = {}
	for id, r in ts.research do
		r.left -= simDt
		if r.left <= 0 then
			ts.research[id] = nil
			local l = levelsOf(ts, id);
			(l :: any)[r.branch] = math.max((l :: any)[r.branch], r.level)
			table.insert(done, { id = id, branch = r.branch, level = r.level })
		end
	end
	if #done > 0 then
		ts.version += 1
		table.sort(done, function(a, b): boolean
			return a.id < b.id
		end)
	end
	return done
end

-- Сразу изучить уровень (панель разработчика).
function Tech.grant(ts: TechState, id: number, branch: Branch, level: number)
	local l = levelsOf(ts, id);
	(l :: any)[branch] = math.max((l :: any)[branch], level)
	ts.version += 1
end

function Tech.removeNation(ts: TechState, id: number)
	ts.levels[id] = nil
	ts.research[id] = nil
	ts.version += 1
end

return table.freeze(Tech)
