--!strict
--[[
	MapButtons — §15ц Ц3: справа снизу над мини-картой — подписанные кнопки окон (значок + название + клавиша):
	Дипломатия [T], Технологии [Y], Стабильность [N], Меню [Tab]. Слева от мини-карты — «+» и «−» (зум камеры,
	как колесо мыши). Где стоят — решает aboveBar в Main.client (рамки «MapButtons» и «ZoomButtons»).
	Кнопка окна подсвечена золотом, пока окно открыто; видна, только пока видна прежняя кнопка окна (visible).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

export type Item = {
	icon: string, -- ключ PixelIcons
	name: string, -- ключ Strings
	key: string, -- клавиша
	toggle: () -> (),
	isOpen: () -> boolean,
	visible: (() -> boolean)?,
}

export type MapButtons = {
	frame: Frame, -- столбик кнопок окон
	zoom: Frame, -- «+» и «−»
	height: () -> number, -- высота столбика (условные px)
	update: () -> (), -- подсветка открытых окон и видимость
	setCompact: (compact: boolean) -> (), -- §15ц Ц5в: узкий экран — квадратные значки
	width: () -> number,
}

local MapButtons = {}

function MapButtons.new(gui: ScreenGui, lang: Strings.Lang, items: { Item }, zoomBy: (dir: number) -> ()): MapButtons
	local cfg = Config.Render.MapButtons

	local frame = Instance.new("Frame")
	frame.Name = "MapButtons"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Size = UDim2.fromOffset(cfg.WidthPx, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Parent = gui
	local list = MenuKit.list(frame, cfg.GapPx)
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom

	type Row = { button: TextButton, edge: UIStroke, item: Item, icon: Frame, name: TextLabel, key: TextLabel }
	local rows: { Row } = {}
	for k, item in items do
		local b = Instance.new("TextButton")
		b.Name = "Open" .. item.icon
		b.Text = ""
		b.LayoutOrder = k
		b.Size = UDim2.fromOffset(cfg.WidthPx, cfg.HeightPx)
		b.BackgroundColor3 = Theme.Colors.PanelBg
		b.BackgroundTransparency = 0.05
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.Parent = frame
		MenuKit.corner(b, 6)
		local edge = MenuKit.stroke(b, Theme.Colors.PanelBorder, 2)
		local icon = MenuKit.icon(b, item.icon, 2)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 8, 0.5, 0)
		local name = MenuKit.label(b, Strings.get(item.name, lang), 14, Theme.Colors.Text, true)
		name.AnchorPoint = Vector2.new(0, 0.5)
		name.Position = UDim2.new(0, 32, 0.5, 0)
		local key = MenuKit.label(b, item.key, 12, Theme.Colors.Gold, true)
		key.AnchorPoint = Vector2.new(1, 0.5)
		key.Position = UDim2.new(1, -8, 0.5, 0)
		key.TextXAlignment = Enum.TextXAlignment.Right
		Session.connect(b.Activated, item.toggle)
		table.insert(rows, { button = b, edge = edge, item = item, icon = icon, name = name, key = key })
	end

	-- §15ц Ц5в: узкий экран — квадратные значки без названия и клавиши (палец, а не клавиатура).
	local compact = false
	local function setCompact(c: boolean)
		compact = c
		local w = if c then cfg.CompactPx else cfg.WidthPx
		local h = if c then cfg.CompactPx else cfg.HeightPx
		frame.Size = UDim2.fromOffset(w, 0)
		for _, r in rows do
			r.button.Size = UDim2.fromOffset(w, h)
			r.name.Visible = not c
			r.key.Visible = not c
			r.icon.AnchorPoint = if c then Vector2.new(0.5, 0.5) else Vector2.new(0, 0.5)
			r.icon.Position = if c then UDim2.fromScale(0.5, 0.5) else UDim2.new(0, 8, 0.5, 0)
		end
	end

	local zoom = Instance.new("Frame")
	zoom.Name = "ZoomButtons"
	zoom.BackgroundTransparency = 1
	zoom.AnchorPoint = Vector2.new(1, 1)
	zoom.Size = UDim2.fromOffset(cfg.ZoomPx, 0)
	zoom.AutomaticSize = Enum.AutomaticSize.Y
	zoom.Parent = gui
	MenuKit.list(zoom, cfg.GapPx)
	type ZoomSpec = { text: string, dir: number }
	local specs: { ZoomSpec } = { { text = "+", dir = 1 }, { text = "−", dir = -1 } }
	for k, spec in specs do
		local b = Instance.new("TextButton")
		b.Name = if spec.dir > 0 then "ZoomIn" else "ZoomOut"
		b.LayoutOrder = k
		b.Size = UDim2.fromOffset(cfg.ZoomPx, cfg.ZoomPx)
		b.BackgroundColor3 = Theme.Colors.PanelBg
		b.BackgroundTransparency = 0.05
		b.BorderSizePixel = 0
		b.FontFace = Theme.FontBold
		b.TextSize = 22
		b.TextColor3 = Theme.Colors.Text
		b.Text = spec.text
		b.Parent = zoom
		MenuKit.corner(b, 6)
		MenuKit.stroke(b, Theme.Colors.PanelBorder, 2)
		Session.connect(b.Activated, function()
			zoomBy(spec.dir)
		end)
	end

	local function update()
		for _, r in rows do
			local fn = r.item.visible
			r.button.Visible = fn == nil or fn()
			local open = r.item.isOpen()
			r.edge.Color = if open then Theme.Colors.Gold else Theme.Colors.PanelBorder
		end
	end
	update()

	return {
		frame = frame,
		zoom = zoom,
		height = function(): number
			local n = 0
			for _, r in rows do
				if r.button.Visible then
					n += 1
				end
			end
			local h = if compact then cfg.CompactPx else cfg.HeightPx
			return if n == 0 then 0 else n * h + (n - 1) * cfg.GapPx
		end,
		update = update,
		setCompact = setCompact,
		width = function(): number
			return if compact then cfg.CompactPx else cfg.WidthPx
		end,
	}
end

return table.freeze(MapButtons)
