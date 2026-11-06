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
	этап 7в-1: окно «Технологии» (Y, TechPanel), закрытые технологией здания в меню «Построить»;
	этап 7в-2: выбор генерала в лобби, способности Q / E (CommanderPanel), вспышка снимает туман;
	этап 7г: баннер событий и аукцион наёмников (WorldPanel), круги шторма и ракет (MarkerLayer), пуск ракеты (R);
	этап 8а: голосование за режим, сложность, пауза и ×2 «Против ботов» (ModePanel), режим и команды в HUD.
]]

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local AudioCues = require(Shared:WaitForChild("AudioCues"))
local Config = require(Shared:WaitForChild("Config"))
local Flood = require(Shared:WaitForChild("Flood"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local RenderBudget = require(Shared:WaitForChild("RenderBudget"))
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
local MarkerLayer = require(Render:WaitForChild("MarkerLayer"))
local WarFxLayer = require(Render:WaitForChild("WarFxLayer"))
local AirPanel = require(UI:WaitForChild("AirPanel"))
local BuildPanel = require(UI:WaitForChild("BuildPanel"))
local CityLabels = require(UI:WaitForChild("CityLabels"))
local BuildingInfo = require(UI:WaitForChild("BuildingInfo"))
local Polish = require(UI:WaitForChild("Polish"))
local BuildGhost = require(Render:WaitForChild("BuildGhost"))
local CloudLayer = require(Render:WaitForChild("CloudLayer"))
local BuildingLayer = require(Render:WaitForChild("BuildingLayer"))
local CouncilPanel = require(UI:WaitForChild("CouncilPanel"))
local DebugOverlay = require(UI:WaitForChild("DebugOverlay"))
local DevPanel = require(UI:WaitForChild("DevPanel"))
local DiplomacyPanel = require(UI:WaitForChild("DiplomacyPanel"))
local ForcesPanel = require(UI:WaitForChild("ForcesPanel"))
local FrontLayer = require(Render:WaitForChild("FrontLayer"))
local MapRenderer = require(Render:WaitForChild("MapRenderer"))
local MatchClient = require(Client:WaitForChild("Net"):WaitForChild("MatchClient"))
local Session = require(Client:WaitForChild("Session"))
local SelfCheck = require(Client:WaitForChild("SelfCheck"))
local Audio = require(Client:WaitForChild("Audio"))
local SoundPanel = require(UI:WaitForChild("SoundPanel"))
local ProvinceLabels = require(UI:WaitForChild("ProvinceLabels"))
local MatchHud = require(UI:WaitForChild("MatchHud"))
local Minimap = require(UI:WaitForChild("Minimap"))
local NavalPanel = require(UI:WaitForChild("NavalPanel"))
local NationLabels = require(UI:WaitForChild("NationLabels"))
local Pings = require(UI:WaitForChild("Pings"))
local ResultsPanel = require(UI:WaitForChild("ResultsPanel"))
local ShipLayer = require(Render:WaitForChild("ShipLayer"))
local StabilityPanel = require(UI:WaitForChild("StabilityPanel"))
local TechPanel = require(UI:WaitForChild("TechPanel"))
local CommanderPanel = require(UI:WaitForChild("CommanderPanel"))
local ModePanel = require(UI:WaitForChild("ModePanel"))
local ServerPanel = require(UI:WaitForChild("ServerPanel"))
local ShopPanel = require(UI:WaitForChild("ShopPanel"))
local WardrobePanel = require(UI:WaitForChild("WardrobePanel"))
local QuestsPanel = require(UI:WaitForChild("QuestsPanel"))
local TutorialPanel = require(UI:WaitForChild("TutorialPanel"))
local WorldPanel = require(UI:WaitForChild("WorldPanel"))
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
-- Сессия на одну карту (этап 8б, §5.2): при смене карты всё снимается и строится заново.
local function runSession(mapId: string, resync: boolean)
	local teardown: () -> ()
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

	Session.track(gui)
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
	local stopSparkles, sparklesOnCamera = WaterSparkles.start(
		view.canvas,
		map,
		MapPaint.sparkleMask(map, depth, Config.Render.SparkleMinDepth),
		camera.state
	)
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
	local buildingLayer = BuildingLayer.new(view.canvas, cs, provinces, map)
	local buildGhost = BuildGhost.new(view.canvas, map.width) -- «призрак» стройки (§15г)
	local clouds = CloudLayer.new(view.canvas, map.width, map.height) -- тени облаков (§15г)
	local shipLayer = ShipLayer.new(view.canvas, cs)
	local airLayer = AirLayer.new(view.canvas, cs)
	local markerLayer = MarkerLayer.new(view.canvas, cs) -- шторм и ракеты (§6.16, §6.9)
	local provinceLabels = ProvinceLabels.new(view.canvas, provinces, map.width, lang) -- названия с зума ×6
	local cityLabels = CityLabels.new(view.canvas, cs, provinces, map, lang) -- названия городов (§15д ч.4)
	camera.onChanged(function(state)
		provinceLabels.onCamera(state)
		cityLabels.onCamera(state)
		labels.onCamera(state)
		buildingLayer.onCamera(state)
		buildGhost.onCamera(state)
	end)

	-- Интерфейс создаётся до подключения к серверу: сообщения из очереди могут прийти сразу при подключении.
	local client: MatchClient.MatchClient? = nil
	local throttle = AudioCues.newThrottle()
	local function sound(name: string)
		if AudioCues.allow(throttle, name, os.clock()) then
			Audio.play(name)
		end
	end
	local function send(kind: string, payload: { [string]: any })
		if client ~= nil then
			client.send(kind, payload)
		end
		-- Звук своего действия (§13): найм и стройка сразу, отказ сервера — «Error».
		if kind == "hire" then
			sound("Hire")
		elseif kind == "build" then
			sound("Build")
		end
	end

	-- HUD — отдельный ScreenGui: ScreenInsets = CoreUISafeInsets держит его вне кнопок Roblox и выреза экрана.
	local hudGui = Instance.new("ScreenGui")
	hudGui.Name = "FrontirHud"
	hudGui.ResetOnSpawn = false
	hudGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	hudGui.DisplayOrder = 1
	Session.track(hudGui)
	hudGui.Parent = player:WaitForChild("PlayerGui")
	Polish.attach(hudGui) -- скругления, градиенты, отклик кнопок, появление окон (§15г)

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
	-- Зрелищная война (§15б): баннер, искры границы, виньетка, стрелки наступления, вспышки захвата.
	local warFx = WarFxLayer.new(view.canvas, hudGui, cs, lang)
	wars.refresh()
	local build = BuildPanel.new(hudGui, cs, lang, send, hud.toast, map, provinces, buildGhost)
	build.refresh()
	local buildingInfo = BuildingInfo.new(hudGui, cs, lang, send, map) -- окно своего здания (§15д)
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
	local commanderPanel = CommanderPanel.new(hudGui, cs, lang, send, hud.percent)
	local modePanel = ModePanel.new(hudGui, cs, lang, send)
	local serverPanel = ServerPanel.new(hudGui, cs, lang, send) -- частный сервер (§5.4)
	local shopPanel = ShopPanel.new(hudGui, cs, lang, send, hud.toast) -- профиль и магазин (§11.1)
	local wardrobe = WardrobePanel.new(hudGui, cs, lang, send) -- косметика и флаг (§11.4)
	local questsPanel = QuestsPanel.new(hudGui, cs, lang, hud.toast) -- задания и лидеры (§11.5)
	local tutorial = TutorialPanel.new(hudGui, cs, lang, hud.toast) -- обучение (§5.5)
	local soundPanel = SoundPanel.new(hudGui, cs, lang, send) -- громкости (§13)
	-- Клик (§13): любая кнопка HUD, в том числе созданная позже.
	local function hookButton(inst: Instance)
		if inst:IsA("GuiButton") then
			Session.connect((inst :: GuiButton).Activated, function()
				sound("Click")
			end)
		end
	end
	for _, d in hudGui:GetDescendants() do
		hookButton(d)
	end
	Session.connect(hudGui.DescendantAdded, hookButton)
	-- Суша для доли лидера (музыка «Финал») и города (звук взятого города).
	local totalLand = 0
	for i = 0, map.width * map.height - 1 do
		if Config.Terrain[MapDataModule.getTerrain(map, i)].borderPassable then
			totalLand += 1
		end
	end
	local citySet: { [number]: boolean } = {}
	local resultFor: number? = nil -- matchId, за который уже прозвучал итог
	local lastReward: any = nil
	local worldPanel = WorldPanel.new(hudGui, cs, lang, send, function(id: number): string
		local n = cs.nations[id]
		return if n == nil then "?" elseif lang == "en" then n.nameEn else n.name
	end)
	local naval = NavalPanel.new(hudGui, cs, lang, map, provinces, send, hud.percent, shipLayer.pick, shipLayer.select)
	local airPanel = AirPanel.new(hudGui, cs, lang, map, provinces, send, airLayer.pick, airLayer.select)
	-- Панель разработчика (F4) — только в Studio; создаётся в фоне (ждёт канал Remotes.Dev от сервера).
	local devPanel: DevPanel.DevPanel? = nil
	task.spawn(function()
		devPanel = DevPanel.new(hudGui, cs, lang, SelfCheck.start)
	end)
	-- Самопроверка (Studio, F4): окна этой сессии; модуль живёт над сессиями (смена карты).
	SelfCheck.attach({
		cs = cs,
		mapId = mapId,
		windows = {
			{ name = "дипломатия", toggle = diplomacy.toggle, isOpen = diplomacy.isOpen },
			{ name = "технологии", toggle = techPanel.toggle, isOpen = techPanel.isOpen },
			{ name = "магазин", toggle = shopPanel.toggle, isOpen = shopPanel.isOpen },
			{ name = "гардероб", toggle = wardrobe.toggle, isOpen = wardrobe.isOpen },
			{ name = "задания", toggle = questsPanel.toggle, isOpen = questsPanel.isOpen },
			{
				name = "настройки сервера",
				toggle = serverPanel.toggle,
				isOpen = serverPanel.isOpen,
				skip = function(): string?
					local info = cs.server
					if info == nil or not info.isOwner then
						return "не частный сервер (Config.Dev.PrivateServer = true)"
					end
					if cs.phase ~= "Lobby" and cs.phase ~= "Waiting" then
						return "открывается только в лобби"
					end
					return nil
				end,
			},
		},
		commanderOpen = commanderPanel.isOpen,
		air = airPanel,
		naval = naval,
		zoom = function(): number
			return camera.state.zoom
		end,
	})
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

	-- «Потоп» (§5.3): утонувшие клетки — водой в цветах карты (их же рисует мини-карта); новый матч — суша целая.
	local baseColors = buffer.create(buffer.len(colors))
	buffer.copy(baseColors, 0, colors)
	local floodShown = 0
	local function syncFlood()
		local target = if cs.flood ~= nil then cs.flood.step else 0
		if target == floodShown then
			return
		end
		if target < floodShown then
			buffer.copy(colors, 0, baseColors)
			floodShown = 0
			territory.repaintAll()
			gridChanged()
			if target == 0 then
				return
			end
		end
		local cells = Flood.paint(colors, Flood.levels(map), map.width, floodShown, target)
		floodShown = target
		territory.cellsChanged(cells, os.clock(), false)
		gridChanged()
	end

	-- Туман (§6.11): пересчёт обзора раз в Fog.RefreshSec и сразу — при смене фазы, державы, «Туман выкл».
	local fogAt, fogMs = -math.huge, 0
	local revealOn = false -- идёт ли «Радарная вспышка» (§6.15)
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
		-- Смена карты (§5.2): сервер начал матч на другой карте — снять сессию и загрузить её.
		onMapChange = function(newMapId: string)
			task.defer(function()
				teardown()
				runSession(newMapId, true)
			end)
		end,
		onLeaders = function()
			questsPanel.refresh()
		end,
		onShopEvent = function(msg: any)
			if msg.kind == "quests" then
				questsPanel.onQuests(msg)
				return
			end
			shopPanel.onShopEvent(msg)
		end,
		onProfile = function()
			soundPanel.refresh()
			local reward = if cs.profile ~= nil then cs.profile.reward else nil
			if reward ~= nil and reward ~= lastReward then
				sound("Coin")
			end
			lastReward = reward
			shopPanel.refresh()
			wardrobe.refresh()
			questsPanel.refresh()
			commanderPanel.refresh()
		end,
		onInfo = function(colorsChanged: boolean)
			-- Звук (§13): города — для «Province»; итог матча — победа или поражение один раз.
			table.clear(citySet)
			for _, c in cs.cities do
				citySet[c] = true
			end
			local result = cs.result
			if cs.phase == "Over" and result ~= nil and resultFor ~= cs.matchId then
				resultFor = cs.matchId
				local name = AudioCues.result(result.winner, result.coWinners, cs.myNation)
				if name ~= nil then
					Audio.play(name)
				end
			end
			-- Новый матч тоже приходит как смена цветов: ClientState уже сбросил сетку, перерисовываем всё.
			if colorsChanged then
				territory.repaintAll()
				gridChanged()
			end
			syncFlood()
			refreshFog(os.clock()) -- фаза или своя держава могли смениться (зритель видит всё)
			labels.refresh()
			cityLabels.refresh() -- новые города (§15д ч.4)
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
			commanderPanel.refresh()
			modePanel.refresh()
			serverPanel.refresh()
			tutorial.refresh()
			shopPanel.refresh()
			naval.refresh()
			airPanel.refresh()
		end,
		onSnapshot = function()
			ClientState.refreshFog(cs)
			territory.repaintAll()
			gridChanged()
			labels.recolor()
			buildingLayer.recolor()
			warFx.onSnapshot()
		end,
		onDelta = function(cells: { number })
			warFx.onDelta(cells) -- вспышки захвата (§15б)
			-- Звук захвата (§13): свои новые клетки; город — «Province».
			local me = cs.myNation
			if me ~= nil and cs.phase == "Play" then
				local mine, city = false, false
				for _, c in cells do
					if ClientState.ownerAt(cs, c) == me then
						mine = true
						if citySet[c] then
							city = true
						end
					end
				end
				if city then
					sound("Province")
				elseif mine then
					sound("Capture")
				end
			end
			territory.cellsChanged(cells, os.clock())
			gridChanged()
			labels.recolor()
			buildingLayer.recolor()
		end,
		onStats = function()
			-- Бой на своём фронте (§13) — не чаще Audio.Gaps.Battle.
			local stats, me = cs.stats, cs.myNation
			if stats ~= nil and me ~= nil then
				for _, a in stats.attacks do
					if a.fighting and (a.attacker == me or a.target == me) then
						sound("Battle")
						break
					end
				end
			end
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
			buildingInfo.refresh() -- деньги поменялись: цена улучшения доступна или нет
		end,
		onBuildings = function()
			buildingLayer.refresh()
			build.onBuildings() -- эффект постройки (§15г)
			cityLabels.refresh() -- уровни городов
			buildingInfo.refresh()
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
		onWorld = function(newOil: { number })
			-- Нефтяная лихорадка (§6.16): новые поля — в провинции клиента и значки на карте.
			for _, p in newOil do
				local province = provinces.list[p]
				if province ~= nil then
					(province :: any).oil = true
				end
			end
			if #newOil > 0 then
				buildingLayer.refresh()
			end
			markerLayer.refresh()
			buildingLayer.charges() -- заряды ПВО (§15д ч.3)
			worldPanel.refresh()
			commanderPanel.update(os.clock())
		end,
		onCommander = function()
			commanderPanel.refresh()
			-- Радарная вспышка (§6.15) началась — обзор сразу (конец — обычным пересчётом раз в Fog.RefreshSec).
			local now = ClientState.revealLeft(cs, os.clock()) > 0
			if now ~= revealOn then
				revealOn = now
				refreshFog(os.clock())
			end
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
			for _, name in AudioCues.fromEvents(events, cs.myNation) do
				sound(name)
			end
			hud.onEvents(events)
			wars.onEvents(events)
			pings.onEvents(events)
			airLayer.onEvents(events) -- вспышки бомб и сбитые самолёты
			markerLayer.onEvents(events) -- круг ракеты сразу при пуске
			warFx.onEvents(events) -- баннер войны, искры границы (§15б)
			worldPanel.onEvents(events) -- баннер события
			tutorial.onEvents(events) -- шаги обучения (§5.5)
		end,
		onDev = function(msg: any)
			if type(msg.fog) == "boolean" then
				cs.fogOff = not msg.fog
				refreshFog(os.clock())
			end
			if devPanel ~= nil then
				devPanel.onDev(msg)
			end
			SelfCheck.onDev(msg)
		end,
		onRejected = function(reason: string)
			sound("Error")
			hud.toast(Strings.get("reject." .. reason, lang))
		end,
	}, mapId)

	local function goHome()
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		local capital = if me ~= nil then me.capital else nil
		if capital ~= nil then
			CameraMath.centerOn(camera.state, capital % map.width + 0.5, capital // map.width + 0.5)
			camera.refresh()
		else
			camera.fit()
		end
	end
	-- Телефон (этап 10в): кнопка «⌂» — к столице (на ПК — пробел), над кнопкой звука.
	if RenderBudget.isPhone(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled) then
		local home = Instance.new("TextButton")
		home.Name = "HomeButton"
		home.AnchorPoint = Vector2.new(1, 1)
		home.Size = UDim2.fromOffset(Config.Render.MinTouchTargetPx, Config.Render.MinTouchTargetPx)
		home.Position = UDim2.new(1, -12, 1, -12 - Config.Render.MinimapSide - 8 - Config.Render.MinTouchTargetPx - 6)
		home.BackgroundColor3 = Theme.Colors.PanelBg
		home.BackgroundTransparency = 0.05
		home.BorderSizePixel = 0
		home.FontFace = Theme.FontBold
		home.TextSize = 20
		home.TextColor3 = Theme.Colors.Text
		home.Text = "⌂"
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = Theme.Colors.PanelBorder
		stroke.Parent = home
		home.Parent = hudGui
		Session.connect(home.Activated, goHome)
	end

	local input = CameraInput.bind(camera, viewport, {
		onTap = function(sx: number, sy: number)
			local cx, cy = CameraMath.cellAt(camera.state, sx, sy)
			if cx ~= nil and cy ~= nil then
				local cell = cy * map.width + cx
				-- Режим стройки забирает нажатие; иначе — старт, атака, война.
				local handled = shopPanel.tap(cell) -- цель «Авиаудара» (§11.3)
					or commanderPanel.tap(cell)
					or build.tap(cell)
					or diplomacy.tap(cell)
					or pings.tap(cell)
					or naval.tap(cell, camera.state.zoom)
					or airPanel.tap(cell, camera.state.zoom)
					or buildingInfo.tap(cell)
				if not handled then
					hud.tapCell(cell)
				end
			end
		end,
		-- Space — к своей столице (GDD §10); нет столицы — вся карта. На телефоне — кнопка «⌂».
		onHome = goHome,
	})
	-- «Призрак» стройки за курсором (§15г).
	Session.connect(UserInputService.InputChanged, function(io: InputObject)
		if io.UserInputType ~= Enum.UserInputType.MouseMovement or not build.active() then
			return
		end
		local p = io.Position
		local inset = viewport.AbsolutePosition
		local cx, cy = CameraMath.cellAt(camera.state, p.X - inset.X, p.Y - inset.Y)
		build.hover(if cx ~= nil and cy ~= nil then cy * map.width + cx else nil)
	end)

	local musicAt = 0
	local cloudsAt = os.clock()
	local frameConn = Session.connect(RunService.RenderStepped, function()
		local now = os.clock()
		-- Музыка (§13): лобби, игра или финал — раз в полсекунды.
		if now - musicAt >= 0.5 then
			musicAt = now
			local leader = 0
			local stats = cs.stats
			if stats ~= nil then
				for _, s in stats.nations do
					leader = math.max(leader, s.cells)
				end
			end
			local limit = cs.rules.timeLimitSec
			Audio.music(AudioCues.music({
				phase = cs.phase,
				leaderShare = leader / math.max(1, totalLand),
				victoryShare = cs.rules.victoryShare,
				timeLeft = if limit > 0 then limit - ClientState.matchTime(cs, now) else nil,
			}))
		end
		if now - fogAt >= Config.Fog.RefreshSec then
			refreshFog(now)
		end
		territory.update(now)
		clouds.update(math.clamp(now - cloudsAt, 0, 0.25), camera.state)
		cloudsAt = now
		frontLayer.update(now, camera.state)
		shipLayer.update(now, camera.state)
		airLayer.update(now, camera.state)
		markerLayer.update(now, camera.state)
		warFx.update(now, camera.state)
		worldPanel.update(now)
		hud.update(now)
		commanderPanel.update(now)
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
			table.insert(
				lines,
				string.format(Strings.get("debug.ping", lang), math.round(player:GetNetworkPing() * 1000))
			)
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

	-- Снять сессию: рендер, ввод, камера и всё из Session (подписки, интерфейс, EditableImage).
	function teardown()
		stopSparkles()
		frameConn:Disconnect()
		input.disconnect()
		camera.destroy()
		view.destroy()
		Session.reset()
	end
	Session.connect(player.AncestryChanged, function()
		if not player:IsDescendantOf(game) then
			teardown()
		end
	end)
	if resync then
		send("sync", {}) -- карта сменилась: сервер пришлёт info, договоры и сетку заново
	end

	print(
		string.format(
			"[Frontir] client: карта %s %d×%d, чанков %d",
			map.name,
			map.width,
			map.height,
			view.chunkCount
		)
	)
end

runSession(mapId :: string, false)
