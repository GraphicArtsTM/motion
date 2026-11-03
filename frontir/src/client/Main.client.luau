--!strict
--[[
	Точка входа клиента. Клиент только отправляет намерения и рисует (docs/GDD.md §0, п. 4).
	Карта, выбранная сервером, рендер через EditableImage, камера, блики, F3;
	этап 2: приём матча (MatchClient), слой территорий, подписи держав, HUD, нажатия на карту;
	этап 3а: города, армии (слой, выделение, приказы, найм).
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
local ArmyLayer = require(Render:WaitForChild("ArmyLayer"))
local ArmyPanel = require(UI:WaitForChild("ArmyPanel"))
local MatchHud = require(UI:WaitForChild("MatchHud"))
local NationLabels = require(UI:WaitForChild("NationLabels"))
local TerritoryLayer = require(Render:WaitForChild("TerritoryLayer"))
local Theme = require(UI:WaitForChild("Theme"))
local WaterSparkles = require(Render:WaitForChild("WaterSparkles"))

local player = Players.LocalPlayer
local lang: Strings.Lang = Strings.langFromLocale(
	if Config.Dev.ForceLang ~= "" then Config.Dev.ForceLang else LocalizationService.RobloxLocaleId
)

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

-- Матч: состояние с сервера, слой территорий, города и подписи, армии, HUD.
local cs = ClientState.new(map.width, map.height)
local territory = TerritoryLayer.new(view, map, colors, cs)
local labels = NationLabels.new(view.canvas, cs, lang, map.width)
local armyLayer = ArmyLayer.new(view.canvas, cs)
camera.onChanged(function(state)
	labels.onCamera(state)
end)

-- Интерфейс создаётся до подключения к серверу: сообщения из очереди могут прийти сразу при подключении.
local client: MatchClient.MatchClient? = nil
local function send(kind: string, payload: { [string]: any })
	if client ~= nil then
		client.send(kind, payload)
	end
end

-- HUD — отдельный ScreenGui: ScreenInsets = CoreUISafeInsets держит его вне кнопок Roblox и выреза экрана.
local hudGui = Instance.new("ScreenGui")
hudGui.Name = "FrontirHud"
hudGui.ResetOnSpawn = false
hudGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
hudGui.DisplayOrder = 1
hudGui.Parent = player:WaitForChild("PlayerGui")

local hud = MatchHud.new(hudGui, cs, lang, map, send)
hud.refresh()
local armyPanel = ArmyPanel.new(hudGui, cs, lang, armyLayer, send)
armyPanel.refresh()

client = MatchClient.connect(cs, {
	onInfo = function(colorsChanged: boolean)
		if colorsChanged and cs.hasSnapshot then
			territory.repaintAll()
		end
		labels.refresh()
		hud.refresh()
	end,
	onSnapshot = function()
		territory.repaintAll()
		labels.recolor()
	end,
	onDelta = function(cells: { number })
		territory.cellsChanged(cells, os.clock())
		labels.recolor()
	end,
	onStats = function()
		hud.refresh()
		armyPanel.refresh()
	end,
	onArmies = function() end, -- армии рисуются каждый кадр из ClientState
	onEvents = function(events: { any })
		hud.onEvents(events)
	end,
	onRejected = function(reason: string)
		hud.toast(Strings.get("reject." .. reason, lang))
	end,
})

-- Рамка выделения армий (ПК): рисуется в той же системе координат, что и карта.
local boxFrame = Instance.new("Frame")
boxFrame.Name = "SelectionBox"
boxFrame.BackgroundColor3 = Theme.Colors.Gold
boxFrame.BackgroundTransparency = 0.85
boxFrame.BorderSizePixel = 0
boxFrame.Visible = false
boxFrame.ZIndex = 20
local boxStroke = Instance.new("UIStroke")
boxStroke.Color = Theme.Colors.Gold
boxStroke.Thickness = 1
boxStroke.Parent = boxFrame
boxFrame.Parent = viewport

local input = CameraInput.bind(camera, viewport, {
	onTap = function(sx: number, sy: number, shift: boolean)
		local cx, cy = CameraMath.cellAt(camera.state, sx, sy)
		local cell = if cx ~= nil and cy ~= nil then cy * map.width + cx else nil
		-- Сначала армии (выбор или приказ), потом HUD (старт, атака границей).
		if armyPanel.tap(sx, sy, cell, shift, camera.state) then
			return
		end
		if cell ~= nil then
			hud.tapCell(cell)
		end
	end,
	onBox = function(x0: number, y0: number, x1: number, y1: number, shift: boolean)
		armyPanel.box(x0, y0, x1, y1, shift, camera.state)
	end,
	onBoxPreview = function(x0: number, y0: number, x1: number, y1: number)
		boxFrame.Visible = true
		boxFrame.Position = UDim2.fromOffset(math.min(x0, x1), math.min(y0, y1))
		boxFrame.Size = UDim2.fromOffset(math.abs(x1 - x0), math.abs(y1 - y0))
	end,
	onBoxEnd = function()
		boxFrame.Visible = false
	end,
	-- Space — к своей столице (GDD §10); нет столицы — вся карта.
	onHome = function()
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		local capital = if me ~= nil then me.capital else nil
		if capital ~= nil then
			CameraMath.centerOn(camera.state, capital % map.width + 0.5, capital // map.width + 0.5)
			camera.refresh()
		else
			camera.fit()
		end
	end,
})

local frameConn = RunService.RenderStepped:Connect(function()
	local now = os.clock()
	territory.update(now)
	armyLayer.update(now, camera.state)
	armyPanel.update()
	hud.update(now)
end)

DebugOverlay.create(hudGui, {
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
		local armies = 0
		for _ in cs.armies do
			armies += 1
		end
		table.insert(lines, string.format(Strings.get("debug.armies", lang), armies))
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
