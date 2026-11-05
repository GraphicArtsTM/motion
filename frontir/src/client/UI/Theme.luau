--!strict
--[[
	Theme — визуальные константы интерфейса. Цвета только из палитры (Shared.Palette, docs/palette.md).
	Шрифт — Config.Render.UiFont: RobotoMono (кириллица, моноширинные цифры) или пиксельный «Arcade» на пробу.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapPaint = require(Shared:WaitForChild("MapPaint"))
local Palette = require(Shared:WaitForChild("Palette"))

local function color(name: string): Color3
	local c = Palette.rgb(name)
	return Color3.fromRGB(c.r, c.g, c.b)
end

local Theme = {}

Theme.color = color
-- Шрифт — Config.Render.UiFont (сводная правка: пиксельный «Arcade» на пробу); неизвестное имя — RobotoMono.
local fontEnum = Enum.Font.RobotoMono
local okFont, chosen = pcall(function(): any
	return (Enum.Font :: any)[Config.Render.UiFont]
end)
if okFont and chosen ~= nil then
	fontEnum = chosen
end
Theme.Font = Font.fromEnum(fontEnum)
-- У пиксельного шрифта нет жирного начертания — тогда «жирный» тот же.
Theme.FontBold = if fontEnum == Enum.Font.RobotoMono
	then Font.new(Theme.Font.Family, Enum.FontWeight.Bold)
	else Theme.Font
Theme.BorderPx = 1

Theme.Colors = table.freeze({
	Backdrop = color("Ink"),
	-- Фон вокруг карты — цвет открытого моря из MapPaint, край карты не виден.
	Ocean = color(MapPaint.OceanColorName),
	PanelBg = color("Night"),
	PanelBorder = color("Steel"),
	Text = color("White"),
	Muted = color("Mist"),
	Gold = color("Gold"),
	Sky = color("Sky"),
	Alert = color("Red"),
})

return table.freeze(Theme)
