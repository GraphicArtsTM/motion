--!strict
--[[
	ShopPanel — профиль и магазин (GDD §11.1, §11.2, этап 9а).
	- Справа сверху: «Магазин (M)» и строка профиля «Ур. N · опыт · медали · жетоны».
	- Окно (M): бусты (жетон / из запаса / за Robux — по одному каждого вида за матч), геймпассы, наборы.
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

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type ShopPanel = {
	refresh: () -> (), -- пришёл профиль или сменилась фаза
	tap: (cell: number) -> boolean, -- true — нажатие ушло в цель «Авиаудара»
	onShopEvent: (msg: any) -> (), -- ежедневная награда, открытый ящик (§11.3)
	-- Самопроверка (сводная правка, часть 1): открыть/закрыть окно и узнать, открыто ли.
	toggle: () -> (),
	isOpen: () -> boolean,
}

local ShopPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local W = 560
local ROW = BUTTON + 8

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

	local window = Instance.new("ScrollingFrame")
	window.Name = "Shop"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.new(0, W, 0.8, 0)
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BorderSizePixel = 0
	window.ScrollBarThickness = 6
	window.Visible = false
	window.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = window
	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function fit()
		scale.Scale = math.clamp((gui.AbsoluteSize.X - 24) / W, 0.5, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()

	local y = 8
	local function heading(key: string)
		local h = label(window, 15, true)
		h.Position = UDim2.fromOffset(12, y)
		h.Size = UDim2.fromOffset(W - 24, 22)
		h.TextColor3 = Theme.Colors.Gold
		h.Text = Strings.get(key, lang)
		y += 26
	end
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

	local closeButton = button(window, "×", BUTTON)
	closeButton.Position = UDim2.fromOffset(W - 12 - BUTTON, 6)
	Session.connect(closeButton.Activated, function()
		window.Visible = false
	end)
	local note = label(window, 12)
	note.Position = UDim2.fromOffset(12, y)
	note.Size = UDim2.fromOffset(W - 24 - BUTTON - 8, 32)
	note.TextColor3 = Theme.Colors.Muted
	note.Text = Strings.get("shop.note", lang)
	y += 36

	-- Боевой пропуск сезона (§11.3).
	heading("shop.season")
	local seasonLine = label(window, 13)
	seasonLine.Position = UDim2.fromOffset(12, y)
	seasonLine.Size = UDim2.fromOffset(W - 24 - 130, BUTTON)
	local seasonBuy =
		button(window, string.format(Strings.get("shop.robux", lang), Config.Shop.Packs.SeasonPass.price), 120)
	seasonBuy.Position = UDim2.fromOffset(W - 12 - 120, y)
	seasonBuy.TextColor3 = Theme.Colors.Gold
	Session.connect(seasonBuy.Activated, function()
		local p = cs.profile
		if p ~= nil and not p.season.premium then
			prompt("product", Config.Shop.Packs.SeasonPass.id)
		end
	end)
	y += ROW
	local seasonNext = label(window, 12)
	seasonNext.Position = UDim2.fromOffset(12, y)
	seasonNext.Size = UDim2.fromOffset(W - 24, 32)
	seasonNext.TextColor3 = Theme.Colors.Muted
	y += 36

	-- Ящики снабжения (§11.3): шансы и гарантия видны до покупки.
	heading("shop.crates")
	local crateLine = label(window, 13)
	crateLine.Position = UDim2.fromOffset(12, y)
	crateLine.Size = UDim2.fromOffset(W - 24 - 130, BUTTON)
	local openCrate = button(window, Strings.get("shop.openCrate", lang), 120)
	openCrate.Position = UDim2.fromOffset(W - 12 - 120, y)
	Session.connect(openCrate.Activated, function()
		send("openCrate", {})
	end)
	y += ROW
	local odds = label(window, 12)
	odds.Position = UDim2.fromOffset(12, y)
	odds.Size = UDim2.fromOffset(W - 24, 48)
	odds.TextColor3 = Theme.Colors.Muted
	local oddsParts: { string } = {}
	for _, o in Profile.crateOdds() do
		table.insert(oddsParts, string.format("%s %.0f%%", Strings.get("shop.odds." .. o.key, lang), o.percent))
	end
	odds.Text = Strings.get("shop.odds", lang)
		.. " "
		.. table.concat(oddsParts, " · ")
		.. "\n"
		.. string.format(Strings.get("shop.pity", lang), Config.Crates.Pity)
	y += 52

	-- Бусты.
	heading("shop.boosts")
	local strikePay: string? = nil -- «Авиаудар» ждёт клетку цели (оплата: token / stock)
	type BoostRow = { key: string, status: TextLabel, token: TextButton, stock: TextButton, robux: TextButton }
	local boostRows: { BoostRow } = {}
	for _, key in Shop.BoostKeys do
		local cfg = (Config.Shop.Boosts :: any)[key]
		local name = label(window, 13, true)
		name.Position = UDim2.fromOffset(12, y)
		name.Size = UDim2.fromOffset(240, 18)
		name.Text = Strings.get("shop." .. key, lang)
		local desc = label(window, 12)
		desc.Position = UDim2.fromOffset(12, y + 18)
		desc.Size = UDim2.fromOffset(240, 18)
		desc.TextColor3 = Theme.Colors.Muted
		desc.Text = effect(key, lang)
		local status = label(window, 12)
		status.Position = UDim2.fromOffset(256, y)
		status.Size = UDim2.fromOffset(W - 268, BUTTON)
		status.TextXAlignment = Enum.TextXAlignment.Right
		status.TextColor3 = Theme.Colors.Muted
		local token = button(window, Strings.get("shop.useToken", lang), 92)
		token.Position = UDim2.fromOffset(W - 12 - 92 * 3 - 12, y)
		local stock = button(window, "", 92)
		stock.Position = UDim2.fromOffset(W - 12 - 92 * 2 - 6, y)
		local robux = button(window, string.format(Strings.get("shop.robux", lang), cfg.price), 92)
		robux.Position = UDim2.fromOffset(W - 12 - 92, y)
		robux.TextColor3 = Theme.Colors.Gold
		local function use(pay: string)
			if key == "Airstrike" then
				strikePay = pay -- цель — следующим нажатием на карту
				window.Visible = false
				toast(Strings.get("shop.pickTarget", lang))
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
		table.insert(boostRows, { key = key, status = status, token = token, stock = stock, robux = robux })
		y += ROW + 6
	end

	-- Геймпассы.
	heading("shop.passes")
	type PassRow = { key: string, buy: TextButton }
	local passRows: { PassRow } = {}
	for _, key in Shop.PassKeys do
		local cfg = (Config.Shop.Passes :: any)[key]
		local name = label(window, 13, true)
		name.Position = UDim2.fromOffset(12, y)
		name.Size = UDim2.fromOffset(W - 140, 18)
		name.Text = Strings.get("shop." .. key, lang)
		local desc = label(window, 12)
		desc.Position = UDim2.fromOffset(12, y + 18)
		desc.Size = UDim2.fromOffset(W - 140, 18)
		desc.TextColor3 = Theme.Colors.Muted
		desc.Text = effect(key, lang)
		local buy = button(window, string.format(Strings.get("shop.robux", lang), cfg.price), 110)
		buy.Position = UDim2.fromOffset(W - 12 - 110, y)
		buy.TextColor3 = Theme.Colors.Gold
		Session.connect(buy.Activated, function()
			local p = cs.profile
			if p == nil or not p.passes[key] then
				prompt("pass", cfg.id)
			end
		end)
		table.insert(passRows, { key = key, buy = buy })
		y += ROW + 6
	end

	-- Наборы.
	heading("shop.packs")
	type PackRow = { key: string, buy: TextButton, desc: TextLabel }
	local packRows: { PackRow } = {}
	for _, key in Shop.PackKeys do
		local cfg = (Config.Shop.Packs :: any)[key]
		local name = label(window, 13, true)
		name.Position = UDim2.fromOffset(12, y)
		name.Size = UDim2.fromOffset(W - 140, 18)
		name.Text = Strings.get("shop." .. key, lang)
		local desc = label(window, 12)
		desc.Position = UDim2.fromOffset(12, y + 18)
		desc.Size = UDim2.fromOffset(W - 140, 18)
		desc.TextColor3 = Theme.Colors.Muted
		desc.Text = effect(key, lang)
		local buy = button(window, string.format(Strings.get("shop.robux", lang), cfg.price), 110)
		buy.Position = UDim2.fromOffset(W - 12 - 110, y)
		buy.TextColor3 = Theme.Colors.Gold
		Session.connect(buy.Activated, function()
			local p = cs.profile
			if p ~= nil and p.packs[key] then
				prompt("product", cfg.id)
			end
		end)
		table.insert(packRows, { key = key, buy = buy, desc = desc })
		y += ROW + 6
	end
	window.CanvasSize = UDim2.fromOffset(0, y + 8)

	local function draw()
		local p = cs.profile
		strip.Visible = p ~= nil
		if p == nil then
			return
		end
		strip.Text =
			string.format(Strings.get("shop.strip", lang), p.level, p.xp, p.need, Strings.formatInt(p.medals), p.tokens)
		local inMatch = cs.phase == "Play"
		for _, row in boostRows do
			local used = p.used[row.key] == true
			local stockCount = p.stock[row.key] or 0
			local canUse = inMatch and p.boosts and not used
			row.status.Text = if used
				then Strings.get("shop.used", lang)
				elseif not p.boosts and inMatch then Strings.get("shop.noBoosts", lang)
				elseif not inMatch then Strings.get("shop.onlyMatch", lang)
				else ""
			row.token.Visible = canUse and p.tokens > 0
			row.stock.Visible = canUse and stockCount > 0
			row.stock.Text = string.format(Strings.get("shop.useStock", lang), stockCount)
			row.status.Visible = not (row.token.Visible or row.stock.Visible)
		end
		for _, row in passRows do
			local owned = p.passes[row.key] == true
			local cfg = (Config.Shop.Passes :: any)[row.key]
			row.buy.Text = if owned
				then Strings.get("shop.owned", lang)
				else string.format(Strings.get("shop.robux", lang), cfg.price)
			row.buy.AutoButtonColor = not owned
		end
		-- Пропуск и ящики.
		local season = p.season
		local left = season.left
		seasonLine.Text = if left ~= nil
			then string.format(
				Strings.get("shop.seasonLine", lang),
				season.tier,
				Config.Season.Tiers,
				season.xp,
				season.per,
				daysHours(left, lang)
			)
			else string.format(
				Strings.get("shop.seasonLineOpen", lang),
				season.tier,
				Config.Season.Tiers,
				season.xp,
				season.per
			)
		seasonBuy.Text = if season.premium
			then Strings.get("shop.owned", lang)
			else string.format(Strings.get("shop.robux", lang), Config.Shop.Packs.SeasonPass.price)
		local nextTier = math.min(Config.Season.Tiers, season.tier + 1)
		seasonNext.Text = string.format(
			Strings.get("shop.seasonNext", lang),
			nextTier,
			rewardText(Profile.seasonReward(nextTier, false), lang),
			rewardText(Profile.paidReward(Profile.seasonReward(nextTier, true), p.noPaidRandom == true), lang)
		)
		crateLine.Text = string.format(Strings.get("shop.crateLine", lang), p.crates, p.pityLeft)
		openCrate.Visible = p.crates > 0
		for _, row in packRows do
			local cfg = (Config.Shop.Packs :: any)[row.key]
			-- Ящики за Robux там, где платные случайные награды запрещены (PolicyService), не продаются.
			local blocked = p.noPaidRandom == true and (cfg.crates or 0) > 0
			row.buy.Visible = not blocked
			if row.key == "Weekly" then
				row.desc.Text = string.format(
					Strings.get("shop.weeklyDesc", lang),
					rewardText(p.weekly.offer, lang),
					daysHours(p.weekly.left, lang)
				)
			else
				row.desc.Text = if blocked then Strings.get("shop.crateRestricted", lang) else effect(row.key, lang)
			end
			local available = p.packs[row.key] == true
			row.buy.Text = if available
				then string.format(Strings.get("shop.robux", lang), cfg.price)
				else Strings.get("shop.bought", lang)
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

return table.freeze(ShopPanel)
