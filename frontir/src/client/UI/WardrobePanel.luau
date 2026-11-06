--!strict
--[[
	WardrobePanel — гардероб (GDD §11.4, этап 9в), клавиша K и кнопка справа сверху.
	- Узоры территории, вспышки захвата, титулы: «Надеть» / «Снять» для открытых, «Купить N» за медали,
	  «🔒 ур. N» / «🔒 пропуск» для открываемых уровнем и премиум-пропуском.
	- Флаг: предпросмотр и строки «◀ значение ▶» (фон, раскладка, её цвет, эмблема, её цвет); закрытая часть —
	  «Купить N»; «Сохранить флаг» — намерение flag (проверяет сервер).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Strings = require(Shared:WaitForChild("Strings"))

local FlagView = require(script.Parent:WaitForChild("FlagView"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type WardrobePanel = {
	refresh: () -> (),
	-- Самопроверка (сводная правка, часть 1): открыть/закрыть окно и узнать, открыто ли.
	toggle: () -> (),
	isOpen: () -> boolean,
}

local WardrobePanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local W = 520
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

	local window = Instance.new("ScrollingFrame")
	window.Name = "Wardrobe"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.new(0, W, 0.8, 0)
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BorderSizePixel = 0
	window.ScrollBarThickness = 6
	window.Visible = false
	window.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = window
	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function fit()
		scale.Scale = math.clamp((gui.AbsoluteSize.X - 24) / W, 0.5, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()
	local close = button(window, "×", BUTTON)
	close.Position = UDim2.fromOffset(W - 12 - BUTTON, 6)
	Session.connect(close.Activated, function()
		window.Visible = false
	end)

	local y = 8
	local function heading(key: string)
		local h = label(window, 15, true)
		h.Position = UDim2.fromOffset(12, y)
		h.Size = UDim2.fromOffset(W - 24 - BUTTON, 22)
		h.TextColor3 = Theme.Colors.Gold
		h.Text = Strings.get(key, lang)
		y += 26
	end

	-- Узоры, вспышки, титулы.
	type Row = { kind: Cosmetics.Kind, id: string, action: TextButton }
	local rows: { Row } = {}
	local function section(kind: Cosmetics.Kind, key: string)
		heading(key)
		for _, it in Cosmetics.list(kind) do
			local name = label(window, 13)
			name.Position = UDim2.fromOffset(12, y)
			name.Size = UDim2.fromOffset(W - 200, BUTTON)
			name.Text = Strings.get(kind .. "." .. it.id, lang)
			local action = button(window, "", 160)
			action.Position = UDim2.fromOffset(W - 12 - 160, y)
			local row: Row = { kind = kind, id = it.id, action = action }
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
			y += ROW
		end
	end
	section("pattern", "wardrobe.patterns")
	section("capture", "wardrobe.captures")
	section("title", "wardrobe.titles")

	-- Флаг.
	heading("wardrobe.flag")
	local preview = FlagView.new(window, 120, 80, 3)
	preview.frame.Position = UDim2.fromOffset(12, y)
	local draft: Cosmetics.Flag = Cosmetics.defaultFlag()
	local flagCfg = Config.Cosmetics.Flag
	type FlagRow = { field: string, value: TextLabel, buy: TextButton }
	local flagRows: { FlagRow } = {}
	local fy = y
	local function drawFlag()
		preview.set(draft)
		local p = cs.profile
		for _, fr in flagRows do
			local v = (draft :: any)[fr.field] :: string
			local isPart = fr.field == "layout" or fr.field == "emblem"
			fr.value.Text = if isPart then Strings.get("flag." .. v, lang) else Strings.get("color." .. v, lang)
			local owned = not isPart or (p ~= nil and p.wardrobe.owned[Cosmetics.key(fr.field :: any, v)] == true)
			fr.buy.Visible = not owned
			fr.buy.Text = string.format(Strings.get("wardrobe.buy", lang), flagCfg.PartPrice)
		end
	end
	for _, field in { "bg", "layout", "layoutColor", "emblem", "emblemColor" } do
		local name = label(window, 12)
		name.Position = UDim2.fromOffset(144, fy)
		name.Size = UDim2.fromOffset(100, BUTTON)
		name.Text = Strings.get("wardrobe.flag." .. field, lang)
		local prev = button(window, "◀", BUTTON)
		prev.Position = UDim2.fromOffset(248, fy)
		local value = label(window, 12, true)
		value.Position = UDim2.fromOffset(248 + BUTTON + 2, fy)
		value.Size = UDim2.fromOffset(90, BUTTON)
		value.TextXAlignment = Enum.TextXAlignment.Center
		local nextB = button(window, "▶", BUTTON)
		nextB.Position = UDim2.fromOffset(248 + BUTTON + 94, fy)
		local buy = button(window, "", 74)
		buy.Position = UDim2.fromOffset(W - 12 - 74, fy)
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
	y = math.max(y + 86, fy)
	local save = button(window, Strings.get("wardrobe.saveFlag", lang), 200)
	save.Position = UDim2.fromOffset(12, y)
	save.TextColor3 = Theme.Colors.Gold
	Session.connect(save.Activated, function()
		send("flag", { flag = draft })
	end)
	y += ROW + 8
	window.CanvasSize = UDim2.fromOffset(0, y)

	local function draw()
		local p = cs.profile
		openButton.Visible = p ~= nil
		if p == nil then
			return
		end
		local wr = p.wardrobe
		for _, row in rows do
			local it = Cosmetics.item(row.kind, row.id)
			local owned = wr.owned[Cosmetics.key(row.kind, row.id)] == true
			local worn = wr.equipped[row.kind] == row.id
			row.action.Text = if owned
				then Strings.get(if worn then "wardrobe.unequip" else "wardrobe.equip", lang)
				elseif it ~= nil and it.price ~= nil then string.format(
					Strings.get("wardrobe.buy", lang),
					it.price
				)
				elseif it ~= nil and it.level ~= nil then string.format(
					Strings.get("wardrobe.level", lang),
					it.level
				)
				else Strings.get("wardrobe.pass", lang)
			row.action.TextColor3 = if worn then Theme.Colors.Gold else Theme.Colors.Text
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
		refresh = draw,
		toggle = open,
		isOpen = function(): boolean
			return window.Visible
		end,
	}
end

return table.freeze(WardrobePanel)
