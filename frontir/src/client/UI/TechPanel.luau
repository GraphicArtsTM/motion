--!strict
--[[
	TechPanel — окно «Технологии» (GDD §6.14, этап 7в-1): кнопка «Технологии (Y)» над «Стабильностью» и клавиша Y.
	Три столбца-ветки (Войска, Экономика, Флот) по четыре уровня: название, что даёт, цена и время.
	Изученный уровень — золотой, доступный — кнопка, следующий за ним и закрытые до этапа 7г — серые.
	Идёт исследование — полоска в его клетке и строка на кнопке («Учебка: 23 с»).
	Решения на сервере: клиент шлёт намерение research, отказ показывает лента (rejected).
	§15л ч.9: витрина CardKit — карточки уровней с картинками ItemArt, «ИЗУЧЕНО» / «ЗАКРЫТО», стрелки, полоса исследования.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type TechPanel = {
	button: GuiButton, -- §15з: кнопка прячется в док
	refresh: () -> (), -- пришли технологии или сменилась фаза
	-- Самопроверка (сводная правка, часть 1): открыть/закрыть окно и узнать, открыто ли.
	toggle: () -> (),
	isOpen: () -> boolean,
}

local TechPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local COLUMN = 280
local CELL_H = 90
local BRANCHES: { Types.TechBranch } = { "Army", "Economy", "Fleet" }

local function stroke(parent: Instance, color: Color3)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = Theme.BorderPx
	s.Parent = parent
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

	-- Окно (§15л ч.9): витрина CardKit — три ветки столбцами, уровень — карточка с картинкой ItemArt, между — стрелки.
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local win = CardKit.window(gui, "Tech", t("tech.titleBig"), t("tech.subtitle"), 940, 640, {}, { main = "list" })
	local window = win.frame
	window.ZIndex = 5
	local moneyChip = CardKit.chip(win.chips, "money", 1)
	local page = win.page("main")
	local statusRow = Instance.new("Frame")
	statusRow.BackgroundColor3 = Theme.Colors.Backdrop
	statusRow.BorderSizePixel = 0
	statusRow.Size = UDim2.new(1, 0, 0, 44)
	statusRow.LayoutOrder = 1
	statusRow.Parent = page
	MenuKit.stroke(statusRow, Theme.Colors.PanelBorder, 2)
	local status = MenuKit.label(statusRow, "", 15, Theme.Colors.Text, true)
	status.Position = UDim2.fromOffset(12, 4)
	local statusBarHost = Instance.new("Frame")
	statusBarHost.BackgroundTransparency = 1
	statusBarHost.Position = UDim2.fromOffset(12, 28)
	statusBarHost.Size = UDim2.new(1, -24, 0, 8)
	statusBarHost.Parent = statusRow
	local statusBar = MenuKit.bar(statusBarHost, 8, Theme.Colors.Sky)

	local columns = Instance.new("Frame")
	columns.BackgroundTransparency = 1
	columns.Size = UDim2.new(1, 0, 0, 40 + #cfg.Cost * (CELL_H + 30))
	columns.LayoutOrder = 2
	columns.Parent = page
	local colLayout = MenuKit.list(columns, 12, true)
	colLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	colLayout.HorizontalFlex = Enum.UIFlexAlignment.Fill

	type Cell = {
		button: TextButton,
		name: TextLabel,
		desc: TextLabel,
		info: TextLabel,
		bar: Frame,
		edge: UIStroke,
		dim: Frame,
		tag: TextLabel,
	}
	local cells: { [string]: Cell } = {}
	local heads: { [string]: TextLabel } = {}
	local BRANCH_ICON: { [string]: string } = { Army = "army", Economy = "money", Fleet = "tech" }

	for k, branch in BRANCHES do
		local col = MenuKit.box(columns, branch, k)
		col.AutomaticSize = Enum.AutomaticSize.Y
		col.Size = UDim2.fromOffset(COLUMN, 0)
		MenuKit.list(col, 4, false, Enum.HorizontalAlignment.Center)
		local headRow = MenuKit.box(col, "Head", 0)
		MenuKit.list(headRow, 8, true)
		MenuKit.icon(headRow, BRANCH_ICON[branch], 3, 1)
		local head = MenuKit.label(headRow, t("tech.branch." .. branch), 18, Theme.Colors.Gold, true, 2)
		heads[branch] = head
		for level = 1, #cfg.Cost do
			if level > 1 then
				MenuKit.label(col, "▼", 14, Theme.Colors.PanelBorder, true, level * 2 - 1)
			end
			local b = Instance.new("TextButton")
			b.Name = branch .. level
			b.Size = UDim2.new(1, 0, 0, CELL_H)
			b.BackgroundColor3 = Theme.Colors.Backdrop
			b.BorderSizePixel = 0
			b.AutoButtonColor = true
			b.Text = ""
			b.LayoutOrder = level * 2
			b.ClipsDescendants = true
			b.Parent = col
			local edge = MenuKit.stroke(b, Theme.Colors.PanelBorder, 2)
			local bar = Instance.new("Frame")
			bar.Name = "Progress"
			bar.BackgroundColor3 = Theme.Colors.Sky
			bar.BackgroundTransparency = 0.6
			bar.BorderSizePixel = 0
			bar.Size = UDim2.fromScale(0, 1)
			bar.Visible = false
			bar.Parent = b
			local art = CardKit.art(b, "tech." .. branch .. level, 84, 56)
			art.Position = UDim2.fromOffset(6, 6)
			local name = MenuKit.label(
				b,
				string.format("%d. %s", level, t("tech." .. branch .. "." .. level)),
				14,
				Theme.Colors.Text,
				true
			)
			name.AutomaticSize = Enum.AutomaticSize.None
			name.Position = UDim2.fromOffset(98, 6)
			name.Size = UDim2.new(1, -104, 0, 18)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local desc = MenuKit.label(b, describe(branch, level, lang), 11, Theme.Colors.Muted)
			desc.AutomaticSize = Enum.AutomaticSize.None
			desc.Position = UDim2.fromOffset(98, 25)
			desc.Size = UDim2.new(1, -104, 0, 38)
			desc.TextWrapped = true
			desc.TextYAlignment = Enum.TextYAlignment.Top
			local info = MenuKit.label(b, "", 12, Theme.Colors.Text, true)
			info.AutomaticSize = Enum.AutomaticSize.None
			info.Position = UDim2.new(0, 98, 1, -20)
			info.Size = UDim2.new(1, -104, 0, 16)
			local dim = Instance.new("Frame")
			dim.Name = "Dim"
			dim.BackgroundColor3 = Theme.color("Ink")
			dim.BackgroundTransparency = 0.6
			dim.BorderSizePixel = 0
			dim.Position = UDim2.fromOffset(6, 6)
			dim.Size = UDim2.fromOffset(84, 56)
			dim.Visible = false
			dim.Parent = b
			local tag = MenuKit.label(b, "", 10, Theme.color("Ink"), true)
			tag.Position = UDim2.fromOffset(8, 8)
			tag.BackgroundTransparency = 0
			tag.BackgroundColor3 = Theme.Colors.Gold
			MenuKit.pad(tag, 4, 1)
			tag.Visible = false
			cells[branch .. level] =
				{ button = b, name = name, desc = desc, info = info, bar = bar, edge = edge, dim = dim, tag = tag }
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
	local closeButton = win.close

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
				c.dim.Visible = closed or (not done and not available and not isResearching)
				c.tag.Visible = done or closed
				c.tag.Text = t(if done then "tech.tagDone" else "tech.tagLocked")
				c.tag.BackgroundColor3 = if done then Theme.Colors.Gold else Theme.Colors.PanelBorder
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
				if available then
					c.edge.Color = Theme.Colors.Good
				end
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
		statusBar.frame.Visible = r ~= nil
		if r ~= nil then
			statusBar.set(1 - r.left / math.max(1, r.total))
		end
		moneyChip.Text = "$" .. Strings.formatInt(money)
		for _, branch in BRANCHES do
			local have = (cs.tech.levels :: any)[branch] :: number
			heads[branch].Text = string.format(t("tech.branchLevel"), t("tech.branch." .. branch), have, #cfg.Cost)
		end
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
		button = main,
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
