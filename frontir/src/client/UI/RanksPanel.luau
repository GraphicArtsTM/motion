--!strict
--[[
	RanksPanel — окно «Путь командира» (GDD §15щ Щ3 → §15ю Ю6–Ю7): один путь, две дороги.

	Строение (сверху вниз):
	  1. Шапка — заголовок, кошелёк (медали, жетоны, ящики: сюда летят награды), «×».
	  2. Герой — погон, звание, уровень, «пройдено N%», полоса опыта; в середине — ГЛАВНЫЙ ПРИЗ ур. 100; справа —
	     что даёт премиум-дорога (или «премиум-дорога ваша»).
	  3. Лента — «БЕСПЛАТНО» над линией уровней с номерами, «ПРЕМИУМ» (золотая, под замком без покупки) под ней; в конце —
	     «БОНУС ∞» (сундуки после 100-го). Карточка: редкость (цвет рамки и метка), «★» каждый 5-й, картинка, что даёт,
	     «ЗАБРАТЬ» / «✔ получено» / «🔒».
	  4. «Впереди» — ближайшие особые награды обеих дорог (техника, улучшения, косметика, звания, генералы).
	  5. Низ — описание выбранной карточки, как идёт опыт, «ОТКРЫТЬ ПРЕМИУМ — R$ N», «ЗАБРАТЬ ВСЁ (N)».

	Эффекты (Ю7): окно въезжает; готовые карточки — блик и покачивание; премиум — бегущий золотой отлив; забор —
	вспышка, искры, лучи, значки дугой в кошелёк (кошелёк подпрыгивает, счётчики щёлкают); особая награда и новое
	звание — окно с вращающимися лучами и конфетти (очередью); покупка премиума — «ПРЕМИУМ-ДОРОГА ОТКРЫТА», замки
	слетают; линия прогресса заполняется плавно; закрытая карточка — встряска и «откроется на ур. N».

	Забрать — намерение pathClaim (сервер выдаёт обе дороги по порядку), ответ pathClaimed → onClaimed.
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
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState
type PathReward = Profile.PathReward

export type RanksPanel = {
	toggle: () -> (),
	isOpen: () -> boolean,
	refresh: () -> (),
	onClaimed: (msg: any) -> (), -- pathClaimed: { got = { { level, premium, bonus, reward } } }
	pending: () -> number, -- сколько наград ждёт на обеих дорогах (метка в меню)
	window: Frame,
}

local RanksPanel = {}

-- Размеры (px до UiScale).
local W, H = 1060, 720
local BANNER = Config.Render.Banner.MaxPx -- высота картинки-шапки над окном
local PAD = 24
local HERO_Y, HERO_H = 70, 128
local TRACK_Y = 208
local CARD_W, CARD_H, GAP = 112, 140, 10
local COL = CARD_W + GAP
local CIRCLE = 30
local LANE_W = 110
local FOOTER_Y = H - 86
local FIRST, LAST = 2, Config.Profile.MaxLevel
local COLUMNS = LAST - FIRST + 2 -- уровни 2…100 и «БОНУС ∞»
local BONUS_COL = COLUMNS

type Rarity = "common" | "rare" | "epic" | "legendary"
local RARITY_COLOR: { [string]: string } = {
	common = "Steel",
	rare = "Sky",
	epic = "Violet",
	legendary = "Orange",
}

local function groupColor(rank: number): Color3
	return Theme.color(Ranks.GroupColors[Ranks.group(rank)])
end

local function rarityOf(r: PathReward, bonus: boolean): Rarity
	if r.unit ~= nil or r.pass ~= nil or r.cosmetic == "title:Legend" or r.medals >= 5000 then
		return "legendary" :: Rarity
	elseif r.cosmetic ~= nil or r.crates >= 3 or bonus then
		return "epic" :: Rarity
	elseif r.crates > 0 or r.tokens > 0 or next(r.stock) ~= nil or r.title ~= nil then
		return "rare" :: Rarity
	end
	return "common" :: Rarity
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
	local function cosmeticName(key: string): (string, string, string)
		local kind, id = string.match(key, "^(%a+):(%a+)$")
		local k, i = kind or "pattern", id or ""
		if k == "title" then
			return k, i, string.format(t("path.titleItem"), t("title." .. i))
		end
		return k, i, t("path.cosmetic." .. k) .. " «" .. t(k .. "." .. i) .. "»"
	end

	-- Главная часть награды: ключ картинки (ItemArt) или значка, картинка ли, крупная подпись.
	local function mainPart(r: PathReward, bonus: boolean): (string, string, boolean, string)
		if bonus then
			return "bonus", "shop.Crates", true, t("path.bonusName")
		elseif r.unit ~= nil then
			return "unit", "unlock." .. r.unit, true, unitName(r.unit)
		elseif r.pass ~= nil then
			return "pass", "shop." .. r.pass, true, t("shop." .. r.pass)
		elseif r.cosmetic ~= nil then
			local kind, id, name = cosmeticName(r.cosmetic)
			return "cosmetic", kind .. "." .. id, true, name
		elseif r.title ~= nil then
			return "title", "title." .. r.title, true, string.format(t("path.titleItem"), t("title." .. r.title))
		end
		for key, n in r.stock do
			if n > 0 then
				return "stock", "shop." .. key, true, t("shop." .. key)
			end
		end
		if r.crates >= 3 then
			return "crates", "shop.Crates", true, string.format(t("path.crates"), r.crates)
		elseif r.crates > 0 and r.medals == 0 and r.tokens == 0 then
			return "crates", "arsenal", false, "+" .. r.crates
		elseif r.tokens > 0 and r.medals == 0 then
			return "tokens", "hint", false, "+" .. r.tokens
		end
		return "medals", "money", false, "+" .. Strings.formatInt(r.medals)
	end

	-- Мелкая строка: всё, что не вошло в главную часть.
	local function extras(r: PathReward, main: string): string
		local out: { string } = {}
		if main ~= "medals" and r.medals > 0 then
			table.insert(out, "+" .. Strings.formatInt(r.medals))
		end
		if main ~= "crates" and r.crates > 0 then
			table.insert(out, string.format(t("path.crates"), r.crates))
		end
		if main ~= "tokens" and r.tokens > 0 then
			table.insert(out, string.format(t("path.tokens"), r.tokens))
		end
		if main ~= "stock" then
			for key, n in r.stock do
				if n > 0 then
					table.insert(out, t("shop." .. key))
				end
			end
		end
		return table.concat(out, " · ")
	end

	-- Полное описание награды (строка «выбрано» внизу).
	local function describe(r: PathReward, bonus: boolean): string
		local out: { string } = {}
		if bonus then
			table.insert(out, t("path.bonusName"))
		end
		if r.unit ~= nil then
			table.insert(out, string.format(t("path.opensUnit"), unitName(r.unit)))
		end
		if r.pass ~= nil then
			table.insert(out, string.format(t("path.passItem"), t("shop." .. r.pass)))
		end
		if r.cosmetic ~= nil then
			local _, _, name = cosmeticName(r.cosmetic)
			table.insert(out, name)
		end
		if r.title ~= nil then
			table.insert(out, string.format(t("path.titleItem"), t("title." .. r.title)))
		end
		if r.medals > 0 then
			table.insert(out, string.format(t("path.medals"), Strings.formatInt(r.medals)))
		end
		if r.crates > 0 then
			table.insert(out, string.format(t("path.crates"), r.crates))
		end
		if r.tokens > 0 then
			table.insert(out, string.format(t("path.tokens"), r.tokens))
		end
		for key, n in r.stock do
			if n > 0 then
				table.insert(out, t("shop." .. key))
			end
		end
		return table.concat(out, ", ")
	end

	local function shortText(r: PathReward): string
		local out: { string } = {}
		if r.medals > 0 then
			table.insert(out, string.format(t("path.medals"), Strings.formatInt(r.medals)))
		end
		if r.crates > 0 then
			table.insert(out, string.format(t("path.crates"), r.crates))
		end
		if r.tokens > 0 then
			table.insert(out, string.format(t("path.tokens"), r.tokens))
		end
		return table.concat(out, ", ")
	end

	---------------------------------------------------------------------------------------------------------------
	-- 0. Рамка. Имя без «Window» на конце: Polish не трогает масштаб окна (въезд — свой).
	local window = Instance.new("Frame")
	window.Name = "RanksBoard"
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

	-- Бегущий золотой отлив (UIGradient, сдвиг — в Heartbeat).
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

	---------------------------------------------------------------------------------------------------------------
	-- 1. Шапка.
	local title = MenuKit.label(window, t("path.windowTitle"), 28, Theme.Colors.Text, true)
	title.FontFace = Theme.FontHeavy
	title.Position = UDim2.fromOffset(PAD + 4, 16)
	local close = MenuKit.button(window, "×", "normal")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -PAD + 4, 0, 10)
	close.Size = UDim2.fromOffset(44, 44)

	type Wallet = { frame: Frame, label: TextLabel, pop: UIScale, value: number }
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
		local pop = Instance.new("UIScale")
		pop.Parent = chip
		local icon =
			MenuKit.icon(chip, if kind == "medals" then "money" elseif kind == "tokens" then "hint" else "arsenal", 3)
		icon.Position = UDim2.fromOffset(8, 7)
		local label = MenuKit.label(chip, "0", 18, Theme.Colors.Gold, true)
		label.AnchorPoint = Vector2.new(1, 0.5)
		label.Position = UDim2.new(1, -10, 0.5, 0)
		label.TextXAlignment = Enum.TextXAlignment.Right
		wallet[kind] = { frame = chip, label = label, pop = pop, value = 0 }
	end
	divider(62)

	---------------------------------------------------------------------------------------------------------------
	-- 2. Герой: звание и опыт; главный приз; премиум.
	local hero = Instance.new("Frame")
	hero.Name = "Hero"
	hero.Position = UDim2.fromOffset(PAD, HERO_Y)
	hero.Size = UDim2.new(1, -2 * PAD, 0, HERO_H)
	hero.BackgroundColor3 = Theme.Colors.Backdrop
	hero.BorderSizePixel = 0
	hero.Parent = window
	MenuKit.corner(hero, 12)
	local heroStroke = MenuKit.stroke(hero, Theme.Colors.PanelBorder, 2)
	local bigRank = MenuKit.rankIcon(hero, 1, 7) -- 112 px
	bigRank.Position = UDim2.fromOffset(12, 8)
	local nowLabel = MenuKit.label(hero, t("ranks.now"), 12, Theme.Colors.Sky, true)
	nowLabel.Position = UDim2.fromOffset(140, 12)
	local rankName = MenuKit.label(hero, "", 26, Theme.Colors.Text, true)
	rankName.FontFace = Theme.FontHeavy
	rankName.Position = UDim2.fromOffset(140, 28)
	local levelLine = MenuKit.label(hero, "", 14, Theme.Colors.Text)
	levelLine.Position = UDim2.fromOffset(140, 62)
	local xpHost = Instance.new("Frame")
	xpHost.BackgroundTransparency = 1
	xpHost.Position = UDim2.fromOffset(140, 86)
	xpHost.Size = UDim2.fromOffset(330, 12)
	xpHost.Parent = hero
	local xpBar = MenuKit.bar(xpHost, 12, Theme.Colors.Sky)
	local xpText = MenuKit.label(hero, "", 12, Theme.Colors.Muted)
	xpText.Position = UDim2.fromOffset(140, 102)

	local function heroBox(x: number, w: number, gold: boolean): Frame
		local f = Instance.new("Frame")
		f.Position = UDim2.fromOffset(x, 12)
		f.Size = UDim2.fromOffset(w, HERO_H - 24)
		f.BackgroundColor3 = if gold then Theme.color("Plum") else Theme.Colors.PanelBg
		f.BorderSizePixel = 0
		f.Parent = hero
		MenuKit.corner(f, 10)
		MenuKit.stroke(f, if gold then Theme.Colors.Gold else Theme.Colors.PanelBorder, if gold then 2 else 1)
		return f
	end
	-- Главный приз последнего уровня.
	local grandBox = heroBox(486, 256, false)
	grandBox.Name = "Grand"
	local grandArt = CardKit.art(grandBox, "title.Legend", 72, 48)
	grandArt.Position = UDim2.fromOffset(10, 30)
	local grandHead = MenuKit.label(grandBox, string.format(t("path.grand"), LAST), 13, Theme.Colors.Gold, true)
	grandHead.Position = UDim2.fromOffset(10, 6)
	local grandBody = MenuKit.label(grandBox, "", 11, Theme.Colors.Text)
	grandBody.AutomaticSize = Enum.AutomaticSize.None
	grandBody.Position = UDim2.fromOffset(90, 26)
	grandBody.Size = UDim2.fromOffset(158, 74)
	grandBody.TextWrapped = true
	grandBody.TextYAlignment = Enum.TextYAlignment.Top
	local grandPremium = Profile.premiumReward(LAST)
	local legendId = string.match(grandPremium.cosmetic or "title:Legend", "^%a+:(%a+)$") or "Legend"
	grandBody.Text = string.format(t("path.grandPremium"), t("title." .. legendId), shortText(grandPremium))
		.. "\n"
		.. string.format(t("path.grandFree"), shortText(Profile.pathReward(LAST)))
	-- Премиум.
	local premBox = heroBox(752, 248, true)
	premBox.Name = "Premium"
	shimmer(premBox)
	local premHead = MenuKit.label(premBox, "", 14, Theme.Colors.Gold, true)
	premHead.FontFace = Theme.FontHeavy
	premHead.Position = UDim2.fromOffset(12, 8)
	local premBody = MenuKit.label(premBox, "", 11, Theme.Colors.Text)
	premBody.AutomaticSize = Enum.AutomaticSize.None
	premBody.Position = UDim2.fromOffset(12, 30)
	premBody.Size = UDim2.fromOffset(226, 70)
	premBody.TextWrapped = true
	premBody.TextYAlignment = Enum.TextYAlignment.Top

	-- Итоги премиум-дороги (для «премиум-дорога даёт»).
	local paidMedals, paidCrates, paidTokens, paidStock, paidPasses, paidCosmetics = 0, 0, 0, 0, 0, 0
	for lv = FIRST, LAST do
		local r = Profile.premiumReward(lv)
		paidMedals += r.medals
		paidCrates += r.crates
		paidTokens += r.tokens
		for _, n in r.stock do
			paidStock += n
		end
		if r.pass ~= nil then
			paidPasses += 1
		end
		if r.cosmetic ~= nil then
			paidCosmetics += 1
		end
	end
	local premiumText = string.format(
		t("path.totals"),
		Strings.formatInt(paidMedals),
		paidCrates,
		paidTokens,
		paidStock
	) .. "\n" .. string.format(t("path.extras"), paidPasses, paidCosmetics)

	---------------------------------------------------------------------------------------------------------------
	-- 3. Лента: подписи дорог, прокрутка, линия, карточки.
	local lineY = 4 + CARD_H + 20
	local premiumY = lineY + 20
	local trackH = premiumY + CARD_H + 14

	local function laneLabel(y: number, text: string, color: Color3, gold: boolean): TextLabel
		local f = Instance.new("Frame")
		f.Name = "Lane"
		f.Position = UDim2.fromOffset(PAD, TRACK_Y + y)
		f.Size = UDim2.fromOffset(LANE_W - 10, CARD_H)
		f.BackgroundColor3 = if gold then Theme.color("Plum") else Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.Parent = window
		MenuKit.corner(f, 10)
		MenuKit.stroke(f, color, 2)
		if gold then
			shimmer(f)
		end
		local l = MenuKit.label(f, text, 14, color, true)
		l.FontFace = Theme.FontHeavy
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(0.5, 0, 0, 16)
		local sub = MenuKit.label(f, "", 11, Theme.Colors.Muted, true)
		sub.AutomaticSize = Enum.AutomaticSize.None
		sub.AnchorPoint = Vector2.new(0.5, 0)
		sub.Position = UDim2.new(0.5, 0, 0, 42)
		sub.Size = UDim2.new(1, -12, 0, 90)
		sub.TextWrapped = true
		sub.TextXAlignment = Enum.TextXAlignment.Center
		sub.TextYAlignment = Enum.TextYAlignment.Top
		return sub
	end
	local freeSub = laneLabel(4, t("path.free"), Theme.Colors.Sky, false)
	local paidSub = laneLabel(premiumY, t("path.premium"), Theme.Colors.Gold, true)

	local viewW = W - 2 * PAD - LANE_W
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Track"
	scroll.Position = UDim2.fromOffset(PAD + LANE_W, TRACK_Y)
	scroll.Size = UDim2.fromOffset(viewW, trackH)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.Colors.Gold
	scroll.ElasticBehavior = Enum.ElasticBehavior.Never
	scroll.Parent = window
	local canvasW = 8 + COLUMNS * COL - GAP + 8
	scroll.CanvasSize = UDim2.fromOffset(canvasW, trackH - 10)
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.fromOffset(canvasW, trackH - 10)
	canvas.Parent = scroll

	local function colX(i: number): number
		return 8 + (i - 1) * COL
	end

	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BackgroundColor3 = Theme.Colors.Slate
	line.BorderSizePixel = 0
	line.Position = UDim2.fromOffset(8, lineY - 3)
	line.Size = UDim2.fromOffset(canvasW - 16, 6)
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
	for i = 1, COLUMNS do
		local text = if i == BONUS_COL then "∞" else tostring(FIRST + i - 1)
		local c = MenuKit.label(canvas, text, 13, Theme.Colors.Text, true)
		c.Name = "Step" .. i
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.AutomaticSize = Enum.AutomaticSize.None
		c.Size = UDim2.fromOffset(CIRCLE, CIRCLE)
		c.Position = UDim2.fromOffset(colX(i) + CARD_W / 2, lineY)
		c.TextXAlignment = Enum.TextXAlignment.Center
		c.BackgroundTransparency = 0
		c.BackgroundColor3 = Theme.Colors.Slate
		c.ZIndex = 2
		MenuKit.corner(c, CIRCLE // 2)
		MenuKit.stroke(c, Theme.color("Ink"), 2)
		circles[i] = c
	end

	-- Карточка.
	type Card = {
		frame: Frame,
		pop: UIScale,
		stroke: UIStroke,
		art: GuiObject,
		amount: TextLabel,
		state: TextLabel,
		claim: TextButton,
		lock: TextLabel?,
		shine: Frame?,
		level: number, -- уровень (бонус — LAST + 1)
		premium: boolean,
		bonus: boolean,
		reward: PathReward,
		rarity: Rarity,
		x: number,
		y: number,
	}
	local freeCards: { [number]: Card } = {}
	local paidCards: { [number]: Card } = {}
	local selectCard: (c: Card) -> () = function(_c: Card) end

	local busy = false
	local function requestClaim()
		if busy then
			return
		end
		busy = true
		send("pathClaim", {})
		task.delay(3, function()
			busy = false -- ответ не пришёл — кнопку снова можно нажать
		end)
	end

	local function makeCard(i: number, y: number, r: PathReward, premium: boolean, bonus: boolean): Card
		local x = colX(i)
		local rarity: Rarity = rarityOf(r, bonus)
		local rc = Theme.color(RARITY_COLOR[rarity])
		local level = FIRST + i - 1
		local f = Instance.new("Frame")
		f.Name = (if premium then "Premium" else "Free") .. (if bonus then "Bonus" else tostring(level))
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(CARD_W, CARD_H)
		f.BackgroundColor3 = if premium then Theme.color("Plum") else Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.ClipsDescendants = true
		f.Parent = canvas
		MenuKit.corner(f, 10)
		local stroke = MenuKit.stroke(f, rc, 2)
		local pop = Instance.new("UIScale")
		pop.Parent = f
		-- Нажатие / наведение — описание внизу.
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.Parent = f
		-- Метка редкости и «★» каждого 5-го уровня.
		local tag = MenuKit.label(f, t("path.rarity." .. rarity), 9, Theme.color("Ink"), true)
		tag.Position = UDim2.fromOffset(6, 5)
		tag.BackgroundTransparency = 0
		tag.BackgroundColor3 = rc
		MenuKit.pad(tag, 4, 1)
		MenuKit.corner(tag, 4)
		if not bonus and level % 5 == 0 then
			local star = MenuKit.label(f, "★", 14, Theme.Colors.Gold, true)
			star.AnchorPoint = Vector2.new(1, 0)
			star.Position = UDim2.new(1, -6, 0, 2)
		end
		local main, key, isArt, text = mainPart(r, bonus)
		local art: GuiObject
		if isArt then
			art = CardKit.art(f, key, 88, 58)
			art.Position = UDim2.fromOffset(12, 22)
		else
			art = MenuKit.icon(f, key, 5) -- 40 px
			art.Position = UDim2.fromOffset(36, 28)
		end
		local amount = MenuKit.label(f, text, 13, Theme.Colors.Text, true)
		amount.AutomaticSize = Enum.AutomaticSize.None
		amount.Size = UDim2.new(1, -8, 0, 16)
		amount.Position = UDim2.fromOffset(4, 83)
		amount.TextXAlignment = Enum.TextXAlignment.Center
		amount.TextTruncate = Enum.TextTruncate.AtEnd
		local more = MenuKit.label(f, extras(r, main), 10, Theme.Colors.Gold, true)
		more.AutomaticSize = Enum.AutomaticSize.None
		more.Size = UDim2.new(1, -8, 0, 13)
		more.Position = UDim2.fromOffset(4, 99)
		more.TextXAlignment = Enum.TextXAlignment.Center
		more.TextTruncate = Enum.TextTruncate.AtEnd
		local state = MenuKit.label(f, "", 11, Theme.Colors.Muted, true)
		state.AutomaticSize = Enum.AutomaticSize.None
		state.Size = UDim2.new(1, -8, 0, 22)
		state.Position = UDim2.fromOffset(4, CARD_H - 26)
		state.TextXAlignment = Enum.TextXAlignment.Center
		local claim = MenuKit.button(f, t("path.claim"), "primary", 24)
		claim.Size = UDim2.new(1, -16, 0, 24)
		claim.Position = UDim2.fromOffset(8, CARD_H - 28)
		claim.TextSize = 12
		claim.ZIndex = 3
		claim.Visible = false
		Session.connect(claim.Activated, requestClaim)
		local lock: TextLabel? = nil
		if premium then
			local l = MenuKit.label(f, "🔒", 16, Theme.Colors.Gold, true)
			l.AnchorPoint = Vector2.new(0.5, 0.5)
			l.Position = UDim2.fromOffset(CARD_W - 18, 34)
			l.ZIndex = 4
			lock = l
		end
		local card: Card = {
			frame = f,
			pop = pop,
			stroke = stroke,
			art = art,
			amount = amount,
			state = state,
			claim = claim,
			lock = lock,
			shine = nil,
			level = if bonus then LAST + 1 else level,
			premium = premium,
			bonus = bonus,
			reward = r,
			rarity = rarity,
			x = x,
			y = y,
		}
		Session.connect(hit.Activated, function()
			selectCard(card)
		end)
		Session.connect(hit.MouseEnter, function()
			selectCard(card)
		end)
		return card
	end

	for i = 1, COLUMNS do
		local bonus = i == BONUS_COL
		local level = FIRST + i - 1
		local fr = if bonus then Profile.bonusReward(false) else Profile.pathReward(level)
		local pr = if bonus then Profile.bonusReward(true) else Profile.premiumReward(level)
		freeCards[i] = makeCard(i, 4, fr, false, bonus)
		paidCards[i] = makeCard(i, premiumY, pr, true, bonus)
	end

	-- Блик на готовой карточке (создаётся при первой готовности).
	local function shineOf(c: Card): Frame
		local existing = c.shine
		if existing ~= nil then
			return existing
		end
		local s = Instance.new("Frame")
		s.Name = "Shine"
		s.BackgroundColor3 = Color3.new(1, 1, 1)
		s.BackgroundTransparency = 0.7
		s.BorderSizePixel = 0
		s.Size = UDim2.new(0, 34, 1.6, 0)
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Rotation = 20
		s.ZIndex = 2
		s.Parent = c.frame
		local grad = Instance.new("UIGradient")
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		grad.Parent = s
		c.shine = s
		return s
	end

	---------------------------------------------------------------------------------------------------------------
	-- 4. «Впереди».
	local aheadY = TRACK_Y + trackH + 4
	local aheadLabel = MenuKit.label(window, t("path.ahead"), 13, Theme.Colors.Sky, true)
	aheadLabel.Position = UDim2.fromOffset(PAD + 4, aheadY)
	local aheadRow = Instance.new("Frame")
	aheadRow.Name = "Ahead"
	aheadRow.BackgroundTransparency = 1
	aheadRow.Position = UDim2.fromOffset(PAD, aheadY + 20)
	aheadRow.Size = UDim2.new(1, -2 * PAD, 0, 60)
	aheadRow.Parent = window
	MenuKit.list(aheadRow, 10, true)
	local AHEAD = 5
	type Chip = { frame: Frame, stroke: UIStroke, art: Frame, level: TextLabel, name: TextLabel }
	local aheadChips: { Chip } = {}
	for k = 1, AHEAD do
		local f = Instance.new("Frame")
		f.Name = "Milestone" .. k
		f.LayoutOrder = k
		f.Size = UDim2.fromOffset(((W - 2 * PAD) - (AHEAD - 1) * 10) // AHEAD, 56)
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.Parent = aheadRow
		MenuKit.corner(f, 8)
		local stroke = MenuKit.stroke(f, Theme.Colors.PanelBorder, 1)
		local host = Instance.new("Frame")
		host.BackgroundTransparency = 1
		host.Position = UDim2.fromOffset(5, 5)
		host.Size = UDim2.fromOffset(69, 46)
		host.Parent = f
		local lvl = MenuKit.label(f, "", 12, Theme.Colors.Gold, true)
		lvl.Position = UDim2.fromOffset(80, 6)
		local name = MenuKit.label(f, "", 12, Theme.Colors.Text, true)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.Position = UDim2.fromOffset(80, 22)
		name.Size = UDim2.new(1, -86, 0, 30)
		name.TextWrapped = true
		name.TextYAlignment = Enum.TextYAlignment.Top
		aheadChips[k] = { frame = f, stroke = stroke, art = host, level = lvl, name = name }
	end

	---------------------------------------------------------------------------------------------------------------
	-- 5. Низ.
	divider(FOOTER_Y)
	local detail = MenuKit.label(window, "", 13, Theme.Colors.Text, true)
	detail.AutomaticSize = Enum.AutomaticSize.None
	detail.Position = UDim2.fromOffset(PAD + 4, FOOTER_Y + 10)
	detail.TextTruncate = Enum.TextTruncate.AtEnd
	local how = MenuKit.label(window, t("path.how"), 12, Theme.Colors.Muted)
	how.AutomaticSize = Enum.AutomaticSize.None
	how.Position = UDim2.fromOffset(PAD + 4, FOOTER_Y + 32)
	how.TextWrapped = true
	how.TextYAlignment = Enum.TextYAlignment.Top
	local buyPremium = MenuKit.button(window, "", "primary", 50)
	buyPremium.AnchorPoint = Vector2.new(1, 1)
	buyPremium.Position = UDim2.new(1, -PAD - 280, 1, -16)
	buyPremium.Size = UDim2.fromOffset(290, 50)
	buyPremium.TextSize = 17
	buyPremium.BackgroundColor3 = Theme.color("Orange")
	shimmer(buyPremium)
	local claimAll = MenuKit.button(window, "", "primary", 50)
	claimAll.AnchorPoint = Vector2.new(1, 1)
	claimAll.Position = UDim2.new(1, -PAD, 1, -16)
	claimAll.Size = UDim2.fromOffset(268, 50)
	claimAll.TextSize = 18
	local claimGlow = MenuKit.stroke(claimAll, Theme.Colors.Gold, 3)
	Session.connect(claimAll.Activated, requestClaim)
	Session.connect(buyPremium.Activated, function()
		local id = Config.Shop.Packs.PathPremium.id
		if id == 0 then
			if toast ~= nil then
				toast(t("shop.soon"))
			end
			return
		end
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, id)
	end)

	-- Слой эффектов поверх окна.
	local fx = Instance.new("Frame")
	fx.Name = "Fx"
	fx.BackgroundTransparency = 1
	fx.Size = UDim2.fromScale(1, 1)
	fx.ZIndex = 50
	fx.Parent = window

	---------------------------------------------------------------------------------------------------------------
	-- Состояние профиля.
	type State = {
		level: number,
		claimed: number,
		premium: boolean,
		paid: number,
		earned: number,
		bonus: number,
		bonusPaid: number,
	}
	local function state(): State
		local p = cs.profile
		if p == nil then
			return { level = 1, claimed = 1, premium = false, paid = 1, earned = 0, bonus = 0, bonusPaid = 0 }
		end
		local path = p.path
		if path == nil then
			return {
				level = p.level,
				claimed = p.level,
				premium = false,
				paid = p.level,
				earned = 0,
				bonus = 0,
				bonusPaid = 0,
			}
		end
		local earned = path.bonusEarned or 0
		return {
			level = p.level,
			claimed = path.claimed,
			premium = path.premium == true,
			paid = path.paid or p.level,
			earned = earned,
			bonus = path.bonus or earned,
			bonusPaid = path.bonusPaid or earned,
		}
	end
	local function pending(): number
		local free, paid, bonus = ClientState.rewardsPending(cs)
		return free + paid + bonus
	end
	-- Дошли ли, забрана ли, под замком ли.
	local function cardState(c: Card, s: State): (boolean, boolean, boolean)
		local locked = c.premium and not s.premium
		if c.bonus then
			local got = if c.premium then s.bonusPaid else s.bonus
			return s.earned > 0, s.earned <= got, locked
		end
		local reached = c.level <= s.level
		local done = c.level <= (if c.premium then s.paid else s.claimed)
		return reached, done, locked
	end

	selectCard = function(c: Card)
		local s = state()
		local reached, done, locked = cardState(c, s)
		local road = t(if c.premium then "path.premium" else "path.free")
		local lv = if c.bonus then LAST else c.level
		local text = string.format(t("path.detail"), lv, road, describe(c.reward, c.bonus))
		if locked then
			text ..= t("path.detailNeedPremium")
		elseif not reached and not c.bonus then
			text ..= string.format(t("path.detailWhen"), c.level)
		elseif done then
			text ..= "  ✔"
		end
		detail.Text = text
		detail.TextColor3 = Theme.color(RARITY_COLOR[c.rarity])
		if locked or (not reached and not c.bonus) then
			-- Встряска закрытой карточки.
			for k, dx in { -6, 6, -4, 4, 0 } do
				task.delay((k - 1) * 0.04, function()
					c.frame.Position = UDim2.fromOffset(c.x + dx, c.y)
				end)
			end
		end
	end

	local function setWallet(kind: string, value: number)
		local w = wallet[kind]
		w.value = value
		w.label.Text = Strings.formatInt(value)
	end

	local generalAt: { [number]: string } = {}
	for id, glv in Config.Profile.CommanderLevels :: { [string]: number } do
		if glv > 1 then
			generalAt[glv] = id
		end
	end
	local tierAt: { [number]: number } = {}
	for k, tlv in Config.Ranks.Tiers do
		tierAt[tlv] = k
	end

	local function drawAhead(lv: number)
		type Item = { level: number, art: string?, rank: number?, name: string, color: Color3, premium: boolean }
		local items: { Item } = {}
		for l = lv + 1, LAST do
			if #items >= AHEAD then
				break
			end
			local fr = Profile.pathReward(l)
			local pr = Profile.premiumReward(l)
			if fr.unit ~= nil then
				local unit = fr.unit :: string
				table.insert(items, {
					level = l,
					art = "unlock." .. unit,
					rank = nil,
					name = string.format(t("path.opensUnit"), unitName(unit)),
					color = Theme.color("Orange"),
					premium = false,
				})
			elseif tierAt[l] ~= nil then
				local rank = tierAt[l]
				table.insert(items, {
					level = l,
					art = nil,
					rank = rank,
					name = string.format(t("path.rankAt"), t("rank." .. rank)),
					color = groupColor(rank),
					premium = false,
				})
			elseif generalAt[l] ~= nil then
				table.insert(items, {
					level = l,
					art = nil,
					rank = nil,
					name = string.format(t("path.general"), t("commander." .. generalAt[l])),
					color = Theme.Colors.Sky,
					premium = false,
				})
			end
			if #items < AHEAD and (pr.unit ~= nil or pr.pass ~= nil or pr.cosmetic ~= nil) then
				local _, key, _, name = mainPart(pr, false)
				table.insert(items, {
					level = l,
					art = key,
					rank = nil,
					name = "★ " .. name,
					color = Theme.Colors.Gold,
					premium = true,
				})
			end
		end
		for k = 1, AHEAD do
			local chip = aheadChips[k]
			local it = items[k]
			chip.frame.Visible = it ~= nil
			if it == nil then
				continue
			end
			for _, child in chip.art:GetChildren() do
				child:Destroy()
			end
			local rank, art = it.rank, it.art
			if rank ~= nil then
				local ep = MenuKit.rankIcon(chip.art, rank, 3)
				ep.Position = UDim2.fromOffset(10, -1)
			elseif art ~= nil then
				CardKit.art(chip.art, art, 69, 46)
			else
				local icon = MenuKit.icon(chip.art, "army", 5)
				icon.Position = UDim2.fromOffset(14, 3)
			end
			chip.level.Text = string.format(t("ranks.levelLeft"), it.level, it.level - lv)
			chip.name.Text = it.name
			chip.name.TextColor3 = it.color
			chip.stroke.Color = if it.premium then Theme.Colors.Gold else Theme.Colors.PanelBorder
			chip.frame.BackgroundColor3 = if it.premium then Theme.color("Plum") else Theme.Colors.Backdrop
		end
	end

	local readyCards: { Card } = {}
	local scrolledTo = -1
	local lastFill = -1

	local function paintCard(c: Card, s: State, isNext: boolean)
		local reached, done, locked = cardState(c, s)
		local ready = reached and not done and not locked
		c.claim.Visible = ready
		c.state.Visible = not ready
		c.state.Text = if done then "✔ " .. t("path.claimed") elseif locked then t("path.locked") else "🔒"
		c.state.TextColor3 = if done
			then Theme.color("Lime")
			elseif locked then Theme.Colors.Gold
			else Theme.Colors.Muted
		c.stroke.Color = if ready
			then Theme.Colors.Gold
			elseif isNext then Theme.Colors.Sky
			else Theme.color(RARITY_COLOR[c.rarity])
		c.stroke.Thickness = if ready then 3 else 2
		c.frame.BackgroundTransparency = if reached and not locked then 0 else 0.3
		c.amount.TextColor3 = if reached and not locked then Theme.Colors.Text else Theme.Colors.Muted
		if c.art:IsA("ImageLabel") then
			c.art.ImageTransparency = if reached and not locked then 0 else 0.4
		end
		local lock = c.lock
		if lock ~= nil then
			lock.Visible = locked
		end
		if c.bonus and ready then
			local waiting = s.earned - (if c.premium then s.bonusPaid else s.bonus)
			c.amount.Text = t("path.bonusName") .. " ×" .. waiting
		end
		local shine = c.shine
		if ready then
			table.insert(readyCards, c)
			shineOf(c).Visible = true
		elseif shine ~= nil then
			shine.Visible = false
			c.pop.Scale = 1
		end
	end

	local function draw()
		local p = cs.profile
		local s = state()
		if p ~= nil then
			setWallet("medals", p.medals)
			setWallet("tokens", p.tokens)
			setWallet("crates", p.crates)
		end
		local lv = s.level
		local rank = Ranks.of(lv)
		local into = if p ~= nil then p.xp else 0
		local need = if p ~= nil then p.need else Profile.xpNeeded(1)
		MenuKit.setRank(bigRank, rank, 7)
		rankName.Text = t("rank." .. rank)
		rankName.TextColor3 = groupColor(rank)
		heroStroke.Color = groupColor(rank)
		local percent = math.floor((lv - 1) / (LAST - 1) * 100)
		levelLine.Text = string.format(t("ranks.levelLine"), lv, t("rank.troops." .. rank))
			.. "  ·  "
			.. string.format(t("path.done"), percent)
		local path = if p ~= nil then p.path else nil
		local bonusPer = if path ~= nil then path.bonusPer else nil
		local bonusXp = if path ~= nil then path.bonusXp or 0 else 0
		local frac = 0
		if need > 0 then
			frac = into / need
			xpBar.set(frac)
			xpText.Text = string.format(t("ranks.xp"), into, need, lv + 1)
		elseif bonusPer ~= nil then
			frac = bonusXp / math.max(1, bonusPer)
			xpBar.set(frac)
			xpText.Text = string.format(t("path.bonusLine"), Strings.formatInt(bonusXp), Strings.formatInt(bonusPer))
		else
			xpBar.set(1)
			xpText.Text = t("menu.maxLevel")
		end
		premHead.Text = t(if s.premium then "path.premiumOn" else "path.premiumGives")
		premBody.Text = premiumText
		-- Лента.
		table.clear(readyCards)
		for i = 1, COLUMNS do
			local isNext = i ~= BONUS_COL and FIRST + i - 1 == lv + 1
			paintCard(freeCards[i], s, isNext)
			paintCard(paidCards[i], s, isNext)
		end
		local free, paid, bonus = ClientState.rewardsPending(cs)
		freeSub.Text = string.format(t("path.laneWaiting"), free)
		paidSub.Text = if s.premium then string.format(t("path.laneWaiting"), paid) else t("path.laneLocked")
		-- Линия: до центра пройденного столбца и доля пути к следующему (после 100-го — к бонусу).
		local reachedIndex = lv - FIRST + 1
		local cx = if reachedIndex <= 0 then 0 else (reachedIndex - 1) * COL + CARD_W / 2 + COL * frac
		cx = math.clamp(cx, 0, canvasW - 16)
		if lastFill < 0 then
			fill.Size = UDim2.fromOffset(cx, 6)
		elseif cx ~= lastFill then
			TweenService:Create(
				fill,
				TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(cx, 6) }
			):Play()
		end
		lastFill = cx
		for i, c in circles do
			local reached = if i == BONUS_COL then s.earned > 0 else i <= reachedIndex
			local nextOne = i == reachedIndex + 1
			c.BackgroundColor3 = if reached
				then Theme.Colors.Gold
				elseif nextOne then Theme.Colors.Sky
				else Theme.Colors.Slate
			c.TextColor3 = if reached or nextOne then Theme.color("Ink") else Theme.Colors.Muted
		end
		drawAhead(lv)
		-- Низ.
		local n = free + paid + bonus
		buyPremium.Visible = not s.premium
		buyPremium.Text = string.format(t("path.buy"), Config.Shop.Packs.PathPremium.price)
		local textW = W - 2 * PAD - (if buyPremium.Visible then 600 else 300)
		detail.Size = UDim2.fromOffset(textW, 18)
		how.Size = UDim2.fromOffset(textW, 40)
		claimAll.Text = if n > 0 then string.format(t("path.claimAll"), n) else t("path.nothing")
		claimAll.Active = n > 0
		claimAll.AutoButtonColor = n > 0
		claimAll.BackgroundTransparency = if n > 0 then 0 else 0.5
		claimGlow.Enabled = n > 0
		-- Прокрутка (один раз на открытие): первая готовая, иначе следующий уровень.
		local firstReady = math.min(s.claimed, if s.premium then s.paid else s.claimed) + 1
		local focus = if firstReady <= lv then firstReady else lv + 1
		local index = math.clamp(focus - FIRST + 1, 1, COLUMNS)
		if index ~= scrolledTo then
			scrolledTo = index
			local x = colX(index) + CARD_W / 2
			scroll.CanvasPosition = Vector2.new(math.clamp(x - viewW / 2, 0, math.max(0, canvasW - viewW)), 0)
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- Эффекты.
	local revealSpin: { Frame } = {}
	Session.connect(RunService.Heartbeat, function()
		if not window.Visible then
			return
		end
		local now = os.clock()
		claimGlow.Transparency = 0.15 + 0.5 * (0.5 + 0.5 * math.sin(now * 4))
		-- Золотой отлив бежит слева направо раз в 2.4 с.
		local phase = (now % 2.4) / 2.4
		for _, g in shimmers do
			g.Offset = Vector2.new(phase * 2 - 1, 0)
		end
		-- Готовые карточки: блик проходит, карточка чуть покачивается.
		for idx, c in readyCards do
			local shine = c.shine
			if shine ~= nil then
				shine.Position = UDim2.fromScale((now * 0.6 + idx * 0.13) % 1.6 - 0.3, 0.5)
			end
			c.pop.Scale = 1 + 0.025 * math.sin(now * 3 + idx)
		end
		for _, spin in revealSpin do
			spin.Rotation = (now * 25) % 360
		end
	end)

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

	-- Искры: квадратики разлетаются и гаснут.
	local function sparks(at: Vector2, color: Color3, count: number)
		for _ = 1, count do
			local bit = Instance.new("Frame")
			bit.AnchorPoint = Vector2.new(0.5, 0.5)
			bit.Position = UDim2.fromOffset(at.X, at.Y)
			bit.Size = UDim2.fromOffset(6, 6)
			bit.Rotation = math.random(0, 90)
			bit.BackgroundColor3 = if math.random() < 0.3 then Color3.new(1, 1, 1) else color
			bit.BorderSizePixel = 0
			bit.ZIndex = 52
			bit.Parent = fx
			local a = math.random() * math.pi * 2
			local dist = 40 + math.random() * 60
			TweenService
				:Create(
					bit,
					TweenInfo.new(0.5 + math.random() * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{
						Position = UDim2.fromOffset(at.X + math.cos(a) * dist, at.Y + math.sin(a) * dist),
						Rotation = bit.Rotation + 180,
						BackgroundTransparency = 1,
					}
				)
				:Play()
			task.delay(0.9, function()
				bit:Destroy()
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
		icon.ZIndex = 53
		for _, d in icon:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 53
			end
		end
		-- Дуга: вверх и в сторону, потом в кошелёк.
		local midX = (from.X + dest.X) / 2 + math.random(-40, 40)
		local midY = math.min(from.Y, dest.Y) - 60
		TweenService:Create(
			icon,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(midX, midY) }
		):Play()
		task.delay(0.3, function()
			TweenService:Create(
				icon,
				TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.fromOffset(dest.X, dest.Y) }
			):Play()
			task.delay(0.45, function()
				icon:Destroy()
				local start, goal = target.value, target.value + amount
				target.value = goal
				local steps = 12
				for st = 1, steps do
					task.delay(st * 0.03, function()
						target.label.Text = Strings.formatInt(math.floor(start + (goal - start) * st / steps))
					end)
				end
				TweenService:Create(
					target.pop,
					TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true),
					{ Scale = 1.18 }
				):Play()
				TweenService:Create(
					target.frame,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
					{ BackgroundColor3 = Theme.Colors.Gold }
				):Play()
			end)
		end)
	end

	-- Окно-открытие (новое звание, особая награда, премиум): лучи вращаются, крупно картинка, конфетти. Очередью.
	type Reveal = { head: string, name: string, color: Color3, art: string?, rank: number?, sub: string? }
	local queue: { Reveal } = {}
	local showing = false
	local function confetti(parent: Instance)
		local colors = { "Gold", "Red", "Sky", "Lime", "Orange", "White", "Violet" }
		for k = 1, 40 do
			local bit = Instance.new("Frame")
			bit.Size = UDim2.fromOffset(8, 12)
			bit.Position = UDim2.fromOffset(math.random(40, W - 40), -20)
			bit.Rotation = math.random(0, 90)
			bit.BackgroundColor3 = Theme.color(colors[(k % #colors) + 1])
			bit.BorderSizePixel = 0
			bit.ZIndex = 64
			bit.Parent = parent
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
	end
	local function showNext()
		local item = table.remove(queue, 1)
		if item == nil or not window.Visible then
			showing = false
			table.clear(queue)
			return
		end
		showing = true
		local shade = Instance.new("TextButton")
		shade.Name = "Reveal"
		shade.Text = ""
		shade.AutoButtonColor = false
		shade.Size = UDim2.fromScale(1, 1)
		shade.BackgroundColor3 = Theme.Colors.Backdrop
		shade.BackgroundTransparency = 0.1
		shade.ZIndex = 60
		shade.Parent = fx
		MenuKit.corner(shade, Theme.CornerPx)
		-- Вращающиеся лучи за картинкой.
		local spin = Instance.new("Frame")
		spin.Name = "Rays"
		spin.AnchorPoint = Vector2.new(0.5, 0.5)
		spin.Position = UDim2.new(0.5, 0, 0, 330)
		spin.Size = UDim2.fromOffset(10, 10)
		spin.BackgroundTransparency = 1
		spin.ZIndex = 61
		spin.Parent = shade
		for k = 0, 11 do
			local ray = Instance.new("Frame")
			ray.AnchorPoint = Vector2.new(0.5, 1)
			ray.Position = UDim2.fromScale(0.5, 0.5)
			ray.Size = UDim2.fromOffset(26, 260)
			ray.Rotation = k * 30
			ray.BackgroundColor3 = item.color
			ray.BackgroundTransparency = 0.8
			ray.BorderSizePixel = 0
			ray.ZIndex = 61
			ray.Parent = spin
			local grad = Instance.new("UIGradient")
			grad.Rotation = 90
			grad.Transparency = NumberSequence.new(0, 1)
			grad.Parent = ray
		end
		table.insert(revealSpin, spin)
		local head = MenuKit.label(shade, item.head, 34, Theme.Colors.Gold, true)
		head.FontFace = Theme.FontHeavy
		head.AnchorPoint = Vector2.new(0.5, 0)
		head.Position = UDim2.new(0.5, 0, 0, 110)
		head.ZIndex = 63
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.new(0.5, 0, 0, 330)
		holder.Size = UDim2.fromOffset(240, 160)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 62
		holder.Parent = shade
		local grow = Instance.new("UIScale")
		grow.Scale = 0.2
		grow.Parent = holder
		local rank, art = item.rank, item.art
		if rank ~= nil then
			local ep = MenuKit.rankIcon(holder, rank, 10) -- 160 px
			ep.Position = UDim2.fromOffset(40, 0)
		elseif art ~= nil then
			CardKit.art(holder, art, 240, 160)
		end
		for _, d in holder:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 62
			end
		end
		local name = MenuKit.label(shade, item.name, 28, item.color, true)
		name.AnchorPoint = Vector2.new(0.5, 0)
		name.Position = UDim2.new(0.5, 0, 0, 430)
		name.ZIndex = 63
		local sub = MenuKit.label(shade, item.sub or t("path.reveal.tap"), 14, Theme.Colors.Muted, true)
		sub.AnchorPoint = Vector2.new(0.5, 0)
		sub.Position = UDim2.new(0.5, 0, 0, 474)
		sub.ZIndex = 63
		TweenService:Create(grow, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		confetti(shade)
		local closed = false
		local function hide()
			if closed then
				return
			end
			closed = true
			local i = table.find(revealSpin, spin)
			if i ~= nil then
				table.remove(revealSpin, i)
			end
			shade:Destroy()
			task.delay(0.15, showNext)
		end
		Session.connect(shade.Activated, hide)
		task.delay(4, hide)
	end
	local function reveal(item: Reveal)
		if #queue >= 5 then
			return
		end
		table.insert(queue, item)
		if not showing then
			showNext()
		end
	end

	-- Забор одной карточки: вспышка, подпрыгнуть, лучи, искры, значки в кошелёк.
	local function celebrate(c: Card, r: PathReward, delay: number)
		task.delay(delay, function()
			if not window.Visible then
				return
			end
			local flash = Instance.new("Frame")
			flash.BackgroundColor3 = Color3.new(1, 1, 1)
			flash.BackgroundTransparency = 0.6
			flash.BorderSizePixel = 0
			flash.Size = UDim2.fromScale(1, 1)
			flash.ZIndex = 5
			flash.Parent = c.frame
			TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			task.delay(0.4, function()
				flash:Destroy()
			end)
			TweenService:Create(
				c.pop,
				TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true),
				{ Scale = 1.18 }
			):Play()
			local at = inWindow(c.art)
			local color = if c.premium then Theme.Colors.Gold else Theme.color(RARITY_COLOR[c.rarity])
			rays(at, color)
			sparks(at, color, if c.rarity == "common" then 6 else 14)
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
		local newRank: number? = nil
		local specials: { Reveal } = {}
		for i, item in msg.got :: { any } do
			local r = item.reward :: PathReward
			local index = if item.bonus then BONUS_COL else (tonumber(item.level) or 0) - FIRST + 1
			local card = if item.premium then paidCards[index] else freeCards[index]
			if card ~= nil then
				celebrate(card, r, math.min(i - 1, 12) * 0.15)
			end
			if not item.premium and not item.bonus and tierAt[item.level] ~= nil then
				newRank = tierAt[item.level]
			end
			local unit, pass, cosmetic = r.unit, r.pass, r.cosmetic
			if unit ~= nil then
				table.insert(specials, {
					head = t("path.reveal.unit"),
					name = unitName(unit),
					color = Theme.color("Orange"),
					art = "unlock." .. unit,
				})
			end
			if pass ~= nil then
				table.insert(specials, {
					head = t("path.reveal.pass"),
					name = t("shop." .. pass),
					color = Theme.color("Orange"),
					art = "shop." .. pass,
				})
			end
			if cosmetic ~= nil then
				local kind, id, name = cosmeticName(cosmetic)
				table.insert(specials, {
					head = t(if kind == "title" then "path.reveal.title" else "path.reveal.cosmetic"),
					name = name,
					color = Theme.color("Violet"),
					art = kind .. "." .. id,
				})
			end
		end
		task.delay(math.min(#msg.got, 12) * 0.15 + 0.9, function()
			if not window.Visible then
				return
			end
			local shown = newRank
			if shown ~= nil then
				reveal({ head = t("path.newRank"), name = t("rank." .. shown), color = groupColor(shown), rank = shown })
			end
			for _, sp in specials do
				reveal(sp)
			end
		end)
	end

	-- Покупка премиума: замки слетают, окно «ПРЕМИУМ-ДОРОГА ОТКРЫТА».
	local lastPremium: boolean? = nil
	local function checkPremium()
		local now = state().premium
		if lastPremium == false and now and window.Visible then
			for _, c in paidCards do
				local lock = c.lock
				if lock ~= nil then
					local clone = lock:Clone()
					clone.Visible = true
					clone.Parent = c.frame
					TweenService:Create(
						clone,
						TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Position = lock.Position - UDim2.fromOffset(0, 40), TextTransparency = 1, Rotation = 40 }
					):Play()
					task.delay(0.65, function()
						clone:Destroy()
					end)
				end
			end
			reveal({
				head = t("path.reveal.premium"),
				name = t("shop.PathPremium"),
				color = Theme.Colors.Gold,
				art = "shop.PathPremium",
				sub = t("path.reveal.premiumDesc"),
			})
		end
		lastPremium = now
	end

	local openPos = window.Position
	local function toggle()
		window.Visible = not window.Visible
		if window.Visible then
			scrolledTo = -1
			lastFill = -1
			detail.Text = ""
			-- Въезд снизу с пружинкой.
			window.Position = openPos + UDim2.fromOffset(0, 40)
			TweenService:Create(
				window,
				TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = openPos }
			):Play()
			draw()
			checkPremium()
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
			checkPremium()
		end,
		onClaimed = onClaimed,
		pending = pending,
		window = window,
	}
end

return table.freeze(RanksPanel)
