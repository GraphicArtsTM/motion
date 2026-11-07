--!strict
--[[
	Theme — визуальные константы интерфейса. Цвета только из палитры (Shared.Palette, docs/palette.md).
	Шрифт — Config.Render.UiFont: RobotoMono (кириллица, моноширинные цифры) или пиксельный «Arcade» на пробу.
	§15л ч.4: кнопки и окна — пиксельный вид (Theme.decorate по правилам Shared.PixelSkin).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapPaint = require(Shared:WaitForChild("MapPaint"))
local Palette = require(Shared:WaitForChild("Palette"))
local PixelSkin = require(Shared:WaitForChild("PixelSkin"))

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

-- Оформление окон и кнопок — пиксельный вид (§15л ч.4, правила — Shared.PixelSkin): квадратные углы, рамка
-- в Unit пикселей без сглаживания (UIStroke, Miter), светлая фаска сверху и слева, тёмная снизу и справа, «полка»
-- под кнопкой. Наведение — золотая рамка; нажатие — фаска наоборот и без полки («вдавилась»). Фаска — соседи цвета
-- кнопки по палитре (PixelSkin.Shades), неизвестный цвет — полупрозрачные White / Ink. Если в рамке есть раскладка
-- (UIListLayout и т. п.), детали фаски не ставим (раскладка двигала бы их) — остаются рамка и квадратные углы.
-- Повторный вызов ничего не меняет.
Theme.CornerPx = 0 -- пиксельный вид: углы квадратные (круглые кнопки-значки остаются круглыми)
Theme.PanelAlpha = 0.08 -- §15з: прозрачность фона окон
local U = PixelSkin.Unit
local HOVER = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
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
local OUTLINE = color(PixelSkin.Outline)
local HOVER_EDGE = color(PixelSkin.Hover)
local LIP = color(PixelSkin.Lip)
local WHITE, INK = color("White"), color("Ink")

local function faceName(c: Color3): string?
	return PixelSkin.nameOf(math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

-- Квадратные углы: скругление убираем (круг — Scale ≥ 0.5 — не трогаем).
function Theme.square(corner: UICorner)
	if corner.CornerRadius.Scale < 0.5 then
		corner.CornerRadius = UDim.new(0, 0)
	end
end

local function padding(g: GuiObject): (number, number, number, number)
	local p = g:FindFirstChildOfClass("UIPadding")
	if p == nil then
		return 0, 0, 0, 0
	end
	return p.PaddingLeft.Offset, p.PaddingRight.Offset, p.PaddingTop.Offset, p.PaddingBottom.Offset
end

local function part(g: GuiObject, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = g.ZIndex
	f.Parent = g
	return f
end

-- Детали фаски (кнопка — с боками и полкой, окно — только светлая линия сверху).
local function bevel(g: GuiObject, isButton: boolean): (pressed: boolean) -> ()
	if g:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil then
		return function(_pressed: boolean) end
	end
	local pl, pr, pt, pb = padding(g)
	local hiTop = part(g, "PxHi")
	hiTop.Position = UDim2.fromOffset(-pl, -pt)
	hiTop.Size = UDim2.new(1, pl + pr, 0, U)
	if not isButton then
		local function paintPanel()
			local name = faceName(g.BackgroundColor3)
			local shade = if name ~= nil then PixelSkin.shadeOf(name) else nil
			hiTop.BackgroundColor3 = if shade ~= nil then color(shade.hi) else WHITE
			hiTop.BackgroundTransparency = math.max(g.BackgroundTransparency, if shade ~= nil then 0 else 0.85)
		end
		paintPanel()
		g:GetPropertyChangedSignal("BackgroundColor3"):Connect(paintPanel)
		return function(_pressed: boolean) end
	end
	local hiLeft = part(g, "PxHiL")
	hiLeft.Position = UDim2.fromOffset(-pl, -pt)
	hiLeft.Size = UDim2.new(0, U, 1, pt + pb)
	local loBottom = part(g, "PxLo")
	loBottom.AnchorPoint = Vector2.new(0, 1)
	loBottom.Position = UDim2.new(0, -pl, 1, pb)
	loBottom.Size = UDim2.new(1, pl + pr, 0, U)
	local loRight = part(g, "PxLoR")
	loRight.AnchorPoint = Vector2.new(1, 0)
	loRight.Position = UDim2.new(1, pr, 0, -pt)
	loRight.Size = UDim2.new(0, U, 1, pt + pb)
	local lip = part(g, "PxLip")
	lip.Position = UDim2.new(0, -pl, 1, pb + U) -- под рамкой
	lip.Size = UDim2.new(1, pl + pr, 0, U)
	lip.BackgroundColor3 = LIP
	local down = false
	local function paint()
		local name = faceName(g.BackgroundColor3)
		local shade = if name ~= nil then PixelSkin.shadeOf(name) else nil
		local hi, lo = WHITE, INK
		local hiAlpha, loAlpha = 0.7, 0.45
		if shade ~= nil then
			hi, lo = color(shade.hi), color(shade.lo)
			hiAlpha, loAlpha = 0, 0
		end
		if down then
			hi, lo = lo, hi
			hiAlpha, loAlpha = loAlpha, hiAlpha
		end
		local base = g.BackgroundTransparency
		for _, f in { hiTop, hiLeft } do
			f.BackgroundColor3 = hi
			f.BackgroundTransparency = math.max(base, hiAlpha)
		end
		for _, f in { loBottom, loRight } do
			f.BackgroundColor3 = lo
			f.BackgroundTransparency = math.max(base, loAlpha)
		end
		lip.BackgroundTransparency = if down then 1 else math.max(base, 0.2)
	end
	paint()
	g:GetPropertyChangedSignal("BackgroundColor3"):Connect(paint)
	g:GetPropertyChangedSignal("BackgroundTransparency"):Connect(paint)
	return function(pressed: boolean)
		down = pressed
		paint()
	end
end

function Theme.decorate(g: GuiObject)
	if g:GetAttribute("FrontirStyled") then
		return
	end
	g:SetAttribute("FrontirStyled", true)
	local isButton = g:IsA("GuiButton")
	-- §15з: окна чуть прозрачные — карта просвечивает, как в играх жанра.
	if not isButton and g.BackgroundTransparency < Theme.PanelAlpha then
		g.BackgroundTransparency = Theme.PanelAlpha
	end
	local corner = g:FindFirstChildOfClass("UICorner")
	if corner ~= nil then
		Theme.square(corner)
	end
	local stroke = g:FindFirstChildOfClass("UIStroke")
	if stroke == nil then
		stroke = Instance.new("UIStroke")
		local st = stroke :: UIStroke
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Color = if isButton then OUTLINE else color(PixelSkin.PanelOutline)
		st.Parent = g
	end
	local st = stroke :: UIStroke
	st.LineJoinMode = Enum.LineJoinMode.Miter
	st.Thickness = math.max(st.Thickness, U)
	if isButton and st.Color == Theme.Colors.PanelBorder then
		st.Color = OUTLINE
	end
	-- Детали фаски — когда рамка собрана (раскладку и отступы добавляют после создания).
	local press: (boolean) -> () = function(_pressed: boolean) end
	task.defer(function()
		if g.Parent ~= nil then
			press = bevel(g, isButton)
		end
	end)
	if isButton then
		local b = g :: GuiButton
		local base = st.Color
		local over = false
		b.MouseEnter:Connect(function()
			over = true
			base = if st.Color ~= HOVER_EDGE then st.Color else base
			TweenService:Create(st, HOVER, { Color = HOVER_EDGE }):Play()
		end)
		b.MouseLeave:Connect(function()
			over = false
			press(false)
			TweenService:Create(st, HOVER, { Color = base }):Play()
		end)
		b.MouseButton1Down:Connect(function()
			press(true)
		end)
		b.MouseButton1Up:Connect(function()
			press(false)
			if not over then
				st.Color = base
			end
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
