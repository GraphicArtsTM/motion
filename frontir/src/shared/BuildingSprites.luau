--!strict
--[[
	BuildingSprites — программные значки зданий и нефтяного поля 7×7 (пока нет арта, docs/ART_LIST.md).
	Общие для клиента (Render/BuildingLayer) и превью партии. Деталь: прямоугольник; ink — тёмная деталь,
	иначе цвет владельца (у нефтяного поля без вышки — тёмная капля).
]]

export type Part = { x: number, y: number, w: number, h: number, ink: boolean }

local BuildingSprites = {}

BuildingSprites.Size = 7

BuildingSprites.Shapes = table.freeze({
	Factory = { -- цех и труба
		{ x = 0, y = 3, w = 7, h = 4, ink = false },
		{ x = 5, y = 0, w = 2, h = 3, ink = false },
		{ x = 1, y = 4, w = 1, h = 1, ink = true },
		{ x = 3, y = 4, w = 1, h = 1, ink = true },
	},
	Fort = { -- стена с зубцами и воротами
		{ x = 0, y = 2, w = 7, h = 5, ink = false },
		{ x = 0, y = 0, w = 2, h = 2, ink = false },
		{ x = 5, y = 0, w = 2, h = 2, ink = false },
		{ x = 3, y = 4, w = 1, h = 3, ink = true },
	},
	Market = { -- полосатый навес и прилавок
		{ x = 0, y = 1, w = 7, h = 2, ink = false },
		{ x = 1, y = 3, w = 5, h = 4, ink = false },
		{ x = 1, y = 1, w = 1, h = 2, ink = true },
		{ x = 3, y = 1, w = 1, h = 2, ink = true },
		{ x = 5, y = 1, w = 1, h = 2, ink = true },
	},
	OilRig = { -- вышка: две опоры и площадка
		{ x = 1, y = 2, w = 1, h = 5, ink = false },
		{ x = 5, y = 2, w = 1, h = 5, ink = false },
		{ x = 2, y = 0, w = 3, h = 2, ink = false },
		{ x = 2, y = 4, w = 3, h = 1, ink = true },
	},
	OilField = { -- капля нефти (поле без вышки)
		{ x = 3, y = 0, w = 1, h = 1, ink = true },
		{ x = 2, y = 1, w = 3, h = 2, ink = true },
		{ x = 1, y = 3, w = 5, h = 3, ink = true },
		{ x = 2, y = 6, w = 3, h = 1, ink = true },
	},
} :: { [string]: { Part } })

return table.freeze(BuildingSprites)
