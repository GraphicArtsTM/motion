--!strict
--[[
	DiplomacyPanel — окно дипломатии и входящие предложения (GDD §8.1, этап 6а).
	- Кнопка «Дипломатия (T)» и клавиша T открывают окно: державы по суше — цвет, имя, отношение с вами
	  (мир, война, пакт с остатком срока, союз, вассал, сюзерен, разрыв), метка «Предатель», сила примерно.
	- Выбрали державу — действия: пакт 3 / 5 мин, союз, разорвать, требование (потом нажать её провинцию на карте),
	  объявить войну (окно WarPanel), независимость (если вы вассал). Внизу — история договоров матча.
	- Входящее предложение или требование — окно с таймером: принять / отказать (у требования — «Отдать»).
	Все решения — на сервере; клиент шлёт намерения offer / offerReply / breakTreaty / rebel / distrust.
	§15у: союз — «частичное доверие»; «Полное доверие» (предложение союзнику) и «Снять доверие».
	§15л ч.10: витрина CardKit — державы карточками, выбранная — портрет её цветом и кнопки по группам.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local DiploMain = require(Shared:WaitForChild("DiploMain"))
local MapData = require(Shared:WaitForChild("MapData"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local OfferQueue = require(Shared:WaitForChild("OfferQueue"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type DiplomacyPanel = {
	button: TextButton, -- §15ф: прежняя кнопка «Дипломатия (T)» — в док
	refresh: () -> (),
	update: (now: number) -> (),
	tap: (cell: number) -> boolean, -- режим требования забирает нажатие на карту
	-- Самопроверка (сводная правка, часть 1): открыть/закрыть окно и узнать, открыто ли.
	toggle: () -> (),
	isOpen: () -> boolean,
	-- §15й Й7: из окна державы — открыть дипломатию на этой державе / потребовать у неё провинцию (нажатие на карту).
	openFor: (target: number) -> (),
	demand: (target: number) -> (),
}

local DiplomacyPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx

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
		if UiScale.size(gui).X < Config.Render.NarrowScreenPx then
			mainButton.AnchorPoint = Vector2.new(1, 1)
			mainButton.Position = UDim2.new(1, -20 - Config.Render.MinimapSide - 208, 1, -12 - 2 * 56 - 12)
		else
			mainButton.AnchorPoint = Vector2.new(1, 1)
			mainButton.Position = UDim2.new(0.5, -108, 1, -12 - 56 - 6)
		end
	end
	UiScale.onResize(gui, placeMain)
	placeMain()

	-- Окно.
	-- §15л ч.10: витрина CardKit — слева державы карточками (цвет, имя, отношение, сила), справа выбранная:
	-- «портрет» её цветом (ItemArt nation.<цвет>), генерал, кнопки по группам «Договоры», «Помощь», «Война».
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local win = CardKit.window(
		gui,
		"Diplomacy",
		t("diplo.titleBig"),
		t("diplo.subtitle"),
		960,
		720,
		{},
		{ main = "list" },
		true
	)
	-- §15ц Ц4б: главная кнопка — самое полезное с выбранной державой (DiploMain).
	local foot = win.footer :: CardKit.Footer
	local mainAction: DiploMain.Action = "pick"
	local window = win.frame
	window.ZIndex = 5
	local closeButton = win.close
	local page = win.page("main")
	-- §15я: сводка сверху — сколько союзников, пактов, войн и торговых соглашений (цветные плашки).
	local summaryRow = Instance.new("Frame")
	summaryRow.Name = "Summary"
	summaryRow.BackgroundTransparency = 1
	summaryRow.LayoutOrder = -1
	summaryRow.Size = UDim2.new(1, 0, 0, 48)
	summaryRow.Parent = page
	local summaryLayout = MenuKit.list(summaryRow, 8, true)
	summaryLayout.HorizontalFlex = Enum.UIFlexAlignment.Fill
	local function summaryChip(order: number, color: string, caption: string): TextLabel
		local f = Instance.new("Frame")
		f.Name = "Chip"
		f.LayoutOrder = order
		f.Size = UDim2.new(0, 100, 1, 0)
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.Parent = summaryRow
		MenuKit.corner(f, 8)
		MenuKit.stroke(f, Theme.color(color), 2)
		local value = MenuKit.label(f, "0", 22, Theme.color(color), true)
		value.FontFace = Theme.FontHeavy
		value.AnchorPoint = Vector2.new(0, 0.5)
		value.Position = UDim2.new(0, 12, 0.5, 0)
		local cap = MenuKit.label(f, caption, 12, Theme.Colors.Muted, true)
		cap.AnchorPoint = Vector2.new(0, 0.5)
		cap.Position = UDim2.new(0, 48, 0.5, 0)
		return value
	end
	local alliesChip = summaryChip(1, "Gold", t("diplo.sum.allies"))
	local pactsChip = summaryChip(2, "Sky", t("diplo.sum.pacts"))
	local warsChip = summaryChip(3, "Red", t("diplo.sum.wars"))
	local tradeChip = summaryChip(4, "Meadow", t("diplo.sum.trade"))
	local cols = Instance.new("Frame")
	cols.BackgroundTransparency = 1
	cols.Size = UDim2.new(1, 0, 0, 500) -- §15ц Ц4б: ниже — главная кнопка
	cols.Parent = page
	-- §15ё Ё2: на телефоне столбцы — во всю высоту страницы (без двойной прокрутки страницы и списка).
	win.onFit(function()
		local h = if win.isPhone() then math.max(200, win.pageHeight() - 64) else 500
		cols.Size = UDim2.new(1, 0, 0, h)
	end)
	local list = Instance.new("ScrollingFrame")
	list.Name = "Nations"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.new(0.4, -8, 1, 0)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Theme.Colors.PanelBorder
	list.Parent = cols
	MenuKit.list(list, 6)
	MenuKit.pad(list, 2, 2)
	-- §15ц Ц4б: под окном — главная кнопка, карточка ниже; действия держав прокручиваются.
	local detail = Instance.new("ScrollingFrame")
	detail.Name = "Detail"
	detail.CanvasSize = UDim2.new()
	detail.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detail.ScrollingDirection = Enum.ScrollingDirection.Y
	detail.ScrollBarThickness = 6
	detail.ScrollBarImageColor3 = Theme.Colors.PanelBorder
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.fromScale(1, 0)
	detail.Size = UDim2.new(0.6, -8, 1, 0)
	detail.BackgroundColor3 = Theme.Colors.Backdrop
	detail.BorderSizePixel = 0
	detail.Parent = cols
	MenuKit.stroke(detail, Theme.Colors.PanelBorder, 2)
	local detailPad = Instance.new("UIPadding")
	detailPad.PaddingBottom = UDim.new(0, 12)
	detailPad.Parent = detail
	local portraitHost = Instance.new("Frame")
	portraitHost.BackgroundTransparency = 1
	portraitHost.Position = UDim2.fromOffset(12, 12)
	portraitHost.Size = UDim2.fromOffset(210, 140)
	portraitHost.Parent = detail
	local portrait: ImageLabel? = nil
	local portraitColor = -1
	local info = MenuKit.box(detail, "Info")
	info.Position = UDim2.fromOffset(234, 12)
	info.AutomaticSize = Enum.AutomaticSize.Y
	info.Size = UDim2.new(1, -246, 0, 0)
	MenuKit.list(info, 4)
	local selName = MenuKit.label(info, "", 22, Theme.Colors.Gold, true, 1)
	selName.RichText = true
	local selectedText = MenuKit.wrapLabel(info, "", 14, Theme.Colors.Text, 2)
	local selPower = MenuKit.label(info, "", 13, Theme.Colors.Muted, false, 3)
	local actionsBox = MenuKit.box(detail, "Actions")
	actionsBox.Position = UDim2.fromOffset(12, 164)
	actionsBox.Size = UDim2.new(1, -24, 0, 0)
	actionsBox.AutomaticSize = Enum.AutomaticSize.Y
	MenuKit.list(actionsBox, 6)
	local function group(key: string, order: number): Frame
		MenuKit.label(actionsBox, t(key), 12, Theme.Colors.Sky, true, order)
		local g = MenuKit.box(actionsBox, "Group", order + 1)
		g.Size = UDim2.fromScale(1, 0)
		g.AutomaticSize = Enum.AutomaticSize.Y
		local l = MenuKit.list(g, 6, true)
		l.Wraps = true
		return g
	end
	local treaties = group("diplo.groupTreaty", 1)
	local helpGroup = group("diplo.groupHelp", 3)
	local warGroup = group("diplo.groupWar", 5)
	MenuKit.wrapLabel(actionsBox, t("diplo.act.hint") .. "\n" .. t("diplo.taxHint"), 11, Theme.Colors.Muted, 8)
	local historyText = MenuKit.wrapLabel(actionsBox, "", 12, Theme.Colors.Text, 9)

	local selected: number? = nil
	local demandTarget: number? = nil
	local drawWindow: () -> ()

	local function act(key: string, handler: () -> (), parent: Frame, style: MenuKit.ButtonStyle?): TextButton
		local b = CardKit.button(parent, t("diplo.act." .. key), style or "normal")
		b.Size = UDim2.fromOffset(172, MenuKit.Touch)
		b.TextSize = 13
		b.RichText = true
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
	end, treaties, "good")
	local pact5Button = act("pact5", function()
		offer("pact5")
	end, treaties, "good")
	local allianceButton = act("alliance", function()
		offer("alliance")
	end, treaties, "primary")
	-- §15у: второй уровень союза — полное доверие (удар через союзника) и снять его.
	local trustButton = act("trust", function()
		offer("trust")
	end, treaties, "primary")
	local distrustButton = act("distrust", function()
		if selected ~= nil and playing() then
			send("distrust", { target = selected })
		end
	end, treaties)
	local tradeButton = act("trade", function()
		offer("trade")
	end, treaties)
	local embargoButton = act("embargo", function()
		local me = cs.myNation
		if selected ~= nil and me ~= nil and playing() then
			send("embargo", { target = selected, on = not ClientState.embargoBy(cs, me, selected) })
		end
	end, treaties)
	local breakButton = act("break", function()
		if selected ~= nil and playing() then
			send("breakTreaty", { target = selected })
		end
	end, treaties, "danger")
	-- Быстрые переводы (§8.2): налог и лимит проверяет сервер.
	local quick = Config.Trade.QuickAmounts
	local function give(money: number, oil: number, people: number)
		if selected ~= nil and playing() then
			send("transfer", { target = selected, money = money, oil = oil, people = people })
		end
	end
	local moneyButton = act("giveMoney", function()
		give(quick.money, 0, 0)
	end, helpGroup)
	moneyButton.Text = string.format(t("diplo.act.giveMoney"), Strings.formatInt(quick.money))
	local oilButton = act("giveOil", function()
		give(0, quick.oil, 0)
	end, helpGroup)
	oilButton.Text = string.format(t("diplo.act.giveOil"), Strings.formatInt(quick.oil))
	local peopleButton = act("givePeople", function()
		give(0, 0, quick.people)
	end, helpGroup)
	peopleButton.Text = string.format(t("diplo.act.givePeople"), Strings.formatInt(quick.people))
	local demandButton = act("demand", function()
		if selected ~= nil and playing() then
			demandTarget = selected
			window.Visible = false
			toast(string.format(t("diplo.demandHint"), nameOf(selected)))
		end
	end, warGroup)
	-- Разведка (§6.11а): мощь цели видна Intel.DurationSec; цена и проверки — на сервере.
	local intelButton = act("intel", function()
		if selected ~= nil and playing() then
			-- §15э Э1б: разведка в блоке — замок и причина вместо отказа сервера.
			local open, level = ClientState.unitOpen(cs, "Intel")
			if not open then
				toast(string.format(t("diplo.intelLocked"), level or Config.Unlocks.Items.Intel.level))
				return
			end
			local wait = ClientState.intelLeft(cs, os.clock()) / math.max(cs.speed, 1e-6) -- секунды матча
			if wait > 0 then
				toast(string.format(t("diplo.intelWait"), math.ceil(wait)))
				return
			end
			send("intel", { target = selected })
		end
	end, warGroup)
	intelButton.Text =
		string.format(t("diplo.act.intel"), Strings.formatInt(Config.Intel.Cost), Config.Intel.DurationSec)
	local warButton = act("war", function()
		if selected ~= nil and playing() then
			window.Visible = false
			declareWar(selected)
		end
	end, warGroup, "danger")
	local rebelButton = act("rebel", function()
		if playing() then
			send("rebel", {})
		end
	end, warGroup, "primary")

	Session.connect(foot.main.Activated, function()
		if not foot.main.Active then
			return
		end
		if mainAction == "alliance" then
			offer("alliance")
		elseif mainAction == "trust" then
			offer("trust")
		end
	end)

	-- Карточки держав в списке (по одной на державу, переиспользуются).
	type NationRow = {
		button: TextButton,
		edge: UIStroke,
		accent: Frame,
		swatch: Frame,
		name: TextLabel,
		rel: TextLabel,
		power: TextLabel,
	}
	local rows: { [number]: NationRow } = {}
	local function rowFor(id: number): NationRow
		local existing = rows[id]
		if existing ~= nil then
			return existing
		end
		local nb = Instance.new("TextButton")
		nb.Text = ""
		nb.Size = UDim2.new(1, -10, 0, 58)
		nb.BackgroundColor3 = Theme.Colors.Backdrop
		nb.BorderSizePixel = 0
		nb.AutoButtonColor = true
		nb.Parent = list
		local edge = MenuKit.stroke(nb, Theme.Colors.PanelBorder, 2)
		-- §15я: слева полоска цвета отношения (война — красная, союз — золотая, пакт — голубая, мир — серая).
		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.BorderSizePixel = 0
		accent.Size = UDim2.new(0, 5, 1, 0)
		accent.BackgroundColor3 = Theme.Colors.Slate
		accent.Parent = nb
		local swatch = Instance.new("Frame")
		swatch.Position = UDim2.fromOffset(10, 11)
		swatch.Size = UDim2.fromOffset(36, 36)
		swatch.BorderSizePixel = 0
		swatch.Parent = nb
		MenuKit.stroke(swatch, Theme.color("Ink"), 2)
		local name = MenuKit.label(nb, "", 15, Theme.Colors.Text, true)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.Position = UDim2.fromOffset(56, 8)
		name.Size = UDim2.new(1, -150, 0, 18)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local rel = MenuKit.label(nb, "", 12, Theme.Colors.Text)
		rel.AutomaticSize = Enum.AutomaticSize.None
		rel.Position = UDim2.fromOffset(56, 30)
		rel.Size = UDim2.new(1, -64, 0, 18)
		rel.TextTruncate = Enum.TextTruncate.AtEnd
		local power = MenuKit.label(nb, "", 12, Theme.Colors.Muted, true)
		power.AutomaticSize = Enum.AutomaticSize.None
		power.AnchorPoint = Vector2.new(1, 0)
		power.Position = UDim2.new(1, -10, 0, 9)
		power.Size = UDim2.fromOffset(84, 16)
		power.TextXAlignment = Enum.TextXAlignment.Right
		local row: NationRow =
			{ button = nb, edge = edge, accent = accent, swatch = swatch, name = name, rel = rel, power = power }
		Session.connect(nb.Activated, function()
			selected = id
			drawWindow()
		end)
		rows[id] = row
		return row
	end

	-- §15я: вид отношения державы id к нам — для цвета полоски и сводки.
	local function relationKind(id: number): string
		local me = cs.myNation
		if me == nil or id == me then
			return "me"
		end
		if ClientState.warBetween(cs, me, id) ~= nil then
			return "war"
		end
		if ClientState.overlordOf(cs, id) == me or ClientState.overlordOf(cs, me) == id then
			return "ally"
		end
		local tr = ClientState.treatyBetween(cs, me, id)
		if tr ~= nil then
			return if tr.kind == "alliance" then "ally" else "pact"
		end
		return "peace"
	end
	local KIND_COLOR: { [string]: string } =
		{ war = "Red", ally = "Gold", pact = "Sky", peace = "Slate", me = "Meadow" }

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
				then Strings.get(if t.trust then "diplo.rel.trust" else "diplo.rel.alliance", lang)
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
	-- §15у ч.2: союзы державы id с другими (не с нами) — «союз с X» / «полное доверие с X»: все знают, кто с кем.
	local function allianceTags(id: number): string
		local me = cs.myNation
		local out = ""
		for _, tr in cs.diplo.treaties do
			if tr.kind == "alliance" and (tr.a == id or tr.b == id) then
				local other = if tr.a == id then tr.b else tr.a
				if other ~= me then
					out ..= string.format(
						' <font color="%s">· %s</font>',
						sky,
						string.format(
							Strings.get(if tr.trust then "diplo.tag.trust" else "diplo.tag.alliance", lang),
							nameOf(other)
						)
					)
				end
			end
		end
		return out
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

	drawWindow = function()
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
			local r = rowFor(id)
			r.button.LayoutOrder = k
			r.button.Visible = true
			local n = cs.nations[id]
			local c = if n.colorIndex >= 1 then NationColors.Colors[n.colorIndex] else nil
			r.swatch.BackgroundColor3 = if c ~= nil then Color3.fromRGB(c.r, c.g, c.b) else Theme.Colors.Gold
			r.edge.Color = if id == selected then Theme.Colors.Gold else Theme.Colors.PanelBorder
			r.accent.BackgroundColor3 = Theme.color(KIND_COLOR[relationKind(id)])
			local traitor = if ClientState.isTraitor(cs, id, now, ClientState.simRate(cs))
				then string.format(' <font color="%s">⚠</font>', alert)
				else ""
			r.name.Text = nameOf(id) .. traitor -- nameOf уже RichText с экранированным именем
			if id == me then
				r.rel.Text = string.format('<font color="%s">%s</font>', gold, t("diplo.you"))
				r.power.Text = ""
			else
				r.rel.Text = relation(id) .. tradeTags(id) .. allianceTags(id)
				r.power.Text = string.format(t("diplo.power"), if powerOf(id) < 0 then "?" else approx(powerOf(id)))
			end
		end
		for id, r in rows do
			if not shown[id] then
				r.button.Visible = false
			end
		end
		-- Сводка сверху.
		local allies, pacts, wars, trades = 0, 0, 0, 0
		for _, entry in order do
			local kind = relationKind(entry.id)
			if kind == "ally" then
				allies += 1
			elseif kind == "pact" then
				pacts += 1
			elseif kind == "war" then
				wars += 1
			end
			if me ~= nil and entry.id ~= me and ClientState.hasTrade(cs, me, entry.id) then
				trades += 1
			end
		end
		alliesChip.Text = tostring(allies)
		pactsChip.Text = tostring(pacts)
		warsChip.Text = tostring(wars)
		tradeChip.Text = tostring(trades)
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
		-- Портрет выбранной державы её цветом (картинка пересоздаётся, когда сменился цвет).
		local ci = if valid and target ~= nil then cs.nations[target].colorIndex else 0
		if ci ~= portraitColor then
			portraitColor = ci
			local old = portrait
			if old ~= nil then
				old:Destroy()
				portrait = nil
			end
			if ci >= 1 then
				local art = CardKit.art(portraitHost, "nation." .. ci, 210, 140)
				portrait = art
			end
		end
		selName.Text = if valid and target ~= nil then nameOf(target) else ""
		selectedText.Text = if valid and target ~= nil
			then relation(target) .. tradeTags(target) .. allianceTags(target) .. commanderOf(target)
			else string.format('<font color="%s">%s</font>', muted, Strings.get("diplo.pick", lang))
		selPower.Text = if valid and target ~= nil
			then string.format(
				Strings.get("diplo.power", lang),
				if powerOf(target) < 0 then "?" else approx(powerOf(target))
			)
			else ""
		actionsBox.Visible = valid or (me ~= nil and ClientState.overlordOf(cs, me) ~= nil)
		for _, b in { pact3Button, pact5Button, allianceButton, demandButton, warButton, tradeButton } do
			b.Visible = valid
		end
		for _, b in { embargoButton, moneyButton, oilButton, peopleButton } do
			b.Visible = valid
		end
		-- Разведывать есть смысл, только пока мощь скрыта.
		intelButton.Visible = valid and target ~= nil and powerOf(target) < 0
		local intelOpen, intelLevel = ClientState.unitOpen(cs, "Intel") -- §15э Э1б
		local intelWait = ClientState.intelLeft(cs, os.clock()) / math.max(cs.speed, 1e-6)
		intelButton.Text = if intelOpen and intelWait > 0
			then string.format(Strings.get("diplo.act.intelWait", lang), math.ceil(intelWait))
			elseif intelOpen then string.format(
				Strings.get("diplo.act.intel", lang),
				Strings.formatInt(Config.Intel.Cost),
				Config.Intel.DurationSec
			)
			else string.format(
				Strings.get("diplo.act.intelLocked", lang),
				intelLevel or Config.Unlocks.Items.Intel.level
			)
		if valid and me ~= nil and target ~= nil then
			embargoButton.Text = Strings.get(
				if ClientState.embargoBy(cs, me, target) then "diplo.act.unembargo" else "diplo.act.embargo",
				lang
			)
		end
		breakButton.Visible = valid and t ~= nil
		-- §15у: «Полное доверие» — союзнику без доверия (до TrustAfterSec — с отсчётом), «Снять доверие» — с ним.
		local allied = valid and t ~= nil and t.kind == "alliance" and t.breakLeft == nil
		trustButton.Visible = allied and t ~= nil and not t.trust
		distrustButton.Visible = allied and t ~= nil and t.trust == true
		if trustButton.Visible and t ~= nil then
			local age = (t.age or 0) + (now - cs.diploAt) * ClientState.simRate(cs)
			local wait = (Config.Alliance.TrustAfterSec - age) / cs.speed
			trustButton.Text = Strings.get("diplo.act.trust", lang)
				.. if wait > 0 then string.format(" %s", clock(wait)) else ""
		end
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
		-- §15ц Ц4б: главная кнопка внизу окна.
		local trustWait = 0
		if t ~= nil and t.kind == "alliance" then
			local age = (t.age or 0) + (now - cs.diploAt) * ClientState.simRate(cs)
			trustWait = (Config.Alliance.TrustAfterSec - age) / cs.speed
		end
		local pick = DiploMain.pick({
			valid = valid,
			atWar = valid and me ~= nil and target ~= nil and ClientState.warBetween(cs, me, target) ~= nil,
			treaty = if t ~= nil then t.kind else nil,
			breaking = t ~= nil and t.breakLeft ~= nil,
			trust = t ~= nil and t.trust == true,
			trustWait = trustWait,
		})
		mainAction = pick.action
		if pick.action == "pick" then
			foot.set(Strings.get("diplo.main.pick", lang), false, Strings.get("diplo.main.pickHint", lang))
		elseif pick.action == "war" then
			foot.set("", false, Strings.get("diplo.main.war", lang))
		elseif pick.action == "alliance" then
			foot.set(Strings.get("diplo.act.alliance", lang), true, Strings.get("diplo.main.allianceHint", lang))
		elseif pick.action == "trust" then
			local text = Strings.get("diplo.act.trust", lang)
				.. if trustWait > 0 then string.format(" %s", clock(trustWait)) else ""
			foot.set(text, pick.enabled, Strings.get("diplo.main.trustHint", lang))
		else
			foot.set("", false, "")
		end
		-- История договоров (последние сверху).
		local lines = { string.format('<font color="%s"><b>%s</b></font>', muted, Strings.get("diplo.history", lang)) }
		local history = cs.diplo.history
		for k = #history, math.max(1, #history - 5), -1 do
			table.insert(lines, historyLine(history[k]))
		end
		historyText.Text = table.concat(lines, "\n")
	end

	-- Входящее предложение или требование. §15й Й6: справа в столбике (Main ставит рамку в TopRight), по одному —
	-- самое срочное, «ещё N», полоса таймера (OfferQueue).
	local popup = frame(gui, "DiplomacyOffer")
	popup.Size = UDim2.fromOffset(Config.Render.Offers.WidthPx, 0)
	popup.AutomaticSize = Enum.AutomaticSize.Y
	popup.ZIndex = 1 -- как соседи по столбику: с ZIndex выше содержимое (z1) рисовалось бы под фоном (ZIndex Global)
	local popupPop = Instance.new("UIScale")
	popupPop.Parent = popup
	-- §15ъ: одной строкой — текст слева (кто, что, сколько осталось, «ещё N»), справа ✓ / ✗ / 🚫 («Всегда нет»:
	-- такие предложения этого вида дальше отклоняет сервер сам; сброс — в настройках), под строкой — полоса таймера.
	local offerLine = Instance.new("Frame")
	offerLine.BackgroundTransparency = 1
	offerLine.Size = UDim2.fromScale(1, 0)
	offerLine.AutomaticSize = Enum.AutomaticSize.Y
	offerLine.LayoutOrder = 1
	offerLine.Parent = popup
	local OFFER_BUTTONS = 3 * BUTTON + 2 * 6
	local textCol = Instance.new("Frame")
	textCol.BackgroundTransparency = 1
	textCol.Size = UDim2.new(1, -(OFFER_BUTTONS + 8), 0, 0)
	textCol.AutomaticSize = Enum.AutomaticSize.Y
	textCol.Parent = offerLine
	local textList = Instance.new("UIListLayout")
	textList.SortOrder = Enum.SortOrder.LayoutOrder
	textList.Parent = textCol
	local popupText = label(textCol, 14, 1)
	local popupLeft = label(textCol, 12, 2)
	popupLeft.TextColor3 = Theme.Colors.Muted
	local popupRow = Instance.new("Frame")
	popupRow.BackgroundTransparency = 1
	popupRow.AnchorPoint = Vector2.new(1, 0)
	popupRow.Position = UDim2.fromScale(1, 0)
	popupRow.Size = UDim2.fromOffset(OFFER_BUTTONS, BUTTON)
	popupRow.Parent = offerLine
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.Padding = UDim.new(0, 6)
	rowList.Parent = popupRow
	local acceptButton = button(popupRow, "✓", BUTTON)
	acceptButton.TextColor3 = Theme.Colors.Good
	acceptButton.TextSize = 20
	local refuseButton = button(popupRow, "✗", BUTTON)
	refuseButton.TextColor3 = Theme.Colors.Alert
	refuseButton.TextSize = 20
	local neverButton = button(popupRow, "🚫", BUTTON)
	neverButton.TextColor3 = Theme.Colors.Muted
	neverButton.TextSize = 18
	local timerHost = Instance.new("Frame")
	timerHost.BackgroundTransparency = 1
	timerHost.Size = UDim2.new(1, 0, 0, 4)
	timerHost.LayoutOrder = 2
	timerHost.Parent = popup
	local timerBar = MenuKit.bar(timerHost, 4, Theme.Colors.Gold)
	local popupKey: string? = nil
	local answered: { [string]: boolean } = {} -- уже ответили (ждём, пока сервер уберёт предложение)
	local totals: { [string]: number } = {} -- сколько было времени, когда предложение пришло (полоса таймера)

	local function leftOf(o: OfferQueue.Offer): number
		return ClientState.diploLeft(cs, o.left, now, ClientState.simRate(cs))
	end
	local function pendingOffers(): { ClientState.DiploOffer }
		return OfferQueue.pending(cs.diplo.offers :: any, cs.myNation, answered, leftOf :: any) :: any
	end
	local function currentOffer(): ClientState.DiploOffer?
		return pendingOffers()[1]
	end
	local function reply(accept: boolean)
		local o = currentOffer()
		if o ~= nil then
			answered[OfferQueue.key(o :: any)] = true
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
	Session.connect(neverButton.Activated, function()
		local o = currentOffer()
		if o ~= nil and table.find(Config.Hud.AutoNoKinds, o.kind) ~= nil then
			send("prefs", { autoNo = o.kind, on = true })
			toast(Strings.get("offer.neverSet", lang))
		end
		reply(false)
	end)

	local function drawPopup()
		local list = if playing() then pendingOffers() else {}
		local o = list[1]
		if o == nil then
			popup.Visible = false
			popupKey = nil
			return
		end
		local key = OfferQueue.key(o :: any)
		local left = leftOf(o :: any)
		if totals[key] == nil then
			totals[key] = left
		end
		if popupKey ~= key then
			popupKey = key
			popupPop.Scale = 0.85
			TweenService:Create(popupPop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
			if o.kind == "demand" then
				local p = if o.province ~= nil then provinces.list[o.province] else nil
				local pname = if p ~= nil then (if lang == "en" then p.nameEn else p.name) else "?"
				popupText.Text = string.format(Strings.get("diplo.offer.demand", lang), nameOf(o.from), escape(pname))
			else
				popupText.Text = string.format(Strings.get("diplo.offer." .. o.kind, lang), nameOf(o.from))
			end
		end
		local secLeft = left / math.max(cs.speed, 1e-3)
		popupLeft.Text = string.format(Strings.get("diplo.offer.left", lang), math.ceil(secLeft))
			.. if #list > 1 then " · " .. string.format(Strings.get("diplo.offer.more", lang), #list - 1) else ""
		timerBar.set(OfferQueue.share(left, totals[key]))
		timerBar.fill.BackgroundColor3 = if secLeft <= Config.Render.Offers.UrgentSec
			then Theme.Colors.Alert
			else Theme.Colors.Gold
		neverButton.Visible = table.find(Config.Hud.AutoNoKinds, o.kind) ~= nil -- требование — нельзя (отказ — война)
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
		-- §15ш Ш3: только в матче (как Y и N) — в меню окно больше не открывается невидимым; закрыть — всегда.
		if input.KeyCode == Enum.KeyCode.T and (window.Visible or playing()) then
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
			live[OfferQueue.key(o :: any)] = true
		end
		for key in answered do
			if not live[key] then
				answered[key] = nil
			end
		end
		for key in totals do
			if not live[key] then
				totals[key] = nil
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

	return {
		button = mainButton, -- §15ф: прежняя кнопка — в док (Dock прячет её и читает видимость)
		refresh = refresh,
		update = update,
		tap = tap,
		toggle = function()
			setOpen(not window.Visible)
		end,
		isOpen = function(): boolean
			return window.Visible
		end,
		openFor = function(target: number)
			selected = target
			setOpen(true)
		end,
		demand = function(target: number)
			if playing() then
				demandTarget = target
				window.Visible = false
				toast(string.format(t("diplo.demandHint"), nameOf(target)))
			end
		end,
	}
end

return table.freeze(DiplomacyPanel)
