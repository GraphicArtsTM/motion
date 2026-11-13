--!strict
--[[
	WardrobePanel — гардероб (GDD §11.4, этап 9в), клавиша K и кнопка справа сверху.
	- Узоры территории, вспышки захвата, титулы: «Надеть» / «Снять» для открытых, «Купить N» за медали,
	  «🔒 ур. N» / «🔒 пропуск» для открываемых уровнем и премиум-пропуском.
	- Флаг: предпросмотр и строки «◀ значение ▶» (фон, раскладка, её цвет, эмблема, её цвет); закрытая часть —
	  «Купить N»; «Сохранить флаг» — намерение flag (проверяет сервер).
	§15л ч.9: витрина CardKit — вкладки, карточки с картинками ItemArt (узор, вспышка, титул), «НАДЕТО» / «ЕСТЬ».
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Strings = require(Shared:WaitForChild("Strings"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local FlagView = require(script.Parent:WaitForChild("FlagView"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type WardrobePanel = {
	button: GuiButton, -- §15з: кнопка прячется в док
	refresh: () -> (),
	-- Самопроверка (сводная правка, часть 1): открыть/закрыть окно и узнать, открыто ли.
	toggle: () -> (),
	isOpen: () -> boolean,
}

local WardrobePanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local ROW = BUTTON + 6

local function label(parent: Instance, size: number, bold: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = if bold then Theme.FontBold else Theme.Font
	t.TextSize = size
	t.TextColor3 = Theme.Colors.Text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Parent = parent
	return t
end

local function button(parent: Instance, text: string, w: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(w, BUTTON)
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
	b.Parent = parent
	return b
end

local function cycle(list: { string }, value: string, dir: number): string
	local k = table.find(list, value) or 1
	return list[(k - 1 + dir) % #list + 1]
end

function WardrobePanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> ()
): WardrobePanel
	local openButton = button(gui, Strings.get("wardrobe.open", lang), 220)
	openButton.AnchorPoint = Vector2.new(1, 0)
	openButton.Position = UDim2.new(1, -12, 0, 124 + BUTTON + 24)

	-- §15л ч.9: витрина CardKit — вкладки «Узоры», «Вспышки», «Титулы», «Флаг», карточки с картинками ItemArt.
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local win = CardKit.window(gui, "Wardrobe", t("wardrobe.title"), t("wardrobe.subtitle"), 860, 720, {
		{ key = "pattern", label = t("wardrobe.patterns") },
		{ key = "capture", label = t("wardrobe.captures") },
		{ key = "title", label = t("wardrobe.titles") },
		{ key = "flag", label = t("wardrobe.flag") },
	}, { flag = "list" }, true)
	local window = win.frame; -- §15ц Ц5а: низ витрины — где взять медали (кнопки — на карточках).
	(win.footer :: CardKit.Footer).set("", false, t("wardrobe.hint"))
	local medalsChip = CardKit.chip(win.chips, "money", 1)

	-- Узоры, вспышки, титулы.
	type Row = { kind: Cosmetics.Kind, id: string, action: TextButton, card: CardKit.Card }
	local rows: { Row } = {}
	local function section(kind: Cosmetics.Kind)
		for k, it in Cosmetics.list(kind) do
			local card = CardKit.card(
				win.page(kind),
				kind .. "." .. it.id,
				Strings.get(kind .. "." .. it.id, lang),
				t("wardrobe.desc." .. kind),
				k
			)
			local action = CardKit.button(card.actions, "", "primary", 1)
			local row: Row = { kind = kind, id = it.id, action = action, card = card }
			Session.connect(action.Activated, function()
				local p = cs.profile
				if p == nil then
					return
				end
				local wr = p.wardrobe
				if wr.owned[Cosmetics.key(kind, it.id)] then
					local worn = wr.equipped[kind] == it.id
					send("equip", { kind = kind, id = if worn then nil else it.id })
				elseif it.price ~= nil then
					send("buyCosmetic", { kind = kind, id = it.id })
				end
			end)
			table.insert(rows, row)
		end
	end
	section("pattern")
	section("capture")
	section("title")

	-- Флаг: большой флаг слева, части справа (◀ значение ▶, закрытая — «Купить»), «Сохранить флаг».
	local flagPage = win.page("flag")
	local flagBox = Instance.new("Frame")
	flagBox.Name = "FlagEditor"
	flagBox.BackgroundColor3 = Theme.Colors.Backdrop
	flagBox.BorderSizePixel = 0
	flagBox.Size = UDim2.new(1, 0, 0, 5 * ROW + 80)
	flagBox.Parent = flagPage
	MenuKit.stroke(flagBox, Theme.Colors.PanelBorder, 2)
	local preview = FlagView.new(flagBox, 240, 160, 3)
	preview.frame.Position = UDim2.fromOffset(16, 16)
	local draft: Cosmetics.Flag = Cosmetics.defaultFlag()
	local flagCfg = Config.Cosmetics.Flag
	type FlagRow = { field: string, value: TextLabel, buy: TextButton }
	local flagRows: { FlagRow } = {}
	local fx, fy = 280, 16
	local function drawFlag()
		preview.set(draft)
		local p = cs.profile
		for _, fr in flagRows do
			local v = (draft :: any)[fr.field] :: string
			local isPart = fr.field == "layout" or fr.field == "emblem"
			fr.value.Text = if isPart then Strings.get("flag." .. v, lang) else Strings.get("color." .. v, lang)
			local owned = not isPart or (p ~= nil and p.wardrobe.owned[Cosmetics.key(fr.field :: any, v)] == true)
			fr.buy.Visible = not owned
			fr.buy.Text = string.format(t("wardrobe.buy"), flagCfg.PartPrice)
		end
	end
	for _, field in { "bg", "layout", "layoutColor", "emblem", "emblemColor" } do
		local name = label(flagBox, 14)
		name.Position = UDim2.fromOffset(fx, fy)
		name.Size = UDim2.fromOffset(120, BUTTON)
		name.TextColor3 = Theme.Colors.Muted
		name.Text = t("wardrobe.flag." .. field)
		local prev = button(flagBox, "◀", BUTTON)
		prev.Position = UDim2.fromOffset(fx + 124, fy)
		local value = label(flagBox, 14, true)
		value.Position = UDim2.fromOffset(fx + 124 + BUTTON + 4, fy)
		value.Size = UDim2.fromOffset(120, BUTTON)
		value.TextXAlignment = Enum.TextXAlignment.Center
		local nextB = button(flagBox, "▶", BUTTON)
		nextB.Position = UDim2.fromOffset(fx + 124 + BUTTON + 128, fy)
		local buy = button(flagBox, "", 110)
		buy.Position = UDim2.fromOffset(fx + 124 + 2 * BUTTON + 136, fy)
		buy.TextColor3 = Theme.Colors.Gold
		local list: { string } = if field == "layout"
			then flagCfg.Layouts
			elseif field == "emblem" then flagCfg.Emblems
			else flagCfg.Colors
		local function step(dir: number)
			(draft :: any)[field] = cycle(list, (draft :: any)[field], dir)
			drawFlag()
		end
		Session.connect(prev.Activated, function()
			step(-1)
		end)
		Session.connect(nextB.Activated, function()
			step(1)
		end)
		Session.connect(buy.Activated, function()
			send("buyCosmetic", { kind = field, id = (draft :: any)[field] })
		end)
		table.insert(flagRows, { field = field, value = value, buy = buy })
		fy += ROW
	end
	local save = CardKit.button(flagBox, t("wardrobe.saveFlag"), "primary")
	save.Position = UDim2.fromOffset(16, 192)
	save.Size = UDim2.fromOffset(240, MenuKit.Touch)
	Session.connect(save.Activated, function()
		send("flag", { flag = draft })
	end)

	local function draw()
		local p = cs.profile
		openButton.Visible = p ~= nil
		if p == nil then
			return
		end
		medalsChip.Text = Strings.formatInt(p.medals)
		local wr = p.wardrobe
		for _, row in rows do
			local it = Cosmetics.item(row.kind, row.id)
			local owned = wr.owned[Cosmetics.key(row.kind, row.id)] == true
			local worn = wr.equipped[row.kind] == row.id
			row.action.Text = if owned
				then t(if worn then "wardrobe.unequip" else "wardrobe.equip")
				elseif it ~= nil and it.price ~= nil then string.format(t("wardrobe.buy"), it.price)
				elseif it ~= nil and it.level ~= nil then string.format(t("wardrobe.level"), it.level)
				else t("wardrobe.pass")
			local canBuy = not owned and it ~= nil and it.price ~= nil and p.medals >= (it.price :: number)
			row.action.BackgroundColor3 =
				Theme.color(if worn then "Slate" elseif owned then "Forest" elseif canBuy then "Gold" else "Basalt")
			row.action.TextColor3 = Theme.color(if canBuy and not owned then "Ink" else "White")
			row.card.tag.Visible = worn or owned
			row.card.tag.Text = t(if worn then "wardrobe.tagWorn" else "wardrobe.tagOwned")
			row.card.edge.Color = if worn
				then Theme.Colors.Gold
				elseif owned then Theme.Colors.Good
				else Theme.Colors.PanelBorder
			row.card.price.Text = if owned then "" else row.action.Text
			row.card.dim.Visible = not owned and not canBuy
		end
		drawFlag()
	end
	local function open()
		local p = cs.profile
		if p ~= nil then
			draft = table.clone(p.wardrobe.flag)
		end
		window.Visible = not window.Visible
		draw()
	end
	Session.connect(win.close.Activated, function()
		window.Visible = false
	end)
	Session.connect(openButton.Activated, open)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.K then
			open()
		end
	end)

	return {
		button = openButton,
		refresh = draw,
		toggle = open,
		isOpen = function(): boolean
			return window.Visible
		end,
	}
end

return table.freeze(WardrobePanel)
