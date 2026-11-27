--!strict
--[[
	TouchBuild — стройка пальцем (§15ъ), без Roblox API. Первое касание ставит «призрак» на клетку, второе строит,
	если пришлось рядом с призраком: не дальше Render.TouchConfirmPx экрана (палец не попадает в ту же клетку —
	на карте она в несколько пикселей). zoom — пикселей экрана на клетку (CameraMath).
]]

local Config = require("./Config")

local TouchBuild = {}

-- Второе касание (клетка cell) подтверждает призрак на клетке pending?
function TouchBuild.confirms(pending: number?, cell: number, width: number, zoom: number): boolean
	if pending == nil or width <= 0 then
		return false
	end
	if pending == cell then
		return true
	end
	local dx = (cell % width) - (pending % width)
	local dy = (cell // width) - (pending // width)
	local px = math.sqrt(dx * dx + dy * dy) * math.max(zoom, 0)
	return px <= Config.Render.TouchConfirmPx
end

return table.freeze(TouchBuild)
