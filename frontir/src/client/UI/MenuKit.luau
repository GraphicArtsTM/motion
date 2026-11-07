--!strict
--[[
	MenuKit — детали нового интерфейса (GDD §15л): тёмная карточка с заголовком капсом и надписью справа,
	подписи, крупные кнопки (основная — золотая, обычная — тёмная, опасная — сливовая), полоса прогресса,
	плитка со значком, пиксельный значок (PixelIcons 8×8 или звание Ranks 14×14). Цвета — только палитра (Theme).
	Главное меню, «Звания», меню игры и итоги собраны из этих деталей — один вид везде.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PixelIcons = require(Shared:WaitForChild("PixelIcons"))
local Ranks = require(Shared:WaitForChild("Ranks"))

local Theme = require(script.Parent:WaitForChild("Theme"))

export type Card = { frame: Frame, body: Frame, title: TextLabel, accent: TextLabel }
export type Bar = { frame: Frame, fill: Frame, set: (share: number) -> () }
export type ButtonStyle = "primary" | "normal" | "danger" | "good"

local MenuKit = {}

MenuKit.Touch = Config.Render.MinTouchTargetPx

function MenuKit.corner(g: GuiObject, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = g
end

function MenuKit.stroke(g: GuiObject, color: Color3, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = thickness or 1
	s.Parent = g
	return s
end

function MenuKit.pad(g: GuiObject, x: number, y: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, x)
	p.PaddingRight = UDim.new(0, x)
	p.PaddingTop = UDim.new(0, y)
	p.PaddingBottom = UDim.new(0, y)
	p.Parent = g
end

function MenuKit.list(g: GuiObject, gap: number, horizontal: boolean?, align: Enum.HorizontalAlignment?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap)
	if horizontal then
		l.FillDirection = Enum.FillDirection.Horizontal
		l.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	if align ~= nil then
		l.HorizontalAlignment = align
	end
	l.Parent = g
	return l
end

-- Прозрачная рамка-контейнер (размер по содержимому).
function MenuKit.box(parent: Instance, name: string, order: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(0, 0)
	f.AutomaticSize = Enum.AutomaticSize.XY
	f.LayoutOrder = order or 0
	f.Parent = parent
	return f
end

function MenuKit.label(
	parent: Instance,
	text: string,
	size: number,
	color: Color3?,
	bold: boolean?,
	order: number?
): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromOffset(0, 0)
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.FontFace = if bold then Theme.FontBold else Theme.Font
	t.TextSize = size
	t.TextColor3 = color or Theme.Colors.Text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.RichText = true
	t.Text = text
	t.LayoutOrder = order or 0
	t.Parent = parent
	return t
end

-- Подпись во всю ширину родителя с переносом строк.
function MenuKit.wrapLabel(parent: Instance, text: string, size: number, color: Color3?, order: number?): TextLabel
	local t = MenuKit.label(parent, text, size, color, false, order)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.fromScale(1, 0)
	t.TextWrapped = true
	return t
end

-- Карточка: заголовок капсом слева, надпись-акцент справа, под ними — body (столбик).
function MenuKit.card(parent: Instance, name: string, title: string, width: number, order: number?): Card
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.LayoutOrder = order or 0
	frame.Size = UDim2.fromOffset(width, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Theme.Colors.PanelBg
	frame.BackgroundTransparency = 0.04
	frame.BorderSizePixel = 0
	frame.Parent = parent
	MenuKit.corner(frame, 8)
	MenuKit.stroke(frame, Theme.Colors.PanelBorder)
	MenuKit.pad(frame, 14, 12)
	MenuKit.list(frame, 10)
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 22)
	head.LayoutOrder = 0
	head.Parent = frame
	local titleLabel = MenuKit.label(head, title, 16, Theme.Colors.Text, true)
	titleLabel.AnchorPoint = Vector2.new(0, 0.5)
	titleLabel.Position = UDim2.fromScale(0, 0.5)
	local accent = MenuKit.label(head, "", 12, Theme.Colors.Gold, true)
	accent.AnchorPoint = Vector2.new(1, 0.5)
	accent.Position = UDim2.fromScale(1, 0.5)
	accent.TextXAlignment = Enum.TextXAlignment.Right
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.LayoutOrder = 1
	body.Parent = frame
	MenuKit.list(body, 8)
	return { frame = frame, body = body, title = titleLabel, accent = accent }
end

-- Плашка внутри карточки (строка задания, предложение магазина).
function MenuKit.row(parent: Instance, name: string, order: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.LayoutOrder = order
	f.Size = UDim2.fromScale(1, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundColor3 = Theme.Colors.Backdrop
	f.BackgroundTransparency = 0.3
	f.BorderSizePixel = 0
	f.Parent = parent
	MenuKit.corner(f, 6)
	MenuKit.stroke(f, Theme.Colors.Slate)
	MenuKit.pad(f, 10, 8)
	MenuKit.list(f, 5)
	return f
end

local STYLES: { [string]: { bg: string, text: string, edge: string } } = {
	-- §15л ч.4: рамка у всех кнопок тёмная (пиксельный вид), объём даёт фаска Theme.decorate.
	primary = { bg = "Gold", text = "Ink", edge = "Ink" },
	normal = { bg = "Slate", text = "White", edge = "Ink" },
	danger = { bg = "Plum", text = "White", edge = "Ink" },
	good = { bg = "Forest", text = "White", edge = "Ink" },
}

function MenuKit.button(parent: Instance, text: string, style: ButtonStyle, height: number?, order: number?): TextButton
	local s = STYLES[style]
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.LayoutOrder = order or 0
	b.Size = UDim2.new(1, 0, 0, height or MenuKit.Touch)
	b.BackgroundColor3 = Theme.color(s.bg)
	b.BorderSizePixel = 0
	b.FontFace = Theme.FontBold
	b.TextSize = if (height or 0) >= 56 then 24 else 16
	b.TextColor3 = Theme.color(s.text)
	b.Text = text
	b.Parent = parent
	MenuKit.corner(b, 6)
	MenuKit.stroke(b, Theme.color(s.edge), 2)
	return b
end

-- Полоса прогресса: share 0..1.
function MenuKit.bar(parent: Instance, height: number, color: Color3, order: number?): Bar
	local frame = Instance.new("Frame")
	frame.Name = "Bar"
	frame.LayoutOrder = order or 0
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundColor3 = Theme.Colors.Backdrop
	frame.BorderSizePixel = 0
	frame.Parent = parent
	MenuKit.corner(frame, height // 2)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = frame
	MenuKit.corner(fill, height // 2)
	return {
		frame = frame,
		fill = fill,
		set = function(share: number)
			fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
			fill.Visible = share > 0
		end,
	}
end

-- Пиксельный значок из частей (PixelIcons.Part): side — сторона в клетках, scale — пикселей на клетку.
function MenuKit.pixels(
	parent: Instance,
	parts: { PixelIcons.Part },
	side: number,
	scale: number,
	order: number?
): Frame
	local root = Instance.new("Frame")
	root.Name = "Icon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(side * scale, side * scale)
	root.LayoutOrder = order or 0
	root.Parent = parent
	for _, p in parts do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Theme.color(p.color)
		f.Position = UDim2.fromOffset(p.x * scale, p.y * scale)
		f.Size = UDim2.fromOffset(p.w * scale, p.h * scale)
		f.Parent = root
	end
	return root
end

function MenuKit.icon(parent: Instance, key: string, scale: number, order: number?): Frame
	return MenuKit.pixels(parent, PixelIcons.Icons[key] or {}, PixelIcons.Size, scale, order)
end

-- Значок звания; перерисовать — MenuKit.setRank(frame, rank, scale).
function MenuKit.rankIcon(parent: Instance, rank: number, scale: number, order: number?): Frame
	local f = MenuKit.pixels(parent, Ranks.icon(rank), Ranks.IconSize, scale, order)
	f:SetAttribute("Rank", rank)
	return f
end

function MenuKit.setRank(f: Frame, rank: number, scale: number)
	if f:GetAttribute("Rank") == rank then
		return
	end
	f:SetAttribute("Rank", rank)
	for _, child in f:GetChildren() do
		child:Destroy()
	end
	for _, p in Ranks.icon(rank) do
		local px = Instance.new("Frame")
		px.BorderSizePixel = 0
		px.BackgroundColor3 = Theme.color(p.color)
		px.Position = UDim2.fromOffset(p.x * scale, p.y * scale)
		px.Size = UDim2.fromOffset(p.w * scale, p.h * scale)
		px.Parent = f
	end
end

-- Плитка: квадратная кнопка, значок по центру, подпись снизу капсом.
function MenuKit.tile(parent: Instance, name: string, text: string, size: number, order: number): (TextButton, Frame)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = true
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BackgroundTransparency = 0.04
	b.BorderSizePixel = 0
	b.Parent = parent
	MenuKit.corner(b, 8)
	MenuKit.stroke(b, Theme.Colors.PanelBorder, 2)
	local slot = Instance.new("Frame")
	slot.Name = "IconSlot"
	slot.BackgroundTransparency = 1
	slot.AnchorPoint = Vector2.new(0.5, 0.5)
	slot.Position = UDim2.fromScale(0.5, 0.42)
	slot.Size = UDim2.fromOffset(size // 2, size // 2)
	slot.Parent = b
	local caption = MenuKit.label(b, text, 12, Theme.Colors.Text, true)
	caption.AnchorPoint = Vector2.new(0.5, 1)
	caption.Position = UDim2.new(0.5, 0, 1, -8)
	caption.TextXAlignment = Enum.TextXAlignment.Center
	return b, slot
end

-- Значок в слоте плитки по центру.
function MenuKit.center(icon: Frame)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
end

-- Круглая кнопка со значком (верхняя полоса меню).
function MenuKit.roundButton(parent: Instance, name: string, key: string, order: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = true
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(MenuKit.Touch, MenuKit.Touch)
	b.BackgroundColor3 = Theme.Colors.Slate
	b.BorderSizePixel = 0
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = b
	MenuKit.stroke(b, Theme.Colors.PanelBorder, 2)
	local icon = MenuKit.icon(b, key, 3)
	MenuKit.center(icon)
	return b
end

-- Секунды → «М:СС».
function MenuKit.clock(sec: number): string
	local s = math.max(0, math.floor(sec))
	return string.format("%d:%02d", s // 60, s % 60)
end

return table.freeze(MenuKit)
