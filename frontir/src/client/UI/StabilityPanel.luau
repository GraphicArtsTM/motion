--!strict
--[[
	StabilityPanel — стабильность провинций (GDD §6.10, этап 7а; окно — §15ц Ц4а).
	- Окно шаблона CardKit (N, кнопка «Стабильность» у мини-карты): сводка, свои провинции от худшей к лучшей
	  (имя, число и полоса цветом стабильности, метка «ВОССТАНИЕ» / «доход ×0.5» — чистый StabilityList), нажатие —
	  камера к провинции; главная кнопка — «К самой слабой провинции».
	- Пока окно открыто, карта — в цветах стабильности (рисует TerritoryLayer), а с зума Render.StabilityLabelZoom в
	  центре каждой своей провинции — число.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local StabilityList = require(Shared:WaitForChild("StabilityList"))
local Strings = require(Shared:WaitForChild("Strings"))
local TerritoryPaint = require(Shared:WaitForChild("TerritoryPaint"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type StabilityPanel = {
	refresh: () -> (), -- пришла стабильность или сменилась фаза
	onCamera: (state: CameraState) -> (),
	-- §15з док: кнопка (прячется) и окно.
	button: GuiButton,
	toggle: () -> (),
	isOpen: () -> boolean,
	close: () -> (),
	window: Frame,
}

local StabilityPanel = {}

local ROW_H = 46
local LEVEL_COLOR: { [StabilityList.Level]: string } = { revolt = "Red", low = "Orange", ok = "Meadow" }

function StabilityPanel.new(
	gui: ScreenGui,
	canvas: Frame,
	cs: ClientState,
	lang: Strings.Lang,
	provinces: Provinces.ProvinceSet,
	setMode: (on: boolean) -> (),
	focus: (cell: number) -> ()
): StabilityPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local cfg = Config.Stability
	local zoom = 1
	local labels: { [number]: TextLabel } = {}

	-- Прежняя кнопка «Стабильность (N)»: на экране её нет (Main.client прячет), видимость = «можно открыть».
	local main = Instance.new("TextButton")
	main.Name = "StabilityButton"
	main.Size = UDim2.fromOffset(180, Config.Render.MinTouchTargetPx)
	main.Text = t("stability.button")
	main.Visible = false
	main.Parent = gui

	local win = CardKit.window(
		gui,
		"StabilityWindow",
		t("stability.titleBig"),
		string.format(t("stability.subtitle"), cfg.LowBelow, cfg.RevoltBelow),
		760,
		600,
		{},
		{ main = "list" },
		true
	)
	local window = win.frame
	local page = win.page("main")
	local foot = win.footer :: CardKit.Footer
	foot.set(t("stability.worst"), false, t("stability.hint"))
	local summary = MenuKit.wrapLabel(page, "", 15, Theme.Colors.Text, 0)
	summary.RichText = true
	local empty = MenuKit.wrapLabel(page, t("stability.none"), 14, Theme.Colors.Muted, 1)

	local function playing(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
	end
	local function isOpen(): boolean
		return window.Visible
	end

	-- Строки провинций (переиспользуются по номеру строки).
	type Row = { button: TextButton, name: TextLabel, tag: TextLabel, value: TextLabel, fill: Frame, province: number }
	local rows: { Row } = {}
	local function makeRow(k: number): Row
		local b = Instance.new("TextButton")
		b.Name = "Province"
		b.Text = ""
		b.LayoutOrder = 10 + k
		b.Size = UDim2.new(1, 0, 0, ROW_H)
		b.BackgroundColor3 = Theme.Colors.Backdrop
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.Parent = page
		MenuKit.stroke(b, Theme.Colors.PanelBorder, 2)
		local name = MenuKit.label(b, "", 15, Theme.Colors.Text, true)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.Position = UDim2.fromOffset(12, 5)
		name.Size = UDim2.new(1, -230, 0, 20)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local tag = MenuKit.label(b, "", 12, Theme.Colors.Muted, true)
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.new(1, -70, 0, 7)
		tag.TextXAlignment = Enum.TextXAlignment.Right
		local value = MenuKit.label(b, "", 20, Theme.Colors.Text, true)
		value.AnchorPoint = Vector2.new(1, 0.5)
		value.Position = UDim2.new(1, -14, 0.5, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right
		local track = Instance.new("Frame")
		track.Name = "Bar"
		track.BorderSizePixel = 0
		track.BackgroundColor3 = Theme.Colors.PanelBg
		track.Position = UDim2.new(0, 12, 1, -14)
		track.Size = UDim2.new(1, -90, 0, 6)
		track.Parent = b
		local fill = Instance.new("Frame")
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = track
		local row: Row = { button = b, name = name, tag = tag, value = value, fill = fill, province = 0 }
		Session.connect(b.Activated, function()
			local p = provinces.list[row.province]
			if p ~= nil then
				focus(p.center)
			end
		end)
		return row
	end

	local worst: number? = nil
	local function drawWindow()
		if not window.Visible then
			return
		end
		local st = cs.stability
		local list = StabilityList.rows(st.ids, st.values)
		local counts = StabilityList.counts(list)
		worst = StabilityList.worst(list)
		summary.Text = string.format(t("stability.summary"), st.average, #list, counts.revolt, st.lowCells)
		empty.Visible = #list == 0
		for k, r in list do
			local row = rows[k]
			if row == nil then
				row = makeRow(k)
				rows[k] = row
			end
			row.button.Visible = true
			row.province = r.province
			local p = provinces.list[r.province]
			row.name.Text = if p == nil then "?" elseif lang == "en" then p.nameEn else p.name
			local cr, cg, cb = TerritoryPaint.stabilityColor(r.value)
			local color = Color3.fromRGB(cr, cg, cb)
			row.value.Text = tostring(r.value)
			row.value.TextColor3 = color
			row.fill.BackgroundColor3 = color
			row.fill.Size = UDim2.fromScale(math.clamp(r.value / 100, 0, 1), 1)
			row.tag.Text = t("stability.tag." .. r.level)
			row.tag.TextColor3 = Theme.color(LEVEL_COLOR[r.level])
		end
		for k = #list + 1, #rows do
			rows[k].button.Visible = false
		end
		foot.set(t("stability.worst"), worst ~= nil)
	end
	Session.connect(foot.main.Activated, function()
		local p = if worst ~= nil then provinces.list[worst] else nil
		if p ~= nil then
			focus(p.center)
		end
	end)

	local function clearLabels()
		for _, l in labels do
			l:Destroy()
		end
		table.clear(labels)
	end

	local function placeLabel(l: TextLabel, cell: number)
		local w = cs.width
		local cx, cy = cell % w, cell // w
		local left, top = CameraMath.cellEdge(zoom, cx), CameraMath.cellEdge(zoom, cy)
		l.Position = UDim2.fromOffset(
			left + (CameraMath.cellEdge(zoom, cx + 1) - left) / 2,
			top + (CameraMath.cellEdge(zoom, cy + 1) - top) / 2
		)
	end

	-- Числа на своих провинциях: только пока окно открыто и с достаточного зума.
	local function drawLabels()
		local show = isOpen() and playing() and zoom >= Config.Render.StabilityLabelZoom
		if not show then
			clearLabels()
			return
		end
		local seen: { [number]: boolean } = {}
		for k, p in cs.stability.ids do
			local province = provinces.list[p]
			if province ~= nil then
				seen[p] = true
				local label: TextLabel
				local existing: TextLabel? = labels[p]
				if existing ~= nil then
					label = existing
				else
					local made = Instance.new("TextLabel")
					made.Name = "Stability_" .. p
					made.AnchorPoint = Vector2.new(0.5, 0.5)
					made.Size = UDim2.fromOffset(34, 18)
					made.BackgroundColor3 = Theme.Colors.Backdrop
					made.BackgroundTransparency = 0.25
					made.BorderSizePixel = 0
					made.FontFace = Theme.FontBold
					made.TextSize = 13
					made.ZIndex = 8
					made.Parent = canvas
					labels[p] = made
					label = made
				end
				local value = cs.stability.values[k] or 0
				local r, g, b = TerritoryPaint.stabilityColor(value)
				label.Text = tostring(value)
				label.TextColor3 = Color3.fromRGB(r, g, b)
				placeLabel(label, province.center)
			end
		end
		for p, l in labels do
			if not seen[p] then
				l:Destroy()
				labels[p] = nil
			end
		end
	end

	-- Окно открыто ⇔ карта в цветах стабильности.
	local wasOpen = false
	local function sync()
		local open = window.Visible
		if open ~= wasOpen then
			wasOpen = open
			setMode(open)
		end
		drawWindow()
		drawLabels()
	end
	Session.connect(window:GetPropertyChangedSignal("Visible"), sync)
	setMode(false)

	local function setOpen(open: boolean)
		window.Visible = open and playing()
	end
	Session.connect(main.Activated, function()
		setOpen(not isOpen())
	end)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.N and playing() then
			setOpen(not isOpen())
		end
	end)

	return {
		button = main,
		window = window,
		toggle = function()
			setOpen(not isOpen())
		end,
		isOpen = isOpen,
		close = function()
			setOpen(false)
		end,
		refresh = function()
			main.Visible = playing()
			if not playing() and isOpen() then
				setOpen(false)
			end
			drawWindow()
			drawLabels()
		end,
		onCamera = function(state: CameraState)
			if state.zoom ~= zoom then
				zoom = state.zoom
				drawLabels()
			end
		end,
	}
end

return table.freeze(StabilityPanel)
