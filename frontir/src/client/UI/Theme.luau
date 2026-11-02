--!strict
--[[
	Theme — визуальные константы интерфейса. Цвета только из палитры (Shared.Palette, docs/palette.md).
	Шрифт временно стандартный RobotoMono (кириллица, моноширинные цифры); пиксельный — на этапе HUD.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))

local function color(name: string): Color3
	local c = Palette.rgb(name)
	return Color3.fromRGB(c.r, c.g, c.b)
end

local Theme = {}

Theme.color = color
Theme.Font = Font.fromEnum(Enum.Font.RobotoMono)
Theme.FontBold = Font.new(Theme.Font.Family, Enum.FontWeight.Bold)
Theme.BorderPx = 1

Theme.Colors = table.freeze({
	Backdrop = color("Ink"),
	PanelBg = color("Night"),
	PanelBorder = color("Steel"),
	Text = color("White"),
	Muted = color("Mist"),
	Gold = color("Gold"),
	Sky = color("Sky"),
	Alert = color("Red"),
})

return table.freeze(Theme)
