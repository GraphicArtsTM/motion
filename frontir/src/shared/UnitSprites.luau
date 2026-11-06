--!strict
--[[
	UnitSprites — программные спрайты юнитов на линии фронта (пока нет арта, docs/ART_LIST.md) и их размер
	на разных зумах. Общие для клиента (Render/FrontLayer) и превью партии (tools/match_preview), поэтому
	чистые данные без Roblox API. Где юниты стоят — Shared.BattleLayout.
]]

local Config = require("./Config")

-- Деталь спрайта 12×10: прямоугольник; ink — тёмная деталь, иначе цвет державы с оттенком shade
-- (меньше 1 — темнее, больше 1 — светлее; §15г: объём и читаемость силуэта).
export type Part = { x: number, y: number, w: number, h: number, ink: boolean, shade: number? }

local UnitSprites = {}

UnitSprites.Width = 12
UnitSprites.Height = 10

UnitSprites.Shapes = table.freeze({
	Infantry = { -- солдат в каске с винтовкой наперевес
		{ x = 4, y = 3, w = 4, h = 4, ink = false }, -- тело
		{ x = 4, y = 0, w = 4, h = 2, ink = false, shade = 0.7 }, -- каска
		{ x = 5, y = 2, w = 2, h = 1, ink = false, shade = 1.5 }, -- лицо
		{ x = 4, y = 5, w = 4, h = 1, ink = true }, -- ремень
		{ x = 4, y = 7, w = 1, h = 2, ink = false, shade = 0.7 }, -- ноги
		{ x = 7, y = 7, w = 1, h = 2, ink = false, shade = 0.7 },
		{ x = 3, y = 9, w = 2, h = 1, ink = true }, -- сапоги
		{ x = 7, y = 9, w = 2, h = 1, ink = true },
		{ x = 6, y = 3, w = 6, h = 1, ink = true }, -- винтовка
		{ x = 7, y = 4, w = 2, h = 1, ink = false, shade = 1.25 }, -- рука
	},
	Tanks = { -- гусеницы с катками, корпус, башня со стволом
		{ x = 0, y = 7, w = 12, h = 3, ink = true }, -- гусеница
		{ x = 2, y = 8, w = 1, h = 1, ink = false, shade = 0.6 }, -- катки
		{ x = 5, y = 8, w = 1, h = 1, ink = false, shade = 0.6 },
		{ x = 8, y = 8, w = 1, h = 1, ink = false, shade = 0.6 },
		{ x = 1, y = 4, w = 10, h = 3, ink = false }, -- корпус
		{ x = 1, y = 6, w = 10, h = 1, ink = false, shade = 0.7 },
		{ x = 3, y = 1, w = 5, h = 3, ink = false, shade = 1.2 }, -- башня
		{ x = 4, y = 0, w = 2, h = 1, ink = false, shade = 0.75 }, -- люк
		{ x = 8, y = 2, w = 4, h = 1, ink = true }, -- ствол
	},
	Artillery = { -- пушка на лафете: длинный ствол вверх-вперёд, щит, большое колесо
		{ x = 6, y = 1, w = 6, h = 1, ink = true }, -- ствол
		{ x = 4, y = 2, w = 3, h = 1, ink = true },
		{ x = 3, y = 3, w = 3, h = 3, ink = false, shade = 1.15 }, -- щит
		{ x = 1, y = 6, w = 8, h = 1, ink = false, shade = 0.7 }, -- лафет
		{ x = 0, y = 7, w = 3, h = 1, ink = true }, -- станина
		{ x = 3, y = 6, w = 3, h = 4, ink = true }, -- колесо
		{ x = 4, y = 7, w = 1, h = 2, ink = false, shade = 1.3 }, -- ступица
	},
	AntiAir = { -- зенитка на грузовике: два ствола вверх, прицел
		{ x = 0, y = 6, w = 12, h = 2, ink = false }, -- кузов
		{ x = 9, y = 4, w = 3, h = 2, ink = false, shade = 1.2 }, -- кабина
		{ x = 4, y = 4, w = 4, h = 2, ink = false, shade = 0.75 }, -- станок
		{ x = 5, y = 0, w = 1, h = 4, ink = true }, -- стволы
		{ x = 7, y = 0, w = 1, h = 4, ink = true },
		{ x = 1, y = 3, w = 2, h = 3, ink = false, shade = 1.3 }, -- прицел
		{ x = 1, y = 8, w = 2, h = 2, ink = true }, -- колёса
		{ x = 5, y = 8, w = 2, h = 2, ink = true },
		{ x = 9, y = 8, w = 2, h = 2, ink = true },
	},
} :: { [string]: { Part } })

-- Цвет детали с оттенком (0..255): shade < 1 — к чёрному, > 1 — к белому.
function UnitSprites.shade(r: number, g: number, b: number, shade: number?): (number, number, number)
	local k = shade or 1
	if k < 1 then
		return math.round(r * k), math.round(g * k), math.round(b * k)
	elseif k > 1 then
		local t = math.min(1, k - 1)
		return math.round(r + (255 - r) * t), math.round(g + (255 - g) * t), math.round(b + (255 - b) * t)
	end
	return r, g, b
end

-- Во сколько раз увеличить спрайт на зуме zoom (Config.Render.UnitSpriteScales): на мелком зуме
-- пиксель спрайта = пиксель экрана (12×10 — уже заметно), ближе — крупнее, чтобы силуэты читались.
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
