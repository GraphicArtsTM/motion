--!strict
--[[
	UiFit — масштаб интерфейса под экран (GDD §15ц Ц1), чистый модуль без Roblox API.
	Размеры интерфейса в коде — «условные пиксели» экрана высотой Config.Render.UiScale.RefHeightPx. На экране
	крупнее всё растёт одним множителем (клиент ставит его в UIScale слоёв HUD, меню и окон), поэтому на мониторе
	2560×1440 или 3440×1440 кнопки и текст той же доли экрана, что и на 1600×900, а не мельче.
	- scale(w, h): множитель по размеру экрана в настоящих пикселях;
	- toUnits(px, scale): настоящие пиксели → условные (ширина экрана для узких раскладок, место курсора);
	- unitsSize(w, h): размер экрана в условных пикселях.
]]

local Config = require("./Config")

local UiFit = {}

-- touch: экран с касанием (§15ё): узкий сенсорный экран (планшет) растёт до условного TouchRefWidthPx ×
-- TouchRefHeightPx — иначе на планшете всё размером с телефон и много пустоты. Компьютер с сенсорным экраном
-- (широкий в условных пикселях) — как раньше.
function UiFit.scale(w: number, h: number, touch: boolean?): number
	local cfg = Config.Render.UiScale
	if w <= 0 or h <= 0 then
		return cfg.Min
	end
	local raw = math.min(h / cfg.RefHeightPx, w / cfg.RefWidthPx)
	if touch and w / math.max(cfg.Min, raw) < Config.Render.NarrowScreenPx then
		raw = math.max(raw, math.min(h / cfg.TouchRefHeightPx, w / cfg.TouchRefWidthPx))
	end
	local stepped = math.floor(raw * cfg.StepsPerUnit + 0.5) / cfg.StepsPerUnit
	return math.clamp(stepped, cfg.Min, cfg.Max)
end

function UiFit.toUnits(px: number, scale: number): number
	return px / math.max(scale, 0.01)
end

function UiFit.unitsSize(w: number, h: number, touch: boolean?): (number, number)
	local s = UiFit.scale(w, h, touch)
	return UiFit.toUnits(w, s), UiFit.toUnits(h, s)
end

return table.freeze(UiFit)
