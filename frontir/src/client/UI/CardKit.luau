--!strict
--[[
	CardKit — окна-витрины из карточек (GDD §15л ч.9), один вид на Магазин, Гардероб, Задания, Технологии, Арсенал:
	- window: окно по центру — заголовок, подпись, плашки (медали, жетоны), «×», вкладки, страницы (сетка или список);
	- card: карточка — картинка предмета (ItemArt, без сглаживания), метка в углу, название, что даёт, цена, кнопки;
	- art: картинка ItemArt в любом месте; button: кнопка в стиле меню; chip: плашка с числом.
	Пиксельные рамки и фаску даёт Theme.decorate (Polish), здесь — только раскладка.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IconArt = require(Shared:WaitForChild("IconArt"))
local ItemArt = require(Shared:WaitForChild("ItemArt"))

local IconImage = require(script.Parent:WaitForChild("IconImage"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

export type Page = ScrollingFrame
-- §15ц Ц4а: низ окна — подсказка слева и одна главная кнопка справа.
export type Footer = {
	hint: TextLabel,
	main: TextButton,
	set: (text: string, enabled: boolean, hint: string?) -> (),
}
export type Window = {
	frame: Frame,
	chips: Frame,
	close: TextButton,
	page: (key: string) -> Page,
	setTab: (key: string) -> (),
	tab: () -> string,
	onTab: (fn: (key: string) -> ()) -> (),
	footer: Footer?, -- есть, если окно создано с footer = true
}
export type Card = {
	frame: Frame,
	art: ImageLabel,
	edge: UIStroke,
	tag: TextLabel,
	title: TextLabel,
	desc: TextLabel,
	price: TextLabel,
	actions: Frame,
	dim: Frame,
}

local CardKit = {}

CardKit.CardW = 184
CardKit.CardH = 280
CardKit.Gap = 10
CardKit.MainW = 300 -- §15ц Ц4а: главная кнопка внизу окна

-- Картинки, которые можно перерисовать (repaint): ImageLabel → EditableImage.
local editables: { [ImageLabel]: EditableImage } = setmetatable({}, { __mode = "k" }) :: any

-- Картинка предмета: EditableImage на сессию.
-- §15ш Ш5: здание, юнит, корабль, самолёт — иконка IconArt (вписана, на тёмном фоне); остальное — сцена ItemArt.
local function paintArt(img: ImageLabel, key: string)
	local icon = IconArt.forKey(key)
	local content = if icon ~= nil then IconImage.content(icon) else nil
	if content ~= nil then
		img.ImageContent = content
		img.ScaleType = Enum.ScaleType.Fit
		return
	end
	img.ScaleType = Enum.ScaleType.Crop
	local editable: EditableImage? = editables[img]
	if editable == nil then
		local ok, image = pcall(function(): EditableImage?
			return AssetService:CreateEditableImage({ Size = Vector2.new(ItemArt.W, ItemArt.H) })
		end)
		if not ok or image == nil then
			return
		end
		editable = Session.track(image :: EditableImage)
		editables[img] = editable :: EditableImage
	end
	local e = editable :: EditableImage
	e:WritePixelsBuffer(Vector2.zero, Vector2.new(ItemArt.W, ItemArt.H), ItemArt.paint(key))
	img.ImageContent = Content.fromObject(e)
end

function CardKit.art(parent: Instance, key: string, w: number, h: number): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = "Art"
	img.Size = UDim2.fromOffset(w, h)
	img.BackgroundColor3 = Theme.Colors.Backdrop
	img.BorderSizePixel = 0
	img.ResampleMode = Enum.ResamplerMode.Pixelated
	img.ScaleType = Enum.ScaleType.Crop
	img.Parent = parent
	paintArt(img, key)
	img:SetAttribute("ArtKey", key)
	MenuKit.stroke(img, Theme.color("Ink"), 2)
	return img
end

-- Перерисовать картинку другим ключом (здание сменилось, держава другая); тот же ключ — ничего не делает.
function CardKit.repaint(img: ImageLabel, key: string)
	if img:GetAttribute("ArtKey") == key then
		return
	end
	img:SetAttribute("ArtKey", key)
	paintArt(img, key)
end

function CardKit.button(parent: Instance, text: string, style: MenuKit.ButtonStyle, order: number?): TextButton
	local b = MenuKit.button(parent, text, style, MenuKit.Touch, order)
	b.TextSize = 14
	b.TextScaled = false
	b.TextTruncate = Enum.TextTruncate.AtEnd
	return b
end

function CardKit.chip(parent: Instance, icon: string, order: number): TextLabel
	local row = MenuKit.box(parent, "Chip", order)
	row.BackgroundTransparency = 0
	row.BackgroundColor3 = Theme.Colors.Backdrop
	row.Size = UDim2.fromOffset(0, 34)
	row.AutomaticSize = Enum.AutomaticSize.X
	MenuKit.pad(row, 8, 0)
	MenuKit.list(row, 6, true)
	MenuKit.stroke(row, Theme.Colors.Gold, 2)
	MenuKit.icon(row, icon, 3, 1)
	local text = MenuKit.label(row, "", 17, Theme.Colors.Gold, true, 2)
	return text
end

-- Окно: tabs — { { key, label } } (пусто — одна страница "main"); kinds — "grid" (по умолчанию) или "list";
-- footer — §15ц Ц4а: низ окна с подсказкой и одной главной кнопкой (win.footer).
function CardKit.window(
	gui: ScreenGui,
	name: string,
	title: string,
	subtitle: string,
	width: number,
	height: number,
	tabs: { { key: string, label: string } },
	kinds: { [string]: string }?,
	footer: boolean?
): Window
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.52)
	frame.Size = UDim2.fromOffset(width, height)
	frame.BackgroundColor3 = Theme.Colors.PanelBg
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Visible = false
	frame.Parent = gui
	MenuKit.stroke(frame, Theme.Colors.PanelBorder, 2)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local function fit()
		-- §15ц Ц5а: по слою, где окно лежит сейчас (Main.client переносит окна из HUD в слой окон; HUD под главным
		-- меню выключен — его размер в этот момент не тот).
		local layer = frame:FindFirstAncestorWhichIsA("ScreenGui") or gui
		local s = UiScale.size(layer)
		if s.X <= 0 or s.Y <= 0 then
			return
		end
		-- Место сверху — под картинку-шапку (SceneBanner).
		scale.Scale = math.clamp(math.min((s.X - 24) / width, (s.Y - 140) / height), 0.4, 1)
	end
	UiScale.onResize(gui, fit)
	-- Пересчёт при каждом открытии: размер слоя мог смениться, пока окно было закрыто или переезжало.
	Session.connect(frame:GetPropertyChangedSignal("Visible"), function()
		if frame.Visible then
			fit()
		end
	end)
	fit()

	local head = Instance.new("Frame")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.Position = UDim2.fromOffset(16, 12)
	head.Size = UDim2.new(1, -32, 0, 52)
	head.Parent = frame
	MenuKit.label(head, title, 26, Theme.Colors.Gold, true)
	local sub = MenuKit.label(head, subtitle, 13, Theme.Colors.Muted)
	sub.Position = UDim2.fromOffset(0, 32)
	local close = MenuKit.button(head, "×", "normal")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(MenuKit.Touch, MenuKit.Touch)
	close.TextSize = 24
	local chips = MenuKit.box(head, "Chips")
	chips.AnchorPoint = Vector2.new(1, 0)
	chips.Position = UDim2.new(1, -(MenuKit.Touch + 12), 0, 4)
	MenuKit.list(chips, 8, true)

	local top = 72
	local tabBar: Frame? = nil
	if #tabs > 0 then
		local bar = MenuKit.box(frame, "Tabs")
		bar.Position = UDim2.fromOffset(16, top)
		MenuKit.list(bar, 8, true)
		tabBar = bar
		top += 52
	end
	-- Низ окна: подсказка и главная кнопка (страницы кончаются над ним).
	local bottom = 0
	local foot: Footer? = nil
	if footer then
		bottom = MenuKit.Touch + 16
		local f = Instance.new("Frame")
		f.Name = "Footer"
		f.BackgroundTransparency = 1
		f.AnchorPoint = Vector2.new(0, 1)
		f.Position = UDim2.new(0, 16, 1, -12)
		f.Size = UDim2.new(1, -32, 0, MenuKit.Touch)
		f.Parent = frame
		local line = Instance.new("Frame")
		line.Name = "Line"
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Theme.Colors.Slate
		line.Position = UDim2.fromOffset(0, -8)
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Parent = f
		local hint = MenuKit.label(f, "", 13, Theme.Colors.Muted)
		hint.AutomaticSize = Enum.AutomaticSize.None
		hint.AnchorPoint = Vector2.new(0, 0.5)
		hint.Position = UDim2.fromScale(0, 0.5)
		hint.Size = UDim2.new(1, -(CardKit.MainW + 16), 1, 0)
		hint.TextWrapped = true
		hint.RichText = true
		local main = CardKit.button(f, "", "primary")
		main.Name = "Main"
		main.AnchorPoint = Vector2.new(1, 0)
		main.Position = UDim2.fromScale(1, 0)
		main.Size = UDim2.fromOffset(CardKit.MainW, MenuKit.Touch)
		main.TextSize = 15
		foot = {
			hint = hint,
			main = main,
			set = function(text: string, enabled: boolean, hintText: string?)
				main.Text = text
				main.Visible = text ~= ""
				main.Active = enabled
				main.AutoButtonColor = enabled
				main.TextTransparency = if enabled then 0 else 0.45
				main.BackgroundTransparency = if enabled then 0 else 0.5
				if hintText ~= nil then
					hint.Text = hintText
				end
			end,
		}
	end
	local pages: { [string]: Page } = {}
	local tabButtons: { [string]: TextButton } = {}
	local current = if #tabs > 0 then tabs[1].key else "main"
	local listeners: { (string) -> () } = {}
	local function makePage(key: string): Page
		local p = Instance.new("ScrollingFrame")
		p.Name = "Page_" .. key
		p.BackgroundTransparency = 1
		p.BorderSizePixel = 0
		p.Position = UDim2.fromOffset(16, top)
		p.Size = UDim2.new(1, -32, 1, -(top + 14 + bottom))
		p.ScrollBarThickness = 8
		p.ScrollBarImageColor3 = Theme.Colors.PanelBorder
		p.ScrollingDirection = Enum.ScrollingDirection.Y
		p.AutomaticCanvasSize = Enum.AutomaticSize.Y
		p.CanvasSize = UDim2.new()
		p.Visible = key == current
		p.Parent = frame
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 4)
		pad.PaddingTop = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = p
		if (kinds or {})[key] == "list" then
			MenuKit.list(p, CardKit.Gap)
		else
			local grid = Instance.new("UIGridLayout")
			grid.CellSize = UDim2.fromOffset(CardKit.CardW, CardKit.CardH)
			grid.CellPadding = UDim2.fromOffset(CardKit.Gap, CardKit.Gap)
			grid.SortOrder = Enum.SortOrder.LayoutOrder
			grid.Parent = p
		end
		pages[key] = p
		return p
	end
	local function setTab(key: string)
		current = key
		for k, p in pages do
			p.Visible = k == key
		end
		for k, b in tabButtons do
			local on = k == key
			b.BackgroundColor3 = Theme.color(if on then "Gold" else "Slate")
			b.TextColor3 = Theme.color(if on then "Ink" else "White")
		end
		for _, fn in listeners do
			fn(key)
		end
	end
	if #tabs == 0 then
		makePage("main")
	end
	for k, t in tabs do
		makePage(t.key)
		local b = MenuKit.button(tabBar :: Frame, t.label, "normal", 40, k)
		b.Size = UDim2.fromOffset(0, 40)
		b.AutomaticSize = Enum.AutomaticSize.X
		b.TextSize = 15
		MenuKit.pad(b, 16, 0)
		tabButtons[t.key] = b
		Session.connect(b.Activated, function()
			setTab(t.key)
		end)
	end
	setTab(current)
	Session.connect(close.Activated, function()
		frame.Visible = false
	end)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.Escape and frame.Visible then
			frame.Visible = false
		end
	end)
	return {
		frame = frame,
		chips = chips,
		close = close,
		page = function(key: string): Page
			return pages[key] or makePage(key)
		end,
		setTab = setTab,
		tab = function(): string
			return current
		end,
		onTab = function(fn: (string) -> ())
			table.insert(listeners, fn)
		end,
		footer = foot,
	}
end

-- Карточка предмета в сетке (CardW×CardH): картинка, метка, название, описание, цена, ряд кнопок.
function CardKit.card(parent: Instance, artKey: string, title: string, desc: string, order: number): Card
	local w = CardKit.CardW
	local f = Instance.new("Frame")
	f.Name = "Card_" .. artKey
	f.LayoutOrder = order
	f.BackgroundColor3 = Theme.Colors.Backdrop
	f.BorderSizePixel = 0
	f.Parent = parent
	local edge = MenuKit.stroke(f, Theme.Colors.PanelBorder, 2)
	local art = CardKit.art(f, artKey, w - 12, math.floor((w - 12) * ItemArt.H / ItemArt.W))
	art.Position = UDim2.fromOffset(6, 6)
	local tag = MenuKit.label(f, "", 11, Theme.color("Ink"), true)
	tag.Position = UDim2.fromOffset(10, 10)
	tag.BackgroundTransparency = 0
	tag.BackgroundColor3 = Theme.Colors.Gold
	tag.ZIndex = 3
	MenuKit.pad(tag, 5, 2)
	tag.Visible = false
	local artH = math.floor((w - 12) * ItemArt.H / ItemArt.W)
	local name = MenuKit.label(f, title, 15, Theme.Colors.Text, true)
	name.Position = UDim2.fromOffset(8, artH + 14)
	name.Size = UDim2.fromOffset(w - 16, 18)
	name.AutomaticSize = Enum.AutomaticSize.None
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local d = MenuKit.label(f, desc, 12, Theme.Colors.Muted)
	d.Position = UDim2.fromOffset(8, artH + 36)
	d.Size = UDim2.fromOffset(w - 16, 46)
	d.AutomaticSize = Enum.AutomaticSize.None
	d.TextWrapped = true
	d.TextYAlignment = Enum.TextYAlignment.Top
	local price = MenuKit.label(f, "", 13, Theme.Colors.Gold, true)
	price.Position = UDim2.fromOffset(8, artH + 86)
	price.Size = UDim2.fromOffset(w - 16, 16)
	price.AutomaticSize = Enum.AutomaticSize.None
	-- §15ц Ц5а: длинная строка цены («только в матче (купленное — в запас)») ужимается по ширине карточки.
	price.TextScaled = true
	local priceFit = Instance.new("UITextSizeConstraint")
	priceFit.MaxTextSize = 13
	priceFit.MinTextSize = 8
	priceFit.Parent = price
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.BackgroundTransparency = 1
	actions.AnchorPoint = Vector2.new(0, 1)
	actions.Position = UDim2.new(0, 8, 1, -8)
	actions.Size = UDim2.new(1, -16, 0, MenuKit.Touch)
	actions.Parent = f
	local list = MenuKit.list(actions, 6, true)
	list.HorizontalFlex = Enum.UIFlexAlignment.Fill
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = Theme.color("Ink")
	dim.BackgroundTransparency = 0.6 -- от 0.6 Polish не оформляет (это затемнение, не окно)
	dim.BorderSizePixel = 0
	dim.Position = UDim2.fromOffset(6, 6)
	dim.Size = art.Size
	dim.ZIndex = 2
	dim.Visible = false
	dim.Parent = f
	return {
		frame = f,
		art = art,
		edge = edge,
		tag = tag,
		title = name,
		desc = d,
		price = price,
		actions = actions,
		dim = dim,
	}
end

-- Широкая строка-карточка для списков (сезон, ящики, задания, технологии): картинка слева, текст справа.
function CardKit.row(
	parent: Instance,
	artKey: string,
	artW: number,
	height: number,
	order: number
): (Frame, Frame, UIStroke)
	local f = Instance.new("Frame")
	f.Name = "Row_" .. artKey
	f.LayoutOrder = order
	f.Size = UDim2.new(1, 0, 0, height)
	f.BackgroundColor3 = Theme.Colors.Backdrop
	f.BorderSizePixel = 0
	f.Parent = parent
	local edge = MenuKit.stroke(f, Theme.Colors.PanelBorder, 2)
	local artH = height - 12
	local aw = math.min(artW, math.floor(artH * ItemArt.W / ItemArt.H))
	local art = CardKit.art(f, artKey, aw, artH)
	art.Position = UDim2.fromOffset(6, 6)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(aw + 18, 8)
	body.Size = UDim2.new(1, -(aw + 26), 1, -16)
	body.Parent = f
	return f, body, edge
end

-- Меню у здания на карте (§15л ч.11): порт, аэродром — шапка с картинкой, плитки найма, кнопка приказа.
export type HireTile = {
	button: TextButton,
	name: TextLabel,
	price: TextLabel,
	badge: TextLabel,
}
export type Dock = {
	frame: Frame,
	art: ImageLabel,
	title: TextLabel,
	status: TextLabel,
	close: TextButton,
	hires: { HireTile },
	action: TextButton,
}

CardKit.DockW = 460

function CardKit.dock(gui: ScreenGui, name: string, artKey: string, hireKeys: { string }, hireLabel: string): Dock
	local width = CardKit.DockW
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -150)
	frame.Size = UDim2.fromOffset(width, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Theme.Colors.PanelBg
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Visible = false
	frame.ZIndex = 15
	frame.Parent = gui
	MenuKit.stroke(frame, Theme.Colors.PanelBorder, 2)
	MenuKit.pad(frame, 10, 10)
	MenuKit.list(frame, 8)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local function fit()
		scale.Scale = math.clamp((UiScale.size(gui).X - 16) / width, 0.5, 1)
	end
	UiScale.onResize(gui, fit)
	fit()

	local head = MenuKit.box(frame, "Head", 1)
	head.AutomaticSize = Enum.AutomaticSize.None
	head.Size = UDim2.new(1, 0, 0, 64)
	local art = CardKit.art(head, artKey, 96, 64)
	local title = MenuKit.label(head, "", 20, Theme.Colors.Gold, true)
	title.Position = UDim2.fromOffset(108, 2)
	local status = MenuKit.label(head, "", 13, Theme.Colors.Muted)
	status.AutomaticSize = Enum.AutomaticSize.None
	status.Position = UDim2.fromOffset(108, 28)
	status.Size = UDim2.new(1, -(108 + MenuKit.Touch + 6), 0, 34)
	status.TextWrapped = true
	status.TextYAlignment = Enum.TextYAlignment.Top
	local close = MenuKit.button(head, "×", "normal")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(MenuKit.Touch, MenuKit.Touch)
	close.TextSize = 24

	local row = MenuKit.box(frame, "Hires", 2)
	row.AutomaticSize = Enum.AutomaticSize.None
	row.Size = UDim2.new(1, 0, 0, 84)
	row.Visible = #hireKeys > 0
	local rowList = MenuKit.list(row, 8, true)
	rowList.HorizontalFlex = Enum.UIFlexAlignment.Fill
	local hires: { HireTile } = {}
	for k, key in hireKeys do
		local b = Instance.new("TextButton")
		b.Name = "Hire_" .. key
		b.LayoutOrder = k
		b.Text = ""
		b.AutoButtonColor = true
		b.BackgroundColor3 = Theme.Colors.Backdrop
		b.BorderSizePixel = 0
		b.Size = UDim2.new(0, 100, 1, 0)
		b.Parent = row
		MenuKit.stroke(b, Theme.Colors.PanelBorder, 2)
		local a = CardKit.art(b, key, 84, 56)
		a.Position = UDim2.fromOffset(6, 6)
		local n = MenuKit.label(b, "", 15, Theme.Colors.Text, true)
		n.Position = UDim2.fromOffset(98, 6)
		local price = MenuKit.label(b, "", 12, Theme.Colors.Gold, true)
		price.AutomaticSize = Enum.AutomaticSize.None
		price.Position = UDim2.fromOffset(98, 26)
		price.Size = UDim2.new(1, -104, 0, 30)
		price.TextWrapped = true
		price.TextYAlignment = Enum.TextYAlignment.Top
		local badge = MenuKit.label(b, "+ " .. hireLabel, 12, Theme.color("Ink"), true)
		badge.AnchorPoint = Vector2.new(1, 1)
		badge.Position = UDim2.new(1, -6, 1, -6)
		badge.BackgroundTransparency = 0
		badge.BackgroundColor3 = Theme.Colors.Gold
		MenuKit.pad(badge, 6, 2)
		table.insert(hires, { button = b, name = n, price = price, badge = badge })
	end

	local action = MenuKit.button(frame, "", "primary", MenuKit.Touch, 3)
	action.Size = UDim2.new(1, 0, 0, MenuKit.Touch)
	action.TextSize = 15
	action.TextScaled = false
	return {
		frame = frame,
		art = art,
		title = title,
		status = status,
		close = close,
		hires = hires,
		action = action,
	}
end

return table.freeze(CardKit)
