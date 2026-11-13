--!strict
--[[
	RanksPanel — окно «Путь командира» 2.0 (GDD §15щ Щ3). Сверху — где вы: погон крупно, звание, уровень, полоса
	опыта, следующее звание; справа — кошелёк (медали, жетоны, ящики), куда летят награды. Середина — лента наград
	по уровням 2…MaxLevel (прокрутка, текущий уровень по центру): у каждого уровня — что даёт (Profile.pathReward),
	над ступенями званий — погон, у уровней генералов — «Генерал: …»; состояние — закрыто / готово (светится) /
	получено. Низ — как получать опыт и «ЗАБРАТЬ ВСЁ (N)» (намерение pathClaim, сервер выдаёт по порядку).
	Анимации забора (onClaimed ← событие pathClaimed): карточка подпрыгивает, за ней лучи, значок награды летит к
	кошельку, счётчик щёлкает; ступень звания — окно «НОВОЕ ЗВАНИЕ» с погоном и салютом.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
	onClaimed: (msg: any) -> (), -- событие pathClaimed: { got = { { level, reward } } }
	pending: () -> number, -- сколько наград ждёт (метка на кнопке в меню)
	window: Frame,
}

local RanksPanel = {}

local W, H = 1000, 640
local BANNER = Config.Render.Banner.MaxPx -- высота картинки-шапки над окном
local NODE_W, NODE_H, GAP = 100, 176, 8

local function groupColor(rank: number): Color3
	return Theme.color(Ranks.GroupColors[Ranks.group(rank)])
end

-- Главная часть награды: что нарисовать крупно и подпись к ней.
local function mainPart(r: PathReward): (string, string, number)
	if r.cosmetic ~= nil then
		return "cosmetic", r.cosmetic, 0
	elseif r.crates > 0 and r.medals == 0 and r.tokens == 0 then
		return "crates", "arsenal", r.crates
	elseif r.tokens > 0 then
		return "tokens", "hint", r.tokens
	end
	return "medals", "money", r.medals
end

function RanksPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> ()
): RanksPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end

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

	-- Заголовок и «×».
	local title = MenuKit.label(window, t("ranks.title"), 30, Theme.Colors.Text, true)
	title.FontFace = Theme.FontHeavy
	title.Position = UDim2.fromOffset(28, 20)
	local sub = MenuKit.label(window, t("path.subtitle"), 15, Theme.Colors.Muted)
	sub.Position = UDim2.fromOffset(28, 58)
	local close = MenuKit.button(window, "×", "normal")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -20, 0, 18)
	close.Size = UDim2.fromOffset(48, 48)

	-- Шапка: погон, звание, уровень, опыт, следующее звание.
	local hero = Instance.new("Frame")
	hero.Name = "Hero"
	hero.Position = UDim2.fromOffset(24, 92)
	hero.Size = UDim2.new(1, -48, 0, 150)
	hero.BackgroundColor3 = Theme.Colors.Backdrop
	hero.BorderSizePixel = 0
	hero.Parent = window
	MenuKit.corner(hero, 12)
	local heroStroke = MenuKit.stroke(hero, Theme.Colors.PanelBorder, 2)
	local bigRank = MenuKit.rankIcon(hero, 1, 8) -- 128 px
	bigRank.Position = UDim2.fromOffset(18, 11)
	local nowLabel = MenuKit.label(hero, t("ranks.now"), 13, Theme.Colors.Sky, true)
	nowLabel.Position = UDim2.fromOffset(166, 16)
	local rankName = MenuKit.label(hero, "", 32, Theme.Colors.Text, true)
	rankName.FontFace = Theme.FontHeavy
	rankName.Position = UDim2.fromOffset(166, 34)
	local levelLine = MenuKit.label(hero, "", 16, Theme.Colors.Text)
	levelLine.Position = UDim2.fromOffset(166, 76)
	local xpHost = Instance.new("Frame")
	xpHost.BackgroundTransparency = 1
	xpHost.Position = UDim2.fromOffset(166, 104)
	xpHost.Size = UDim2.fromOffset(380, 12)
	xpHost.Parent = hero
	local xpBar = MenuKit.bar(xpHost, 12, Theme.Colors.Sky)
	local xpText = MenuKit.label(hero, "", 13, Theme.Colors.Muted)
	xpText.Position = UDim2.fromOffset(166, 122)
	local nextIcon = MenuKit.rankIcon(hero, 2, 3)
	nextIcon.Position = UDim2.fromOffset(566, 22)
	local nextTitle = MenuKit.label(hero, t("ranks.next"), 12, Theme.Colors.Sky, true)
	nextTitle.Position = UDim2.fromOffset(620, 22)
	local nextName = MenuKit.label(hero, "", 17, Theme.Colors.Text, true)
	nextName.Position = UDim2.fromOffset(620, 40)
	local nextWhen = MenuKit.label(hero, "", 13, Theme.Colors.Gold)
	nextWhen.Position = UDim2.fromOffset(620, 64)

	-- Кошелёк справа в шапке: сюда летят награды.
	type Wallet = { frame: Frame, label: TextLabel, value: number }
	local wallet: { [string]: Wallet } = {}
	for k, kind in { "medals", "tokens", "crates" } do
		local row = Instance.new("Frame")
		row.Name = "Wallet_" .. kind
		row.AnchorPoint = Vector2.new(1, 0)
		row.Position = UDim2.new(1, -16, 0, 14 + (k - 1) * 42)
		row.Size = UDim2.fromOffset(150, 36)
		row.BackgroundColor3 = Theme.Colors.PanelBg
		row.BorderSizePixel = 0
		row.Parent = hero
		MenuKit.corner(row, 8)
		MenuKit.stroke(row, Theme.Colors.Gold, 1)
		local icon =
			MenuKit.icon(row, if kind == "medals" then "money" elseif kind == "tokens" then "hint" else "arsenal", 3)
		icon.Position = UDim2.fromOffset(8, 6)
		local label = MenuKit.label(row, "0", 18, Theme.Colors.Gold, true)
		label.AnchorPoint = Vector2.new(1, 0.5)
		label.Position = UDim2.new(1, -10, 0.5, 0)
		label.TextXAlignment = Enum.TextXAlignment.Right
		wallet[kind] = { frame = row, label = label, value = 0 }
	end

	-- Лента наград.
	local track = Instance.new("ScrollingFrame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(24, 258)
	track.Size = UDim2.new(1, -48, 0, NODE_H + 28)
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.ScrollingDirection = Enum.ScrollingDirection.X
	track.AutomaticCanvasSize = Enum.AutomaticSize.X
	track.CanvasSize = UDim2.new()
	track.ScrollBarThickness = 6
	track.ScrollBarImageColor3 = Theme.Colors.Gold
	track.ElasticBehavior = Enum.ElasticBehavior.Never
	track.Parent = window
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Size = UDim2.fromOffset(0, NODE_H + 12)
	row.Position = UDim2.fromOffset(0, 6)
	row.Parent = track
	local rowList = MenuKit.list(row, GAP, true)
	rowList.VerticalAlignment = Enum.VerticalAlignment.Top
	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingLeft = UDim.new(0, 4)
	rowPad.PaddingRight = UDim.new(0, 4)
	rowPad.Parent = row

	-- Генерал по уровню (§11.2): уровень → кого открывает.
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

	type Node = {
		frame: Frame,
		pop: UIScale,
		stroke: UIStroke,
		top: Frame,
		art: GuiObject,
		amount: TextLabel,
		state: TextLabel,
		claim: TextButton,
		level: number,
		kind: string,
	}
	local nodes: { [number]: Node } = {}
	local claimAll: TextButton
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

	for lv = 2, Config.Profile.MaxLevel do
		local r = Profile.pathReward(lv)
		local f = Instance.new("Frame")
		f.Name = "Level" .. lv
		f.LayoutOrder = lv
		f.Size = UDim2.fromOffset(NODE_W, NODE_H)
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.Parent = row
		MenuKit.corner(f, 10)
		local stroke = MenuKit.stroke(f, Theme.Colors.PanelBorder, 2)
		local pop = Instance.new("UIScale")
		pop.Parent = f
		-- Полоса сверху: пройден ли уровень.
		local top = Instance.new("Frame")
		top.Size = UDim2.new(1, -16, 0, 4)
		top.Position = UDim2.fromOffset(8, 6)
		top.BorderSizePixel = 0
		top.BackgroundColor3 = Theme.Colors.Slate
		top.Parent = f
		MenuKit.corner(top, 2)
		local lvLabel = MenuKit.label(f, string.format(t("ranks.level"), lv), 13, Theme.Colors.Muted, true)
		lvLabel.Position = UDim2.fromOffset(8, 14)
		local tier = tierAt[lv]
		if tier ~= nil then
			local ep = MenuKit.rankIcon(f, tier, 2)
			ep.AnchorPoint = Vector2.new(1, 0)
			ep.Position = UDim2.new(1, -6, 0, 12)
			lvLabel.TextColor3 = groupColor(tier)
		end
		local kind, what, n = mainPart(r)
		local art: GuiObject
		if kind == "cosmetic" then
			local cKind, cId = string.match(what, "^(%a+):(%a+)$")
			art = CardKit.art(f, (cKind or "pattern") .. "." .. (cId or ""), 80, 54)
			art.Position = UDim2.fromOffset(10, 48)
		else
			art = MenuKit.icon(f, what, 5) -- 40 px
			art.Position = UDim2.fromOffset(30, 52)
		end
		local text = if kind == "cosmetic"
			then t("path.cosmetic." .. (string.match(what, "^(%a+):") or "pattern"))
			else "+" .. Strings.formatInt(n)
		local extra: { string } = {}
		if kind ~= "crates" and r.crates > 0 then
			table.insert(extra, string.format(t("path.crates"), r.crates))
		end
		if kind ~= "tokens" and r.tokens > 0 then
			table.insert(extra, string.format(t("path.tokens"), r.tokens))
		end
		if kind ~= "medals" and kind ~= "tokens" and r.medals > 0 then
			table.insert(extra, "+" .. Strings.formatInt(r.medals))
		end
		local amount = MenuKit.label(f, text, 15, Theme.Colors.Text, true)
		amount.AutomaticSize = Enum.AutomaticSize.None
		amount.Size = UDim2.new(1, -8, 0, 18)
		amount.Position = UDim2.fromOffset(4, 104)
		amount.TextXAlignment = Enum.TextXAlignment.Center
		amount.TextTruncate = Enum.TextTruncate.AtEnd
		local more = MenuKit.label(f, table.concat(extra, " · "), 11, Theme.Colors.Gold, true)
		more.AutomaticSize = Enum.AutomaticSize.None
		more.Size = UDim2.new(1, -8, 0, 14)
		more.Position = UDim2.fromOffset(4, 122)
		more.TextXAlignment = Enum.TextXAlignment.Center
		more.TextTruncate = Enum.TextTruncate.AtEnd
		local general = generalAt[lv]
		if general ~= nil and #extra == 0 then
			more.Text = string.format(t("path.general"), t("commander." .. general))
		end
		local state = MenuKit.label(f, "", 12, Theme.Colors.Muted, true)
		state.AutomaticSize = Enum.AutomaticSize.None
		state.Size = UDim2.new(1, -8, 0, 28)
		state.Position = UDim2.fromOffset(4, NODE_H - 36)
		state.TextXAlignment = Enum.TextXAlignment.Center
		local claim = MenuKit.button(f, t("path.claim"), "primary", 28)
		claim.Size = UDim2.new(1, -16, 0, 28)
		claim.Position = UDim2.fromOffset(8, NODE_H - 36)
		claim.TextSize = 13
		claim.Visible = false
		Session.connect(claim.Activated, requestClaim)
		nodes[lv] = {
			frame = f,
			pop = pop,
			stroke = stroke,
			top = top,
			art = art,
			amount = amount,
			state = state,
			claim = claim,
			level = lv,
			kind = kind,
		}
	end

	-- Низ: как получать опыт и «ЗАБРАТЬ ВСЁ».
	local how = MenuKit.wrapLabel(window, t("ranks.how"), 14, Theme.Colors.Muted)
	how.Position = UDim2.fromOffset(28, H - 74)
	how.Size = UDim2.new(1, -340, 0, 0)
	claimAll = MenuKit.button(window, "", "primary", 52)
	claimAll.AnchorPoint = Vector2.new(1, 1)
	claimAll.Position = UDim2.new(1, -24, 1, -20)
	claimAll.Size = UDim2.fromOffset(280, 52)
	claimAll.TextSize = 18
	Session.connect(claimAll.Activated, requestClaim)
	local claimGlow = MenuKit.stroke(claimAll, Theme.Colors.Gold, 3)

	-- Слой анимаций поверх окна (летящие значки, лучи, «НОВОЕ ЗВАНИЕ»).
	local fx = Instance.new("Frame")
	fx.Name = "Fx"
	fx.BackgroundTransparency = 1
	fx.Size = UDim2.fromScale(1, 1)
	fx.ZIndex = 50
	fx.Parent = window

	local function level(): (number, number, number)
		local p = cs.profile
		if p == nil then
			return 1, 0, Profile.xpNeeded(1)
		end
		return p.level, p.xp, p.need
	end
	local function claimedUpTo(): number
		local p = cs.profile
		return if p ~= nil and p.path ~= nil then p.path.claimed else 1
	end
	local function pending(): number
		local lv = level()
		return math.max(0, lv - claimedUpTo())
	end

	local function setWallet(kind: string, value: number)
		local w = wallet[kind]
		w.value = value
		w.label.Text = Strings.formatInt(value)
	end

	local scrolledTo = -1
	local function draw()
		local lv, into, need = level()
		local rank = Ranks.of(lv)
		local claimed = claimedUpTo()
		MenuKit.setRank(bigRank, rank, 8)
		rankName.Text = t("rank." .. rank)
		rankName.TextColor3 = groupColor(rank)
		heroStroke.Color = groupColor(rank)
		levelLine.Text = string.format(t("ranks.levelLine"), lv, t("rank.troops." .. rank))
		if need > 0 then
			xpBar.set(into / need)
			xpText.Text = string.format(t("ranks.xp"), into, need, lv + 1)
		else
			xpBar.set(1)
			xpText.Text = t("menu.maxLevel")
		end
		local nextAt = Ranks.nextAt(lv)
		nextIcon.Visible = nextAt ~= nil
		nextTitle.Visible = nextAt ~= nil
		nextName.Visible = nextAt ~= nil
		nextWhen.Visible = nextAt ~= nil
		if nextAt ~= nil then
			MenuKit.setRank(nextIcon, rank + 1, 3)
			nextName.Text = t("rank." .. (rank + 1))
			nextWhen.Text = string.format(t("ranks.nextWhen"), nextAt, nextAt - lv)
		end
		local p = cs.profile
		if p ~= nil then
			setWallet("medals", p.medals)
			setWallet("tokens", p.tokens)
			setWallet("crates", p.crates)
		end
		for l, node in nodes do
			local reached = l <= lv
			local done = l <= claimed
			local ready = reached and not done
			node.top.BackgroundColor3 = if reached then Theme.Colors.Gold else Theme.Colors.Slate
			node.claim.Visible = ready
			node.state.Visible = not ready
			node.state.Text = if done then "✔ " .. t("path.claimed") else "🔒"
			node.state.TextColor3 = if done then Theme.color("Lime") else Theme.Colors.Muted
			node.stroke.Color = if ready
				then Theme.Colors.Gold
				elseif l == lv + 1 then Theme.Colors.Sky
				elseif tierAt[l] ~= nil then groupColor(tierAt[l])
				else Theme.Colors.PanelBorder
			node.stroke.Thickness = if ready then 3 else 2
			node.frame.BackgroundTransparency = if reached then 0 else 0.35
			node.amount.TextColor3 = if reached then Theme.Colors.Text else Theme.Colors.Muted
			if node.art:IsA("ImageLabel") then
				node.art.ImageTransparency = if reached then 0 else 0.5
			end
		end
		local n = pending()
		claimAll.Text = if n > 0 then string.format(t("path.claimAll"), n) else t("path.nothing")
		claimAll.Active = n > 0
		claimAll.AutoButtonColor = n > 0
		claimAll.BackgroundTransparency = if n > 0 then 0 else 0.5
		claimGlow.Enabled = n > 0
		-- Прокрутка: первая награда «готово», иначе текущий уровень — по центру (один раз на открытие).
		local focus = if n > 0 then claimed + 1 else lv + 1
		focus = math.clamp(focus, 2, Config.Profile.MaxLevel)
		if focus ~= scrolledTo then
			scrolledTo = focus
			local x = 4 + (focus - 2) * (NODE_W + GAP) + NODE_W / 2
			local viewW = W - 48
			track.CanvasPosition = Vector2.new(math.max(0, x - viewW / 2), 0)
		end
	end

	-- Пульс «готово»: кнопки забрать и «ЗАБРАТЬ ВСЁ» мягко дышат.
	Session.connect(game:GetService("RunService").Heartbeat, function()
		if not window.Visible then
			return
		end
		local k = 0.5 + 0.5 * math.sin(os.clock() * 4)
		claimGlow.Transparency = 0.15 + 0.5 * k
	end)

	-- Точка узла / кошелька в координатах окна (без масштабов).
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
			local tween = TweenService:Create(
				ray,
				TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(6, 70), BackgroundTransparency = 1 }
			)
			tween:Play()
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
		local up = TweenService:Create(
			icon,
			TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(from.X, from.Y - 40) }
		)
		up:Play()
		task.delay(0.25, function()
			local go = TweenService:Create(
				icon,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.fromOffset(dest.X, dest.Y) }
			)
			go:Play()
			task.delay(0.5, function()
				icon:Destroy()
				-- Счётчик щёлкает к новому значению, строка кошелька вспыхивает.
				local start, goal = target.value, target.value + amount
				target.value = goal
				local steps = 10
				for s = 1, steps do
					task.delay(s * 0.03, function()
						target.label.Text = Strings.formatInt(math.floor(start + (goal - start) * s / steps))
					end)
				end
				local flash = TweenService:Create(
					target.frame,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
					{ BackgroundColor3 = Theme.Colors.Gold }
				)
				flash:Play()
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

	local function onClaimed(msg: any)
		busy = false
		if type(msg) ~= "table" or type(msg.got) ~= "table" then
			return
		end
		local newRank: number? = nil
		for i, item in msg.got :: { { level: number, reward: PathReward } } do
			local node = nodes[item.level]
			local r = item.reward
			if tierAt[item.level] ~= nil then
				newRank = tierAt[item.level]
			end
			if node == nil then
				continue
			end
			-- Видимые — по одному с паузой; далёкие (за краем ленты) — без анимации.
			local delay = math.min(i - 1, 10) * 0.18
			task.delay(delay, function()
				if not window.Visible then
					return
				end
				local pop = TweenService:Create(
					node.pop,
					TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true),
					{ Scale = 1.15 }
				)
				pop:Play()
				local at = inWindow(node.art)
				rays(at, Theme.Colors.Gold)
				if r.medals > 0 then
					fly(at, "money", "medals", r.medals)
				end
				if r.tokens > 0 then
					fly(at + Vector2.new(-16, 0), "hint", "tokens", r.tokens)
				end
				if r.crates > 0 then
					fly(at + Vector2.new(16, 0), "arsenal", "crates", r.crates)
				end
			end)
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
			scrolledTo = -1
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
