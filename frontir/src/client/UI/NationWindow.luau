--!strict
--[[
	NationWindow — окно державы (GDD §15й Й7): нажатие на чужую державу. Шапка (портрет, имя, бот, плашка отношения,
	«Предатель»), сравнение «она · вы» (суша, сила, города) с полосой «кто сильнее», действия плитками по группам
	ВОЙНА · ДИПЛОМАТИЯ · РАЗВЕДКА · ЕЩЁ — значок, название, строка «что будет» или почему нельзя (чистый NationCard).
	Рамка зовётся «DeclareWar» (на её место в раскладке HUD и телефона): Main ставит её снизу по центру, на телефоне —
	во всю ширину снизу. Окно мира и требование провинции — у WarPanel и DiplomacyPanel (connect).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationCard = require(Shared:WaitForChild("NationCard"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Strings = require(Shared:WaitForChild("Strings"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type Links = {
	openPeace: ((target: number) -> ())?,
	openDiplomacy: ((target: number) -> ())?,
	demand: ((target: number) -> ())?,
}

export type NationWindow = {
	frame: Frame,
	open: (target: number) -> (),
	close: () -> (),
	isOpen: () -> boolean,
	update: (now: number) -> (),
	connect: (links: Links) -> (),
}

local NationWindow = {}

local WIDTH = 520
local TILE_H = 52

local ICONS: { [string]: string } = {
	declare = "army",
	front = "land",
	peace = "stability",
	demand = "ping",
	alliance = "reinforce",
	pact = "council",
	trade = "convoy",
	trust = "hqReserve",
	gift = "money",
	intel = "threat",
	capital = "home",
	diplomacy = "diplomacy",
}
local GROUP_COLOR: { [string]: string } = { war = "Red", diplo = "Sky", intel = "Gold", more = "Mist" }

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

local function escape(s: string): string
	return (
		string.gsub(s, "[&<>\"']", {
			["&"] = "&amp;",
			["<"] = "&lt;",
			[">"] = "&gt;",
			['"'] = "&quot;",
			["'"] = "&apos;",
		})
	)
end

function NationWindow.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> (),
	toast: (text: string) -> (),
	toFront: (x: number, y: number) -> ()
): NationWindow
	local cfg = Config.Render.NationCard
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local links: Links = {}

	local frame = Instance.new("Frame")
	frame.Name = "DeclareWar"
	frame.Size = UDim2.fromOffset(WIDTH, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Theme.Colors.PanelBg
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Visible = false
	frame.Parent = gui
	MenuKit.corner(frame, 12)
	MenuKit.pad(frame, 14, 12)
	local edge = MenuKit.stroke(frame, Theme.Colors.PanelBorder, 2)
	MenuKit.list(frame, 6)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	UiScale.fitSheet(gui, frame, scale, WIDTH, 8, 0.6) -- §15ё: на телефоне — во всю ширину и по высоте
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = frame

	-- Шапка: портрет | имя, бот | плашка отношения | ×.
	local head = MenuKit.box(frame, "Head", 1)
	head.AutomaticSize = Enum.AutomaticSize.None
	head.Size = UDim2.new(1, 0, 0, 68)
	local portraitHost = MenuKit.box(head, "Portrait")
	portraitHost.AutomaticSize = Enum.AutomaticSize.None
	portraitHost.Size = UDim2.fromOffset(96, 64)
	local portrait: GuiObject? = nil
	local portraitColor = -1
	local name = MenuKit.label(head, "", 20, Theme.Colors.Text, true)
	name.FontFace = Theme.FontHeavy
	name.Position = UDim2.fromOffset(108, 2)
	local sub = MenuKit.label(head, "", 13, Theme.Colors.Muted, false)
	sub.Position = UDim2.fromOffset(108, 30)
	local chip = MenuKit.label(head, "", 12, Theme.color("Ink"), true)
	chip.Position = UDim2.fromOffset(108, 48)
	chip.BackgroundTransparency = 0
	MenuKit.pad(chip, 8, 1)
	MenuKit.corner(chip, 6)
	local traitorChip = MenuKit.label(head, t("nation.rel.traitor"), 12, Theme.color("White"), true)
	traitorChip.BackgroundTransparency = 0
	traitorChip.BackgroundColor3 = Theme.Colors.Alert
	MenuKit.pad(traitorChip, 8, 1)
	MenuKit.corner(traitorChip, 6)
	local close = MenuKit.button(head, "×", "normal", 32)
	close.Size = UDim2.fromOffset(32, 32)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.TextSize = 18

	-- Сравнение «она · вы».
	local compare = MenuKit.box(frame, "Compare", 2)
	compare.AutomaticSize = Enum.AutomaticSize.None
	compare.Size = UDim2.new(1, 0, 0, 50)
	compare.BackgroundTransparency = 0
	compare.BackgroundColor3 = Theme.Colors.Backdrop
	MenuKit.corner(compare, 8)
	local cols: { { cap: TextLabel, value: TextLabel, mine: TextLabel } } = {}
	for k, key in { "land", "power", "cities" } do
		local col = MenuKit.box(compare, "Col")
		col.AutomaticSize = Enum.AutomaticSize.None
		col.Position = UDim2.new((k - 1) / 3, 10, 0, 4)
		col.Size = UDim2.new(1 / 3, -10, 1, -8)
		local cap = MenuKit.label(col, t("nation.cmp." .. key), 11, Theme.Colors.Muted, true)
		local value = MenuKit.label(col, "", 18, Theme.Colors.Text, true)
		value.FontFace = Theme.FontHeavy
		value.Position = UDim2.fromOffset(0, 12)
		local mine = MenuKit.label(col, "", 11, Theme.Colors.Muted, false)
		mine.AnchorPoint = Vector2.new(1, 0)
		mine.Position = UDim2.new(1, -8, 0, 17)
		table.insert(cols, { cap = cap, value = value, mine = mine })
	end
	local balanceRow = MenuKit.box(frame, "Balance", 3)
	balanceRow.AutomaticSize = Enum.AutomaticSize.None
	balanceRow.Size = UDim2.new(1, 0, 0, 22)
	local balanceBack = Instance.new("Frame")
	balanceBack.BorderSizePixel = 0
	balanceBack.Size = UDim2.new(1, 0, 0, 6)
	balanceBack.Parent = balanceRow
	MenuKit.corner(balanceBack, 3)
	local balanceFill = Instance.new("Frame")
	balanceFill.BorderSizePixel = 0
	balanceFill.Size = UDim2.fromScale(0.5, 1)
	balanceFill.Parent = balanceBack
	MenuKit.corner(balanceFill, 3)
	local balanceText = MenuKit.label(balanceRow, "", 12, Theme.Colors.Muted, true)
	balanceText.Position = UDim2.fromOffset(0, 10)

	-- Группы действий: заголовок и плитки.
	type Tile = { button: TextButton, title: TextLabel, line: TextLabel, icon: Frame, stroke: UIStroke }
	local tiles: { [string]: Tile } = {}
	local sections: { [string]: { header: TextLabel, grid: Frame, layout: UIGridLayout } } = {}
	local onAction: (key: string) -> () = function(_key: string) end
	for k, group in NationCard.Groups do
		local header =
			MenuKit.label(frame, t("nation.group." .. group), 12, Theme.color(GROUP_COLOR[group]), true, 3 + k * 2)
		local grid = MenuKit.box(frame, "Group_" .. group, 4 + k * 2)
		grid.Size = UDim2.fromScale(1, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		local layout = Instance.new("UIGridLayout")
		layout.CellPadding = UDim2.fromOffset(8, 8)
		layout.CellSize = UDim2.new(1 / 3, -6, 0, TILE_H)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid
		sections[group] = { header = header, grid = grid, layout = layout }
	end
	local function tileFor(key: string, group: string, order: number): Tile
		local existing = tiles[key]
		if existing ~= nil then
			existing.button.LayoutOrder = order
			return existing
		end
		local b = Instance.new("TextButton")
		b.Name = "Act_" .. key
		b.Text = ""
		b.AutoButtonColor = true
		b.BackgroundColor3 = Theme.Colors.Backdrop
		b.BorderSizePixel = 0
		b.LayoutOrder = order
		b.Parent = sections[group].grid
		MenuKit.corner(b, 8)
		local stroke = MenuKit.stroke(b, Theme.color(GROUP_COLOR[group]), 1)
		local icon = MenuKit.icon(b, ICONS[key] or "hint", 3)
		icon.Position = UDim2.fromOffset(8, 8)
		local title = MenuKit.label(b, t("nation.act." .. key), 14, Theme.Colors.Text, true)
		title.AutomaticSize = Enum.AutomaticSize.None
		title.Position = UDim2.fromOffset(40, 6)
		title.Size = UDim2.new(1, -46, 0, 18)
		title.TextTruncate = Enum.TextTruncate.AtEnd
		local line = MenuKit.label(b, "", 11, Theme.Colors.Muted, false)
		line.AutomaticSize = Enum.AutomaticSize.None
		line.Position = UDim2.fromOffset(40, 24)
		line.Size = UDim2.new(1, -46, 0, 26)
		line.TextWrapped = true
		line.TextYAlignment = Enum.TextYAlignment.Top
		Session.connect(b.Activated, function()
			if b:GetAttribute("Enabled") then
				onAction(key)
			end
		end)
		local tile = { button = b, title = title, line = line, icon = icon, stroke = stroke }
		tiles[key] = tile
		return tile
	end

	-- Состояние.
	local target: number? = nil
	local openUntil = 0
	local nextDraw = 0

	local function nationName(id: number): string
		local n = cs.nations[id]
		if n == nil then
			return "?"
		end
		return if lang == "en" then n.nameEn else n.name
	end
	local function colorOf(id: number): Color3
		local n = cs.nations[id]
		if n ~= nil and n.colorIndex >= 1 then
			local c = NationColors.Colors[n.colorIndex]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Muted
	end
	local function approx(v: number): string
		return if v >= 1000 then string.format("%.1fk", v / 1000) else tostring(math.floor(v + 0.5))
	end
	local function powerOf(id: number): number
		local s = ClientState.statsOf(cs, id)
		if s == nil then
			return 0
		end
		if s.power < 0 or s.frontPower < 0 then
			return -1
		end
		return s.power + s.frontPower
	end
	local function landOf(id: number): number
		local s = ClientState.statsOf(cs, id)
		local total = if cs.task ~= nil then cs.task.land else 0
		if total <= 0 then
			local stats = cs.stats
			if stats ~= nil then
				for _, n in stats.nations do
					total += n.cells
				end
			end
		end
		return if s ~= nil then s.cells / math.max(1, total) * 100 else 0
	end
	local function citiesOf(id: number): number
		local c = 0
		for _, cell in cs.cities do
			if ClientState.ownerAt(cs, cell) == id then
				c += 1
			end
		end
		return c
	end
	local function clock(sec: number): string
		local s = math.max(0, math.ceil(sec))
		return string.format("%d:%02d", s // 60, s % 60)
	end

	local function facts(me: number, id: number, now: number): NationCard.Facts
		local war = ClientState.warBetween(cs, me, id)
		local tr = ClientState.treatyBetween(cs, me, id)
		local trustWait = 0
		if tr ~= nil and tr.kind == "alliance" then
			local age = (tr.age or 0) + (now - cs.diploAt) * ClientState.simRate(cs)
			trustWait = (Config.Alliance.TrustAfterSec - age) / math.max(cs.speed, 1e-6)
		end
		local trade = false
		for _, p in cs.diplo.trade do
			if (p.a == me and p.b == id) or (p.a == id and p.b == me) then
				trade = true
			end
		end
		local mine, theirs = cs.nations[me], cs.nations[id]
		local open = ClientState.unitOpen(cs, "Intel")
		local forces = cs.myForces
		return {
			atWar = war ~= nil and war.active,
			mobilizing = war ~= nil and not war.active,
			treaty = if tr ~= nil then tr.kind else nil,
			breaking = tr ~= nil and tr.breakLeft ~= nil,
			trust = tr ~= nil and tr.trust == true,
			trustWait = trustWait,
			trade = trade,
			cooldown = math.max(0, ClientState.cooldownBetween(cs, me, id) - (now - cs.warsAt)),
			diplomacy = cs.rules.diplomacy ~= false,
			teammate = mine ~= nil and theirs ~= nil and mine.team ~= nil and mine.team == theirs.team,
			intelOpen = open,
			intelWait = ClientState.intelLeft(cs, now) / math.max(cs.speed, 1e-6),
			powerKnown = powerOf(id) >= 0,
			money = if forces ~= nil then forces.economy.money else 0,
			giftMoney = Config.Trade.QuickAmounts.money,
		}
	end

	local function hintOf(a: NationCard.Action, f: NationCard.Facts): string
		if a.why ~= nil then
			local key = "nation.why." .. a.why
			if a.why == "cooldown" then
				return string.format(t(key), math.ceil(f.cooldown))
			elseif a.why == "trustWait" then
				return string.format(t(key), clock(f.trustWait))
			elseif a.why == "intelWait" then
				return string.format(t(key), math.ceil(f.intelWait))
			elseif a.why == "locked" then
				local _, level = ClientState.unitOpen(cs, "Intel")
				return string.format(t(key), level or Config.Unlocks.Items.Intel.level)
			end
			return t(key)
		end
		if a.warn ~= nil then
			return t("nation.warn." .. a.warn)
		end
		local key = "nation.hint." .. a.key
		if a.key == "declare" then
			return string.format(t(key), Config.War.MobilizationSec)
		elseif a.key == "pact" then
			return string.format(t(key), Config.Diplomacy.PactMinutes[1])
		elseif a.key == "trade" then
			return string.format(t(key), math.round(Config.Trade.AgreementIncome * 100))
		elseif a.key == "gift" then
			return string.format(t(key), Strings.formatInt(Config.Trade.QuickAmounts.money))
		elseif a.key == "intel" then
			return string.format(t(key), Strings.formatInt(Config.Intel.Cost), Config.Intel.DurationSec)
		end
		return t(key)
	end

	local function relation(f: NationCard.Facts): (string, Color3)
		if f.atWar then
			return t("nation.rel.war"), Theme.Colors.Alert
		elseif f.mobilizing then
			return t("nation.rel.mobilizing"), Theme.color("Orange")
		elseif f.treaty == "alliance" then
			if f.trust then
				return t("nation.rel.trust"), Theme.Colors.Gold
			end
			return t("nation.rel.alliance"), Theme.color("Meadow")
		elseif f.treaty == "pact" then
			return t("nation.rel.pact"), Theme.Colors.Sky
		end
		return t("nation.rel.peace"), Theme.Colors.Muted
	end

	local function draw(now: number)
		local id, me = target, cs.myNation
		if id == nil or me == nil then
			return
		end
		local f = facts(me, id, now)
		-- Шапка.
		local n = cs.nations[id]
		local ci = if n ~= nil then n.colorIndex else 0
		if ci ~= portraitColor then
			portraitColor = ci
			if portrait ~= nil then
				portrait:Destroy()
			end
			portrait = CardKit.art(portraitHost, "nation." .. math.max(1, ci), 96, 64)
		end
		name.Text = string.format('<font color="%s">%s</font>', hex(colorOf(id)), escape(nationName(id)))
		sub.Text = if n ~= nil
				and n.isBot
				and n.botLevel ~= nil
				and n.personality ~= nil
			then t("bot.level." .. n.botLevel) .. " · " .. t("bot.personality." .. n.personality)
			else t("nation.player")
		local relText, relColor = relation(f)
		chip.Text = relText
		chip.BackgroundColor3 = relColor
		edge.Color = if f.atWar or f.mobilizing then Theme.Colors.Alert else Theme.Colors.PanelBorder
		local traitor = ClientState.isTraitor(cs, id, now, ClientState.simRate(cs))
		traitorChip.Visible = traitor
		traitorChip.Position = UDim2.fromOffset(108 + chip.AbsoluteSize.X / math.max(UiScale.factor(), 1e-3) + 8, 48)
		-- Сравнение.
		local theirPower, myPower = powerOf(id), powerOf(me)
		cols[1].value.Text = string.format("%.1f%%", landOf(id))
		cols[1].mine.Text = string.format(t("nation.cmp.you"), string.format("%.1f%%", landOf(me)))
		cols[2].value.Text = if theirPower < 0 then "?" else approx(theirPower)
		cols[2].mine.Text = string.format(t("nation.cmp.you"), approx(math.max(0, myPower)))
		cols[3].value.Text = tostring(citiesOf(id))
		cols[3].mine.Text = string.format(t("nation.cmp.you"), tostring(citiesOf(me)))
		local bal = NationCard.balance(math.max(0, myPower), if theirPower < 0 then nil else theirPower)
		-- Скрытая сила врага — серая полоса без деления.
		balanceBack.BackgroundColor3 = if bal == nil then Theme.Colors.Slate else colorOf(id)
		balanceFill.BackgroundColor3 = colorOf(me)
		balanceFill.Size = UDim2.fromScale(bal or 0.5, 1)
		balanceFill.Visible = bal ~= nil
		if bal == nil then
			balanceText.Text = t("nation.bal.hidden")
		elseif bal >= 0.55 then
			balanceText.Text = string.format(t("nation.bal.mine"), string.format("%.1f", bal / math.max(1 - bal, 0.01)))
		elseif bal <= 0.45 then
			balanceText.Text =
				string.format(t("nation.bal.theirs"), string.format("%.1f", (1 - bal) / math.max(bal, 0.01)))
		else
			balanceText.Text = t("nation.bal.even")
		end
		-- Действия.
		local phone = UiScale.isPhone(gui)
		local list = NationCard.actions(f)
		local shown: { [string]: boolean } = {}
		for _, group: NationCard.Group in NationCard.Groups do
			local sec = sections[group]
			sec.layout.CellSize = UDim2.new(if phone then 1 / 2 else 1 / 3, -6, 0, TILE_H)
			local items = NationCard.inGroup(list, group)
			sec.header.Visible = #items > 0
			sec.grid.Visible = #items > 0
			for order, a in items do
				local tile = tileFor(a.key, group, order)
				shown[a.key] = true
				tile.button.Visible = true
				tile.button:SetAttribute("Enabled", a.enabled)
				tile.button.AutoButtonColor = a.enabled
				tile.title.TextTransparency = if a.enabled then 0 else 0.45
				-- На телефоне плитка в полокна шире — шрифт крупнее (мелкий текст на экране телефона не прочесть).
				tile.title.TextSize = if phone then 15 else 14
				tile.line.TextSize = if phone then 12 else 11
				tile.line.Text = hintOf(a, f)
				tile.line.TextColor3 = if a.warn ~= nil
					then Theme.color("Orange")
					elseif not a.enabled then Theme.Colors.Alert
					else Theme.Colors.Muted
				tile.stroke.Transparency = if a.enabled then 0.2 else 0.7
			end
		end
		for key, tile in tiles do
			if not shown[key] then
				tile.button.Visible = false
			end
		end
	end

	local function closeWindow()
		target = nil
		frame.Visible = false
	end

	-- Линия фронта с врагом: середина своих клеток у его границы, иначе — его столица (как «К фронту» у войны).
	local function frontOf(me: number, id: number): (number?, number?)
		local w, size = cs.width, cs.width * cs.height
		local sx, sy, k = 0, 0, 0
		for i = 0, size - 1, 3 do
			if ClientState.ownerAt(cs, i) == me then
				local x = i % w
				if
					(x > 0 and ClientState.ownerAt(cs, i - 1) == id)
					or (x < w - 1 and ClientState.ownerAt(cs, i + 1) == id)
					or (i >= w and ClientState.ownerAt(cs, i - w) == id)
					or (i + w < size and ClientState.ownerAt(cs, i + w) == id)
				then
					sx += x
					sy += i // w
					k += 1
				end
			end
		end
		if k > 0 then
			return sx / k + 0.5, sy / k + 0.5
		end
		local n = cs.nations[id]
		if n ~= nil and n.capital ~= nil then
			return n.capital % w + 0.5, n.capital // w + 0.5
		end
		return nil, nil
	end

	onAction = function(key: string)
		local id, me = target, cs.myNation
		if id == nil or me == nil or cs.phase ~= "Play" then
			return
		end
		local who = nationName(id)
		if key == "declare" then
			send("declare", { target = id })
		elseif key == "front" then
			local x, y = frontOf(me, id)
			if x ~= nil and y ~= nil then
				toFront(x, y)
			end
		elseif key == "capital" then
			local n = cs.nations[id]
			if n ~= nil and n.capital ~= nil then
				toFront(n.capital % cs.width + 0.5, n.capital // cs.width + 0.5)
			end
		elseif key == "peace" then
			if links.openPeace ~= nil then
				links.openPeace(id)
			end
		elseif key == "demand" then
			if links.demand ~= nil then
				links.demand(id)
			end
		elseif key == "diplomacy" then
			if links.openDiplomacy ~= nil then
				links.openDiplomacy(id)
			end
		elseif key == "alliance" or key == "pact" or key == "trade" or key == "trust" then
			send("offer", { target = id, offer = if key == "pact" then "pact3" else key })
			toast(string.format(t("nation.sent"), t("nation.act." .. key), who))
		elseif key == "gift" then
			local money = Config.Trade.QuickAmounts.money
			send("transfer", { target = id, money = money, oil = 0, people = 0 })
			toast(string.format(t("nation.gifted"), Strings.formatInt(money), who))
		elseif key == "intel" then
			send("intel", { target = id })
			toast(string.format(t("nation.intelSent"), who))
		end
		closeWindow()
	end

	Session.connect(close.Activated, closeWindow)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.Escape then
			closeWindow()
		end
	end)

	local function open(id: number)
		if cs.myNation == nil or id == cs.myNation or cs.nations[id] == nil then
			return
		end
		local fresh = target ~= id or not frame.Visible
		target = id
		openUntil = os.clock() + cfg.AutoCloseSec
		frame.Visible = true
		draw(os.clock())
		if fresh then
			pop.Scale = 0.9
			TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
	end

	local function update(now: number)
		if not frame.Visible then
			return
		end
		local id = target
		local n = if id ~= nil then cs.nations[id] else nil
		if id == nil or n == nil or not n.alive or cs.phase ~= "Play" or now > openUntil then
			closeWindow()
			return
		end
		if now >= nextDraw then
			nextDraw = now + cfg.RefreshSec
			draw(now)
		end
	end

	return {
		frame = frame,
		open = open,
		close = closeWindow,
		isOpen = function(): boolean
			return frame.Visible
		end,
		update = update,
		connect = function(l: Links)
			for k, v in l :: any do
				(links :: any)[k] = v
			end
		end,
	}
end

return table.freeze(NationWindow)
