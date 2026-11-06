--!strict
--[[
	BuildingSprites — программные значки зданий и нефтяного поля 12×12 (§15д ч.4: были 7×7 «точки»; пока нет арта,
	docs/ART_LIST.md). Общие для клиента (Render/BuildingLayer, BuildGhost, UI/BuildPanel) и превью партии.
	Деталь: прямоугольник; ink — тёмная деталь; tone "window" — золото (окна, флаг), "glass" — голубое стекло;
	иначе цвет владельца с оттенком shade (меньше 1 — темнее, больше 1 — светлее), как у юнитов.
]]

local Palette = require("./Palette")
local UnitSprites = require("./UnitSprites")

export type Part = { x: number, y: number, w: number, h: number, ink: boolean, shade: number?, tone: string? }

local BuildingSprites = {}

BuildingSprites.Size = 12

local function p(x: number, y: number, w: number, h: number, shade: number?, tone: string?): Part
	return { x = x, y = y, w = w, h = h, ink = tone == "ink", shade = shade, tone = tone }
end
local INK, GOLD, SKY = "ink", "window", "glass"

BuildingSprites.Shapes = table.freeze({
	Factory = { -- цех с пилообразной крышей, труба, окна
		p(0, 5, 9, 7),
		p(0, 3, 3, 2, 0.55),
		p(3, 3, 3, 2, 0.55),
		p(6, 3, 3, 2, 0.55),
		p(9, 1, 2, 11, 1.4),
		p(9, 0, 2, 1, nil, INK),
		p(1, 7, 2, 2, nil, GOLD),
		p(6, 7, 2, 2, nil, GOLD),
		p(4, 9, 2, 3, nil, INK),
	},
	Barracks = { -- казарма под крышей, флагшток с золотым флагом
		p(1, 5, 10, 7),
		p(0, 4, 12, 2, 0.55),
		p(5, 0, 1, 4, nil, INK),
		p(6, 0, 3, 2, nil, GOLD),
		p(5, 8, 2, 4, nil, INK),
		p(2, 7, 2, 2, nil, INK),
		p(8, 7, 2, 2, nil, INK),
	},
	Housing = { -- два дома с крышами и светом в окнах
		p(0, 5, 5, 7, 1.3),
		p(0, 3, 5, 2, 0.5),
		p(6, 3, 6, 9, 1.1),
		p(6, 1, 6, 2, 0.5),
		p(1, 7, 1, 1, nil, GOLD),
		p(3, 7, 1, 1, nil, GOLD),
		p(8, 5, 1, 1, nil, GOLD),
		p(10, 5, 1, 1, nil, GOLD),
		p(8, 10, 2, 2, nil, INK),
	},
	Market = { -- полосатый навес, прилавок, товары
		p(0, 2, 12, 3),
		p(2, 2, 2, 3, 1.5),
		p(6, 2, 2, 3, 1.5),
		p(10, 2, 2, 3, 1.5),
		p(1, 5, 10, 1, 0.55),
		p(1, 6, 10, 6, 1.2),
		p(3, 7, 2, 2, nil, GOLD),
		p(7, 7, 2, 2, nil, SKY),
	},
	OilRig = { -- вышка на опорах, насос и бак
		p(4, 1, 4, 2),
		p(5, 0, 2, 1, nil, INK),
		p(3, 3, 1, 9, nil, INK),
		p(8, 3, 1, 9, nil, INK),
		p(4, 5, 4, 1, nil, INK),
		p(4, 8, 4, 1, nil, INK),
		p(9, 7, 3, 3, 1.3),
		p(0, 10, 12, 2, 0.6),
	},
	Fort = { -- каменная стена с зубцами и воротами
		p(0, 4, 12, 8),
		p(0, 2, 2, 2),
		p(4, 2, 2, 2),
		p(8, 2, 2, 2),
		p(10, 2, 2, 2, 0.8),
		p(0, 7, 12, 1, 0.6),
		p(5, 8, 2, 4, nil, INK),
	},
	Port = { -- кран над складом, причал
		p(1, 0, 1, 10, nil, INK),
		p(1, 0, 8, 1, nil, INK),
		p(8, 1, 1, 3, nil, INK),
		p(4, 5, 7, 5),
		p(4, 4, 7, 1, 0.5),
		p(6, 7, 2, 3, nil, INK),
		p(0, 10, 12, 2, 0.55),
	},
	Radar = { -- тарелка на мачте
		p(1, 1, 10, 3, 1.4),
		p(3, 4, 6, 1, 1.1),
		p(5, 2, 2, 1, nil, INK),
		p(5, 5, 2, 5, nil, INK),
		p(2, 10, 8, 2),
	},
	Airfield = { -- полоса с разметкой, ангар, вышка со стеклом
		p(0, 7, 12, 3, nil, INK),
		p(2, 8, 2, 1, nil, GOLD),
		p(6, 8, 2, 1, nil, GOLD),
		p(0, 3, 6, 4, 0.8),
		p(0, 2, 6, 1, 0.5),
		p(9, 1, 3, 6),
		p(9, 1, 3, 2, nil, SKY),
		p(0, 10, 12, 2, 0.6),
	},
	AirDefense = { -- установка с двумя стволами и прицелом
		p(1, 8, 10, 4),
		p(3, 5, 6, 3, 1.3),
		p(4, 0, 1, 5, nil, INK),
		p(7, 0, 1, 5, nil, INK),
		p(10, 6, 1, 2, nil, SKY),
	},
	MissileSilo = { -- ракета в шахте
		p(0, 9, 12, 3, nil, INK),
		p(1, 8, 10, 1, 0.6),
		p(5, 1, 2, 8, 1.5),
		p(5, 0, 2, 1, nil, GOLD),
		p(4, 6, 1, 2),
		p(7, 6, 1, 2),
	},
	OilField = { -- капля нефти (поле без вышки)
		p(5, 1, 2, 1, nil, INK),
		p(4, 2, 4, 2, nil, INK),
		p(3, 4, 6, 4, nil, INK),
		p(4, 8, 4, 2, nil, INK),
		p(4, 4, 1, 2, nil, SKY),
	},
} :: { [string]: { Part } })

local INK_RGB, GOLD_RGB, SKY_RGB = Palette.rgb("Ink"), Palette.rgb("Gold"), Palette.rgb("Sky")

-- Цвет детали (0..255) для цвета владельца r, g, b.
function BuildingSprites.rgb(part: Part, r: number, g: number, b: number): (number, number, number)
	if part.tone == INK or part.ink then
		return INK_RGB.r, INK_RGB.g, INK_RGB.b
	elseif part.tone == GOLD then
		return GOLD_RGB.r, GOLD_RGB.g, GOLD_RGB.b
	elseif part.tone == SKY then
		return SKY_RGB.r, SKY_RGB.g, SKY_RGB.b
	end
	return UnitSprites.shade(r, g, b, part.shade)
end

return table.freeze(BuildingSprites)
