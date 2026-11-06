--!strict
--[[
	PixelIcons — значки интерфейса 8×8 (§15д ч.5: полоса ресурсов «как в игре»): монета, бочка нефти, люди,
	войска, земля, лампочка подсказки. Программный пиксель-арт (пока нет арта, docs/ART_LIST.md); цвета — имена
	палитры (docs/palette.md).
]]

export type Part = { x: number, y: number, w: number, h: number, color: string }

local PixelIcons = {}

PixelIcons.Size = 8

local function p(x: number, y: number, w: number, h: number, color: string): Part
	return { x = x, y = y, w = w, h = h, color = color }
end

PixelIcons.Icons = table.freeze({
	money = { -- монета
		p(2, 0, 4, 1, "Gold"),
		p(1, 1, 6, 6, "Gold"),
		p(2, 7, 4, 1, "Orange"),
		p(0, 2, 1, 4, "Gold"),
		p(7, 2, 1, 4, "Orange"),
		p(3, 2, 2, 4, "Orange"),
		p(2, 1, 1, 1, "White"),
	},
	oil = { -- бочка
		p(1, 0, 6, 8, "Ink"),
		p(2, 0, 4, 8, "Slate"),
		p(1, 2, 6, 1, "Gold"),
		p(1, 5, 6, 1, "Gold"),
		p(3, 1, 1, 1, "Mist"),
	},
	people = { -- два человека
		p(1, 0, 2, 2, "Sky"),
		p(0, 2, 4, 4, "Sky"),
		p(5, 1, 2, 2, "White"),
		p(4, 3, 4, 4, "White"),
		p(1, 6, 1, 2, "Sky"),
		p(5, 7, 1, 1, "White"),
	},
	army = { -- скрещённые мечи
		p(0, 0, 1, 1, "White"),
		p(1, 1, 1, 1, "White"),
		p(2, 2, 1, 1, "White"),
		p(5, 2, 1, 1, "White"),
		p(6, 1, 1, 1, "White"),
		p(7, 0, 1, 1, "White"),
		p(3, 3, 2, 2, "Mist"),
		p(2, 5, 1, 1, "Gold"),
		p(5, 5, 1, 1, "Gold"),
		p(1, 6, 1, 2, "Orange"),
		p(6, 6, 1, 2, "Orange"),
	},
	land = { -- флаг на земле
		p(1, 0, 1, 8, "Mist"),
		p(2, 0, 5, 4, "Red"),
		p(2, 1, 5, 1, "Orange"),
		p(0, 7, 8, 1, "Grass"),
	},
	hint = { -- лампочка
		p(2, 0, 4, 1, "Gold"),
		p(1, 1, 6, 4, "Gold"),
		p(3, 2, 1, 2, "White"),
		p(2, 5, 4, 1, "Orange"),
		p(3, 6, 2, 1, "Mist"),
		p(3, 7, 2, 1, "Slate"),
	},
} :: { [string]: { Part } })

return table.freeze(PixelIcons)
