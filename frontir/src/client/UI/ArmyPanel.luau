--!strict
--[[
	ArmyPanel — армии в интерфейсе (GDD §6.6, §10):
	- снизу по центру — карточки найма (пехота, танки, артиллерия; клавиши 1–3), цена в людях и время;
	- справа — выбранная армия: тип, сила, состояние («Марш», «Захват 63%»), кнопки «Стоп», «Авто», «Снять»;
	- выделение: нажатие на свою армию (Shift — добавить), рамка левой кнопкой на ПК, Esc — снять.
	  Пока что-то выделено, нажатие на карту — приказ «идти сюда» (по прибытии армия захватывает провинцию).
	Все кнопки от 44 px (телефоны).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Armies = require(Shared:WaitForChild("Armies"))
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local ArmyLayer = require(script.Parent.Parent:WaitForChild("Render"):WaitForChild("ArmyLayer"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type ArmyPanel = {
	-- Нажатие на карту: true — обработано (выбор армии или приказ), false — пусть решает HUD (атака, старт).
	tap: (sx: number, sy: number, cell: number?, shift: boolean, state: CameraState) -> boolean,
	box: (x0: number, y0: number, x1: number, y1: number, shift: boolean, state: CameraState) -> (),
	refresh: () -> (),
	update: () -> (),
}

local ArmyPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

local function makeButton(parent: Instance, text: string, width: number, height: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, height)
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BackgroundTransparency = 0.1
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.RichText = true
	b.FontFace = Theme.FontBold
	b.TextSize = 15
	b.TextColor3 = Theme.Colors.Text
	b.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = b
	b.Parent = parent
	return b
end

function ArmyPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	layer: ArmyLayer.ArmyLayer,
	send: (string, { [string]: any }) -> ()
): ArmyPanel
	local selected: { [number]: boolean } = {}
	local gold, sky, muted = hex(Theme.Colors.Gold), hex(Theme.Colors.Sky), hex(Theme.Colors.Muted)

	local function selectedIds(): { number }
		local ids: { number } = {}
		for id in selected do
			table.insert(ids, id)
		end
		table.sort(ids)
		return ids
	end

	local function canCommand(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
	end

	-- Снизу по центру: карточки найма.
	local cards = Instance.new("Frame")
	cards.Name = "HireCards"
	cards.BackgroundTransparency = 1
	cards.AnchorPoint = Vector2.new(0.5, 1)
	cards.Position = UDim2.new(0.5, 0, 1, -12)
	cards.Size = UDim2.fromOffset(0, 56)
	cards.AutomaticSize = Enum.AutomaticSize.X
	cards.Parent = gui
	local cardsLayout = Instance.new("UIListLayout")
	cardsLayout.FillDirection = Enum.FillDirection.Horizontal
	cardsLayout.Padding = UDim.new(0, 6)
	cardsLayout.Parent = cards
	-- Узкий экран (телефон): по центру карточки налезут на ползунок атаки слева — прижимаем вправо.
	local function placeCards()
		if gui.AbsoluteSize.X < Config.Render.NarrowScreenPx then
			cards.AnchorPoint = Vector2.new(1, 1)
			cards.Position = UDim2.new(1, -12, 1, -12)
		else
			cards.AnchorPoint = Vector2.new(0.5, 1)
			cards.Position = UDim2.new(0.5, 0, 1, -12)
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeCards)
	placeCards()
	local cardButtons: { TextButton } = {}
	for k, kind in Types.LandUnits do
		local unit: Types.LandUnit = kind :: Types.LandUnit
		local stats = Armies.stats(unit)
		local b = makeButton(cards, "", 132, 56)
		b.Name = "Hire" .. kind
		b.Text = string.format(
			'<font color="%s">%d</font> %s\n<font size="12" color="%s">%s</font>',
			gold,
			k,
			Strings.get("unit." .. kind, lang),
			sky,
			string.format(Strings.get("hire.cost", lang), Strings.formatInt(stats.people), stats.recruitSec)
		)
		b.Activated:Connect(function()
			send("hire", { unit = kind })
		end)
		table.insert(cardButtons, b)
	end

	-- Справа: выбранная армия.
	local panel = Instance.new("Frame")
	panel.Name = "ArmyInfo"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -12, 0.5, 0)
	panel.Size = UDim2.fromOffset(3 * BUTTON + 2 * 6 + 16, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Theme.Colors.PanelBg
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = panel
	local panelLayout = Instance.new("UIListLayout")
	panelLayout.Padding = UDim.new(0, 6)
	panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
	panelLayout.Parent = panel
	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1
	info.RichText = true
	info.AutomaticSize = Enum.AutomaticSize.Y
	info.Size = UDim2.fromScale(1, 0)
	info.TextWrapped = true
	info.FontFace = Theme.Font
	info.TextSize = 14
	info.TextColor3 = Theme.Colors.Text
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.LayoutOrder = 1
	info.Parent = panel
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, BUTTON)
	row.LayoutOrder = 2
	row.Parent = panel
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.Parent = row
	local stopButton = makeButton(row, Strings.get("army.stop", lang), BUTTON + 4, BUTTON)
	local autoButton = makeButton(row, Strings.get("army.auto", lang), BUTTON + 4, BUTTON)
	local clearButton = makeButton(row, Strings.get("army.deselect", lang), BUTTON + 4, BUTTON)

	local function setSelection(ids: { number }, add: boolean)
		if not add then
			table.clear(selected)
		end
		for _, id in ids do
			if add and selected[id] then
				selected[id] = nil -- Shift по уже выбранной — снять с неё выделение
			else
				selected[id] = true
			end
		end
		layer.setSelected(selected)
	end

	stopButton.Activated:Connect(function()
		local ids = selectedIds()
		if #ids > 0 then
			send("stop", { armies = ids })
		end
	end)
	autoButton.Activated:Connect(function()
		local ids = selectedIds()
		if #ids == 0 then
			return
		end
		-- Если хоть одна не в «авто» — включаем всем, иначе выключаем.
		local turnOn = false
		for _, id in ids do
			local a = cs.armies[id]
			if a ~= nil and not a.auto then
				turnOn = true
			end
		end
		send("auto", { armies = ids, on = turnOn })
	end)
	clearButton.Activated:Connect(function()
		setSelection({}, false)
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			setSelection({}, false)
			return
		end
		for k, key in KEYS do
			if input.KeyCode == key and canCommand() then
				send("hire", { unit = Types.LandUnits[k] })
			end
		end
	end)

	local function refresh()
		local playing = canCommand()
		cards.Visible = playing
		local myStats = if cs.myNation ~= nil then ClientState.statsOf(cs, cs.myNation) else nil
		for k, b in cardButtons do
			local unit: Types.LandUnit = Types.LandUnits[k] :: Types.LandUnit
			local affordable = myStats ~= nil and myStats.people >= Armies.stats(unit).people
			b.TextTransparency = if affordable then 0 else 0.5
		end
	end

	local function update()
		-- Исчезнувшие армии выпадают из выделения.
		local changed = false
		for id in selected do
			local a = cs.armies[id]
			if a == nil or a.owner ~= cs.myNation then
				selected[id] = nil
				changed = true
			end
		end
		if changed then
			layer.setSelected(selected)
		end
		local ids = selectedIds()
		panel.Visible = #ids > 0
		if #ids == 0 then
			return
		end
		local text: string
		if #ids == 1 then
			local a = cs.armies[ids[1]]
			local stateText = Strings.get("army.state." .. a.state, lang)
			if a.state == "capture" or a.state == "recruit" then
				stateText = string.format(stateText, math.floor(a.progress * 100))
			end
			text = string.format(
				'<b>%s</b>\n%s\n<font color="%s">%s</font>\n<font color="%s">%s</font>',
				Strings.get("unit." .. a.kind, lang),
				string.format(
					Strings.get("army.strength", lang),
					string.format('<font color="%s">%s</font>', gold, Strings.formatInt(a.strength)),
					Strings.formatInt(a.maxStrength)
				),
				sky,
				stateText,
				muted,
				Strings.get(if a.auto then "army.auto.on" else "army.auto.off", lang)
			)
		else
			text = "<b>" .. string.format(Strings.get("army.selected", lang), #ids) .. "</b>"
		end
		text ..= string.format('\n<font size="12" color="%s">%s</font>', muted, Strings.get("army.hint", lang))
		info.Text = text
	end

	local function tap(sx: number, sy: number, cell: number?, shift: boolean, state: CameraState): boolean
		local myNation = cs.myNation
		if myNation == nil or not canCommand() then
			return false
		end
		local hit = layer.armyAt(sx, sy, state, myNation, os.clock())
		if hit ~= nil then
			setSelection({ hit }, shift)
			return true
		end
		local ids = selectedIds()
		if #ids > 0 and cell ~= nil then
			send("move", { armies = ids, cell = cell })
			return true
		end
		return false
	end

	local function box(x0: number, y0: number, x1: number, y1: number, shift: boolean, state: CameraState)
		local myNation = cs.myNation
		if myNation == nil then
			return
		end
		setSelection(layer.armiesInRect(x0, y0, x1, y1, state, myNation, os.clock()), shift)
	end

	return {
		tap = tap,
		box = box,
		refresh = refresh,
		update = update,
	}
end

return table.freeze(ArmyPanel)
