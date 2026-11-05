--!strict
--[[
	PlaneSprites — программные спрайты самолётов 8×6 (пока нет арта, docs/ART_LIST.md). Общие для клиента
	(Render/AirLayer) и превью партии. Деталь: прямоугольник; ink — тёмная деталь, иначе цвет державы.
	Нос — справа; летит влево — спрайт зеркалится. Тень рисуется ниже самолёта (Render.PlaneShadow).
]]

export type Part = { x: number, y: number, w: number, h: number, ink: boolean }

local PlaneSprites = {}

PlaneSprites.Width = 8
PlaneSprites.Height = 6

PlaneSprites.Shapes = table.freeze({
	Fighter = { -- узкий фюзеляж, стреловидное крыло, хвост
		{ x = 1, y = 2, w = 7, h = 2, ink = false },
		{ x = 3, y = 0, w = 2, h = 6, ink = false },
		{ x = 0, y = 1, w = 1, h = 4, ink = false },
		{ x = 6, y = 2, w = 1, h = 1, ink = true },
	},
	Bomber = { -- толстый фюзеляж, широкое крыло, два двигателя
		{ x = 0, y = 2, w = 8, h = 2, ink = false },
		{ x = 3, y = 0, w = 2, h = 6, ink = false },
		{ x = 2, y = 1, w = 1, h = 1, ink = true },
		{ x = 2, y = 4, w = 1, h = 1, ink = true },
		{ x = 0, y = 1, w = 1, h = 4, ink = false },
	},
} :: { [string]: { Part } })

return table.freeze(PlaneSprites)
