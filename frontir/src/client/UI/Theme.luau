--!strict
--[[
	Theme — визуальные константы интерфейса (цвета, шрифты, размеры).
	Не баланс, поэтому живёт на клиенте, а не в Config.

	Шрифт: временно стандартный RobotoMono (есть кириллица и латиница, моноширинные цифры).
	Пиксельный шрифт выберем на этапе HUD — см. docs/ART_LIST.md.
	Цвета — заглушки до docs/palette.md (этап 1).
]]

local Theme = {}

Theme.Font = Font.fromEnum(Enum.Font.RobotoMono)
Theme.FontBold = Font.new(Theme.Font.Family, Enum.FontWeight.Bold)

Theme.Colors = table.freeze({
	Backdrop = Color3.fromRGB(8, 10, 18),
	PanelBg = Color3.fromRGB(20, 22, 34),
	PanelBorder = Color3.fromRGB(90, 96, 130),
	Gold = Color3.fromRGB(240, 196, 64),
	Sky = Color3.fromRGB(120, 200, 255),
	Muted = Color3.fromRGB(90, 96, 130),
})

Theme.BorderPx = 1

return table.freeze(Theme)
