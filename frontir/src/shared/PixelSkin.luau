--!strict
--[[
	PixelSkin — пиксельный вид кнопок и окон (GDD §15л ч.4), общий для клиента (UI/Theme.decorate) и превью
	(tools/ui_preview): квадратные углы, тёмная рамка в Unit пикселей, светлая фаска сверху, тёмная снизу, «полка»
	(тень) под кнопкой; наведение — золотая рамка, нажатие — фаска наоборот, полки нет («вдавилась»).
	Цвета фаски — соседи цвета кнопки по палитре (shadeOf), никаких смешанных цветов.
]]

local Palette = require("./Palette")

export type Shade = { hi: string, lo: string }
export type Rect = { x: number, y: number, w: number, h: number, color: string }

local PixelSkin = {}

PixelSkin.Unit = 2 -- пикселей экрана на пиксель рамки и фаски
PixelSkin.Outline = "Ink" -- рамка кнопки
PixelSkin.PanelOutline = "Steel" -- рамка окна (на тёмной карте тёмная рамка не видна)
PixelSkin.Hover = "Gold"
PixelSkin.Lip = "Ink" -- полка под кнопкой

-- Цвет кнопки → светлая и тёмная фаска (имена палитры). Нет в списке — фаска полупрозрачными White / Ink.
PixelSkin.Shades = table.freeze({
	Gold = { hi = "White", lo = "Orange" },
	Orange = { hi = "Gold", lo = "Basalt" },
	Slate = { hi = "Steel", lo = "Night" },
	Night = { hi = "Slate", lo = "Ink" },
	Steel = { hi = "Mist", lo = "Slate" },
	Ink = { hi = "Night", lo = "Ink" },
	Plum = { hi = "Rose", lo = "Night" },
	Red = { hi = "Rose", lo = "Plum" },
	Forest = { hi = "Meadow", lo = "Pine" },
	Grass = { hi = "Meadow", lo = "Forest" },
	Meadow = { hi = "Lime", lo = "Forest" },
	Teal = { hi = "Sky", lo = "Pine" },
	Sky = { hi = "White", lo = "River" },
	River = { hi = "Sky", lo = "Shallows" },
	Shallows = { hi = "River", lo = "Sea" },
	Sea = { hi = "Shallows", lo = "Abyss" },
	Violet = { hi = "Rose", lo = "Night" },
	Mist = { hi = "White", lo = "Steel" },
} :: { [string]: Shade })

-- Имя палитры по цвету 0..255 (точное совпадение) или nil.
function PixelSkin.nameOf(r: number, g: number, b: number): string?
	for _, sw in Palette.Swatches do
		local c = Palette.rgb(sw.name)
		if c.r == r and c.g == g and c.b == b then
			return sw.name
		end
	end
	return nil
end

function PixelSkin.shadeOf(face: string): Shade?
	return PixelSkin.Shades[face]
end

-- Детали кнопки w×h (в пикселях экрана) поверх фона face: рамка снаружи, фаска внутри, полка снизу.
-- Координаты — от левого верхнего угла самой кнопки (рамка и полка выходят за неё). Для превью.
function PixelSkin.button(w: number, h: number, face: string, state: "normal" | "hover" | "pressed"): { Rect }
	local u = PixelSkin.Unit
	local shade = PixelSkin.Shades[face] or { hi = "White", lo = "Ink" }
	local edge = if state == "hover" then PixelSkin.Hover else PixelSkin.Outline
	local hi, lo = shade.hi, shade.lo
	if state == "pressed" then
		hi, lo = lo, hi
	end
	local out: { Rect } = {
		{ x = 0, y = 0, w = w, h = h, color = face },
		{ x = 0, y = 0, w = w, h = u, color = hi },
		{ x = 0, y = 0, w = u, h = h, color = hi },
		{ x = 0, y = h - u, w = w, h = u, color = lo },
		{ x = w - u, y = 0, w = u, h = h, color = lo },
		-- Рамка: четыре полосы без углов — уголки «срезаны», как у пиксельной кнопки.
		{ x = 0, y = -u, w = w, h = u, color = edge },
		{ x = 0, y = h, w = w, h = u, color = edge },
		{ x = -u, y = 0, w = u, h = h, color = edge },
		{ x = w, y = 0, w = u, h = h, color = edge },
	}
	if state ~= "pressed" then
		table.insert(out, { x = 0, y = h + u, w = w, h = u, color = PixelSkin.Lip })
	end
	return out
end

-- Окно w×h: фон face, рамка PanelOutline снаружи, внутренняя светлая линия сверху.
function PixelSkin.panel(w: number, h: number, face: string): { Rect }
	local u = PixelSkin.Unit
	local shade = PixelSkin.Shades[face] or { hi = "Slate", lo = "Ink" }
	return {
		{ x = 0, y = 0, w = w, h = h, color = face },
		{ x = 0, y = 0, w = w, h = u, color = shade.hi },
		{ x = 0, y = -u, w = w, h = u, color = PixelSkin.PanelOutline },
		{ x = 0, y = h, w = w, h = u, color = PixelSkin.PanelOutline },
		{ x = -u, y = 0, w = u, h = h, color = PixelSkin.PanelOutline },
		{ x = w, y = 0, w = u, h = h, color = PixelSkin.PanelOutline },
		{ x = 0, y = h + u, w = w, h = u, color = "Ink" },
	}
end

return table.freeze(PixelSkin)
