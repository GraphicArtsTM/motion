--!strict
--[[
	MatchSetup — окно «Играть одному» и «Свой матч» (GDD §15ц Ц2): карта (миниатюры всех карт пула), режим
	(Config.Lobbies.Modes, под ними — что это за режим), сила ботов (только «одному») и одна главная кнопка.
	«Свой матч» в хабе — ещё «Войти по коду». Живёт внутри главного меню (над его содержимым).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapThumbs = require(Shared:WaitForChild("MapThumbs"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local MapThumb = require(script.Parent:WaitForChild("MapThumb"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

export type Kind = "solo" | "own"

export type Choice = { map: string, mode: string, solo: boolean, level: string? }

export type Actions = {
	start: (choice: Choice) -> (), -- «Играть» / «Создать матч»
	joinCode: (code: string) -> (), -- «Войти по коду» (хаб)
	codeAllowed: () -> boolean, -- коды есть только в хабе (опубликованная игра)
	busy: () -> boolean, -- идёт переход — кнопки неактивны
}

export type MatchSetup = {
	open: (kind: Kind) -> (),
	close: () -> (),
	isOpen: () -> boolean,
	frame: Frame,
}

local MatchSetup = {}

local WIDTH = 780
local MAP_W, MAP_H = 136, 104
local CHIP_H = 40

local function selectable(b: GuiButton, on: boolean)
	local s = b:FindFirstChildOfClass("UIStroke")
	if s ~= nil then
		s.Color = if on then Theme.Colors.Gold else Theme.Colors.Slate
		s.Thickness = if on then 3 else 1
		s.Transparency = if on then 0 else 0.3
	end
	b.BackgroundColor3 = if on then Theme.color("Slate") else Theme.Colors.Backdrop
end

local function section(parent: Instance, text: string, order: number): TextLabel
	local l = MenuKit.label(parent, text, 13, Theme.Colors.Muted, true, order)
	return l
end

function MatchSetup.new(parent: Instance, lang: Strings.Lang, act: Actions): MatchSetup
	local function t(key: string): string
		return Strings.get(key, lang)
	end

	-- Затемнение во весь экран; нажатие мимо окна — закрыть.
	local shade = Instance.new("TextButton")
	shade.Name = "MatchSetup"
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Theme.Colors.Backdrop
	shade.BackgroundTransparency = 0.35
	shade.BorderSizePixel = 0
	shade.ZIndex = 20
	shade.Visible = false
	shade.Parent = parent
	shade:SetAttribute("FrontirStyled", true)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(WIDTH, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Theme.Colors.PanelBg
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.ZIndex = 21
	panel.Parent = shade
	panel:SetAttribute("FrontirStyled", true)
	MenuKit.corner(panel, 14)
	MenuKit.stroke(panel, Theme.Colors.Slate, 1).Transparency = 0.2
	MenuKit.pad(panel, 24, 20)
	MenuKit.list(panel, 12)
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	-- Шапка: заголовок, строка «что это», крестик.
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 52)
	head.LayoutOrder = 1
	head.Parent = panel
	local title = MenuKit.label(head, "", 26, Theme.Colors.Text, true)
	title.FontFace = Theme.FontHeavy
	local sub = MenuKit.label(head, "", 14, Theme.Colors.Muted, false)
	sub.Position = UDim2.fromOffset(0, 32)
	local close = MenuKit.button(head, "×", "normal", nil)
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(MenuKit.Touch, MenuKit.Touch)
	close.TextSize = 20

	-- Карта.
	section(panel, t("setup.map"), 2)
	local maps = Instance.new("Frame")
	maps.Name = "Maps"
	maps.BackgroundTransparency = 1
	maps.Size = UDim2.fromScale(1, 0)
	maps.AutomaticSize = Enum.AutomaticSize.Y
	maps.LayoutOrder = 3
	maps.Parent = panel
	local mapGrid = Instance.new("UIGridLayout")
	mapGrid.CellSize = UDim2.fromOffset(MAP_W, MAP_H)
	mapGrid.CellPadding = UDim2.fromOffset(10, 10)
	mapGrid.SortOrder = Enum.SortOrder.LayoutOrder
	mapGrid.Parent = maps
	local thumbOf = MapThumb.new()
	local mapButtons: { [string]: TextButton } = {}
	local chosenMap = Config.Lobbies.Slots[1].map
	local chosenMode = "Ffa"
	local chosenLevel = Config.Lobbies.SoloLevel
	local refresh: () -> () = function() end
	for k, id in Config.MapVote.Pool do
		if (Config.RealMaps :: any)[id] == nil then
			continue
		end
		local b = Instance.new("TextButton")
		b.Name = "Map_" .. id
		b.Text = ""
		b.AutoButtonColor = true
		b.LayoutOrder = k
		b.BackgroundColor3 = Theme.Colors.Backdrop
		b.BorderSizePixel = 0
		b.Parent = maps
		b:SetAttribute("FrontirStyled", true)
		MenuKit.corner(b, 10)
		MenuKit.stroke(b, Theme.Colors.Slate, 1)
		local img = Instance.new("ImageLabel")
		img.BackgroundColor3 = Theme.Colors.Ocean
		img.BorderSizePixel = 0
		img.AnchorPoint = Vector2.new(0.5, 0)
		img.Position = UDim2.new(0.5, 0, 0, 8)
		img.Size = UDim2.fromOffset(MapThumbs.W * 2.5, MapThumbs.H * 2.5)
		img.ResampleMode = Enum.ResamplerMode.Pixelated
		img.Parent = b
		MenuKit.corner(img, 6)
		local content = thumbOf(id)
		if content ~= nil then
			img.ImageContent = content
		end
		local name = MenuKit.label(b, Strings.get("map." .. id, lang), 15, Theme.Colors.Text, true)
		name.AnchorPoint = Vector2.new(0.5, 1)
		name.Position = UDim2.new(0.5, 0, 1, -8)
		name.TextXAlignment = Enum.TextXAlignment.Center
		mapButtons[id] = b
		Session.connect(b.Activated, function()
			chosenMap = id
			refresh()
		end)
	end

	-- Режим и что это за режим.
	section(panel, t("setup.mode"), 4)
	local modes = Instance.new("Frame")
	modes.Name = "Modes"
	modes.BackgroundTransparency = 1
	modes.Size = UDim2.fromScale(1, 0)
	modes.AutomaticSize = Enum.AutomaticSize.Y
	modes.LayoutOrder = 5
	modes.Parent = panel
	local modeGrid = Instance.new("UIGridLayout")
	modeGrid.CellSize = UDim2.new(0.25, -8, 0, CHIP_H)
	modeGrid.CellPadding = UDim2.fromOffset(10, 10)
	modeGrid.SortOrder = Enum.SortOrder.LayoutOrder
	modeGrid.Parent = modes
	local modeButtons: { [string]: TextButton } = {}
	for k, id in Config.Lobbies.Modes do
		local b = MenuKit.button(modes, Strings.get("mode." .. id, lang), "normal", CHIP_H, k)
		b.Name = "Mode_" .. id
		b:SetAttribute("FrontirStyled", true) -- рамку «выбрано» ставит refresh, наведение её не сбивает
		b.TextSize = 15
		b.TextWrapped = true
		modeButtons[id] = b
		Session.connect(b.Activated, function()
			chosenMode = id
			refresh()
		end)
	end
	local modeDesc = MenuKit.wrapLabel(panel, "", 14, Theme.Colors.Text, 6)

	-- Сила ботов (только «одному»).
	local levelHead = section(panel, t("setup.bots"), 7)
	local levels = MenuKit.box(panel, "Levels", 8)
	levels.Size = UDim2.fromScale(1, 0)
	levels.AutomaticSize = Enum.AutomaticSize.Y
	MenuKit.list(levels, 10, true)
	local levelButtons: { [string]: TextButton } = {}
	for k, id in Types.BotLevels do
		local b = MenuKit.button(levels, Strings.get("mode.level." .. id, lang), "normal", CHIP_H, k)
		b.Name = "Level_" .. id
		b:SetAttribute("FrontirStyled", true)
		b.Size = UDim2.new(1 / 3, -7, 0, CHIP_H)
		levelButtons[id] = b
		Session.connect(b.Activated, function()
			chosenLevel = id
			refresh()
		end)
	end

	-- Главная кнопка и пояснение.
	local go = MenuKit.button(panel, "", "primary", 60, 9)
	go.Name = "Start"
	go.FontFace = Theme.FontHeavy
	go.TextSize = 24
	local note = MenuKit.wrapLabel(panel, "", 13, Theme.Colors.Muted, 10)

	-- «Свой матч» в хабе: войти по коду друга.
	local codeRow = MenuKit.box(panel, "Code", 11)
	codeRow.Size = UDim2.fromScale(1, 0)
	codeRow.AutomaticSize = Enum.AutomaticSize.Y
	MenuKit.list(codeRow, 10, true)
	MenuKit.label(codeRow, t("setup.code"), 14, Theme.Colors.Sky, true, 1)
	local codeBox = Instance.new("TextBox")
	codeBox.Name = "CodeBox"
	codeBox.LayoutOrder = 2
	codeBox.Size = UDim2.fromOffset(150, MenuKit.Touch)
	codeBox.BackgroundColor3 = Theme.Colors.Backdrop
	codeBox.BorderSizePixel = 0
	codeBox.ClearTextOnFocus = false
	codeBox.FontFace = Theme.FontBold
	codeBox.TextSize = 20
	codeBox.TextColor3 = Theme.Colors.Gold
	codeBox.PlaceholderText = t("menu.codePlaceholder")
	codeBox.PlaceholderColor3 = Theme.Colors.Muted
	codeBox.Text = ""
	codeBox.Parent = codeRow
	MenuKit.corner(codeBox, 8)
	MenuKit.stroke(codeBox, Theme.Colors.Slate, 1)
	local codeJoin = MenuKit.button(codeRow, t("menu.codeJoin"), "good", nil, 3)
	codeJoin.Size = UDim2.fromOffset(140, MenuKit.Touch)
	Session.connect(codeBox:GetPropertyChangedSignal("Text"), function()
		local clean = string.sub(string.upper((string.gsub(codeBox.Text, "[^%w]", ""))), 1, Config.Places.CodeLength)
		if clean ~= codeBox.Text then
			codeBox.Text = clean
		end
	end)

	local kind: Kind = "solo"
	local opened = false

	function refresh()
		for id, b in mapButtons do
			selectable(b, id == chosenMap)
		end
		for id, b in modeButtons do
			selectable(b, id == chosenMode)
		end
		for id, b in levelButtons do
			selectable(b, id == chosenLevel)
		end
		modeDesc.Text = Strings.get("mode.desc." .. chosenMode, lang)
		local solo = kind == "solo"
		levelHead.Visible = solo
		levels.Visible = solo
		title.Text = t(if solo then "setup.title.solo" else "setup.title.own")
		sub.Text = t(if solo then "setup.sub.solo" else "setup.sub.own")
		local hubCodes = act.codeAllowed()
		codeRow.Visible = not solo and hubCodes
		go.Text = if solo then "▶  " .. t("setup.play") else t(if hubCodes then "setup.create" else "setup.here")
		note.Text = if solo then t("setup.note.solo") elseif hubCodes then t("setup.note.own") else t("setup.note.here")
		local busy = act.busy()
		go.Active = not busy
		go.AutoButtonColor = not busy
		go.BackgroundTransparency = if busy then 0.5 else 0
		codeJoin.Active = not busy and #codeBox.Text == Config.Places.CodeLength
		codeJoin.BackgroundTransparency = if codeJoin.Active then 0 else 0.5
	end
	Session.connect(codeBox:GetPropertyChangedSignal("Text"), refresh)

	local function setOpen(on: boolean)
		opened = on
		shade.Visible = on
	end
	Session.connect(close.Activated, function()
		setOpen(false)
	end)
	Session.connect(shade.Activated, function()
		setOpen(false)
	end)
	Session.connect(go.Activated, function()
		if act.busy() then
			return
		end
		local solo = kind == "solo"
		act.start({
			map = chosenMap,
			mode = chosenMode,
			solo = solo,
			level = if solo then chosenLevel else nil,
		})
		setOpen(false)
	end)
	local function joinCode()
		if codeJoin.Active then
			act.joinCode(codeBox.Text)
			setOpen(false)
		end
	end
	Session.connect(codeJoin.Activated, joinCode)
	Session.connect(codeBox.FocusLost, function(enter: boolean)
		if enter then
			joinCode()
		end
	end)

	-- Окно не выше экрана: ужимаем (в условных пикселях слоя).
	-- Обе величины — в настоящих пикселях, их отношение от масштаба слоя не зависит.
	local function fit()
		local natural = panel.AbsoluteSize / math.max(0.01, scale.Scale)
		local room = shade.AbsoluteSize
		if natural.X > 0 and natural.Y > 0 and room.X > 0 then
			scale.Scale = math.clamp(math.min((room.X - 24) / natural.X, (room.Y - 24) / natural.Y), 0.5, 1)
		end
	end
	Session.connect(shade:GetPropertyChangedSignal("AbsoluteSize"), fit)
	Session.connect(panel:GetPropertyChangedSignal("AbsoluteSize"), fit)

	return {
		open = function(k: Kind)
			kind = k
			refresh()
			setOpen(true)
			task.defer(fit)
		end,
		close = function()
			setOpen(false)
		end,
		isOpen = function(): boolean
			return opened
		end,
		frame = panel,
	}
end

return table.freeze(MatchSetup)
