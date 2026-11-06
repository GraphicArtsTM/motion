--!strict
--[[
	LobbyScreen — экран лобби (GDD §15и): карта за ним затемнена, по центру — «ФРОНТИР» и карточка «Следующий матч»
	(карта, режим — лидер голосования, игроки, большой отсчёт с полосой), ниже — голосование за режим и выбор генерала
	(рамки ModePanel и CommanderPanel переезжают сюда на время лобби, их логика не меняется), список игроков.
	Снизу остаётся док (магазин, задания, гардероб…). В выборе старта и в игре экран скрыт, рамки возвращаются.
	Отдельно — окно «Как играть» (H): шесть шагов и клавиши.
	§15к: голосование за карту (рамка ModePanel.mapVoteFrame) — тоже здесь, под режимом; в строке карты — лидер
	голосования. В карточке — плашка игрока: флаг, имя, уровень и «Изменить флаг» (те же части, что в гардеробе;
	сохранить можно только открытые, закрытые покупаются в гардеробе).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local PixelIcons = require(Shared:WaitForChild("PixelIcons"))
local Strings = require(Shared:WaitForChild("Strings"))

local FlagView = require(script.Parent:WaitForChild("FlagView"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type LobbyScreen = {
	-- Рамки голосования (режим, карта) и выбора генерала: на время лобби — в экран, потом — обратно.
	attach: (vote: GuiObject?, picker: GuiObject?, mapVote: GuiObject?) -> (),
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

local function cycle(list: { string }, value: string, dir: number): string
	local k = table.find(list, value) or 1
	return list[(k - 1 + dir) % #list + 1]
end

function LobbyScreen.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	mapName: string,
	send: (string, { [string]: any }) -> ()
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

	-- §15к Плашка игрока: флаг, имя, уровень; «Изменить флаг» раскрывает строки частей флага.
	local BTN = Config.Render.MinTouchTargetPx
	local plate = Instance.new("Frame")
	plate.Name = "Me"
	plate.BackgroundColor3 = Theme.Colors.Backdrop
	plate.BackgroundTransparency = 0.4
	plate.BorderSizePixel = 0
	plate.LayoutOrder = 6
	plate.Size = UDim2.new(1, 0, 0, 56)
	plate.Parent = card
	local plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(0, 6)
	plateCorner.Parent = plate
	local myFlag = FlagView.new(plate, 60, 40, 2)
	myFlag.frame.Position = UDim2.fromOffset(8, 8)
	myFlag.frame.Parent = plate
	local myName = Instance.new("TextLabel")
	myName.BackgroundTransparency = 1
	myName.Position = UDim2.fromOffset(80, 8)
	myName.Size = UDim2.new(1, -260, 0, 22)
	myName.FontFace = Theme.FontBold
	myName.TextSize = 17
	myName.TextColor3 = Theme.Colors.Text
	myName.TextXAlignment = Enum.TextXAlignment.Left
	myName.TextTruncate = Enum.TextTruncate.AtEnd
	myName.Text = Players.LocalPlayer.DisplayName
	myName.Parent = plate
	local myLevel = Instance.new("TextLabel")
	myLevel.BackgroundTransparency = 1
	myLevel.Position = UDim2.fromOffset(80, 30)
	myLevel.Size = UDim2.new(1, -260, 0, 18)
	myLevel.FontFace = Theme.Font
	myLevel.TextSize = 13
	myLevel.TextColor3 = Theme.Colors.Muted
	myLevel.TextXAlignment = Enum.TextXAlignment.Left
	myLevel.Parent = plate
	local editFlag = smallButton(plate, Strings.get("lobby.editFlag", lang), 170, BTN)
	editFlag.AnchorPoint = Vector2.new(1, 0.5)
	editFlag.Position = UDim2.new(1, -8, 0.5, 0)
	editFlag.TextColor3 = Theme.Colors.Gold

	-- Редактор флага: пять строк «часть ◀ значение ▶», внизу «Сохранить» и подсказка про закрытые части.
	local editor = Instance.new("Frame")
	editor.Name = "FlagEditor"
	editor.BackgroundTransparency = 1
	editor.LayoutOrder = 7
	editor.Size = UDim2.fromScale(1, 0)
	editor.AutomaticSize = Enum.AutomaticSize.Y
	editor.Visible = false
	editor.Parent = card
	local editorList = Instance.new("UIListLayout")
	editorList.SortOrder = Enum.SortOrder.LayoutOrder
	editorList.Padding = UDim.new(0, 4)
	editorList.Parent = editor
	local flagCfg = Config.Cosmetics.Flag
	local draft: Cosmetics.Flag = Cosmetics.defaultFlag()
	type EditRow = { field: string, value: TextLabel, lock: TextLabel }
	local editRows: { EditRow } = {}
	local saveRow = Instance.new("Frame")
	local saveFlag: TextButton
	local saveNote: TextLabel
	local function partOwned(field: string, v: string): boolean
		local p = cs.profile
		if field ~= "layout" and field ~= "emblem" then
			return true
		end
		return p ~= nil and p.wardrobe.owned[Cosmetics.key(field :: any, v)] == true
	end
	local function drawEditor()
		myFlag.set(draft)
		local allOwned = true
		for _, r in editRows do
			local v = (draft :: any)[r.field] :: string
			local isPart = r.field == "layout" or r.field == "emblem"
			r.value.Text = if isPart then Strings.get("flag." .. v, lang) else Strings.get("color." .. v, lang)
			local owned = partOwned(r.field, v)
			r.lock.Visible = not owned
			allOwned = allOwned and owned
		end
		saveFlag.AutoButtonColor = allOwned
		saveFlag.TextColor3 = if allOwned then Theme.Colors.Gold else Theme.Colors.Muted
		saveNote.Text = if allOwned then "" else Strings.get("lobby.flagLocked", lang)
	end
	for k, field in { "bg", "layout", "layoutColor", "emblem", "emblemColor" } do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.LayoutOrder = k
		row.Size = UDim2.new(1, 0, 0, BTN)
		row.Parent = editor
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.fromOffset(150, BTN)
		name.FontFace = Theme.Font
		name.TextSize = 13
		name.TextColor3 = Theme.Colors.Muted
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = Strings.get("wardrobe.flag." .. field, lang)
		name.Parent = row
		local prev = smallButton(row, "◀", BTN, BTN)
		prev.Position = UDim2.fromOffset(160, 0)
		local value = Instance.new("TextLabel")
		value.BackgroundTransparency = 1
		value.Position = UDim2.fromOffset(160 + BTN + 4, 0)
		value.Size = UDim2.fromOffset(150, BTN)
		value.FontFace = Theme.FontBold
		value.TextSize = 14
		value.TextColor3 = Theme.Colors.Text
		value.Parent = row
		local nextB = smallButton(row, "▶", BTN, BTN)
		nextB.Position = UDim2.fromOffset(160 + BTN + 158, 0)
		local lock = Instance.new("TextLabel")
		lock.BackgroundTransparency = 1
		lock.Position = UDim2.fromOffset(160 + 2 * BTN + 166, 0)
		lock.Size = UDim2.fromOffset(200, BTN)
		lock.FontFace = Theme.Font
		lock.TextSize = 12
		lock.TextColor3 = Theme.Colors.Alert
		lock.TextXAlignment = Enum.TextXAlignment.Left
		lock.Text = string.format(Strings.get("lobby.flagPart", lang), flagCfg.PartPrice)
		lock.Visible = false
		lock.Parent = row
		local list: { string } = if field == "layout"
			then flagCfg.Layouts
			elseif field == "emblem" then flagCfg.Emblems
			else flagCfg.Colors
		local function step(dir: number)
			(draft :: any)[field] = cycle(list, (draft :: any)[field], dir)
			drawEditor()
		end
		Session.connect(prev.Activated, function()
			step(-1)
		end)
		Session.connect(nextB.Activated, function()
			step(1)
		end)
		table.insert(editRows, { field = field, value = value, lock = lock })
	end
	saveRow.BackgroundTransparency = 1
	saveRow.LayoutOrder = 10
	saveRow.Size = UDim2.new(1, 0, 0, BTN)
	saveRow.Parent = editor
	saveFlag = smallButton(saveRow, Strings.get("wardrobe.saveFlag", lang), 200, BTN)
	saveNote = Instance.new("TextLabel")
	saveNote.BackgroundTransparency = 1
	saveNote.Position = UDim2.fromOffset(212, 0)
	saveNote.Size = UDim2.new(1, -212, 1, 0)
	saveNote.FontFace = Theme.Font
	saveNote.TextSize = 12
	saveNote.TextWrapped = true
	saveNote.TextColor3 = Theme.Colors.Muted
	saveNote.TextXAlignment = Enum.TextXAlignment.Left
	saveNote.Parent = saveRow
	Session.connect(saveFlag.Activated, function()
		for _, r in editRows do
			if not partOwned(r.field, (draft :: any)[r.field]) then
				return
			end
		end
		send("flag", { flag = table.clone(draft) })
		editor.Visible = false
		editFlag.Text = Strings.get("lobby.editFlag", lang)
	end)
	Session.connect(editFlag.Activated, function()
		editor.Visible = not editor.Visible
		editFlag.Text = Strings.get(if editor.Visible then "lobby.closeFlag" else "lobby.editFlag", lang)
		local p = cs.profile
		if editor.Visible and p ~= nil then
			draft = table.clone(p.wardrobe.flag)
		end
		drawEditor()
	end)

	-- Места для голосования (режим, под ним — карта) и выбора генерала.
	local voteSlot = column(content, "VoteSlot", 4, 0)
	local mapSlot = column(content, "MapSlot", 5, 0)
	local pickerSlot = column(content, "PickerSlot", 6, 0)

	type Attached = { frame: GuiObject, home: Instance?, position: UDim2, anchor: Vector2, slot: Frame }
	local attached: { Attached } = {}
	local function attach(vote: GuiObject?, picker: GuiObject?, mapVote: GuiObject?)
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
		-- Карта: лидер голосования (ничья — раньше в списке, первой идёт текущая карта, как Modes.mapWinner).
		local mv = cs.mapVote
		local mapLead = mapName
		if mv ~= nil and #mv.options > 0 then
			local bestK = 1
			for k = 2, #mv.options do
				if (mv.counts[k] or 0) > (mv.counts[bestK] or 0) then
					bestK = k
				end
			end
			mapLead = mv.options[bestK]
		end
		mapLine.Text = Strings.get("map." .. mapLead, lang)
		mapLine.TextColor3 = if mapLead ~= mapName then Theme.Colors.Gold else Theme.Colors.Text
		-- Плашка игрока: уровень из профиля, флаг — сохранённый (пока редактор закрыт).
		local p = cs.profile
		plate.Visible = p ~= nil
		if p ~= nil then
			myLevel.Text = string.format(Strings.get("lobby.level", lang), p.level)
			if not editor.Visible then
				myFlag.set(p.wardrobe.flag)
			end
		else
			editor.Visible = false
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
