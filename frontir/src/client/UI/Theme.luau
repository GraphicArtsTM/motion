--!strict
--[[
	Theme — визуальные константы интерфейса. Цвета только из палитры (Shared.Palette, docs/palette.md).
	§15ф Ф1: «ясный» вид — шрифт Montserrat (Config.Render.UiFont), скругления, тонкие рамки; пиксельный — только логотип.
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
-- Шрифт: §15ф — семейство Config.Render.UiFontFamily (Montserrat — читаемый, с кириллицей, начертания от Medium
-- до ExtraBold); пусто — Enum по Config.Render.UiFont (RobotoMono или пиксельный).
local family = Config.Render.UiFontFamily
if family ~= "" then
	Theme.Font = Font.new(family, Enum.FontWeight.Medium)
	Theme.FontBold = Font.new(family, Enum.FontWeight.Bold)
	Theme.FontHeavy = Font.new(family, Enum.FontWeight.ExtraBold)
else
	local fontEnum = Enum.Font.RobotoMono
	local okFont, chosen = pcall(function(): any
		return (Enum.Font :: any)[Config.Render.UiFont]
	end)
	if okFont and chosen ~= nil then
		fontEnum = chosen
	end
	Theme.Font = Font.fromEnum(fontEnum)
	-- У пиксельного шрифта нет жирного начертания — тогда «жирный» тот же.
	local weights = fontEnum == Enum.Font.RobotoMono
	Theme.FontBold = if weights then Font.new(Theme.Font.Family, Enum.FontWeight.Bold) else Theme.Font
	Theme.FontHeavy = Theme.FontBold
end
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

-- §15ф Ф1: «ясный» вид — скруглённые углы (CornerPx), тонкая рамка, без пиксельной фаски. Наведение на кнопку —
-- золотая рамка, нажатие — кнопка чуть уменьшается. Окна — тёмные, слегка прозрачные (карта
-- просвечивает). Повторный вызов ничего не меняет.
Theme.CornerPx = 8 -- скругление кнопок и окон (круги — Scale ≥ 0.5 — остаются кругами)
Theme.PanelAlpha = 0.06 -- §15з: прозрачность фона окон
local HOVER = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SPRING = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PANEL_EDGE = color("Slate")
local BUTTON_EDGE = color("Ink")
local HOVER_EDGE = color("Gold")

local function scaleOf(g: GuiObject): UIScale
	local found = g:FindFirstChildOfClass("UIScale")
	if found ~= nil then
		return found
	end
	local s = Instance.new("UIScale")
	s.Parent = g
	return s
end

-- Скругление не меньше CornerPx (круг — Scale ≥ 0.5 — не трогаем). Старое имя square оставлено для вызовов.
function Theme.round(corner: UICorner)
	if corner.CornerRadius.Scale < 0.5 and corner.CornerRadius.Offset < Theme.CornerPx then
		corner.CornerRadius = UDim.new(0, Theme.CornerPx)
	end
end
Theme.square = Theme.round

function Theme.decorate(g: GuiObject)
	if g:GetAttribute("FrontirStyled") then
		return
	end
	g:SetAttribute("FrontirStyled", true)
	local isButton = g:IsA("GuiButton")
	if not isButton and g.BackgroundTransparency < Theme.PanelAlpha then
		g.BackgroundTransparency = Theme.PanelAlpha
	end
	local corner = g:FindFirstChildOfClass("UICorner")
	if corner == nil then
		local made = Instance.new("UICorner")
		made.CornerRadius = UDim.new(0, Theme.CornerPx)
		made.Parent = g
	else
		Theme.round(corner)
	end
	local stroke = g:FindFirstChildOfClass("UIStroke")
	if stroke == nil then
		local made = Instance.new("UIStroke")
		made.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		made.Color = if isButton then BUTTON_EDGE else PANEL_EDGE
		made.Transparency = if isButton then 0.4 else 0.35
		made.Thickness = 1
		made.Parent = g
		stroke = made
	end
	local st = stroke :: UIStroke
	st.LineJoinMode = Enum.LineJoinMode.Round
	if isButton then
		local b = g :: GuiButton
		local baseColor, baseAlpha = st.Color, st.Transparency
		local scale = scaleOf(b)
		-- Фон кнопки не трогаем (окна сами красят «нельзя» / «выбрано»), меняется только рамка.
		b.MouseEnter:Connect(function()
			TweenService:Create(st, HOVER, { Color = HOVER_EDGE, Transparency = 0 }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(st, HOVER, { Color = baseColor, Transparency = baseAlpha }):Play()
			scale.Scale = 1
		end)
		b.MouseButton1Down:Connect(function()
			scale.Scale = 0.97
		end)
		b.MouseButton1Up:Connect(function()
			scale.Scale = 1
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
