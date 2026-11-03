--!strict
--[[
	TerritoryPaint — цвет клетки с учётом владельца (слои 3, 4 и 6 из GDD §3):
	3. цвет державы поверх местности: местность просвечивает (доля Config.Render.OwnerTint);
	4. граница державы — её цвет × Config.Nations.BorderShade, линия в 1 клетку по краю территории
	   (своя клетка, у которой сосед чужой, ничей или вода);
	6. вспышка свежезахваченной клетки: к белому на Config.Render.CaptureFlashStrength × flash.
	Слой 5 (границы провинций) — этап 3.
]]

local Config = require("./Config")
local NationColors = require("./NationColors")

local TerritoryPaint = {}

local function ownerAt(owners: buffer, i: number): number
	return buffer.readu16(owners, i * 2)
end

-- Граница территории: у клетки есть сосед (из 4) с другим владельцем или край карты.
function TerritoryPaint.isBorder(owners: buffer, width: number, height: number, i: number): boolean
	local o = ownerAt(owners, i)
	local x = i % width
	if x == 0 or x == width - 1 or i < width or i >= width * (height - 1) then
		return true
	end
	return ownerAt(owners, i - 1) ~= o
		or ownerAt(owners, i + 1) ~= o
		or ownerAt(owners, i - width) ~= o
		or ownerAt(owners, i + width) ~= o
end

-- Цвет клетки i. terrain — RGBA-буфер местности (MapPaint.paint), colorIndexOf — цвет державы по id
-- (0 — цвета нет), flash — сила вспышки захвата 0..1.
function TerritoryPaint.cellColor(
	terrain: buffer,
	owners: buffer,
	width: number,
	height: number,
	i: number,
	colorIndexOf: (owner: number) -> number,
	flash: number
): (number, number, number)
	local o = i * 4
	local r, g, b = buffer.readu8(terrain, o), buffer.readu8(terrain, o + 1), buffer.readu8(terrain, o + 2)
	local owner = ownerAt(owners, i)
	if owner == 0 then
		return r, g, b
	end
	local ci = colorIndexOf(owner)
	if ci < 1 or ci > NationColors.Count then
		return r, g, b
	end
	if TerritoryPaint.isBorder(owners, width, height, i) then
		local c = NationColors.Borders[ci]
		r, g, b = c.r, c.g, c.b
	else
		local c = NationColors.Colors[ci]
		local t = Config.Render.OwnerTint
		r = r + (c.r - r) * t
		g = g + (c.g - g) * t
		b = b + (c.b - b) * t
	end
	if flash > 0 then
		local f = math.clamp(flash, 0, 1) * Config.Render.CaptureFlashStrength
		r = r + (255 - r) * f
		g = g + (255 - g) * f
		b = b + (255 - b) * f
	end
	return math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)
end

return table.freeze(TerritoryPaint)
