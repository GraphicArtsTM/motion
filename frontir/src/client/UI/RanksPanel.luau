--!strict
--[[
	RanksPanel — окно наград: вкладки «Путь командира» и «Боевой пропуск» (GDD §15щ Щ3 → §15э Э3).

	Строение (сверху вниз, одинаково на обеих вкладках):
	  1. Шапка — заголовок, кошелёк (медали, жетоны, ящики: сюда летят награды), «×».
	  2. Вкладки — «Путь командира» и «Боевой пропуск», у каждой красная метка «сколько ждёт».
	  3. Герой вкладки — где вы: погон и звание / сезон и ступень, полоса опыта, что дальше (или что даёт премиум).
	  4. Лента — путь: одна дорога наград по уровням 2…MaxLevel над линией прогресса с номерами; ниже — «Впереди»
	     (ближайшие вехи: техника, звания, генералы). Пропуск: две дороги — «БЕСПЛАТНО» над линией ступеней,
	     «ПРЕМИУМ» (золотая, под замком без покупки) под ней.
	  5. Низ — как идёт опыт, «ОТКРЫТЬ ПРЕМИУМ — R$ N» (пропуск без премиума) и «ЗАБРАТЬ ВСЁ (N)».

	Забрать — намерение pathClaim / seasonClaim, сервер выдаёт по порядку; событие pathClaimed / seasonClaimed →
	onClaimed: карточки подпрыгивают, лучи, значки летят в кошелёк, счётчики щёлкают; ступень звания — «НОВОЕ ЗВАНИЕ».
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Profile = require(Shared:WaitForChild("Profile"))
local Ranks = require(Shared:WaitForChild("Ranks"))
local Strings = require(Shared:WaitForChild("Strings"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local ShopPanel = require(script.Parent:WaitForChild("ShopPanel"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type RanksPanel = {
	toggle: () -> (),
	isOpen: () -> boolean,
	refresh: () -> (),
	-- pathClaimed: { got = { { level, reward } } }; seasonClaimed: { got = { { tier, premium, reward } } }
	onClaimed: (msg: any) -> (),
	pending: () -> number, -- сколько наград ждёт на пути и обеих дорогах пропуска (метка в меню)
	window: Frame,
}

local RanksPanel = {}

-- Размеры окна и частей (px до UiScale).
local W, H = 1040, 672
local BANNER = Config.Render.Banner.MaxPx -- высота картинки-шапки над окном
local PAD = 24
local HEADER_H, TABS_H = 64, 44
local TABS_Y = HEADER_H -- вкладки — сразу под шапкой
local HERO_Y, HERO_H = 118, 124
local TRACK_Y = 252
local FOOTER_H = 78
local CARD_W, GAP = 112, 10
local COL = CARD_W + GAP
local PATH_CARD_H, PASS_CARD_H = 172, 132
local CIRCLE = 30

-- Награда в одном виде для карточки (путь и обе дороги пропуска).
type View = {
	medals: number,
	tokens: number,
	crates: number,
	stock: { [string]: number },
	cosmetic: string?,
	unit: string?, -- §15э Э1: открывает технику
	title: string?, -- титул (последняя ступень премиума)
}

local function groupColor(rank: number): Color3
	return Theme.color(Ranks.GroupColors[Ranks.group(rank)])
end

local function viewOf(r: any): View
	return {
		medals = r.medals or 0,
		tokens = r.tokens or 0,
		crates = r.crates or 0,
		stock = r.stock or {},
		cosmetic = r.cosmetic,
		unit = r.unit,
		title = r.title,
	}
end

-- Титул, который даёт ступень пропуска (Cosmetics.Titles.seasonTier) — только премиум.
local function seasonTitle(tier: number): string?
	for _, it in Config.Cosmetics.Titles do
		if it.seasonTier == tier then
			return it.id
		end
	end
	return nil
end

function RanksPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> (),
	toast: ((string) -> ())?
): RanksPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local function unitName(key: string): string
		return if key == "Missile" then t("building.MissileSilo") else t("unit." .. key)
	end

	-- Главная часть награды: картинка (ключ ItemArt) или значок, и крупная подпись.
	local function mainPart(v: View): (string, string, boolean, string)
		if v.unit ~= nil then
			return "unit", "unlock." .. v.unit, true, unitName(v.unit)
		elseif v.title ~= nil then
			return "title", "title." .. v.title, true, string.format(t("path.titleItem"), t("title." .. v.title))
		elseif v.cosmetic ~= nil then
			local kind, id = string.match(v.cosmetic, "^(%a+):(%a+)$")
			return "cosmetic",
				(kind or "pattern") .. "." .. (id or ""),
				true,
				t("path.cosmetic." .. (kind or "pattern"))
		end
		for key, n in v.stock do
			if n > 0 then
				return "stock", "shop." .. key, true, t("shop." .. key)
			end
		end
		if v.crates > 0 and v.medals == 0 and v.tokens == 0 then
			return "crates", "arsenal", false, "+" .. v.crates
		elseif v.tokens > 0 and v.medals == 0 then
			return "tokens", "hint", false, "+" .. v.tokens
		end
		return "medals", "money", false, "+" .. Strings.formatInt(v.medals)
	end

	-- Мелкая строка под подписью: всё, что не вошло в главную часть.
	local function extras(v: View, main: string): string
		local out: { string } = {}
		if main ~= "medals" and v.medals > 0 then
			table.insert(out, "+" .. Strings.formatInt(v.medals))
		end
		if main ~= "crates" and v.crates > 0 then
			table.insert(out, string.format(t("path.crates"), v.crates))
		end
		if main ~= "tokens" and v.tokens > 0 then
			table.insert(out, string.format(t("path.tokens"), v.tokens))
		end
		if main == "unit" and v.cosmetic ~= nil then
			table.insert(out, t("path.cosmetic." .. (string.match(v.cosmetic, "^(%a+):") or "pattern")))
		end
		return table.concat(out, " · ")
	end

	---------------------------------------------------------------------------------------------------------------
	-- 0. Рамка окна.
	local window = Instance.new("Frame")
	window.Name = "RanksWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.new(0.5, 0, 0.5, BANNER / 2) -- над окном — картинка-шапка (SceneBanner)
	window.Size = UDim2.fromOffset(W, H)
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BorderSizePixel = 0
	window.Active = true
	window.Visible = false
	window.ClipsDescendants = false
	window.Parent = gui
	MenuKit.corner(window, Theme.CornerPx)
	MenuKit.stroke(window, Theme.Colors.PanelBorder, 2)
	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function fit()
		local s = UiScale.size(gui)
		scale.Scale = math.clamp(math.min((s.X - 24) / W, (s.Y - 24) / (H + BANNER)), 0.4, 1)
	end
	UiScale.onResize(gui, fit)
	fit()

	local function divider(y: number)
		local line = Instance.new("Frame")
		line.Name = "Divider"
		line.BackgroundColor3 = Theme.Colors.PanelBorder
		line.BorderSizePixel = 0
		line.Position = UDim2.fromOffset(PAD, y)
		line.Size = UDim2.new(1, -2 * PAD, 0, 1)
		line.Parent = window
	end

	---------------------------------------------------------------------------------------------------------------
	-- 1. Шапка: заголовок, кошелёк, «×».
	local title = MenuKit.label(window, t("path.windowTitle"), 28, Theme.Colors.Text, true)
	title.FontFace = Theme.FontHeavy
	title.Position = UDim2.fromOffset(PAD + 4, 16)
	local close = MenuKit.button(window, "×", "normal")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -PAD + 4, 0, 10)
	close.Size = UDim2.fromOffset(44, 44)

	type Wallet = { frame: Frame, label: TextLabel, value: number }
	local wallet: { [string]: Wallet } = {}
	for k, kind in { "medals", "tokens", "crates" } do
		local chip = Instance.new("Frame")
		chip.Name = "Wallet_" .. kind
		chip.AnchorPoint = Vector2.new(1, 0)
		chip.Position = UDim2.new(1, -PAD - 56 - (3 - k) * 128, 0, 13)
		chip.Size = UDim2.fromOffset(120, 38)
		chip.BackgroundColor3 = Theme.Colors.Backdrop
		chip.BorderSizePixel = 0
		chip.Parent = window
		MenuKit.corner(chip, 8)
		MenuKit.stroke(chip, Theme.Colors.Gold, 1)
		local icon =
			MenuKit.icon(chip, if kind == "medals" then "money" elseif kind == "tokens" then "hint" else "arsenal", 3)
		icon.Position = UDim2.fromOffset(8, 7)
		local label = MenuKit.label(chip, "0", 18, Theme.Colors.Gold, true)
		label.AnchorPoint = Vector2.new(1, 0.5)
		label.Position = UDim2.new(1, -10, 0.5, 0)
		label.TextXAlignment = Enum.TextXAlignment.Right
		wallet[kind] = { frame = chip, label = label, value = 0 }
	end

	---------------------------------------------------------------------------------------------------------------
	-- 2. Вкладки.
	type TabKey = "path" | "pass"
	local current: TabKey = "path"
	type Tab = { button: TextButton, stroke: UIStroke, badge: TextLabel, page: Frame }
	local tabs: { [string]: Tab } = {}
	local tabOrder: { TabKey } = { "path" :: TabKey, "pass" :: TabKey }
	local switchTab: (key: TabKey) -> ()
	for k, key in tabOrder do
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. key
		b.AutoButtonColor = true
		b.Position = UDim2.fromOffset(PAD + (k - 1) * 236, TABS_Y)
		b.Size = UDim2.fromOffset(224, TABS_H - 6)
		b.BackgroundColor3 = Theme.Colors.Backdrop
		b.BorderSizePixel = 0
		b.FontFace = Theme.FontBold
		b.TextSize = 17
		b.TextColor3 = Theme.Colors.Text
		b.Text = t(if key == "path" then "path.tabPath" else "path.tabPass")
		b.Parent = window
		MenuKit.corner(b, 8)
		local stroke = MenuKit.stroke(b, Theme.Colors.PanelBorder, 2)
		local badge = MenuKit.label(b, "", 13, Theme.color("White"), true)
		badge.Name = "Badge"
		badge.AnchorPoint = Vector2.new(1, 0.5)
		badge.Position = UDim2.new(1, -8, 0.5, 0)
		badge.AutomaticSize = Enum.AutomaticSize.None
		badge.Size = UDim2.fromOffset(28, 22)
		badge.TextXAlignment = Enum.TextXAlignment.Center
		badge.BackgroundColor3 = Theme.Colors.Alert
		badge.BackgroundTransparency = 0
		badge.Visible = false
		MenuKit.corner(badge, 11)
		local page = Instance.new("Frame")
		page.Name = "Page_" .. key
		page.BackgroundTransparency = 1
		page.Size = UDim2.fromScale(1, 1)
		page.Visible = key == current
		page.Parent = window
		tabs[key] = { button = b, stroke = stroke, badge = badge, page = page }
		local tabKey: TabKey = key :: TabKey
		Session.connect(b.Activated, function()
			switchTab(tabKey)
		end)
	end
	divider(TABS_Y + TABS_H + 2)

	---------------------------------------------------------------------------------------------------------------
	-- Общее: карточка награды, лента с линией прогресса.
	type Card = {
		frame: Frame,
		pop: UIScale,
		stroke: UIStroke,
		art: GuiObject,
		amount: TextLabel,
		more: TextLabel,
		state: TextLabel,
		claim: TextButton,
		lock: TextLabel?,
	}
	local busy = false
	local function requestClaim(intent: string)
		if busy then
			return
		end
		busy = true
		send(intent, {})
		task.delay(3, function()
			busy = false -- ответ не пришёл — кнопку снова можно нажать
		end)
	end

	local function makeCard(
		parent: Instance,
		x: number,
		y: number,
		h: number,
		v: View,
		intent: string,
		gold: boolean
	): Card
		local f = Instance.new("Frame")
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(CARD_W, h)
		f.BackgroundColor3 = if gold then Theme.color("Night") else Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.Parent = parent
		MenuKit.corner(f, 10)
		local stroke = MenuKit.stroke(f, if gold then Theme.Colors.Gold else Theme.Colors.PanelBorder, 2)
		local pop = Instance.new("UIScale")
		pop.Parent = f
		local y0 = h - PASS_CARD_H -- путь: сверху место под погон ступени звания
		local main, key, isArt, text = mainPart(v)
		local art: GuiObject
		if isArt then
			art = CardKit.art(f, key, 88, 58)
			art.Position = UDim2.fromOffset(12, y0 + 6)
		else
			art = MenuKit.icon(f, key, 5) -- 40 px
			art.Position = UDim2.fromOffset(36, y0 + 14)
		end
		local amount = MenuKit.label(f, text, 14, Theme.Colors.Text, true)
		amount.AutomaticSize = Enum.AutomaticSize.None
		amount.Size = UDim2.new(1, -8, 0, 18)
		amount.Position = UDim2.fromOffset(4, y0 + 68)
		amount.TextXAlignment = Enum.TextXAlignment.Center
		amount.TextTruncate = Enum.TextTruncate.AtEnd
		local more = MenuKit.label(f, extras(v, main), 11, Theme.Colors.Gold, true)
		more.AutomaticSize = Enum.AutomaticSize.None
		more.Size = UDim2.new(1, -8, 0, 14)
		more.Position = UDim2.fromOffset(4, y0 + 86)
		more.TextXAlignment = Enum.TextXAlignment.Center
		more.TextTruncate = Enum.TextTruncate.AtEnd
		local state = MenuKit.label(f, "", 12, Theme.Colors.Muted, true)
		state.AutomaticSize = Enum.AutomaticSize.None
		state.Size = UDim2.new(1, -8, 0, 26)
		state.Position = UDim2.fromOffset(4, h - 32)
		state.TextXAlignment = Enum.TextXAlignment.Center
		local claim = MenuKit.button(f, t("path.claim"), "primary", 26)
		claim.Size = UDim2.new(1, -16, 0, 26)
		claim.Position = UDim2.fromOffset(8, h - 32)
		claim.TextSize = 13
		claim.Visible = false
		Session.connect(claim.Activated, function()
			requestClaim(intent)
		end)
		local lock: TextLabel? = nil
		if gold then
			local l = MenuKit.label(f, "🔒", 16, Theme.Colors.Gold, true)
			l.AnchorPoint = Vector2.new(1, 0)
			l.Position = UDim2.new(1, -6, 0, y0 + 4)
			l.ZIndex = 3
			lock = l
		end
		return {
			frame = f,
			pop = pop,
			stroke = stroke,
			art = art,
			amount = amount,
			more = more,
			state = state,
			claim = claim,
			lock = lock,
		}
	end

	-- Лента: прокрутка по X; линия прогресса с кружками номеров на высоте lineY.
	type Track = {
		scroll: ScrollingFrame,
		canvas: Frame,
		fill: Frame,
		circles: { TextLabel },
		width: number,
	}
	local function makeTrack(
		parent: Instance,
		x: number,
		y: number,
		w: number,
		h: number,
		count: number,
		lineY: number,
		firstNumber: number
	): Track
		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "Track"
		scroll.Position = UDim2.fromOffset(x, y)
		scroll.Size = UDim2.fromOffset(w, h)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollingDirection = Enum.ScrollingDirection.X
		scroll.ScrollBarThickness = 6
		scroll.ScrollBarImageColor3 = Theme.Colors.Gold
		scroll.ElasticBehavior = Enum.ElasticBehavior.Never
		scroll.Parent = parent
		local width = 8 + count * COL - GAP + 8
		scroll.CanvasSize = UDim2.fromOffset(width, h - 10)
		local canvas = Instance.new("Frame")
		canvas.Name = "Canvas"
		canvas.BackgroundTransparency = 1
		canvas.Size = UDim2.fromOffset(width, h - 10)
		canvas.Parent = scroll
		local line = Instance.new("Frame")
		line.Name = "Line"
		line.BackgroundColor3 = Theme.Colors.Slate
		line.BorderSizePixel = 0
		line.Position = UDim2.fromOffset(8, lineY - 3)
		line.Size = UDim2.fromOffset(width - 16, 6)
		line.Parent = canvas
		MenuKit.corner(line, 3)
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = Theme.Colors.Gold
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromOffset(0, 6)
		fill.Parent = line
		MenuKit.corner(fill, 3)
		local circles: { TextLabel } = {}
		for i = 1, count do
			local c = MenuKit.label(canvas, tostring(firstNumber + i - 1), 13, Theme.Colors.Text, true)
			c.Name = "Step" .. i
			c.AnchorPoint = Vector2.new(0.5, 0.5)
			c.AutomaticSize = Enum.AutomaticSize.None
			c.Size = UDim2.fromOffset(CIRCLE, CIRCLE)
			c.Position = UDim2.fromOffset(8 + (i - 1) * COL + CARD_W / 2, lineY)
			c.TextXAlignment = Enum.TextXAlignment.Center
			c.BackgroundTransparency = 0
			c.BackgroundColor3 = Theme.Colors.Slate
			c.ZIndex = 2
			MenuKit.corner(c, CIRCLE // 2)
			MenuKit.stroke(c, Theme.color("Ink"), 2)
			circles[i] = c
		end
		return { scroll = scroll, canvas = canvas, fill = fill, circles = circles, width = width }
	end

	local function colX(i: number): number
		return 8 + (i - 1) * COL
	end

	-- Линия: закрашено до центра пройденного столбца и доля пути к следующему; кружки — пройдено / следующий.
	local function paintTrack(tr: Track, reachedIndex: number, frac: number)
		local count = #tr.circles
		local cx = if reachedIndex <= 0
			then 0
			else (reachedIndex - 1) * COL + CARD_W / 2 + (if reachedIndex < count then COL * frac else 0)
		tr.fill.Size = UDim2.fromOffset(math.clamp(cx, 0, tr.width - 16), 6)
		for i, c in tr.circles do
			local reached = i <= reachedIndex
			c.BackgroundColor3 = if reached
				then Theme.Colors.Gold
				elseif i == reachedIndex + 1 then Theme.Colors.Sky
				else Theme.Colors.Slate
			c.TextColor3 = if reached or i == reachedIndex + 1 then Theme.color("Ink") else Theme.Colors.Muted
		end
	end

	local function scrollTo(tr: Track, index: number)
		local x = colX(index) + CARD_W / 2
		local viewW = tr.scroll.Size.X.Offset
		tr.scroll.CanvasPosition = Vector2.new(math.clamp(x - viewW / 2, 0, math.max(0, tr.width - viewW)), 0)
	end

	-- Состояние карточки: закрыто / готово / получено (и замок премиума).
	local function paintCard(c: Card, reached: boolean, done: boolean, locked: boolean, isNext: boolean, edge: Color3?)
		local ready = reached and not done and not locked
		c.claim.Visible = ready
		c.state.Visible = not ready
		c.state.Text = if done then "✔ " .. t("path.claimed") elseif locked then t("pass.locked") else "🔒"
		c.state.TextColor3 = if done
			then Theme.color("Lime")
			elseif locked then Theme.Colors.Gold
			else Theme.Colors.Muted
		c.stroke.Color = if ready
			then Theme.Colors.Gold
			elseif isNext then Theme.Colors.Sky
			else edge or Theme.Colors.PanelBorder
		c.stroke.Thickness = if ready then 3 else 2
		c.frame.BackgroundTransparency = if reached and not locked then 0 else 0.35
		c.amount.TextColor3 = if reached and not locked then Theme.Colors.Text else Theme.Colors.Muted
		if c.art:IsA("ImageLabel") then
			c.art.ImageTransparency = if reached and not locked then 0 else 0.45
		end
		local lock = c.lock
		if lock ~= nil then
			lock.Visible = locked
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- 3–4. Вкладка «Путь командира».
	local pathPage = tabs.path.page
	local pathHero = Instance.new("Frame")
	pathHero.Name = "Hero"
	pathHero.Position = UDim2.fromOffset(PAD, HERO_Y)
	pathHero.Size = UDim2.new(1, -2 * PAD, 0, HERO_H)
	pathHero.BackgroundColor3 = Theme.Colors.Backdrop
	pathHero.BorderSizePixel = 0
	pathHero.Parent = pathPage
	MenuKit.corner(pathHero, 12)
	local pathHeroStroke = MenuKit.stroke(pathHero, Theme.Colors.PanelBorder, 2)
	local bigRank = MenuKit.rankIcon(pathHero, 1, 7) -- 112 px
	bigRank.Position = UDim2.fromOffset(14, 6)
	local nowLabel = MenuKit.label(pathHero, t("ranks.now"), 12, Theme.Colors.Sky, true)
	nowLabel.Position = UDim2.fromOffset(146, 12)
	local rankName = MenuKit.label(pathHero, "", 28, Theme.Colors.Text, true)
	rankName.FontFace = Theme.FontHeavy
	rankName.Position = UDim2.fromOffset(146, 28)
	local levelLine = MenuKit.label(pathHero, "", 15, Theme.Colors.Text)
	levelLine.Position = UDim2.fromOffset(146, 62)
	local xpHost = Instance.new("Frame")
	xpHost.BackgroundTransparency = 1
	xpHost.Position = UDim2.fromOffset(146, 86)
	xpHost.Size = UDim2.fromOffset(380, 12)
	xpHost.Parent = pathHero
	local xpBar = MenuKit.bar(xpHost, 12, Theme.Colors.Sky)
	local xpText = MenuKit.label(pathHero, "", 13, Theme.Colors.Muted)
	xpText.Position = UDim2.fromOffset(146, 101)
	-- Справа в герое — следующее звание.
	local nextBox = Instance.new("Frame")
	nextBox.Name = "Next"
	nextBox.AnchorPoint = Vector2.new(1, 0)
	nextBox.Position = UDim2.new(1, -12, 0, 12)
	nextBox.Size = UDim2.fromOffset(360, HERO_H - 24)
	nextBox.BackgroundColor3 = Theme.Colors.PanelBg
	nextBox.BorderSizePixel = 0
	nextBox.Parent = pathHero
	MenuKit.corner(nextBox, 10)
	MenuKit.stroke(nextBox, Theme.Colors.PanelBorder, 1)
	local nextIcon = MenuKit.rankIcon(nextBox, 2, 4) -- 64 px
	nextIcon.Position = UDim2.fromOffset(14, 18)
	local nextTitle = MenuKit.label(nextBox, t("ranks.next"), 12, Theme.Colors.Sky, true)
	nextTitle.Position = UDim2.fromOffset(92, 14)
	local nextName = MenuKit.label(nextBox, "", 18, Theme.Colors.Text, true)
	nextName.Position = UDim2.fromOffset(92, 32)
	local nextWhen = MenuKit.label(nextBox, "", 13, Theme.Colors.Gold)
	nextWhen.Position = UDim2.fromOffset(92, 58)

	-- Генерал по уровню (§11.2), ступени званий.
	local generalAt: { [number]: string } = {}
	for id, lv in Config.Profile.CommanderLevels :: { [string]: number } do
		if lv > 1 then
			generalAt[lv] = id
		end
	end
	local tierAt: { [number]: number } = {}
	for k, lv in Config.Ranks.Tiers do
		tierAt[lv] = k
	end

	local PATH_FIRST, PATH_LAST = 2, Config.Profile.MaxLevel
	local pathCount = PATH_LAST - PATH_FIRST + 1
	local pathLineY = 4 + PATH_CARD_H + 22
	local pathTrack =
		makeTrack(pathPage, PAD, TRACK_Y, W - 2 * PAD, pathLineY + CIRCLE // 2 + 14, pathCount, pathLineY, PATH_FIRST)
	local pathCards: { [number]: Card } = {}
	for lv = PATH_FIRST, PATH_LAST do
		local i = lv - PATH_FIRST + 1
		local v = viewOf(Profile.pathReward(lv))
		local card = makeCard(pathTrack.canvas, colX(i), 4, PATH_CARD_H, v, "pathClaim", false)
		card.frame.Name = "Level" .. lv
		-- Верх карточки: погон ступени звания или генерал.
		local tier = tierAt[lv]
		if tier ~= nil then
			local ep = MenuKit.rankIcon(card.frame, tier, 2)
			ep.Position = UDim2.fromOffset(8, 6)
			local rn = MenuKit.label(card.frame, t("rank." .. tier), 11, groupColor(tier), true)
			rn.AutomaticSize = Enum.AutomaticSize.None
			rn.Position = UDim2.fromOffset(44, 8)
			rn.Size = UDim2.fromOffset(CARD_W - 50, 28)
			rn.TextWrapped = true
			rn.TextYAlignment = Enum.TextYAlignment.Top
		elseif generalAt[lv] ~= nil then
			local gn = MenuKit.label(
				card.frame,
				string.format(t("path.general"), t("commander." .. generalAt[lv])),
				11,
				Theme.Colors.Sky,
				true
			)
			gn.AutomaticSize = Enum.AutomaticSize.None
			gn.Position = UDim2.fromOffset(6, 8)
			gn.Size = UDim2.fromOffset(CARD_W - 12, 28)
			gn.TextWrapped = true
			gn.TextYAlignment = Enum.TextYAlignment.Top
		else
			local lvl = MenuKit.label(card.frame, string.format(t("ranks.level"), lv), 12, Theme.Colors.Muted, true)
			lvl.Position = UDim2.fromOffset(8, 10)
		end
		pathCards[lv] = card
	end

	-- «Впереди»: ближайшие вехи пути (техника, звания, генералы).
	local aheadY = TRACK_Y + pathLineY + CIRCLE // 2 + 22
	local aheadLabel = MenuKit.label(pathPage, t("path.ahead"), 13, Theme.Colors.Sky, true)
	aheadLabel.Position = UDim2.fromOffset(PAD + 4, aheadY + 4)
	local aheadRow = Instance.new("Frame")
	aheadRow.Name = "Ahead"
	aheadRow.BackgroundTransparency = 1
	aheadRow.Position = UDim2.fromOffset(PAD, aheadY + 24)
	aheadRow.Size = UDim2.new(1, -2 * PAD, 0, 64)
	aheadRow.Parent = pathPage
	MenuKit.list(aheadRow, 10, true)
	local AHEAD = 5
	type Chip = { frame: Frame, art: Frame, level: TextLabel, name: TextLabel }
	local aheadChips: { Chip } = {}
	for k = 1, AHEAD do
		local f = Instance.new("Frame")
		f.Name = "Milestone" .. k
		f.LayoutOrder = k
		f.Size = UDim2.fromOffset(((W - 2 * PAD) - (AHEAD - 1) * 10) // AHEAD, 60)
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.Parent = aheadRow
		MenuKit.corner(f, 8)
		MenuKit.stroke(f, Theme.Colors.PanelBorder, 1)
		local host = Instance.new("Frame")
		host.BackgroundTransparency = 1
		host.Position = UDim2.fromOffset(6, 6)
		host.Size = UDim2.fromOffset(72, 48)
		host.Parent = f
		local lvl = MenuKit.label(f, "", 13, Theme.Colors.Gold, true)
		lvl.Position = UDim2.fromOffset(84, 8)
		local name = MenuKit.label(f, "", 13, Theme.Colors.Text, true)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.Position = UDim2.fromOffset(84, 26)
		name.Size = UDim2.new(1, -90, 0, 30)
		name.TextWrapped = true
		name.TextYAlignment = Enum.TextYAlignment.Top
		aheadChips[k] = { frame = f, art = host, level = lvl, name = name }
	end

	---------------------------------------------------------------------------------------------------------------
	-- 3–4. Вкладка «Боевой пропуск».
	local passPage = tabs.pass.page
	local passHero = Instance.new("Frame")
	passHero.Name = "Hero"
	passHero.Position = UDim2.fromOffset(PAD, HERO_Y)
	passHero.Size = UDim2.new(1, -2 * PAD, 0, HERO_H)
	passHero.BackgroundColor3 = Theme.Colors.Backdrop
	passHero.BorderSizePixel = 0
	passHero.Parent = passPage
	MenuKit.corner(passHero, 12)
	local passHeroStroke = MenuKit.stroke(passHero, Theme.Colors.PanelBorder, 2)
	local seasonArt = CardKit.art(passHero, "shop.SeasonPass", 150, 100)
	seasonArt.Position = UDim2.fromOffset(12, 12)
	local seasonLabel =
		MenuKit.label(passHero, string.format(t("pass.season"), Config.Season.Id), 12, Theme.Colors.Sky, true)
	seasonLabel.Position = UDim2.fromOffset(178, 12)
	local tierLine = MenuKit.label(passHero, "", 28, Theme.Colors.Text, true)
	tierLine.FontFace = Theme.FontHeavy
	tierLine.Position = UDim2.fromOffset(178, 28)
	local tierHost = Instance.new("Frame")
	tierHost.BackgroundTransparency = 1
	tierHost.Position = UDim2.fromOffset(178, 68)
	tierHost.Size = UDim2.fromOffset(340, 12)
	tierHost.Parent = passHero
	local tierBar = MenuKit.bar(tierHost, 12, Theme.Colors.Gold)
	local tierXp = MenuKit.label(passHero, "", 13, Theme.Colors.Muted)
	tierXp.Position = UDim2.fromOffset(178, 84)
	local seasonEnd = MenuKit.label(passHero, "", 12, Theme.Colors.Muted)
	seasonEnd.Position = UDim2.fromOffset(178, 102)
	-- Справа — что даёт премиум (или «премиум активен»).
	local premBox = Instance.new("Frame")
	premBox.Name = "Premium"
	premBox.AnchorPoint = Vector2.new(1, 0)
	premBox.Position = UDim2.new(1, -12, 0, 12)
	premBox.Size = UDim2.fromOffset(400, HERO_H - 24)
	premBox.BackgroundColor3 = Theme.color("Night")
	premBox.BorderSizePixel = 0
	premBox.Parent = passHero
	MenuKit.corner(premBox, 10)
	MenuKit.stroke(premBox, Theme.Colors.Gold, 2)
	local premHead = MenuKit.label(premBox, "", 16, Theme.Colors.Gold, true)
	premHead.FontFace = Theme.FontHeavy
	premHead.Position = UDim2.fromOffset(14, 10)
	local premBody = MenuKit.label(premBox, "", 13, Theme.Colors.Text)
	premBody.AutomaticSize = Enum.AutomaticSize.None
	premBody.Position = UDim2.fromOffset(14, 34)
	premBody.Size = UDim2.new(1, -28, 0, 56)
	premBody.TextWrapped = true
	premBody.TextYAlignment = Enum.TextYAlignment.Top

	-- Итоги дорог за сезон (для «премиум даёт»).
	type Total = { medals: number, crates: number, tokens: number, stock: number }
	local function total(premium: boolean): Total
		local sum: Total = { medals = 0, crates = 0, tokens = 0, stock = 0 }
		for tier = 1, Config.Season.Tiers do
			local r = Profile.seasonReward(tier, premium)
			sum.medals += r.medals
			sum.crates += r.crates
			sum.tokens += r.tokens
			for _, n in r.stock do
				sum.stock += n
			end
		end
		return sum
	end
	local freeTotal, paidTotal = total(false), total(true)

	-- Подписи дорог слева (не прокручиваются).
	local LANE_W = 118
	local passLineY = 4 + PASS_CARD_H + 20
	local premiumY = passLineY + 20
	local passH = premiumY + PASS_CARD_H + 14
	local function laneLabel(y: number, text: string, color: Color3, gold: boolean): (Frame, TextLabel)
		local f = Instance.new("Frame")
		f.Name = "Lane"
		f.Position = UDim2.fromOffset(PAD, TRACK_Y + y)
		f.Size = UDim2.fromOffset(LANE_W - 10, PASS_CARD_H)
		f.BackgroundColor3 = if gold then Theme.color("Night") else Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.Parent = passPage
		MenuKit.corner(f, 10)
		MenuKit.stroke(f, color, 2)
		local l = MenuKit.label(f, text, 15, color, true)
		l.FontFace = Theme.FontHeavy
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(0.5, 0, 0, 18)
		local sub = MenuKit.label(f, "", 12, Theme.Colors.Muted, true)
		sub.AutomaticSize = Enum.AutomaticSize.None
		sub.AnchorPoint = Vector2.new(0.5, 0)
		sub.Position = UDim2.new(0.5, 0, 0, 46)
		sub.Size = UDim2.new(1, -12, 0, 70)
		sub.TextWrapped = true
		sub.TextXAlignment = Enum.TextXAlignment.Center
		sub.TextYAlignment = Enum.TextYAlignment.Top
		return f, sub
	end
	local _, freeSub = laneLabel(4, t("pass.free"), Theme.Colors.Sky, false)
	local _, paidSub = laneLabel(premiumY, t("pass.premium"), Theme.Colors.Gold, true)
	local passTrack =
		makeTrack(passPage, PAD + LANE_W, TRACK_Y, W - 2 * PAD - LANE_W, passH, Config.Season.Tiers, passLineY, 1)
	local freeCards: { [number]: Card } = {}
	local paidCards: { [number]: Card } = {}
	for tier = 1, Config.Season.Tiers do
		local fv = viewOf(Profile.seasonReward(tier, false))
		freeCards[tier] = makeCard(passTrack.canvas, colX(tier), 4, PASS_CARD_H, fv, "seasonClaim", false)
		freeCards[tier].frame.Name = "Free" .. tier
		local pv = viewOf(Profile.seasonReward(tier, true))
		pv.title = seasonTitle(tier)
		paidCards[tier] = makeCard(passTrack.canvas, colX(tier), premiumY, PASS_CARD_H, pv, "seasonClaim", true)
		paidCards[tier].frame.Name = "Premium" .. tier
	end

	---------------------------------------------------------------------------------------------------------------
	-- 5. Низ: как идёт опыт, «ОТКРЫТЬ ПРЕМИУМ», «ЗАБРАТЬ ВСЁ».
	divider(H - FOOTER_H - 6)
	local how = MenuKit.wrapLabel(window, "", 13, Theme.Colors.Muted)
	how.Position = UDim2.fromOffset(PAD + 4, H - FOOTER_H + 8)
	local buyPremium = MenuKit.button(window, "", "good", 50)
	buyPremium.AnchorPoint = Vector2.new(1, 1)
	buyPremium.Position = UDim2.new(1, -PAD - 280, 1, -16)
	buyPremium.Size = UDim2.fromOffset(300, 50)
	buyPremium.TextSize = 17
	local claimAll = MenuKit.button(window, "", "primary", 50)
	claimAll.AnchorPoint = Vector2.new(1, 1)
	claimAll.Position = UDim2.new(1, -PAD, 1, -16)
	claimAll.Size = UDim2.fromOffset(268, 50)
	claimAll.TextSize = 18
	local claimGlow = MenuKit.stroke(claimAll, Theme.Colors.Gold, 3)
	Session.connect(claimAll.Activated, function()
		requestClaim(if current == "path" then "pathClaim" else "seasonClaim")
	end)
	Session.connect(buyPremium.Activated, function()
		local id = Config.Shop.Packs.SeasonPass.id
		if id == 0 then
			if toast ~= nil then
				toast(t("shop.soon"))
			end
			return
		end
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, id)
	end)

	-- Слой анимаций поверх окна (летящие значки, лучи, «НОВОЕ ЗВАНИЕ»).
	local fx = Instance.new("Frame")
	fx.Name = "Fx"
	fx.BackgroundTransparency = 1
	fx.Size = UDim2.fromScale(1, 1)
	fx.ZIndex = 50
	fx.Parent = window

	---------------------------------------------------------------------------------------------------------------
	-- Рисование.
	local function level(): (number, number, number)
		local p = cs.profile
		if p == nil then
			return 1, 0, Profile.xpNeeded(1)
		end
		return p.level, p.xp, p.need
	end
	local function pending(): number
		local path, free, paid = ClientState.rewardsPending(cs)
		return path + free + paid
	end
	local function setWallet(kind: string, value: number)
		local w = wallet[kind]
		w.value = value
		w.label.Text = Strings.formatInt(value)
	end
	local function setBadge(tab: Tab, n: number)
		tab.badge.Visible = n > 0
		tab.badge.Text = if n > 99 then "99+" else tostring(n)
	end

	local scrolled: { [string]: number } = {}

	local function drawAhead(lv: number)
		local k = 0
		for l = lv + 1, PATH_LAST do
			if k >= AHEAD then
				break
			end
			local r = Profile.pathReward(l)
			local tier = tierAt[l]
			local general = generalAt[l]
			if r.unit == nil and tier == nil and general == nil then
				continue
			end
			k += 1
			local chip = aheadChips[k]
			chip.frame.Visible = true
			for _, child in chip.art:GetChildren() do
				child:Destroy()
			end
			if r.unit ~= nil then
				CardKit.art(chip.art, "unlock." .. r.unit, 72, 48)
				chip.name.Text = string.format(t("path.opensUnit"), unitName(r.unit))
				chip.name.TextColor3 = Theme.Colors.Gold
			elseif tier ~= nil then
				local ep = MenuKit.rankIcon(chip.art, tier, 3)
				ep.Position = UDim2.fromOffset(12, 0)
				chip.name.Text = string.format(t("path.rankAt"), t("rank." .. tier))
				chip.name.TextColor3 = groupColor(tier)
			else
				local icon = MenuKit.icon(chip.art, "army", 5)
				icon.Position = UDim2.fromOffset(16, 4)
				chip.name.Text = string.format(t("path.general"), t("commander." .. (general :: string)))
				chip.name.TextColor3 = Theme.Colors.Sky
			end
			chip.level.Text = string.format(t("ranks.levelLeft"), l, l - lv)
		end
		for j = k + 1, AHEAD do
			aheadChips[j].frame.Visible = false
		end
	end

	local function drawPath()
		local lv, into, need = level()
		local rank = Ranks.of(lv)
		local p = cs.profile
		local claimed = if p ~= nil and p.path ~= nil then p.path.claimed else lv
		MenuKit.setRank(bigRank, rank, 7)
		rankName.Text = t("rank." .. rank)
		rankName.TextColor3 = groupColor(rank)
		pathHeroStroke.Color = groupColor(rank)
		levelLine.Text = string.format(t("ranks.levelLine"), lv, t("rank.troops." .. rank))
		if need > 0 then
			xpBar.set(into / need)
			xpText.Text = string.format(t("ranks.xp"), into, need, lv + 1)
		else
			xpBar.set(1)
			xpText.Text = t("menu.maxLevel")
		end
		local nextAt = Ranks.nextAt(lv)
		nextBox.Visible = nextAt ~= nil
		if nextAt ~= nil then
			MenuKit.setRank(nextIcon, rank + 1, 4)
			nextName.Text = t("rank." .. (rank + 1))
			nextName.TextColor3 = groupColor(rank + 1)
			nextWhen.Text = string.format(t("ranks.nextWhen"), nextAt, nextAt - lv)
		end
		for l, card in pathCards do
			local edge = if tierAt[l] ~= nil then groupColor(tierAt[l]) else nil
			paintCard(card, l <= lv, l <= claimed, false, l == lv + 1, edge)
		end
		paintTrack(pathTrack, lv - PATH_FIRST + 1, if need > 0 then into / need else 0)
		drawAhead(lv)
		local n = math.max(0, lv - claimed)
		local focus = math.clamp(if n > 0 then claimed + 1 else lv + 1, PATH_FIRST, PATH_LAST)
		if scrolled.path ~= focus then
			scrolled.path = focus
			scrollTo(pathTrack, focus - PATH_FIRST + 1)
		end
	end

	local function drawPass()
		local p = cs.profile
		local s = if p ~= nil
			then p.season
			else {
				tier = 0,
				xp = 0,
				per = Config.Season.XpPerTier,
				premium = false,
				free = 0,
				paid = 0,
				left = nil,
			}
		local tiers = Config.Season.Tiers
		local freeDone = s.free or s.tier
		local paidDone = s.paid or s.tier
		tierLine.Text = string.format(t("pass.tier"), s.tier, tiers)
		if s.tier >= tiers then
			tierBar.set(1)
			tierXp.Text = t("pass.max")
		else
			tierBar.set(s.xp / math.max(1, s.per))
			tierXp.Text = string.format(t("pass.xp"), s.xp, s.per, s.tier + 1)
		end
		local left = s.left
		seasonEnd.Text = if left ~= nil
			then string.format(t("pass.endsIn"), ShopPanel.daysHours(left, lang))
			else t("pass.noEnd")
		passHeroStroke.Color = if s.premium then Theme.Colors.Gold else Theme.Colors.PanelBorder
		if s.premium then
			premHead.Text = t("pass.premiumOn")
			premBody.Text = t("pass.premiumOnDesc")
		else
			premHead.Text = t("pass.premiumGives")
			premBody.Text = string.format(
				t("pass.totals"),
				Strings.formatInt(paidTotal.medals),
				paidTotal.crates,
				paidTotal.tokens,
				paidTotal.stock
			) .. "\n" .. string.format(
				t("pass.times"),
				math.max(1, math.floor(paidTotal.medals / math.max(1, freeTotal.medals) + 0.5)),
				t("title." .. (seasonTitle(tiers) or "Legend"))
			)
		end
		freeSub.Text = string.format(t("pass.laneFree"), math.max(0, s.tier - freeDone))
		paidSub.Text = if s.premium
			then string.format(t("pass.laneFree"), math.max(0, s.tier - paidDone))
			else t("pass.laneLocked")
		for tier = 1, tiers do
			local reached = tier <= s.tier
			paintCard(freeCards[tier], reached, tier <= freeDone, false, tier == s.tier + 1, nil)
			paintCard(
				paidCards[tier],
				reached,
				s.premium and tier <= paidDone,
				not s.premium,
				tier == s.tier + 1,
				Theme.Colors.Gold
			)
		end
		paintTrack(passTrack, s.tier, if s.tier < tiers then s.xp / math.max(1, s.per) else 0)
		local firstReady = math.min(freeDone, if s.premium then paidDone else freeDone) + 1
		local focus = math.clamp(if firstReady <= s.tier then firstReady else s.tier + 1, 1, tiers)
		if scrolled.pass ~= focus then
			scrolled.pass = focus
			scrollTo(passTrack, focus)
		end
	end

	local function draw()
		local p = cs.profile
		if p ~= nil then
			setWallet("medals", p.medals)
			setWallet("tokens", p.tokens)
			setWallet("crates", p.crates)
		end
		local path, free, paid = ClientState.rewardsPending(cs)
		setBadge(tabs.path, path)
		setBadge(tabs.pass, free + paid)
		for _, key in tabOrder do
			local tab = tabs[key]
			local on = key == current
			tab.page.Visible = on
			tab.button.BackgroundColor3 = if on then Theme.Colors.Gold else Theme.Colors.Backdrop
			tab.button.TextColor3 = if on then Theme.color("Ink") else Theme.Colors.Text
			tab.stroke.Color = if on then Theme.color("Ink") else Theme.Colors.PanelBorder
		end
		local premium = p ~= nil and p.season.premium
		local n: number
		if current == "path" then
			drawPath()
			n = path
			how.Text = t("ranks.how")
			buyPremium.Visible = false
		else
			drawPass()
			n = free + paid
			how.Text = t("pass.how")
			buyPremium.Visible = not premium
			buyPremium.Text = string.format(t("pass.buy"), Config.Shop.Packs.SeasonPass.price)
		end
		how.Size = UDim2.fromOffset(W - 2 * PAD - (if buyPremium.Visible then 600 else 300), 0)
		claimAll.Text = if n > 0 then string.format(t("path.claimAll"), n) else t("path.nothing")
		claimAll.Active = n > 0
		claimAll.AutoButtonColor = n > 0
		claimAll.BackgroundTransparency = if n > 0 then 0 else 0.5
		claimGlow.Enabled = n > 0
	end

	switchTab = function(key: TabKey)
		current = key
		scrolled[key] = nil
		draw()
	end

	-- Пульс «готово»: «ЗАБРАТЬ ВСЁ» мягко дышит.
	Session.connect(RunService.Heartbeat, function()
		if not window.Visible then
			return
		end
		local k = 0.5 + 0.5 * math.sin(os.clock() * 4)
		claimGlow.Transparency = 0.15 + 0.5 * k
	end)

	---------------------------------------------------------------------------------------------------------------
	-- Анимации забора.
	local function inWindow(g: GuiObject): Vector2
		local f = UiScale.factor() * scale.Scale
		return (g.AbsolutePosition + g.AbsoluteSize / 2 - window.AbsolutePosition) / f
	end

	local function rays(at: Vector2, color: Color3)
		for k = 0, 7 do
			local ray = Instance.new("Frame")
			ray.AnchorPoint = Vector2.new(0.5, 1)
			ray.Position = UDim2.fromOffset(at.X, at.Y)
			ray.Size = UDim2.fromOffset(6, 10)
			ray.Rotation = k * 45
			ray.BackgroundColor3 = color
			ray.BorderSizePixel = 0
			ray.ZIndex = 51
			ray.Parent = fx
			MenuKit.corner(ray, 3)
			TweenService:Create(
				ray,
				TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(6, 70), BackgroundTransparency = 1 }
			):Play()
			task.delay(0.6, function()
				ray:Destroy()
			end)
		end
	end

	local function fly(from: Vector2, iconKey: string, to: string, amount: number)
		local target = wallet[to]
		if target == nil then
			return
		end
		local dest = inWindow(target.frame)
		local icon = MenuKit.icon(fx, iconKey, 4)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromOffset(from.X, from.Y)
		icon.ZIndex = 52
		for _, d in icon:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 52
			end
		end
		TweenService:Create(
			icon,
			TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(from.X, from.Y - 40) }
		):Play()
		task.delay(0.25, function()
			TweenService:Create(
				icon,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.fromOffset(dest.X, dest.Y) }
			):Play()
			task.delay(0.5, function()
				icon:Destroy()
				-- Счётчик щёлкает к новому значению, плашка кошелька вспыхивает.
				local start, goal = target.value, target.value + amount
				target.value = goal
				local steps = 10
				for s = 1, steps do
					task.delay(s * 0.03, function()
						target.label.Text = Strings.formatInt(math.floor(start + (goal - start) * s / steps))
					end)
				end
				TweenService:Create(
					target.frame,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
					{ BackgroundColor3 = Theme.Colors.Gold }
				):Play()
			end)
		end)
	end

	-- «НОВОЕ ЗВАНИЕ»: погон крупно с прыжком, название, салют из конфетти.
	local function rankUp(rank: number)
		local shade = Instance.new("TextButton")
		shade.Name = "RankUp"
		shade.Text = ""
		shade.AutoButtonColor = false
		shade.Size = UDim2.fromScale(1, 1)
		shade.BackgroundColor3 = Theme.Colors.Backdrop
		shade.BackgroundTransparency = 0.15
		shade.ZIndex = 60
		shade.Parent = fx
		MenuKit.corner(shade, Theme.CornerPx)
		local head = MenuKit.label(shade, t("path.newRank"), 34, Theme.Colors.Gold, true)
		head.FontFace = Theme.FontHeavy
		head.AnchorPoint = Vector2.new(0.5, 0)
		head.Position = UDim2.new(0.5, 0, 0, 110)
		head.ZIndex = 61
		local ep = MenuKit.rankIcon(shade, rank, 12) -- 192 px
		ep.AnchorPoint = Vector2.new(0.5, 0.5)
		ep.Position = UDim2.new(0.5, 0, 0, 330)
		local grow = Instance.new("UIScale")
		grow.Scale = 0.2
		grow.Parent = ep
		for _, d in ep:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 61
			end
		end
		local name = MenuKit.label(shade, t("rank." .. rank), 28, groupColor(rank), true)
		name.AnchorPoint = Vector2.new(0.5, 0)
		name.Position = UDim2.new(0.5, 0, 0, 450)
		name.ZIndex = 61
		TweenService:Create(grow, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		local colors = { "Gold", "Red", "Sky", "Lime", "Orange", "White" }
		for k = 1, 36 do
			local bit = Instance.new("Frame")
			bit.Size = UDim2.fromOffset(8, 12)
			bit.Position = UDim2.fromOffset(math.random(40, W - 40), -20)
			bit.Rotation = math.random(0, 90)
			bit.BackgroundColor3 = Theme.color(colors[(k % #colors) + 1])
			bit.BorderSizePixel = 0
			bit.ZIndex = 62
			bit.Parent = shade
			local fall = TweenService:Create(
				bit,
				TweenInfo.new(1.4 + math.random() * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					Position = UDim2.fromOffset(bit.Position.X.Offset + math.random(-80, 80), H + 20),
					Rotation = bit.Rotation + math.random(180, 540),
				}
			)
			task.delay(math.random() * 0.4, function()
				fall:Play()
			end)
		end
		local function hide()
			if shade.Parent ~= nil then
				shade:Destroy()
			end
		end
		Session.connect(shade.Activated, hide)
		task.delay(3.5, hide)
	end

	-- Одна карточка: подпрыгнуть, лучи, значки в кошелёк.
	local function celebrate(card: Card, r: any, delay: number, color: Color3)
		task.delay(delay, function()
			if not window.Visible then
				return
			end
			TweenService:Create(
				card.pop,
				TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true),
				{ Scale = 1.15 }
			):Play()
			local at = inWindow(card.art)
			rays(at, color)
			if (r.medals or 0) > 0 then
				fly(at, "money", "medals", r.medals)
			end
			if (r.tokens or 0) > 0 then
				fly(at + Vector2.new(-16, 0), "hint", "tokens", r.tokens)
			end
			if (r.crates or 0) > 0 then
				fly(at + Vector2.new(16, 0), "arsenal", "crates", r.crates)
			end
		end)
	end

	local function onClaimed(msg: any)
		busy = false
		if type(msg) ~= "table" or type(msg.got) ~= "table" then
			return
		end
		-- Анимация — на вкладке, где забрали (ответ сервера о другой — переключиться на неё).
		local want: TabKey = if msg.kind == "seasonClaimed" then "pass" else "path"
		if current ~= want then
			current = want
			draw()
		end
		local newRank: number? = nil
		for i, item in msg.got :: { any } do
			-- Видимые — по одному с паузой; далёкие (за краем ленты) — без отдельной паузы.
			local delay = math.min(i - 1, 10) * 0.18
			if msg.kind == "seasonClaimed" then
				local card = if item.premium then paidCards[item.tier] else freeCards[item.tier]
				if card ~= nil then
					celebrate(card, item.reward, delay, if item.premium then Theme.Colors.Gold else Theme.Colors.Sky)
				end
			else
				if tierAt[item.level] ~= nil then
					newRank = tierAt[item.level]
				end
				local card = pathCards[item.level]
				if card ~= nil then
					celebrate(card, item.reward, delay, Theme.Colors.Gold)
				end
			end
		end
		if newRank ~= nil then
			local shown = newRank :: number
			task.delay(math.min(#msg.got, 10) * 0.18 + 0.9, function()
				if window.Visible then
					rankUp(shown)
				end
			end)
		end
	end

	local function toggle()
		window.Visible = not window.Visible
		if window.Visible then
			scrolled = {}
			draw()
		end
	end
	Session.connect(close.Activated, function()
		window.Visible = false
	end)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and window.Visible then
			window.Visible = false
		end
	end)

	return {
		toggle = toggle,
		isOpen = function(): boolean
			return window.Visible
		end,
		refresh = function()
			if window.Visible then
				draw()
			end
		end,
		onClaimed = onClaimed,
		pending = pending,
		window = window,
	}
end

return table.freeze(RanksPanel)
