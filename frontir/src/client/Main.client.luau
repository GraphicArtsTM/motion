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
local SocialService = game:GetService("SocialService")
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
local Types = require(Shared:WaitForChild("Types"))
local RenderBudget = require(Shared:WaitForChild("RenderBudget"))
local MapFormat = require(Shared:WaitForChild("MapFormat"))
local MapPaint = require(Shared:WaitForChild("MapPaint"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))
local StrikeMenu = require(Shared:WaitForChild("StrikeMenu"))

local Client = script.Parent
local Render = Client:WaitForChild("Render")
local UI = Client:WaitForChild("UI")
local Camera2D = require(Render:WaitForChild("Camera2D"))
local CameraInput = require(Client:WaitForChild("Input"):WaitForChild("CameraInput"))
local AirLayer = require(Render:WaitForChild("AirLayer"))
local MarkerLayer = require(Render:WaitForChild("MarkerLayer"))
local StrikeFxLayer = require(Render:WaitForChild("StrikeFxLayer"))
local MapHighlightLayer = require(Render:WaitForChild("MapHighlightLayer"))
local SpectacleLayer = require(Render:WaitForChild("SpectacleLayer"))
local WarFxLayer = require(Render:WaitForChild("WarFxLayer"))
local BattleFxLayer = require(Render:WaitForChild("BattleFxLayer"))
local ActionRingUI = require(UI:WaitForChild("ActionRing"))
local StrikeStatus = require(UI:WaitForChild("StrikeStatus"))
local DoomBar = require(UI:WaitForChild("DoomBar"))
local CommandBar = require(UI:WaitForChild("CommandBar"))
local Dock = require(UI:WaitForChild("Dock"))
local AttackPanel = require(UI:WaitForChild("AttackPanel"))
local LobbyScreen = require(UI:WaitForChild("LobbyScreen"))
local SirenPanel = require(UI:WaitForChild("SirenPanel"))
local AlarmBanner = require(UI:WaitForChild("AlarmBanner"))
local ThreatPanel = require(UI:WaitForChild("ThreatPanel"))
local GameMenu = require(UI:WaitForChild("GameMenu"))
local MainMenu = require(UI:WaitForChild("MainMenu"))
local RanksPanel = require(UI:WaitForChild("RanksPanel"))
local HandbookPanel = require(UI:WaitForChild("HandbookPanel"))
local HowToPlay = require(UI:WaitForChild("HowToPlay"))
local MapTooltip = require(UI:WaitForChild("MapTooltip"))
local AirPanel = require(UI:WaitForChild("AirPanel"))
local BuildPanel = require(UI:WaitForChild("BuildPanel"))
local CityLabels = require(UI:WaitForChild("CityLabels"))
local HintPanel = require(UI:WaitForChild("HintPanel"))
local BuildingInfo = require(UI:WaitForChild("BuildingInfo"))
local Polish = require(UI:WaitForChild("Polish"))
local BuildGhost = require(Render:WaitForChild("BuildGhost"))
local CloudLayer = require(Render:WaitForChild("CloudLayer"))
local BuildingLayer = require(Render:WaitForChild("BuildingLayer"))
local CouncilPanel = require(UI:WaitForChild("CouncilPanel"))
local DebugOverlay = require(UI:WaitForChild("DebugOverlay"))
local DevPanel = require(UI:WaitForChild("DevPanel"))
local Layering = require(UI:WaitForChild("Layering"))
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
local MapButtons = require(UI:WaitForChild("MapButtons"))
local PhoneLayout = require(Shared:WaitForChild("PhoneLayout"))
local Minimap = require(UI:WaitForChild("Minimap"))
local NavalPanel = require(UI:WaitForChild("NavalPanel"))
local NationLabels = require(UI:WaitForChild("NationLabels"))
local Pings = require(UI:WaitForChild("Pings"))
local ResultsPanel = require(UI:WaitForChild("ResultsPanel"))
local ShipLayer = require(Render:WaitForChild("ShipLayer"))
local RailLayer = require(Render:WaitForChild("RailLayer"))
local StabilityPanel = require(UI:WaitForChild("StabilityPanel"))
local TechPanel = require(UI:WaitForChild("TechPanel"))
local CommanderPanel = require(UI:WaitForChild("CommanderPanel"))
local ModePanel = require(UI:WaitForChild("ModePanel"))
local ServerPanel = require(UI:WaitForChild("ServerPanel"))
local ShopPanel = require(UI:WaitForChild("ShopPanel"))
local WardrobePanel = require(UI:WaitForChild("WardrobePanel"))
local ArsenalPanel = require(UI:WaitForChild("ArsenalPanel"))
local SceneBanner = require(UI:WaitForChild("SceneBanner"))
local QuestsPanel = require(UI:WaitForChild("QuestsPanel"))
local TutorialPanel = require(UI:WaitForChild("TutorialPanel"))
local WorldPanel = require(UI:WaitForChild("WorldPanel"))
local TerritoryLayer = require(Render:WaitForChild("TerritoryLayer"))
local Theme = require(UI:WaitForChild("Theme"))
local UiScale = require(UI:WaitForChild("UiScale"))
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
-- Главное меню (§15л) открыто при входе; смена карты (новая сессия) сохраняет, было ли оно открыто.
local menuWasOpen = true
-- §15л ч.3: роль сервера узнаём из первого info; на сервере матча игрок пришёл играть — меню при входе не открываем.
local placeSeen = false
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

	-- Подложка под картой: при тряске экрана (§15м) по краям видно море, а не пустоту.
	local underlay = Instance.new("Frame")
	underlay.Name = "MapUnderlay"
	underlay.AnchorPoint = Vector2.new(0.5, 0.5)
	underlay.Position = UDim2.fromScale(0.5, 0.5)
	underlay.Size = UDim2.new(1, 40, 1, 40)
	underlay.BackgroundColor3 = Theme.Colors.Ocean
	underlay.BorderSizePixel = 0
	underlay.ZIndex = 0
	underlay.Parent = gui

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
	-- §15ч Ч2: линии дорог вдали и поезда.
	local railLayer = RailLayer.new(view.canvas, cs, map.width, function(cell: number): boolean
		return MapDataModule.getTerrain(map, cell) == Types.Terrain.River
	end)
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
		-- Хаб и показательный бой (§15л ч.5, ч.7): события матча ботов за меню не звучат.
		if cs.place == "hub" or cs.demo then
			return
		end
		if AudioCues.allow(throttle, name, os.clock()) then
			Audio.play(name)
		end
	end
	-- §15х ч.9: приказ по клетке — шевроны к точке (SpectacleLayer создаётся ниже).
	local onOrder: ((cell: number) -> ())? = nil
	local ORDER_CELL: { [string]: string } =
		{ attack = "focus", land = "target", raid = "cell", cover = "cell", patrol = "cell" }
	local function send(kind: string, payload: { [string]: any })
		if client ~= nil then
			client.send(kind, payload)
		end
		local field = ORDER_CELL[kind]
		local cell = if field ~= nil then payload[field] else nil
		local hook = onOrder
		if hook ~= nil and type(cell) == "number" then
			hook(cell)
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
	UiScale.attach(hudGui) -- §15ц Ц1: интерфейс растёт вместе с экраном
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
	-- Живой фронт (§15м): плашки перевеса, «ПРОРЫВ!», захват городов, выбывание, корона, тряска экрана.
	local battleFx = BattleFxLayer.new(view.canvas, viewport, hudGui, cs, lang, map)
	-- §15х ч.7: зрелище ударов и разрушения (звено и ковёр разрывов, воронки, пожары, выжженная земля).
	local strikeFx = StrikeFxLayer.new(view.canvas, cs, battleFx.shake)
	-- §15х ч.8: граница с врагом пульсирует, контур державы под курсором, котлы с подписью.
	local highlight = MapHighlightLayer.new(view.canvas, cs, lang)
	-- §15х ч.9: зрелищность — флот, взятый город, заражение, шторм, день и ночь, старт, приказ, победа.
	local spectacle = SpectacleLayer.new(view.canvas, cs, strikeFx.spawn, shipLayer.visible, function(cell: number)
		-- Победа: камера к столице победителя, крупно.
		CameraMath.centerOn(camera.state, cell % map.width + 0.5, cell // map.width + 0.5)
		camera.refresh()
		local st = camera.state
		if st.zoom < Config.Render.Spectacle.VictoryZoom then
			camera.zoomTo(Config.Render.Spectacle.VictoryZoom, st.viewW / 2, st.viewH / 2)
		end
	end)
	battleFx.setCityHook(spectacle.cityTaken)
	onOrder = spectacle.order
	wars.refresh()
	local build = BuildPanel.new(hudGui, cs, lang, send, hud.toast, map, provinces, buildGhost)
	build.refresh()
	local buildingInfo = BuildingInfo.new(hudGui, cs, lang, send, map) -- окно своего здания (§15д)
	local hints = HintPanel.new(hudGui, cs, lang) -- «что делать дальше» (§15д ч.5)
	local forcesPanel = ForcesPanel.new(hudGui, cs, lang, send)
	forcesPanel.refresh()
	-- Мини-карта справа снизу: нажатие — камера туда. Нет памяти под EditableImage — играем без неё.
	local minimap = Minimap.new(hudGui, cs, colors, map.width, map.height, function(wx: number, wy: number)
		CameraMath.centerOn(camera.state, wx, wy)
		camera.refresh()
	end)
	-- §15х ч.3: «Сирена» — удар летит по вам: строка сверху, «Показать» — камера к цели.
	-- §15ш Ш2: тревога «на вас атакуют — нет войск» с наймом пехоты (как Z).
	local alarm = AlarmBanner.new(hudGui, cs, lang, forcesPanel.army, function()
		forcesPanel.hire(1)
	end)
	local siren = SirenPanel.new(hudGui, cs, lang, function(cell: number)
		toFront(cell % map.width + 0.5, cell // map.width + 0.5)
	end)
	-- §15ф Ф2: панель «АТАКИ» справа (свои и на вас) и фишки своих атак над полосой.
	local attackPanel = AttackPanel.new(hudGui, cs, lang, send, function(cell: number)
		toFront(cell % map.width + 0.5, cell // map.width + 0.5)
	end)
	-- §15х ч.4б: «Карта угроз» (L, кнопка в доке) — зоны защиты и угроз, «дыры» в своей защите.
	local threat = ThreatPanel.new(hudGui, cs, lang, markerLayer.zone, function(cell: number)
		toFront(cell % map.width + 0.5, cell // map.width + 0.5)
	end)
	local openMainMenu: () -> () = function() end -- главное меню создаётся ниже (§15л)
	local results = ResultsPanel.new(hudGui, cs, lang, function()
		openMainMenu()
	end)
	results.refresh()
	local diplomacy = DiplomacyPanel.new(hudGui, cs, lang, map, provinces, send, hud.toast, wars.offerDeclare)
	diplomacy.refresh()
	-- §15ц Ц4а: созыв Совета открывает окно, только если никакое окно механики не открыто (список sheets ниже).
	local anyWindowOpen: () -> boolean = function(): boolean
		return false
	end
	local council = CouncilPanel.new(hudGui, cs, lang, send, function(): boolean
		return not anyWindowOpen()
	end)
	council.refresh()
	local pings = Pings.new(hudGui, view.canvas, cs, lang, send, hud.toast)
	local stabilityPanel = StabilityPanel.new(
		hudGui,
		view.canvas,
		cs,
		lang,
		provinces,
		territory.setStabilityMode,
		function(cell: number)
			toFront(cell % map.width + 0.5, cell // map.width + 0.5)
		end
	)
	stabilityPanel.refresh()
	local techPanel = TechPanel.new(hudGui, cs, lang, send)
	local commanderPanel = CommanderPanel.new(hudGui, cs, lang, send, hud.percent)
	-- Слева сверху столбиком (§15д ч.5): полоса ресурсов → панель державы → способности генерала (без наложений).
	do
		local nationPanel = hudGui:FindFirstChild("NationPanel") :: Frame?
		local abilities = hudGui:FindFirstChild("Abilities") :: Frame?
		if nationPanel ~= nil and abilities ~= nil then
			local np, ab = nationPanel :: Frame, abilities :: Frame
			local function stack()
				-- §15ф Ф2: дока нет — сразу под кнопкой «≡» (она сверху слева, 8 px от края).
				local left = 12
				np.Position = UDim2.fromOffset(left, 8 + Config.Render.MinTouchTargetPx + 10)
				-- §15ф: панель державы спрятана (в FrontirStash) — способности сразу под «≡».
				local shown = np.Visible and np:IsDescendantOf(hudGui)
				local bottom = np.Position.Y.Offset + (if shown then UiScale.units(np.AbsoluteSize.Y) + 8 else 0)
				ab.Position = UDim2.fromOffset(left, bottom)
			end
			Session.connect(np:GetPropertyChangedSignal("AbsoluteSize"), stack)
			Session.connect(np:GetPropertyChangedSignal("Visible"), stack)
			Session.connect(np.AncestryChanged, stack)
			stack()
		end
	end
	local modePanel = ModePanel.new(hudGui, cs, lang, send)
	local serverPanel = ServerPanel.new(hudGui, cs, lang, send) -- частный сервер (§5.4)
	local shopPanel = ShopPanel.new(hudGui, cs, lang, send, hud.toast) -- профиль и магазин (§11.1)
	local wardrobe = WardrobePanel.new(hudGui, cs, lang, send) -- косметика и флаг (§11.4)
	local arsenalPanel = ArsenalPanel.new(hudGui, cs, lang, send) -- §15л ч.6 (окно переедет в слой окон)
	-- Применить предмет Арсенала: по клетке — следующим нажатием на карту.
	local arsenalTarget = false
	local function useArsenal()
		local p = cs.profile
		local a = if p ~= nil then p.arsenal else nil
		if a == nil or a.loadout == nil or a.used then
			return
		end
		local it = Config.Arsenal.Items[a.loadout]
		if it ~= nil and it.target then
			arsenalTarget = true
			hud.toast(Strings.get("arsenal.pickTarget", lang))
		else
			send("arsenalUse", {})
		end
	end
	local function arsenalTap(cell: number): boolean
		if not arsenalTarget then
			return false
		end
		arsenalTarget = false
		send("arsenalUse", { cell = cell })
		return true
	end
	local questsPanel = QuestsPanel.new(hudGui, cs, lang, hud.toast) -- задания и лидеры (§11.5)
	local tutorial = TutorialPanel.new(hudGui, cs, lang, hud.toast) -- обучение (§5.5)
	local soundPanel = SoundPanel.new(hudGui, cs, lang, send) -- громкости (§13)
	-- §15ц Ц4б: «Как играть» (H) — окно шаблона; «Справочник: <группа>» открывает справочник (создаётся ниже).
	local openHandbookAt: (tab: string) -> () = function(_tab: string) end
	local howTo = HowToPlay.new(hudGui, lang, function(tab: string)
		openHandbookAt(tab)
	end)
	-- Экран лобби (§15и): «Следующий матч», голосование и выбор генерала переезжают в него на время лобби.
	-- §15ф Ф1: «Выйти» из ожидания — держава убирается, главное меню (сервер матча — в хаб).
	local lobby = LobbyScreen.new(hudGui, cs, lang, map.name, send, function()
		if cs.place ~= "match" then
			send("leaveMatch", {})
		end
		openMainMenu()
	end)
	lobby.attach(modePanel.voteFrame, commanderPanel.pickerFrame, modePanel.mapVoteFrame)
	-- Док снизу по центру (§15з): все окна — отсюда; прежние кнопки окон прячутся, их состояние — в подсказке.
	local dock = Dock.new(hudGui, lang, {
		{
			icon = "build",
			name = "dock.build",
			key = "B",
			hidden = true, -- §15ф: стройка — в нижней полосе (1–0)
			button = build.button,
			toggle = build.toggle,
			isOpen = build.isOpen,
		},
		{
			icon = "tech",
			name = "dock.tech",
			hidden = true, -- §15ф Ф2: дока нет — окно в меню игры (≡) и на клавише
			key = "Y",
			button = techPanel.button,
			toggle = techPanel.toggle,
			isOpen = techPanel.isOpen,
		},
		{
			icon = "diplomacy",
			name = "dock.diplomacy",
			hidden = true, -- §15ф Ф2: дока нет — окно в меню игры (≡) и на клавише
			key = "T",
			button = diplomacy.button, -- §15ф: «Дипломатия (T)» над полосой больше не висит
			toggle = diplomacy.toggle,
			isOpen = diplomacy.isOpen,
		},
		{
			icon = "stability",
			name = "dock.stability",
			hidden = true, -- §15ф Ф2: дока нет — окно в меню игры (≡) и на клавише
			key = "N",
			button = stabilityPanel.button,
			toggle = stabilityPanel.toggle,
			isOpen = stabilityPanel.isOpen,
		},
		{
			icon = "ping",
			name = "dock.ping",
			hidden = true, -- §15ф Ф2: дока нет — окно в меню игры (≡) и на клавише
			key = "G",
			button = pings.button,
			toggle = pings.toggle,
			isOpen = pings.isOpen,
		},
		{
			icon = "threat",
			name = "dock.threat",
			hidden = true, -- §15ф Ф2: дока нет — окно в меню игры (≡) и на клавише
			key = "L",
			visible = threat.visible, -- §15х ч.4б
			toggle = threat.toggle,
			isOpen = threat.isOpen,
		},
		{
			icon = "shop",
			name = "dock.shop",
			hidden = true, -- §15ф: окно — в меню игры (≡)
			key = "M",
			button = shopPanel.button,
			toggle = shopPanel.toggle,
			isOpen = shopPanel.isOpen,
		},
		{
			icon = "quests",
			name = "dock.quests",
			hidden = true, -- §15ф: окно — в меню игры (≡)
			key = "J",
			button = questsPanel.button,
			toggle = questsPanel.toggle,
			isOpen = questsPanel.isOpen,
		},
		{
			icon = "wardrobe",
			name = "dock.wardrobe",
			hidden = true, -- §15ф: окно — в меню игры (≡)
			key = "K",
			button = wardrobe.button,
			toggle = wardrobe.toggle,
			isOpen = wardrobe.isOpen,
		},
		{
			icon = "arsenal",
			name = "dock.arsenal",
			hidden = true, -- §15ф: окно — в меню игры (≡)
			key = "U",
			toggle = arsenalPanel.toggle,
			isOpen = arsenalPanel.isOpen,
		},
		{
			icon = "server",
			name = "dock.server",
			hidden = true, -- §15ф: окно — в меню игры (≡)
			key = "O",
			button = serverPanel.button,
			toggle = serverPanel.toggle,
			isOpen = serverPanel.isOpen,
		},
		{
			icon = "sound",
			name = "dock.sound",
			hidden = true, -- §15ф: окно — в меню игры (≡)
			button = soundPanel.button,
			toggle = soundPanel.toggle,
			isOpen = soundPanel.isOpen,
		},
		{
			icon = "help",
			name = "dock.help",
			key = "H",
			toggle = howTo.toggle,
			isOpen = howTo.isOpen,
			hidden = true, -- §15ф: в меню игры
		},
	})
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
	local doomBar = DoomBar.new(hudGui, cs, lang, totalLand) -- «часы судного дня» (§15з)
	local citySet: { [number]: boolean } = {}
	local resultFor: number? = nil -- matchId, за который уже прозвучал итог
	local lastReward: any = nil
	local worldPanel = WorldPanel.new(hudGui, cs, lang, send, function(id: number): string
		local n = cs.nations[id]
		return if n == nil then "?" elseif lang == "en" then n.nameEn else n.name
	end)
	local naval = NavalPanel.new(hudGui, cs, lang, map, provinces, send, hud.percent, shipLayer.pick, shipLayer.select)
	local airPanel = AirPanel.new(hudGui, cs, lang, map, provinces, send, airLayer.pick, airLayer.select)
	commanderPanel.setRaid(airPanel.startRaid) -- §15х ч.4: «Налёт» в панели «УДАРЫ»
	-- Окна снизу по центру (меню стройки, здание, порт, аэродром, «Объявить войну») стоят в одном месте и не
	-- накладываются: открылось новое (нажатием, клавишей, кольцом, доком) — прежние закрываются.
	local sheets: { { busy: () -> boolean, cancel: () -> () } } = {
		{
			busy = build.isOpen,
			cancel = function()
				if build.isOpen() then
					build.toggle()
				end
			end,
		},
		{ busy = buildingInfo.isOpen, cancel = buildingInfo.close },
		{ busy = naval.busy, cancel = naval.cancel },
		{ busy = airPanel.busy, cancel = airPanel.cancel },
		{ busy = wars.declareOpen, cancel = wars.closeDeclare },
		-- §15ц Ц4а: одно окно за раз — и окна механик по центру.
		{
			busy = diplomacy.isOpen,
			cancel = function()
				if diplomacy.isOpen() then
					diplomacy.toggle()
				end
			end,
		},
		{
			busy = techPanel.isOpen,
			cancel = function()
				if techPanel.isOpen() then
					techPanel.toggle()
				end
			end,
		},
		{ busy = council.isOpen, cancel = council.close },
		{ busy = stabilityPanel.isOpen, cancel = stabilityPanel.close },
	}
	anyWindowOpen = function(): boolean
		for _, sheet in sheets do
			if sheet.busy() then
				return true
			end
		end
		return false
	end
	local sheetWas: { boolean } = {}
	Session.connect(RunService.Heartbeat, function()
		for k, sheet in sheets do
			local now = sheet.busy()
			if now and not sheetWas[k] then
				for j, other in sheets do
					if j ~= k and other.busy() then
						other.cancel()
					end
				end
			end
		end
		local anyBusy = false
		for k, sheet in sheets do
			sheetWas[k] = sheet.busy()
			anyBusy = anyBusy or sheetWas[k]
		end
		attackPanel.setBlocked(anyBusy) -- окно снизу по центру — фишки атак не мешают
	end)

	-- §15л: слои над HUD — главное меню (2) и окна (3). Магазин, гардероб, задания, звук, настройки сервера,
	-- «Как играть», «Звания» и меню игры открываются и поверх главного меню, и поверх матча.
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local function layer(name: string, order: number, fullScreen: boolean): ScreenGui
		local g = Instance.new("ScreenGui")
		g.Name = name
		g.ResetOnSpawn = false
		g.DisplayOrder = order
		g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		if fullScreen then
			g.IgnoreGuiInset = true
		else
			g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		end
		Session.track(g)
		g.Parent = playerGui
		UiScale.attach(g)
		Polish.attach(g)
		for _, d in g:GetDescendants() do
			hookButton(d)
		end
		Session.connect(g.DescendantAdded, hookButton)
		return g
	end
	local menuGui = layer("FrontirMenu", 2, true)
	local windowsGui = layer("FrontirWindows", 3, false)
	for _, name in { "Shop", "Wardrobe", "Quests", "Sound", "ServerSettings", "HowToPlay", "ArsenalWindow" } do
		local w = hudGui:FindFirstChild(name)
		if w ~= nil and w:IsA("GuiObject") then
			w.Parent = windowsGui
			if name == "Sound" then
				-- Звук открывается и из меню — по центру, а не у мини-карты.
				w.AnchorPoint = Vector2.new(0.5, 0.5)
				w.Position = UDim2.fromScale(0.5, 0.5)
			end
		end
	end
	local ranksPanel = RanksPanel.new(windowsGui, cs, lang)
	-- §15х ч.5: справочник механик — из окна «Как играть» (окно «Как играть» закрывается, справочник — поверх).
	local handbook = HandbookPanel.new(windowsGui, lang)
	table.insert(sheets, { -- §15ц Ц4а: справочник — тоже «одно окно за раз»
		busy = handbook.isOpen,
		cancel = function()
			if handbook.isOpen() then
				handbook.toggle()
			end
		end,
	})
	table.insert(sheets, { -- «Как играть» — тоже одно окно за раз
		busy = howTo.isOpen,
		cancel = function()
			if howTo.isOpen() then
				howTo.toggle()
			end
		end,
	})
	-- §15ш Ш3: одно окно за раз — и окна из меню (Магазин, Арсенал, Гардероб, Задания, Путь командира, Звук,
	-- настройки сервера). Окно предложения мира — нет: оно приходит само и не закрывает то, где игрок.
	local function sheetOf(isOpen: () -> boolean, toggle: () -> ()): { busy: () -> boolean, cancel: () -> () }
		return {
			busy = isOpen,
			cancel = function()
				if isOpen() then
					toggle()
				end
			end,
		}
	end
	for _, w in
		{
			{ shopPanel.isOpen, shopPanel.toggle },
			{ arsenalPanel.isOpen, arsenalPanel.toggle },
			{ wardrobe.isOpen, wardrobe.toggle },
			{ questsPanel.isOpen, questsPanel.toggle },
			{ ranksPanel.isOpen, ranksPanel.toggle },
			{ soundPanel.isOpen, soundPanel.toggle },
			{ serverPanel.isOpen, serverPanel.toggle },
		} :: { { any } }
	do
		table.insert(sheets, sheetOf(w[1], w[2]))
	end
	openHandbookAt = function(tab: string)
		handbook.open(tab)
	end
	-- Открыть окно (если уже открыто — оставить).
	local function opener(isOpen: () -> boolean, toggle: () -> ()): () -> ()
		return function()
			if not isOpen() then
				toggle()
			end
		end
	end
	local openShop = opener(shopPanel.isOpen, shopPanel.toggle)
	local openSound = opener(soundPanel.isOpen, soundPanel.toggle)
	local openHelp = opener(howTo.isOpen, howTo.toggle)
	local gameMenu: GameMenu.GameMenu? = nil
	local mainMenu = MainMenu.new(menuGui, cs, lang, map.name, {
		shop = openShop,
		wardrobe = opener(wardrobe.isOpen, wardrobe.toggle),
		quests = opener(questsPanel.isOpen, questsPanel.toggle),
		ranks = opener(ranksPanel.isOpen, ranksPanel.toggle),
		arsenal = opener(arsenalPanel.isOpen, arsenalPanel.toggle),
		help = openHelp,
		sound = openSound,
		server = opener(serverPanel.isOpen, serverPanel.toggle),
		serverVisible = function(): boolean
			local info = cs.server
			return info ~= nil and info.isOwner and (cs.phase == "Lobby" or cs.phase == "Waiting")
		end,
		rewardText = function(r: any): string
			return ShopPanel.rewardText(r, lang)
		end,
		timeLeft = function(sec: number): string
			return ShopPanel.daysHours(sec, lang)
		end,
		play = function(serverId: string?, req: MainMenu.Request?)
			-- Хаб (§15л ч.3): переход на сервер матча; «Подключение…» — сразу, сервер подтвердит или откажет.
			-- §15ц Ц2: req — новое лобби пары или «одному» (карта, режим, сила ботов); «как раньше» — без перехода.
			local payload: { [string]: any } = { server = serverId }
			if req ~= nil then
				payload.map, payload.mode, payload.solo, payload.level = req.map, req.mode, req.solo, req.level
			end
			if cs.place == "hub" then
				cs.travel = "going"
				cs.travelReason = nil
				cs.travelAt = os.clock()
			end
			send("play", payload)
		end,
		join = function()
			if cs.place == "combined" and cs.myNation == nil then
				send("joinMatch", {})
			end
		end,
		tutorial = function()
			-- §15ф Ф1: обучение — вступить в матч одному (сервер ставит режим «Обучение»).
			if cs.place == "combined" and cs.myNation == nil then
				send("playTutorial", {})
			end
		end,
		invite = function()
			-- §15л ч.7: окно приглашения Roblox (если игроку можно приглашать).
			task.spawn(function()
				local okCan, can = pcall(function(): boolean
					return SocialService:CanSendGameInviteAsync(player)
				end)
				if okCan and can then
					pcall(function()
						SocialService:PromptGameInvite(player)
					end)
				else
					hud.toast(Strings.get("menu.inviteNo", lang))
				end
			end)
		end,
		privateCreate = function(req: MainMenu.Request?)
			cs.travel = "going"
			cs.travelReason = nil
			cs.travelAt = os.clock()
			send("privateCreate", if req ~= nil then { map = req.map, mode = req.mode } else {})
		end,
		privateJoin = function(code: string)
			cs.travel = "going"
			cs.travelReason = nil
			cs.travelAt = os.clock()
			send("privateJoin", { code = code })
		end,
		onOpenChanged = function(open: boolean)
			menuWasOpen = open
			-- Под меню интерфейс матча скрыт целиком (карта видна через затемнение).
			hudGui.Enabled = not open
			if gameMenu ~= nil then
				gameMenu.close()
			end
		end,
	})
	-- Сервер матча (§15л ч.3): главное меню — в хабе, переход туда; иначе — меню поверх матча.
	local function toMainMenu()
		if cs.place == "match" then
			cs.travel = "going"
			cs.travelAt = os.clock()
			hud.toast(Strings.get("menu.toHub", lang))
			send("toHub", {})
		else
			mainMenu.open()
		end
	end
	openMainMenu = toMainMenu -- «В меню» на экране итогов
	local menuExtra: { GameMenu.MenuItem } = {
		-- §15ц Ц3: пауза и ×2 «одному» — здесь и клавишей P (плашка «ПАУЗА» — сверху по центру).
		{
			label = Strings.get("solo.pause", lang),
			text = modePanel.pauseText,
			action = modePanel.togglePause,
			visible = modePanel.soloOn,
		},
		{
			label = Strings.get("solo.fast", lang),
			text = modePanel.fastText,
			action = modePanel.toggleFast,
			visible = modePanel.soloOn,
		},
		{
			label = Strings.get("dock.diplomacy", lang) .. "  [T]",
			action = diplomacy.toggle,
			visible = function(): boolean
				return diplomacy.button.Visible
			end,
		},
		{
			label = Strings.get("dock.tech", lang) .. "  [Y]",
			action = techPanel.toggle,
			visible = function(): boolean
				return techPanel.button.Visible
			end,
		},
		{
			label = Strings.get("dock.stability", lang) .. "  [N]",
			action = stabilityPanel.toggle,
			visible = function(): boolean
				return stabilityPanel.button.Visible
			end,
		},
		{
			label = Strings.get("council.title", lang) .. "  [F]", -- §15ц Ц4а: окно Совета
			action = council.toggle,
			visible = function(): boolean
				return stabilityPanel.button.Visible -- то же условие: идёт игра и держава жива
			end,
		},
		{
			label = Strings.get("dock.threat", lang) .. "  [L]",
			action = threat.toggle,
			visible = threat.visible,
		},
		{
			label = Strings.get("dock.ping", lang) .. "  [G]",
			action = pings.toggle,
			visible = function(): boolean
				return pings.button.Visible
			end,
		},
		{ label = Strings.get("dock.quests", lang) .. "  [J]", action = questsPanel.toggle },
		{ label = Strings.get("dock.wardrobe", lang) .. "  [K]", action = wardrobe.toggle },
		{ label = Strings.get("dock.arsenal", lang) .. "  [U]", action = arsenalPanel.toggle },
		{ label = Strings.get("menu.nav.ranks", lang), action = ranksPanel.toggle },
		{
			label = Strings.get("dock.server", lang) .. "  [O]",
			action = serverPanel.toggle,
			visible = function(): boolean
				return serverPanel.button.Visible
			end,
		},
	}
	gameMenu = GameMenu.new(hudGui, windowsGui, cs, lang, map.name, {
		help = openHelp,
		sound = openSound,
		shop = openShop,
		mainMenu = toMainMenu,
		blocked = mainMenu.isOpen,
		-- §15ф: окна из прежнего дока (§15ф Ф2: док убран совсем — здесь и дела матча).
		extra = menuExtra,
	})
	-- §15л ч.2: командная полоса снизу по центру. Прежние полоса ресурсов и карточки найма — в выключенный
	-- ScreenGui (их код работает как раньше, но на экране их нет: всё это — в полосе).
	local stash = Instance.new("ScreenGui")
	stash.Name = "FrontirStash"
	stash.Enabled = false
	stash.ResetOnSpawn = false
	Session.track(stash)
	stash.Parent = playerGui
	-- §15ф: панель державы (имя, «атакует») — тоже: имя и доля мира — в нижней полосе.
	-- §15ц Ц3: и панель «Войска» справа — состав войск теперь в группе ВОЙСКА полосы (подсказка заголовка).
	for _, name in { "ResourceBar", "HireCards", "NationPanel", "Forces" } do
		local g = hudGui:FindFirstChild(name)
		if g ~= nil then
			g.Parent = stash
		end
	end
	-- §15л ч.8: картинки-шапки окон (сцены SceneArt над окном, следуют за ним).
	local banners: { [string]: SceneBanner.Banner } = {}
	for name, key in
		{
			Shop = "shop",
			Wardrobe = "wardrobe",
			Quests = "quests",
			Sound = "sound",
			ServerSettings = "server",
			HowToPlay = "help",
			Handbook = "help",
			ArsenalWindow = "arsenal",
			RanksWindow = "ranks",
			GameMenuWindow = "gamemenu",
			Tech = "tech",
			Diplomacy = "diplomacy",
			Council = "council",
			StabilityWindow = "stability", -- §15ц Ц4а
			Results = "victory",
		} :: { [string]: string }
	do
		local w = windowsGui:FindFirstChild(name) or hudGui:FindFirstChild(name)
		if w ~= nil and w:IsA("GuiObject") then
			local b = SceneBanner.attach(w, key)
			if b ~= nil then
				banners[name] = b
			end
		end
	end
	local commandBar = CommandBar.new(hudGui, cs, lang, {
		values = hud.values,
		percent = hud.percent,
		setPercent = hud.setPercent,
		hire = forcesPanel.hire,
		hireInfo = forcesPanel.hireInfo,
		army = forcesPanel.army,
		armyTip = forcesPanel.summary,
		build = build,
		buildIcon = BuildPanel.icon,
		shop = openShop,
		arsenal = {
			info = function(): (string?, boolean)
				local p = cs.profile
				local a = if p ~= nil then p.arsenal else nil
				if a == nil or not cs.rules.boosts then
					return nil, false
				end
				return a.loadout, a.used
			end,
			use = useArsenal,
			icons = ArsenalPanel.Icons,
		},
	})
	-- Меню фраз меток (G) лежало внутри кнопки, которую док прячет, — переносим в HUD (меню стройки — так же,
	-- в BuildPanel).
	local phrases = pings.button:FindFirstChild("Phrases")
	if phrases ~= nil and phrases:IsA("GuiObject") then
		phrases.AnchorPoint = Vector2.new(0.5, 1)
		phrases.Parent = hudGui
	end
	-- §15ц Ц3: над мини-картой — подписанные кнопки окон, слева от неё — «+» и «−».
	local mapButtons = MapButtons.new(hudGui, lang, {
		{
			icon = "diplomacy",
			name = "dock.diplomacy",
			key = "T",
			toggle = diplomacy.toggle,
			isOpen = diplomacy.isOpen,
			visible = function(): boolean
				return diplomacy.button.Visible
			end,
		},
		{
			icon = "tech",
			name = "dock.tech",
			key = "Y",
			toggle = techPanel.toggle,
			isOpen = techPanel.isOpen,
			visible = function(): boolean
				return techPanel.button.Visible
			end,
		},
		{
			icon = "stability",
			name = "dock.stability",
			key = "N",
			toggle = stabilityPanel.toggle,
			isOpen = stabilityPanel.isOpen,
			visible = function(): boolean
				return stabilityPanel.button.Visible
			end,
		},
		{ -- §15ш Ш3: Совет — на виду, как остальные окна механик
			icon = "council",
			name = "council.title",
			key = "F",
			toggle = council.toggle,
			isOpen = council.isOpen,
			visible = function(): boolean
				return stabilityPanel.button.Visible -- то же условие, что в меню игры: идёт игра, держава жива
			end,
		},
		{
			icon = "server",
			name = "mapbtn.menu",
			key = "Tab",
			toggle = (gameMenu :: GameMenu.GameMenu).toggle,
			isOpen = (gameMenu :: GameMenu.GameMenu).isOpen,
		},
	}, function(dir: number)
		local s = camera.state
		camera.zoomTo(CameraMath.wheelTarget(s, camera.targetZoom(), dir), s.viewW / 2, s.viewH / 2)
	end)
	-- Над полосой: слева атаки и лента, справа мини-карта, по центру окна стройки, меток, здания, порта,
	-- аэродрома, «Объявить войну». Полоса скрыта (лобби, выбор, итоги) — всё на прежней высоте от края.
	local function aboveBar()
		local bar = commandBar.frame
		local off = if bar.Visible
			then UiScale.units(bar.AbsoluteSize.Y) + Config.Render.CommandBar.BottomPx + 10
			else 12
		local function at(name: string, anchor: Vector2, x: UDim, extra: number)
			local g = hudGui:FindFirstChild(name)
			if g ~= nil and g:IsA("GuiObject") then
				g.AnchorPoint = anchor
				g.Position = UDim2.new(x, UDim.new(1, -(off + extra)))
			end
		end
		at("AttackArea", Vector2.new(0, 1), UDim.new(0, 12), 0)
		at("AttackChips", Vector2.new(0.5, 1), UDim.new(0.5, 0), 0) -- §15ф Ф2: фишки своих атак
		at("Minimap", Vector2.new(1, 1), UDim.new(1, -12), 0)
		at("BuildMenu", Vector2.new(0.5, 1), UDim.new(0.5, 0), 0)
		at("Phrases", Vector2.new(0.5, 1), UDim.new(0.5, 0), 0)
		at("BuildingInfoPanel", Vector2.new(0.5, 1), UDim.new(0.5, 0), 0)
		at("AirPanel", Vector2.new(0.5, 1), UDim.new(0.5, 0), 0)
		at("NavalPanel", Vector2.new(0.5, 1), UDim.new(0.5, 0), 0)
		at("DeclareWar", Vector2.new(0.5, 1), UDim.new(0.5, 0), 0)
		local mapH = if minimap ~= nil then minimap.height else 0
		local mapFrame = hudGui:FindFirstChild("Minimap")
		local mapW = if mapFrame ~= nil and mapFrame:IsA("GuiObject")
			then mapFrame.Size.X.Offset
			else Config.Render.MapButtons.WidthPx
		local buttonsAt = if mapH > 0 then mapH + 8 else 0
		at("MapButtons", Vector2.new(1, 1), UDim.new(1, -12), buttonsAt)
		at("ZoomButtons", Vector2.new(1, 1), UDim.new(1, -(12 + mapW + 8)), 0)
		at("HomeButton", Vector2.new(1, 1), UDim.new(1, -12), buttonsAt + mapButtons.height() + 8)
	end
	-- §15ц Ц5в: узкий экран (телефон; в Studio — Dev.PhoneLayout) — «АТАКИ» свёрнуты, кнопки у мини-карты значками.
	-- Только при смене раскладки: свернуть или развернуть «АТАКИ» вручную игрок может и потом.
	local wasNarrow: boolean? = nil
	local function applyNarrow()
		local narrow = PhoneLayout.narrow(UiScale.size(hudGui).X, RunService:IsStudio() and Config.Dev.PhoneLayout)
		if narrow ~= wasNarrow then
			wasNarrow = narrow
			attackPanel.setCollapsed(narrow)
			mapButtons.setCompact(narrow)
			aboveBar()
		end
	end
	UiScale.onResize(hudGui, applyNarrow)
	applyNarrow()
	Session.connect(RunService.Heartbeat, function()
		local playing = commandBar.visible()
		mapButtons.frame.Visible = playing
		mapButtons.zoom.Visible = playing
		if playing then
			local h = mapButtons.height()
			mapButtons.update()
			if mapButtons.height() ~= h then
				aboveBar()
			end
		end
	end)
	-- §15ц Ц5б: карточка «Обучения» стоит слева сама (UI/TutorialPanel) — дока больше нет.
	Session.connect(commandBar.frame:GetPropertyChangedSignal("AbsoluteSize"), aboveBar)
	Session.connect(commandBar.frame:GetPropertyChangedSignal("Visible"), aboveBar)
	aboveBar()
	-- Меню открываем с первым info (роль сервера — в нём); до него интерфейс матча не показываем.
	local menuPending = true
	if menuWasOpen then
		hudGui.Enabled = false
	end
	local function decideMenu()
		if not menuPending then
			return
		end
		menuPending = false
		if not placeSeen then
			placeSeen = true
			if cs.place == "match" then
				menuWasOpen = false
			end
		end
		if menuWasOpen or cs.place == "hub" then
			mainMenu.open()
		else
			hudGui.Enabled = true
		end
	end

	-- §15л: без наложений — всё, что появляется сверху по центру, идёт одним столбиком; справа сверху — тоже.
	local function column(name: string, anchorX: number, x: UDim, align: Enum.HorizontalAlignment): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.AnchorPoint = Vector2.new(anchorX, 0)
		f.Position = UDim2.new(x, UDim.new(0, 8))
		f.Size = UDim2.fromOffset(0, 0)
		f.AutomaticSize = Enum.AutomaticSize.XY
		f.Parent = hudGui
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.HorizontalAlignment = align
		list.Padding = UDim.new(0, 6)
		list.Parent = f
		return f
	end
	local function stackInto(target: Frame, names: { string })
		for order, name in names do
			local g = hudGui:FindFirstChild(name)
			if g ~= nil and g:IsA("GuiObject") then
				g.AnchorPoint = Vector2.new(0, 0)
				g.LayoutOrder = order
				g.Parent = target
			end
		end
	end
	stackInto(column("TopCenter", 0.5, UDim.new(0.5, 0), Enum.HorizontalAlignment.Center), {
		"Alarm", -- §15ш Ш2: тревога — первой
		"PhaseBanner",
		"Solo", -- §15ц Ц3: плашка «ПАУЗА · P — продолжить» (пауза и ×2 — в меню игры)
		"Siren",
		"ThreatLegend", -- §15х ч.4б
		"DoomBar",
		"PrivateServer",
		"WarStatus",
		"Resolutions",
		"WorldBanner",
	})
	-- §15ш Ш2: сверху по центру — меньше карточек: подсказка «что делать дальше» — внизу слева, над лентой.
	do
		local area = hudGui:FindFirstChild("AttackArea")
		local hintFrame = hudGui:FindFirstChild("HintPanel")
		if area ~= nil and hintFrame ~= nil and hintFrame:IsA("GuiObject") then
			hintFrame.LayoutOrder = 0 -- лента — 1, ползунок — 100
			hintFrame.Parent = area
		end
	end
	stackInto(
		column("TopRight", 1, UDim.new(1, -12), Enum.HorizontalAlignment.Right),
		{ "PlaceChip", "GiantChip", "Attacks", "Leaders", "Auction" }
	)
	-- HUD рисуется в режиме Global: содержимое окон с поднятым ZIndex — выше их фона (иначе текст под фоном).
	Layering.liftAll(hudGui)
	-- Панель разработчика (F4) — только в Studio; создаётся в фоне (ждёт канал Remotes.Dev от сервера).
	local devPanel: DevPanel.DevPanel? = nil
	task.spawn(function()
		devPanel = DevPanel.new(hudGui, cs, lang, SelfCheck.start)
		local panel = hudGui:FindFirstChild("DevPanel")
		if panel ~= nil and panel:IsA("GuiObject") then
			Layering.lift(panel)
		end
	end)
	-- Самопроверка (Studio, F4): окна этой сессии; модуль живёт над сессиями (смена карты).
	SelfCheck.attach({
		cs = cs,
		mapId = mapId,
		windows = {
			{
				name = "дипломатия",
				toggle = diplomacy.toggle,
				isOpen = diplomacy.isOpen,
				frame = "Diplomacy",
			},
			{ name = "технологии", toggle = techPanel.toggle, isOpen = techPanel.isOpen, frame = "Tech" },
			-- §15ц Ц4–Ц5: новые окна механик и «влезает в экран».
			{ name = "Совет держав", toggle = council.toggle, isOpen = council.isOpen, frame = "Council" },
			{
				name = "стабильность",
				toggle = stabilityPanel.toggle,
				isOpen = stabilityPanel.isOpen,
				frame = "StabilityWindow",
			},
			{ name = "как играть", toggle = howTo.toggle, isOpen = howTo.isOpen, frame = "HowToPlay" },
			{ name = "справочник", toggle = handbook.toggle, isOpen = handbook.isOpen, frame = "Handbook" },
			{ name = "магазин", toggle = shopPanel.toggle, isOpen = shopPanel.isOpen, frame = "Shop" },
			{ name = "гардероб", toggle = wardrobe.toggle, isOpen = wardrobe.isOpen, frame = "Wardrobe" },
			{ name = "задания", toggle = questsPanel.toggle, isOpen = questsPanel.isOpen, frame = "Quests" },
			{ name = "звания", toggle = ranksPanel.toggle, isOpen = ranksPanel.isOpen, frame = "RanksWindow" },
			{
				name = "арсенал",
				toggle = arsenalPanel.toggle,
				isOpen = arsenalPanel.isOpen,
				frame = "ArsenalWindow",
			},
			{
				name = "главное меню",
				toggle = function()
					if mainMenu.isOpen() then
						mainMenu.close()
					else
						mainMenu.open()
					end
				end,
				isOpen = mainMenu.isOpen,
			},
			{
				name = "меню игры",
				toggle = (gameMenu :: GameMenu.GameMenu).toggle,
				isOpen = (gameMenu :: GameMenu.GameMenu).isOpen,
			},
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
		hud = hudGui,
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
			arsenalPanel.refresh()
			questsPanel.refresh()
			commanderPanel.refresh()
		end,
		onInfo = function(colorsChanged: boolean)
			decideMenu()
			-- Звук (§13): города — для «Province»; итог матча — победа или поражение один раз.
			table.clear(citySet)
			for _, c in cs.cities do
				citySet[c] = true
			end
			local result = cs.result
			if cs.phase == "Over" and result ~= nil and resultFor ~= cs.matchId then
				resultFor = cs.matchId
				local name = AudioCues.result(result.winner, result.coWinners, cs.myNation)
				if name ~= nil and cs.place ~= "hub" and not cs.demo then
					Audio.play(name)
				end
			end
			-- §15л ч.8: шапка итогов — салют за победу, дым над развалинами за поражение.
			local rb = banners.Results
			if rb ~= nil and cs.phase == "Over" and result ~= nil then
				local me = cs.myNation
				local won = me ~= nil
					and (result.winner == me or (result.coWinners ~= nil and table.find(result.coWinners, me) ~= nil))
				rb.setKey(if won then "victory" else "defeat")
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
			battleFx.onSnapshot()
		end,
		onDelta = function(cells: { number })
			warFx.onDelta(cells) -- вспышки захвата (§15б)
			battleFx.onDelta(cells) -- кольца захвата городов (§15м)
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
		onRails = function(msg: any)
			-- §15ч Ч1: рельсы рисуются в картинке территории; мост — клетка реки.
			local river = Types.Terrain.River
			local changed = ClientState.applyRails(cs, msg, function(cell: number): boolean
				return MapDataModule.getTerrain(map, cell) == river
			end)
			territory.railsChanged(changed)
			railLayer.railsChanged() -- §15ч Ч2: линии вдали
			railLayer.onRails(msg) -- со снимком — поезда в пути
		end,
		onBuildings = function()
			buildingLayer.refresh()
			build.onBuildings() -- эффект постройки (§15г)
			cityLabels.refresh() -- уровни городов
			labels.refresh() -- город растёт на карте (§15д ч.4)
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
			hints.onEvents(events)
			wars.onEvents(events)
			pings.onEvents(events)
			airLayer.onEvents(events) -- вспышки бомб и сбитые самолёты
			markerLayer.onEvents(events) -- круг ракеты сразу при пуске
			warFx.onEvents(events) -- баннер войны, искры границы (§15б)
			battleFx.onEvents(events) -- выбывание, тряска (§15м)
			strikeFx.onEvents(events) -- удары и разрушения (§15х ч.7)
			spectacle.onEvents(events) -- гибель кораблей, салют победы (§15х ч.9)
			worldPanel.onEvents(events) -- баннер события
			tutorial.onEvents(events) -- шаги обучения (§5.5)
			railLayer.onEvents(events) -- §15ч Ч2: поезда отправились и доехали
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
		aboveBar() -- §15л ч.2: над мини-картой, которая стоит над командной полосой
		Session.connect(home.Activated, goHome)
	end

	-- Кольцо действий (§15е): ПКМ или долгое касание — «что можно сделать здесь».
	-- Последняя точка кольца: «Эмодзи» открывает второе кольцо там же.
	local ringAt: { x: number, y: number, reopen: boolean, pick: ((index: number) -> ())? } =
		{ x = 0, y = 0, reopen = false, pick = nil }
	-- §15х ч.4: удар из кольца — готов: сразу по клетке; не готов — подсказка «что сделать».
	local function strikeAt(kind: StrikeMenu.Kind, cell: number)
		local f = StrikeStatus.facts(cs, cell, os.clock())
		local why = StrikeMenu.check(kind, f)
		if why ~= "ok" then
			hud.toast(StrikeStatus.how(kind, why, f, lang))
			return
		end
		if kind == "missile" then
			send("missile", { cell = cell, warhead = "missile" })
		elseif kind == "raid" then
			send("raid", { cell = cell })
		else
			send("ability", { slot = StrikeStatus.abilitySlot(cs), cell = cell, percent = hud.percent() })
		end
	end
	local ring
	ring = ActionRingUI.new(hudGui, viewport, lang, function(action, cell: number, owner: number)
		if action == "missile" or action == "raid" or action == "ability" then
			strikeAt(action :: any, cell)
		elseif action == "expand" or action == "attack" then
			hud.tapCell(cell)
		elseif action == "declare" then
			wars.offerDeclare(owner)
		elseif action == "alliance" or action == "trade" then
			send("offer", { target = owner, offer = action })
		elseif action == "intel" then
			send("intel", { target = owner })
		elseif action == "target" or action == "mark" then
			send("ping", { cell = cell, phrase = "attack" })
		elseif action == "help" then
			send("ping", { cell = cell, phrase = "help" })
		elseif action == "build" then
			build.open()
		elseif action == "emoji" then
			-- Второе кольцо: 8 эмодзи (§15ж); державу берём по клетке (своя — своя столица).
			local target = if owner ~= 0 then owner else cs.myNation
			if target ~= nil then
				ringAt.pick = function(index: number)
					send("emoji", { target = target, emoji = index })
				end
				ringAt.reopen = true
			end
		end
	end)
	-- Второе кольцо открывается после того, как первое закрылось (нажатие уже обработано).
	Session.connect(RunService.Heartbeat, function()
		local pick = ringAt.pick
		if ringAt.reopen and pick ~= nil then
			ringAt.reopen = false
			ring.choose(ringAt.x, ringAt.y, table.clone(Config.Emoji.List) :: { string }, pick)
		end
	end)
	local function openRing(sx: number, sy: number)
		ringAt.x, ringAt.y = sx, sy
		local cx, cy = CameraMath.cellAt(camera.state, sx, sy)
		local me = cs.myNation
		if cx == nil or cy == nil or me == nil then
			return
		end
		local cell = cy * map.width + cx
		local owner = ClientState.ownerAt(cs, cell)
		local war = if owner ~= 0 and owner ~= me then ClientState.warBetween(cs, me, owner) else nil
		-- §15х ч.4: у ударов — готовность и чего не хватает прямо на кнопке.
		local function decorate(action: string): (string?, boolean, string?, Color3?)
			if action ~= "missile" and action ~= "raid" and action ~= "ability" then
				return nil, true, nil, nil
			end
			local kind: StrikeMenu.Kind = action :: any
			local f = StrikeStatus.facts(cs, cell, os.clock())
			local why = StrikeMenu.check(kind, f)
			local ability = f.ability
			local name = if kind == "ability" and ability ~= nil
				then Strings.get("ability." .. ability, lang)
				else Strings.get("ring." .. kind, lang)
			-- §15х ч.5: картинка удара и цвет рамки (ракета — красный, налёт — оранжевый, генерал — золотой).
			local art = if kind == "ability" and ability ~= nil then "strike." .. ability else "strike." .. kind
			local accent = if kind == "missile"
				then Theme.Colors.Alert
				elseif kind == "raid" then Theme.color("Orange")
				else Theme.Colors.Gold
			if why == "ok" then
				return name, true, art, accent
			end
			return name .. "\n" .. StrikeStatus.short(kind, why, f, lang), false, art, accent
		end
		ring.open(sx, sy, cell, {
			playing = cs.phase == "Play" and cs.nations[me] ~= nil and cs.nations[me].alive,
			me = me,
			owner = owner,
			land = MapDataModule.getTerrain(map, cell) ~= 0, -- 0 — вода (Types.Terrain.Water)
			war = if war == nil then "none" elseif war.active then "active" else "mobilizing",
			allied = table.find(ClientState.alliesOf(cs, me), owner) ~= nil,
			trade = owner ~= 0 and ClientState.hasTrade(cs, me, owner),
			ability = StrikeStatus.abilitySlot(cs) ~= nil,
		}, decorate :: any)
	end

	-- §15ш Ш3: подсказка по касанию (телефон) — задаётся ниже, когда готова подсказка над картой.
	local touchPoint: (x: number, y: number, down: boolean) -> () = function() end
	local touchPointEnd: () -> () = function() end
	local input = CameraInput.bind(camera, viewport, {
		onContext = openRing,
		onPoint = function(x: number, y: number, down: boolean)
			touchPoint(x, y, down)
		end,
		onPointEnd = function()
			touchPointEnd()
		end,
		onTap = function(sx: number, sy: number)
			local cx, cy = CameraMath.cellAt(camera.state, sx, sy)
			if cx ~= nil and cy ~= nil then
				local cell = cy * map.width + cx
				-- Режим стройки забирает нажатие; иначе — старт, атака, война.
				local handled = arsenalTap(cell) -- цель Арсенала (§15л ч.6)
					or shopPanel.tap(cell) -- цель «Авиаудара» (§11.3)
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
	-- §15к: подсказка при наведении на карту (владелец, местность, провинция, что будет по клику).
	local tooltip = MapTooltip.new(hudGui, cs, lang, map, provinces)
	local aimCell: number? = nil -- клетка под курсором (для кругов защиты при прицеливании)
	-- §15х: чем целимся сейчас — ракета / бомба (R) или налёт (аэродром); подсказка и круги защиты у курсора.
	tooltip.setAiming(function(): any
		return commanderPanel.aiming() or (if airPanel.aiming() then "raid" else nil)
	end)
	-- Подсказка, подсветка державы и «призрак» стройки у точки экрана: курсор мыши или палец (§15ш Ш3).
	local function pointAt(p: Vector3)
		local inset = viewport.AbsolutePosition
		local cx, cy = CameraMath.cellAt(camera.state, p.X - inset.X, p.Y - inset.Y)
		local cell = if cx ~= nil and cy ~= nil then cy * map.width + cx else nil
		if build.active() then
			tooltip.show(nil, 0, 0, 0)
			highlight.setHover(nil)
			build.hover(cell)
			return
		end
		-- Не в игре или над окном интерфейса (док, панели, лобби) — без подсказки.
		if cs.phase ~= "Play" and cs.phase ~= "Pick" then
			cell = nil
		else
			-- Считаем окном только непрозрачную рамку или кнопку не во весь экран (виньетка войны — не окно).
			local screen = hudGui.AbsoluteSize
			for _, g in playerGui:GetGuiObjectsAtPosition(p.X, p.Y) do
				if
					(g:IsDescendantOf(hudGui) or g:IsDescendantOf(windowsGui) or g:IsDescendantOf(menuGui))
					and not g:IsDescendantOf(view.canvas)
					and g.Name ~= "MapTooltip"
					and (g.BackgroundTransparency < 0.99 or g:IsA("GuiButton"))
					and (g.AbsoluteSize.X < screen.X * 0.9 or g.AbsoluteSize.Y < screen.Y * 0.9)
				then
					cell = nil
					break
				end
			end
		end
		-- §15ц: подсказка живёт в слое с масштабом экрана — место курсора в условных пикселях.
		tooltip.show(cell, UiScale.units(p.X), UiScale.units(p.Y), hud.percent())
		highlight.setHover(if cell ~= nil then ClientState.ownerAt(cs, cell) else nil)
		aimCell = cell
	end
	Session.connect(UserInputService.InputChanged, function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.MouseMovement then
			pointAt(io.Position)
		end
	end)
	-- §15ш Ш3: палец лежит — подсказка; отпустили — держится Render.TouchTipSec; повели камеру — уходит.
	local touchTipUntil: number? = nil
	touchPoint = function(x: number, y: number, down: boolean)
		pointAt(Vector3.new(x, y, 0))
		touchTipUntil = if down then math.huge else os.clock() + Config.Render.TouchTipSec
	end
	touchPointEnd = function()
		if touchTipUntil == nil then
			return
		end
		touchTipUntil = nil
		tooltip.show(nil, 0, 0, 0)
		highlight.setHover(nil)
		if build.active() then
			build.hover(nil)
		end
		aimCell = nil
	end

	local musicAt = 0
	local travelToastAt = -1
	-- §15л ч.5 Хаб: камера сама облетает показательный матч — от войны к войне (нет войн — крупные державы).
	local tourAt, tourPick, tourLast = 0, 0, os.clock()
	local tourX: number?, tourY: number? = nil, nil
	local function cellXY(cell: number): (number, number)
		return cell % map.width + 0.5, cell // map.width + 0.5
	end
	local function tourTarget(): (number?, number?)
		local spots: { { number } } = {}
		for _, w in cs.wars.wars do
			local a, b = cs.nations[w.a], cs.nations[w.b]
			if w.active and a ~= nil and b ~= nil and a.capital ~= nil and b.capital ~= nil then
				local ax, ay = cellXY(a.capital)
				local bx, by = cellXY(b.capital)
				table.insert(spots, { (ax + bx) / 2, (ay + by) / 2 })
			end
		end
		if #spots == 0 then
			local list: { { id: number, cells: number } } = {}
			for id, n in cs.nations do
				local st = ClientState.statsOf(cs, id)
				if n.alive and n.capital ~= nil and st ~= nil then
					table.insert(list, { id = id, cells = st.cells })
				end
			end
			table.sort(list, function(p: { id: number, cells: number }, q: { id: number, cells: number }): boolean
				return p.cells > q.cells
			end)
			for k = 1, math.min(5, #list) do
				local capital = cs.nations[list[k].id].capital :: number
				local x, y = cellXY(capital)
				table.insert(spots, { x, y })
			end
		end
		if #spots == 0 then
			return nil, nil
		end
		tourPick += 1
		local spot = spots[(tourPick - 1) % #spots + 1]
		return spot[1], spot[2]
	end
	local function tour(now: number)
		local dt = math.min(0.1, now - tourLast)
		tourLast = now
		-- §15ф: облёт — в хабе, за показом и под главным меню (карта на весь экран, а не маленькая посередине).
		local menuOpen = mainMenu.isOpen()
		if
			(cs.place ~= "hub" and not cs.demo and not menuOpen)
			or (cs.phase ~= "Play" and cs.phase ~= "Over" and not menuOpen)
		then
			return
		end
		local s = camera.state
		if now >= tourAt then
			tourAt = now + Config.Hub.TourSec
			tourX, tourY = tourTarget()
			-- Не мельче «карта закрывает экран» (по большей стороне), с запасом TourZoom от «вся карта».
			local cover = math.max(s.viewW / s.mapW, s.viewH / s.mapH)
			s.zoom = CameraMath.snapZoom(s, math.max(CameraMath.minZoom(s) * Config.Hub.TourZoom, cover * 1.15))
			if tourX == nil then
				tourX, tourY = s.mapW / 2, s.mapH / 2 -- держав ещё нет — середина карты
			end
		end
		local tx, ty = tourX, tourY
		if tx == nil or ty == nil then
			return
		end
		local cx = s.x + s.viewW / s.zoom / 2
		local cy = s.y + s.viewH / s.zoom / 2
		local k = math.min(1, dt * Config.Hub.TourEase)
		CameraMath.centerOn(s, cx + (tx - cx) * k, cy + (ty - cy) * k)
		camera.refresh()
	end
	local cloudsAt = os.clock()
	local railAt = os.clock() -- §15ч Ч2: поезда едут по игровому времени между кадрами
	local frameConn = Session.connect(RunService.RenderStepped, function()
		local now = os.clock()
		tour(now)
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
		railLayer.update(now, math.clamp(now - railAt, 0, 0.25), camera.state) -- §15ч Ч2: дороги вдали и поезда
		railAt = now
		tooltip.tick(hud.percent()) -- §15ш Ш1: числа в подсказке живые и без движения мыши
		if touchTipUntil ~= nil and os.clock() > touchTipUntil then
			touchPointEnd() -- §15ш Ш3: подсказка по касанию отслужила
		end
		-- §15х: целимся — круги защиты врага, которые накрывают клетку под курсором.
		local ac = aimCell
		if ac ~= nil then
			local f = tooltip.forecast(ac)
			if f ~= nil then
				markerLayer.defenses(f.covers)
			else
				-- §15х ч.2: не целимся — круг действия здания (или снабжения города) под курсором.
				local r, color = tooltip.rangeAt(ac)
				if r ~= nil and color ~= nil then
					markerLayer.range(ac, r, color)
				end
			end
		end
		threat.update(now) -- §15х ч.4б: круги угроз — до кадра маркеров
		markerLayer.update(now, camera.state)
		siren.update(now)
		alarm.update(now)
		warFx.update(now, camera.state)
		battleFx.update(now, camera.state)
		strikeFx.update(now, camera.state)
		highlight.update(now, camera.state)
		spectacle.update(now, camera.state)
		doomBar.update(now)
		dock.update(now)
		lobby.update(now)
		mainMenu.update(now)
		-- Переход в хаб не удался (§15л ч.3) — сказать один раз.
		if cs.travel == "failed" and cs.place ~= "hub" and travelToastAt ~= cs.travelAt then
			travelToastAt = cs.travelAt
			hud.toast(Strings.get("menu.travelFailed", lang))
		end
		commandBar.update(now)
		worldPanel.update(now)
		hud.update(now)
		attackPanel.update(now)
		hints.update(now)
		commanderPanel.update(now)
		wars.update(now)
		results.update(now)
		diplomacy.update(now)
		council.update(now)
		tutorial.update(now) -- §15ц Ц5б: подсветка места текущего шага
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
