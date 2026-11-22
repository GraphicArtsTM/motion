--!strict
--[[
	UiScale — масштаб интерфейса под экран (GDD §15ц Ц1). Правило — чистый Shared.UiFit; здесь обвязка:
	- attach(gui): ставит в слой (HUD, меню, окна) UIScale и держит его по размеру экрана;
	- factor(): множитель сейчас; size(gui): размер слоя в условных пикселях (для «узкий экран?» и «влезает ли»);
	- units(px): настоящие пиксели → условные (место курсора, AbsolutePosition → Position.Offset);
	- onResize(gui, fn): fn при смене размера экрана (и слоя, и масштаба — в любом порядке);
	- isPhone(gui): §15ё телефонный экран (PhoneLayout.phone по размеру слоя);
	- touchText(gui, text): §15ё на телефоне — текст без клавиш (TouchText.strip);
	- fitSheet(gui, frame, scale, width, margin, minScale): §15ё нижнее окно — в ширину, на телефоне и в высоту.
	Всё, что кладёт в слой точку из настоящих пикселей (курсор, AbsolutePosition другого окна), делит её на factor().
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiFit = require(Shared:WaitForChild("UiFit"))
local PhoneLayout = require(Shared:WaitForChild("PhoneLayout"))
local TouchText = require(Shared:WaitForChild("TouchText"))
local Config = require(Shared:WaitForChild("Config"))
local Layering = require(script.Parent:WaitForChild("Layering"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

local UiScale = {}

local NAME = "ScreenScale"

local function viewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera ~= nil then camera.ViewportSize else Vector2.new(0, 0)
end

-- §15ё: в Studio с Dev.PhoneScreenW/H — экран телефона на мониторе (не меньше W×H точек, тесная сторона — ровно).
local devPhone = RunService:IsStudio() and Config.Dev.PhoneScreenW > 0 and Config.Dev.PhoneScreenH > 0

function UiScale.factor(): number
	local v = viewportSize()
	if devPhone then
		-- монитор = телефон W×H (точки), увеличенный в k раз по более тесной стороне; дальше — правило игры
		local k = math.max(math.min(v.X / Config.Dev.PhoneScreenW, v.Y / Config.Dev.PhoneScreenH), 0.01)
		return UiFit.scale(v.X / k, v.Y / k, true) * k
	end
	return UiFit.scale(v.X, v.Y, UserInputService.TouchEnabled) -- §15ё: планшет — крупнее
end

function UiScale.units(px: number): number
	return UiFit.toUnits(px, UiScale.factor())
end

function UiScale.size(gui: GuiBase2d): Vector2
	return gui.AbsoluteSize / UiScale.factor()
end

-- §15ё полоса Roblox сверху (кнопки Roblox слева, справа свободно — GuiService.TopbarInset): левый край свободной
-- части и высота полосы, в условных пикселях. Нет полосы — 0, 0.
function UiScale.topbar(): (number, number)
	local r = GuiService.TopbarInset
	local f = UiScale.factor()
	return r.Min.X / f, r.Height / f
end

-- fn при смене полосы Roblox сверху (поворот экрана, другое устройство).
function UiScale.onTopbar(fn: () -> ())
	Session.connect(GuiService:GetPropertyChangedSignal("TopbarInset"), fn)
end

-- §15ё телефонный экран (узкий или низкий; в Studio — Dev.PhoneLayout): раскладки HUD и окон для пальца.
function UiScale.isPhone(gui: GuiBase2d): boolean
	local s = UiScale.size(gui)
	if s.X <= 0 or s.Y <= 0 then
		return RunService:IsStudio() and Config.Dev.PhoneLayout
	end
	return PhoneLayout.phone(s.X, s.Y, RunService:IsStudio() and Config.Dev.PhoneLayout)
end

-- §15ё нижнее окно (стройка, здание, порт, аэродром, война): по ширине экрана (поле margin с каждой стороны, не
-- мельче minScale); на телефоне — ещё и по высоте (поля Phone.Hud.WindowEdge, не мельче SheetMinScale): окно с
-- AutomaticSize — высота «как есть» берётся из AbsoluteSize / Scale. Пересчёт — при смене экрана, размера и показе.
function UiScale.fitSheet(
	gui: GuiBase2d,
	frame: GuiObject,
	scale: UIScale,
	width: number,
	margin: number,
	minScale: number
)
	local function fit()
		local s = UiScale.size(gui)
		if s.X <= 0 or s.Y <= 0 then
			return
		end
		local k = math.clamp((s.X - 2 * margin) / width, minScale, 1)
		if UiScale.isPhone(gui) then
			local hud = Config.Render.Phone.Hud
			local natural = UiScale.units(frame.AbsoluteSize.Y) / math.max(0.01, scale.Scale)
			if natural > 0 then
				k = math.clamp(math.min(k, (s.Y - 2 * hud.WindowEdge) / natural), hud.SheetMinScale, 1)
			end
		end
		if math.abs(scale.Scale - k) > 0.005 then
			scale.Scale = k
		end
	end
	UiScale.onResize(gui, fit)
	Session.connect(frame:GetPropertyChangedSignal("AbsoluteSize"), function()
		task.defer(fit)
	end)
	Session.connect(frame:GetPropertyChangedSignal("Visible"), fit)
	fit()
end

-- §15ё Ё3: большое окно постоянной раскладки («Путь командира», Итоги) на телефоне — масштаб по ширине экрана (не
-- мельче Phone.Hud.ScrollMinScale), а что не влезло по высоте — прокручивается: окно переезжает в прокрутку на весь
-- слой (ScrollingFrame «<имя>Scroll»), сверху у края. Возвращает fit(width) → true, если это телефон (масштаб
-- поставлен; иначе окно вернулось на место и масштаб — забота вызвавшего).
function UiScale.scrollHost(gui: GuiBase2d, frame: GuiObject, scale: UIScale): (width: number) -> boolean
	local host = Instance.new("ScrollingFrame")
	host.Name = frame.Name .. "Scroll"
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.Size = UDim2.fromScale(1, 1)
	host.CanvasSize = UDim2.new()
	host.ScrollingDirection = Enum.ScrollingDirection.Y
	host.ScrollBarThickness = 6
	host.ScrollBarImageColor3 = Theme.Colors.PanelBorder
	host.Visible = false
	-- В HUD (ZIndex Global) хозяин — ZIndex 1, чтобы Layering.liftAll его не трогал; содержимое окна поднимаем сами
	-- (один раз — атрибут ZLifted), иначе в прокрутке оно ушло бы под фон окна.
	host.ZIndex = 1
	Layering.lift(frame)
	local homeAnchor, homePos = frame.AnchorPoint, frame.Position
	local hosted = false
	local edge = Config.Render.Phone.Hud.WindowEdge
	local function canvas()
		if hosted then
			host.Visible = frame.Visible
			host.CanvasSize = UDim2.fromOffset(0, UiScale.units(frame.AbsoluteSize.Y) + 2 * edge)
		end
	end
	local lastWidth = 0
	local function rescale()
		local s = UiScale.size(gui)
		-- Ширина окна — заявленная (у окна в прокрутке — постоянная, а не AutomaticSize).
		local natural = math.max(1, lastWidth)
		local k = math.clamp((s.X - 2 * edge) / natural, Config.Render.Phone.Hud.ScrollMinScale, 1)
		if math.abs(scale.Scale - k) > 0.005 then
			scale.Scale = k
		end
		canvas()
	end
	Session.connect(frame:GetPropertyChangedSignal("Visible"), canvas)
	Session.connect(frame:GetPropertyChangedSignal("AbsoluteSize"), function()
		if hosted then
			task.defer(rescale)
		end
	end)
	return function(width: number): boolean
		local phone = UiScale.isPhone(gui)
		if phone and not hosted then
			hosted = true
			homeAnchor, homePos = frame.AnchorPoint, frame.Position
			host.Parent = frame.Parent
			frame.Parent = host
			frame.AnchorPoint = Vector2.new(0.5, 0)
			frame.Position = UDim2.new(0.5, 0, 0, edge)
		elseif not phone and hosted then
			hosted = false
			frame.Parent = host.Parent
			host.Parent = nil
			frame.AnchorPoint, frame.Position = homeAnchor, homePos
		end
		if phone then
			lastWidth = width
			rescale()
		end
		return phone
	end
end

-- §15ё подсказка для пальца: на телефоне (или касание без клавиатуры) — без упоминаний клавиш (TouchText).
function UiScale.touchText(gui: GuiBase2d, text: string): string
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	return if touchOnly or UiScale.isPhone(gui) then TouchText.strip(text) else text
end

-- Камера может смениться (CurrentCamera) — слушаем и её, и размер её окна.
local function onViewport(fn: () -> ())
	local sizeConn: RBXScriptConnection? = nil
	local function hook()
		if sizeConn ~= nil then
			sizeConn:Disconnect()
			sizeConn = nil
		end
		local camera = Workspace.CurrentCamera
		if camera ~= nil then
			sizeConn = Session.connect(camera:GetPropertyChangedSignal("ViewportSize"), fn)
		end
		fn()
	end
	Session.connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), hook)
	hook()
end

function UiScale.onResize(gui: GuiBase2d, fn: () -> ())
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fn)
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		Session.connect(camera:GetPropertyChangedSignal("ViewportSize"), fn)
	end
end

function UiScale.attach(gui: ScreenGui)
	local found = gui:FindFirstChild(NAME)
	local scale: UIScale
	if found ~= nil and found:IsA("UIScale") then
		scale = found
	else
		scale = Instance.new("UIScale")
		scale.Name = NAME
		scale.Parent = gui
	end
	onViewport(function()
		local s = UiScale.factor()
		if scale.Scale ~= s then
			scale.Scale = s
		end
	end)
end

return table.freeze(UiScale)
