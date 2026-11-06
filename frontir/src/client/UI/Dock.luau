--!strict
--[[
	Dock — док окон (GDD §15з; с §15л ч.2 — вертикальной полосой слева под «≡»): все окна открываются отсюда.
	Квадратные кнопки со значком (Shared.PixelIcons) и клавишей в уголке; открытое окно — золотая рамка; при
	наведении над доком — подсказка: название и состояние (текст прежней кнопки окна, например «Технологии —
	исследуется: Авиация, 30 с»). Прежние разбросанные кнопки окон переезжают в скрытую папку: их логика (когда
	видны, что написано) работает как раньше, док только читает её.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PixelIcons = require(Shared:WaitForChild("PixelIcons"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

export type Item = {
	icon: string, -- PixelIcons.Icons
	name: string, -- ключ Strings
	key: string?, -- клавиша (подпись в уголке)
	button: GuiButton?, -- прежняя кнопка окна: видимость и состояние берём у неё
	visible: (() -> boolean)?, -- если прежней кнопки нет
	toggle: () -> (),
	isOpen: (() -> boolean)?,
}

export type Dock = {
	update: (now: number) -> (),
	frame: Frame,
}

local Dock = {}

function Dock.new(gui: ScreenGui, lang: Strings.Lang, items: { Item }): Dock
	local cfg = Config.Render.Dock
	-- Прежние кнопки — в скрытую папку (их код по-прежнему ставит Visible и Text).
	local holder = Instance.new("Folder")
	holder.Name = "DockHidden"
	local hidden = Instance.new("ScreenGui")
	hidden.Name = "FrontirDockHidden"
	hidden.Enabled = false
	hidden.ResetOnSpawn = false
	Session.track(hidden)
	hidden.Parent = gui.Parent
	holder.Parent = hidden

	local frame = Instance.new("Frame")
	frame.Name = "Dock"
	-- §15л ч.2: слева под кнопкой «≡» (снизу теперь командная полоса матча).
	frame.Position = UDim2.fromOffset(cfg.LeftPx, cfg.TopPx)
	frame.Size = UDim2.fromOffset(cfg.ButtonPx + 2 * cfg.PadPx, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	local dockScale = Instance.new("UIScale")
	dockScale.Parent = frame
	frame.BackgroundColor3 = Theme.Colors.Backdrop
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, cfg.ButtonPx // 4 + cfg.PadPx)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Transparency = 0.3
	stroke.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, cfg.PadPx)
	pad.PaddingRight = UDim.new(0, cfg.PadPx)
	pad.PaddingTop = UDim.new(0, cfg.PadPx)
	pad.PaddingBottom = UDim.new(0, cfg.PadPx)
	pad.Parent = frame
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Vertical
	row.Padding = UDim.new(0, cfg.GapPx)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.Parent = frame

	-- Подсказка справа от кнопки.
	local tip = Instance.new("TextLabel")
	tip.Name = "DockTip"
	tip.AnchorPoint = Vector2.new(0, 0.5)
	tip.Size = UDim2.fromOffset(0, 26)
	tip.AutomaticSize = Enum.AutomaticSize.X
	tip.BackgroundColor3 = Theme.Colors.PanelBg
	tip.BackgroundTransparency = 0.05
	tip.BorderSizePixel = 0
	tip.FontFace = Theme.FontBold
	tip.TextSize = 14
	tip.TextColor3 = Theme.Colors.Text
	tip.Visible = false
	tip.ZIndex = 20
	tip.Parent = gui
	local tipPad = Instance.new("UIPadding")
	tipPad.PaddingLeft = UDim.new(0, 10)
	tipPad.PaddingRight = UDim.new(0, 10)
	tipPad.Parent = tip
	local tipCorner = Instance.new("UICorner")
	tipCorner.CornerRadius = UDim.new(0, 6)
	tipCorner.Parent = tip

	type Slot = { item: Item, root: TextButton, edge: UIStroke }
	local slots: { Slot } = {}
	local hovered: Slot? = nil

	local function tipText(item: Item): string
		local name = Strings.get(item.name, lang)
		local b = item.button
		if b ~= nil and b:IsA("TextButton") then
			local t = (b :: TextButton).Text
			-- Прежняя кнопка пишет состояние («исследуется…», «Магазин (M)») — показываем, если это не просто имя.
			if t ~= "" and string.find(t, name, 1, true) == nil then
				name ..= " — " .. t
			end
		end
		if item.key ~= nil then
			name ..= "  [" .. item.key .. "]"
		end
		return name
	end

	for order, item in items do
		local b = item.button
		if b ~= nil then
			b.Parent = holder
		end
		local root = Instance.new("TextButton")
		root.Name = "Dock_" .. item.icon
		root.Text = ""
		root.AutoButtonColor = true
		root.LayoutOrder = order
		root.Size = UDim2.fromOffset(cfg.ButtonPx, cfg.ButtonPx)
		root.BackgroundColor3 = Theme.Colors.PanelBg
		root.BorderSizePixel = 0
		root.Parent = frame
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, cfg.ButtonPx // 4)
		c.Parent = root
		local edge = Instance.new("UIStroke")
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Color = Theme.Colors.PanelBorder
		edge.Thickness = 2
		edge.Parent = root
		-- Значок 8×8 крупно по центру.
		local scale = cfg.IconScale
		local icon = Instance.new("Frame")
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.45)
		icon.Size = UDim2.fromOffset(PixelIcons.Size * scale, PixelIcons.Size * scale)
		icon.Parent = root
		local parts: { PixelIcons.Part } = PixelIcons.Icons[item.icon] or {}
		for _, part in parts do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = Theme.color(part.color)
			f.Position = UDim2.fromOffset(part.x * scale, part.y * scale)
			f.Size = UDim2.fromOffset(part.w * scale, part.h * scale)
			f.Parent = icon
		end
		if item.key ~= nil then
			local badge = Instance.new("TextLabel")
			badge.AnchorPoint = Vector2.new(1, 1)
			badge.Position = UDim2.new(1, -2, 1, -2)
			badge.Size = UDim2.fromOffset(16, 14)
			badge.BackgroundColor3 = Theme.Colors.Backdrop
			badge.BackgroundTransparency = 0.2
			badge.BorderSizePixel = 0
			badge.FontFace = Theme.FontBold
			badge.TextSize = 11
			badge.TextColor3 = Theme.Colors.Gold
			badge.Text = item.key :: string
			badge.Parent = root
			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0, 4)
			bc.Parent = badge
		end
		local slot: Slot = { item = item, root = root, edge = edge }
		Session.connect(root.Activated, function()
			item.toggle()
		end)
		Session.connect(root.MouseEnter, function()
			hovered = slot
		end)
		Session.connect(root.MouseLeave, function()
			if hovered == slot then
				hovered = nil
			end
		end)
		table.insert(slots, slot)
	end

	local nextAt = 0
	local function update(now: number)
		if now >= nextAt then
			nextAt = now + cfg.RefreshSec
			local any = false
			for _, slot in slots do
				local item = slot.item
				local b = item.button
				local visibleFn = item.visible
				local on = if b ~= nil then b.Visible elseif visibleFn ~= nil then visibleFn() else true
				slot.root.Visible = on
				any = any or on
				local isOpen = item.isOpen
				local open = isOpen ~= nil and isOpen()
				slot.edge.Color = if open then Theme.Colors.Gold else Theme.Colors.PanelBorder
				slot.root.BackgroundColor3 = if open then Theme.Colors.Slate else Theme.Colors.PanelBg
			end
			frame.Visible = any
			-- Не ниже места под командную полосу: высокий док ужимается (телефон, маленький экран).
			local natural = frame.AbsoluteSize.Y / math.max(0.01, dockScale.Scale)
			local room = gui.AbsoluteSize.Y - cfg.TopPx - cfg.BottomPx
			dockScale.Scale = math.clamp(room / math.max(1, natural), 0.5, 1)
		end
		local h = hovered
		if h ~= nil and h.root.Visible and frame.Visible then
			tip.Visible = true
			tip.Text = tipText(h.item)
			local p = h.root.AbsolutePosition - gui.AbsolutePosition
			tip.Position = UDim2.fromOffset(p.X + h.root.AbsoluteSize.X + 10, p.Y + h.root.AbsoluteSize.Y / 2)
		else
			tip.Visible = false
		end
	end

	return { update = update, frame = frame }
end

return table.freeze(Dock)
