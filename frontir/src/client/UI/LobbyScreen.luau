--!strict
--[[
	LobbyScreen — экран лобби (GDD §15и): карта за ним затемнена, по центру — «ФРОНТИР» и карточка «Следующий матч»
	(карта, режим — лидер голосования, игроки, большой отсчёт с полосой), ниже — голосование за режим и выбор генерала
	(рамки ModePanel и CommanderPanel переезжают сюда на время лобби, их логика не меняется), список игроков.
	Снизу остаётся док (магазин, задания, гардероб…). В выборе старта и в игре экран скрыт, рамки возвращаются.
	Отдельно — окно «Как играть» (H): шесть шагов и клавиши.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local PixelIcons = require(Shared:WaitForChild("PixelIcons"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type LobbyScreen = {
	-- Рамки голосования и выбора генерала: на время лобби — в карточку, потом — обратно.
	attach: (vote: GuiObject?, picker: GuiObject?) -> (),
	update: (now: number) -> (),
	toggleHelp: () -> (),
	helpOpen: () -> boolean,
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

local function icon(parent: Instance, key: string, scale: number, order: number): Frame
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(PixelIcons.Size * scale, PixelIcons.Size * scale)
	root.LayoutOrder = order
	root.Parent = parent
	local parts: { PixelIcons.Part } = PixelIcons.Icons[key] or {}
	for _, p in parts do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Theme.color(p.color)
		f.Position = UDim2.fromOffset(p.x * scale, p.y * scale)
		f.Size = UDim2.fromOffset(p.w * scale, p.h * scale)
		f.Parent = root
	end
	return root
end

function LobbyScreen.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang, mapName: string): LobbyScreen
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
		local s = gui.AbsoluteSize
		scale.Scale = math.clamp(math.min((s.X - 24) / cfg.WidthPx, (s.Y - cfg.DockSpacePx) / cfg.HeightPx), 0.5, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()

	-- Заголовок.
	local title = label(content, 44, true, 1)
	title.Text = Strings.get("lobby.title", lang)
	title.TextColor3 = Theme.Colors.Gold
	title.TextStrokeTransparency = 0.4
	local subtitle = label(content, 15, false, 2)
	subtitle.Text = Strings.get("lobby.subtitle", lang)
	subtitle.TextColor3 = Theme.Colors.Muted

	-- Карточка «Следующий матч».
	local card = Instance.new("Frame")
	card.Name = "NextMatch"
	card.LayoutOrder = 3
	card.Size = UDim2.fromOffset(cfg.WidthPx, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Theme.Colors.PanelBg
	card.Parent = content
	Theme.decorate(card)
	local cardPad = Instance.new("UIPadding")
	cardPad.PaddingLeft = UDim.new(0, 18)
	cardPad.PaddingRight = UDim.new(0, 18)
	cardPad.PaddingTop = UDim.new(0, 12)
	cardPad.PaddingBottom = UDim.new(0, 14)
	cardPad.Parent = card
	local cardList = Instance.new("UIListLayout")
	cardList.SortOrder = Enum.SortOrder.LayoutOrder
	cardList.Padding = UDim.new(0, 6)
	cardList.Parent = card
	local head = label(card, 13, true, 1)
	head.Text = Strings.get("lobby.next", lang)
	head.TextColor3 = Theme.Colors.Sky
	local mapLine = label(card, 30, true, 2)
	mapLine.Text = Strings.get("map." .. mapName, lang)
	local infoLine = label(card, 15, false, 3)
	infoLine.TextColor3 = Theme.Colors.Text
	local timeRow = Instance.new("Frame")
	timeRow.BackgroundTransparency = 1
	timeRow.LayoutOrder = 4
	timeRow.Size = UDim2.new(1, 0, 0, 30)
	timeRow.Parent = card
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.fromScale(0, 0.5)
	bar.Size = UDim2.new(1, -90, 0, 10)
	bar.BackgroundColor3 = Theme.Colors.Backdrop
	bar.BorderSizePixel = 0
	bar.Parent = timeRow
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 5)
	barCorner.Parent = bar
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Theme.Colors.Gold
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill
	local countdown = Instance.new("TextLabel")
	countdown.AnchorPoint = Vector2.new(1, 0.5)
	countdown.Position = UDim2.fromScale(1, 0.5)
	countdown.Size = UDim2.fromOffset(80, 30)
	countdown.BackgroundTransparency = 1
	countdown.FontFace = Theme.FontBold
	countdown.TextSize = 26
	countdown.TextColor3 = Theme.Colors.Gold
	countdown.TextXAlignment = Enum.TextXAlignment.Right
	countdown.Parent = timeRow
	local players = label(card, 13, false, 5)
	players.TextColor3 = Theme.Colors.Muted
	players.TextWrapped = true
	players.AutomaticSize = Enum.AutomaticSize.Y
	players.Size = UDim2.fromScale(1, 0)
	players.TextXAlignment = Enum.TextXAlignment.Left

	-- Места для голосования и выбора генерала.
	local voteSlot = column(content, "VoteSlot", 4, 0)
	local pickerSlot = column(content, "PickerSlot", 5, 0)

	type Attached = { frame: GuiObject, home: Instance?, position: UDim2, anchor: Vector2, slot: Frame }
	local attached: { Attached } = {}
	local function attach(vote: GuiObject?, picker: GuiObject?)
		for k, f in { vote, picker } do
			if f ~= nil then
				table.insert(attached, {
					frame = f,
					home = f.Parent,
					position = f.Position,
					anchor = f.AnchorPoint,
					slot = if k == 1 then voteSlot else pickerSlot,
				})
			end
		end
	end

	-- «Как играть»: окно поверх всего.
	local help = Instance.new("Frame")
	help.Name = "HowToPlay"
	help.AnchorPoint = Vector2.new(0.5, 0.5)
	help.Position = UDim2.fromScale(0.5, 0.5)
	help.Size = UDim2.fromOffset(cfg.HelpWidthPx, 0)
	help.AutomaticSize = Enum.AutomaticSize.Y
	help.BackgroundColor3 = Theme.Colors.PanelBg
	help.Visible = false
	help.ZIndex = 30
	help.Parent = gui
	Theme.decorate(help)
	local helpScale = Instance.new("UIScale")
	helpScale.Parent = help
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), function()
		helpScale.Scale = math.clamp((gui.AbsoluteSize.X - 24) / cfg.HelpWidthPx, 0.5, 1)
	end)
	helpScale.Scale = math.clamp((gui.AbsoluteSize.X - 24) / cfg.HelpWidthPx, 0.5, 1)
	local helpPad = Instance.new("UIPadding")
	helpPad.PaddingLeft = UDim.new(0, 18)
	helpPad.PaddingRight = UDim.new(0, 18)
	helpPad.PaddingTop = UDim.new(0, 14)
	helpPad.PaddingBottom = UDim.new(0, 14)
	helpPad.Parent = help
	local helpList = Instance.new("UIListLayout")
	helpList.SortOrder = Enum.SortOrder.LayoutOrder
	helpList.Padding = UDim.new(0, 8)
	helpList.Parent = help
	local helpTitle = label(help, 22, true, 0)
	helpTitle.Text = Strings.get("help.title", lang)
	helpTitle.TextColor3 = Theme.Colors.Gold
	for k, step in cfg.HelpSteps do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.LayoutOrder = k
		row.Size = UDim2.fromScale(1, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Parent = help
		local rowList = Instance.new("UIListLayout")
		rowList.FillDirection = Enum.FillDirection.Horizontal
		rowList.VerticalAlignment = Enum.VerticalAlignment.Center
		rowList.Padding = UDim.new(0, 12)
		rowList.SortOrder = Enum.SortOrder.LayoutOrder
		rowList.Parent = row
		icon(row, step.icon, 4, 1)
		local t = Instance.new("TextLabel")
		t.LayoutOrder = 2
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, -48, 0, 0)
		t.AutomaticSize = Enum.AutomaticSize.Y
		t.TextWrapped = true
		t.RichText = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.FontFace = Theme.Font
		t.TextSize = 15
		t.TextColor3 = Theme.Colors.Text
		t.Text = Strings.get("help." .. step.key, lang)
		t.Parent = row
	end
	local keys = label(help, 13, false, #cfg.HelpSteps + 1)
	keys.TextWrapped = true
	keys.AutomaticSize = Enum.AutomaticSize.Y
	keys.Size = UDim2.fromScale(1, 0)
	keys.TextXAlignment = Enum.TextXAlignment.Left
	keys.TextColor3 = Theme.Colors.Muted
	keys.Text = Strings.get("help.keys", lang)
	local close = Instance.new("TextButton")
	close.LayoutOrder = #cfg.HelpSteps + 2
	close.Size = UDim2.fromOffset(180, Config.Render.MinTouchTargetPx)
	close.BackgroundColor3 = Theme.Colors.Slate
	close.FontFace = Theme.FontBold
	close.TextSize = 16
	close.TextColor3 = Theme.Colors.Gold
	close.Text = Strings.get("help.close", lang)
	close.Parent = help
	Theme.decorate(close)
	local function toggleHelp()
		help.Visible = not help.Visible
		if help.Visible then
			Theme.popIn(help)
		end
	end
	Session.connect(close.Activated, toggleHelp)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.H then
			toggleHelp()
		elseif input.KeyCode == Enum.KeyCode.Escape and help.Visible then
			help.Visible = false
		end
	end)

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
		-- Режим: лидер голосования (до конца лобби — «Каждый сам за себя»).
		local mode = cs.mode
		local best, bestVotes = mode.mode, -1
		for k, id in mode.options do
			local v = mode.counts[k] or 0
			if v > bestVotes then
				best, bestVotes = id, v
			end
		end
		local humans: { string } = {}
		for _, n in cs.nations do
			if not n.isBot then
				table.insert(humans, if lang == "en" then n.nameEn else n.name)
			end
		end
		infoLine.Text = string.format(
			Strings.get("lobby.info", lang),
			Strings.get("mode." .. best, lang),
			#humans,
			cs.targetNations
		)
		players.Text = if #humans > 0
			then Strings.get("lobby.players", lang) .. " " .. table.concat(humans, " · ")
			else ""
		if cs.phase == "Waiting" then
			countdown.Text = "…"
			fill.Size = UDim2.fromScale(0.15 + 0.1 * math.sin(now * 3), 1)
		else
			local left = math.max(0, cs.phaseEndsAt - now)
			countdown.Text = string.format("%d", math.ceil(left))
			fill.Size = UDim2.fromScale(1 - math.clamp(left / Config.Match.LobbySec, 0, 1), 1)
			countdown.TextColor3 = if left <= 5 and math.floor(now * 2) % 2 == 0
				then Theme.Colors.Alert
				else Theme.Colors.Gold
		end
	end

	return {
		attach = attach,
		update = update,
		toggleHelp = toggleHelp,
		helpOpen = function(): boolean
			return help.Visible
		end,
	}
end

return table.freeze(LobbyScreen)
