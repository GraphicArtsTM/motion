--!strict
--[[
	MainMenu — главное меню (§15ф «Ясный Фронтир», вместо трёх карточек §15л). Карта — на весь экран (за меню идёт
	показательный бой ботов), слева — штабная колонка, справа — задания дня и предложение недели.

	Штабная колонка (сверху вниз):
	- логотип и одна строка о том, что это за игра;
	- профиль: знак ступени «Пути командира», имя, ступень и уровень, полоса опыта, медали и жетоны (нажатие —
	  окно «Путь командира»);
	- «В БОЙ» — большая золотая кнопка, под ней одна строка: карта · режим · что идёт;
	- «Обучение · 5 минут» — пока обучение не пройдено;
	- хаб (cs.place == "hub"): список матчей (миниатюра, карта · режим, игроки и статус, «Войти» / «Смотреть») и
	  «Свой матч по коду» (создать / войти по коду);
	- навигация списком: Арсенал, Магазин, Гардероб, Путь командира, Как играть, Пригласить друзей, Звук
	  (у владельца частного сервера — ещё «Настройки сервера»).
	Узкий или низкий экран — колонка ужимается UIScale; правые карточки на узком экране прячутся.
	Окна (магазин, гардероб…) открываются в слое окон над меню.
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
	serverVisible: () -> boolean, -- «Настройки сервера» — только владельцу частного сервера в лобби
	rewardText: (reward: any) -> string, -- что в наборе (как в магазине)
	timeLeft: (sec: number) -> string, -- «N дн. N ч»
	onOpenChanged: (open: boolean) -> (),
	play: (serverId: string?) -> (), -- §15л ч.3: хаб — переход на сервер матча (nil — быстрый вход)
	join: () -> (), -- §15л ч.7: «как раньше» — вступить в матч (держава — только по «В БОЙ»)
	invite: () -> (), -- §15л ч.7: пригласить друзей (окно Roblox)
	privateCreate: () -> (), -- §15л ч.4: свой матч — новый сервер для друзей
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

local COLUMN_W = 440 -- штабная колонка
local SIDE_W = 340 -- карточки справа
local NAV_H = 54 -- строка навигации

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
	MenuKit.corner(f, 12)
	local s = MenuKit.stroke(f, Theme.Colors.Slate, 1)
	s.Transparency = 0.4
	return f
end

function MainMenu.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang, mapName: string, act: Actions): MainMenu
	local cfg = Config.Render.Menu
	local player = Players.LocalPlayer
	local function t(key: string): string
		return Strings.get(key, lang)
	end

	-- Затемнение карты: слева (под колонкой) темнее, справа — карта видна.
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
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.32, 0.25),
		NumberSequenceKeypoint.new(0.6, 0.75),
		NumberSequenceKeypoint.new(1, 0.55),
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

	-- Штабная колонка.
	local column = Instance.new("Frame")
	column.Name = "Column"
	column.BackgroundTransparency = 1
	column.Position = UDim2.fromOffset(32, 0)
	column.Size = UDim2.new(0, COLUMN_W, 1, 0)
	column.Parent = root
	local columnScale = Instance.new("UIScale")
	columnScale.Parent = column
	local columnList = MenuKit.list(column, 14)
	columnList.VerticalAlignment = Enum.VerticalAlignment.Center

	-- Логотип и строка «что за игра».
	local logoBox = MenuKit.box(column, "Logo", 1)
	if Config.Art.Logo ~= "" then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(Config.Art.LogoW, Config.Art.LogoH)
		img.Image = Config.Art.Logo
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = logoBox
	elseif Logo.new(logoBox, Config.Art.LogoScale) == nil then
		local l = MenuKit.label(logoBox, t("lobby.title"), 40, Theme.Colors.Gold, true)
		l.FontFace = Theme.FontHeavy
	end
	MenuKit.label(column, t("menu.tagline"), 15, Theme.Colors.Muted, false, 2)

	-- Профиль: знак ступени, имя, ступень и уровень, опыт, медали и жетоны.
	local profile = Instance.new("TextButton")
	profile.Name = "Profile"
	profile.Text = ""
	profile.AutoButtonColor = true
	profile.LayoutOrder = 3
	profile.BackgroundColor3 = Theme.Colors.PanelBg
	profile.BackgroundTransparency = 0.08
	profile.BorderSizePixel = 0
	profile.Size = UDim2.new(1, 0, 0, 92)
	profile.Parent = column
	MenuKit.corner(profile, 12)
	MenuKit.stroke(profile, Theme.Colors.Slate, 1).Transparency = 0.4
	local rankIcon = MenuKit.rankIcon(profile, 1, 4)
	rankIcon.Position = UDim2.fromOffset(16, 14)
	local who = Instance.new("Frame")
	who.BackgroundTransparency = 1
	who.Position = UDim2.fromOffset(96, 12)
	who.Size = UDim2.new(1, -112, 1, -24)
	who.Parent = profile
	MenuKit.list(who, 4)
	local nameLabel = MenuKit.label(who, player.DisplayName, 20, Theme.Colors.Text, true, 1)
	local rankLabel = MenuKit.label(who, "", 14, Theme.Colors.Gold, true, 2)
	local xpBar = MenuKit.bar(who, 6, Theme.Colors.Sky, 3)
	local wallet = MenuKit.label(who, "", 14, Theme.Colors.Muted, false, 4)
	Session.connect(profile.Activated, act.ranks)

	-- «В БОЙ» и строка о матче.
	local playBox = panel(column, "Play")
	playBox.LayoutOrder = 4
	MenuKit.pad(playBox, 16, 16)
	MenuKit.list(playBox, 10)
	local playButton = MenuKit.button(playBox, "", "primary", 76, 1)
	playButton.Name = "PlayButton"
	playButton.TextSize = 30
	playButton.FontFace = Theme.FontHeavy
	local matchLine = MenuKit.wrapLabel(playBox, "", 15, Theme.Colors.Text, 2)
	local playHint = MenuKit.wrapLabel(playBox, "", 13, Theme.Colors.Muted, 3)
	local tutorialButton = MenuKit.button(playBox, t("menu.tutorial"), "normal", 46, 4)
	tutorialButton.Name = "TutorialButton"
	tutorialButton.TextSize = 16

	-- Хаб: список матчей и «Свой матч по коду».
	local matchList = MenuKit.box(playBox, "Matches", 5)
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
	local thumbOf = MapThumb.new()
	local matchRows: { MatchRow } = {}
	for k = 1, Config.Places.ListMax do
		local row = Instance.new("Frame")
		row.Name = "Match" .. k
		row.LayoutOrder = k
		row.Size = UDim2.new(1, 0, 0, 56)
		row.BackgroundColor3 = Theme.Colors.Backdrop
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		row.Parent = matchList
		row:SetAttribute("FrontirStyled", true)
		MenuKit.corner(row, 8)
		local thumb = Instance.new("ImageLabel")
		thumb.Size = UDim2.fromOffset(MapThumbs.W * 2, MapThumbs.H * 2)
		thumb.AnchorPoint = Vector2.new(0, 0.5)
		thumb.Position = UDim2.new(0, 8, 0.5, 0)
		thumb.BackgroundColor3 = Theme.Colors.Backdrop
		thumb.BorderSizePixel = 0
		thumb.ResampleMode = Enum.ResamplerMode.Pixelated
		thumb.Parent = row
		MenuKit.corner(thumb, 4)
		local title = MenuKit.label(row, "", 15, Theme.Colors.Text, true)
		title.Position = UDim2.fromOffset(MapThumbs.W * 2 + 18, 8)
		local info = MenuKit.label(row, "", 12, Theme.Colors.Muted)
		info.Position = UDim2.fromOffset(MapThumbs.W * 2 + 18, 30)
		local go = MenuKit.button(row, "", "good", nil)
		go.AnchorPoint = Vector2.new(1, 0.5)
		go.Position = UDim2.new(1, -8, 0.5, 0)
		go.Size = UDim2.fromOffset(100, 40)
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

	local friends = MenuKit.box(playBox, "Friends", 6)
	friends.Size = UDim2.fromScale(1, 0)
	friends.AutomaticSize = Enum.AutomaticSize.Y
	MenuKit.list(friends, 6)
	friends.Visible = false
	MenuKit.label(friends, t("menu.friends"), 14, Theme.Colors.Sky, true, 1)
	local friendsRow = MenuKit.box(friends, "Row", 2)
	MenuKit.list(friendsRow, 8, true)
	local createButton = MenuKit.button(friendsRow, t("menu.privateCreate"), "normal", nil, 1)
	createButton.Size = UDim2.fromOffset(140, MenuKit.Touch)
	local codeBox = Instance.new("TextBox")
	codeBox.Name = "CodeBox"
	codeBox.LayoutOrder = 2
	codeBox.Size = UDim2.fromOffset(120, MenuKit.Touch)
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
	MenuKit.corner(codeBox, 8)
	MenuKit.stroke(codeBox, Theme.Colors.Slate, 1)
	local joinButton = MenuKit.button(friendsRow, t("menu.codeJoin"), "good", nil, 3)
	joinButton.Size = UDim2.fromOffset(110, MenuKit.Touch)
	Session.connect(codeBox:GetPropertyChangedSignal("Text"), function()
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

	-- Навигация: крупные строки «значок · название · что там».
	local nav = panel(column, "Nav")
	nav.LayoutOrder = 5
	MenuKit.pad(nav, 8, 8)
	MenuKit.list(nav, 2)
	local serverRow: TextButton? = nil
	local navDefs: { { key: string, icon: string, action: () -> () } } = {
		{ key = "arsenal", icon = "arsenal", action = act.arsenal },
		{ key = "shop", icon = "shop", action = act.shop },
		{ key = "wardrobe", icon = "wardrobe", action = act.wardrobe },
		{ key = "ranks", icon = "", action = act.ranks },
		{ key = "help", icon = "help", action = act.help },
		{ key = "invite", icon = "people", action = act.invite },
		{ key = "sound", icon = "sound", action = act.sound },
		{ key = "server", icon = "server", action = act.server },
	}
	local navRank: Frame? = nil
	for k, def in navDefs do
		local b = Instance.new("TextButton")
		b.Name = "Nav_" .. def.key
		b.Text = ""
		b.AutoButtonColor = false
		b.LayoutOrder = k
		b.Size = UDim2.new(1, 0, 0, NAV_H)
		b.BackgroundColor3 = Theme.Colors.Slate
		b.BackgroundTransparency = 1
		b.BorderSizePixel = 0
		b.Parent = nav
		b:SetAttribute("FrontirStyled", true)
		MenuKit.corner(b, 8)
		local icon = if def.icon == "" then MenuKit.rankIcon(b, 1, 2) else MenuKit.icon(b, def.icon, 4)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 10, 0.5, 0)
		if def.icon == "" then
			navRank = icon
		end
		local name = MenuKit.label(b, t("menu.nav." .. def.key), 17, Theme.Colors.Text, true)
		name.Position = UDim2.fromOffset(56, 7)
		local sub = MenuKit.label(b, t("menu.navSub." .. def.key), 12, Theme.Colors.Muted)
		sub.Position = UDim2.fromOffset(56, 30)
		local arrow = MenuKit.label(b, "›", 26, Theme.Colors.Muted, true)
		arrow.AnchorPoint = Vector2.new(1, 0.5)
		arrow.Position = UDim2.new(1, -12, 0.5, -2)
		-- Наведение — строка подсвечивается.
		Session.connect(b.MouseEnter, function()
			b.BackgroundTransparency = 0.55
			arrow.TextColor3 = Theme.Colors.Gold
		end)
		Session.connect(b.MouseLeave, function()
			b.BackgroundTransparency = 1
			arrow.TextColor3 = Theme.Colors.Muted
		end)
		Session.connect(b.Activated, def.action)
		if def.key == "server" then
			serverRow = b
		end
	end

	-- Справа: задания дня и предложение недели.
	local side = Instance.new("Frame")
	side.Name = "Side"
	side.BackgroundTransparency = 1
	side.AnchorPoint = Vector2.new(1, 0)
	side.Position = UDim2.new(1, -32, 0, 24)
	side.Size = UDim2.fromOffset(SIDE_W, 0)
	side.AutomaticSize = Enum.AutomaticSize.Y
	side.Parent = root
	local sideScale = Instance.new("UIScale")
	sideScale.Parent = side
	MenuKit.list(side, 12)

	local quests = panel(side, "Quests")
	quests.LayoutOrder = 1
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
		row.Size = UDim2.new(1, 0, 0, 46)
		row.BackgroundColor3 = Theme.Colors.Backdrop
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		row.Parent = quests
		row:SetAttribute("FrontirStyled", true)
		MenuKit.corner(row, 8)
		local name = MenuKit.label(row, "", 14, Theme.Colors.Text, false)
		name.Position = UDim2.fromOffset(10, 6)
		local reward = MenuKit.label(row, "", 13, Theme.Colors.Gold, true)
		reward.AnchorPoint = Vector2.new(1, 0)
		reward.Position = UDim2.new(1, -10, 0, 6)
		local barHost = Instance.new("Frame")
		barHost.BackgroundTransparency = 1
		barHost.Position = UDim2.fromOffset(10, 30)
		barHost.Size = UDim2.new(1, -80, 0, 6)
		barHost.Parent = row
		local bar = MenuKit.bar(barHost, 6, Theme.Colors.Sky)
		local count = MenuKit.label(row, "", 12, Theme.Colors.Muted, true)
		count.AnchorPoint = Vector2.new(1, 0)
		count.Position = UDim2.new(1, -10, 0, 25)
		table.insert(questRows, { frame = row, name = name, reward = reward, bar = bar, count = count })
	end
	local questsNote = MenuKit.wrapLabel(quests, "", 12, Theme.Colors.Muted, 10)

	local offer = panel(side, "Offer")
	offer.LayoutOrder = 2
	MenuKit.pad(offer, 16, 14)
	MenuKit.list(offer, 6)
	MenuKit.label(offer, t("menu.weekly"), 15, Theme.Colors.Gold, true, 1)
	local weeklyWhat = MenuKit.wrapLabel(offer, "", 14, Theme.Colors.Text, 2)
	local weeklyLeft = MenuKit.label(offer, "", 12, Theme.Colors.Muted, false, 3)
	local dailyLine = MenuKit.label(offer, "", 13, Theme.Colors.Muted, false, 4)
	local openShop = MenuKit.button(offer, t("menu.open"), "normal", 42, 5)
	Session.connect(openShop.Activated, act.shop)

	local function fit()
		local s = gui.AbsoluteSize
		local k = math.clamp(math.min(s.Y / cfg.ColumnHeightPx, s.X / cfg.MinWidthPx), 0.5, 1)
		columnScale.Scale = k
		sideScale.Scale = k
		-- Узкий экран: справа места нет — карточки прячем (задания есть и в окне «Задания»).
		side.Visible = s.X >= (COLUMN_W + SIDE_W + 120) * k
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
	Session.connect(tutorialButton.Activated, function()
		act.tutorial()
		setOpen(false)
	end)
	local function travelling(now: number): boolean
		return cs.travel == "going" and now - cs.travelAt < Config.Places.RetrySec
	end

	-- Режим: заданный (по очереди сервера) или лидер голосования.
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

	local function hubRows(now: number)
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
				local left = if e.phase ~= "Play"
					then math.max(0, e.left - (now - cs.serversAt))
					else e.left + (now - cs.serversAt)
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
	end

	local gold = Theme.Colors.Gold:ToHex()
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
		MenuKit.setRank(rankIcon, rank, 4)
		local nr = navRank
		if nr ~= nil then
			MenuKit.setRank(nr, rank, 2)
		end
		nameLabel.Text = player.DisplayName
		rankLabel.Text = Strings.get("rank." .. rank, lang) .. "  ·  " .. string.format(t("menu.level"), level)
		rankLabel.TextColor3 = Theme.color(Ranks.GroupColors[Ranks.group(rank)])
		xpBar.set(if p ~= nil and p.need > 0 then p.xp / p.need elseif p ~= nil then 1 else 0)
		wallet.Text = string.format(t("menu.medals"), Strings.formatInt(if p ~= nil then p.medals else 0))
			.. "     "
			.. string.format(t("menu.tokens"), if p ~= nil then p.tokens else 0)

		-- «В БОЙ» и строка о матче.
		local hub = cs.place == "hub"
		root.BackgroundTransparency = if hub or cs.demo then Config.Hub.ShadeAlpha else cfg.ShadeAlpha
		matchList.Visible = hub
		friends.Visible = hub
		local going = travelling(now)
		if hub then
			hubRows(now)
			matchLine.Text = string.format(t("menu.hubLine"), #cs.servers)
			playButton.Text = if going then t("menu.connecting") else "▶  " .. t("menu.play")
			playButton.Active = not going
			createButton.Active = not going
			joinButton.Active = not going and #codeBox.Text == Config.Places.CodeLength
			joinButton.BackgroundTransparency = if joinButton.Active then 0 else 0.5
			playHint.Text = if cs.travel == "failed" and cs.travelReason == "badCode"
				then t("menu.badCode")
				elseif cs.travel == "failed" then t("menu.travelFailed")
				elseif going then t("menu.connectingHint")
				else t("menu.quickHint")
			playHint.TextColor3 = if cs.travel == "failed" then Theme.Colors.Alert else Theme.Colors.Muted
		else
			local phase = cs.phase
			local humans = 0
			for _, n in cs.nations do
				if not n.isBot then
					humans += 1
				end
			end
			local left = math.max(0, math.ceil(cs.phaseEndsAt - now))
			local status = if cs.demo
				then t("menu.status.demo")
				elseif phase == "Play" then string.format(
					t("menu.status.Play"),
					MenuKit.clock(ClientState.matchTime(cs, now))
				)
				elseif phase == "Waiting" then t("menu.status.Waiting")
				else string.format(Strings.get("menu.status." .. phase, lang), left)
			local mode = if cs.demo then Strings.get("mode.Ffa", lang) else modeName()
			matchLine.Text = string.format(
				'<b>%s</b>  ·  %s  ·  <font color="#%s">%s</font>',
				Strings.get("map." .. mapName, lang),
				mode,
				gold,
				status
			)
			local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
			local watching = not cs.demo and (phase == "Play" or phase == "Over") and (me == nil or not me.alive)
			playButton.Text = "▶  " .. t(if watching then "menu.watch" else "menu.play")
			playHint.Text = if cs.demo
				then t("menu.demoHint")
				elseif watching then t("menu.watchHint")
				elseif humans > 0 and (phase == "Lobby" or phase == "Waiting") then t("menu.playHint")
				else ""
			playHint.TextColor3 = Theme.Colors.Muted
		end
		matchLine.RichText = true
		playHint.Visible = playHint.Text ~= ""
		tutorialButton.Visible = not hub
			and (p == nil or not p.tutorialDone)
			and (cs.demo or ((cs.phase == "Waiting" or cs.phase == "Lobby") and cs.myNation == nil))

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
		local sr = serverRow
		if sr ~= nil then
			sr.Visible = act.serverVisible()
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
