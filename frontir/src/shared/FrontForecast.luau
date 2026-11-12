--!strict
--[[
	FrontForecast — прогноз фронта для плашки перевеса (§15н). Чистый модуль: бой не меняет, только объясняет то,
	что сервер уже посчитал в бою (Fronts.battle, MatchSim.stepAttacks).

	- state — состояние по перевесу: свободно / стоит / медленно / наступает / прорыв.
	- why — главная причина торможения своего фронта: самый большой множитель обороны на линии
	  (снабжение, укреплённая линия, укрепления, река, местность, способность генерала); нет такого или фронт стоял бы
	  и без него — «мало войск».
	- needAttack / needDefense — сколько силы добавить атаке до полной скорости / обороне до остановки фронта.
	- lastsSec — на сколько реальных секунд хватит войск фронта при нынешних потерях (без разброса).
	- trend — перевес растёт или падает (с мёртвой зоной).
	- lines — готовые строки плашки (через Strings).
]]

local Config = require("./Config")
local Forces = require("./Forces")
local Fronts = require("./Fronts")
local Rng = require("./Rng")
local Strings = require("./Strings")
local Types = require("./Types")

export type State = "free" | "stalled" | "slow" | "advance" | "breakthrough"

-- Множители обороны на линии фронта (1 — не мешает).
export type Factors = {
	supply: number, -- без снабжения атака слабее: 1 / UnsuppliedPowerMul
	fortLine: number, -- укреплённая линия (§6.9)
	forts: number, -- здания-укрепления в провинциях линии
	river: number, -- берег реки
	terrain: number, -- средняя защита местности
	ability: number, -- способность генерала защитника (§6.15)
}

-- Что знает плашка о фронте.
export type View = {
	ratio: number,
	fighting: boolean,
	againstMe: boolean, -- фронт врага против игрока
	why: number, -- номер в FrontForecast.Whys (0 — причины нет)
	need: number, -- своему фронту — до полной скорости, против вас — обороны до остановки
	lasts: number?, -- реальных секунд войск фронта (nil — не теряет)
	trend: number, -- -1, 0, 1
}

export type Lines = {
	status: string, -- «Медленно ↑ · река»
	detail: string?, -- «+1.2K до ×2 · войск на ~40 с»
	advice: string?, -- «Лучше отступить»
}

local FrontForecast = {}

-- Коды причин: по сети уходит номер в списке (0 — нет причины). «garrison» — последний: множителя у него нет.
FrontForecast.Whys = table.freeze({ "supply", "fortLine", "forts", "river", "terrain", "ability", "garrison" })
FrontForecast.Garrison = #FrontForecast.Whys

function FrontForecast.state(ratio: number, fighting: boolean): State
	if not fighting or ratio == math.huge then
		return "free"
	end
	local c = Config.Combat
	if ratio <= 1 then
		return "stalled"
	elseif ratio < c.FullSpeedRatio then
		return "slow"
	elseif ratio < c.BreakthroughRatio then
		return "advance"
	end
	return "breakthrough"
end

-- Главная причина торможения (номер в Whys): только если перевес ниже полной скорости и идёт бой.
function FrontForecast.why(f: Factors, ratio: number, fighting: boolean): number
	if not fighting or ratio >= Config.Combat.FullSpeedRatio then
		return 0
	end
	local muls = { f.supply, f.fortLine, f.forts, f.river, f.terrain, f.ability }
	local best, bestMul = 0, Config.Forecast.ReasonMinMul
	for k, mul in muls do
		if mul > bestMul then
			best, bestMul = k, mul
		end
	end
	-- Причина — то, без чего фронт пошёл бы. Даже без самого большого множителя перевес ниже ×1 — дело в числе войск.
	if best == 0 or ratio * bestMul < 1 then
		return FrontForecast.Garrison
	end
	return best
end

-- Сколько силы добавить атаке, чтобы выйти на полную скорость (сила атаки почти линейна по войскам).
function FrontForecast.needAttack(power: number, ratio: number): number
	local full = Config.Combat.FullSpeedRatio
	if power <= 0 or ratio >= full then
		return 0
	end
	return power * (full / math.max(ratio, Config.Forecast.MinRatio) - 1)
end

-- Сколько силы обороны добавить на линии, чтобы перевес врага упал до ×1.
function FrontForecast.needDefense(defStrength: number, ratio: number): number
	if ratio <= 1 or ratio == math.huge or defStrength <= 0 then
		return 0
	end
	return defStrength * (ratio - 1)
end

-- На сколько реальных секунд хватит войск фронта: power / burn (в игровых секундах) / темп матча.
function FrontForecast.lastsSec(power: number, burn: number, simRate: number): number?
	if burn <= 0 or power <= 0 then
		return nil
	end
	return power / burn / math.max(simRate, 0.01)
end

-- Тренд перевеса: old — значение TrendSec назад (nil — истории ещё нет).
function FrontForecast.trend(old: number?, now: number): number
	if old == nil or old == now then
		return 0
	elseif old == math.huge then
		return -1
	elseif now == math.huge then
		return 1
	end
	local rel = (now - old) / math.max(old, Config.Forecast.MinRatio)
	if rel > Config.Forecast.TrendDeadband then
		return 1
	elseif rel < -Config.Forecast.TrendDeadband then
		return -1
	end
	return 0
end

-- §15н ч.2: прогноз до атаки — та же формула боя, что у сервера (Fronts.battle без потерь).
export type PreviewInput = {
	attack: Types.Forces, -- наши войска на фронт
	defenders: Types.Forces, -- его гарнизон (оценка)
	share: number, -- доля его гарнизона у этой линии
	counter: Types.Forces?, -- его встречный фронт против нас
	supplied: boolean,
	plain: number, -- средняя защита местности на линии
	river: number, -- × берег реки
	forts: number, -- × укрепления
}
export type Preview = { ratio: number, fighting: boolean, state: State, why: number, need: number }

local PREVIEW_RNG = Rng.new(1) -- без потерь случайность не нужна

function FrontForecast.preview(i: PreviewInput): Preview
	local attack: Types.Attack = {
		attacker = 0,
		target = 0,
		troops = 0,
		focus = nil,
		forces = i.attack,
		supplied = i.supplied,
		ratio = math.huge,
		fighting = false,
		lastAdvance = 0,
	}
	local result = Fronts.battle(
		attack,
		{ home = i.defenders, share = i.share, counter = i.counter },
		i.plain * i.river * i.forts,
		PREVIEW_RNG,
		0,
		false
	)
	local why = FrontForecast.why({
		supply = if i.supplied then 1 else 1 / Config.Combat.UnsuppliedPowerMul,
		fortLine = 1,
		forts = i.forts,
		river = i.river,
		terrain = i.plain,
		ability = 1,
	}, result.ratio, result.fighting)
	return {
		ratio = result.ratio,
		fighting = result.fighting,
		state = FrontForecast.state(result.ratio, result.fighting),
		why = why,
		need = FrontForecast.needAttack(Forces.total(i.attack), result.ratio),
	}
end

-- «×1.6», большой перевес и «обороны нет» — «×8+» (как плашка, Render.BattleFx.BadgeMaxShown).
function FrontForecast.ratioText(ratio: number): string
	local max = Config.Render.BattleFx.BadgeMaxShown
	if ratio >= max then
		return string.format("×%d+", max)
	end
	return string.format("×%.1f", math.max(0.1, ratio))
end

export type PreviewView = {
	ratio: number,
	state: State,
	why: number,
	need: number,
	existing: number?, -- перевес нашего фронта против него сейчас
	known: boolean, -- его силы известны
}

-- §15н ч.2: строки прогноза до атаки для подсказки над картой. atWar — идёт война (иначе «если начать войну»).
function FrontForecast.previewLines(v: PreviewView, atWar: boolean, lang: Strings.Lang): (string, string?)
	local ratio = (if v.known then "" else "≈") .. FrontForecast.ratioText(v.ratio)
	local existing = v.existing
	local head = if atWar and existing ~= nil
		then string.format(Strings.get("forecast.previewReinforce", lang), FrontForecast.ratioText(existing), ratio)
		elseif atWar then string.format(Strings.get("forecast.preview", lang), ratio)
		else string.format(Strings.get("forecast.previewDeclare", lang), ratio)
	head ..= " · " .. Strings.get("forecast.state." .. v.state, lang)
	if v.why > 0 and v.why <= #FrontForecast.Whys then
		head ..= " · " .. Strings.get("forecast.why." .. FrontForecast.Whys[v.why], lang)
	end
	local parts: { string } = {}
	if v.need > 0 then
		local full = string.format("%g", Config.Combat.FullSpeedRatio)
		table.insert(parts, string.format(Strings.get("forecast.need", lang), FrontForecast.short(v.need), full))
	end
	if not v.known then
		table.insert(parts, Strings.get("forecast.previewGuess", lang))
	end
	return head, if #parts > 0 then table.concat(parts, " · ") else nil
end

-- 1234 → «1.2K».
function FrontForecast.short(n: number): string
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.max(1, math.round(n)))
end

-- Строки плашки.
function FrontForecast.lines(v: View, lang: Strings.Lang): Lines
	local cfg = Config.Forecast
	local state = FrontForecast.state(v.ratio, v.fighting)
	local status = Strings.get((if v.againstMe then "forecast.enemy." else "forecast.state.") .. state, lang)
	if v.trend > 0 then
		status ..= " ↑"
	elseif v.trend < 0 then
		status ..= " ↓"
	end
	if not v.againstMe and v.why > 0 and v.why <= #FrontForecast.Whys then
		status ..= " · " .. Strings.get("forecast.why." .. FrontForecast.Whys[v.why], lang)
	end
	local parts: { string } = {}
	if v.need > 0 then
		if v.againstMe then
			table.insert(parts, string.format(Strings.get("forecast.needDef", lang), FrontForecast.short(v.need)))
		else
			local full = string.format("%g", Config.Combat.FullSpeedRatio)
			table.insert(parts, string.format(Strings.get("forecast.need", lang), FrontForecast.short(v.need), full))
		end
	end
	local lasts = v.lasts
	if not v.againstMe and lasts ~= nil and lasts < cfg.LastsShowSec then
		table.insert(parts, string.format(Strings.get("forecast.lasts", lang), math.max(1, math.round(lasts))))
	end
	local advice: string? = nil
	if
		not v.againstMe
		and (state == "stalled" or state == "slow")
		and v.trend <= 0
		and lasts ~= nil
		and lasts < cfg.RetreatBelowSec
	then
		advice = Strings.get("forecast.retreat", lang)
	end
	return {
		status = status,
		detail = if #parts > 0 then table.concat(parts, " · ") else nil,
		advice = advice,
	}
end

return table.freeze(FrontForecast)
