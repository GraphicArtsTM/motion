--!strict
--[[
	DiplomacyPanel — окно дипломатии и входящие предложения (GDD §8.1, этап 6а).
	- Кнопка «Дипломатия (T)» и клавиша T открывают окно: державы по суше — цвет, имя, отношение с вами
	  (мир, война, пакт с остатком срока, союз, вассал, сюзерен, разрыв), метка «Предатель», сила примерно.
	- Выбрали державу — действия: пакт 3 / 5 мин, союз, разорвать, требование (потом нажать её провинцию на карте),
	  объявить войну (окно WarPanel), независимость (если вы вассал). Внизу — история договоров матча.
	- Входящее предложение или требование — окно с таймером: принять / отказать (у требования — «Отдать»).
	Все решения — на сервере; клиент шлёт намерения offer / offerReply / breakTreaty / rebel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local MapData = require(Shared:WaitForChild("MapData"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type DiplomacyPanel = {
	refresh: () -> (),
	update: (now: number) -> (),
	tap: (cell: number) -> boolean, -- режим требования забирает нажатие на карту
}

local DiplomacyPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local WIDTH = 560
local ROW_H = 30

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

local function escape(s: string): string
	return (
		string.gsub(s, "[&<>\"']", {
			["&"] = "&amp;",
			["<"] = "&lt;",
			[">"] = "&gt;",
			['"'] = "&quot;",
			["'"] = "&apos;",
		})
	)
end

local function frame(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Theme.Colors.PanelBg
	f.BackgroundTransparency = 0.05
	f.BorderSizePixel = 0
	f.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = f
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = f
	f.Parent = parent
	return f
end

local function label(parent: Instance, size: number, order: number): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.RichText = true
	t.TextWrapped = true
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.fromScale(1, 0)
	t.FontFace = Theme.Font
	t.TextSize = size
	t.TextColor3 = Theme.Colors.Text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.LayoutOrder = order
	t.Parent = parent
	return t
end

local function button(parent: Instance, text: string, width: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, BUTTON)
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.RichText = true
	b.TextWrapped = true
	b.FontFace = Theme.FontBold
	b.TextSize = 14
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

local function row(parent: Instance, order: number, wraps: boolean?): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, BUTTON)
	f.AutomaticSize = if wraps then Enum.AutomaticSize.Y else Enum.AutomaticSize.None
	f.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Wraps = wraps == true
	layout.Parent = f
	f.Parent = parent
	return f
end

function DiplomacyPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	map: MapData.MapData,
	provinces: Provinces.ProvinceSet,
	send: (string, { [string]: any }) -> (),
	toast: (text: string) -> (),
	declareWar: (target: number) -> ()
): DiplomacyPanel
	local muted, alert, gold, sky =
		hex(Theme.Colors.Muted), hex(Theme.Colors.Alert), hex(Theme.Colors.Gold), hex(Theme.Colors.Sky)
	local now = os.clock()

	local function nationColor(id: number): string
		local n = cs.nations[id]
		if n == nil or n.colorIndex < 1 then
			return hex(Theme.Colors.Text)
		end
		local c = NationColors.Colors[n.colorIndex]
		return string.format("#%02x%02x%02x", c.r, c.g, c.b)
	end
	local function nameOf(id: number): string
		local n = cs.nations[id]
		if n == nil then
			return "?"
		end
		return string.format(
			'<font color="%s">%s</font>',
			nationColor(id),
			escape(if lang == "en" then n.nameEn else n.name)
		)
	end
	local function playing(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
	end
	local function clock(sec: number): string
		local s = math.max(0, math.ceil(sec))
		return string.format("%d:%02d", s // 60, s % 60)
	end

	-- Кнопка рядом с «Построить»: по центру снизу (на узком экране — слева от мини-карты).
	local mainButton = button(gui, Strings.get("diplo.button", lang), 180)
	mainButton.Name = "DiplomacyButton"
	local function placeMain()
		if gui.AbsoluteSize.X < Config.Render.NarrowScreenPx then
			mainButton.AnchorPoint = Vector2.new(1, 1)
			mainButton.Position = UDim2.new(1, -20 - Config.Render.MinimapSide - 208, 1, -12 - 2 * 56 - 12)
		else
			mainButton.AnchorPoint = Vector2.new(1, 1)
			mainButton.Position = UDim2.new(0.5, -108, 1, -12 - 56 - 6)
		end
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), placeMain)
	placeMain()

	-- Окно.
	local window = frame(gui, "Diplomacy")
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(WIDTH, 0)
	window.AutomaticSize = Enum.AutomaticSize.Y
	window.ZIndex = 5
	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function fit()
		local s = gui.AbsoluteSize
		scale.Scale = math.clamp(math.min(s.X / (WIDTH + 40), s.Y / 560), 0.55, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()

	local header = row(window, 1)
	local title = label(header, 18, 1)
	title.Size = UDim2.new(1, -BUTTON - 6, 0, BUTTON)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.FontFace = Theme.FontBold
	title.TextColor3 = Theme.Colors.Gold
	title.Text = Strings.get("diplo.title", lang)
	local closeButton = button(header, "×", BUTTON)
	closeButton.LayoutOrder = 2

	local list = Instance.new("ScrollingFrame")
	list.Name = "Nations"
	list.BackgroundColor3 = Theme.Colors.Backdrop
	list.BackgroundTransparency = 0.3
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, 0, 0, 7 * ROW_H)
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.LayoutOrder = 2
	list.Parent = window
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local selectedText = label(window, 15, 3)
	local actions = row(window, 4, true)
	local hint = label(window, 12, 5)
	hint.TextColor3 = Theme.Colors.Muted
	hint.Text = Strings.get("diplo.act.hint", lang) .. "\n" .. Strings.get("diplo.taxHint", lang)
	local historyText = label(window, 12, 6)

	local selected: number? = nil
	local demandTarget: number? = nil

	local function act(key: string, handler: () -> ()): TextButton
		local b = button(actions, Strings.get("diplo.act." .. key, lang), 128)
		Session.connect(b.Activated, handler)
		return b
	end
	local function offer(kind: string)
		if selected ~= nil and playing() then
			send("offer", { target = selected, offer = kind })
		end
	end
	local pact3Button = act("pact3", function()
		offer("pact3")
	end)
	local pact5Button = act("pact5", function()
		offer("pact5")
	end)
	local allianceButton = act("alliance", function()
		offer("alliance")
	end)
	local breakButton = act("break", function()
		if selected ~= nil and playing() then
			send("breakTreaty", { target = selected })
		end
	end)
	local demandButton = act("demand", function()
		if selected ~= nil and playing() then
			demandTarget = selected
			window.Visible = false
			toast(string.format(Strings.get("diplo.demandHint", lang), nameOf(selected)))
		end
	end)
	local warButton = act("war", function()
		if selected ~= nil and playing() then
			window.Visible = false
			declareWar(selected)
		end
	end)
	warButton.TextColor3 = Theme.Colors.Alert
	-- Разведка (§6.11а): мощь цели видна Intel.DurationSec; цена и проверки — на сервере.
	local intelButton = act("intel", function()
		if selected ~= nil and playing() then
			send("intel", { target = selected })
		end
	end)
	intelButton.Text = string.format(
		Strings.get("diplo.act.intel", lang),
		Strings.formatInt(Config.Intel.Cost),
		Config.Intel.DurationSec
	)
	local tradeButton = act("trade", function()
		offer("trade")
	end)
	local embargoButton = act("embargo", function()
		local me = cs.myNation
		if selected ~= nil and me ~= nil and playing() then
			send("embargo", { target = selected, on = not ClientState.embargoBy(cs, me, selected) })
		end
	end)
	-- Быстрые переводы (§8.2): налог и лимит проверяет сервер.
	local quick = Config.Trade.QuickAmounts
	local function give(money: number, oil: number, people: number)
		if selected ~= nil and playing() then
			send("transfer", { target = selected, money = money, oil = oil, people = people })
		end
	end
	local moneyButton = act("giveMoney", function()
		give(quick.money, 0, 0)
	end)
	moneyButton.Text = string.format(Strings.get("diplo.act.giveMoney", lang), Strings.formatInt(quick.money))
	local oilButton = act("giveOil", function()
		give(0, quick.oil, 0)
	end)
	oilButton.Text = string.format(Strings.get("diplo.act.giveOil", lang), Strings.formatInt(quick.oil))
	local peopleButton = act("givePeople", function()
		give(0, 0, quick.people)
	end)
	peopleButton.Text = string.format(Strings.get("diplo.act.givePeople", lang), Strings.formatInt(quick.people))
	local rebelButton = act("rebel", function()
		if playing() then
			send("rebel", {})
		end
	end)
	rebelButton.TextColor3 = Theme.Colors.Gold

	-- Строки списка держав (по одной на державу, переиспользуются).
	local rows: { [number]: TextButton } = {}
	local function rowFor(id: number): TextButton
		local existing: TextButton? = rows[id]
		if existing ~= nil then
			return existing
		end
		do
			local nb = Instance.new("TextButton")
			nb.Size = UDim2.new(1, -8, 0, ROW_H)
			nb.BackgroundColor3 = Theme.Colors.PanelBg
			nb.BackgroundTransparency = 1
			nb.BorderSizePixel = 0
			nb.AutoButtonColor = true
			nb.RichText = true
			nb.FontFace = Theme.Font
			nb.TextSize = 14
			nb.TextColor3 = Theme.Colors.Text
			nb.TextXAlignment = Enum.TextXAlignment.Left
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 6)
			pad.Parent = nb
			Session.connect(nb.Activated, function()
				selected = id
			end)
			nb.Parent = list
			rows[id] = nb
			return nb
		end
	end

	-- Отношение державы id к нам (текст).
	local function relation(id: number): string
		local me = cs.myNation
		if me == nil then
			return ""
		end
		local war = ClientState.warBetween(cs, me, id)
		if war ~= nil then
			return string.format(
				'<font color="%s">%s</font>',
				alert,
				Strings.get(if war.active then "diplo.rel.war" else "diplo.rel.mobilizing", lang)
			)
		end
		if ClientState.overlordOf(cs, id) == me then
			return string.format('<font color="%s">%s</font>', gold, Strings.get("diplo.rel.vassal", lang))
		end
		if ClientState.overlordOf(cs, me) == id then
			return string.format('<font color="%s">%s</font>', gold, Strings.get("diplo.rel.overlord", lang))
		end
		local t = ClientState.treatyBetween(cs, me, id)
		if t ~= nil then
			local text = if t.kind == "alliance"
				then Strings.get("diplo.rel.alliance", lang)
				else string.format(
					Strings.get("diplo.rel.pact", lang),
					clock(ClientState.diploLeft(cs, t.left or 0, now, ClientState.simRate(cs)) / cs.speed)
				)
			if t.breakLeft ~= nil then
				text ..= " · " .. string.format(
					Strings.get("diplo.rel.breaking", lang),
					math.ceil(ClientState.diploLeft(cs, t.breakLeft, now, ClientState.simRate(cs)) / cs.speed)
				)
			end
			return string.format('<font color="%s">%s</font>', sky, text)
		end
		return Strings.get("diplo.rel.peace", lang)
	end
	-- Торговля и эмбарго (§8.2) — довеском к отношению.
	local function tradeTags(id: number): string
		local me = cs.myNation
		if me == nil then
			return ""
		end
		local out = ""
		if ClientState.hasTrade(cs, me, id) then
			out ..= string.format(' <font color="%s">· %s</font>', gold, Strings.get("diplo.rel.trade", lang))
		end
		if ClientState.embargoBy(cs, me, id) or ClientState.embargoBy(cs, id, me) then
			out ..= string.format(' <font color="%s">· %s</font>', alert, Strings.get("diplo.rel.embargo", lang))
		end
		return out
	end

	local function powerOf(id: number): number
		local s = ClientState.statsOf(cs, id)
		if s ~= nil and (s.power < 0 or s.frontPower < 0) then
			return -1 -- скрытая мощь (§6.11а)
		end
		return if s ~= nil then s.power + s.frontPower else 0
	end
	local function approx(v: number): string
		if v >= 1000 then
			return string.format("%.1fk", v / 1000)
		end
		return tostring(math.floor(v + 0.5))
	end

	local function historyLine(e: { kind: string, a: number, b: number, minutes: number? }): string
		local key = "diplo.hist." .. e.kind
		if e.kind == "pact" then
			return string.format(Strings.get(key, lang), nameOf(e.a), nameOf(e.b), e.minutes or 0)
		end
		return string.format(Strings.get(key, lang), nameOf(e.a), nameOf(e.b))
	end

	local function drawWindow()
		local me = cs.myNation
		-- Список: живые державы по суше.
		local order: { { id: number, cells: number } } = {}
		for id, n in cs.nations do
			if n.alive then
				local s = ClientState.statsOf(cs, id)
				table.insert(order, { id = id, cells = if s ~= nil then s.cells else 0 })
			end
		end
		table.sort(order, function(a, b)
			if a.cells ~= b.cells then
				return a.cells > b.cells
			end
			return a.id < b.id
		end)
		local shown: { [number]: boolean } = {}
		for k, entry in order do
			local id = entry.id
			shown[id] = true
			local b = rowFor(id)
			b.LayoutOrder = k
			b.Visible = true
			b.BackgroundTransparency = if id == selected then 0.4 else 1
			local traitor = if ClientState.isTraitor(cs, id, now, ClientState.simRate(cs))
				then string.format(' <font color="%s">⚠ %s</font>', alert, Strings.get("diplo.traitor", lang))
				else ""
			b.Text = if id == me
				then string.format(
					'<font color="%s">■</font> %s <font color="%s">(%s)</font>%s',
					nationColor(id),
					nameOf(id),
					gold,
					Strings.get("diplo.you", lang),
					traitor
				)
				else string.format(
					'<font color="%s">■</font> %s%s  ·  %s%s  <font size="12" color="%s">%s</font>',
					nationColor(id),
					nameOf(id),
					traitor,
					relation(id),
					tradeTags(id),
					muted,
					string.format(
						Strings.get("diplo.power", lang),
						if powerOf(id) < 0 then "?" else approx(powerOf(id))
					)
				)
		end
		for id, b in rows do
			if not shown[id] then
				b.Visible = false
			end
		end
		-- Генерал державы (§6.15) — виден всем.
		local function commanderOf(id: number): string
			local c = cs.nations[id].commander
			if c == nil then
				return ""
			end
			return string.format(
				'  ·  <font color="%s">%s</font>',
				muted,
				string.format(Strings.get("commander.label", lang), Strings.get("commander." .. c, lang))
			)
		end
		-- Выбранная держава и действия.
		local target = selected
		local valid = target ~= nil and target ~= me and cs.nations[target] ~= nil and cs.nations[target].alive
		local t = if valid and me ~= nil and target ~= nil then ClientState.treatyBetween(cs, me, target) else nil
		local lord = if me ~= nil then ClientState.overlordOf(cs, me) else nil
		selectedText.Text = if valid and target ~= nil
			then nameOf(target) .. "  ·  " .. relation(target) .. commanderOf(target)
			else string.format('<font color="%s">%s</font>', muted, Strings.get("diplo.pick", lang))
		for _, b in { pact3Button, pact5Button, allianceButton, demandButton, warButton, tradeButton } do
			b.Visible = valid
		end
		for _, b in { embargoButton, moneyButton, oilButton, peopleButton } do
			b.Visible = valid
		end
		-- Разведывать есть смысл, только пока мощь скрыта.
		intelButton.Visible = valid and target ~= nil and powerOf(target) < 0
		if valid and me ~= nil and target ~= nil then
			embargoButton.Text = Strings.get(
				if ClientState.embargoBy(cs, me, target) then "diplo.act.unembargo" else "diplo.act.embargo",
				lang
			)
		end
		breakButton.Visible = valid and t ~= nil
		rebelButton.Visible = lord ~= nil
		if lord ~= nil and me ~= nil then
			for _, v in cs.diplo.vassals do
				if v.vassal == me then
					local left = ClientState.diploLeft(cs, v.rebelLeft, now, ClientState.simRate(cs)) / cs.speed
					rebelButton.Text = Strings.get("diplo.act.rebel", lang)
						.. if left > 0 then string.format(" %s", clock(left)) else ""
				end
			end
		end
		-- История договоров (последние сверху).
		local lines = { string.format('<font color="%s"><b>%s</b></font>', muted, Strings.get("diplo.history", lang)) }
		local history = cs.diplo.history
		for k = #history, math.max(1, #history - 5), -1 do
			table.insert(lines, historyLine(history[k]))
		end
		historyText.Text = table.concat(lines, "\n")
	end

	-- Входящее предложение или требование.
	local popup = frame(gui, "DiplomacyOffer")
	popup.AnchorPoint = Vector2.new(0.5, 0)
	popup.Position = UDim2.new(0.5, 0, 0, 300)
	popup.Size = UDim2.fromOffset(380, 0)
	popup.AutomaticSize = Enum.AutomaticSize.Y
	popup.ZIndex = 6
	local popupText = label(popup, 15, 1)
	local popupLeft = label(popup, 12, 2)
	popupLeft.TextColor3 = Theme.Colors.Muted
	local popupRow = row(popup, 3)
	local acceptButton = button(popupRow, Strings.get("diplo.accept", lang), 170)
	acceptButton.TextColor3 = Theme.Colors.Sky
	local refuseButton = button(popupRow, Strings.get("diplo.refuse", lang), 170)
	refuseButton.TextColor3 = Theme.Colors.Alert
	local popupFrom: number? = nil
	local answered: { [string]: boolean } = {} -- уже ответили (ждём, пока сервер уберёт предложение)

	local function offerKey(o: ClientState.DiploOffer): string
		return string.format("%d:%d:%s", o.from, o.to, o.kind)
	end
	local function currentOffer(): ClientState.DiploOffer?
		local me = cs.myNation
		for _, o in cs.diplo.offers do
			if o.to == me and not answered[offerKey(o)] then
				if ClientState.diploLeft(cs, o.left, now, ClientState.simRate(cs)) > 0 then
					return o
				end
			end
		end
		return nil
	end
	local function reply(accept: boolean)
		local o = currentOffer()
		if o ~= nil then
			answered[offerKey(o)] = true
			send("offerReply", { target = o.from, accept = accept })
		end
		popup.Visible = false
	end
	Session.connect(acceptButton.Activated, function()
		reply(true)
	end)
	Session.connect(refuseButton.Activated, function()
		reply(false)
	end)

	local function drawPopup()
		local o = if playing() then currentOffer() else nil
		if o == nil then
			popup.Visible = false
			popupFrom = nil
			return
		end
		if popupFrom ~= o.from then
			popupFrom = o.from
			if o.kind == "demand" then
				local p = if o.province ~= nil then provinces.list[o.province] else nil
				local pname = if p ~= nil then (if lang == "en" then p.nameEn else p.name) else "?"
				popupText.Text = string.format(Strings.get("diplo.offer.demand", lang), nameOf(o.from), escape(pname))
				acceptButton.Text = Strings.get("diplo.cede", lang)
			else
				popupText.Text = string.format(Strings.get("diplo.offer." .. o.kind, lang), nameOf(o.from))
				acceptButton.Text = Strings.get("diplo.accept", lang)
			end
		end
		popupLeft.Text = string.format(
			Strings.get("diplo.offer.left", lang),
			math.ceil(ClientState.diploLeft(cs, o.left, now, ClientState.simRate(cs)) / cs.speed)
		)
		popup.Visible = true
	end

	local function setOpen(open: boolean)
		window.Visible = open and playing()
		if window.Visible then
			drawWindow()
		end
	end
	Session.connect(mainButton.Activated, function()
		setOpen(not window.Visible)
	end)
	Session.connect(closeButton.Activated, function()
		setOpen(false)
	end)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.T then
			setOpen(not window.Visible)
		elseif input.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
			demandTarget = nil
		end
	end)

	local function refresh()
		now = os.clock()
		mainButton.Visible = playing()
		if not playing() then
			window.Visible = false
			demandTarget = nil
		end
		-- Новые предложения сервер присылает заново — старые отметки об ответе больше не нужны.
		local live: { [string]: boolean } = {}
		for _, o in cs.diplo.offers do
			live[offerKey(o)] = true
		end
		for key in answered do
			if not live[key] then
				answered[key] = nil
			end
		end
		if window.Visible then
			drawWindow()
		end
		drawPopup()
	end

	local lastSecond = -1
	local function update(t: number)
		now = t
		local second = math.floor(t)
		if second ~= lastSecond then
			lastSecond = second
			if window.Visible then
				drawWindow()
			end
			drawPopup()
		end
	end

	local function tap(cell: number): boolean
		local target = demandTarget
		if target == nil then
			return false
		end
		demandTarget = nil
		if ClientState.ownerAt(cs, cell) ~= target then
			toast(Strings.get("reject.notTheirs", lang))
			return true
		end
		local province = MapData.getProvince(map, cell)
		if province == 0 then
			toast(Strings.get("reject.province", lang))
			return true
		end
		send("offer", { target = target, offer = "demand", province = province })
		return true
	end

	return { refresh = refresh, update = update, tap = tap }
end

return table.freeze(DiplomacyPanel)
