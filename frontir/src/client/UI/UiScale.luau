--!strict
--[[
	UiScale — масштаб интерфейса под экран (GDD §15ц Ц1). Правило — чистый Shared.UiFit; здесь обвязка:
	- attach(gui): ставит в слой (HUD, меню, окна) UIScale и держит его по размеру экрана;
	- factor(): множитель сейчас; size(gui): размер слоя в условных пикселях (для «узкий экран?» и «влезает ли»);
	- units(px): настоящие пиксели → условные (место курсора, AbsolutePosition → Position.Offset);
	- onResize(gui, fn): fn при смене размера экрана (и слоя, и масштаба — в любом порядке).
	Всё, что кладёт в слой точку из настоящих пикселей (курсор, AbsolutePosition другого окна), делит её на factor().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiFit = require(Shared:WaitForChild("UiFit"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

local UiScale = {}

local NAME = "ScreenScale"

local function viewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera ~= nil then camera.ViewportSize else Vector2.new(0, 0)
end

function UiScale.factor(): number
	local v = viewportSize()
	return UiFit.scale(v.X, v.Y)
end

function UiScale.units(px: number): number
	return UiFit.toUnits(px, UiScale.factor())
end

function UiScale.size(gui: GuiBase2d): Vector2
	return gui.AbsoluteSize / UiScale.factor()
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
