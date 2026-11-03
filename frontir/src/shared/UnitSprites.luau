--!strict
--[[
	UnitSprites — программные спрайты юнитов на линии фронта (пока нет арта, docs/ART_LIST.md) и их размер
	на разных зумах. Общие для клиента (Render/FrontLayer) и превью партии (tools/match_preview), поэтому
	чистые данные без Roblox API. Где юниты стоят — Shared.BattleLayout.
]]

local Config = require("./Config")

-- Деталь спрайта 8×6: прямоугольник; ink — тёмная деталь, иначе цвет державы.
export type Part = { x: number, y: number, w: number, h: number, ink: boolean }

local UnitSprites = {}

UnitSprites.Width = 8
UnitSprites.Height = 6

UnitSprites.Shapes = table.freeze({
	Infantry = { -- солдат: голова, тело, винтовка, ноги
		{ x = 3, y = 0, w = 2, h = 2, ink = false },
		{ x = 2, y = 2, w = 4, h = 3, ink = false },
		{ x = 6, y = 1, w = 1, h = 4, ink = true },
		{ x = 2, y = 5, w = 1, h = 1, ink = true },
		{ x = 5, y = 5, w = 1, h = 1, ink = true },
	},
	Tanks = { -- корпус, башня, ствол, гусеница
		{ x = 0, y = 3, w = 8, h = 2, ink = false },
		{ x = 2, y = 1, w = 4, h = 2, ink = false },
		{ x = 6, y = 1, w = 2, h = 1, ink = true },
		{ x = 0, y = 5, w = 8, h = 1, ink = true },
	},
	Artillery = { -- лафет, длинный ствол, колёса
		{ x = 1, y = 3, w = 5, h = 2, ink = false },
		{ x = 4, y = 1, w = 4, h = 1, ink = true },
		{ x = 1, y = 5, w = 2, h = 1, ink = true },
		{ x = 4, y = 5, w = 2, h = 1, ink = true },
	},
	AntiAir = { -- платформа и два ствола вверх
		{ x = 1, y = 3, w = 6, h = 3, ink = false },
		{ x = 2, y = 0, w = 1, h = 3, ink = true },
		{ x = 5, y = 0, w = 1, h = 3, ink = true },
	},
} :: { [string]: { Part } })

-- Во сколько раз увеличить спрайт на зуме zoom (Config.Render.UnitSpriteScales): на мелком зуме
-- пиксель спрайта = пиксель экрана, ближе — крупнее, чтобы силуэты читались.
function UnitSprites.scaleFor(zoom: number): number
	local scale = 1
	for _, step in Config.Render.UnitSpriteScales do
		if zoom >= step.zoom then
			scale = step.scale
		end
	end
	return scale
end

return table.freeze(UnitSprites)
