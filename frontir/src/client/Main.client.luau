--!strict
--[[
	Точка входа клиента. Клиент только отправляет намерения и рисует (docs/GDD.md §0, п. 4).
	Этап 1: загрузка карты, выбранной сервером, рендер через EditableImage, камера, блики, F3.
]]

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local Config = require(Shared:WaitForChild("Config"))
local MapFormat = require(Shared:WaitForChild("MapFormat"))
local MapPaint = require(Shared:WaitForChild("MapPaint"))
local Strings = require(Shared:WaitForChild("Strings"))

local Client = script.Parent
local Render = Client:WaitForChild("Render")
local UI = Client:WaitForChild("UI")
local Camera2D = require(Render:WaitForChild("Camera2D"))
local CameraInput = require(Client:WaitForChild("Input"):WaitForChild("CameraInput"))
local DebugOverlay = require(UI:WaitForChild("DebugOverlay"))
local MapRenderer = require(Render:WaitForChild("MapRenderer"))
local Theme = require(UI:WaitForChild("Theme"))
local WaterSparkles = require(Render:WaitForChild("WaterSparkles"))

local player = Players.LocalPlayer
local lang: Strings.Lang = Strings.langFromLocale(LocalizationService.RobloxLocaleId)

-- 3D-камера и управление персонажем не нужны: игра целиком в GUI. Фиксируем камеру, чтобы правая
-- кнопка мыши и пальцы её не вращали, и выключаем стандартные контролы (джойстик на телефоне, WASD).
local worldCamera = workspace.CurrentCamera
if worldCamera then
	worldCamera.CameraType = Enum.CameraType.Scriptable
end
task.spawn(function()
	local ok, err = pcall(function()
		local playerModule =
			require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
		playerModule:GetControls():Disable()
	end)
	if not ok then
		warn("[Frontir] не удалось выключить стандартное управление:", err)
	end
end)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
-- Справа сверху по GDD §10 будет своя таблица лидеров; стандартный список игроков её перекрывал бы.
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

-- Карту выбирает сервер (атрибут MapId у ReplicatedStorage), данные лежат в ReplicatedStorage.Maps.
local mapId = ReplicatedStorage:GetAttribute("MapId")
while type(mapId) ~= "string" do
	ReplicatedStorage:GetAttributeChangedSignal("MapId"):Wait()
	mapId = ReplicatedStorage:GetAttribute("MapId")
end
local mapModule = require(ReplicatedStorage:WaitForChild("Maps"):WaitForChild(mapId) :: ModuleScript) :: any
local map = MapFormat.fromModule(mapModule :: MapFormat.MapModule)

local depth = MapPaint.waterDepth(map)
local colors = MapPaint.paint(map, depth)

local gui = Instance.new("ScreenGui")
gui.Name = "FrontirMap"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local viewport = Instance.new("Frame")
viewport.Name = "MapViewport"
viewport.Size = UDim2.fromScale(1, 1)
viewport.BackgroundColor3 = Theme.Colors.Ocean
viewport.BorderSizePixel = 0
viewport.ClipsDescendants = true
viewport.Active = false
viewport.Parent = gui

gui.Parent = player:WaitForChild("PlayerGui")

local view, createError, details = MapRenderer.create(viewport, map, colors)
if view == nil then
	local message = Instance.new("TextLabel")
	message.Name = "MapError"
	message.AnchorPoint = Vector2.new(0.5, 0.5)
	message.Position = UDim2.fromScale(0.5, 0.5)
	message.Size = UDim2.new(0.8, 0, 0, 120)
	message.BackgroundColor3 = Theme.Colors.PanelBg
	message.BorderSizePixel = 0
	message.TextWrapped = true
	message.FontFace = Theme.Font
	message.TextSize = 18
	message.TextColor3 = Theme.Colors.Alert
	message.Text =
		Strings.get(if createError == "Budget" then "error.editable.budget" else "error.editable.disabled", lang)
	message.Parent = viewport
	warn("[Frontir] карта не отрисована:", createError, details)
	return
end

local camera = Camera2D.new(map.width, map.height, viewport)
local stopSparkles, sparklesOnCamera =
	WaterSparkles.start(view.canvas, map, MapPaint.sparkleMask(map, depth, Config.Render.SparkleMinDepth), camera.state)
camera.onChanged(function(state)
	local ox, oy = CameraMath.canvasOffset(state)
	view.setView(state.zoom, ox, oy)
	sparklesOnCamera(state)
end)

local input = CameraInput.bind(camera, viewport)
DebugOverlay.create(gui, {
	map = map,
	state = camera.state,
	chunkCount = view.chunkCount,
	memoryBytes = view.memoryBytes,
	hover = input.hover,
}, lang)

player.AncestryChanged:Connect(function()
	if not player:IsDescendantOf(game) then
		stopSparkles()
		input.disconnect()
		camera.destroy()
		view.destroy()
	end
end)

print(
	string.format(
		"[Frontir] client: карта %s %d×%d, чанков %d",
		map.name,
		map.width,
		map.height,
		view.chunkCount
	)
)
