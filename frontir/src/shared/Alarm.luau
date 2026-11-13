--!strict
--[[
	Alarm — тревога на экране матча (GDD §15ш Ш2), чистые правила без Roblox API:
	- state(входящих атак, войск) — показывать ли плашку «НА ВАС N АТАК — НЕТ ВОЙСК»;
	- alertName(цвет державы) — каким цветом палитры писать тревогу, чтобы он не сливался со своей державой.
]]

local Config = require("./Config")
local Palette = require("./Palette")

export type Rgb = Palette.Rgb
export type State = { kind: "noTroops", attacks: number }

local Alarm = {}

-- Тревога «нет войск»: на вас идёт хотя бы одна атака, а войск (дома и на фронтах) меньше одного.
function Alarm.state(incoming: number, army: number): State?
	if incoming >= 1 and army < 1 then
		return { kind = "noTroops", attacks = incoming }
	end
	return nil
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
