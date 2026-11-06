--!strict
--[[
	RanksPanel — окно «Звания» (GDD §15л): сверху — ваше звание крупно, уровень, полоса опыта и «следующее
	звание — на уровне N»; ниже — сетка всех званий (уровни, значок, название): ваше подсвечено и помечено «ВЫ»,
	будущие притушены и с замком. Только вид. Открывается из главного меню (профиль, плитка «Звания»).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Ranks = require(Shared:WaitForChild("Ranks"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type RanksPanel = {
	toggle: () -> (),
	isOpen: () -> boolean,
	refresh: () -> (),
	window: Frame,
}

local RanksPanel = {}

local CELL_W, CELL_H = 150, 112

function RanksPanel.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang): RanksPanel
	local cfg = Config.Render.Menu
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local cols = cfg.RanksColumns
	local width = cols * CELL_W + (cols - 1) * 8 + 28

	local window = Instance.new("Frame")
	window.Name = "RanksWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(width, 0)
	window.AutomaticSize = Enum.AutomaticSize.Y
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BorderSizePixel = 0
	window.Active = true
	window.Visible = false
	window.Parent = gui
	MenuKit.corner(window, 8)
	MenuKit.stroke(window, Theme.Colors.PanelBorder, 2)
	MenuKit.pad(window, 14, 12)
	MenuKit.list(window, 10)
	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function fit()
		local s = gui.AbsoluteSize
		scale.Scale = math.clamp(math.min((s.X - 24) / width, (s.Y - 24) / 640), 0.4, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()

	-- Заголовок и «×».
	local head = Instance.new("Frame")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 52)
	head.LayoutOrder = 1
	head.Parent = window
	MenuKit.label(head, t("ranks.title"), 26, Theme.Colors.Gold, true)
	local sub = MenuKit.label(head, t("ranks.subtitle"), 13, Theme.Colors.Muted)
	sub.Position = UDim2.fromOffset(0, 32)
	local close = MenuKit.button(head, "×", "normal")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(MenuKit.Touch, MenuKit.Touch)
	close.TextSize = 24

	-- Ваше звание.
	local mine = MenuKit.row(window, "Mine", 2)
	local mineList = mine:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	mineList.FillDirection = Enum.FillDirection.Horizontal
	mineList.VerticalAlignment = Enum.VerticalAlignment.Center
	mineList.Padding = UDim.new(0, 14)
	local mineIcon = MenuKit.rankIcon(mine, 1, 4, 1)
	local mineText = MenuKit.box(mine, "Text", 2)
	MenuKit.list(mineText, 4)
	local mineTitle = MenuKit.label(mineText, "", 20, Theme.Colors.Text, true, 1)
	local barHost = Instance.new("Frame")
	barHost.BackgroundTransparency = 1
	barHost.Size = UDim2.fromOffset(width - 140, 8)
	barHost.LayoutOrder = 2
	barHost.Parent = mineText
	local xpBar = MenuKit.bar(barHost, 8, Theme.Colors.Sky)
	local mineXp = MenuKit.label(mineText, "", 12, Theme.Colors.Muted, false, 3)
	local mineNext = MenuKit.label(mineText, "", 13, Theme.Colors.Sky, true, 4)

	-- Сетка званий.
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 3
	grid.Parent = window
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL_W, CELL_H)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	type Cell = { frame: Frame, edge: UIStroke, badge: TextLabel, dim: Frame, name: TextLabel }
	local cells: { Cell } = {}
	for rank = 1, Ranks.Count do
		local f = Instance.new("Frame")
		f.Name = "Rank" .. rank
		f.LayoutOrder = rank
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BackgroundTransparency = 0.2
		f.BorderSizePixel = 0
		f.Parent = grid
		MenuKit.corner(f, 6)
		local edge = MenuKit.stroke(f, Theme.Colors.Slate, 2)
		local levels = MenuKit.label(
			f,
			string.format(
				t("ranks.levels"),
				Ranks.firstLevel(rank),
				Ranks.firstLevel(rank) + Config.Ranks.LevelsPerRank - 1
			),
			10,
			Theme.Colors.Muted,
			true
		)
		levels.Position = UDim2.fromOffset(8, 6)
		local badge = MenuKit.label(f, "", 10, Theme.color("Ink"), true)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -6, 0, 5)
		badge.BackgroundColor3 = Theme.Colors.Sky
		MenuKit.corner(badge, 3)
		MenuKit.pad(badge, 4, 1)
		local icon = MenuKit.rankIcon(f, rank, 3)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 24)
		local name = MenuKit.label(f, Strings.get("rank." .. rank, lang), 12, Theme.Colors.Text, true)
		name.AnchorPoint = Vector2.new(0.5, 1)
		name.Position = UDim2.new(0.5, 0, 1, -6)
		name.TextXAlignment = Enum.TextXAlignment.Center
		local dim = Instance.new("Frame")
		dim.Name = "Dim"
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Theme.Colors.Backdrop
		dim.BackgroundTransparency = 0.45
		dim.BorderSizePixel = 0
		dim.ZIndex = 2
		dim.Parent = f
		MenuKit.corner(dim, 6)
		table.insert(cells, { frame = f, edge = edge, badge = badge, dim = dim, name = name })
	end

	local function refresh()
		if not window.Visible then
			return
		end
		local p = cs.profile
		local level = if p ~= nil then p.level else 1
		local rank = Ranks.of(level)
		MenuKit.setRank(mineIcon, rank, 4)
		mineTitle.Text = string.format(t("menu.level"), level) .. "  ·  " .. Strings.get("rank." .. rank, lang)
		if p ~= nil and p.need > 0 then
			xpBar.set(p.xp / p.need)
			mineXp.Text = string.format(t("menu.xp"), p.xp, p.need)
				.. "   ·   "
				.. string.format(t("ranks.total"), p.matches, p.wins)
		else
			xpBar.set(1)
			mineXp.Text = t("menu.maxLevel")
		end
		local nextLevel = Ranks.nextAt(level)
		mineNext.Text = if nextLevel ~= nil
			then string.format(t("ranks.next"), Strings.get("rank." .. (rank + 1), lang), nextLevel)
			else t("ranks.max")
		for k, c in cells do
			local mineCell = k == rank
			c.edge.Color = if mineCell
				then Theme.Colors.Sky
				elseif k < rank then Theme.Colors.PanelBorder
				else Theme.Colors.Slate
			c.frame.BackgroundColor3 = if mineCell then Theme.Colors.Slate else Theme.Colors.Backdrop
			c.dim.Visible = k > rank
			c.badge.Visible = mineCell or k > rank
			c.badge.Text = if mineCell then t("ranks.you") else t("ranks.locked")
			c.badge.BackgroundTransparency = if mineCell then 0 else 1
			c.name.TextColor3 = if mineCell then Theme.Colors.Gold else Theme.Colors.Text
		end
	end

	local function toggle()
		window.Visible = not window.Visible
		refresh()
	end
	Session.connect(close.Activated, toggle)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and window.Visible then
			window.Visible = false
		end
	end)

	return {
		toggle = toggle,
		isOpen = function(): boolean
			return window.Visible
		end,
		refresh = refresh,
		window = window,
	}
end

return table.freeze(RanksPanel)
