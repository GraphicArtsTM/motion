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

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

export type ActionRing = {
	-- Открыть у точки экрана (координаты области карты; inset — её AbsolutePosition) для клетки cell.
	open: (sx: number, sy: number, cell: number, facts: ActionRingLogic.Facts) -> (),
	close: () -> (),
	isOpen: () -> boolean,
}

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
	local current: { cell: number, owner: number }? = nil
	local picks: { ActionRingLogic.Action } = {}

	local function close()
		backdrop.Visible = false
		current = nil
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
		made.Parent = backdrop
		Session.connect(made.Activated, function()
			local cur = current
			local action: ActionRingLogic.Action? = picks[k]
			close()
			if cur ~= nil and action ~= nil then
				handler(action, cur.cell, cur.owner)
			end
		end)
		buttons[k] = made
		return made
	end

	local function open(sx: number, sy: number, cell: number, facts: ActionRingLogic.Facts)
		picks = ActionRingLogic.actions(facts)
		if #picks == 0 then
			close()
			return
		end
		current = { cell = cell, owner = facts.owner }
		local inset = viewport.AbsolutePosition - gui.AbsolutePosition
		local cx, cy = sx + inset.X, sy + inset.Y
		-- Кольцо не вылезает за край экрана.
		local size = gui.AbsoluteSize
		local r = cfg.Radius
		local margin = r + cfg.ButtonW / 2
		cx = math.clamp(cx, margin, math.max(margin, size.X - margin))
		cy = math.clamp(cy, r + 30, math.max(r + 30, size.Y - r - 30))
		center.Position = UDim2.fromOffset(sx + inset.X, sy + inset.Y)
		for k, action in picks do
			local b = button(k)
			-- Первая кнопка — сверху, дальше по часовой стрелке.
			local angle = -math.pi / 2 + (k - 1) * 2 * math.pi / #picks
			b.Position = UDim2.fromOffset(cx + math.cos(angle) * r, cy + math.sin(angle) * r)
			b.Text = Strings.get("ring." .. action, lang)
			b.Visible = true
		end
		for k, b in buttons do
			if k > #picks and b then
				b.Visible = false
			end
		end
		backdrop.Visible = true
	end

	Session.connect(backdrop.Activated, close)
	Session.connect(UserInputService.InputBegan, function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Escape then
			close()
		end
	end)

	return {
		open = open,
		close = close,
		isOpen = function(): boolean
			return backdrop.Visible
		end,
	}
end

return table.freeze(ActionRing)
