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
	-- §15з: значки дока.
	build = { -- молоток
		p(1, 0, 5, 3, "Steel"),
		p(1, 0, 5, 1, "Mist"),
		p(3, 3, 2, 5, "Ochre"),
		p(3, 3, 1, 5, "Sand"),
	},
	tech = { -- колба
		p(3, 0, 2, 3, "Mist"),
		p(2, 0, 4, 1, "White"),
		p(1, 3, 6, 4, "Teal"),
		p(2, 4, 2, 1, "Lime"),
		p(1, 7, 6, 1, "Steel"),
	},
	diplomacy = { -- рукопожатие
		p(0, 3, 3, 3, "Sky"),
		p(5, 3, 3, 3, "Orange"),
		p(2, 2, 4, 3, "Sand"),
		p(3, 3, 2, 1, "Ochre"),
	},
	stability = { -- весы
		p(3, 0, 2, 7, "Gold"),
		p(0, 2, 8, 1, "Gold"),
		p(0, 3, 3, 2, "Ochre"),
		p(5, 3, 3, 2, "Ochre"),
		p(2, 7, 4, 1, "Steel"),
	},
	ping = { -- метка на карте
		p(2, 0, 4, 4, "Red"),
		p(3, 1, 2, 2, "White"),
		p(3, 4, 2, 2, "Red"),
		p(1, 7, 6, 1, "Steel"),
	},
	shop = { -- сумка с монетой
		p(2, 0, 4, 2, "Ochre"),
		p(0, 2, 8, 6, "Plum"),
		p(3, 4, 2, 2, "Gold"),
	},
	quests = { -- свиток с галочкой
		p(1, 0, 6, 8, "Sand"),
		p(1, 0, 6, 1, "Ochre"),
		p(2, 4, 1, 1, "Grass"),
		p(3, 5, 1, 1, "Grass"),
		p(4, 3, 1, 2, "Grass"),
		p(5, 2, 1, 1, "Grass"),
	},
	wardrobe = { -- флаг державы
		p(1, 0, 1, 8, "Steel"),
		p(2, 0, 6, 2, "Violet"),
		p(2, 2, 6, 2, "Gold"),
		p(2, 4, 6, 1, "Violet"),
	},
	server = { -- шестерёнка
		p(2, 0, 4, 8, "Mist"),
		p(0, 2, 8, 4, "Mist"),
		p(1, 1, 6, 6, "Steel"),
		p(3, 3, 2, 2, "Ink"),
	},
	threat = { -- §15х ч.4б: прицел — «Карта угроз»
		p(2, 0, 4, 1, "Red"),
		p(2, 7, 4, 1, "Red"),
		p(0, 2, 1, 4, "Red"),
		p(7, 2, 1, 4, "Red"),
		p(1, 1, 1, 1, "Red"),
		p(6, 1, 1, 1, "Red"),
		p(1, 6, 1, 1, "Red"),
		p(6, 6, 1, 1, "Red"),
		p(3, 3, 2, 2, "Gold"),
	},
	help = { -- вопрос
		p(2, 0, 4, 1, "Gold"),
		p(1, 1, 2, 2, "Gold"),
		p(5, 1, 2, 3, "Gold"),
		p(3, 4, 3, 1, "Gold"),
		p(3, 5, 2, 1, "Gold"),
		p(3, 7, 2, 1, "Gold"),
	},
	sound = { -- нота
		p(5, 0, 1, 6, "White"),
		p(5, 0, 3, 1, "White"),
		p(2, 5, 4, 3, "White"),
	},
	-- §15л ч.6 Арсенал.
	arsenal = { -- ящик с оружием
		p(0, 2, 8, 6, "Ochre"),
		p(0, 2, 8, 1, "Hills"),
		p(3, 3, 2, 2, "Gold"),
		p(1, 0, 6, 2, "Rock"),
		p(0, 7, 8, 1, "Basalt"),
	},
	reinforce = { -- каска
		p(1, 2, 6, 3, "Grass"),
		p(2, 1, 4, 1, "Meadow"),
		p(0, 5, 8, 1, "Forest"),
		p(2, 6, 4, 2, "Sand"),
	},
	convoy = { -- грузовик
		p(0, 1, 5, 4, "Sand"),
		p(5, 2, 3, 3, "Ochre"),
		p(6, 2, 1, 1, "Sky"),
		p(1, 5, 2, 2, "Ink"),
		p(5, 5, 2, 2, "Ink"),
	},
	hqReserve = { -- песочные часы
		p(1, 0, 6, 1, "Gold"),
		p(2, 1, 4, 2, "Sand"),
		p(3, 3, 2, 2, "Sand"),
		p(2, 5, 4, 2, "Dune"),
		p(1, 7, 6, 1, "Gold"),
	},
	barrage = { -- три снаряда
		p(0, 2, 2, 5, "Steel"),
		p(3, 1, 2, 6, "Steel"),
		p(6, 2, 2, 5, "Steel"),
		p(0, 1, 2, 1, "Orange"),
		p(3, 0, 2, 1, "Orange"),
		p(6, 1, 2, 1, "Orange"),
		p(0, 7, 8, 1, "Red"),
	},
	jammer = { -- антенна с волнами
		p(3, 3, 2, 5, "Mist"),
		p(2, 2, 4, 1, "White"),
		p(0, 0, 1, 3, "Sky"),
		p(7, 0, 1, 3, "Sky"),
		p(1, 1, 1, 1, "Sky"),
		p(6, 1, 1, 1, "Sky"),
		p(1, 7, 6, 1, "Steel"),
	},
} :: { [string]: { Part } })

return table.freeze(PixelIcons)
