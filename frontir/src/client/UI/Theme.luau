--!strict
--[[
	Theme — визуальные константы интерфейса. Цвета только из палитры (Shared.Palette, docs/palette.md).
	Шрифт — Config.Render.UiFont: RobotoMono (кириллица, моноширинные цифры) или пиксельный «Arcade» на пробу.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
	Good = color("Meadow"), -- «можно» (призрак стройки, §15г)
	Slate = color("Slate"),
})

-- Оформление окон и кнопок (§15г): скругление, мягкий градиент сверху вниз, рамка; кнопки откликаются —
-- наведение: золотая рамка и ×1.04, нажатие: ×0.95 и пружинка обратно. Повторный вызов ничего не меняет.
Theme.CornerPx = 6
Theme.PanelAlpha = 0.08 -- §15з: прозрачность фона окон
local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SPRING = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function scaleOf(g: GuiObject): UIScale
	local found = g:FindFirstChildOfClass("UIScale")
	if found ~= nil then
		return found
	end
	local s = Instance.new("UIScale")
	s.Parent = g
	return s
end

function Theme.decorate(g: GuiObject)
	if g:GetAttribute("FrontirStyled") then
		return
	end
	g:SetAttribute("FrontirStyled", true)
	-- §15з: окна чуть прозрачные — карта просвечивает, как в играх жанра.
	if not g:IsA("GuiButton") and g.BackgroundTransparency < Theme.PanelAlpha then
		g.BackgroundTransparency = Theme.PanelAlpha
	end
	if g:FindFirstChildOfClass("UICorner") == nil then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Theme.CornerPx)
		corner.Parent = g
	end
	if g:FindFirstChildOfClass("UIGradient") == nil then
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 202, 222))
		grad.Parent = g
	end
	local stroke = g:FindFirstChildOfClass("UIStroke")
	if stroke == nil then
		stroke = Instance.new("UIStroke")
		local st = stroke :: UIStroke
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Color = Theme.Colors.PanelBorder
		st.Thickness = Theme.BorderPx
		st.Parent = g
	end
	if g:IsA("GuiButton") then
		local st = stroke :: UIStroke
		local base = st.Color
		local scale = scaleOf(g)
		local over = false
		g.MouseEnter:Connect(function()
			over = true
			TweenService:Create(scale, HOVER, { Scale = 1.04 }):Play()
			TweenService:Create(st, HOVER, { Color = Theme.Colors.Gold }):Play()
		end)
		g.MouseLeave:Connect(function()
			over = false
			TweenService:Create(scale, HOVER, { Scale = 1 }):Play()
			TweenService:Create(st, HOVER, { Color = base }):Play()
		end)
		g.MouseButton1Down:Connect(function()
			TweenService:Create(scale, HOVER, { Scale = 0.95 }):Play()
		end)
		g.MouseButton1Up:Connect(function()
			TweenService:Create(scale, SPRING, { Scale = if over then 1.04 else 1 }):Play()
		end)
	end
end

-- Окно появляется: из ×0.9 с пружинкой.
function Theme.popIn(g: GuiObject)
	local scale = scaleOf(g)
	scale.Scale = 0.9
	TweenService:Create(scale, SPRING, { Scale = 1 }):Play()
end

return table.freeze(Theme)
