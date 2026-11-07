--!strict
--[[
	MatchHud — интерфейс матча, этапы 2–3 (полный HUD — этап 4, GDD §10):
	- сверху по центру: фаза — ожидание, выбор старта с таймером, время матча;
	- слева сверху: держава, люди / максимум, прирост в секунду, доля суши, люди в атаках;
	- справа сверху: лидеры по доле суши;
	- слева снизу: ползунок «Атака N%» (кнопки −/+ и полоса, всё от 44 px), активные атаки и фронты с отменой
	  (сила войск, перевес, «нет снабжения» красным), над ними — лента событий (4 строки, гаснут через 8 с:
	  отказы сервера, войны, мир, павшие державы; нападение на вас — красным).
	HUD живёт в отдельном ScreenGui с ScreenInsets = CoreUISafeInsets: Roblox сам держит его вне своих кнопок
	(лого, меню, чат) и выреза экрана телефона, поэтому отступы считаются от 0.
	Нажатие на карту (tapCell): в фазе выбора — точка старта; в игре — атака на ничью землю или страну, с которой
	идёт война, с силой из ползунка (нажатая клетка — главное направление удара); страна без войны —
	onNationTap (предложить объявить войну, §6.7а).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Protocol = require(Shared:WaitForChild("Net"):WaitForChild("Protocol"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))

local ResourceBar = require(script.Parent:WaitForChild("ResourceBar"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState
type MapData = MapDataModule.MapData

export type Hud = {
	refresh: () -> (),
	update: (now: number) -> (),
	tapCell: (cell: number) -> (),
	toast: (text: string) -> (),
	alert: (text: string) -> (), -- строка ленты красным (на вас напали)
	onEvents: (events: { any }) -> (),
	percent: () -> number, -- ползунок «Атака» (доля 0..1): им же — сколько войск на высадку (§6.12)
	setPercent: (p: number) -> (), -- §15л ч.2: кнопки доли атаки в командной полосе
	values: () -> ResourceBar.Values?, -- §15л ч.2: ресурсы своей державы (для командной полосы)
}

local MatchHud = {}

local BUTTON = Config.Render.MinTouchTargetPx
local GAP = 8

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

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

local function nationHex(colorIndex: number): string
	if colorIndex < 1 then
		return hex(Theme.Colors.Text)
	end
	local c = NationColors.Colors[colorIndex]
	return string.format("#%02x%02x%02x", c.r, c.g, c.b)
end

local function panel(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Theme.Colors.PanelBg
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	f.AutomaticSize = Enum.AutomaticSize.XY
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, GAP)
	pad.PaddingRight = UDim.new(0, GAP)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = f
	f.Parent = parent
	return f
end

local function richLabel(parent: Instance, size: number): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.Size = UDim2.fromOffset(0, 0)
	t.RichText = true
	t.FontFace = Theme.Font
	t.TextSize = size
	t.TextColor3 = Theme.Colors.Text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Text = ""
	t.Parent = parent
	return t
end

local function button(parent: Instance, text: string, width: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, BUTTON)
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.FontFace = Theme.FontBold
	b.TextSize = 20
	b.TextColor3 = Theme.Colors.Gold
	b.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = b
	b.Parent = parent
	return b
end

function MatchHud.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	map: MapData,
	send: (string, { [string]: any }) -> (),
	onNationTap: (owner: number) -> (), -- нажатие на страну, с которой нет войны (объявление войны)
	provinces: Provinces.ProvinceSet -- имена провинций (восстания в ленте, §6.10)
): Hud
	local cfg = Config.Expansion
	local percent = cfg.DefaultPercent
	local gold, sky, alert = hex(Theme.Colors.Gold), hex(Theme.Colors.Sky), hex(Theme.Colors.Alert)
	local muted = hex(Theme.Colors.Muted)
	local green = hex(Theme.color("Lime"))

	local totalLand = 0
	for i = 0, map.width * map.height - 1 do
		if Config.Terrain[MapDataModule.getTerrain(map, i)].borderPassable then
			totalLand += 1
		end
	end

	local function nationName(id: number): string
		if id == 0 then
			return Strings.get("hud.neutral", lang)
		end
		local n = cs.nations[id]
		if n == nil then
			return "?"
		end
		return if lang == "en" then n.nameEn else n.name
	end

	-- Сверху по центру: фаза.
	local banner = panel(gui, "PhaseBanner")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, GAP)
	local bannerLayout = Instance.new("UIListLayout")
	bannerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bannerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bannerLayout.Padding = UDim.new(0, 4)
	bannerLayout.Parent = banner
	local bannerText = richLabel(banner, 18)
	bannerText.TextXAlignment = Enum.TextXAlignment.Center
	bannerText.LayoutOrder = 1
	-- §15л ч.5 Верх матча как в похожих играх: одна панель — слева «Время матча», справа «Контроль суши» (полоса до
	-- цели победы, белая черта — ваша доля, подпись «Вы N%» и лидер). Остальное (режим, потоп, пауза) — строками ниже.
	local top = Instance.new("Frame")
	top.Name = "MatchTop"
	top.BackgroundTransparency = 1
	top.AutomaticSize = Enum.AutomaticSize.XY
	top.Size = UDim2.fromOffset(0, 0)
	top.LayoutOrder = 0
	top.Visible = false
	top.Parent = banner
	local topList = Instance.new("UIListLayout")
	topList.FillDirection = Enum.FillDirection.Horizontal
	topList.VerticalAlignment = Enum.VerticalAlignment.Center
	topList.SortOrder = Enum.SortOrder.LayoutOrder
	topList.Padding = UDim.new(0, 16)
	topList.Parent = top
	local function column(order: number): Frame
		local c = Instance.new("Frame")
		c.BackgroundTransparency = 1
		c.AutomaticSize = Enum.AutomaticSize.XY
		c.Size = UDim2.fromOffset(0, 0)
		c.LayoutOrder = order
		c.Parent = top
		local l = Instance.new("UIListLayout")
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Padding = UDim.new(0, 2)
		l.Parent = c
		return c
	end
	local timeCol = column(1)
	local timeHead = richLabel(timeCol, 12)
	timeHead.TextColor3 = Theme.Colors.Muted
	timeHead.Text = Strings.get("hud.matchTime", lang)
	timeHead.LayoutOrder = 1
	local timeBig = richLabel(timeCol, 26)
	timeBig.FontFace = Font.fromEnum(Enum.Font.Arcade)
	timeBig.LayoutOrder = 2
	local timeSub = richLabel(timeCol, 12)
	timeSub.TextColor3 = Theme.Colors.Sky
	timeSub.LayoutOrder = 3
	local divider = Instance.new("Frame")
	divider.BorderSizePixel = 0
	divider.BackgroundColor3 = Theme.Colors.PanelBorder
	divider.Size = UDim2.fromOffset(2, 44)
	divider.LayoutOrder = 2
	divider.Parent = top
	local controlCol = column(3)
	local controlHead = Instance.new("Frame")
	controlHead.BackgroundTransparency = 1
	controlHead.Size = UDim2.fromOffset(320, 16)
	controlHead.LayoutOrder = 1
	controlHead.Parent = controlCol
	local controlTitle = richLabel(controlHead, 12)
	controlTitle.TextColor3 = Theme.Colors.Muted
	controlTitle.Text = Strings.get("hud.controlTitle", lang)
	local goalText = richLabel(controlHead, 12)
	goalText.AnchorPoint = Vector2.new(1, 0)
	goalText.Position = UDim2.fromScale(1, 0)
	goalText.TextXAlignment = Enum.TextXAlignment.Right
	goalText.TextColor3 = Theme.Colors.Gold
	goalText.FontFace = Theme.FontBold
	local leaderBar = Instance.new("Frame")
	leaderBar.Name = "LeaderBar"
	leaderBar.BackgroundColor3 = Theme.Colors.Backdrop
	leaderBar.BorderSizePixel = 0
	leaderBar.Size = UDim2.fromOffset(320, 10)
	leaderBar.LayoutOrder = 2
	leaderBar.Parent = controlCol
	local leaderFill = Instance.new("Frame")
	leaderFill.BorderSizePixel = 0
	leaderFill.Size = UDim2.fromScale(0, 1)
	leaderFill.Parent = leaderBar
	local myMark = Instance.new("Frame")
	myMark.Name = "Me"
	myMark.AnchorPoint = Vector2.new(0.5, 0.5)
	myMark.Size = UDim2.fromOffset(3, 16)
	myMark.Position = UDim2.fromScale(0, 0.5)
	myMark.BackgroundColor3 = Theme.color("White")
	myMark.BorderSizePixel = 0
	myMark.ZIndex = 3
	myMark.Parent = leaderBar
	local controlText = richLabel(controlCol, 13)
	controlText.LayoutOrder = 3
	-- Справа сверху — место по суше «#N · M%» (стоит первым в столбике TopRight, Main.client).
	local placeChip = panel(gui, "PlaceChip")
	placeChip.AnchorPoint = Vector2.new(1, 0)
	placeChip.Position = UDim2.new(1, -12, 0, GAP)
	placeChip.Visible = false
	local placeText = richLabel(placeChip, 20)
	placeText.FontFace = Theme.FontBold
	placeText.TextColor3 = Theme.Colors.Gold

	-- Слева сверху: полоса ресурсов «как в игре» (§15д ч.5), под ней — держава.
	local resources = ResourceBar.new(gui, lang)
	local nationPanel = panel(gui, "NationPanel")
	nationPanel.Position = UDim2.fromOffset(12, GAP + 48)
	local nationText = richLabel(nationPanel, 15)
	nationPanel.Visible = false

	-- Справа сверху: лидеры.
	local leaders = panel(gui, "Leaders")
	leaders.AnchorPoint = Vector2.new(1, 0)
	leaders.Position = UDim2.new(1, -12, 0, GAP)
	local leadersText = richLabel(leaders, 14)
	leaders.Visible = false

	-- Слева снизу: ползунок атаки, атаки, сообщения.
	local bottom = Instance.new("Frame")
	bottom.Name = "AttackArea"
	bottom.BackgroundTransparency = 1
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.new(0, 12, 1, -12)
	bottom.Size = UDim2.fromOffset(320, 0)
	bottom.AutomaticSize = Enum.AutomaticSize.Y
	bottom.Parent = gui
	local bottomLayout = Instance.new("UIListLayout")
	bottomLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bottomLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	bottomLayout.Padding = UDim.new(0, 6)
	bottomLayout.Parent = bottom

	-- Лента событий (GDD §10): до FeedLines строк, каждая гаснет через FeedSec; новые — снизу.
	local feed = Instance.new("Frame")
	feed.Name = "Feed"
	feed.BackgroundTransparency = 1
	feed.Size = UDim2.fromOffset(320, 0)
	feed.AutomaticSize = Enum.AutomaticSize.Y
	feed.LayoutOrder = 1
	feed.Parent = bottom
	local feedLayout = Instance.new("UIListLayout")
	feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
	feedLayout.Padding = UDim.new(0, 2)
	feedLayout.Parent = feed
	type FeedLine = { label: TextLabel, untilTime: number }
	local feedLines: { FeedLine } = {}
	local feedOrder = 0

	-- Строки активных атак (пул, чтобы кнопки не пересоздавались 5 раз в секунду).
	type Row = { frame: Frame, text: TextLabel, cancel: TextButton, target: number }
	local rows: { Row } = {}
	for k = 1, cfg.MaxAttacks do
		local rowFrame = panel(bottom, "AttackRow" .. k)
		rowFrame.AutomaticSize = Enum.AutomaticSize.None
		rowFrame.Size = UDim2.fromOffset(320, BUTTON + 4)
		rowFrame.LayoutOrder = 1 + k
		rowFrame.Visible = false
		local text = richLabel(rowFrame, 14)
		text.Position = UDim2.fromOffset(0, 2)
		local cancel = button(rowFrame, "×", BUTTON)
		cancel.AnchorPoint = Vector2.new(1, 0.5)
		cancel.Position = UDim2.fromScale(1, 0.5)
		local row: Row = { frame = rowFrame, text = text, cancel = cancel, target = -1 }
		Session.connect(cancel.Activated, function()
			if row.target >= 0 then
				send("cancel", { target = row.target })
			end
		end)
		table.insert(rows, row)
	end

	local slider = panel(bottom, "AttackSlider")
	slider.LayoutOrder = 100
	slider.AutomaticSize = Enum.AutomaticSize.None
	slider.Size = UDim2.fromOffset(320, BUTTON + 34)
	local sliderTitle = richLabel(slider, 16)
	local minus = button(slider, "−", BUTTON)
	minus.Position = UDim2.fromOffset(0, 26)
	local plus = button(slider, "+", BUTTON)
	plus.AnchorPoint = Vector2.new(1, 0)
	plus.Position = UDim2.new(1, 0, 0, 26)
	local bar = Instance.new("TextButton")
	bar.Name = "Bar"
	bar.Text = ""
	bar.AutoButtonColor = false
	bar.BackgroundColor3 = Theme.Colors.Backdrop
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(BUTTON + GAP, 26)
	bar.Size = UDim2.new(1, -2 * (BUTTON + GAP), 0, BUTTON)
	bar.Parent = slider
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Theme.Colors.Gold
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(percent, 1)
	fill.Parent = bar
	slider.Visible = false

	local function setPercent(p: number)
		local step = cfg.PercentStep
		percent = math.clamp(math.round(p / step) * step, cfg.MinPercent, cfg.MaxPercent)
		fill.Size = UDim2.fromScale(percent, 1)
		sliderTitle.Text = string.format(Strings.get("hud.attack", lang), math.round(percent * 100))
			.. string.format(
				' <font color="%s" size="12">%s</font>',
				hex(Theme.Colors.Muted),
				Strings.get("hud.attack.hint", lang)
			)
	end
	setPercent(percent)

	Session.connect(minus.Activated, function()
		setPercent(percent - cfg.PercentStep)
	end)
	Session.connect(plus.Activated, function()
		setPercent(percent + cfg.PercentStep)
	end)
	local dragging = false
	local function setFromX(x: number)
		local t = (x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X)
		setPercent(t)
	end
	Session.connect(bar.InputBegan, function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	Session.connect(UserInputService.InputChanged, function(input: InputObject)
		local t = input.UserInputType
		if dragging and (t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	Session.connect(UserInputService.InputEnded, function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	-- Строка атаки: цель; ниже — люди (ничья земля) или сила войск, перевес и снабжение (фронт).
	local function frontText(a: Protocol.AttackStats): string
		local parts: { string } = {}
		if a.target == 0 then
			table.insert(
				parts,
				string.format(
					Strings.get("hud.front.people", lang),
					string.format(
						'<font color="%s">%s</font>',
						gold,
						if a.troops < 0 then "?" else Strings.formatInt(a.troops)
					)
				)
			)
		end
		-- Скрытая мощь (§6.11а): сила < 0 — чужая, без разведки «?».
		if a.power >= 1 or a.power < 0 then
			table.insert(
				parts,
				string.format(
					Strings.get("hud.front.power", lang),
					string.format(
						'<font color="%s">%s</font>',
						gold,
						if a.power < 0 then "?" else Strings.formatInt(a.power)
					)
				)
			)
		end
		if a.target ~= 0 then
			if a.ratio == math.huge then
				table.insert(
					parts,
					string.format('<font color="%s">%s</font>', sky, Strings.get("hud.front.open", lang))
				)
			elseif a.ratio <= 1 then
				table.insert(
					parts,
					string.format(
						'<font color="%s">%s · %s</font>',
						alert,
						string.format(Strings.get("hud.front.ratio", lang), a.ratio),
						Strings.get("hud.front.stalled", lang)
					)
				)
			else
				table.insert(
					parts,
					string.format(
						'<font color="%s">%s</font>',
						sky,
						string.format(Strings.get("hud.front.ratio", lang), a.ratio)
					)
				)
			end
			if not a.supplied then
				table.insert(
					parts,
					string.format('<font color="%s">%s</font>', alert, Strings.get("hud.front.noSupply", lang))
				)
			end
		end
		return string.format(
			'→ %s\n<font size="12">%s</font>',
			escape(nationName(a.target)),
			table.concat(parts, " · ")
		)
	end

	local function push(text: string, color: Color3)
		local line: FeedLine
		if #feedLines >= Config.Render.FeedLines then
			line = table.remove(feedLines, 1) :: FeedLine -- самая старая строка уходит
		else
			local label = richLabel(feed, 15)
			label.TextStrokeColor3 = Theme.Colors.Backdrop
			label.TextStrokeTransparency = 0.2
			label.TextWrapped = true
			label.AutomaticSize = Enum.AutomaticSize.Y
			label.Size = UDim2.fromOffset(320, 0)
			line = { label = label, untilTime = 0 }
		end
		feedOrder += 1
		line.label.LayoutOrder = feedOrder
		line.label.Text = escape(text)
		line.label.TextColor3 = color
		line.label.Visible = true
		-- Новая строка проявляется (§15г).
		line.label.TextTransparency = 1
		TweenService:Create(line.label, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { TextTransparency = 0 }):Play()
		line.untilTime = os.clock() + Config.Render.FeedSec
		table.insert(feedLines, line)
	end

	local function toast(text: string)
		push(text, Theme.Colors.Gold)
	end

	local function alertLine(text: string)
		push(text, Theme.Colors.Alert)
	end

	local lastValues: ResourceBar.Values? = nil
	local function refresh()
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		if me == nil or cs.phase ~= "Play" then
			lastValues = nil
		end
		local playing = cs.phase == "Play"
		local stats = cs.stats

		-- Своя держава.
		local myStats = if me ~= nil then ClientState.statsOf(cs, me.id) else nil
		nationPanel.Visible = me ~= nil
		resources.setVisible(me ~= nil and playing)
		if me ~= nil then
			local lines = {
				string.format(
					'<font color="%s">■</font> <b>%s</b>',
					nationHex(me.colorIndex),
					escape(nationName(me.id))
				),
			}
			if myStats ~= nil then
				local growth = Economy.growthPerSec(myStats.people, myStats.maxPeople)
				if growth > 0 then
					growth *= 1 - myStats.weariness -- усталость от войны (§6.7а)
				end
				-- Люди, деньги, нефть, войска и суша — в полосе ресурсов (§15д ч.5), здесь не повторяются.
				local economy = if cs.myForces ~= nil then cs.myForces.economy else nil
				if economy ~= nil then
					local army = 0
					for _, k in (cs.myForces :: any).kinds do
						army += k.home + k.front
					end
					local v: ResourceBar.Values = {
						money = economy.money,
						income = economy.income - economy.upkeep,
						oil = economy.oil,
						oilIncome = economy.oilIncome,
						people = myStats.people,
						maxPeople = myStats.maxPeople,
						growth = growth,
						army = army,
						land = myStats.cells / math.max(1, totalLand) * 100,
					}
					lastValues = v
					resources.set(v)
				end
				-- Средняя стабильность (§6.10): зелёная от 50, жёлтая от 30, красная ниже; клетки с половинным доходом.
				if #cs.stability.ids > 0 then
					local avg = cs.stability.average
					local c = if avg >= 50 then green elseif avg >= Config.Stability.LowBelow then gold else alert
					local text = string.format(
						Strings.get("hud.stability", lang),
						string.format('<font color="%s">%d</font>', c, avg)
					)
					if cs.stability.lowCells > 0 then
						text ..= string.format(
							' <font color="%s">%s</font>',
							alert,
							string.format(Strings.get("hud.lowIncome", lang), Strings.formatInt(cs.stability.lowCells))
						)
					end
					table.insert(lines, text)
				end
				table.insert(lines, string.format(Strings.get("hud.troops", lang), Strings.formatInt(myStats.troops)))
				-- Флот (§6.12): свои корабли.
				local transports, destroyers = 0, 0
				for _, ship in cs.ships.ships do
					if ship.owner == me.id then
						if ship.kind == "Transport" then
							transports += 1
						else
							destroyers += 1
						end
					end
				end
				if transports + destroyers > 0 then
					table.insert(lines, string.format(Strings.get("hud.fleet", lang), transports, destroyers))
				end
				-- Авиация (§6.13): свои самолёты.
				local fighters, bombers = 0, 0
				for _, plane in cs.air.planes do
					if plane.owner == me.id then
						if plane.kind == "Fighter" then
							fighters += 1
						else
							bombers += 1
						end
					end
				end
				if fighters + bombers > 0 then
					table.insert(lines, string.format(Strings.get("hud.air", lang), fighters, bombers))
				end
				if myStats.weariness > 0 then
					table.insert(
						lines,
						string.format(
							'<font color="%s">%s</font>',
							alert,
							string.format(Strings.get("hud.weariness", lang), math.round(myStats.weariness * 100))
						)
					)
				end
			end
			nationText.Text = table.concat(lines, "\n")
		end

		-- Лидеры.
		leaders.Visible = playing and stats ~= nil
		if stats ~= nil then
			local sorted = table.clone(stats.nations)
			table.sort(sorted, function(a, b)
				if a.cells ~= b.cells then
					return a.cells > b.cells
				end
				return a.id < b.id
			end)
			local lines = { "<b>" .. Strings.get("hud.leaders", lang) .. "</b>" }
			for k = 1, math.min(8, #sorted) do
				local s = sorted[k]
				local n = cs.nations[s.id]
				if n ~= nil and n.alive then
					local you = if s.id == cs.myNation then " (" .. Strings.get("hud.you", lang) .. ")" else ""
					-- Бот — метка уровня (§9.1): «бот·Генерал».
					local tag = if n.isBot and n.botLevel ~= nil
						then string.format(
							' <font size="11" color="%s">%s</font>',
							muted,
							Strings.get("bot.level." .. n.botLevel, lang)
						)
						else ""
					-- Договоры (§8.1): «Предатель» красным, наш союзник — голубым.
					if ClientState.isTraitor(cs, s.id, os.clock(), ClientState.simRate(cs)) then
						tag ..= string.format(
							' <font size="11" color="%s">⚠%s</font>',
							alert,
							Strings.get("diplo.traitor", lang)
						)
					end
					if cs.myNation ~= nil and s.id ~= cs.myNation then
						local t = ClientState.treatyBetween(cs, cs.myNation, s.id)
						if t ~= nil and t.kind == "alliance" then
							tag ..= string.format(
								' <font size="11" color="%s">%s</font>',
								sky,
								Strings.get("diplo.ally", lang)
							)
						end
					end
					table.insert(
						lines,
						string.format(
							'<font color="%s">■</font> %s%s%s  <font color="%s">%.1f%%</font>',
							nationHex(n.colorIndex),
							escape(nationName(s.id)),
							tag,
							you,
							sky,
							s.cells / math.max(1, totalLand) * 100
						)
					)
				end
			end
			leadersText.Text = table.concat(lines, "\n")
		end

		-- Ползунок и атаки — только у живой державы в игре.
		local canAttack = playing and me ~= nil and me.alive
		-- §15л ч.2: доля атаки — кнопками в командной полосе; старый ползунок не показываем.
		slider.Visible = false
		local k = 0
		if canAttack and stats ~= nil and me ~= nil then
			for _, a in stats.attacks do
				if a.attacker == me.id and k < #rows then
					k += 1
					local row = rows[k]
					row.target = a.target
					row.text.Text = frontText(a)
					row.frame.Visible = true
				end
			end
		end
		for j = k + 1, #rows do
			rows[j].frame.Visible = false
			rows[j].target = -1
		end
	end

	local lastBanner = ""
	local function update(now: number)
		resources.update(now) -- «бегущие» числа (§15д ч.5)
		local text: string
		if cs.phase == "Waiting" then
			text = Strings.get("hud.waiting", lang)
		elseif cs.phase == "Pick" then
			local left = math.max(0, math.ceil(cs.phaseEndsAt - now))
			text = string.format(Strings.get("hud.pick", lang), left)
			if cs.myNation ~= nil then
				local me = cs.nations[cs.myNation]
				local hint = if me ~= nil and me.capital ~= nil then "hud.pick.done" else "hud.pick.hint"
				text ..= string.format('\n<font color="%s" size="14">%s</font>', sky, Strings.get(hint, lang))
			end
			-- Режим, выбранный в лобби (§5.1).
			text ..= string.format(
				'\n<font color="%s" size="14">%s</font>',
				sky,
				string.format(Strings.get("hud.mode", lang), Strings.get("mode." .. cs.mode.mode, lang))
			)
		elseif cs.phase == "Lobby" then
			local left = math.max(0, math.ceil(cs.phaseEndsAt - now))
			local players = 0
			for _, n in cs.nations do
				if not n.isBot then
					players += 1
				end
			end
			text = string.format(Strings.get("hud.lobby", lang), Strings.get("map." .. map.name, lang), left)
				.. string.format(
					'\n<font color="%s" size="14">%s</font>',
					sky,
					string.format(Strings.get("hud.lobby.players", lang), players, cs.targetNations)
				)
		elseif cs.phase == "Over" then
			local left = math.max(0, math.ceil(cs.phaseEndsAt - now))
			text = string.format(Strings.get("hud.over", lang), left)
		else
			-- Время матча / лимит (цифры — пиксельным Arcade), державы в игре.
			local t = math.floor(ClientState.matchTime(cs, now))
			local limit = math.floor(cs.timeLimit)
			local alive = 0
			local total = 0
			for _, n in cs.nations do
				total += 1
				if n.alive then
					alive += 1
				end
			end
			-- §15л ч.5: время — в левой колонке панели, здесь — только строки под ней.
			timeBig.Text = string.format(Strings.get("hud.time", lang), t // 60, t % 60)
			timeSub.Text = string.format(Strings.get("hud.timeOf", lang), limit // 60, limit % 60)
				.. "  ·  "
				.. string.format(Strings.get("hud.nations", lang), alive, total)
			text = ""
			local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
			if me == nil then
				text = Strings.get("hud.spectator", lang) .. "\n"
			elseif not me.alive then
				text = Strings.get("hud.defeated", lang) .. "\n"
			end
			-- Режим (§5.1): название, своя команда, охота на столицы, пауза «Против ботов».
			local line = string.format(Strings.get("hud.mode", lang), Strings.get("mode." .. cs.mode.mode, lang))
			if me ~= nil and me.team ~= nil then
				line ..= " · " .. string.format(Strings.get("hud.team", lang), me.team)
			end
			if cs.rules.capitalHunt then
				local need = Config.Modes.CapitalHunt.Need
				if me ~= nil and me.hunt ~= nil then
					line ..= " · " .. string.format(Strings.get("hud.hunt", lang), me.hunt, need)
				end
				-- Кто ближе всех к победе охотой — отсчёт всем.
				for _, n in cs.nations do
					if n.huntLeft ~= nil then
						local left = math.max(0, math.ceil(n.huntLeft - (now - cs.timeAt) * ClientState.clockRate(cs)))
						line ..= string.format(
							'\n<font color="%s">%s</font>',
							gold,
							string.format(Strings.get("hud.huntLeader", lang), nationName(n.id), n.hunt or need, left)
						)
					end
				end
			end
			text ..= string.format('<font color="%s" size="14">%s</font>', sky, line)
			-- «Потоп» (§5.3): отсчёт до следующей ступени.
			local flood = cs.flood
			if flood ~= nil and flood.step < Config.Flood.MaxSteps then
				local left = math.max(0, math.ceil(flood.nextIn - (now - cs.floodAt) * ClientState.clockRate(cs)))
				text ..= string.format(
					'\n<font color="%s" size="14">%s</font>',
					sky,
					string.format(Strings.get("hud.flood", lang), left, flood.step, Config.Flood.MaxSteps)
				)
			end
			if cs.mode.paused then
				text ..= string.format('\n<font color="%s" size="18">%s</font>', gold, Strings.get("hud.paused", lang))
			end
		end
		-- Лидер к победе: доля суши / порог победы.
		local stats = cs.stats
		local showBar = cs.phase == "Play" and stats ~= nil
		top.Visible = showBar
		if not showBar then
			placeChip.Visible = false
		end
		if showBar and stats ~= nil then
			local best, bestCells = 0, -1
			for _, s in stats.nations do
				if s.cells > bestCells then
					best, bestCells = s.id, s.cells
				end
			end
			local share = bestCells / math.max(1, totalLand)
			leaderFill.Size = UDim2.fromScale(math.clamp(share / cs.rules.victoryShare, 0, 1), 1)
			local mine = if cs.myNation ~= nil then ClientState.statsOf(cs, cs.myNation) else nil
			local myShare = if mine ~= nil then mine.cells / math.max(1, totalLand) else 0
			placeChip.Visible = mine ~= nil
			if mine ~= nil then
				local place = 1
				for _, s in stats.nations do
					if s.cells > mine.cells then
						place += 1
					end
				end
				placeText.Text = string.format(Strings.get("hud.place", lang), place, myShare * 100)
			end
			myMark.Visible = mine ~= nil
			myMark.Position = UDim2.fromScale(math.clamp(myShare / cs.rules.victoryShare, 0, 1), 0.5)
			goalText.Text = string.format(Strings.get("hud.goal", lang), math.round(cs.rules.victoryShare * 100))
			local function nationHex(id: number?): string
				local nn = if id ~= nil then cs.nations[id] else nil
				if nn == nil or nn.colorIndex < 1 then
					return gold
				end
				local c = NationColors.Colors[nn.colorIndex]
				return string.format("#%02x%02x%02x", c.r, c.g, c.b)
			end
			local you = if mine ~= nil
				then string.format(
					'<font color="%s">■</font> %s  ',
					nationHex(cs.myNation),
					string.format(Strings.get("hud.youShare", lang), myShare * 100)
				)
				else ""
			controlText.Text = you
				.. string.format(
					'<font color="%s">♛</font> <font color="%s">■</font> %s %.1f%%',
					gold,
					nationHex(best),
					escape(nationName(best)),
					share * 100
				)
			local n = cs.nations[best]
			leaderFill.BackgroundColor3 = if n ~= nil and n.colorIndex >= 1
				then Color3.fromRGB(
					NationColors.Colors[n.colorIndex].r,
					NationColors.Colors[n.colorIndex].g,
					NationColors.Colors[n.colorIndex].b
				)
				else Theme.Colors.Gold
		end
		if text ~= lastBanner then
			lastBanner = text
			bannerText.Text = text
		end
		-- §15и: в лобби карточку «Следующий матч» показывает экран лобби — баннер не дублирует.
		local lobby = cs.phase == "Lobby" or cs.phase == "Waiting"
		if banner.Visible == lobby then
			banner.Visible = not lobby
		end
		local j = 1
		while j <= #feedLines do
			local line = feedLines[j]
			if now > line.untilTime then
				line.label:Destroy()
				table.remove(feedLines, j)
			else
				j += 1
			end
		end
	end

	local function tapCell(cell: number)
		local myNation = cs.myNation
		if myNation == nil then
			return
		end
		if cs.phase == "Pick" then
			send("pick", { cell = cell })
			return
		end
		if cs.phase ~= "Play" then
			return
		end
		local me = cs.nations[myNation]
		if me == nil or not me.alive then
			return
		end
		if not Config.Terrain[MapDataModule.getTerrain(map, cell)].borderPassable then
			return -- вода и реки: атаковать нечего
		end
		local owner = ClientState.ownerAt(cs, cell)
		if owner == myNation then
			return
		end
		if owner ~= 0 then
			-- Чужая страна: войну сначала объявляют, бои — после мобилизации (§6.7а).
			local war = ClientState.warBetween(cs, myNation, owner)
			if war == nil then
				onNationTap(owner)
				return
			elseif not war.active then
				toast(Strings.get("reject.mobilizing", lang))
				return
			end
		end
		-- Ничья земля или враг: атака; точка нажатия — главное направление удара.
		send("attack", { target = owner, percent = percent, focus = cell })
	end

	local function onEvents(events: { any })
		for _, e in events do
			if type(e) ~= "table" then
				continue
			end
			local a, b = nationName(tonumber(e.nation) or 0), nationName(tonumber(e.target) or 0)
			if e.kind == "eliminated" or e.kind == "capitalLost" then
				toast(string.format(Strings.get("event." .. e.kind, lang), a))
			elseif e.kind == "warDeclared" then
				if e.target == cs.myNation then
					alertLine(string.format(Strings.get("event.attacked", lang), a, Config.War.MobilizationSec))
				else
					toast(string.format(Strings.get("event.warDeclared", lang), a, b))
				end
			elseif e.kind == "warStarted" then
				toast(string.format(Strings.get("event.warStarted", lang), a, b))
			elseif e.kind == "peace" then
				local terms = Strings.get("peace.terms." .. tostring(e.terms), lang)
				toast(string.format(Strings.get("event.peace", lang), a, b, terms))
			elseif e.kind == "victory" then
				toast(string.format(Strings.get("event.victory", lang), a))
			elseif e.kind == "pocketSurrendered" then
				toast(string.format(Strings.get("event.pocketSurrendered", lang), a, nationName(tonumber(e.by) or 0)))
			-- Договоры (§8.1): лента для всех, важное для нас — красной строкой.
			elseif e.kind == "offerAccepted" then
				local key = if e.offer == "alliance"
					then "event.offerAccepted.alliance"
					elseif e.offer == "demand" then "event.offerAccepted.demand"
					else "event.offerAccepted.pact"
				toast(string.format(Strings.get(key, lang), a, b))
			elseif e.kind == "offerRefused" and e.target == cs.myNation then
				toast(
					string.format(
						Strings.get("event.offerRefused", lang),
						a,
						Strings.get("diplo.act." .. tostring(e.offer), lang)
					)
				)
			elseif e.kind == "betrayal" then
				if e.target == cs.myNation then
					alertLine(string.format(Strings.get("event.betrayal", lang), a, b))
				else
					toast(string.format(Strings.get("event.betrayal", lang), a, b))
				end
			elseif e.kind == "treatyBroken" then
				toast(string.format(Strings.get("event.treatyBroken", lang), a, b))
			elseif e.kind == "breakAnnounced" and e.target == cs.myNation then
				alertLine(string.format(Strings.get("event.breakAnnounced", lang), a))
			elseif e.kind == "treatyExpired" and (e.nation == cs.myNation or e.target == cs.myNation) then
				toast(string.format(Strings.get("event.treatyExpired", lang), a, b))
			elseif e.kind == "vassal" or e.kind == "independence" then
				toast(string.format(Strings.get("event." .. e.kind, lang), a, b))
			elseif e.kind == "allyAttacked" and e.ally == cs.myNation then
				alertLine(string.format(Strings.get("event.allyAttacked", lang), a, b))
			-- Торговля, Совет, пинги (§8.2).
			elseif e.kind == "transfer" and e.target == cs.myNation then
				local parts: { string } = {}
				if (tonumber(e.money) or 0) > 0 then
					table.insert(parts, "$" .. Strings.formatInt(e.money))
				end
				if (tonumber(e.oil) or 0) > 0 then
					table.insert(parts, string.format(Strings.get("hire.oil", lang), Strings.formatInt(e.oil)))
				end
				if (tonumber(e.people) or 0) > 0 then
					table.insert(parts, Strings.formatInt(e.people))
				end
				toast(string.format(Strings.get("event.transfer", lang), a, table.concat(parts, ", ")))
			elseif e.kind == "embargo" and e.on then
				toast(string.format(Strings.get("event.embargo", lang), a, b))
			elseif e.kind == "tradeEnded" then
				toast(string.format(Strings.get("event.tradeEnded", lang), a, b))
			elseif e.kind == "councilOpened" then
				alertLine(Strings.get("event.councilOpened", lang))
			elseif e.kind == "councilClosed" and e.winner == nil then
				toast(Strings.get("event.councilNone", lang))
			elseif e.kind == "resolution" then
				if e.resolution == "sanctions" and e.target ~= nil then
					toast(
						string.format(
							Strings.get("event.resolution.sanctions", lang),
							nationName(tonumber(e.target) or 0)
						)
					)
				else
					local name = Strings.get("council.res." .. tostring(e.resolution), lang)
					toast(string.format(Strings.get("event.resolution", lang), name))
				end
			elseif
				e.kind == "ping"
				and type(e.phrase) == "string"
				and table.find(Config.Pings.Phrases, e.phrase) ~= nil
			then
				toast(string.format(Strings.get("event.ping", lang), a, Strings.get("ping." .. e.phrase, lang)))
			-- Флот (§6.12).
			elseif e.kind == "boatLaunched" and e.nation == cs.myNation then
				toast(Strings.get("event.boatLaunched", lang)) -- десант на другой берег (§15д)
			elseif e.kind == "shipBuilt" and e.nation == cs.myNation then
				toast(
					string.format(Strings.get("event.shipBuilt", lang), Strings.get("ship." .. tostring(e.ship), lang))
				)
			-- Торговые суда (§15е): своя доставка и пиратство — в ленту.
			elseif
				e.kind == "tradeDelivered"
				and cs.myNation ~= nil
				and (e.nation == cs.myNation or e.target == cs.myNation)
			then
				local other = if e.nation == cs.myNation then e.target else e.nation
				toast(
					string.format(
						Strings.get("event.tradeDelivered", lang),
						Strings.formatInt(tonumber(e.amount) or 0),
						nationName(tonumber(other) or 0)
					)
				)
			elseif e.kind == "merchantSunk" and cs.myNation ~= nil and e.nation == cs.myNation then
				alertLine(string.format(Strings.get("event.merchantLost", lang), nationName(tonumber(e.by) or 0)))
			elseif e.kind == "merchantSunk" and cs.myNation ~= nil and e.by == cs.myNation then
				toast(
					string.format(
						Strings.get("event.merchantLoot", lang),
						Strings.formatInt(tonumber(e.amount) or 0),
						nationName(tonumber(e.nation) or 0)
					)
				)
			elseif e.kind == "shipSunk" then
				local shipName = Strings.get("ship." .. tostring(e.ship), lang)
				local by = nationName(tonumber(e.by) or 0)
				local lost = tonumber(e.lost) or 0
				local text = if lost >= 1
					then string.format(
						Strings.get("event.shipSunkCargo", lang),
						a,
						shipName,
						Strings.formatInt(lost),
						by
					)
					else string.format(Strings.get("event.shipSunk", lang), a, shipName, by)
				if e.nation == cs.myNation then
					alertLine(text)
				elseif e.by == cs.myNation then
					toast(text)
				end
			elseif e.kind == "landed" then
				if e.target == cs.myNation then
					alertLine(string.format(Strings.get("event.landedOnYou", lang), a))
				elseif e.nation == cs.myNation or e.target ~= 0 then
					local where = if e.target == 0
						then Strings.get("event.landedNeutral", lang)
						else nationName(tonumber(e.target) or 0)
					toast(string.format(Strings.get("event.landed", lang), a, where))
				end
			elseif e.kind == "blockade" then
				if e.on and e.nation == cs.myNation then
					alertLine(Strings.get("event.blockadeYou", lang))
				else
					toast(string.format(Strings.get(if e.on then "event.blockade" else "event.blockadeOff", lang), a))
				end
			-- Буст магазина (§11.1): видят все — честно.
			elseif e.kind == "boost" then
				toast(
					string.format(Strings.get("event.boost", lang), a, Strings.get("shop." .. tostring(e.boost), lang))
				)
			-- «Потоп» (§5.3): всем.
			elseif e.kind == "flood" then
				toast(string.format(Strings.get("event.flood", lang), tonumber(e.cells) or 0))
			-- Разведка (§6.11а): цели — красной строкой, разведчику — подтверждение.
			elseif e.kind == "intel" and e.target == cs.myNation then
				alertLine(string.format(Strings.get("event.intelOnYou", lang), a))
			elseif e.kind == "intel" and e.nation == cs.myNation then
				toast(string.format(Strings.get("event.intelDone", lang), b, Config.Intel.DurationSec))
			-- Ракеты (§6.9): видят все; по вам — красной строкой.
			elseif e.kind == "missileLaunched" and (e.warhead == "atom" or e.warhead == "hydrogen") then
				-- §15ж: ядерный пуск — крупно и всем.
				local name = Strings.get("warhead." .. tostring(e.warhead), lang)
				local nuke = if e.warhead == "atom" then Config.Nukes.Atom else Config.Nukes.Hydrogen
				if e.target == cs.myNation then
					alertLine(string.format(Strings.get("event.nukeOnYou", lang), name, a, nuke.charges))
				else
					alertLine(
						string.format(Strings.get("event.nukeLaunched", lang), name, a, b, tonumber(e.impactIn) or 0)
					)
				end
			elseif e.kind == "doomWarning" then
				if e.nation == cs.myNation then
					alertLine(string.format(Strings.get("event.doomWarning", lang), a))
				else
					toast(string.format(Strings.get("event.doomWarning", lang), a))
				end
			elseif e.kind == "doomCollapse" then
				alertLine(string.format(Strings.get("event.doomCollapse", lang), a, (tonumber(e.bar) or 0) * 100))
			elseif e.kind == "nukeHit" then
				alertLine(
					string.format(
						Strings.get("event.nukeHit", lang),
						Strings.get("warhead." .. tostring(e.warhead), lang),
						a,
						b,
						Strings.formatInt(tonumber(e.cells) or 0)
					)
				)
			elseif e.kind == "missileLaunched" then
				if e.target == cs.myNation then
					alertLine(string.format(Strings.get("event.missileOnYou", lang), a))
				else
					toast(string.format(Strings.get("event.missileLaunched", lang), a, b, tonumber(e.impactIn) or 0))
				end
			elseif e.kind == "missileHit" then
				toast(string.format(Strings.get("event.missileHit", lang), a, tonumber(e.cells) or 0))
			elseif e.kind == "missileShot" then
				toast(string.format(Strings.get("event.missileShot", lang), a, nationName(tonumber(e.by) or 0)))
			-- Генералы (§6.15): свои способности и чужие — по вам.
			elseif e.kind == "ability" and (e.nation == cs.myNation or e.target == cs.myNation) then
				local name = Strings.get("ability." .. tostring(e.ability), lang)
				if e.nation == cs.myNation then
					toast(string.format(Strings.get("event.ability", lang), a, name))
				else
					alertLine(string.format(Strings.get("event.abilityOnYou", lang), a, name))
				end
			-- Технологии (§6.14): только свои.
			elseif e.kind == "researched" and e.nation == cs.myNation then
				toast(
					string.format(
						Strings.get("event.researched", lang),
						Strings.get("tech." .. tostring(e.branch) .. "." .. tostring(e.level), lang)
					)
				)
			-- Авиация (§6.13).
			elseif e.kind == "planeBuilt" and e.nation == cs.myNation then
				toast(
					string.format(
						Strings.get("event.planeBuilt", lang),
						Strings.get("plane." .. tostring(e.plane), lang)
					)
				)
			elseif e.kind == "planeShot" and (e.nation == cs.myNation or e.by == cs.myNation) then
				local text = string.format(
					Strings.get("event.planeShot", lang),
					a,
					Strings.get("plane." .. tostring(e.plane), lang),
					nationName(tonumber(e.by) or 0)
				)
				if e.nation == cs.myNation then
					alertLine(text)
				else
					toast(text)
				end
			elseif e.kind == "raid" and (e.target == cs.myNation or e.nation == cs.myNation) then
				local lost = Strings.formatInt(tonumber(e.lost) or 0)
				local count = tonumber(e.buildings) or 0
				if e.target == cs.myNation then
					alertLine(string.format(Strings.get("event.raidOnYou", lang), a, lost, count))
				else
					toast(string.format(Strings.get("event.raid", lang), b, lost, count))
				end
			elseif e.kind == "cityFounded" then
				-- Новый город (§15д ч.4).
				local name = Provinces.cityName(provinces, map, tonumber(e.cell) or 0)
				toast(
					string.format(Strings.get("event.cityFounded", lang), a, if lang == "en" then name.en else name.ru)
				)
			elseif e.kind == "revoltSoon" and e.nation == cs.myNation then
				-- Отсчёт до восстания (§15д): красной строкой, с секундами.
				local province = provinces.list[tonumber(e.province) or 0]
				local where = if province ~= nil then (if lang == "en" then province.nameEn else province.name) else "?"
				alertLine(string.format(Strings.get("event.revoltSoon", lang), where, tonumber(e.sec) or 0))
			elseif e.kind == "raidIntercepted" then
				-- Заряд ПВО перехватил налёт (§15д): по нам — золотом, наш налёт сбит — красным.
				local text =
					string.format(Strings.get("event.raidIntercepted", lang), nationName(tonumber(e.by) or 0), a)
				if e.nation == cs.myNation then
					alertLine(text)
				elseif e.by == cs.myNation then
					toast(text)
				end
			elseif e.kind == "revolt" then
				-- Восстание (§6.10): у нас — красной строкой.
				local province = provinces.list[tonumber(e.province) or 0]
				local where = if province ~= nil then (if lang == "en" then province.nameEn else province.name) else "?"
				local text = string.format(Strings.get("event.revolt", lang), where, a)
				if e.nation == cs.myNation then
					alertLine(text)
				else
					toast(text)
				end
			elseif e.kind == "peaceRejected" and e.target == cs.myNation then
				-- Наше предложение мира отклонили или оставили без ответа.
				toast(
					string.format(
						Strings.get(if e.expired then "event.peaceExpired" else "event.peaceRejected", lang),
						a
					)
				)
			end
		end
	end

	return {
		refresh = refresh,
		update = update,
		tapCell = tapCell,
		toast = toast,
		alert = alertLine,
		onEvents = onEvents,
		percent = function(): number
			return percent
		end,
		setPercent = setPercent,
		values = function(): ResourceBar.Values?
			return lastValues
		end,
	}
end

return table.freeze(MatchHud)
