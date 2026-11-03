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
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Protocol = require(Shared:WaitForChild("Net"):WaitForChild("Protocol"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type MapData = MapDataModule.MapData

export type Hud = {
	refresh: () -> (),
	update: (now: number) -> (),
	tapCell: (cell: number) -> (),
	toast: (text: string) -> (),
	alert: (text: string) -> (), -- строка ленты красным (на вас напали)
	onEvents: (events: { any }) -> (),
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
	onNationTap: (owner: number) -> () -- нажатие на страну, с которой нет войны (объявление войны)
): Hud
	local cfg = Config.Expansion
	local percent = cfg.DefaultPercent
	local gold, sky, alert = hex(Theme.Colors.Gold), hex(Theme.Colors.Sky), hex(Theme.Colors.Alert)

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
	local bannerText = richLabel(banner, 18)
	bannerText.TextXAlignment = Enum.TextXAlignment.Center

	-- Слева сверху: держава.
	local nationPanel = panel(gui, "NationPanel")
	nationPanel.Position = UDim2.fromOffset(12, GAP)
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
		cancel.Activated:Connect(function()
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

	minus.Activated:Connect(function()
		setPercent(percent - cfg.PercentStep)
	end)
	plus.Activated:Connect(function()
		setPercent(percent + cfg.PercentStep)
	end)
	local dragging = false
	local function setFromX(x: number)
		local t = (x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X)
		setPercent(t)
	end
	bar.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local t = input.UserInputType
		if dragging and (t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
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
					string.format('<font color="%s">%s</font>', gold, Strings.formatInt(a.troops))
				)
			)
		end
		if a.power >= 1 then
			table.insert(
				parts,
				string.format(
					Strings.get("hud.front.power", lang),
					string.format('<font color="%s">%s</font>', gold, Strings.formatInt(a.power))
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
		line.untilTime = os.clock() + Config.Render.FeedSec
		table.insert(feedLines, line)
	end

	local function toast(text: string)
		push(text, Theme.Colors.Gold)
	end

	local function alertLine(text: string)
		push(text, Theme.Colors.Alert)
	end

	local function refresh()
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		local playing = cs.phase == "Play"
		local stats = cs.stats

		-- Своя держава.
		local myStats = if me ~= nil then ClientState.statsOf(cs, me.id) else nil
		nationPanel.Visible = me ~= nil
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
				table.insert(
					lines,
					string.format(
						Strings.get("hud.people", lang),
						string.format('<font color="%s">%s</font>', gold, Strings.formatInt(myStats.people)),
						Strings.formatInt(myStats.maxPeople)
					)
				)
				table.insert(
					lines,
					string.format(
						Strings.get("hud.growth", lang),
						string.format(
							'<font color="%s">%s%s</font>',
							sky,
							if growth >= 0 then "+" else "",
							Strings.formatInt(growth)
						)
					)
				)
				-- Деньги и нефть (§6.8): запас и прирост в секунду (доход минус содержание войск).
				local economy = if cs.myForces ~= nil then cs.myForces.economy else nil
				if economy ~= nil then
					local net = economy.income - economy.upkeep
					table.insert(
						lines,
						string.format(
							Strings.get("hud.money", lang),
							string.format('<font color="%s">%s</font>', gold, Strings.formatInt(economy.money)),
							string.format(
								'<font color="%s">%s%s</font>',
								if net >= 0 then sky else alert,
								if net >= 0 then "+" else "",
								Strings.formatInt(net)
							)
						)
					)
					table.insert(
						lines,
						string.format(
							Strings.get("hud.oil", lang),
							string.format('<font color="%s">%s</font>', gold, Strings.formatInt(economy.oil)),
							string.format('<font color="%s">+%s</font>', sky, Strings.formatInt(economy.oilIncome))
						)
					)
				end
				table.insert(
					lines,
					string.format(
						Strings.get("hud.land", lang),
						string.format('<font color="%s">%.1f</font>', sky, myStats.cells / math.max(1, totalLand) * 100)
					)
				)
				table.insert(lines, string.format(Strings.get("hud.troops", lang), Strings.formatInt(myStats.troops)))
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
					table.insert(
						lines,
						string.format(
							'<font color="%s">■</font> %s%s  <font color="%s">%.1f%%</font>',
							nationHex(n.colorIndex),
							escape(nationName(s.id)),
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
		slider.Visible = canAttack
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
		else
			local t = math.floor(cs.time + (now - cs.timeAt))
			text = string.format(Strings.get("hud.time", lang), t // 60, t % 60)
			local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
			if me == nil then
				text ..= "\n" .. Strings.get("hud.spectator", lang)
			elseif not me.alive then
				text ..= "\n" .. Strings.get("hud.defeated", lang)
			end
		end
		if text ~= lastBanner then
			lastBanner = text
			bannerText.Text = text
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
			elseif e.kind == "pocketSurrendered" then
				toast(string.format(Strings.get("event.pocketSurrendered", lang), a, nationName(tonumber(e.by) or 0)))
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
	}
end

return table.freeze(MatchHud)
