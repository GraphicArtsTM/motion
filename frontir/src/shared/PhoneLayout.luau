--!strict
--[[
	PhoneLayout — §15ц Ц5в: раскладка узкого экрана (телефон, планшет). Чистые правила, клиент только применяет.
	- narrow(width, force): условная ширина слоя меньше Render.NarrowScreenPx (или Dev.PhoneLayout в Studio);
	- bar(...): нижняя полоса — в одну строку (ужимается до MinScale) или, на узком экране / если не влезает, в две:
	  ширина — по нижней строке, масштаб — до ширины экрана, не мельче MinScale.
]]

local Config = require("./Config")

export type Bar = {
	rows: number, -- 1 или 2
	width: number, -- ширина полосы до масштаба (условные px)
	scale: number,
}

local PhoneLayout = {}

function PhoneLayout.narrow(width: number, force: boolean?): boolean
	return force == true or width < Config.Render.NarrowScreenPx
end

-- natural — ширина в одну строку, second — ширина нижней строки (войска, стройка, арсенал, магазин),
-- avail — сколько места по ширине, narrow — узкий экран.
function PhoneLayout.bar(natural: number, second: number, avail: number, narrow: boolean): Bar
	local minScale = Config.Render.CommandBar.MinScale
	if not narrow then
		local s = math.min(1, avail / natural)
		if s >= minScale then
			return { rows = 1, width = natural, scale = s }
		end
	end
	local width = math.min(natural, second)
	return { rows = 2, width = width, scale = math.clamp(avail / width, minScale, 1) }
end

return table.freeze(PhoneLayout)
