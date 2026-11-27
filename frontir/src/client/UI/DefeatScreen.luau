--!strict
--[[
	DefeatScreen — «Боевой отчёт» (GDD §15й Й5, §15ь Л1): своё выбывание — карточка по центру: «ДЕРЖАВА ПАЛА», имя
	державы, кто добил и сколько продержались; плитки «Место · Пик суши · Взято городов · Боеголовки» (счётчики матча —
	cs.task.stats, место — сколько держав было живо, когда пала своя); уровень «Пути» с полосой опыта. Кнопки:
	- «Принять командование» — взять державу бота (Command.candidate — та же, что выберет сервер; на кнопке её цвет,
	  имя и место «№k из M»), намерение command; нет живых ботов или нельзя (дуэль, обучение, конец матча) — кнопки нет;
	- «Следующий матч» — сервер матча: в хаб и сразу быстрый вход (намерение nextMatch); «одному» — новый матч
	  (endSolo); «как раньше» (один сервер) с другими людьми — кнопки нет;
	- «В меню» и «Смотреть» (закрыть и следить за лидером).
	Карточка уходит сама, когда матч кончился (итоги — ResultsPanel) или когда приняли командование.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Command = require(Shared:WaitForChild("Command"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type DefeatScreen = {
	frame: Frame,
	onEvents: (events: { any }) -> (),
	update: (now: number) -> (),
}

local DefeatScreen = {}

local WIDTH, TILE_H, GAP = 600, 70, 10
local TILE_W = (WIDTH - 3 * GAP) / 4
local BUTTON = Config.Render.MinTouchTargetPx

function DefeatScreen.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (kind: string, payload: any) -> (),
	isSolo: () -> boolean,
	onWatch: () -> (),
	onMenu: () -> ()
): DefeatScreen
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local frame = Instance.new("Frame")
	frame.Name = "DefeatScreen"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.47)
	frame.Size = UDim2.fromOffset(WIDTH, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Theme.Colors.PanelBg
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 25
	frame.Parent = gui
	frame:SetAttribute("FrontirStyled", true)
	MenuKit.corner(frame, 12)
	MenuKit.pad(frame, 20, 16)
	MenuKit.stroke(frame, Theme.Colors.PanelBorder, 2)
	local pop = Instance.new("UIScale")
	pop.Parent = frame
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = frame

	-- Шапка: «БОЕВОЙ ОТЧЁТ» → «ДЕРЖАВА ПАЛА» → имя державы крупно → кто добил.
	local kicker = MenuKit.label(frame, t("defeat.report"), 13, Theme.Colors.Gold, true, 1)
	kicker.Name = "Kicker"
	MenuKit.label(frame, t("defeat.title"), 15, Theme.Colors.Muted, true, 2)
	local nameLabel = MenuKit.label(frame, "", 40, Theme.Colors.Alert, true, 3)
	nameLabel.FontFace = Theme.FontHeavy
	local sub = MenuKit.wrapLabel(frame, "", 15, Theme.Colors.Text, 4)

	-- Плитки: место, пик суши, взято городов, боеголовки.
	local tiles = Instance.new("Frame")
	tiles.Name = "Tiles"
	tiles.BackgroundTransparency = 1
	tiles.Size = UDim2.fromOffset(WIDTH, TILE_H)
	tiles.LayoutOrder = 5
	tiles.Parent = frame
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
	grid.CellPadding = UDim2.fromOffset(GAP, GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = tiles
	local function tile(order: number, caption: string): TextLabel
		local f = Instance.new("Frame")
		f.LayoutOrder = order
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.Parent = tiles
		MenuKit.corner(f, 8)
		MenuKit.stroke(f, Theme.Colors.PanelBorder, 1)
		local cap = MenuKit.label(f, caption, 11, Theme.Colors.Muted, true)
		cap.Position = UDim2.fromOffset(10, 8)
		local value = MenuKit.label(f, "—", 24, Theme.Colors.Text, true)
		value.FontFace = Theme.FontHeavy
		value.RichText = true
		value.Position = UDim2.fromOffset(10, 30)
		return value
	end
	local placeValue = tile(1, t("defeat.place"))
	local peak = tile(2, t("defeat.peak"))
	local cities = tile(3, t("defeat.cities"))
	local warheads = tile(4, t("defeat.warheads"))

	-- Уровень «Пути командира» и полоса опыта.
	local levelRow = MenuKit.box(frame, "Level", 6)
	levelRow.AutomaticSize = Enum.AutomaticSize.None
	levelRow.Size = UDim2.fromOffset(WIDTH, 18)
	local levelLabel = MenuKit.label(levelRow, "", 13, Theme.Colors.Muted, true)
	local xpLabel = MenuKit.label(levelRow, "", 13, Theme.Colors.Muted, true)
	xpLabel.AnchorPoint = Vector2.new(1, 0)
	xpLabel.Position = UDim2.fromScale(1, 0)
	local xpBar = MenuKit.bar(frame, 8, Theme.color("Violet"), 7)
	xpBar.frame.Size = UDim2.fromOffset(WIDTH, 8)

	-- Кнопки: «Принять командование» (крупно, с державой) · «Следующий матч» · «В меню»; под ними «Смотреть».
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromOffset(WIDTH, 64)
	row.LayoutOrder = 8
	row.Parent = frame
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.Padding = UDim.new(0, GAP)
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.HorizontalFlex = Enum.UIFlexAlignment.Fill
	rowList.Parent = row
	local function bigButton(order: number, style: MenuKit.ButtonStyle, title: string): (TextButton, TextLabel)
		local b = MenuKit.button(row, "", style, 64, order)
		b.Size = UDim2.fromOffset(150, 64)
		local head = MenuKit.label(b, title, 15, Theme.color(if style == "primary" then "Ink" else "White"), true)
		head.Position = UDim2.fromOffset(12, 10)
		local line = MenuKit.label(b, "", 12, Theme.color(if style == "primary" then "Ink" else "Mist"), false)
		line.Position = UDim2.fromOffset(12, 36)
		line.RichText = true
		return b, line
	end
	local command, commandLine = bigButton(1, "primary", t("defeat.command"))
	local nextMatch, nextLine = bigButton(2, "normal", t("defeat.next"))
	local menu = MenuKit.button(row, t("defeat.menu"), "normal", 64, 3)
	menu.Size = UDim2.fromOffset(110, 64)
	local watch = MenuKit.button(frame, t("defeat.watch"), "normal", BUTTON, 9)
	watch.Size = UDim2.fromOffset(WIDTH, BUTTON)

	local shown = false
	local commanded = false -- в этом матче уже принимали командование (Command.OncePerMatch)
	local fellAt: number? = nil -- сколько держав было живо, когда пала своя (место)
	local total = 0
	Session.connect(watch.Activated, function()
		frame.Visible = false
		onWatch()
	end)
	Session.connect(command.Activated, function()
		send("command", {}) -- держава — та, что выберет сервер (Command.candidate)
	end)
	Session.connect(nextMatch.Activated, function()
		frame.Visible = false
		if isSolo() then
			send("endSolo", {})
		else
			send("nextMatch", {})
		end
	end)
	Session.connect(menu.Activated, function()
		frame.Visible = false
		onMenu()
	end)

	local function nameOf(id: number): string
		local n = cs.nations[id]
		if n == nil then
			return "?"
		end
		return if lang == "en" then n.nameEn else n.name
	end
	local function colorOf(id: number): Color3
		local n = cs.nations[id]
		local c = if n ~= nil and n.colorIndex >= 1 then NationColors.Colors[n.colorIndex] else nil
		return if c ~= nil then Color3.fromRGB(c.r, c.g, c.b) else Theme.Colors.Muted
	end
	local function hex(c: Color3): string
		return string.format("#%02x%02x%02x", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
	end
	local function clock(sec: number): string
		local s = math.max(0, math.floor(sec))
		return string.format("%d:%02d", s // 60, s % 60)
	end
	-- Те же данные, что у сервера для Command.candidate: суша живых держав и кто из них бот.
	local function rows(): { Command.Row }
		local land: { [number]: number } = {}
		if cs.stats ~= nil then
			for _, s in cs.stats.nations do
				land[s.id] = s.cells
			end
		end
		local out: { Command.Row } = {}
		for id, n in cs.nations do
			table.insert(out, { id = id, land = land[id] or 0, bot = n.botLevel ~= nil, alive = n.alive })
		end
		return out
	end
	local function fill()
		local msg = cs.task
		local st = if msg ~= nil then msg.stats else nil
		placeValue.Text = if fellAt ~= nil
			then string.format('#%d<font size="14" color="#8a8fa3"> / %d</font>', fellAt, total)
			else "—"
		peak.Text = if st ~= nil then tostring(st.peak) .. "%" else "—"
		cities.Text = if st ~= nil then Strings.formatInt(st.cities) else "—"
		warheads.Text = if st ~= nil then Strings.formatInt(st.warheads or 0) else "—"
		local p = cs.profile
		if p ~= nil then
			levelLabel.Text = string.format(t("defeat.level"), p.level)
			xpLabel.Text = string.format("%s / %s", Strings.formatInt(p.xp), Strings.formatInt(p.need))
			xpBar.set(if p.need > 0 then p.xp / p.need else 1)
		end
		-- «Принять командование»: можно ли и какая держава (её цвет, имя и место).
		local list = rows()
		local candidate = Command.candidate(list)
		local limit = cs.rules.timeLimitSec
		local secLeft = if limit > 0 then limit - ClientState.matchTime(cs, os.clock()) else math.huge
		local can = candidate ~= nil
			and not cs.rules.duel
			and not cs.rules.tutorial
			and secLeft >= Config.Command.MinSecLeft
			and cs.place ~= "hub"
			and not (commanded and Config.Command.OncePerMatch)
		command.Visible = can
		if can and candidate ~= nil then
			local place, alive = Command.place(list, candidate)
			commandLine.Text =
				string.format(t("defeat.commandOf"), hex(colorOf(candidate)), nameOf(candidate), place or 0, alive)
		end
		-- «Следующий матч»: сервер матча — в хаб и быстрый вход; «одному» — новый матч; иначе — нет.
		nextMatch.Visible = isSolo() or cs.place == "match"
		nextLine.Text = t(if isSolo() then "defeat.nextSolo" else "defeat.nextSub")
	end

	local function onEvents(events: { any })
		local me = cs.myNation
		for _, e in events do
			-- Приняли командование — отчёт больше не нужен (игра продолжается за новую державу).
			if type(e) == "table" and e.kind == "commandTaken" and frame.Visible then
				task.defer(function()
					if cs.myNation == e.nation then
						frame.Visible = false
						shown = false
					end
				end)
			end
			if me ~= nil and not shown and type(e) == "table" and e.kind == "eliminated" and e.nation == me then
				shown = true
				local by = tonumber(e.by) or 0
				local lived = clock(ClientState.matchTime(cs, os.clock()))
				nameLabel.Text = string.upper(nameOf(me))
				sub.Text = if by ~= 0 and by ~= me
					then string.format(t("defeat.by"), nameOf(by), lived)
					else string.format(t("defeat.nobody"), lived)
				local alive = 0
				total = 0
				for _, n in cs.nations do
					total += 1
					if n.alive and n.id ~= me then
						alive += 1
					end
				end
				fellAt = alive + 1
				fill()
				frame.Visible = true
				pop.Scale = 0.7
				TweenService:Create(pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				}):Play()
			end
		end
	end

	local nextFill = 0
	local function update(now: number)
		local mine = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		if frame.Visible then
			if cs.phase ~= "Play" then
				frame.Visible = false
			elseif mine ~= nil and mine.alive then
				frame.Visible = false -- приняли командование: снова есть живая держава
				shown = false
				commanded = true
			elseif now >= nextFill then
				nextFill = now + 0.5
				fill()
			end
		end
		if cs.phase ~= "Play" then
			shown = false -- новый матч — новая карточка
			fellAt = nil
			commanded = false
		end
	end

	return { frame = frame, onEvents = onEvents, update = update }
end

return table.freeze(DefeatScreen)
