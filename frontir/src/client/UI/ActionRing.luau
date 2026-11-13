--!strict
--[[
	ActionRing — кольцо действий (GDD §15е): правая кнопка мыши или долгое касание на карте — вокруг точки кнопки
	«что можно сделать здесь». Список — чистый Shared.ActionRing по фактам о клетке; что делает кнопка —
	handler из Main.client (атака, объявление войны, предложения, разведка, метки, стройка). Нажатие мимо или
	Escape закрывает кольцо.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActionRingLogic = require(Shared:WaitForChild("ActionRing"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

export type ActionRing = {
	-- Открыть у точки экрана (координаты области карты; inset — её AbsolutePosition) для клетки cell.
	-- decorate (§15х ч.4) — подпись кнопки вместо стандартной и «не готово» (кнопка бледнее, нажатие — подсказка).
	open: (sx: number, sy: number, cell: number, facts: ActionRingLogic.Facts, decorate: Decorate?) -> (),
	-- Второе кольцо (§15ж — эмодзи): подписи кнопок и что делать по номеру.
	choose: (sx: number, sy: number, labels: { string }, onPick: (index: number) -> ()) -> (),
	close: () -> (),
	isOpen: () -> boolean,
}

-- Подпись (nil — обычная), готово ли, картинка ItemArt (удары, §15х ч.5) и цвет рамки.
export type Decorate = (action: ActionRingLogic.Action) -> (string?, boolean, string?, Color3?)
type Style = { dim: boolean, art: string?, accent: Color3? }

local ActionRing = {}

function ActionRing.new(
	gui: ScreenGui,
	viewport: GuiObject,
	lang: Strings.Lang,
	handler: (action: ActionRingLogic.Action, cell: number, owner: number) -> ()
): ActionRing
	local cfg = Config.Render.ActionRing
	-- Подложка на весь экран: нажатие мимо кнопок закрывает кольцо.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ActionRing"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundTransparency = 1
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 60
	backdrop.Visible = false
	backdrop.Parent = gui

	local center = Instance.new("Frame")
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Size = UDim2.fromOffset(10, 10)
	center.BackgroundColor3 = Theme.Colors.Gold
	center.BorderSizePixel = 0
	center.ZIndex = 61
	center.Parent = backdrop
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = center

	local buttons: { [number]: TextButton? } = {}
	local arts: { [number]: ImageLabel? } = {} -- картинка удара у кнопки k (создаётся при первой надобности)
	local strokes: { [number]: UIStroke } = {}
	local pads: { [number]: UIPadding } = {}
	-- Что делает кнопка k (кольцо действий или второе кольцо выбора).
	local runs: { [number]: () -> () } = {}

	local function close()
		backdrop.Visible = false
		table.clear(runs)
	end

	local function button(k: number): TextButton
		local existing = buttons[k]
		if existing then
			return existing
		end
		local made = Instance.new("TextButton")
		made.AnchorPoint = Vector2.new(0.5, 0.5)
		made.Size = UDim2.fromOffset(cfg.ButtonW, Config.Render.MinTouchTargetPx)
		made.BackgroundColor3 = Theme.Colors.PanelBg
		made.BorderSizePixel = 0
		made.AutoButtonColor = true
		made.FontFace = Theme.FontBold
		made.TextSize = 14
		made.TextWrapped = true -- §15х ч.4: «Налёт» и строкой ниже — чего не хватает
		made.TextColor3 = Theme.Colors.Text
		made.ZIndex = 62
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = made
		local s = Instance.new("UIStroke")
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Color = Theme.Colors.Gold
		s.Thickness = 2
		s.Parent = made
		strokes[k] = s
		local pad = Instance.new("UIPadding")
		pad.Parent = made
		pads[k] = pad
		made.Parent = backdrop
		Session.connect(made.Activated, function()
			local run = runs[k]
			close()
			if run ~= nil then
				run()
			end
		end)
		buttons[k] = made
		return made
	end

	-- Радиус, при котором соседние кнопки не налезают друг на друга (§15х ч.4: до 8 кнопок).
	local function radiusFor(n: number): number
		local r = cfg.Radius
		local w, h = cfg.ButtonW + 4, Config.Render.MinTouchTargetPx + 4
		for _ = 1, 40 do
			local ok = true
			for k = 1, n do
				local a1 = -math.pi / 2 + (k - 1) * 2 * math.pi / n
				local a2 = -math.pi / 2 + k * 2 * math.pi / n
				local dx = math.abs(math.cos(a1) - math.cos(a2)) * r
				local dy = math.abs(math.sin(a1) - math.sin(a2)) * r
				if dx < w and dy < h then
					ok = false
					break
				end
			end
			if ok then
				break
			end
			r += 4
		end
		return r
	end

	local ART_W, ART_H = 36, 24
	local function styleButton(k: number, b: TextButton, style: Style?)
		local faded = style ~= nil and style.dim
		b.TextColor3 = if faded then Theme.Colors.Muted else Theme.Colors.Text
		b.BackgroundTransparency = if faded then 0.35 else 0
		strokes[k].Color = if style ~= nil
				and style.accent ~= nil
				and not faded
			then style.accent :: Color3
			elseif faded then Theme.Colors.PanelBorder
			else Theme.Colors.Gold
		strokes[k].Thickness = if style ~= nil and style.accent ~= nil and not faded then 3 else 2
		local key = if style ~= nil then style.art else nil
		local img = arts[k]
		if key ~= nil then
			if img == nil then
				local made = CardKit.art(b, key, ART_W, ART_H)
				made.AnchorPoint = Vector2.new(0, 0.5)
				made.Position = UDim2.new(0, -ART_W - 4, 0.5, 0) -- отступ кнопки сдвигает и картинку: её место — x = 4
				made.ZIndex = 63
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0, 5)
				c.Parent = made
				arts[k] = made
				img = made
			else
				CardKit.repaint(img, key)
			end
			local shown = img :: ImageLabel
			shown.Visible = true
			shown.ImageTransparency = if faded then 0.5 else 0
			pads[k].PaddingLeft = UDim.new(0, ART_W + 8)
		else
			if img ~= nil then
				img.Visible = false
			end
			pads[k].PaddingLeft = UDim.new(0, 0)
		end
	end

	local function show(sx: number, sy: number, labels: { string }, todo: { () -> () }, styles: { [number]: Style }?)
		if #labels == 0 then
			close()
			return
		end
		table.clear(runs)
		for k, run in todo do
			runs[k] = run
		end
		-- §15ц: слой в масштабе экрана — точка нажатия (настоящие пиксели) переводится в условные.
		local f = UiScale.factor()
		local inset = viewport.AbsolutePosition - gui.AbsolutePosition
		local px, py = (sx + inset.X) / f, (sy + inset.Y) / f
		local cx, cy = px, py
		-- Кольцо не вылезает за край экрана.
		local size = UiScale.size(gui)
		local r = radiusFor(#labels)
		local margin = r + cfg.ButtonW / 2
		cx = math.clamp(cx, margin, math.max(margin, size.X - margin))
		cy = math.clamp(cy, r + 30, math.max(r + 30, size.Y - r - 30))
		center.Position = UDim2.fromOffset(px, py)
		for k, text in labels do
			local b = button(k)
			-- Первая кнопка — сверху, дальше по часовой стрелке.
			local angle = -math.pi / 2 + (k - 1) * 2 * math.pi / #labels
			b.Position = UDim2.fromOffset(cx + math.cos(angle) * r, cy + math.sin(angle) * r)
			b.Text = text
			b.Visible = true
			styleButton(k, b, if styles ~= nil then styles[k] else nil)
		end
		for k, b in buttons do
			if k > #labels and b then
				b.Visible = false
			end
		end
		backdrop.Visible = true
	end

	local function open(sx: number, sy: number, cell: number, facts: ActionRingLogic.Facts, decorate: Decorate?)
		local labels: { string } = {}
		local todo: { () -> () } = {}
		local styles: { [number]: Style } = {}
		local actions: { ActionRingLogic.Action } = ActionRingLogic.actions(facts)
		for k = 1, #actions do
			local action: ActionRingLogic.Action = actions[k]
			local label: string? = nil
			if decorate ~= nil then
				local text, ready, art, accent = decorate(action)
				label = text
				styles[k] = { dim = not ready, art = art, accent = accent }
			end
			table.insert(labels, label or Strings.get("ring." .. action, lang))
			table.insert(todo, function()
				handler(action, cell, facts.owner)
			end)
		end
		show(sx, sy, labels, todo, styles)
	end

	local function choose(sx: number, sy: number, labels: { string }, onPick: (index: number) -> ())
		local todo: { () -> () } = {}
		for k in labels do
			table.insert(todo, function()
				onPick(k)
			end)
		end
		show(sx, sy, labels, todo)
	end

	Session.connect(backdrop.Activated, close)
	Session.connect(UserInputService.InputBegan, function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Escape then
			close()
		end
	end)

	return {
		open = open,
		choose = choose,
		close = close,
		isOpen = function(): boolean
			return backdrop.Visible
		end,
	}
end

return table.freeze(ActionRing)
