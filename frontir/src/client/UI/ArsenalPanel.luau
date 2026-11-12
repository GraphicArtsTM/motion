--!strict
--[[
	ArsenalPanel — окно «Арсенал» (GDD §15л ч.6): особое оружие навсегда за медали, в бой — одно.
	Сверху — заголовок, медали и «×». Слева — большой значок выбранного предмета на тёмном поле, справа — что делает,
	полоса «медали N / цена» и кнопка: «Купить за N» / «🔒 ур. N» / «Взять в бой» / «В бою ✓». Снизу — карточки
	всех предметов (значок, название, цена или «открыто» / «в бою»). Открывается из главного меню, дока (U).
	§15ф Ф1: внизу — «Генерал в бой»: четыре карточки генералов (пассивка, Q и E, замок до уровня); выбранный
	сохраняется в профиле (намерение prefCommander) и ставится в каждый матч до начала игры.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local CommanderPanel = require(script.Parent:WaitForChild("CommanderPanel"))
local Commanders = require(Shared:WaitForChild("Commanders"))
local Types = require(Shared:WaitForChild("Types"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type ArsenalPanel = {
	toggle: () -> (),
	isOpen: () -> boolean,
	refresh: () -> (),
	window: Frame,
}

local ArsenalPanel = {}

local W = 860
local CARD_W, CARD_H = 156, 106
local GEN_H = 118 -- §15ф Ф1: карточка генерала
local ICONS: { [string]: string } = {
	Reinforce = "reinforce",
	Convoy = "convoy",
	HqReserve = "hqReserve",
	Barrage = "barrage",
	Jammer = "jammer",
}
ArsenalPanel.Icons = ICONS

function ArsenalPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> ()
): ArsenalPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local order = Config.Arsenal.Order
	local items = Config.Arsenal.Items
	local selected = order[1]

	local window = Instance.new("Frame")
	window.Name = "ArsenalWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(W, 0)
	window.AutomaticSize = Enum.AutomaticSize.Y
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BorderSizePixel = 0
	window.Active = true
	window.Visible = false
	window.Parent = gui
	MenuKit.stroke(window, Theme.Colors.PanelBorder, 2)
	MenuKit.pad(window, 16, 14)
	MenuKit.list(window, 12)
	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function fit()
		local s = gui.AbsoluteSize
		scale.Scale = math.clamp(math.min((s.X - 24) / W, (s.Y - 24) / 720), 0.4, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()

	-- Заголовок, медали, «×».
	local head = Instance.new("Frame")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 52)
	head.LayoutOrder = 1
	head.Parent = window
	MenuKit.label(head, t("arsenal.title"), 26, Theme.Colors.Gold, true)
	local sub = MenuKit.label(head, t("arsenal.subtitle"), 13, Theme.Colors.Muted)
	sub.Position = UDim2.fromOffset(0, 32)
	local close = MenuKit.button(head, "×", "normal")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(MenuKit.Touch, MenuKit.Touch)
	close.TextSize = 24
	local medals = MenuKit.label(head, "", 18, Theme.Colors.Gold, true)
	medals.AnchorPoint = Vector2.new(1, 0.5)
	medals.Position = UDim2.new(1, -(MenuKit.Touch + 16), 0, MenuKit.Touch / 2)

	-- Большой предмет: слева поле со значком, справа описание и кнопка.
	local main = Instance.new("Frame")
	main.BackgroundTransparency = 1
	main.Size = UDim2.new(1, 0, 0, 250)
	main.LayoutOrder = 2
	main.Parent = window
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.Size = UDim2.new(0, 500, 1, 0)
	stage.BackgroundColor3 = Theme.color("Abyss")
	stage.BorderSizePixel = 0
	stage.ClipsDescendants = true
	stage.Parent = main
	MenuKit.stroke(stage, Theme.Colors.PanelBorder, 2)
	-- §15л ч.9: большая картинка предмета (ItemArt) во всё поле.
	local bigIcons: { [string]: ImageLabel } = {}
	for _, key in order do
		local art = CardKit.art(stage, "arsenal." .. key, 500, 250)
		art.Size = UDim2.fromScale(1, 1)
		art.Visible = false
		bigIcons[key] = art
	end
	local stageName = MenuKit.label(stage, "", 30, Theme.color("White"), true)
	stageName.AnchorPoint = Vector2.new(0.5, 1)
	stageName.Position = UDim2.new(0.5, 0, 1, -10)
	stageName.TextStrokeTransparency = 0.2
	stageName.ZIndex = 3

	local info = Instance.new("Frame")
	info.Name = "Info"
	info.AnchorPoint = Vector2.new(1, 0)
	info.Position = UDim2.fromScale(1, 0)
	info.Size = UDim2.new(1, -516, 1, 0)
	info.BackgroundColor3 = Theme.Colors.Backdrop
	info.BorderSizePixel = 0
	info.Parent = main
	MenuKit.stroke(info, Theme.Colors.PanelBorder, 2)
	MenuKit.pad(info, 12, 10)
	MenuKit.list(info, 6)
	local tag = MenuKit.label(info, "", 12, Theme.color("Ink"), true, 1)
	tag.BackgroundTransparency = 0
	tag.BackgroundColor3 = Theme.Colors.Gold
	MenuKit.pad(tag, 6, 2)
	local infoName = MenuKit.label(info, "", 22, Theme.Colors.Text, true, 2)
	local infoText = MenuKit.wrapLabel(info, "", 13, Theme.Colors.Muted, 3)
	local spacer = Instance.new("Frame")
	spacer.BackgroundTransparency = 1
	spacer.Size = UDim2.new(1, 0, 0, 8)
	spacer.LayoutOrder = 4
	spacer.Parent = info
	local progressHost = Instance.new("Frame")
	progressHost.BackgroundTransparency = 1
	progressHost.Size = UDim2.new(1, 0, 0, 10)
	progressHost.LayoutOrder = 5
	progressHost.Parent = info
	local progress = MenuKit.bar(progressHost, 10, Theme.Colors.Sky)
	local progressText = MenuKit.label(info, "", 13, Theme.Colors.Sky, true, 6)
	local action = MenuKit.button(info, "", "primary", 52, 7)

	-- Карточки предметов.
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, CARD_H)
	row.LayoutOrder = 3
	row.Parent = window
	MenuKit.list(row, 10, true)
	type Card = { button: TextButton, edge: UIStroke, name: TextLabel, price: TextLabel }
	local draw: () -> ()
	local cards: { [string]: Card } = {}
	for k, key in order do
		local b = Instance.new("TextButton")
		b.Name = "Item_" .. key
		b.Text = ""
		b.AutoButtonColor = true
		b.LayoutOrder = k
		b.Size = UDim2.fromOffset(CARD_W, CARD_H)
		b.BackgroundColor3 = Theme.Colors.Backdrop
		b.BorderSizePixel = 0
		b.Parent = row
		local edge = MenuKit.stroke(b, Theme.Colors.PanelBorder, 2)
		local icon = CardKit.art(b, "arsenal." .. key, CARD_W - 16, 52)
		icon.Position = UDim2.fromOffset(8, 6)
		local name = MenuKit.label(b, t("arsenal.item." .. key), 13, Theme.Colors.Text, true)
		name.AnchorPoint = Vector2.new(0.5, 0)
		name.Position = UDim2.new(0.5, 0, 0, 62)
		local price = MenuKit.label(b, "", 12, Theme.Colors.Gold, true)
		price.AnchorPoint = Vector2.new(0.5, 0)
		price.Position = UDim2.new(0.5, 0, 0, 84)
		cards[key] = { button = b, edge = edge, name = name, price = price }
		Session.connect(b.Activated, function()
			selected = key
			draw()
		end)
	end

	-- §15ф Ф1: «Генерал в бой» — выбор по умолчанию для всех матчей (раньше — в лобби).
	local generalsTitle = MenuKit.label(window, t("arsenal.generals"), 16, Theme.Colors.Sky, true, 4)
	generalsTitle.Size = UDim2.new(1, 0, 0, 20)
	local generals = Instance.new("Frame")
	generals.BackgroundTransparency = 1
	generals.Size = UDim2.new(1, 0, 0, GEN_H)
	generals.LayoutOrder = 5
	generals.Parent = window
	MenuKit.list(generals, 10, true)
	type General = { button: TextButton, edge: UIStroke, lock: TextLabel }
	local generalCards: { [string]: General } = {}
	local genW = math.floor((W - 32 - 10 * (#Types.CommanderIds - 1)) / #Types.CommanderIds)
	for k, raw in Types.CommanderIds do
		local id: Types.CommanderId = raw :: any
		local b = Instance.new("TextButton")
		b.Name = "General_" .. id
		b.Text = ""
		b.AutoButtonColor = true
		b.LayoutOrder = k
		b.Size = UDim2.fromOffset(genW, GEN_H)
		b.BackgroundColor3 = Theme.Colors.Backdrop
		b.BorderSizePixel = 0
		b.Parent = generals
		local edge = MenuKit.stroke(b, Theme.Colors.PanelBorder, 2)
		MenuKit.pad(b, 10, 8)
		MenuKit.list(b, 4)
		MenuKit.label(b, t("commander." .. id), 17, Theme.Colors.Text, true, 1)
		MenuKit.wrapLabel(
			b,
			string.format(
				"%s\nQ — %s\nE — %s",
				CommanderPanel.passive(id, lang),
				t("ability." .. Commanders.ability(id, 1)),
				t("ability." .. Commanders.ability(id, 2))
			),
			13,
			Theme.Colors.Muted,
			2
		)
		local lock = MenuKit.label(
			b,
			string.format(t("commander.locked"), (Config.Profile.CommanderLevels :: any)[id] or 1),
			13,
			Theme.Colors.Alert,
			true,
			3
		)
		generalCards[id] = { button = b, edge = edge, lock = lock }
		Session.connect(b.Activated, function()
			send("prefCommander", { commander = id })
		end)
	end

	local function level(): number
		local p = cs.profile
		return if p ~= nil then p.level else 1
	end
	local function arsenal(): { owned: { [string]: boolean }, loadout: string?, used: boolean }
		local p = cs.profile
		local a = if p ~= nil then p.arsenal else nil
		return a or { owned = {}, loadout = nil, used = false }
	end

	draw = function()
		local p = cs.profile
		local have = if p ~= nil then p.medals else 0
		local a = arsenal()
		medals.Text = string.format(t("arsenal.medals"), Strings.formatInt(have))
		for key, card in cards do
			local it = items[key]
			local owned = a.owned[key] == true
			local inBattle = a.loadout == key
			card.edge.Color = if key == selected
				then Theme.Colors.Gold
				elseif inBattle then Theme.Colors.Good
				else Theme.Colors.PanelBorder
			card.price.Text = if inBattle
				then t("arsenal.inBattle")
				elseif owned then t("arsenal.owned")
				elseif level() < it.level then string.format(t("arsenal.lockLevel"), it.level)
				else "🏅 " .. Strings.formatInt(it.price)
			card.price.TextColor3 = if inBattle
				then Theme.Colors.Good
				elseif owned then Theme.Colors.Sky
				else Theme.Colors.Gold
			bigIcons[key].Visible = key == selected
		end
		local it = items[selected]
		local owned = a.owned[selected] == true
		stageName.Text = t("arsenal.item." .. selected)
		infoName.Text = t("arsenal.item." .. selected)
		tag.Text = t(if it.target then "arsenal.tagTarget" else "arsenal.tagInstant")
		infoText.Text = t("arsenal.desc." .. selected)
		progressHost.Visible = not owned
		progressText.Visible = not owned
		progress.set(have / math.max(1, it.price))
		progressText.Text = string.format(t("arsenal.progress"), Strings.formatInt(have), Strings.formatInt(it.price))
		if a.loadout == selected then
			action.Text = t("arsenal.inBattleBtn")
		elseif owned then
			action.Text = t("arsenal.equip")
		elseif level() < it.level then
			action.Text = string.format(t("arsenal.lockLevel"), it.level)
		else
			action.Text = string.format(t("arsenal.buy"), Strings.formatInt(it.price))
		end
		local can = owned or (level() >= it.level and have >= it.price)
		action.AutoButtonColor = can
		action.BackgroundTransparency = if can then 0 else 0.45
		-- Генерал в бой: выбранный — золотом, закрытый — с замком.
		local pref = (if p ~= nil and p.arsenal ~= nil then p.arsenal.commander else nil) or "Marshal"
		for id, g in generalCards do
			local need = (Config.Profile.CommanderLevels :: any)[id] or 1
			g.lock.Visible = level() < need
			g.edge.Color = if id == pref then Theme.Colors.Gold else Theme.Colors.PanelBorder
			g.edge.Thickness = if id == pref then 3 else 2
		end
	end

	Session.connect(action.Activated, function()
		local a = arsenal()
		local it = items[selected]
		if a.loadout == selected then
			send("arsenalEquip", {}) -- снять (ничего не брать)
		elseif a.owned[selected] then
			send("arsenalEquip", { key = selected })
		elseif level() >= it.level then
			send("arsenalBuy", { key = selected })
		end
	end)

	local function toggle()
		window.Visible = not window.Visible
		if window.Visible then
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
		if input.KeyCode == Enum.KeyCode.U then
			toggle()
		elseif input.KeyCode == Enum.KeyCode.Escape and window.Visible then
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
		window = window,
	}
end

return table.freeze(ArsenalPanel)
