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

local player = Players.LocalPlayer
local lang = Strings.langFromLocale(LocalizationService.RobloxLocaleId)

-- Цвета-заглушки до появления docs/palette.md (этап 1).
local PANEL_BG = Color3.fromRGB(20, 22, 34)
local PANEL_BORDER = Color3.fromRGB(90, 96, 130)
local GOLD = Color3.fromRGB(240, 196, 64)
local SKY = Color3.fromRGB(120, 200, 255)

local gui = Instance.new("ScreenGui")
gui.Name = "FrontirBoot"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(360, 120)
panel.BackgroundColor3 = PANEL_BG
panel.BorderSizePixel = 0
panel.Parent = backdrop

local stroke = Instance.new("UIStroke")
stroke.Color = PANEL_BORDER
stroke.Thickness = 1
stroke.Parent = panel

local function addLabel(name: string, text: string, color: Color3, y: number, size: number)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(0, y)
	label.Size = UDim2.new(1, 0, 0, size + 8)
	label.Font = Enum.Font.Arcade
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.Parent = panel
end

addLabel("Title", Strings.get("game.title", lang), GOLD, 14, 32)
addLabel("Stage", Strings.get("boot.stage", lang), SKY, 60, 16)
addLabel(
	"Hint",
	string.format("%s · %d Hz", Strings.get("boot.hint", lang), Config.Sim.TickRate),
	PANEL_BORDER,
	86,
	14
)

gui.Parent = player:WaitForChild("PlayerGui")
print("[Frontir] client boot, lang =", lang)
