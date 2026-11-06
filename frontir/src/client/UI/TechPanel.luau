--!strict
--[[
	TechPanel — окно «Технологии» (GDD §6.14, этап 7в-1): кнопка «Технологии (Y)» над «Стабильностью» и клавиша Y.
	Три столбца-ветки (Войска, Экономика, Флот) по четыре уровня: название, что даёт, цена и время.
	Изученный уровень — золотой, доступный — кнопка, следующий за ним и закрытые до этапа 7г — серые.
	Идёт исследование — полоска в его клетке и строка на кнопке («Учебка: 23 с»).
	Решения на сервере: клиент шлёт намерение research, отказ показывает лента (rejected).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type TechPanel = {
	refresh: () -> (), -- пришли технологии или сменилась фаза
	-- Самопроверка (сводная правка, часть 1): открыть/закрыть окно и узнать, открыто ли.
	toggle: () -> (),
	isOpen: () -> boolean,
}

local TechPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local COLUMN = 200
local CELL_H = 74
local WIDTH = 3 * COLUMN + 2 * 8 + 20
local BRANCHES: { Types.TechBranch } = { "Army", "Economy", "Fleet" }

local function stroke(parent: Instance, color: Color3)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = Theme.BorderPx
	s.Parent = parent
end

local function text(parent: Instance, size: number, bold: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextWrapped = true
	t.FontFace = if bold then Theme.FontBold else Theme.Font
	t.TextSize = size
	t.TextColor3 = Theme.Colors.Text
	t.Parent = parent
	return t
end

-- Что даёт уровень: подстановка чисел из Config.Tech.
local function describe(branch: string, level: number, lang: Strings.Lang): string
	local cfg = Config.Tech
	local fmt = Strings.get("tech.desc." .. branch .. "." .. level, lang)
	local key = branch .. level
	if key == "Army2" then
		return string.format(fmt, tostring(cfg.SupplyRangeMul))
	elseif key == "Army4" then
		return string.format(fmt, tostring(cfg.TankArmor))
	elseif key == "Economy1" then
		return string.format(fmt, math.round(cfg.TaxBonus * 100))
	elseif key == "Economy2" then
		return string.format(fmt, math.round(cfg.OilBonus * 100))
	elseif key == "Economy3" then
		return string.format(fmt, tostring(cfg.TradeMul))
	elseif key == "Economy4" then
		return string.format(fmt, cfg.OrderStability)
	elseif key == "Fleet1" then
		return string.format(fmt, math.round(cfg.ShipyardDiscount * 100))
	end
	return (string.gsub(fmt, "%%%%", "%%")) -- без подстановок: «%%» → «%»
end

local function locked(branch: string, level: number): boolean
	local l = (Config.Tech.Locked :: any)[branch]
	return l ~= nil and level >= l
end

function TechPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> ()
): TechPanel
	local cfg = Config.Tech
	local function playing(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
	end

	-- Кнопка над «Стабильностью» (на узком экране — тоже над ней).
	local main = Instance.new("TextButton")
	main.Name = "TechButton"
	main.Size = UDim2.fromOffset(180, BUTTON)
	main.BackgroundColor3 = Theme.Colors.PanelBg
	main.BackgroundTransparency = 0.1
	main.BorderSizePixel = 0
	main.AutoButtonColor = true
	main.FontFace = Theme.FontBold
	main.TextSize = 14
	main.TextWrapped = true
	main.TextColor3 = Theme.Colors.Text
	stroke(main, Theme.Colors.PanelBorder)
	main.Parent = gui
	local function place()
		if gui.AbsoluteSize.X < Config.Render.NarrowScreenPx then
			main.AnchorPoint = Vector2.new(1, 1)
			main.Position = UDim2.new(1, -20 - Config.Render.MinimapSide, 1, -12 - 4 * 56 - 24)
		else
			main.AnchorPoint = Vector2.new(0, 1)
			main.Position = UDim2.new(0.5, 108, 1, -12 - 2 * 56 - 12)
		end
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), place)
	place()

	-- Окно.
	local window = Instance.new("Frame")
	window.Name = "Tech"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(WIDTH, 0)
	window.AutomaticSize = Enum.AutomaticSize.Y
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BackgroundTransparency = 0.05
	window.BorderSizePixel = 0
	window.Visible = false
	window.ZIndex = 5
	stroke(window, Theme.Colors.PanelBorder)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = window
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = window
	window.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function fit()
		local s = gui.AbsoluteSize
		scale.Scale = math.clamp(math.min(s.X / (WIDTH + 40), s.Y / (5 * CELL_H + 160)), 0.5, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()

	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, BUTTON)
	header.LayoutOrder = 1
	header.Parent = window
	local title = text(header, 18, true)
	title.Size = UDim2.new(1, -BUTTON - 6, 1, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Theme.Colors.Gold
	title.Text = Strings.get("tech.title", lang)
	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.fromScale(1, 0)
	closeButton.Size = UDim2.fromOffset(BUTTON, BUTTON)
	closeButton.BackgroundColor3 = Theme.Colors.PanelBg
	closeButton.BorderSizePixel = 0
	closeButton.FontFace = Theme.FontBold
	closeButton.TextSize = 18
	closeButton.TextColor3 = Theme.Colors.Text
	closeButton.Text = "×"
	stroke(closeButton, Theme.Colors.PanelBorder)
	closeButton.Parent = header

	local status = text(window, 13)
	status.Size = UDim2.new(1, 0, 0, 18)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = Theme.Colors.Muted
	status.LayoutOrder = 2

	local columns = Instance.new("Frame")
	columns.BackgroundTransparency = 1
	columns.Size = UDim2.new(1, 0, 0, 22 + 4 * (CELL_H + 6))
	columns.LayoutOrder = 3
	columns.Parent = window
	local colLayout = Instance.new("UIListLayout")
	colLayout.FillDirection = Enum.FillDirection.Horizontal
	colLayout.Padding = UDim.new(0, 8)
	colLayout.SortOrder = Enum.SortOrder.LayoutOrder
	colLayout.Parent = columns

	type Cell = { button: TextButton, name: TextLabel, desc: TextLabel, info: TextLabel, bar: Frame, edge: UIStroke }
	local cells: { [string]: Cell } = {}

	for k, branch in BRANCHES do
		local col = Instance.new("Frame")
		col.Name = branch
		col.BackgroundTransparency = 1
		col.Size = UDim2.new(0, COLUMN, 1, 0)
		col.LayoutOrder = k
		col.Parent = columns
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 6)
		list.Parent = col
		local head = text(col, 15, true)
		head.Size = UDim2.new(1, 0, 0, 16)
		head.Text = Strings.get("tech.branch." .. branch, lang)
		head.LayoutOrder = 0
		for level = 1, #cfg.Cost do
			local b = Instance.new("TextButton")
			b.Name = branch .. level
			b.Size = UDim2.new(1, 0, 0, CELL_H)
			b.BackgroundColor3 = Theme.Colors.Backdrop
			b.BackgroundTransparency = 0.2
			b.BorderSizePixel = 0
			b.AutoButtonColor = true
			b.Text = ""
			b.LayoutOrder = level
			b.ClipsDescendants = true
			local edge = Instance.new("UIStroke")
			edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			edge.Color = Theme.Colors.PanelBorder
			edge.Thickness = Theme.BorderPx
			edge.Parent = b
			local bar = Instance.new("Frame")
			bar.Name = "Progress"
			bar.BackgroundColor3 = Theme.Colors.Sky
			bar.BackgroundTransparency = 0.6
			bar.BorderSizePixel = 0
			bar.Size = UDim2.fromScale(0, 1)
			bar.Visible = false
			bar.Parent = b
			local name = text(b, 14, true)
			name.Position = UDim2.fromOffset(6, 4)
			name.Size = UDim2.new(1, -12, 0, 18)
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.Text = string.format("%d. %s", level, Strings.get("tech." .. branch .. "." .. level, lang))
			local desc = text(b, 12)
			desc.Position = UDim2.fromOffset(6, 24)
			desc.Size = UDim2.new(1, -12, 0, 30)
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.TextYAlignment = Enum.TextYAlignment.Top
			desc.TextColor3 = Theme.Colors.Muted
			desc.Text = describe(branch, level, lang)
			local info = text(b, 12, true)
			info.Position = UDim2.new(0, 6, 1, -18)
			info.Size = UDim2.new(1, -12, 0, 16)
			info.TextXAlignment = Enum.TextXAlignment.Left
			b.Parent = col
			cells[branch .. level] = { button = b, name = name, desc = desc, info = info, bar = bar, edge = edge }
			Session.connect(b.Activated, function()
				if not playing() then
					return
				end
				local have = (cs.tech.levels :: any)[branch] :: number
				if level == have + 1 and cs.tech.research == nil and not locked(branch, level) then
					send("research", { branch = branch })
				end
			end)
		end
	end

	local function researchLine(): string?
		local r = cs.tech.research
		if r == nil then
			return nil
		end
		local name = Strings.get("tech." .. r.branch .. "." .. r.level, lang)
		return string.format(Strings.get("tech.progress", lang), name, r.left)
	end

	local function draw()
		local r = cs.tech.research
		local money = if cs.myForces ~= nil then cs.myForces.economy.money else 0
		for _, branch in BRANCHES do
			local have = (cs.tech.levels :: any)[branch] :: number
			for level = 1, #cfg.Cost do
				local c = cells[branch .. level]
				local isResearching = r ~= nil and r.branch == branch and r.level == level
				local done = level <= have
				local closed = locked(branch, level)
				local available = not done and not closed and level == have + 1 and r == nil
				c.bar.Visible = isResearching
				if isResearching and r ~= nil then
					c.bar.Size = UDim2.fromScale(math.clamp(1 - r.left / math.max(1, r.total), 0, 1), 1)
				end
				c.button.AutoButtonColor = available
				c.name.TextColor3 = if done
					then Theme.Colors.Gold
					elseif available or isResearching then Theme.Colors.Text
					else Theme.Colors.Muted
				c.edge.Color = if done
					then Theme.Colors.Gold
					elseif isResearching then Theme.Colors.Sky
					elseif available then Theme.Colors.Text
					else Theme.Colors.PanelBorder
				if done then
					c.info.Text = Strings.get("tech.done", lang)
					c.info.TextColor3 = Theme.Colors.Gold
				elseif closed then
					c.info.Text = Strings.get("tech.locked", lang)
					c.info.TextColor3 = Theme.Colors.Muted
				elseif isResearching and r ~= nil then
					c.info.Text = string.format("%d / %d", r.total - r.left, r.total)
					c.info.TextColor3 = Theme.Colors.Sky
				else
					c.info.Text = string.format(
						Strings.get("tech.cost", lang),
						Strings.formatInt(cfg.Cost[level]),
						cfg.Sec[level]
					)
					c.info.TextColor3 = if available and money < cfg.Cost[level]
						then Theme.Colors.Alert
						elseif available then Theme.Colors.Text
						else Theme.Colors.Muted
				end
			end
		end
		status.Text = researchLine() or Strings.get("tech.idle", lang)
	end

	local function refresh()
		main.Visible = playing()
		main.Text = researchLine() or Strings.get("tech.button", lang)
		if not playing() then
			window.Visible = false
		end
		if window.Visible then
			draw()
		end
	end

	local function setOpen(open: boolean)
		window.Visible = open and playing()
		if window.Visible then
			draw()
		end
	end
	Session.connect(main.Activated, function()
		setOpen(not window.Visible)
	end)
	Session.connect(closeButton.Activated, function()
		setOpen(false)
	end)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.Y and playing() then
			setOpen(not window.Visible)
		elseif input.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
		end
	end)

	refresh()
	return {
		refresh = refresh,
		toggle = function()
			setOpen(not window.Visible)
		end,
		isOpen = function(): boolean
			return window.Visible
		end,
	}
end

return table.freeze(TechPanel)
