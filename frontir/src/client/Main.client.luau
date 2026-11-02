--!strict
--[[
	Точка входа клиента. Клиент только отправляет намерения и рисует (docs/GDD.md §0, п. 4).
	Этап 0: заглушка-экран, чтобы было видно, что Rojo синхронизировал проект.
]]

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local lang: Strings.Lang = Strings.langFromLocale(LocalizationService.RobloxLocaleId)

local gui = Instance.new("ScreenGui")
gui.Name = "FrontirBoot"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Theme.Colors.Backdrop
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(360, 120)
panel.BackgroundColor3 = Theme.Colors.PanelBg
panel.BorderSizePixel = 0
panel.Parent = backdrop

local stroke = Instance.new("UIStroke")
stroke.Color = Theme.Colors.PanelBorder
stroke.Thickness = Theme.BorderPx
stroke.Parent = panel

local function addLabel(name: string, text: string, color: Color3, y: number, size: number, font: Font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(0, y)
	label.Size = UDim2.new(1, 0, 0, size + 8)
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.Parent = panel
end

addLabel("Title", Strings.get("game.title", lang), Theme.Colors.Gold, 14, 32, Theme.FontBold)
addLabel("Stage", Strings.get("boot.stage", lang), Theme.Colors.Sky, 60, 16, Theme.Font)
addLabel(
	"Hint",
	string.format("%s · %d Hz", Strings.get("boot.hint", lang), Config.Sim.TickRate),
	Theme.Colors.Muted,
	86,
	14,
	Theme.Font
)

gui.Parent = player:WaitForChild("PlayerGui")
print("[Frontir] client boot, lang =", lang)
