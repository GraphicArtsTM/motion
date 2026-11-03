--!strict
--[[
	Точка входа клиента. Клиент только отправляет намерения и рисует (docs/GDD.md §0, п. 4).
	Карта, выбранная сервером, рендер через EditableImage, камера, блики, F3;
	этап 2: приём матча (MatchClient), слой территорий, подписи держав, HUD, нажатия на карту.
]]

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
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
local MatchClient = require(Client:WaitForChild("Net"):WaitForChild("MatchClient"))
local MatchHud = require(UI:WaitForChild("MatchHud"))
local NationLabels = require(UI:WaitForChild("NationLabels"))
local TerritoryLayer = require(Render:WaitForChild("TerritoryLayer"))
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
-- Окно чата — на середину левого края: слева сверху по GDD §10 панель державы, слева снизу — ползунок атаки.
pcall(function()
	local chatWindow = TextChatService.ChatWindowConfiguration
	chatWindow.HorizontalAlignment = Enum.HorizontalAlignment.Left
	chatWindow.VerticalAlignment = Enum.VerticalAlignment.Center
end)

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

-- Матч: состояние с сервера, слой территорий, подписи, HUD.
local cs = ClientState.new(map.width, map.height)
local territory = TerritoryLayer.new(view, map, colors, cs)
local labels = NationLabels.new(view.canvas, cs, lang, map.width)
camera.onChanged(function(state)
	labels.onCamera(state)
end)

local hud: MatchHud.Hud
local client = MatchClient.connect(cs, {
	onInfo = function(colorsChanged: boolean)
		if colorsChanged and cs.hasSnapshot then
			territory.repaintAll()
		end
		labels.refresh()
		hud.refresh()
	end,
	onSnapshot = function()
		territory.repaintAll()
	end,
	onDelta = function(cells: { number })
		territory.cellsChanged(cells, os.clock())
	end,
	onStats = function()
		hud.refresh()
	end,
	onEvents = function(events: { any })
		hud.onEvents(events)
	end,
	onRejected = function(reason: string)
		hud.toast(Strings.get("reject." .. reason, lang))
	end,
})
hud = MatchHud.new(gui, cs, lang, map, client.send)
hud.refresh()

local input = CameraInput.bind(camera, viewport, function(sx: number, sy: number)
	local cx, cy = CameraMath.cellAt(camera.state, sx, sy)
	if cx ~= nil and cy ~= nil then
		hud.tapCell(cy * map.width + cx)
	end
end)

local frameConn = RunService.RenderStepped:Connect(function()
	local now = os.clock()
	territory.update(now)
	hud.update(now)
end)

DebugOverlay.create(gui, {
	map = map,
	state = camera.state,
	chunkCount = view.chunkCount,
	memoryBytes = view.memoryBytes,
	hover = input.hover,
	extra = function(): { string }
		local lines: { string } = {}
		local stats = cs.stats
		if stats ~= nil then
			table.insert(lines, string.format(Strings.get("debug.server", lang), stats.tickMs, stats.changed))
		end
		table.insert(lines, string.format(Strings.get("debug.ping", lang), math.round(player:GetNetworkPing() * 1000)))
		return lines
	end,
}, lang)

player.AncestryChanged:Connect(function()
	if not player:IsDescendantOf(game) then
		stopSparkles()
		frameConn:Disconnect()
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
