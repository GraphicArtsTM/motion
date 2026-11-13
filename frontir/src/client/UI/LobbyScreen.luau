--!strict
--[[
	LobbyScreen — §15ф Ф1 «Ожидание игроков» (было — экран лобби §15и с голосованиями). Карта за ним затемнена,
	по центру — логотип и одна карточка: «ОЖИДАНИЕ ИГРОКОВ», карта и режим (по очереди сервера), квадратики игроков
	(занятые — люди, остальные места займут боты), «СТАРТ ЧЕРЕЗ N С» с полосой, код своего матча, у одиночной игры —
	сложность ботов, внизу — «Выйти» (в главное меню). Голосований, генерала и флага здесь нет: генерал — в Арсенале,
	флаг — в Гардеробе. Если голосование включено (Config.Match.LobbyVotes) — рамки ModePanel и CommanderPanel, как
	раньше, переезжают сюда под карточку.
	Окно «Как играть» (H) с §15ц Ц4б — отдельный модуль UI/HowToPlay.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local Logo = require(script.Parent:WaitForChild("Logo"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type LobbyScreen = {
	-- Рамки голосования (режим, карта) и выбора генерала: на время лобби — в экран, потом — обратно.
	attach: (vote: GuiObject?, picker: GuiObject?, mapVote: GuiObject?) -> (),
	update: (now: number) -> (),
}

local LobbyScreen = {}

local function label(parent: Instance, size: number, bold: boolean?, order: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AutomaticSize = Enum.AutomaticSize.XY
	l.Size = UDim2.fromOffset(0, 0)
	l.FontFace = if bold then Theme.FontBold else Theme.Font
	l.TextSize = size
	l.TextColor3 = Theme.Colors.Text
	l.LayoutOrder = order or 0
	l.Parent = parent
	return l
end

local function column(parent: Instance, name: string, order: number, gap: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.AutomaticSize = Enum.AutomaticSize.XY
	f.Size = UDim2.fromOffset(0, 0)
	f.LayoutOrder = order
	f.Parent = parent
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, gap)
	list.Parent = f
	return f
end

local function smallButton(parent: Instance, text: string, w: number, h: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(w, h)
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
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = b
	b.Parent = parent
	return b
end

function LobbyScreen.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	mapName: string,
	send: (string, { [string]: any }) -> (),
	leave: (() -> ())? -- §15ф Ф1: «Выйти» — в главное меню (Main.client)
): LobbyScreen
	local cfg = Config.Render.Lobby
	-- Затемнение поверх карты (снизу оставляем место доку).
	local root = Instance.new("Frame")
	root.Name = "LobbyScreen"
	root.Size = UDim2.new(1, 0, 1, -cfg.DockSpacePx)
	root.BackgroundColor3 = Theme.Colors.Backdrop
	root.BackgroundTransparency = cfg.ShadeAlpha
	root.BorderSizePixel = 0
	root.Visible = false
	root.ZIndex = 0 -- под окнами (магазин, гардероб открываются поверх лобби)
	root.Parent = gui
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	shade.Parent = root

	local content = column(root, "Content", 1, 10)
	content.AnchorPoint = Vector2.new(0.5, 0)
	content.Position = UDim2.new(0.5, 0, 0, cfg.TopPx)
	local scale = Instance.new("UIScale")
	scale.Parent = content
	local function fit()
		local s = UiScale.size(gui)
		scale.Scale = math.clamp(math.min((s.X - 24) / cfg.WidthPx, (s.Y - cfg.DockSpacePx) / cfg.HeightPx), 0.5, 1)
	end
	UiScale.onResize(gui, fit)
	fit()

	-- Заголовок.
	local title = label(content, 44, true, 1)
	title.Text = Strings.get("lobby.title", lang)
	title.TextColor3 = Theme.Colors.Gold
	title.TextStrokeTransparency = 0.4
	-- §15л ч.5: логотип пикселями вместо надписи (нет памяти под картинку — надпись остаётся).
	do
		local img = Logo.new(content, Config.Art.LobbyLogoScale)
		if img ~= nil then
			img.LayoutOrder = 1
			title.Visible = false
		end
	end
	local subtitle = label(content, 15, false, 2)
	subtitle.Text = Strings.get("lobby.subtitle", lang)
	subtitle.TextColor3 = Theme.Colors.Muted

	-- Карточка «Ожидание игроков».
	local card = Instance.new("Frame")
	card.Name = "NextMatch"
	card.LayoutOrder = 3
	card.Size = UDim2.fromOffset(cfg.WidthPx, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Theme.Colors.PanelBg
	card.Parent = content
	Theme.decorate(card)
	local cardPad = Instance.new("UIPadding")
	cardPad.PaddingLeft = UDim.new(0, 28)
	cardPad.PaddingRight = UDim.new(0, 28)
	cardPad.PaddingTop = UDim.new(0, 22)
	cardPad.PaddingBottom = UDim.new(0, 24)
	cardPad.Parent = card
	local cardList = Instance.new("UIListLayout")
	cardList.SortOrder = Enum.SortOrder.LayoutOrder
	cardList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cardList.Padding = UDim.new(0, 12)
	cardList.Parent = card
	local head = label(card, 30, true, 1)
	head.FontFace = Theme.FontHeavy
	head.Text = Strings.get("lobby.waiting", lang)
	local infoLine = label(card, 17, false, 2)
	infoLine.TextColor3 = Theme.Colors.Muted
	-- Квадратики мест: люди — голубые, остальное займут боты.
	local seats = Instance.new("Frame")
	seats.Name = "Seats"
	seats.BackgroundTransparency = 1
	seats.LayoutOrder = 3
	seats.Size = UDim2.fromScale(1, 0)
	seats.AutomaticSize = Enum.AutomaticSize.Y
	seats.Parent = card
	local seatsList = Instance.new("UIGridLayout")
	seatsList.CellSize = UDim2.fromOffset(cfg.SeatPx, cfg.SeatPx)
	seatsList.CellPadding = UDim2.fromOffset(6, 6)
	seatsList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	seatsList.SortOrder = Enum.SortOrder.LayoutOrder
	seatsList.Parent = seats
	local seatFrames: { Frame } = {}
	local playersLine = label(card, 15, false, 4)
	playersLine.TextColor3 = Theme.Colors.Muted
	playersLine.TextWrapped = true
	playersLine.AutomaticSize = Enum.AutomaticSize.Y
	playersLine.Size = UDim2.fromScale(1, 0)
	local countdown = label(card, 18, true, 5)
	countdown.TextColor3 = Theme.Colors.Gold
	local bar = Instance.new("Frame")
	bar.LayoutOrder = 6
	bar.Size = UDim2.new(1, 0, 0, 8)
	bar.BackgroundColor3 = Theme.Colors.Backdrop
	bar.BorderSizePixel = 0
	bar.Parent = card
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 4)
	barCorner.Parent = bar
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Theme.Colors.Gold
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill
	-- §15л ч.4: код своего матча — крупно, золотом (друзья входят по нему из главного меню).
	local codeLine = label(card, 20, true, 7)
	codeLine.TextColor3 = Theme.Colors.Gold
	codeLine.Visible = false
	-- Одиночная игра (один человек): сложность ботов — три кнопки.
	local BTN = Config.Render.MinTouchTargetPx
	local diffRow = Instance.new("Frame")
	diffRow.Name = "Difficulty"
	diffRow.BackgroundTransparency = 1
	diffRow.LayoutOrder = 8
	diffRow.Size = UDim2.fromScale(1, 0)
	diffRow.AutomaticSize = Enum.AutomaticSize.Y
	diffRow.Visible = false
	diffRow.Parent = card
	local diffList = Instance.new("UIListLayout")
	diffList.FillDirection = Enum.FillDirection.Horizontal
	diffList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	diffList.VerticalAlignment = Enum.VerticalAlignment.Center
	diffList.Padding = UDim.new(0, 8)
	diffList.SortOrder = Enum.SortOrder.LayoutOrder
	diffList.Parent = diffRow
	local diffLabel = label(diffRow, 15, false, 0)
	diffLabel.TextColor3 = Theme.Colors.Muted
	diffLabel.Text = Strings.get("lobby.difficulty", lang)
	local diffButtons: { [string]: TextButton } = {}
	for k, level in { "Novice", "Normal", "General" } do
		local b = smallButton(diffRow, Strings.get("mode.level." .. level, lang), 120, BTN)
		b.LayoutOrder = k
		b.TextSize = 15
		diffButtons[level] = b
		Session.connect(b.Activated, function()
			send("difficulty", { level = level })
		end)
	end
	-- «Выйти» — в главное меню.
	local leaveButton = smallButton(card, Strings.get("lobby.leave", lang), 220, BTN + 4)
	leaveButton.LayoutOrder = 9
	leaveButton.TextSize = 17
	Session.connect(leaveButton.Activated, function()
		if leave ~= nil then
			leave()
		end
	end)

	-- Места для голосования (режим, под ним — карта) и выбора генерала.
	local voteSlot = column(content, "VoteSlot", 4, 0)
	local mapSlot = column(content, "MapSlot", 5, 0)
	local pickerSlot = column(content, "PickerSlot", 6, 0)

	type Attached = { frame: GuiObject, home: Instance?, position: UDim2, anchor: Vector2, slot: Frame }
	local attached: { Attached } = {}
	local function attach(vote: GuiObject?, picker: GuiObject?, mapVote: GuiObject?)
		if not Config.Match.LobbyVotes then
			return -- §15ф Ф1: без голосований и генерала в лобби
		end
		local slots = { voteSlot, pickerSlot, mapSlot }
		for k, f in { vote, picker, mapVote } :: { [number]: GuiObject? } do
			if f ~= nil then
				table.insert(attached, {
					frame = f,
					home = f.Parent,
					position = f.Position,
					anchor = f.AnchorPoint,
					slot = slots[k],
				})
			end
		end
	end

	local function update(now: number)
		local lobby = cs.phase == "Lobby" or cs.phase == "Waiting"
		root.Visible = lobby
		for _, a in attached do
			local want: Instance? = if lobby then a.slot else a.home
			if a.frame.Parent ~= want then
				a.frame.Parent = want
				if lobby then
					a.frame.AnchorPoint = Vector2.new(0, 0)
				else
					a.frame.AnchorPoint = a.anchor
					a.frame.Position = a.position
				end
			end
		end
		if not lobby then
			return
		end
		-- Режим: заданный по очереди сервера (с голосованием — лидер голосования).
		local mode = cs.mode
		local best, bestVotes = mode.mode, -1
		for k, id in mode.options do
			local v = mode.counts[k] or 0
			if v > bestVotes then
				best, bestVotes = id, v
			end
		end
		local mapLead = mapName
		local mv = cs.mapVote
		if mv ~= nil and #mv.options > 0 then
			local bestK = 1
			for k = 2, #mv.options do
				if (mv.counts[k] or 0) > (mv.counts[bestK] or 0) then
					bestK = k
				end
			end
			mapLead = mv.options[bestK]
		end
		infoLine.Text = Strings.get("map." .. mapLead, lang) .. "  ·  " .. Strings.get("mode." .. best, lang)
		local humans: { string } = {}
		for _, n in cs.nations do
			if not n.isBot then
				table.insert(humans, if lang == "en" then n.nameEn else n.name)
			end
		end
		-- Места: всего держав в матче (люди + боты), не больше SeatsMax квадратиков.
		local total = math.clamp(math.max(cs.targetNations, #humans), 1, cfg.SeatsMax)
		for k = 1, math.max(total, #seatFrames) do
			local f: Frame? = seatFrames[k]
			if f == nil and k <= total then
				local made = Instance.new("Frame")
				made.BorderSizePixel = 0
				made.LayoutOrder = k
				made.Parent = seats
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0, 4)
				c.Parent = made
				seatFrames[k] = made
				f = made
			end
			if f ~= nil then
				f.Visible = k <= total
				f.BackgroundColor3 = if k <= #humans then Theme.Colors.Sky else Theme.Colors.Slate
				f.BackgroundTransparency = if k <= #humans then 0 else 0.4
			end
		end
		playersLine.Text = string.format(Strings.get("lobby.seats", lang), #humans, math.max(cs.targetNations, #humans))
			.. (if #humans > 0 then "\n" .. table.concat(humans, " · ") else "")
		local code = if cs.server ~= nil then cs.server.code else nil
		codeLine.Visible = code ~= nil
		if code ~= nil then
			codeLine.Text = string.format(Strings.get("lobby.code", lang), code)
		end
		-- §15ц Ц2 / Ц5б: при ожидании выбора сложности нет — сила ботов выбирается в «Играть одному».
		diffRow.Visible = false
		for level, b in diffButtons do
			local on = mode.difficulty == level
			b.BackgroundColor3 = if on then Theme.Colors.Gold else Theme.Colors.PanelBg
			b.TextColor3 = if on then Theme.Colors.Backdrop else Theme.Colors.Text
		end
		leaveButton.Visible = leave ~= nil
		if cs.phase == "Waiting" then
			countdown.Text = Strings.get("lobby.waitingMore", lang)
			fill.Size = UDim2.fromScale(0.15 + 0.1 * math.sin(now * 3), 1)
		else
			local left = math.max(0, cs.phaseEndsAt - now)
			countdown.Text = string.format(Strings.get("lobby.startsIn", lang), math.ceil(left))
			fill.Size = UDim2.fromScale(1 - math.clamp(left / Config.Match.LobbySec, 0, 1), 1)
			countdown.TextColor3 = if left <= 5 and math.floor(now * 2) % 2 == 0
				then Theme.Colors.Alert
				else Theme.Colors.Gold
		end
	end

	return {
		attach = attach,
		update = update,
	}
end

return table.freeze(LobbyScreen)
