--!strict
--[[
	MainMenu — главное меню (GDD §15л): открывается при входе в игру, поверх затемнённой карты текущего матча;
	интерфейс матча под ним скрыт (Main.client выключает hudGui). Живёт в своём ScreenGui (IgnoreGuiInset):
	- сверху полоса: круглые «Звук» и «Как играть», «ФРОНТИР», справа — звание, имя, уровень с полосой опыта,
	  медали и жетоны (нажатие — «Звания»);
	- карточки: «Задания дня» (слева), «Сейчас на сервере» с кнопкой «В БОЙ» (по центру), «Магазин» (справа);
	- снизу плитки: Магазин, Гардероб, Лидеры, Звания, Как играть, Сервер (только владельцу частного сервера).
	Окна (магазин, гардероб…) открываются в слое окон над меню. Узкий экран — всё ужимается UIScale.
	§15л ч.3: в хабе (cs.place == "hub") меню не закрывается, вместо «Сейчас на сервере» — «Матчи»: строки серверов
	матча с «Войти» / «Смотреть»; «В БОЙ» — быстрый вход (act.play), пока идёт переход — «Подключение…».
]]

local GuiService = game:GetService("GuiService")
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
local SceneBanner = require(script.Parent:WaitForChild("SceneBanner"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type Actions = {
	shop: () -> (),
	wardrobe: () -> (),
	quests: () -> (),
	ranks: () -> (),
	arsenal: () -> (), -- §15л ч.6
	help: () -> (),
	sound: () -> (),
	server: () -> (),
	serverVisible: () -> boolean, -- плитка «Сервер» — только владельцу частного сервера в лобби
	rewardText: (reward: any) -> string, -- что в наборе (как в магазине)
	timeLeft: (sec: number) -> string, -- «N дн. N ч»
	onOpenChanged: (open: boolean) -> (),
	play: (serverId: string?) -> (), -- §15л ч.3: хаб — переход на сервер матча (nil — быстрый вход)
	join: () -> (), -- §15л ч.7: «как раньше» — вступить в матч (держава — только по «В БОЙ»)
	invite: () -> (), -- §15л ч.7: пригласить друзей (окно Roblox)
	privateCreate: () -> (), -- §15л ч.4: свой матч — новый сервер для друзей
	privateJoin: (code: string) -> (), -- §15л ч.4: войти в свой матч по коду
}

export type MainMenu = {
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	update: (now: number) -> (),
}

local MainMenu = {}

function MainMenu.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang, mapName: string, act: Actions): MainMenu
	local cfg = Config.Render.Menu
	local player = Players.LocalPlayer
	local function t(key: string): string
		return Strings.get(key, lang)
	end

	-- Затемнение карты: сверху и снизу темнее. Active — клики и колесо не уходят в карту.
	local root = Instance.new("Frame")
	root.Name = "MainMenu"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Theme.Colors.Backdrop
	root.BackgroundTransparency = cfg.ShadeAlpha
	root.BorderSizePixel = 0
	root.Active = true
	root.Visible = false
	root.Parent = gui
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.35, 0.45),
		NumberSequenceKeypoint.new(0.7, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	shade.Parent = root

	-- Верхняя полоса — под кнопками Roblox (GetGuiInset), во всю ширину.
	local inset = GuiService:GetGuiInset()
	local top = Instance.new("Frame")
	top.Name = "TopBar"
	top.Position = UDim2.fromOffset(0, inset.Y)
	top.Size = UDim2.new(1, 0, 0, cfg.TopBarPx)
	top.BackgroundColor3 = Theme.Colors.Backdrop
	top.BackgroundTransparency = 0.1
	top.BorderSizePixel = 0
	top:SetAttribute("FrontirStyled", true) -- плоская полоса: без скругления и рамки Polish
	top.Parent = root
	local topLine = Instance.new("Frame")
	topLine.AnchorPoint = Vector2.new(0, 1)
	topLine.Position = UDim2.fromScale(0, 1)
	topLine.Size = UDim2.new(1, 0, 0, 2)
	topLine.BackgroundColor3 = Theme.Colors.Gold
	topLine.BackgroundTransparency = 0.5
	topLine.BorderSizePixel = 0
	topLine.Parent = top

	local leftButtons = MenuKit.box(top, "Left")
	leftButtons.AnchorPoint = Vector2.new(0, 0.5)
	leftButtons.Position = UDim2.new(0, 16, 0.5, 0)
	MenuKit.list(leftButtons, 8, true)
	local soundButton = MenuKit.roundButton(leftButtons, "Sound", "sound", 1)
	local helpButton = MenuKit.roundButton(leftButtons, "Help", "help", 2)
	Session.connect(soundButton.Activated, act.sound)
	Session.connect(helpButton.Activated, act.help)

	local logo = MenuKit.label(top, t("lobby.title"), 34, Theme.Colors.Gold, true)
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.5)
	logo.TextStrokeTransparency = 0.3
	logo.TextStrokeColor3 = Theme.color("Orange")
	-- §15л ч.4: свой арт (docs/ART_LIST.md) — логотип и фон меню картинками, если их id вписаны в Config.Art.
	local art = Config.Art
	local logoImage: ImageLabel? = nil
	if art.Logo ~= "" then
		local img = Instance.new("ImageLabel")
		img.Name = "LogoImage"
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromOffset(art.LogoW, art.LogoH)
		img.Image = art.Logo
		img.ScaleType = Enum.ScaleType.Fit
		img.ResampleMode = Enum.ResamplerMode.Pixelated
		img.Parent = top
		logo.TextTransparency = 1
		logo.TextStrokeTransparency = 1
		logoImage = img
	else
		-- §15л ч.5: логотип «WORLD CONQUER» пикселями из кода (Shared.LogoArt).
		local img = Logo.new(top, art.LogoScale)
		if img ~= nil then
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.fromScale(0.5, 0.5)
			logo.TextTransparency = 1
			logo.TextStrokeTransparency = 1
			logoImage = img
		end
	end
	if art.MenuBackground ~= "" then
		local bg = Instance.new("ImageLabel")
		bg.Name = "Background"
		bg.BackgroundTransparency = 1
		bg.Size = UDim2.fromScale(1, 1)
		bg.ZIndex = 0 -- под карточками и плитками
		bg.Image = art.MenuBackground
		bg.ImageTransparency = art.BackgroundAlpha
		bg.ScaleType = Enum.ScaleType.Crop
		bg.ResampleMode = Enum.ResamplerMode.Pixelated
		bg.Parent = root
	end

	-- Профиль справа: звание, имя, уровень, полоса опыта; медали и жетоны.
	local right = MenuKit.box(top, "Right")
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.new(1, -16, 0.5, 0)
	MenuKit.list(right, 12, true)
	local profile = Instance.new("TextButton")
	profile.Name = "Profile"
	profile.Text = ""
	profile.AutoButtonColor = true
	profile.BackgroundColor3 = Theme.Colors.PanelBg
	profile.BackgroundTransparency = 0.95
	profile.BorderSizePixel = 0
	profile.Size = UDim2.fromOffset(0, cfg.TopBarPx - 12)
	profile.AutomaticSize = Enum.AutomaticSize.X
	profile.LayoutOrder = 1
	profile.Parent = right
	MenuKit.pad(profile, 6, 4)
	MenuKit.list(profile, 10, true)
	local rankIcon = MenuKit.rankIcon(profile, 1, cfg.RankIconScale, 1)
	local who = MenuKit.box(profile, "Who", 2)
	MenuKit.list(who, 2)
	local nameLabel = MenuKit.label(who, player.DisplayName, 17, Theme.Colors.Text, true, 1)
	local levelLabel = MenuKit.label(who, "", 12, Theme.Colors.Gold, true, 2)
	local xpRow = MenuKit.box(who, "Xp", 3)
	MenuKit.list(xpRow, 8, true)
	local xpBarHost = Instance.new("Frame")
	xpBarHost.BackgroundTransparency = 1
	xpBarHost.Size = UDim2.fromOffset(150, 6)
	xpBarHost.LayoutOrder = 1
	xpBarHost.Parent = xpRow
	local xpBar = MenuKit.bar(xpBarHost, 6, Theme.Colors.Sky)
	local xpLabel = MenuKit.label(xpRow, "", 11, Theme.Colors.Muted, false, 2)
	Session.connect(profile.Activated, act.ranks)

	local function chip(order: number): TextLabel
		local c = Instance.new("TextLabel")
		c.LayoutOrder = order
		c.Size = UDim2.fromOffset(0, 36)
		c.AutomaticSize = Enum.AutomaticSize.X
		c.BackgroundColor3 = Theme.Colors.PanelBg
		c.BorderSizePixel = 0
		c.FontFace = Theme.FontBold
		c.TextSize = 17
		c.TextColor3 = Theme.Colors.Text
		c.Parent = right
		MenuKit.corner(c, 6)
		MenuKit.stroke(c, Theme.Colors.Sky, 2)
		MenuKit.pad(c, 12, 0)
		return c
	end
	local medals = chip(2)
	local tokens = chip(3)
	tokens.TextColor3 = Theme.Colors.Gold

	-- Середина: три карточки (масштаб под экран — общий с плитками).
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0)
	stage.Position = UDim2.new(0.5, 0, 0, inset.Y + cfg.TopBarPx + 20)
	stage.Size = UDim2.fromOffset(0, 0)
	stage.AutomaticSize = Enum.AutomaticSize.XY
	stage.Parent = root
	local stageScale = Instance.new("UIScale")
	stageScale.Parent = stage
	local cards = MenuKit.box(stage, "Cards")
	local cardsList = MenuKit.list(cards, 18, true)
	cardsList.VerticalAlignment = Enum.VerticalAlignment.Top

	-- «Задания дня».
	local quests = MenuKit.card(cards, "Quests", t("menu.quests"), cfg.SideCardPx, 1)
	SceneBanner.image(quests.frame, "quests", Config.Render.Banner.SideCardPx) -- §15л ч.8: картинка карточки
	type QuestRow = { frame: Frame, name: TextLabel, reward: TextLabel, bar: MenuKit.Bar, count: TextLabel }
	local questRows: { QuestRow } = {}
	for k = 1, Config.Quests.PerDay do
		local row = MenuKit.row(quests.body, "Quest" .. k, k)
		local name = MenuKit.wrapLabel(row, "", 13, Theme.Colors.Text, 1)
		local line = Instance.new("Frame")
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(1, 0, 0, 16)
		line.LayoutOrder = 2
		line.Parent = row
		local barHost = Instance.new("Frame")
		barHost.BackgroundTransparency = 1
		barHost.AnchorPoint = Vector2.new(0, 0.5)
		barHost.Position = UDim2.fromScale(0, 0.5)
		barHost.Size = UDim2.new(1, -110, 0, 6)
		barHost.Parent = line
		local bar = MenuKit.bar(barHost, 6, Theme.Colors.Sky)
		local count = MenuKit.label(line, "", 12, Theme.Colors.Muted, true)
		count.AnchorPoint = Vector2.new(1, 0.5)
		count.Position = UDim2.new(1, -54, 0.5, 0)
		count.TextXAlignment = Enum.TextXAlignment.Right
		local reward = MenuKit.label(line, "", 13, Theme.Colors.Gold, true)
		reward.AnchorPoint = Vector2.new(1, 0.5)
		reward.Position = UDim2.fromScale(1, 0.5)
		reward.TextXAlignment = Enum.TextXAlignment.Right
		table.insert(questRows, { frame = row, name = name, reward = reward, bar = bar, count = count })
	end
	local questsNote = MenuKit.wrapLabel(quests.body, "", 12, Theme.Colors.Muted, 10)

	-- «Сейчас на сервере».
	local server = MenuKit.card(cards, "Server", t("menu.server"), cfg.CenterCardPx, 2)
	SceneBanner.image(server.frame, "battle", Config.Render.Banner.CardPx)
	server.accent.TextColor3 = Theme.Colors.Alert
	local mapLabel = MenuKit.label(server.body, Strings.get("map." .. mapName, lang), 30, Theme.Colors.Text, true, 1)
	local modeLabel = MenuKit.label(server.body, "", 15, Theme.Colors.Sky, false, 2)
	local playersLabel = MenuKit.label(server.body, "", 14, Theme.Colors.Muted, false, 3)
	local statusLabel = MenuKit.label(server.body, "", 18, Theme.Colors.Gold, true, 4)
	local phaseBar = MenuKit.bar(server.body, 8, Theme.Colors.Gold, 5)
	local playButton = MenuKit.button(server.body, "", "primary", 64, 6)
	local playHint = MenuKit.wrapLabel(server.body, "", 13, Theme.Colors.Muted, 7)
	local roster = MenuKit.wrapLabel(server.body, "", 12, Theme.Colors.Muted, 8)
	mapLabel.TextStrokeTransparency = 0.6

	-- §15л ч.3 Хаб: строки «Матчи» (карта, режим, игроки, что идёт; справа — «Войти» / «Смотреть»).
	local matchList = MenuKit.box(server.body, "Matches", 0)
	matchList.Size = UDim2.fromScale(1, 0)
	matchList.AutomaticSize = Enum.AutomaticSize.Y
	MenuKit.list(matchList, 6)
	matchList.Visible = false
	type MatchRow = {
		frame: Frame,
		title: TextLabel,
		info: TextLabel,
		go: TextButton,
		id: string,
		thumb: ImageLabel,
		map: string,
	}
	local thumbOf = MapThumb.new() -- §15л ч.6: миниатюры карт
	local matchRows: { MatchRow } = {}
	for k = 1, Config.Places.ListMax do
		local row = MenuKit.row(matchList, "Match" .. k, k)
		local thumb = Instance.new("ImageLabel")
		thumb.Name = "Thumb"
		thumb.LayoutOrder = 0
		thumb.Size = UDim2.fromOffset(MapThumbs.W * 2, MapThumbs.H * 2)
		thumb.BackgroundColor3 = Theme.Colors.Backdrop
		thumb.BorderSizePixel = 0
		thumb.ResampleMode = Enum.ResamplerMode.Pixelated
		thumb.Parent = row
		MenuKit.stroke(thumb, Theme.Colors.Slate, 2)
		local text = MenuKit.box(row, "Text", 1)
		text.Size = UDim2.new(1, -(120 + MapThumbs.W * 2 + 10), 0, 0)
		text.AutomaticSize = Enum.AutomaticSize.Y
		MenuKit.list(text, 2)
		local title = MenuKit.label(text, "", 15, Theme.Colors.Text, true, 1)
		local info = MenuKit.label(text, "", 12, Theme.Colors.Muted, false, 2)
		local go = MenuKit.button(row, "", "good", nil, 2)
		go.Size = UDim2.fromOffset(110, MenuKit.Touch)
		go.AnchorPoint = Vector2.new(1, 0.5)
		go.Position = UDim2.fromScale(1, 0.5)
		-- В строке список выключен: текст слева, кнопка справа.
		local layout = row:FindFirstChildOfClass("UIListLayout")
		if layout ~= nil then
			layout.FillDirection = Enum.FillDirection.Horizontal
			layout.VerticalAlignment = Enum.VerticalAlignment.Center
			layout.Padding = UDim.new(0, 10)
		end
		local r: MatchRow = { frame = row, title = title, info = info, go = go, id = "", thumb = thumb, map = "" }
		Session.connect(go.Activated, function()
			if r.id ~= "" then
				act.play(r.id)
			end
		end)
		row.Visible = false
		table.insert(matchRows, r)
	end
	local matchesEmpty = MenuKit.wrapLabel(matchList, "", 13, Theme.Colors.Muted, 99)

	-- §15л ч.4 Хаб: «Свой матч» и «Войти по коду» (как приватное лобби в похожих играх).
	local friends = MenuKit.box(server.body, "Friends", 9)
	friends.Size = UDim2.fromScale(1, 0)
	friends.AutomaticSize = Enum.AutomaticSize.Y
	MenuKit.list(friends, 6)
	friends.Visible = false
	MenuKit.label(friends, t("menu.friends"), 13, Theme.Colors.Sky, true, 1)
	local friendsRow = MenuKit.box(friends, "Row", 2)
	MenuKit.list(friendsRow, 8, true)
	local createButton = MenuKit.button(friendsRow, t("menu.privateCreate"), "normal", nil, 1)
	createButton.Size = UDim2.fromOffset(150, MenuKit.Touch)
	local codeBox = Instance.new("TextBox")
	codeBox.Name = "CodeBox"
	codeBox.LayoutOrder = 2
	codeBox.Size = UDim2.fromOffset(130, MenuKit.Touch)
	codeBox.BackgroundColor3 = Theme.Colors.Backdrop
	codeBox.BorderSizePixel = 0
	codeBox.ClearTextOnFocus = false
	codeBox.FontFace = Theme.FontBold
	codeBox.TextSize = 18
	codeBox.TextColor3 = Theme.Colors.Gold
	codeBox.PlaceholderText = t("menu.codePlaceholder")
	codeBox.PlaceholderColor3 = Theme.Colors.Muted
	codeBox.Text = ""
	codeBox.Parent = friendsRow
	MenuKit.stroke(codeBox, Theme.Colors.Slate, 2)
	local joinButton = MenuKit.button(friendsRow, t("menu.codeJoin"), "good", nil, 3)
	joinButton.Size = UDim2.fromOffset(110, MenuKit.Touch)
	Session.connect(codeBox:GetPropertyChangedSignal("Text"), function()
		-- Только буквы и цифры кода, заглавными, не длиннее кода.
		local clean = string.sub(string.upper((string.gsub(codeBox.Text, "[^%w]", ""))), 1, Config.Places.CodeLength)
		if clean ~= codeBox.Text then
			codeBox.Text = clean
		end
	end)
	Session.connect(createButton.Activated, act.privateCreate)
	Session.connect(joinButton.Activated, function()
		act.privateJoin(codeBox.Text)
	end)
	Session.connect(codeBox.FocusLost, function(enter: boolean)
		if enter then
			act.privateJoin(codeBox.Text)
		end
	end)

	-- «Магазин».
	local shop = MenuKit.card(cards, "Shop", t("menu.shop"), cfg.SideCardPx, 3)
	SceneBanner.image(shop.frame, "shop", Config.Render.Banner.SideCardPx)
	shop.accent.TextColor3 = Theme.Colors.Sky
	local weekly = MenuKit.row(shop.body, "Weekly", 1)
	MenuKit.label(weekly, t("menu.weekly"), 14, Theme.Colors.Gold, true, 1)
	local weeklyWhat = MenuKit.wrapLabel(weekly, "", 13, Theme.Colors.Text, 2)
	local weeklyLeft = MenuKit.label(weekly, "", 11, Theme.Colors.Muted, false, 3)
	local daily = MenuKit.row(shop.body, "Daily", 2)
	MenuKit.label(daily, t("menu.daily"), 14, Theme.Colors.Gold, true, 1)
	local dailyLine = MenuKit.label(daily, "", 13, Theme.Colors.Text, false, 2)
	local openShop = MenuKit.button(shop.body, t("menu.open"), "normal", nil, 3)
	Session.connect(openShop.Activated, act.shop)

	-- Плитки снизу.
	local tiles = MenuKit.box(root, "Tiles")
	tiles.AnchorPoint = Vector2.new(0.5, 1)
	tiles.Position = UDim2.new(0.5, 0, 1, -20)
	MenuKit.list(tiles, 10, true)
	local tilesScale = Instance.new("UIScale")
	tilesScale.Parent = tiles
	local serverTile: TextButton? = nil
	local tileRank: Frame? = nil
	local tileDefs: { { key: string, icon: string, action: () -> () } } = {
		{ key = "shop", icon = "shop", action = act.shop },
		{ key = "wardrobe", icon = "wardrobe", action = act.wardrobe },
		{ key = "arsenal", icon = "arsenal", action = act.arsenal },
		{ key = "invite", icon = "people", action = act.invite },
		{ key = "quests", icon = "quests", action = act.quests },
		{ key = "ranks", icon = "", action = act.ranks },
		{ key = "help", icon = "help", action = act.help },
		{ key = "server", icon = "server", action = act.server },
	}
	for k, def in tileDefs do
		local b, slot = MenuKit.tile(tiles, "Tile_" .. def.key, t("menu.tile." .. def.key), cfg.TilePx, k)
		local icon = if def.icon == "" then MenuKit.rankIcon(slot, 1, 3) else MenuKit.icon(slot, def.icon, 5)
		MenuKit.center(icon)
		if def.icon == "" then
			tileRank = icon
		end
		if def.key == "server" then
			serverTile = b
		end
		Session.connect(b.Activated, def.action)
	end

	local function fit()
		local s = gui.AbsoluteSize
		local scale = math.clamp(math.min(s.X / cfg.MinWidthPx, s.Y / cfg.MinHeightPx), 0.45, 1)
		stageScale.Scale = scale
		tilesScale.Scale = scale
		-- На узком экране профиль справа налезет на логотип — логотип прячем.
		logo.Visible = s.X >= 900
		if logoImage ~= nil then
			logoImage.Visible = logo.Visible
		end
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()

	local opened = false
	local function setOpen(on: boolean)
		if opened == on then
			return
		end
		opened = on
		root.Visible = on
		act.onOpenChanged(on)
	end
	Session.connect(playButton.Activated, function()
		if cs.place == "hub" then
			act.play(nil) -- хаб: быстрый вход на сервер матча
		else
			act.join() -- §15л ч.7: матч начинается только по «В БОЙ»
			setOpen(false)
		end
	end)
	-- Идёт переход в другое место (не дольше Places.RetrySec — потом кнопка снова доступна).
	local function travelling(now: number): boolean
		return cs.travel == "going" and now - cs.travelAt < Config.Places.RetrySec
	end
	local function hubCard(now: number)
		server.title.Text = t("menu.matches")
		server.accent.Text = if #cs.servers > 0 then string.format(t("menu.matchesCount"), #cs.servers) else ""
		for k, r in matchRows do
			local e = cs.servers[k]
			r.frame.Visible = e ~= nil
			if e ~= nil then
				r.id = e.id
				if r.map ~= e.map then
					r.map = e.map
					local content = thumbOf(e.map)
					if content ~= nil then
						r.thumb.ImageContent = content
					end
				end
				r.title.Text = Strings.get("map." .. e.map, lang) .. "  ·  " .. Strings.get("mode." .. e.mode, lang)
				local left = e.left
				if e.phase ~= "Play" then
					left = math.max(0, e.left - (now - cs.serversAt))
				else
					left = e.left + (now - cs.serversAt)
				end
				local status = if e.phase == "Play"
					then string.format(t("menu.status.Play"), MenuKit.clock(left))
					elseif e.phase == "Waiting" then t("menu.status.Waiting")
					else string.format(Strings.get("menu.status." .. e.phase, lang), math.ceil(left))
				r.info.Text = string.format(t("menu.players"), e.players, e.max) .. "  ·  " .. status
				r.go.Text = t("menu.row." .. e.action)
				r.go.Active = e.action ~= "full" and not travelling(now)
				r.go.AutoButtonColor = r.go.Active
				r.go.BackgroundTransparency = if r.go.Active then 0 else 0.5
			end
		end
		matchesEmpty.Text = if #cs.servers == 0 then t("menu.matchesEmpty") else ""
		matchesEmpty.Visible = #cs.servers == 0
		local going = travelling(now)
		playButton.Text = if going then t("menu.connecting") else "▶  " .. t("menu.play")
		playButton.Active = not going
		playButton.AutoButtonColor = not going
		friends.Visible = true
		createButton.Active = not going
		joinButton.Active = not going and #codeBox.Text == Config.Places.CodeLength
		joinButton.BackgroundTransparency = if joinButton.Active then 0 else 0.5
		playHint.Text = if cs.travel == "failed" and cs.travelReason == "badCode"
			then t("menu.badCode")
			elseif cs.travel == "failed" then t("menu.travelFailed")
			elseif going then t("menu.connectingHint")
			else t("menu.quickHint")
		playHint.TextColor3 = if cs.travel == "failed" then Theme.Colors.Alert else Theme.Colors.Muted
		playHint.Visible = true
	end

	-- Режим: в лобби — лидер голосования.
	local function modeName(): string
		local mode = cs.mode
		local best, bestVotes = mode.mode, -1
		if cs.phase == "Lobby" or cs.phase == "Waiting" then
			for k, id in mode.options do
				local v = mode.counts[k] or 0
				if v > bestVotes then
					best, bestVotes = id, v
				end
			end
		end
		return Strings.get("mode." .. best, lang)
	end

	local nextAt = 0
	local function update(now: number)
		if not opened or now < nextAt then
			return
		end
		nextAt = now + cfg.RefreshSec

		-- Профиль.
		local p = cs.profile
		local level = if p ~= nil then p.level else 1
		local rank = Ranks.of(level)
		MenuKit.setRank(rankIcon, rank, cfg.RankIconScale)
		if tileRank ~= nil then
			MenuKit.setRank(tileRank, rank, 3)
		end
		nameLabel.Text = player.DisplayName
		levelLabel.Text = string.format(t("menu.level"), level) .. "  ·  " .. Strings.get("rank." .. rank, lang)
		if p ~= nil and p.need > 0 then
			xpBar.set(p.xp / p.need)
			xpLabel.Text = string.format(t("menu.xp"), p.xp, p.need)
		else
			xpBar.set(if p ~= nil then 1 else 0)
			xpLabel.Text = if p ~= nil then t("menu.maxLevel") else ""
		end
		medals.Text = string.format(t("menu.medals"), Strings.formatInt(if p ~= nil then p.medals else 0))
		tokens.Text = string.format(t("menu.tokens"), if p ~= nil then p.tokens else 0)

		-- Задания дня.
		local list = if p ~= nil then p.quests else {}
		for k, row in questRows do
			local q = list[k]
			row.frame.Visible = q ~= nil
			if q ~= nil then
				row.name.Text = (if q.done then "✓ " else "")
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
			quests.accent.Text = ""
		else
			questsNote.Text = if p.questsBonus
				then t("menu.questsBonusDone")
				else string.format(t("menu.questsBonus"), Config.Quests.AllDoneTokens)
			quests.accent.Text = string.format(t("menu.questsNew"), math.max(0, p.dayLeft) // 3600)
		end

		-- Хаб (§15л ч.3): список матчей вместо «Сейчас на сервере».
		local hub = cs.place == "hub"
		-- §15л ч.5: в хабе за меню — показательная война, затемнение светлее.
		root.BackgroundTransparency = if hub or cs.demo then Config.Hub.ShadeAlpha else cfg.ShadeAlpha
		matchList.Visible = hub
		for _, g in { mapLabel, modeLabel, playersLabel, statusLabel, roster } :: { GuiObject } do
			g.Visible = not hub
		end
		if hub then
			phaseBar.frame.Visible = false
			hubCard(now)
		else
			-- Сервер: что идёт сейчас.
			local phase = cs.phase
			modeLabel.Text = string.format(t("menu.mode"), modeName())
			local humans: { string } = {}
			for _, n in cs.nations do
				if not n.isBot then
					table.insert(humans, if lang == "en" then n.nameEn else n.name)
				end
			end
			playersLabel.Text = string.format(t("menu.players"), #humans, math.max(cs.targetNations, #humans))
			roster.Text = table.concat(humans, " · ")
			roster.Visible = #humans > 0
			local left = math.max(0, math.ceil(cs.phaseEndsAt - now))
			if phase == "Play" then
				statusLabel.Text = string.format(t("menu.status.Play"), MenuKit.clock(ClientState.matchTime(cs, now)))
			elseif phase == "Waiting" then
				statusLabel.Text = t("menu.status.Waiting")
			else
				statusLabel.Text = string.format(Strings.get("menu.status." .. phase, lang), left)
			end
			server.accent.Text = if phase == "Play" then "● " .. t("menu.live") else ""
			phaseBar.frame.Visible = phase == "Lobby" or phase == "Pick" or phase == "Over"
			if phase == "Lobby" then
				phaseBar.set(1 - left / math.max(1, Config.Match.LobbySec))
			elseif phase == "Pick" then
				phaseBar.set(1 - left / math.max(1, Config.Match.StartPickSec))
			else
				phaseBar.set(0)
			end
			local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
			local watching = (phase == "Play" or phase == "Over") and (me == nil or not me.alive)
			-- §15л ч.7: за меню — показательный бой; матч начнётся по «В БОЙ».
			if cs.demo then
				watching = false
				statusLabel.Text = t("menu.status.demo")
				server.accent.Text = "● " .. t("menu.demo")
				modeLabel.Text = string.format(t("menu.mode"), Strings.get("mode.Ffa", lang))
				playersLabel.Text = t("menu.demoPlayers")
				roster.Visible = false
				phaseBar.frame.Visible = false
			end
			playButton.Text = "▶  " .. t(if watching then "menu.watch" else "menu.play")
			playHint.Text = if cs.demo
				then t("menu.demoHint")
				elseif watching then t("menu.watchHint")
				elseif phase == "Lobby" or phase == "Waiting" then t("menu.playHint")
				else ""
			playHint.Visible = playHint.Text ~= ""
		end

		-- Магазин.
		if p ~= nil then
			weeklyWhat.Text = act.rewardText(p.weekly.offer)
			weeklyLeft.Text = string.format(t("menu.weeklyLeft"), act.timeLeft(p.weekly.left))
			dailyLine.Text = string.format(t("menu.dailyStreak"), p.dailyStreak)
				.. "  ·  "
				.. string.format(t("menu.crates"), p.crates)
			shop.accent.Text = string.format(t("menu.tokens"), p.tokens)
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
