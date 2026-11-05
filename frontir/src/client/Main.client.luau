--!strict
--[[
	Точка входа клиента. Клиент только отправляет намерения и рисует (docs/GDD.md §0, п. 4).
	Карта, выбранная сервером, рендер через EditableImage, камера, блики, F3;
	этап 2: приём матча (MatchClient), слой территорий, подписи держав, HUD, нажатия на карту;
	этап 3а: города; этап 3б: войска державы (найм Z/X/C/V, панель войск), юниты и бой на линиях фронтов;
	этап 3в: война и мир (объявление, баннер войны, окно мира), бой на фронте с артиллерией, воронками и дымом;
	этап 4в: цикл матча (лобби → выбор → игра → итоги → новый матч), экран результатов, мини-карта;
	этап 6а: окно дипломатии (T), предложения и требования, метка «Предатель»;
	этап 6б: Совет держав, торговля в окне дипломатии, пинги на карте (G);
	этап 7а: туман войны (обзор раз в Fog.RefreshSec), стабильность в HUD, режим карты «Стабильность» (N);
	этап 7б-1: корабли на карте (ShipLayer), меню порта, высадка и патруль (NavalPanel);
	этап 7б-2: самолёты на карте (AirLayer), меню аэродрома, налёт и прикрытие (AirPanel);
	этап 7в-1: окно «Технологии» (Y, TechPanel), закрытые технологией здания в меню «Построить».
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
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))

local Client = script.Parent
local Render = Client:WaitForChild("Render")
local UI = Client:WaitForChild("UI")
local Camera2D = require(Render:WaitForChild("Camera2D"))
local CameraInput = require(Client:WaitForChild("Input"):WaitForChild("CameraInput"))
local AirLayer = require(Render:WaitForChild("AirLayer"))
local AirPanel = require(UI:WaitForChild("AirPanel"))
local BuildPanel = require(UI:WaitForChild("BuildPanel"))
local BuildingLayer = require(Render:WaitForChild("BuildingLayer"))
local CouncilPanel = require(UI:WaitForChild("CouncilPanel"))
local DebugOverlay = require(UI:WaitForChild("DebugOverlay"))
local DevPanel = require(UI:WaitForChild("DevPanel"))
local DiplomacyPanel = require(UI:WaitForChild("DiplomacyPanel"))
local ForcesPanel = require(UI:WaitForChild("ForcesPanel"))
local FrontLayer = require(Render:WaitForChild("FrontLayer"))
local MapRenderer = require(Render:WaitForChild("MapRenderer"))
local MatchClient = require(Client:WaitForChild("Net"):WaitForChild("MatchClient"))
local MatchHud = require(UI:WaitForChild("MatchHud"))
local Minimap = require(UI:WaitForChild("Minimap"))
local NavalPanel = require(UI:WaitForChild("NavalPanel"))
local NationLabels = require(UI:WaitForChild("NationLabels"))
local Pings = require(UI:WaitForChild("Pings"))
local ResultsPanel = require(UI:WaitForChild("ResultsPanel"))
local ShipLayer = require(Render:WaitForChild("ShipLayer"))
local StabilityPanel = require(UI:WaitForChild("StabilityPanel"))
local TechPanel = require(UI:WaitForChild("TechPanel"))
local TerritoryLayer = require(Render:WaitForChild("TerritoryLayer"))
local Theme = require(UI:WaitForChild("Theme"))
local WarPanel = require(UI:WaitForChild("WarPanel"))
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

-- Матч: состояние с сервера, слой территорий, города и подписи, юниты на фронтах, HUD.
local cs = ClientState.new(map.width, map.height)
-- Провинции считаются из карты так же, как на сервере (нефтяные поля, центры) — по сети не идут.
local provinces = Provinces.build(map)
local territory = TerritoryLayer.new(view, map, colors, cs, provinces)
local labels = NationLabels.new(view.canvas, cs, lang, map.width)
local frontLayer = FrontLayer.new(view.canvas, cs, map)
local buildingLayer = BuildingLayer.new(view.canvas, cs, provinces)
local shipLayer = ShipLayer.new(view.canvas, cs)
local airLayer = AirLayer.new(view.canvas, cs)
camera.onChanged(function(state)
	labels.onCamera(state)
	buildingLayer.onCamera(state)
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

-- Нажатие на страну без войны → окно «Объявить войну» (WarPanel создаётся после HUD: ей нужна лента HUD).
local warPanel: WarPanel.WarPanel? = nil
local hud = MatchHud.new(hudGui, cs, lang, map, send, function(owner: number)
	if warPanel ~= nil then
		warPanel.offerDeclare(owner)
	end
end, provinces)
hud.refresh()
-- «К фронту»: камера на линию фронта, приблизить хотя бы до ×4, чтобы был виден бой.
local function toFront(x: number, y: number)
	CameraMath.centerOn(camera.state, x, y)
	camera.refresh()
	local s = camera.state
	if s.zoom < 4 then
		camera.zoomTo(4, s.viewW / 2, s.viewH / 2)
	end
end
local wars = WarPanel.new(hudGui, cs, lang, send, hud.toast, toFront)
warPanel = wars
wars.refresh()
local build = BuildPanel.new(hudGui, cs, lang, send, hud.toast)
build.refresh()
local forcesPanel = ForcesPanel.new(hudGui, cs, lang, send)
forcesPanel.refresh()
-- Мини-карта справа снизу: нажатие — камера туда. Нет памяти под EditableImage — играем без неё.
local minimap = Minimap.new(hudGui, cs, colors, map.width, map.height, function(wx: number, wy: number)
	CameraMath.centerOn(camera.state, wx, wy)
	camera.refresh()
end)
local results = ResultsPanel.new(hudGui, cs, lang)
results.refresh()
local diplomacy = DiplomacyPanel.new(hudGui, cs, lang, map, provinces, send, hud.toast, wars.offerDeclare)
diplomacy.refresh()
local council = CouncilPanel.new(hudGui, cs, lang, send)
council.refresh()
local pings = Pings.new(hudGui, view.canvas, cs, lang, send, hud.toast)
local stabilityPanel = StabilityPanel.new(hudGui, view.canvas, cs, lang, provinces, territory.setStabilityMode)
stabilityPanel.refresh()
local techPanel = TechPanel.new(hudGui, cs, lang, send)
local naval = NavalPanel.new(hudGui, cs, lang, map, provinces, send, hud.percent, shipLayer.pick, shipLayer.select)
local airPanel = AirPanel.new(hudGui, cs, lang, map, provinces, send, airLayer.pick, airLayer.select)
-- Панель разработчика (F4) — только в Studio; создаётся в фоне (ждёт канал Remotes.Dev от сервера).
local devPanel: DevPanel.DevPanel? = nil
task.spawn(function()
	devPanel = DevPanel.new(hudGui, cs, lang)
end)
pings.refresh()
camera.onChanged(function(state)
	pings.onCamera(state)
	stabilityPanel.onCamera(state)
end)
local function gridChanged()
	if minimap ~= nil then
		minimap.changed()
	end
end

-- Туман (§6.11): пересчёт обзора раз в Fog.RefreshSec и сразу — при смене фазы, державы, «Туман выкл».
local fogAt, fogMs = -math.huge, 0
local function refreshFog(now: number)
	fogAt = now
	local t0 = os.clock()
	local full, cells = ClientState.refreshFog(cs)
	fogMs = (os.clock() - t0) * 1000
	if full then
		territory.repaintAll()
	elseif #cells > 0 then
		territory.cellsChanged(cells, now, false)
	else
		return
	end
	gridChanged()
	labels.recolor()
	buildingLayer.refresh()
end

client = MatchClient.connect(cs, {
	onInfo = function(colorsChanged: boolean)
		-- Новый матч тоже приходит как смена цветов: ClientState уже сбросил сетку, перерисовываем всё.
		if colorsChanged then
			territory.repaintAll()
			gridChanged()
		end
		refreshFog(os.clock()) -- фаза или своя держава могли смениться (зритель видит всё)
		labels.refresh()
		hud.refresh()
		forcesPanel.refresh()
		wars.refresh()
		build.refresh()
		buildingLayer.refresh()
		results.refresh()
		diplomacy.refresh()
		council.refresh()
		pings.refresh()
		stabilityPanel.refresh()
		techPanel.refresh()
		naval.refresh()
		airPanel.refresh()
	end,
	onSnapshot = function()
		ClientState.refreshFog(cs)
		territory.repaintAll()
		gridChanged()
		labels.recolor()
		buildingLayer.recolor()
	end,
	onDelta = function(cells: { number })
		territory.cellsChanged(cells, os.clock())
		gridChanged()
		labels.recolor()
		buildingLayer.recolor()
	end,
	onStats = function()
		hud.refresh()
		forcesPanel.refresh()
		diplomacy.refresh()
	end,
	onDiplo = function()
		diplomacy.refresh()
		council.refresh()
		labels.refresh() -- метка «Предатель» на подписях
		hud.refresh()
	end,
	onForces = function()
		forcesPanel.refresh()
		hud.refresh()
		build.refresh()
	end,
	onBuildings = function()
		buildingLayer.refresh()
	end,
	onShips = function()
		shipLayer.refresh()
		naval.refresh()
	end,
	onAir = function()
		airLayer.refresh()
		airPanel.refresh()
		hud.refresh()
	end,
	onTech = function()
		techPanel.refresh()
		build.refresh()
	end,
	onStability = function(rebelsChanged: { number })
		territory.provincesChanged(rebelsChanged)
		territory.stabilityChanged()
		stabilityPanel.refresh()
		hud.refresh()
	end,
	onWars = function()
		wars.refresh()
		diplomacy.refresh()
	end,
	onEvents = function(events: { any })
		hud.onEvents(events)
		wars.onEvents(events)
		pings.onEvents(events)
		airLayer.onEvents(events) -- вспышки бомб и сбитые самолёты
	end,
	onDev = function(msg: any)
		if type(msg.fog) == "boolean" then
			cs.fogOff = not msg.fog
			refreshFog(os.clock())
		end
		if devPanel ~= nil then
			devPanel.onDev(msg)
		end
	end,
	onRejected = function(reason: string)
		hud.toast(Strings.get("reject." .. reason, lang))
	end,
})

local input = CameraInput.bind(camera, viewport, {
	onTap = function(sx: number, sy: number)
		local cx, cy = CameraMath.cellAt(camera.state, sx, sy)
		if cx ~= nil and cy ~= nil then
			local cell = cy * map.width + cx
			-- Режим стройки забирает нажатие; иначе — старт, атака, война.
			local handled = build.tap(cell)
				or diplomacy.tap(cell)
				or pings.tap(cell)
				or naval.tap(cell, camera.state.zoom)
				or airPanel.tap(cell, camera.state.zoom)
			if not handled then
				hud.tapCell(cell)
			end
		end
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
	if now - fogAt >= Config.Fog.RefreshSec then
		refreshFog(now)
	end
	territory.update(now)
	frontLayer.update(now, camera.state)
	shipLayer.update(now, camera.state)
	airLayer.update(now, camera.state)
	hud.update(now)
	wars.update(now)
	results.update(now)
	diplomacy.update(now)
	council.update(now)
	pings.update(now)
	if minimap ~= nil then
		minimap.update(now, camera.state)
	end
end)

local netBytes, netAt, netRate = 0, os.clock(), 0
DebugOverlay.create(hudGui, {
	map = map,
	state = camera.state,
	chunkCount = view.chunkCount,
	memoryBytes = view.memoryBytes,
	hover = input.hover,
	bottomInset = if minimap ~= nil then minimap.height + 12 else 0,
	extra = function(): { string }
		local lines: { string } = {}
		local stats = cs.stats
		if stats ~= nil then
			table.insert(lines, string.format(Strings.get("debug.server", lang), stats.tickMs, stats.changed))
		end
		table.insert(lines, string.format(Strings.get("debug.ping", lang), math.round(player:GetNetworkPing() * 1000)))
		-- Сеть: принятые байты за последнюю секунду (buffer-сообщения и таблицы).
		local now = os.clock()
		if now - netAt >= 1 then
			netRate = (cs.bytes - netBytes) / (now - netAt)
			netBytes, netAt = cs.bytes, now
		end
		table.insert(lines, string.format(Strings.get("debug.net", lang), netRate / 1024))
		table.insert(lines, string.format(Strings.get("debug.fog", lang), fogMs))
		if stats ~= nil then
			local fronts, fighting = 0, 0
			for _, a in stats.attacks do
				if a.target ~= 0 then
					fronts += 1
					if a.fighting then
						fighting += 1
					end
				end
			end
			table.insert(lines, string.format(Strings.get("debug.fronts", lang), fronts, fighting))
		end
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
