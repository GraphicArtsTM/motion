--!strict
--[[
	MainMenu — главное меню (§15ц Ц2 «матчи как серверы»). Карта — на весь экран (за меню идёт показательный бой
	ботов или матч сервера), по центру — карточка «ИГРАТЬ», по краям — профиль, задания, предложение, внизу — плитки.

	Центр (сверху вниз):
	- логотип и строка «что за игра»;
	- «В БОЙ» — быстрый вход (лучший открытый матч или новое лобби первой пары плейлиста);
	- «МАТЧИ» — строки как серверы Roblox: миниатюра карты, карта, режим, игроки, «старт через» / «идёт» и кнопка
	  (Войти, В команду, Смотреть, Полон, Занят). Строки строит сервер (Lobbies.board): в хабе — серверы матча,
	  «как раньше» (Studio) — свой сервер и пары плейлиста;
	- «Играть одному», «Свой матч» (окно выбора карты и режима — MatchSetup), «Обучение» (пока не пройдено).
	Слева — профиль (знак ступени, имя, уровень, опыт, медали) и задания дня; справа — предложение недели;
	внизу — плитки: Арсенал, Магазин, Гардероб, Путь командира, Как играть, Пригласить, Звук (у владельца
	частного сервера — ещё «Сервер»). Узкий экран — боковые колонки прячутся; низкий — центр ужимается.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local MapThumbs = require(Shared:WaitForChild("MapThumbs"))
local Ranks = require(Shared:WaitForChild("Ranks"))
local Strings = require(Shared:WaitForChild("Strings"))

local Logo = require(script.Parent:WaitForChild("Logo"))
local MapThumb = require(script.Parent:WaitForChild("MapThumb"))
local MatchSetup = require(script.Parent:WaitForChild("MatchSetup"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

-- Что выбрали в строке плейлиста или в окне «одному» / «свой матч».
export type Request = { map: string, mode: string, solo: boolean?, level: string? }

export type Actions = {
	shop: () -> (),
	wardrobe: () -> (),
	quests: () -> (),
	ranks: () -> (),
	arsenal: () -> (), -- §15л ч.6
	help: () -> (),
	sound: () -> (),
	server: () -> (),
	serverVisible: () -> boolean, -- «Сервер» — только владельцу частного сервера в лобби
	rewardText: (reward: any) -> string, -- что в наборе (как в магазине)
	timeLeft: (sec: number) -> string, -- «N дн. N ч»
	onOpenChanged: (open: boolean) -> (),
	-- §15ц Ц2: войти на сервер (serverId), в новое лобби пары / «одному» (req) или быстрый вход (оба nil).
	play: (serverId: string?, req: Request?) -> (),
	join: () -> (), -- §15л ч.7: «как раньше» — вступить в матч сервера
	invite: () -> (), -- §15л ч.7: пригласить друзей (окно Roblox)
	privateCreate: (req: Request?) -> (), -- §15л ч.4: свой матч — новый сервер для друзей (карта и режим — §15ц)
	privateJoin: (code: string) -> (), -- §15л ч.4: войти в свой матч по коду
	tutorial: () -> (), -- §15ф Ф1: «Обучение» (одиночная партия с подсказками)
}

export type MainMenu = {
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	update: (now: number) -> (),
}

local MainMenu = {}

local CENTER_W = 660 -- карточка «ИГРАТЬ»
local SIDE_W = 300 -- колонки слева и справа
local EDGE = 24 -- отступ от края экрана
local ROW_H = 58 -- строка матча
local TILE = 84 -- плитка снизу
local GO_W = 136 -- кнопка строки

-- Тёмная панель со скруглением (Polish её не трогает — оформлена здесь).
local function panel(parent: Instance, name: string, alpha: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Theme.Colors.PanelBg
	f.BackgroundTransparency = alpha or 0.08
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.Parent = parent
	f:SetAttribute("FrontirStyled", true)
	MenuKit.corner(f, 14)
	local s = MenuKit.stroke(f, Theme.Colors.Slate, 1)
	s.Transparency = 0.35
	return f
end

-- Цвет кнопки строки по действию.
local GO_STYLE: { [string]: MenuKit.ButtonStyle } = {
	join = "good",
	new = "good",
	teams = "good",
	watch = "normal",
	full = "normal",
	busy = "normal",
}

function MainMenu.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang, mapName: string, act: Actions): MainMenu
	local cfg = Config.Render.Menu
	local player = Players.LocalPlayer
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local _ = mapName -- карта сервера приходит в строках списка (§15ц Ц2)

	-- Затемнение карты: по центру (под карточкой) темнее, по краям карта видна.
	local root = Instance.new("Frame")
	root.Name = "MainMenu"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Theme.Colors.Backdrop
	root.BackgroundTransparency = cfg.ShadeAlpha
	root.BorderSizePixel = 0
	root.Active = true
	root.Visible = false
	root.Parent = gui
	root:SetAttribute("FrontirStyled", true)
	local shade = Instance.new("UIGradient")
	shade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.3, 0.15),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.7, 0.15),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	shade.Parent = root
	if Config.Art.MenuBackground ~= "" then
		local bg = Instance.new("ImageLabel")
		bg.Name = "Background"
		bg.BackgroundTransparency = 1
		bg.Size = UDim2.fromScale(1, 1)
		bg.ZIndex = 0
		bg.Image = Config.Art.MenuBackground
		bg.ImageTransparency = Config.Art.BackgroundAlpha
		bg.ScaleType = Enum.ScaleType.Crop
		bg.Parent = root
	end

	------------------------------------------------------------------ центр: логотип и карточка «ИГРАТЬ»
	local center = Instance.new("Frame")
	center.Name = "Center"
	center.BackgroundTransparency = 1
	center.AnchorPoint = Vector2.new(0.5, 0)
	center.Position = UDim2.new(0.5, 0, 0, 16)
	center.Size = UDim2.fromOffset(CENTER_W, 0)
	center.AutomaticSize = Enum.AutomaticSize.Y
	center.Parent = root
	local centerScale = Instance.new("UIScale")
	centerScale.Parent = center
	MenuKit.list(center, 10, false, Enum.HorizontalAlignment.Center)

	local logoBox = MenuKit.box(center, "Logo", 1)
	if Config.Art.Logo ~= "" then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(Config.Art.LogoW, Config.Art.LogoH)
		img.Image = Config.Art.Logo
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = logoBox
	elseif Logo.new(logoBox, Config.Art.LogoScale + 1) == nil then
		local l = MenuKit.label(logoBox, t("lobby.title"), 44, Theme.Colors.Gold, true)
		l.FontFace = Theme.FontHeavy
	end
	local tagline = MenuKit.label(center, t("menu.tagline"), 15, Theme.Colors.Text, false, 2)
	tagline.TextTransparency = 0.15

	local card = panel(center, "Play")
	card.LayoutOrder = 3
	MenuKit.pad(card, 18, 18)
	MenuKit.list(card, 10)

	local playButton = MenuKit.button(card, "", "primary", 68, 1)
	playButton.Name = "PlayButton"
	playButton.TextSize = 30
	playButton.FontFace = Theme.FontHeavy
	local playHint = MenuKit.wrapLabel(card, "", 14, Theme.Colors.Muted, 2)
	playHint.TextXAlignment = Enum.TextXAlignment.Center

	-- Шапка списка: «МАТЧИ» и счёт.
	local listHead = Instance.new("Frame")
	listHead.Name = "ListHead"
	listHead.BackgroundTransparency = 1
	listHead.Size = UDim2.new(1, 0, 0, 24)
	listHead.LayoutOrder = 3
	listHead.Parent = card
	local listTitle = MenuKit.label(listHead, t("menu.matches"), 16, Theme.Colors.Text, true)
	listTitle.AnchorPoint = Vector2.new(0, 0.5)
	listTitle.Position = UDim2.fromScale(0, 0.5)
	local listCount = MenuKit.label(listHead, "", 13, Theme.Colors.Muted, true)
	listCount.AnchorPoint = Vector2.new(1, 0.5)
	listCount.Position = UDim2.fromScale(1, 0.5)
	listCount.TextXAlignment = Enum.TextXAlignment.Right

	-- Строки матчей.
	local matchList = MenuKit.box(card, "Matches", 4)
	matchList.Size = UDim2.fromScale(1, 0)
	matchList.AutomaticSize = Enum.AutomaticSize.Y
	MenuKit.list(matchList, 6)
	type MatchRow = {
		frame: Frame,
		thumb: ImageLabel,
		title: TextLabel,
		live: TextLabel,
		info: TextLabel,
		go: TextButton,
		row: ClientState.ServerRow?,
		map: string,
	}
	local thumbOf = MapThumb.new()
	local matchRows: { MatchRow } = {}
	local onRow: (r: ClientState.ServerRow) -> () = function() end
	for k = 1, Config.Lobbies.Rows do
		local row = Instance.new("Frame")
		row.Name = "Match" .. k
		row.LayoutOrder = k
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.BackgroundColor3 = Theme.Colors.Backdrop
		row.BackgroundTransparency = 0.25
		row.BorderSizePixel = 0
		row.Parent = matchList
		row:SetAttribute("FrontirStyled", true)
		MenuKit.corner(row, 10)
		local thumb = Instance.new("ImageLabel")
		thumb.Size = UDim2.fromOffset(MapThumbs.W * 1.75, MapThumbs.H * 1.75)
		thumb.AnchorPoint = Vector2.new(0, 0.5)
		thumb.Position = UDim2.new(0, 8, 0.5, 0)
		thumb.BackgroundColor3 = Theme.Colors.Ocean
		thumb.BorderSizePixel = 0
		thumb.ResampleMode = Enum.ResamplerMode.Pixelated
		thumb.Parent = row
		MenuKit.corner(thumb, 6)
		local textX = 8 + MapThumbs.W * 1.75 + 14
		local title = MenuKit.label(row, "", 18, Theme.Colors.Text, true)
		title.Position = UDim2.fromOffset(textX, 7)
		title.FontFace = Theme.FontHeavy
		-- «ИДЁТ» — красная метка рядом с названием карты.
		local live = MenuKit.label(row, t("menu.live"), 11, Theme.Colors.Text, true)
		live.BackgroundColor3 = Theme.Colors.Alert
		live.BackgroundTransparency = 0
		live.Position = UDim2.fromOffset(textX, 10)
		MenuKit.pad(live, 6, 2)
		MenuKit.corner(live, 4)
		live.Visible = false
		local info = MenuKit.label(row, "", 14, Theme.Colors.Muted)
		info.Position = UDim2.fromOffset(textX, 33)
		local go = MenuKit.button(row, "", "good", nil)
		go.Name = "Go"
		go.AnchorPoint = Vector2.new(1, 0.5)
		go.Position = UDim2.new(1, -8, 0.5, 0)
		go.Size = UDim2.fromOffset(GO_W, 42)
		go.TextSize = 16
		local r: MatchRow = {
			frame = row,
			thumb = thumb,
			title = title,
			live = live,
			info = info,
			go = go,
			row = nil,
			map = "",
		}
		Session.connect(go.Activated, function()
			local data = r.row
			if data ~= nil and go.Active then
				onRow(data)
			end
		end)
		row.Visible = false
		table.insert(matchRows, r)
	end
	local matchesEmpty = MenuKit.wrapLabel(matchList, "", 14, Theme.Colors.Muted, 99)

	-- Три кнопки снизу карточки.
	local more = MenuKit.box(card, "More", 5)
	more.Size = UDim2.fromScale(1, 0)
	more.AutomaticSize = Enum.AutomaticSize.Y
	MenuKit.list(more, 10, true)
	local soloButton = MenuKit.button(more, t("menu.solo"), "normal", 48, 1)
	soloButton.Name = "SoloButton"
	local ownButton = MenuKit.button(more, t("menu.own"), "normal", 48, 2)
	ownButton.Name = "OwnButton"
	local tutorialButton = MenuKit.button(more, t("menu.tutorial"), "normal", 48, 3)
	tutorialButton.Name = "TutorialButton"
	local function layoutMore()
		local shown = { soloButton, ownButton, tutorialButton }
		local n = 0
		for _, b in shown do
			if b.Visible then
				n += 1
			end
		end
		for _, b in shown do
			b.Size = UDim2.new(1 / math.max(1, n), -(10 * (n - 1)) / math.max(1, n), 0, 48)
		end
	end

	------------------------------------------------------------------ слева: профиль и задания дня
	local left = Instance.new("Frame")
	left.Name = "Left"
	left.BackgroundTransparency = 1
	left.Position = UDim2.fromOffset(EDGE, EDGE)
	left.Size = UDim2.fromOffset(SIDE_W, 0)
	left.AutomaticSize = Enum.AutomaticSize.Y
	left.Parent = root
	MenuKit.list(left, 12)

	local profile = Instance.new("TextButton")
	profile.Name = "Profile"
	profile.Text = ""
	profile.AutoButtonColor = true
	profile.LayoutOrder = 1
	profile.BackgroundColor3 = Theme.Colors.PanelBg
	profile.BackgroundTransparency = 0.08
	profile.BorderSizePixel = 0
	profile.Size = UDim2.new(1, 0, 0, 96)
	profile.Parent = left
	profile:SetAttribute("FrontirStyled", true)
	MenuKit.corner(profile, 14)
	MenuKit.stroke(profile, Theme.Colors.Slate, 1).Transparency = 0.35
	local rankIcon = MenuKit.rankIcon(profile, 1, 4)
	rankIcon.Position = UDim2.fromOffset(14, 16)
	local who = Instance.new("Frame")
	who.BackgroundTransparency = 1
	who.Position = UDim2.fromOffset(92, 12)
	who.Size = UDim2.new(1, -106, 1, -24)
	who.Parent = profile
	MenuKit.list(who, 4)
	local nameLabel = MenuKit.label(who, player.DisplayName, 19, Theme.Colors.Text, true, 1)
	local rankLabel = MenuKit.label(who, "", 14, Theme.Colors.Gold, true, 2)
	local xpBar = MenuKit.bar(who, 6, Theme.Colors.Sky, 3)
	local wallet = MenuKit.label(who, "", 14, Theme.Colors.Muted, false, 4)
	Session.connect(profile.Activated, act.ranks)

	local quests = panel(left, "Quests")
	quests.LayoutOrder = 2
	MenuKit.pad(quests, 16, 14)
	MenuKit.list(quests, 8)
	local questsHead = Instance.new("Frame")
	questsHead.BackgroundTransparency = 1
	questsHead.Size = UDim2.new(1, 0, 0, 22)
	questsHead.LayoutOrder = 0
	questsHead.Parent = quests
	MenuKit.label(questsHead, t("menu.quests"), 15, Theme.Colors.Text, true)
	local questsNew = MenuKit.label(questsHead, "", 12, Theme.Colors.Gold, true)
	questsNew.AnchorPoint = Vector2.new(1, 0)
	questsNew.Position = UDim2.fromScale(1, 0)
	type QuestRow = { frame: Frame, name: TextLabel, reward: TextLabel, bar: MenuKit.Bar, count: TextLabel }
	local questRows: { QuestRow } = {}
	for k = 1, Config.Quests.PerDay do
		local row = Instance.new("Frame")
		row.Name = "Quest" .. k
		row.LayoutOrder = k
		row.Size = UDim2.new(1, 0, 0, 50)
		row.BackgroundColor3 = Theme.Colors.Backdrop
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		row.Parent = quests
		row:SetAttribute("FrontirStyled", true)
		MenuKit.corner(row, 8)
		local name = MenuKit.label(row, "", 14, Theme.Colors.Text, false)
		name.Position = UDim2.fromOffset(10, 7)
		local reward = MenuKit.label(row, "", 13, Theme.Colors.Gold, true)
		reward.AnchorPoint = Vector2.new(1, 0)
		reward.Position = UDim2.new(1, -10, 0, 7)
		local barHost = Instance.new("Frame")
		barHost.BackgroundTransparency = 1
		barHost.Position = UDim2.fromOffset(10, 33)
		barHost.Size = UDim2.new(1, -80, 0, 6)
		barHost.Parent = row
		local bar = MenuKit.bar(barHost, 6, Theme.Colors.Sky)
		local count = MenuKit.label(row, "", 12, Theme.Colors.Muted, true)
		count.AnchorPoint = Vector2.new(1, 0)
		count.Position = UDim2.new(1, -10, 0, 28)
		table.insert(questRows, { frame = row, name = name, reward = reward, bar = bar, count = count })
	end
	local questsNote = MenuKit.wrapLabel(quests, "", 12, Theme.Colors.Muted, 10)

	------------------------------------------------------------------ справа: предложение недели
	local right = Instance.new("Frame")
	right.Name = "Right"
	right.BackgroundTransparency = 1
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.new(1, -EDGE, 0, EDGE)
	right.Size = UDim2.fromOffset(SIDE_W, 0)
	right.AutomaticSize = Enum.AutomaticSize.Y
	right.Parent = root
	MenuKit.list(right, 12)

	local offer = panel(right, "Offer")
	offer.LayoutOrder = 1
	MenuKit.pad(offer, 16, 14)
	MenuKit.list(offer, 6)
	MenuKit.label(offer, t("menu.weekly"), 15, Theme.Colors.Gold, true, 1)
	local weeklyWhat = MenuKit.wrapLabel(offer, "", 14, Theme.Colors.Text, 2)
	local weeklyLeft = MenuKit.label(offer, "", 12, Theme.Colors.Muted, false, 3)
	local dailyLine = MenuKit.label(offer, "", 13, Theme.Colors.Muted, false, 4)
	local openShop = MenuKit.button(offer, t("menu.open"), "normal", 42, 5)
	Session.connect(openShop.Activated, act.shop)

	------------------------------------------------------------------ снизу: плитки
	local tiles = Instance.new("Frame")
	tiles.Name = "Tiles"
	tiles.BackgroundTransparency = 1
	tiles.AnchorPoint = Vector2.new(0.5, 1)
	tiles.Position = UDim2.new(0.5, 0, 1, -16)
	tiles.Size = UDim2.fromOffset(0, TILE)
	tiles.AutomaticSize = Enum.AutomaticSize.X
	tiles.Parent = root
	local tilesScale = Instance.new("UIScale")
	tilesScale.Parent = tiles
	MenuKit.list(tiles, 10, true)
	local serverTile: TextButton? = nil
	local tileRank: Frame? = nil
	local tileDefs: { { key: string, icon: string, action: () -> () } } = {
		{ key = "arsenal", icon = "arsenal", action = act.arsenal },
		{ key = "shop", icon = "shop", action = act.shop },
		{ key = "wardrobe", icon = "wardrobe", action = act.wardrobe },
		{ key = "ranks", icon = "", action = act.ranks },
		{ key = "help", icon = "help", action = act.help },
		{ key = "invite", icon = "people", action = act.invite },
		{ key = "sound", icon = "sound", action = act.sound },
		{ key = "server", icon = "server", action = act.server },
	}
	for k, def in tileDefs do
		local b, slot = MenuKit.tile(tiles, "Tile_" .. def.key, t("menu.tile." .. def.key), TILE, k)
		local icon = if def.icon == "" then MenuKit.rankIcon(slot, 1, 2) else MenuKit.icon(slot, def.icon, 4)
		MenuKit.center(icon)
		if def.icon == "" then
			tileRank = icon
		end
		Session.connect(b.Activated, def.action)
		if def.key == "server" then
			serverTile = b
			b.Visible = false
		end
	end

	------------------------------------------------------------------ окно выбора карты и режима
	local function travelling(now: number): boolean
		return cs.travel == "going" and now - cs.travelAt < Config.Places.RetrySec
	end
	local opened = false
	local function setOpen(on: boolean)
		if opened == on then
			return
		end
		opened = on
		root.Visible = on
		act.onOpenChanged(on)
	end
	local setup = MatchSetup.new(root, lang, {
		start = function(choice: MatchSetup.Choice)
			local req: Request = { map = choice.map, mode = choice.mode, solo = choice.solo, level = choice.level }
			if not choice.solo and cs.place == "hub" then
				act.privateCreate(req)
				return
			end
			act.play(nil, req)
			if cs.place ~= "hub" then
				setOpen(false)
			end
		end,
		joinCode = act.privateJoin,
		codeAllowed = function(): boolean
			return cs.place == "hub"
		end,
		busy = function(): boolean
			return travelling(os.clock())
		end,
	})
	Session.connect(soloButton.Activated, function()
		setup.open("solo")
	end)
	Session.connect(ownButton.Activated, function()
		setup.open("own")
	end)

	------------------------------------------------------------------ раскладка под экран
	local function fit()
		local s = UiScale.size(gui)
		local f = UiScale.factor()
		-- Боковые колонки — если по бокам от карточки есть место.
		local sides = s.X >= CENTER_W + 2 * SIDE_W + 4 * EDGE
		left.Visible = sides
		right.Visible = sides
		tilesScale.Scale =
			math.clamp((s.X - 2 * EDGE) / math.max(1, tiles.AbsoluteSize.X / f / tilesScale.Scale), 0.5, 1)
		-- Центр — между верхом и плитками.
		local natural = center.AbsoluteSize.Y / f / math.max(0.01, centerScale.Scale)
		local room = s.Y - 16 - (TILE * tilesScale.Scale + 16 + 12)
		if natural > 0 then
			centerScale.Scale = math.clamp(math.min(room / natural, (s.X - 2 * EDGE) / CENTER_W), 0.5, 1)
		end
	end
	UiScale.onResize(gui, fit)
	Session.connect(center:GetPropertyChangedSignal("AbsoluteSize"), function()
		task.defer(fit)
	end)
	fit()

	------------------------------------------------------------------ действия
	Session.connect(playButton.Activated, function()
		if cs.place == "hub" then
			act.play(nil, nil) -- хаб: быстрый вход на сервер матча
		else
			act.join() -- §15л ч.7: матч начинается только по «В БОЙ»
			setOpen(false)
		end
	end)
	Session.connect(tutorialButton.Activated, function()
		act.tutorial()
		setOpen(false)
	end)
	function onRow(r: ClientState.ServerRow)
		local hub = cs.place == "hub"
		if r.action == "full" or r.action == "busy" then
			return
		end
		if r.id == "" then
			-- Новое лобби пары: хаб поднимает сервер, «как раньше» — матч этого сервера с этой картой и режимом.
			act.play(nil, { map = r.map, mode = r.mode })
			if not hub then
				setOpen(false)
			end
		elseif hub then
			act.play(r.id, nil)
		else
			-- Свой сервер («как раньше»): войти в его матч или смотреть его.
			if r.action ~= "watch" then
				act.join()
			end
			setOpen(false)
		end
	end

	------------------------------------------------------------------ обновление
	local gold = Theme.Colors.Gold:ToHex()
	local function rowsUpdate(now: number)
		local going = travelling(now)
		local open, live = 0, 0
		for k, r in matchRows do
			local e = cs.servers[k]
			r.row = e
			r.frame.Visible = e ~= nil
			if e == nil then
				continue
			end
			if e.action == "watch" then
				live += 1
			elseif e.action ~= "full" and e.action ~= "busy" then
				open += 1
			end
			if r.map ~= e.map then
				r.map = e.map
				local content = thumbOf(e.map)
				if content ~= nil then
					r.thumb.ImageContent = content
				end
			end
			r.title.Text = Strings.get("map." .. e.map, lang)
			-- «ИДЁТ» — справа от названия карты.
			r.live.Visible = e.phase == "Play"
			if r.live.Visible then
				r.live.Position = UDim2.fromOffset(r.title.Position.X.Offset + r.title.TextBounds.X + 10, 10)
			end
			local elapsed = now - cs.serversAt
			local status: string
			if e.phase == "New" then
				status = t("menu.status.New")
			elseif e.phase == "Play" then
				status = string.format(t("menu.status.Play"), MenuKit.clock(e.left + elapsed))
			elseif e.phase == "Waiting" then
				status = t("menu.status.Waiting")
			else
				status = string.format(
					Strings.get("menu.status." .. e.phase, lang),
					math.ceil(math.max(0, e.left - elapsed))
				)
			end
			local who = if e.phase == "New"
				then string.format(t("menu.nations"), e.max)
				else string.format(t("menu.players"), e.players, e.max)
			r.info.RichText = true
			r.info.Text = string.format(
				'<font color="#%s"><b>%s</b></font>  ·  %s  ·  %s',
				gold,
				Strings.get("mode." .. e.mode, lang),
				who,
				status
			)
			local style = GO_STYLE[e.action] or "normal"
			local active = e.action ~= "full" and e.action ~= "busy" and not going
			-- Свой сервер («как раньше»), а вы в его матче — «Вернуться», а не «Смотреть».
			local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
			local back = e.id == "here" and me ~= nil and me.alive and not cs.demo
			r.go.Text = t(if back then "menu.row.back" else "menu.row." .. e.action)
			r.go.BackgroundColor3 = Theme.color(if style == "good" then "Forest" else "Slate")
			r.go.Active = active
			r.go.AutoButtonColor = active
			r.go.BackgroundTransparency = if active then 0 else 0.5
			r.go.TextTransparency = if active then 0 else 0.35
		end
		matchesEmpty.Text = if #cs.servers == 0 then t("menu.matchesEmpty") else ""
		matchesEmpty.Visible = #cs.servers == 0
		listCount.Text = string.format(t("menu.matchesHead"), open, live)
	end

	local nextAt = 0
	local function update(now: number)
		if not opened then
			return
		end
		-- Кнопки окна выбора (идёт переход — неактивны) — без ожидания RefreshSec.
		if now < nextAt then
			return
		end
		nextAt = now + cfg.RefreshSec

		-- Профиль.
		local p = cs.profile
		local level = if p ~= nil then p.level else 1
		local rank = Ranks.of(level)
		MenuKit.setRank(rankIcon, rank, 4)
		local tr = tileRank
		if tr ~= nil then
			MenuKit.setRank(tr, rank, 2)
		end
		nameLabel.Text = player.DisplayName
		rankLabel.Text = Strings.get("rank." .. rank, lang) .. "  ·  " .. string.format(t("menu.level"), level)
		rankLabel.TextColor3 = Theme.color(Ranks.GroupColors[Ranks.group(rank)])
		xpBar.set(if p ~= nil and p.need > 0 then p.xp / p.need elseif p ~= nil then 1 else 0)
		wallet.Text = string.format(t("menu.medals"), Strings.formatInt(if p ~= nil then p.medals else 0))
			.. "     "
			.. string.format(t("menu.tokens"), if p ~= nil then p.tokens else 0)

		-- «В БОЙ», подсказка и список.
		local hub = cs.place == "hub"
		root.BackgroundTransparency = if hub or cs.demo then Config.Hub.ShadeAlpha else cfg.ShadeAlpha
		local going = travelling(now)
		rowsUpdate(now)
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		local watching = not hub
			and not cs.demo
			and (cs.phase == "Play" or cs.phase == "Over")
			and (me == nil or not me.alive)
		playButton.Text = if going
			then t("menu.connecting")
			else "▶  " .. t(if watching then "menu.watch" else "menu.play")
		playButton.Active = not going
		local failed = cs.travel == "failed" and now - cs.travelAt < Config.Places.RetrySec
		playHint.Text = if failed and cs.travelReason == "badCode"
			then t("menu.badCode")
			elseif failed and cs.travelReason == "busy" then t("menu.busy")
			elseif failed then t("menu.travelFailed")
			elseif going then t("menu.connectingHint")
			elseif watching then t("menu.watchHint")
			else t("menu.quickHint")
		playHint.TextColor3 = if failed then Theme.Colors.Alert else Theme.Colors.Muted
		tutorialButton.Visible = not hub
			and (p == nil or not p.tutorialDone)
			and (cs.demo or ((cs.phase == "Waiting" or cs.phase == "Lobby") and cs.myNation == nil))
		soloButton.Active = not going
		ownButton.Active = not going
		layoutMore()

		-- Задания дня.
		local list = if p ~= nil then p.quests else {}
		for k, row in questRows do
			local q = list[k]
			row.frame.Visible = q ~= nil
			if q ~= nil then
				row.name.Text = (if q.done then "✔ " else "")
					.. string.format(Strings.get("quest." .. q.kind, lang), q.target)
				row.name.TextColor3 = if q.done then Theme.Colors.Gold else Theme.Colors.Text
				row.reward.Text = string.format(t("menu.questReward"), q.medals)
				row.count.Text = string.format("%d / %d", math.min(q.progress, q.target), q.target)
				row.bar.set(q.progress / math.max(1, q.target))
				row.bar.fill.BackgroundColor3 = if q.done then Theme.Colors.Good else Theme.Colors.Sky
			end
		end
		if p == nil then
			questsNote.Text = t("menu.questsEmpty")
			questsNew.Text = ""
		else
			questsNote.Text = if p.questsBonus
				then t("menu.questsBonusDone")
				else string.format(t("menu.questsBonus"), Config.Quests.AllDoneTokens)
			questsNew.Text = string.format(t("menu.questsNew"), math.max(0, p.dayLeft) // 3600)
		end

		-- Предложение недели и ежедневная награда.
		offer.Visible = p ~= nil
		if p ~= nil then
			weeklyWhat.Text = act.rewardText(p.weekly.offer)
			weeklyLeft.Text = string.format(t("menu.weeklyLeft"), act.timeLeft(p.weekly.left))
			dailyLine.Text = string.format(t("menu.dailyStreak"), p.dailyStreak)
				.. "  ·  "
				.. string.format(t("menu.crates"), p.crates)
		end
		local st = serverTile
		if st ~= nil then
			st.Visible = act.serverVisible()
		end
	end

	return {
		open = function()
			setOpen(true)
			nextAt = 0
			update(os.clock())
		end,
		close = function()
			if cs.place ~= "hub" then -- в хабе меню не закрывается: матча за ним нет
				setup.close()
				setOpen(false)
			end
		end,
		isOpen = function(): boolean
			return opened
		end,
		update = update,
	}
end

return table.freeze(MainMenu)
