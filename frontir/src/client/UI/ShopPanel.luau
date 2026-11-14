--!strict
--[[
	ShopPanel — профиль и магазин (GDD §11.1, §11.2, этап 9а).
	- Справа сверху: «Магазин (M)» и строка профиля «Ур. N · опыт · медали · жетоны».
	- Окно (M): бусты (жетон / из запаса / за Robux — по одному каждого вида за матч), геймпассы, наборы.
	  §15л ч.9: витрина CardKit — вкладки «Бусты», «Сезон и ящики», «Навсегда», «Наборы», карточки с картинками ItemArt.
	  Цена и точный эффект видны до покупки (§11.1). Покупка — окно Roblox (MarketplaceService), начисляет сервер.
	- После матча — тост «+опыт, +медали» и один раз за сессию — подсказка про «Набор новобранца».
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Profile = require(Shared:WaitForChild("Profile"))
local Shop = require(Shared:WaitForChild("Shop"))
local Strings = require(Shared:WaitForChild("Strings"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type ShopPanel = {
	button: GuiButton, -- §15з: кнопка прячется в док
	refresh: () -> (), -- пришёл профиль или сменилась фаза
	tap: (cell: number) -> boolean, -- true — нажатие ушло в цель «Авиаудара»
	onShopEvent: (msg: any) -> (), -- ежедневная награда, открытый ящик (§11.3)
	-- Самопроверка (сводная правка, часть 1): открыть/закрыть окно и узнать, открыто ли.
	toggle: () -> (),
	isOpen: () -> boolean,
}

local ShopPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx

local function label(parent: Instance, size: number, bold: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = if bold then Theme.FontBold else Theme.Font
	t.TextSize = size
	t.TextColor3 = Theme.Colors.Text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextWrapped = true
	t.RichText = true
	t.Parent = parent
	return t
end

local function button(parent: Instance, text: string, w: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(w, BUTTON)
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.FontFace = Theme.FontBold
	b.TextSize = 13
	b.TextColor3 = Theme.Colors.Text
	b.Text = text
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = Theme.Colors.PanelBorder
	s.Thickness = Theme.BorderPx
	s.Parent = b
	b.Parent = parent
	return b
end

-- Эффект товара с числами из Config (§11.1: точный эффект виден до покупки).
local function effect(key: string, lang: Strings.Lang): string
	local s = Config.Shop
	local fmt = Strings.get("shop.desc." .. key, lang)
	if key == "Mobilize" then
		return string.format(fmt, math.round(s.Boosts.Mobilize.garrisonShare * 100))
	elseif key == "Loan" then
		return string.format(fmt, Strings.formatInt(s.Boosts.Loan.money))
	elseif key == "HQ" then
		return string.format(fmt, s.Passes.HQ.recruitLines, math.round((s.Passes.HQ.incomeMul - 1) * 100))
	elseif key == "Intel" then
		return string.format(fmt, math.round((1 - s.Passes.Intel.intelCostMul) * 100), s.Passes.Intel.intelDurationSec)
	elseif key == "Vip" then
		return string.format(fmt, tostring(s.Passes.Vip.xpMul))
	elseif key == "Recruit" or key == "Medals" or key == "Tokens" then
		local p = (s.Packs :: any)[key]
		return string.format(fmt, p.tokens, Strings.formatInt(p.medals))
	elseif key == "Guards" then
		return string.format(fmt, math.round(s.Boosts.Guards.powerShare * 100), s.Boosts.Guards.minStrength)
	elseif key == "Airstrike" then
		return string.format(fmt, math.round(s.Boosts.Airstrike.frontLoss * 100))
	elseif key == "Crate1" or key == "Crate5" then
		return string.format(fmt, (s.Packs :: any)[key].crates)
	elseif key == "Levels5" or key == "PathPremiumPlus" then -- §15я Я2
		return string.format(fmt, (s.Packs :: any)[key].levels)
	elseif key == "XpBoost1" or key == "XpBoost7" then
		return string.format(fmt, s.XpBoostMul, (s.Packs :: any)[key].xpBoostHours)
	end
	return fmt
end

-- Награда текстом: «+300 медалей, +1 жетон, Гвардия».
local function rewardText(r: any, lang: Strings.Lang): string
	local parts: { string } = {}
	if (r.medals or 0) > 0 then
		table.insert(parts, string.format(Strings.get("shop.r.medals", lang), Strings.formatInt(r.medals)))
	end
	if (r.tokens or 0) > 0 then
		table.insert(parts, string.format(Strings.get("shop.r.tokens", lang), r.tokens))
	end
	if (r.crates or 0) > 0 then
		table.insert(parts, string.format(Strings.get("shop.r.crates", lang), r.crates))
	end
	for key, n in r.stock or {} do
		table.insert(parts, Strings.get("shop." .. key, lang) .. (if n > 1 then " ×" .. n else ""))
	end
	return table.concat(parts, ", ")
end

-- Секунды → «N дн. N ч» (честный отсчёт до настоящей даты).
local function daysHours(sec: number, lang: Strings.Lang): string
	local d, h = sec // 86400, (sec % 86400) // 3600
	return string.format(Strings.get("shop.daysHours", lang), d, h)
end

function ShopPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> (),
	toast: (text: string) -> (),
	onOpenPath: (() -> ())? -- §15я: «Открыть Путь» с главной карточки
): ShopPanel
	local player = Players.LocalPlayer

	local openButton = button(gui, Strings.get("shop.open", lang), 220)
	openButton.AnchorPoint = Vector2.new(1, 0)
	openButton.Position = UDim2.new(1, -12, 0, 124)
	openButton.TextColor3 = Theme.Colors.Gold
	local strip = label(gui, 12)
	strip.AnchorPoint = Vector2.new(1, 0)
	strip.Position = UDim2.new(1, -12, 0, 124 + BUTTON + 4)
	strip.Size = UDim2.fromOffset(300, 16)
	strip.TextXAlignment = Enum.TextXAlignment.Right
	strip.TextColor3 = Theme.Colors.Sky

	-- §15я Я3: витрина — вкладки Главное · Путь · Техника · Бусты · Навсегда · Наборы · Ящики (CardKit).
	local t = function(key: string): string
		return Strings.get(key, lang)
	end
	local win = CardKit.window(gui, "Shop", t("shop.title"), t("shop.note"), 1000, 740, {
		{ key = "main", label = t("shop.tabMain") },
		{ key = "path", label = t("shop.tabPath") },
		{ key = "units", label = t("shop.tabUnits") },
		{ key = "boosts", label = t("shop.boosts") },
		{ key = "passes", label = t("shop.passes") },
		{ key = "packs", label = t("shop.packs") },
		{ key = "crates", label = t("shop.crates") },
	}, { main = "list", crates = "list" }, true)
	local window = win.frame; -- §15ц Ц5а: низ витрины — где взять медали и жетоны (кнопки — на карточках).
	(win.footer :: CardKit.Footer).set("", false, t("shop.hint"))
	local medalsChip = CardKit.chip(win.chips, "money", 1)
	local tokensChip = CardKit.chip(win.chips, "hint", 2)
	local function prompt(kind: "pass" | "product", id: number)
		if id == 0 then
			toast(Strings.get("shop.soon", lang))
			return
		end
		if kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			MarketplaceService:PromptProductPurchase(player, id)
		end
	end
	local function packPrompt(key: string)
		prompt("product", (Config.Shop.Packs :: any)[key].id)
	end

	-- Метка в правом верхнем углу карточки: «ХИТ», «НОВОЕ», «ВЫГОДНО −N%».
	local function ribbon(parent: GuiObject): TextLabel
		local r = MenuKit.label(parent, "", 11, Theme.color("Ink"), true)
		r.Name = "Ribbon"
		r.AnchorPoint = Vector2.new(1, 0)
		r.Position = UDim2.new(1, -10, 0, 10)
		r.BackgroundTransparency = 0
		r.BackgroundColor3 = Theme.Colors.Gold
		r.ZIndex = 4
		r.Visible = false
		MenuKit.pad(r, 6, 2)
		MenuKit.corner(r, 4)
		return r
	end
	local function setRibbon(r: TextLabel, key: string, saving: number)
		local tag = Config.Shop.Tags[key]
		if saving > 0 then
			r.Text = string.format(t("shop.tag.saving"), saving)
			r.BackgroundColor3 = Theme.color("Lime")
		elseif tag ~= nil then
			r.Text = t("shop.tag." .. tag)
			r.BackgroundColor3 = Theme.color(if tag == "hit" then "Orange" else "Sky")
		end
		r.Visible = saving > 0 or tag ~= nil
	end
	local function savingOf(key: string): number
		local cfg = (Config.Shop.Packs :: any)[key]
		local parts = Shop.partsPrice(key, os.time())
		return if cfg ~= nil and parts ~= nil then Shop.saving(cfg.price, parts) else 0
	end

	-- Золотой отлив (UIGradient бежит в Heartbeat, пока окно открыто).
	local shimmers: { UIGradient } = {}
	local function shimmer(g: GuiObject)
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.42, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 244, 190)),
			ColorSequenceKeypoint.new(0.58, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
		})
		grad.Rotation = 20
		grad.Parent = g
		table.insert(shimmers, grad)
	end

	-- Широкая строка-предложение («Главное», «Ящики»): картинка, заголовок, строка, мелко, кнопки.
	type Offer = {
		frame: Frame,
		edge: UIStroke,
		title: TextLabel,
		line: TextLabel,
		sub: TextLabel,
		buttons: Frame,
		ribbon: TextLabel,
	}
	local function offer(page: Instance, artKey: string, order: number, height: number, gold: boolean): Offer
		local frame, body, edge = CardKit.row(page, artKey, 260, height, order)
		if gold then
			frame.BackgroundColor3 = Theme.color("Plum")
			edge.Color = Theme.Colors.Gold
			edge.Thickness = 3
			shimmer(frame)
		end
		MenuKit.list(body, 6)
		local title = MenuKit.label(body, "", 20, Theme.Colors.Gold, true, 1)
		title.FontFace = Theme.FontHeavy
		local line = MenuKit.wrapLabel(body, "", 14, Theme.Colors.Text, 2)
		local sub = MenuKit.wrapLabel(body, "", 12, Theme.Colors.Muted, 3)
		local buttons = Instance.new("Frame")
		buttons.Name = "Buttons"
		buttons.BackgroundTransparency = 1
		buttons.LayoutOrder = 4
		buttons.Size = UDim2.new(1, 0, 0, MenuKit.Touch)
		buttons.Parent = body
		MenuKit.list(buttons, 8, true)
		return {
			frame = frame,
			edge = edge,
			title = title,
			line = line,
			sub = sub,
			buttons = buttons,
			ribbon = ribbon(frame),
		}
	end
	local function offerButton(
		o: Offer,
		text: string,
		style: MenuKit.ButtonStyle,
		order: number,
		fn: () -> ()
	): TextButton
		local b = CardKit.button(o.buttons, text, style, order)
		b.Size = UDim2.fromOffset(0, MenuKit.Touch)
		b.AutomaticSize = Enum.AutomaticSize.X
		MenuKit.pad(b, 14, 0)
		Session.connect(b.Activated, fn)
		return b
	end

	-- Итоги премиум-дороги (для «что даёт»).
	local premiumMedals, premiumCrates, premiumStock, premiumPasses, premiumCosmetics = 0, 0, 0, 0, 0
	for lv = 2, Config.Profile.MaxLevel do
		local r = Profile.premiumReward(lv)
		premiumMedals += r.medals
		premiumCrates += r.crates
		if r.pass ~= nil then
			premiumPasses += 1
		end
		if r.cosmetic ~= nil then
			premiumCosmetics += 1
		end
		for _, n in r.stock do
			premiumStock += n
		end
	end
	local unitLevels: { string } = {}
	for _, key in Config.Unlocks.Order do
		local item = Config.Unlocks.Items[key]
		local name = if key == "Missile" then t("building.MissileSilo") else t("unit." .. key)
		table.insert(unitLevels, string.format(t("shop.premiumUnit"), name, item.premiumLevel, item.level))
	end
	local premiumGives = string.format(
		t("shop.premiumGives"),
		table.concat(unitLevels, ", "),
		premiumPasses,
		premiumCosmetics,
		Strings.formatInt(premiumMedals),
		premiumCrates,
		premiumStock
	)

	---------------------------------------------------------------------------------------------------------------
	-- «Главное».
	local mainPage = win.page("main")
	local hero = offer(mainPage, "shop.PathPremium", 1, 236, true)
	hero.title.Text = t("shop.PathPremium")
	hero.title.TextSize = 24
	hero.sub.Text = premiumGives
	hero.sub.TextColor3 = Theme.Colors.Text
	local heroBuy = offerButton(hero, "", "primary", 1, function()
		packPrompt("PathPremium")
	end)
	local heroPlus = offerButton(hero, "", "good", 2, function()
		packPrompt("PathPremiumPlus")
	end)
	local heroOpen = offerButton(hero, t("shop.toPath"), "normal", 3, function()
		window.Visible = false
		if onOpenPath ~= nil then
			onOpenPath()
		end
	end)
	local weekly = offer(mainPage, "shop.Weekly", 2, 150, false)
	weekly.title.Text = t("shop.Weekly")
	local weeklyBuy = offerButton(weekly, "", "primary", 1, function()
		packPrompt("Weekly")
	end)
	local recruit = offer(mainPage, "shop.Recruit", 3, 140, false)
	recruit.title.Text = t("shop.Recruit")
	recruit.line.Text = effect("Recruit", lang)
	recruit.ribbon.Text = t("shop.tag.newbie")
	recruit.ribbon.BackgroundColor3 = Theme.color("Sky")
	recruit.ribbon.Visible = true
	local recruitBuy = offerButton(recruit, "", "primary", 1, function()
		packPrompt("Recruit")
	end)
	local boost = offer(mainPage, "shop.XpBoost7", 4, 150, false)
	boost.title.Text = t("shop.xpBoostTitle")
	local boost1 = offerButton(boost, "", "primary", 1, function()
		packPrompt("XpBoost1")
	end)
	local boost7 = offerButton(boost, "", "good", 2, function()
		packPrompt("XpBoost7")
	end)
	local parade = offer(mainPage, "shop.ParadeSet", 5, 140, false)
	parade.title.Text = t("shop.ParadeSet")
	parade.line.Text = t("shop.desc.ParadeSet")
	setRibbon(parade.ribbon, "ParadeSet", 0)
	local paradeBuy = offerButton(parade, "", "primary", 1, function()
		packPrompt("ParadeSet")
	end)

	---------------------------------------------------------------------------------------------------------------
	-- Сетка товаров (Путь, Наборы): карточка с ценой, меткой и состоянием.
	type PackCard = { key: string, card: CardKit.Card, buy: TextButton, ribbon: TextLabel }
	local packCards: { PackCard } = {}
	local function packCard(page: string, key: string, order: number)
		local cfg = (Config.Shop.Packs :: any)[key]
		local card = CardKit.card(win.page(page), "shop." .. key, t("shop." .. key), effect(key, lang), order)
		local buy = CardKit.button(card.actions, string.format(t("shop.robux"), cfg.price), "primary", 1)
		Session.connect(buy.Activated, function()
			local p = cs.profile
			if p ~= nil and p.packs[key] then
				packPrompt(key)
			end
		end)
		local r = ribbon(card.frame)
		setRibbon(r, key, savingOf(key))
		table.insert(packCards, { key = key, card = card, buy = buy, ribbon = r })
	end
	for k, key in { "PathPremium", "PathPremiumPlus", "Levels5", "XpBoost1", "XpBoost7" } do
		packCard("path", key, k)
	end
	for k, key in { "Recruit", "Weekly", "Medals", "Tokens", "ParadeSet" } do
		packCard("packs", key, k)
	end

	-- Бусты: жетон / из запаса / за Robux.
	local strikePay: string? = nil -- «Авиаудар» ждёт клетку цели (оплата: token / stock)
	type BoostCard = { key: string, card: CardKit.Card, token: TextButton, stock: TextButton, robux: TextButton }
	local boostCards: { BoostCard } = {}
	for k, key in Shop.BoostKeys do
		local cfg = (Config.Shop.Boosts :: any)[key]
		local card = CardKit.card(win.page("boosts"), "shop." .. key, t("shop." .. key), effect(key, lang), k)
		local token = CardKit.button(card.actions, t("shop.useToken"), "good", 1)
		local stock = CardKit.button(card.actions, "", "normal", 2)
		local robux = CardKit.button(card.actions, string.format(t("shop.robux"), cfg.price), "primary", 3)
		local function use(pay: string)
			if key == "Airstrike" then
				strikePay = pay -- цель — следующим нажатием на карту
				window.Visible = false
				toast(t("shop.pickTarget"))
			else
				send("boost", { key = key, pay = pay })
			end
		end
		Session.connect(token.Activated, function()
			use("token")
		end)
		Session.connect(stock.Activated, function()
			use("stock")
		end)
		Session.connect(robux.Activated, function()
			prompt("product", cfg.id)
		end)
		table.insert(boostCards, { key = key, card = card, token = token, stock = stock, robux = robux })
	end

	-- Ящики: шансы до покупки, 1 и 5 за Robux, открыть.
	local crates = offer(win.page("crates"), "shop.Crates", 1, 230, false)
	crates.title.Text = t("shop.crates")
	local oddsParts: { string } = {}
	for _, o in Profile.crateOdds() do
		table.insert(oddsParts, string.format("%s %.0f%%", Strings.get("shop.odds." .. o.key, lang), o.percent))
	end
	crates.sub.Text = t("shop.odds")
		.. " "
		.. table.concat(oddsParts, " · ")
		.. "\n"
		.. string.format(t("shop.pity"), Config.Crates.Pity)
	setRibbon(crates.ribbon, "Crate5", savingOf("Crate5"))
	local openCrate = offerButton(crates, t("shop.openCrate"), "good", 1, function()
		send("openCrate", {})
	end)
	local crate1 = offerButton(crates, "", "primary", 2, function()
		packPrompt("Crate1")
	end)
	local crate5 = offerButton(crates, "", "primary", 3, function()
		packPrompt("Crate5")
	end)

	-- Навсегда (геймпассы): §15я Я1 — есть с «Пути» — не продаётся.
	type BuyCard = { key: string, card: CardKit.Card, buy: TextButton }
	local passCards: { BuyCard } = {}
	local passLevel: { [string]: number } = {}
	for lv, sp in Config.Path.Premium.Specials do
		if sp.pass ~= nil then
			passLevel[sp.pass] = lv
		end
	end
	for k, key in Shop.PassKeys do
		local cfg = (Config.Shop.Passes :: any)[key]
		local card = CardKit.card(win.page("passes"), "shop." .. key, t("shop." .. key), effect(key, lang), k)
		local buy = CardKit.button(card.actions, string.format(t("shop.robux"), cfg.price), "primary", 1)
		Session.connect(buy.Activated, function()
			local p = cs.profile
			if p == nil or not p.passes[key] then
				prompt("pass", cfg.id)
			end
		end)
		table.insert(passCards, { key = key, card = card, buy = buy })
	end

	-- §15э Э1: «Техника» — открыть сразу навсегда (иначе бесплатно на уровне «Пути командира»).
	local unitCards: { BuyCard } = {}
	local function unitTitle(key: string): string
		return if key == "Missile"
			then t("building.MissileSilo")
			elseif key == "All" then t("shop.unlockAll")
			else t("unit." .. key)
	end
	local unitKeys = table.clone(Config.Unlocks.Order)
	table.insert(unitKeys, "All")
	local allRibbon: TextLabel? = nil
	for k, key in unitKeys do
		local item = if key == "All" then Config.Unlocks.All else Config.Unlocks.Items[key]
		local card = CardKit.card(win.page("units"), "unlock." .. key, unitTitle(key), "", k)
		local buy = CardKit.button(card.actions, string.format(t("shop.robux"), item.price), "primary", 1)
		if key == "All" then
			local r = ribbon(card.frame)
			local parts = Shop.partsPrice("UnlockAll", 0) :: number
			setRibbon(r, "All", Shop.saving(item.price, parts))
			allRibbon = r
		end
		Session.connect(buy.Activated, function()
			local p = cs.profile
			local opens = if p ~= nil then p.unitUnlocks or {} else {}
			local anyOpen = false
			for _, u in Config.Unlocks.Order do
				anyOpen = anyOpen or opens[u] == true
			end
			-- §15я Я1: «Вся техника» — только пока закрыто всё (без переплаты за открытое).
			local blocked = if key == "All" then anyOpen else opens[key] == true
			if p ~= nil and not blocked then
				prompt("product", item.id)
			end
		end)
		table.insert(unitCards, { key = key, card = card, buy = buy })
	end

	---------------------------------------------------------------------------------------------------------------
	local profileAt = os.clock() -- когда пришёл профиль (отсчёты идут от него)
	local function hoursMinutes(sec: number): string
		return string.format(t("shop.hoursMinutes"), sec // 3600, (sec % 3600) // 60)
	end
	local function ticking()
		local p = cs.profile
		if p == nil then
			return
		end
		local since = math.floor(os.clock() - profileAt)
		weekly.sub.Text = string.format(t("shop.weeklyLeft"), daysHours(math.max(0, p.weekly.left - since), lang))
		local left = math.max(0, (p.xpBoostLeft or 0) - since)
		boost.line.Text = if left > 0
			then string.format(t("shop.xpBoostOn"), Config.Shop.XpBoostMul, hoursMinutes(left))
			else string.format(t("shop.xpBoostDesc"), Config.Shop.XpBoostMul)
		boost.line.TextColor3 = if left > 0 then Theme.color("Lime") else Theme.Colors.Text
	end

	local function stylePrice(b: TextButton, owned: boolean, ownedText: string, price: number)
		b.Text = if owned then ownedText else string.format(t("shop.robux"), price)
		b.AutoButtonColor = not owned
		b.BackgroundColor3 = Theme.color(if owned then "Forest" else "Gold")
		b.TextColor3 = Theme.color(if owned then "White" else "Ink")
	end

	local function draw()
		local p = cs.profile
		-- §15л: уровень, медали и жетоны — в главном меню; строка над картой справа лишняя (налезала на лидеров).
		strip.Visible = false
		if p == nil then
			return
		end
		strip.Text =
			string.format(Strings.get("shop.strip", lang), p.level, p.xp, p.need, Strings.formatInt(p.medals), p.tokens)
		medalsChip.Text = Strings.formatInt(p.medals)
		tokensChip.Text = tostring(p.tokens)
		local packs = Config.Shop.Packs :: any
		local premium = p.path ~= nil and p.path.premium == true
		local _, paidWaiting = ClientState.rewardsPending(cs)

		-- «Главное».
		hero.line.Text = if premium
			then string.format(t("shop.premiumOn"), paidWaiting)
			else string.format(t("shop.premiumWaits"), math.max(0, p.level - 1))
		setRibbon(hero.ribbon, "PathPremium", 0)
		heroBuy.Visible = not premium
		heroBuy.Text = string.format(t("shop.buyPremium"), packs.PathPremium.price)
		heroPlus.Visible = not premium
		heroPlus.Text =
			string.format(t("shop.buyPremiumPlus"), packs.PathPremiumPlus.levels, packs.PathPremiumPlus.price)
		heroOpen.Visible = premium
		hero.edge.Color = Theme.Colors.Gold
		local offerNow = p.weekly.offer
		weekly.line.Text = rewardText(offerNow, lang)
		weeklyBuy.Visible = p.packs.Weekly == true
		weeklyBuy.Text = if p.packs.Weekly then string.format(t("shop.robux"), packs.Weekly.price) else t("shop.bought")
		setRibbon(weekly.ribbon, "Weekly", if p.packs.Weekly then savingOf("Weekly") else 0)
		recruit.frame.Visible = p.packs.Recruit == true
		recruitBuy.Text = string.format(t("shop.robux"), packs.Recruit.price)
		boost1.Text = string.format(t("shop.xpBoostBuy"), t("shop.hours24"), packs.XpBoost1.price)
		boost7.Text = string.format(t("shop.xpBoostBuy"), t("shop.days7"), packs.XpBoost7.price)
		setRibbon(boost.ribbon, "XpBoost7", savingOf("XpBoost7"))
		parade.frame.Visible = p.packs.ParadeSet == true
		paradeBuy.Text = string.format(t("shop.robux"), packs.ParadeSet.price)
		ticking()

		-- Сетки наборов.
		for _, row in packCards do
			local cfg = packs[row.key]
			-- Ящики за Robux там, где платные случайные награды запрещены (PolicyService), не продаются.
			local blocked = p.noPaidRandom == true and (cfg.crates or 0) > 0
			local available = p.packs[row.key] == true and not blocked
			local premiumOwned = cfg.premiumPath and premium
			row.buy.Visible = available
			stylePrice(row.buy, false, "", cfg.price)
			if row.key == "Weekly" then
				row.card.desc.Text = string.format(
					t("shop.weeklyDesc"),
					rewardText(p.weekly.offer, lang),
					daysHours(p.weekly.left, lang)
				)
			end
			row.card.price.Text = if premiumOwned
				then t("shop.premiumOwned")
				elseif not available then t("shop.bought")
				elseif cfg.levels ~= nil and p.level >= Config.Profile.MaxLevel then t("shop.levelsToBonus")
				else ""
			row.card.price.TextColor3 = if premiumOwned then Theme.Colors.Good else Theme.Colors.Gold
			row.card.tag.Visible = not available
			row.card.tag.Text = t(if premiumOwned then "shop.tagOwned" else "shop.tagBought")
			row.card.dim.Visible = not available and not premiumOwned
			row.card.edge.Color = if premiumOwned
				then Theme.Colors.Good
				elseif row.key == "PathPremium" then Theme.Colors.Gold
				else Theme.Colors.PanelBorder
			setRibbon(row.ribbon, row.key, if available then savingOf(row.key) else 0)
			row.ribbon.Visible = row.ribbon.Visible and available
		end

		-- Бусты.
		local inMatch = cs.phase == "Play"
		for _, row in boostCards do
			local used = p.used[row.key] == true
			local stockCount = p.stock[row.key] or 0
			local canUse = inMatch and p.boosts and not used
			row.card.price.Text = if used
				then t("shop.used")
				elseif not p.boosts and inMatch then t("shop.noBoosts")
				elseif not inMatch then t("shop.onlyMatch")
				else string.format(t("shop.stockHave"), stockCount, p.tokens)
			row.card.price.TextColor3 = if canUse then Theme.Colors.Good else Theme.Colors.Muted
			row.token.Visible = canUse and p.tokens > 0
			row.stock.Visible = canUse and stockCount > 0
			row.stock.Text = string.format(t("shop.stockBtn"), stockCount)
			row.card.tag.Visible = used
			row.card.tag.Text = t("shop.tagUsed")
			row.card.edge.Color = if canUse then Theme.Colors.Good else Theme.Colors.PanelBorder
		end

		-- Ящики.
		crates.line.Text = string.format(t("shop.crateLine"), p.crates, p.pityLeft)
		openCrate.Visible = p.crates > 0
		local cratesBlocked = p.noPaidRandom == true
		crate1.Visible = not cratesBlocked
		crate5.Visible = not cratesBlocked
		crate1.Text = string.format(t("shop.buyCrates"), packs.Crate1.crates, packs.Crate1.price)
		crate5.Text = string.format(t("shop.buyCrates"), packs.Crate5.crates, packs.Crate5.price)
		crates.ribbon.Visible = not cratesBlocked and savingOf("Crate5") > 0
		if cratesBlocked then
			crates.sub.Text = t("shop.crateRestricted")
		end

		-- Навсегда: куплено геймпассом / дано «Путём» / будет на премиум-дороге.
		local bought = p.ownedPasses or p.passes
		local fromPath = p.pathPasses or {}
		for _, row in passCards do
			local cfg = (Config.Shop.Passes :: any)[row.key]
			local viaPath = fromPath[row.key] == true and bought[row.key] ~= true
			local owned = p.passes[row.key] == true
			stylePrice(row.buy, owned, t(if viaPath then "shop.ownedPath" else "shop.owned"), cfg.price)
			row.card.tag.Visible = owned
			row.card.tag.Text = t("shop.tagOwned")
			row.card.edge.Color = if owned then Theme.Colors.Good else Theme.Colors.PanelBorder
			local lv = passLevel[row.key]
			row.card.price.Text = if owned
				then t("shop.forever")
				elseif lv ~= nil then string.format(t("shop.passOnPath"), lv, Config.Path.Premium.PassRefund)
				else t("shop.forever")
		end

		-- §15э Э1 / §15я Я1: техника — открыто / откроется на ур. N «Пути» / купить; «Вся» — пока закрыто всё.
		local opens = p.unitUnlocks or {}
		local anyOpen = false
		for _, key in Config.Unlocks.Order do
			anyOpen = anyOpen or opens[key] == true
		end
		for _, row in unitCards do
			local isAll = row.key == "All"
			local opened = if isAll then anyOpen else opens[row.key] == true
			local item = if isAll then Config.Unlocks.All else Config.Unlocks.Items[row.key]
			local level = if isAll then 0 elseif premium then (item :: any).premiumLevel else (item :: any).level
			row.card.desc.Text = if isAll
				then t("shop.unlockAllDesc")
				else string.format(
					t("shop.unlockDesc2"),
					(item :: any).level,
					(item :: any).premiumLevel,
					Config.Path.Premium.UnitRefund
				)
			row.card.price.Text = if isAll and anyOpen
				then t("shop.unlockAllPartly")
				elseif opened then t("shop.unlockOpen")
				elseif isAll then t("shop.forever")
				else string.format(t("shop.unlockAt"), level, p.level)
			row.card.price.TextColor3 = if opened and not isAll then Theme.Colors.Good else Theme.Colors.Gold
			row.buy.Visible = not opened
			row.buy.Text = string.format(t("shop.robux"), item.price)
			row.card.tag.Visible = opened and not isAll
			row.card.tag.Text = t("shop.tagOpen")
			row.card.edge.Color = if opened and not isAll then Theme.Colors.Good else Theme.Colors.PanelBorder
			row.card.dim.Visible = isAll and anyOpen
		end
		local ar = allRibbon
		if ar ~= nil then
			ar.Visible = not anyOpen
		end
	end

	-- Отлив и отсчёты — только пока окно открыто.
	local lastTick = 0
	Session.connect(RunService.Heartbeat, function()
		if not window.Visible then
			return
		end
		local now = os.clock()
		local phase = (now % 2.4) / 2.4
		for _, g in shimmers do
			g.Offset = Vector2.new(phase * 2 - 1, 0)
		end
		if now - lastTick >= 1 then
			lastTick = now
			ticking()
		end
	end)

	Session.connect(openButton.Activated, function()
		window.Visible = not window.Visible
		draw()
	end)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.M then
			window.Visible = not window.Visible
			draw()
		end
	end)

	-- Итог матча — тост один раз; подсказка про набор новобранца — один раз за сессию (§11.1).
	local shownMatches = -1
	local hinted = false
	local lastProfile: any = nil
	local function refresh()
		if cs.profile ~= lastProfile then
			lastProfile = cs.profile
			profileAt = os.clock() -- отсчёты (неделя, ускоритель) — от прихода профиля
		end
		draw()
		local p = cs.profile
		if p == nil then
			return
		end
		local reward = p.reward
		if reward ~= nil and shownMatches ~= -1 and p.matches ~= shownMatches then
			local text = string.format(Strings.get("shop.reward", lang), reward.xp, reward.medals)
			if reward.levels > 0 then
				text ..= " · " .. string.format(Strings.get("shop.levelUp", lang), p.level)
			end
			toast(text)
			if not hinted and p.packs.Recruit then
				hinted = true
				toast(Strings.get("shop.hintRecruit", lang))
			end
		end
		shownMatches = p.matches
	end

	return {
		button = openButton,
		refresh = refresh,
		toggle = function()
			window.Visible = not window.Visible
			draw()
		end,
		isOpen = function(): boolean
			return window.Visible
		end,
		tap = function(cell: number): boolean
			local pay = strikePay
			if pay == nil then
				return false
			end
			strikePay = nil
			send("boost", { key = "Airstrike", pay = pay, cell = cell })
			return true
		end,
		onShopEvent = function(msg: any)
			if msg.kind == "daily" then
				toast(
					string.format(
						Strings.get("shop.daily", lang),
						tonumber(msg.streak) or 1,
						rewardText(msg.reward or {}, lang)
					)
				)
			elseif msg.kind == "crate" then
				local text = rewardText(msg.reward or {}, lang)
				if msg.key == "jackpot" then
					text = Strings.get("shop.jackpot", lang) .. " " .. text
				end
				toast(string.format(Strings.get("shop.crateOpened", lang), text))
			end
		end,
	}
end

-- §15л: главное меню пишет предложение недели так же, как магазин.
ShopPanel.rewardText = rewardText
ShopPanel.daysHours = daysHours

return table.freeze(ShopPanel)
