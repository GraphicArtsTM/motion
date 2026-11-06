--!strict
--[[
	ShipSprites — программные спрайты кораблей 8×5 (пока нет арта, docs/ART_LIST.md). Общие для клиента
	(Render/ShipLayer) и превью партии. Деталь: прямоугольник; ink — тёмная деталь, иначе цвет державы.
	Нос корабля — справа; при движении влево спрайт зеркалится.
]]

-- light — светлая деталь (парус торгового судна, §15е).
export type Part = { x: number, y: number, w: number, h: number, ink: boolean, light: boolean? }

local ShipSprites = {}

ShipSprites.Width = 8
ShipSprites.Height = 5

ShipSprites.Shapes = table.freeze({
	Transport = { -- широкий корпус и надстройка
		{ x = 0, y = 2, w = 8, h = 2, ink = false },
		{ x = 1, y = 4, w = 6, h = 1, ink = true },
		{ x = 1, y = 0, w = 3, h = 2, ink = false },
		{ x = 2, y = 1, w = 1, h = 1, ink = true },
	},
	Destroyer = { -- узкий корпус, башня и ствол вперёд
		{ x = 0, y = 3, w = 8, h = 1, ink = false },
		{ x = 1, y = 4, w = 6, h = 1, ink = true },
		{ x = 3, y = 1, w = 2, h = 2, ink = false },
		{ x = 5, y = 1, w = 3, h = 1, ink = true },
	},
	Merchant = { -- торговое судно (§15е): корпус, мачта и светлые паруса
		{ x = 0, y = 3, w = 8, h = 1, ink = false },
		{ x = 1, y = 4, w = 6, h = 1, ink = true },
		{ x = 4, y = 0, w = 1, h = 3, ink = true },
		{ x = 2, y = 0, w = 2, h = 3, ink = false, light = true },
		{ x = 5, y = 1, w = 2, h = 2, ink = false, light = true },
	},
} :: { [string]: { Part } })

return table.freeze(ShipSprites)
