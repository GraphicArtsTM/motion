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
local ItemArt = require(Shared:WaitForChild("ItemArt"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

export type Page = ScrollingFrame
export type Window = {
	frame: Frame,
	chips: Frame,
	close: TextButton,
	page: (key: string) -> Page,
	setTab: (key: string) -> (),
	tab: () -> string,
	onTab: (fn: (key: string) -> ()) -> (),
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

-- Картинка предмета: EditableImage на сессию.
function CardKit.art(parent: Instance, key: string, w: number, h: number): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = "Art"
	img.Size = UDim2.fromOffset(w, h)
	img.BackgroundColor3 = Theme.Colors.Backdrop
	img.BorderSizePixel = 0
	img.ResampleMode = Enum.ResamplerMode.Pixelated
	img.ScaleType = Enum.ScaleType.Crop
	img.Parent = parent
	local ok, image = pcall(function(): EditableImage?
		return AssetService:CreateEditableImage({ Size = Vector2.new(ItemArt.W, ItemArt.H) })
	end)
	if ok and image ~= nil then
		local editable = image :: EditableImage
		Session.track(editable)
		editable:WritePixelsBuffer(Vector2.zero, Vector2.new(ItemArt.W, ItemArt.H), ItemArt.paint(key))
		img.ImageContent = Content.fromObject(editable)
	end
	MenuKit.stroke(img, Theme.color("Ink"), 2)
	return img
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

-- Окно: tabs — { { key, label } } (пусто — одна страница "main"); kinds — "grid" (по умолчанию) или "list".
function CardKit.window(
	gui: ScreenGui,
	name: string,
	title: string,
	subtitle: string,
	width: number,
	height: number,
	tabs: { { key: string, label: string } },
	kinds: { [string]: string }?
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
		local s = gui.AbsoluteSize
		-- Место сверху — под картинку-шапку (SceneBanner).
		scale.Scale = math.clamp(math.min((s.X - 24) / width, (s.Y - 140) / height), 0.4, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
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
		p.Size = UDim2.new(1, -32, 1, -(top + 14))
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

return table.freeze(CardKit)
