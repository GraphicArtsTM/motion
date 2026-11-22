--!strict
--[[
	FreeArea — свободная часть экрана (GDD §15й Й6), без Roblox API: панели у краёв (слева, справа, сверху, снизу —
	по положению центра) сужают прямоугольник; панели на весь экран не считаются; если свободной части почти не
	осталось (меньше Render.FreeArea.MinShare по стороне) — по этой оси весь экран.
]]

local Config = require("./Config")

export type Box = { x0: number, y0: number, x1: number, y1: number }

local FreeArea = {}

function FreeArea.rect(w: number, h: number, boxes: { Box }): (number, number, number, number)
	local cfg = Config.Render.FreeArea
	local left, right, top, bottom = 0, w, 0, h
	for _, b in boxes do
		local bw, bh = b.x1 - b.x0, b.y1 - b.y0
		if bw <= 0 or bh <= 0 or (bw >= w * cfg.FullShare and bh >= h * cfg.FullShare) then
			continue
		end
		local cx, cy = (b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2
		if cx < w * cfg.EdgeShare and b.x1 < w / 2 then
			left = math.max(left, b.x1)
		elseif cx > w * (1 - cfg.EdgeShare) and b.x0 > w / 2 then
			right = math.min(right, b.x0)
		elseif cy < h * cfg.EdgeShare then
			top = math.max(top, b.y1)
		elseif cy > h * (1 - cfg.EdgeShare) then
			bottom = math.min(bottom, b.y0)
		end
	end
	if right - left < w * cfg.MinShare then
		left, right = 0, w
	end
	if bottom - top < h * cfg.MinShare then
		top, bottom = 0, h
	end
	return left, top, right, bottom
end

-- Центр свободной части.
function FreeArea.center(w: number, h: number, boxes: { Box }): (number, number)
	local x0, y0, x1, y1 = FreeArea.rect(w, h, boxes)
	return (x0 + x1) / 2, (y0 + y1) / 2
end

return table.freeze(FreeArea)
