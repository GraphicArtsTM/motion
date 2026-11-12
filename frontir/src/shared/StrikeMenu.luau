--!strict
--[[
	StrikeMenu — «можно ли ударить и что для этого нужно» (§15х ч.4, решение геймдизайнера: «где ракета, как отправить
	авиаудар — сделай понятным»). Чистый модуль: по фактам о державе игрока (и о цели) — готов ли удар, а если нет —
	первая причина по порядку, как до него дойти (технология → здание → самолёт → перезарядка → война → радиус).
	Причины совпадают с отказами сервера (MatchSim.launch / airIntent «raid» / useAbility), клиент показывает по ним
	подсказку «что сделать». Используют кольцо действий (ПКМ по врагу) и панель «УДАРЫ» слева.
]]

local Config = require("./Config")

local StrikeMenu = {}

export type Kind = "missile" | "raid" | "ability"

export type Why =
	"ok"
	| "notAtWar" -- нет активной войны (с целью или ни с кем)
	| "needTech" -- шахта: нужна технология «Ракетная шахта»
	| "needSilo" -- шахта: технология есть, шахты нет
	| "needAirfieldTech" -- налёт: нужна технология «Авиация»
	| "needAirfield" -- налёт: аэродрома нет
	| "needBomber" -- налёт: нет бомбардировщиков
	| "bombersBusy" -- налёт: все бомбардировщики в полёте
	| "outOfRange" -- налёт: цель дальше радиуса аэродромов
	| "cooldown" -- перезарядка (ракета или способность)
	| "noAbility" -- у генерала нет удара по врагу

export type Facts = {
	atWar: boolean, -- активная война с владельцем цели (без цели — хоть с кем-то)
	armyLevel: number, -- уровень ветки «Войска» (шахта)
	fleetLevel: number, -- уровень ветки «Флот» (аэродром)
	silo: boolean, -- есть работающая шахта
	missileLeft: number, -- секунд до готовности шахты
	airfields: number, -- работающих аэродромов
	inRange: boolean, -- цель в радиусе аэродромов (без цели — true)
	bombers: number, -- бомбардировщиков всего
	bombersReady: number, -- бомбардировщиков на аэродроме
	ability: string?, -- способность генерала против врага (Commanders.Ability) или nil
	abilityLeft: number, -- секунд до её готовности
}

-- Способности генерала, которые бьют по врагу (цель — его земля): их показывает кольцо и панель как «удар».
local ENEMY_ABILITIES: { [string]: boolean } = {
	Airstrike = true,
	SeaLanding = true,
	Airdrop = true,
	Propaganda = true,
	Blockade = true,
}
StrikeMenu.EnemyAbilities = table.freeze(ENEMY_ABILITIES)

-- Ракета из шахты (R).
function StrikeMenu.missile(f: Facts): Why
	if not f.silo then
		if f.armyLevel < Config.Tech.Unlocks.MissileSilo.level then
			return "needTech"
		end
		return "needSilo"
	end
	if f.missileLeft > 0 then
		return "cooldown"
	end
	if not f.atWar then
		return "notAtWar"
	end
	return "ok"
end

-- Налёт бомбардировщика с аэродрома.
function StrikeMenu.raid(f: Facts): Why
	if f.airfields <= 0 then
		if f.fleetLevel < Config.Tech.Unlocks.Airfield.level then
			return "needAirfieldTech"
		end
		return "needAirfield"
	end
	if f.bombers <= 0 then
		return "needBomber"
	end
	if f.bombersReady <= 0 then
		return "bombersBusy"
	end
	if not f.atWar then
		return "notAtWar"
	end
	if not f.inRange then
		return "outOfRange"
	end
	return "ok"
end

-- Способность генерала против врага (Q или E).
function StrikeMenu.ability(f: Facts): Why
	if f.ability == nil then
		return "noAbility"
	end
	if f.abilityLeft > 0 then
		return "cooldown"
	end
	if not f.atWar then
		return "notAtWar"
	end
	return "ok"
end

function StrikeMenu.check(kind: Kind, f: Facts): Why
	if kind == "missile" then
		return StrikeMenu.missile(f)
	elseif kind == "raid" then
		return StrikeMenu.raid(f)
	end
	return StrikeMenu.ability(f)
end

-- Ключ строки «что сделать» (Strings «strikeHow.<вид>.<причина>», общие причины — «strikeHow.<причина>»).
function StrikeMenu.howKey(kind: Kind, why: Why): string
	if why == "notAtWar" or why == "cooldown" then
		return "strikeHow." .. why
	end
	return "strikeHow." .. kind .. "." .. why
end

return table.freeze(StrikeMenu)
