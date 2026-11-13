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
	toast: (text: string) -> ()
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

	-- §15л ч.9: окно-витрина — вкладки и карточки с картинками (CardKit).
	local t = function(key: string): string
		return Strings.get(key, lang)
	end
	local win = CardKit.window(gui, "Shop", t("shop.title"), t("shop.note"), 860, 720, {
		{ key = "boosts", label = t("shop.boosts") },
		{ key = "units", label = t("shop.tabUnits") }, -- §15э Э1: закрытая техника
		{ key = "season", label = t("shop.tabSeason") },
		{ key = "passes", label = t("shop.passes") },
		{ key = "packs", label = t("shop.packs") },
	}, { season = "list" }, true)
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

	-- Сезон и ящики: широкие строки.
	local seasonPage = win.page("season")
	local _, seasonBody = CardKit.row(seasonPage, "shop.SeasonPass", 240, 176, 1)
	MenuKit.list(seasonBody, 6)
	MenuKit.label(seasonBody, t("shop.season"), 20, Theme.Colors.Gold, true, 1)
	local seasonLine = MenuKit.wrapLabel(seasonBody, "", 14, Theme.Colors.Text, 2)
	local seasonBar = MenuKit.bar(seasonBody, 10, Theme.Colors.Sky, 3)
	local seasonNext = MenuKit.wrapLabel(seasonBody, "", 12, Theme.Colors.Muted, 4)
	local seasonBuy =
		CardKit.button(seasonBody, string.format(t("shop.robux"), Config.Shop.Packs.SeasonPass.price), "primary", 5)
	seasonBuy.Size = UDim2.fromOffset(200, MenuKit.Touch)
	Session.connect(seasonBuy.Activated, function()
		local p = cs.profile
		if p ~= nil and not p.season.premium then
			prompt("product", Config.Shop.Packs.SeasonPass.id)
		end
	end)
	local _, crateBody = CardKit.row(seasonPage, "shop.Crates", 240, 176, 2)
	MenuKit.list(crateBody, 6)
	MenuKit.label(crateBody, t("shop.crates"), 20, Theme.Colors.Gold, true, 1)
	local crateLine = MenuKit.wrapLabel(crateBody, "", 14, Theme.Colors.Text, 2)
	local odds = MenuKit.wrapLabel(crateBody, "", 12, Theme.Colors.Muted, 3)
	local oddsParts: { string } = {}
	for _, o in Profile.crateOdds() do
		table.insert(oddsParts, string.format("%s %.0f%%", Strings.get("shop.odds." .. o.key, lang), o.percent))
	end
	odds.Text = t("shop.odds")
		.. " "
		.. table.concat(oddsParts, " · ")
		.. "\n"
		.. string.format(t("shop.pity"), Config.Crates.Pity)
	local openCrate = CardKit.button(crateBody, t("shop.openCrate"), "good", 4)
	openCrate.Size = UDim2.fromOffset(200, MenuKit.Touch)
	Session.connect(openCrate.Activated, function()
		send("openCrate", {})
	end)

	-- Навсегда (геймпассы).
	type BuyCard = { key: string, card: CardKit.Card, buy: TextButton }
	local passCards: { BuyCard } = {}
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
	for k, key in unitKeys do
		local item = if key == "All" then Config.Unlocks.All else Config.Unlocks.Items[key]
		local card = CardKit.card(win.page("units"), "unlock." .. key, unitTitle(key), "", k)
		local buy = CardKit.button(card.actions, string.format(t("shop.robux"), item.price), "primary", 1)
		Session.connect(buy.Activated, function()
			local p = cs.profile
			local opened = p ~= nil
				and p.unitUnlocks ~= nil
				and (
						if key == "All"
							then p.unitUnlocks.Tanks
								and p.unitUnlocks.Artillery
								and p.unitUnlocks.AntiAir
								and p.unitUnlocks.Missile
							else p.unitUnlocks[key]
					)
					== true
			if not opened then
				prompt("product", item.id)
			end
		end)
		table.insert(unitCards, { key = key, card = card, buy = buy })
	end

	-- Наборы.
	local packCards: { BuyCard } = {}
	for k, key in Shop.PackKeys do
		local cfg = (Config.Shop.Packs :: any)[key]
		local card = CardKit.card(win.page("packs"), "shop." .. key, t("shop." .. key), effect(key, lang), k)
		local buy = CardKit.button(card.actions, string.format(t("shop.robux"), cfg.price), "primary", 1)
		Session.connect(buy.Activated, function()
			local p = cs.profile
			if p ~= nil and p.packs[key] then
				prompt("product", cfg.id)
			end
		end)
		table.insert(packCards, { key = key, card = card, buy = buy })
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
		for _, row in passCards do
			local owned = p.passes[row.key] == true
			local cfg = (Config.Shop.Passes :: any)[row.key]
			row.buy.Text = if owned then t("shop.owned") else string.format(t("shop.robux"), cfg.price)
			row.buy.AutoButtonColor = not owned
			row.buy.BackgroundColor3 = Theme.color(if owned then "Forest" else "Gold")
			row.buy.TextColor3 = Theme.color(if owned then "White" else "Ink")
			row.card.tag.Visible = owned
			row.card.tag.Text = t("shop.tagOwned")
			row.card.edge.Color = if owned then Theme.Colors.Good else Theme.Colors.PanelBorder
			row.card.price.Text = t("shop.forever")
		end
		-- §15э Э1: техника — открыто / откроется на ур. N «Пути» / купить.
		local opens = p.unitUnlocks or {}
		local allOpen = true
		for _, key in Config.Unlocks.Order do
			allOpen = allOpen and opens[key] == true
		end
		for _, row in unitCards do
			local opened = if row.key == "All" then allOpen else opens[row.key] == true
			local item = if row.key == "All" then Config.Unlocks.All else Config.Unlocks.Items[row.key]
			row.card.desc.Text = if row.key == "All"
				then t("shop.unlockAllDesc")
				else string.format(t("shop.unlockDesc"), (Config.Unlocks.Items[row.key] :: any).level)
			row.card.price.Text = if opened
				then t("shop.unlockOpen")
				elseif row.key == "All" then t("shop.forever")
				else string.format(t("shop.unlockAt"), (Config.Unlocks.Items[row.key] :: any).level, p.level)
			row.card.price.TextColor3 = if opened then Theme.Colors.Good else Theme.Colors.Gold
			row.buy.Visible = not opened
			row.buy.Text = string.format(t("shop.robux"), item.price)
			row.card.tag.Visible = opened
			row.card.tag.Text = t("shop.tagOpen")
			row.card.edge.Color = if opened then Theme.Colors.Good else Theme.Colors.PanelBorder
		end
		-- Пропуск и ящики.
		local season = p.season
		local left = season.left
		seasonLine.Text = if left ~= nil
			then string.format(
				t("shop.seasonLine"),
				season.tier,
				Config.Season.Tiers,
				season.xp,
				season.per,
				daysHours(left, lang)
			)
			else string.format(t("shop.seasonLineOpen"), season.tier, Config.Season.Tiers, season.xp, season.per)
		seasonBar.set(season.xp / math.max(1, season.per))
		seasonBuy.Text = if season.premium
			then t("shop.owned")
			else string.format(t("shop.robux"), Config.Shop.Packs.SeasonPass.price)
		local nextTier = math.min(Config.Season.Tiers, season.tier + 1)
		seasonNext.Text = string.format(
			t("shop.seasonNext"),
			nextTier,
			rewardText(Profile.seasonReward(nextTier, false), lang),
			rewardText(Profile.paidReward(Profile.seasonReward(nextTier, true), p.noPaidRandom == true), lang)
		)
		crateLine.Text = string.format(t("shop.crateLine"), p.crates, p.pityLeft)
		openCrate.Visible = p.crates > 0
		for _, row in packCards do
			local cfg = (Config.Shop.Packs :: any)[row.key]
			-- Ящики за Robux там, где платные случайные награды запрещены (PolicyService), не продаются.
			local blocked = p.noPaidRandom == true and (cfg.crates or 0) > 0
			row.buy.Visible = not blocked
			if row.key == "Weekly" then
				row.card.desc.Text = string.format(
					t("shop.weeklyDesc"),
					rewardText(p.weekly.offer, lang),
					daysHours(p.weekly.left, lang)
				)
			else
				row.card.desc.Text = if blocked then t("shop.crateRestricted") else effect(row.key, lang)
			end
			local available = p.packs[row.key] == true
			row.buy.Text = if available then string.format(t("shop.robux"), cfg.price) else t("shop.bought")
			row.card.tag.Visible = not available
			row.card.tag.Text = t("shop.tagBought")
			row.card.dim.Visible = not available
		end
	end

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
	local function refresh()
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
