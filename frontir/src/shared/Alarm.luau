--!strict
--[[
	Alarm — тревога на экране матча (GDD §15ш Ш2), чистые правила без Roblox API:
	- state(перевесы атак на вас, войск) — плашка «НА ВАС АТАКУЮТ — НЕТ ВОЙСК» или «ФРОНТ ПРОСЕДАЕТ» (перевес
	  врага на фронте не меньше Render.Alarm.LosingRatio; перевес видят обе стороны фронта — туман его не прячет);
	- alertName(цвет державы) — каким цветом палитры писать тревогу, чтобы он не сливался со своей державой.
]]

local Config = require("./Config")
local Palette = require("./Palette")

export type Rgb = Palette.Rgb
export type Kind = "noTroops" | "losing"
export type State = { kind: Kind, attacks: number } -- attacks: все атаки на вас («нет войск») или проседающие фронты

local Alarm = {}

-- ratios — перевес каждой атаки на вас (атакующий / оборона; math.huge — обороны нет).
-- «Нет войск»: на вас идёт хотя бы одна атака, а войск (дома и на фронтах) меньше одного.
-- «Фронт проседает»: войска есть, но хотя бы на одном фронте перевес врага не меньше LosingRatio.
function Alarm.state(ratios: { number }, army: number): State?
	if #ratios == 0 then
		return nil
	end
	if army < 1 then
		return { kind = "noTroops", attacks = #ratios }
	end
	local losing = 0
	for _, r in ratios do
		if r >= Config.Render.Alarm.LosingRatio then
			losing += 1
		end
	end
	return if losing > 0 then { kind = "losing", attacks = losing } else nil
end

function Alarm.distance(a: Rgb, b: Rgb): number
	local dr, dg, db = a.r - b.r, a.g - b.g, a.b - b.b
	return math.sqrt(dr * dr + dg * dg + db * db)
end

-- Имя цвета палитры для тревоги: первый из Render.Alarm.AlertColors, далёкий от цвета своей державы.
-- Державы нет (зритель, хаб) — первый цвет списка.
function Alarm.alertName(nation: Rgb?): string
	local cfg = Config.Render.Alarm
	local names = cfg.AlertColors :: { string }
	if nation == nil then
		return names[1]
	end
	for _, name in names do
		local c = Palette.ByName[name]
		if c ~= nil and Alarm.distance(c, nation) >= cfg.MinColorDist then
			return name
		end
	end
	return names[1]
end

return table.freeze(Alarm)
