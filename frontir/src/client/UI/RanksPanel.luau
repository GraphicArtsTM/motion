--!strict
--[[
	RanksPanel — окно «Путь командира» (§15ф, вместо сетки званий §15л). Уровень профиля показывает, какой частью
	вы командуете. Сверху — где вы сейчас: крупный знак части, название, уровень, «≈ сколько бойцов», полоса опыта;
	справа — следующая ступень и сколько уровней до неё. Ниже — дорога из 11 ступеней слева направо: линия,
	пройденная часть золотом, у каждой ступени — знак, «ур. N» и название; ваша — в золотой рамке с меткой «ВЫ»,
	будущие притушены. Только вид. Открывается из главного меню (профиль) и меню игры.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Ranks = require(Shared:WaitForChild("Ranks"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type RanksPanel = {
	toggle: () -> (),
	isOpen: () -> boolean,
	refresh: () -> (),
	window: Frame,
}

local RanksPanel = {}

local W = 960
local NODE_W = 84 -- ширина ступени на дороге
local NODE_BADGE = 3 -- масштаб знака на дороге (16 × 3 = 48 px)

local function groupColor(rank: number): Color3
	return Theme.color(Ranks.GroupColors[Ranks.group(rank)])
end

function RanksPanel.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang): RanksPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end

	local window = Instance.new("Frame")
	window.Name = "RanksWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(W, 0)
	window.AutomaticSize = Enum.AutomaticSize.Y
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BorderSizePixel = 0
	window.Active = true
	window.Visible = false
	window.Parent = gui
	MenuKit.pad(window, 28, 22)
	MenuKit.list(window, 18)
	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function fit()
		local s = UiScale.size(gui)
		scale.Scale = math.clamp(math.min((s.X - 24) / W, (s.Y - 24) / 620), 0.4, 1)
	end
	UiScale.onResize(gui, fit)
	fit()

	-- Заголовок и «×».
	local head = Instance.new("Frame")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 56)
	head.LayoutOrder = 1
	head.Parent = window
	local title = MenuKit.label(head, t("ranks.title"), 30, Theme.Colors.Text, true)
	title.FontFace = Theme.FontHeavy
	local sub = MenuKit.label(head, t("ranks.subtitle"), 15, Theme.Colors.Muted)
	sub.Position = UDim2.fromOffset(0, 36)
	local close = MenuKit.button(head, "×", "normal")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(MenuKit.Touch, MenuKit.Touch)
	close.TextSize = 26

	-- Сейчас: знак, название, уровень, бойцы, опыт. Справа — следующая ступень.
	local now = Instance.new("Frame")
	now.Name = "Now"
	now.LayoutOrder = 2
	now.Size = UDim2.new(1, 0, 0, 150)
	now.BackgroundColor3 = Theme.Colors.Backdrop
	now.BorderSizePixel = 0
	now.Parent = window
	MenuKit.corner(now, 10)
	MenuKit.pad(now, 20, 18)
	local bigBadge = MenuKit.rankIcon(now, 1, 7)
	bigBadge.Position = UDim2.fromOffset(0, 1)
	local mine = Instance.new("Frame")
	mine.BackgroundTransparency = 1
	mine.Position = UDim2.fromOffset(136, 0)
	mine.Size = UDim2.new(0.62, -136, 1, 0)
	mine.Parent = now
	MenuKit.list(mine, 6)
	MenuKit.label(mine, t("ranks.now"), 13, Theme.Colors.Sky, true, 1)
	local mineName = MenuKit.label(mine, "", 30, Theme.Colors.Text, true, 2)
	mineName.FontFace = Theme.FontHeavy
	local mineLevel = MenuKit.label(mine, "", 16, Theme.Colors.Muted, false, 3)
	local xpBar = MenuKit.bar(mine, 10, Theme.Colors.Gold, 4)
	local mineXp = MenuKit.label(mine, "", 14, Theme.Colors.Muted, false, 5)

	local nextCard = Instance.new("Frame")
	nextCard.Name = "Next"
	nextCard.AnchorPoint = Vector2.new(1, 0)
	nextCard.Position = UDim2.fromScale(1, 0)
	nextCard.Size = UDim2.fromScale(0.36, 1)
	nextCard.BackgroundColor3 = Theme.Colors.PanelBg
	nextCard.BorderSizePixel = 0
	nextCard.Parent = now
	MenuKit.corner(nextCard, 8)
	MenuKit.pad(nextCard, 14, 10)
	local nextBadge = MenuKit.rankIcon(nextCard, 2, 4)
	nextBadge.Position = UDim2.fromOffset(0, 8)
	local nextText = Instance.new("Frame")
	nextText.BackgroundTransparency = 1
	nextText.Position = UDim2.fromOffset(78, 0)
	nextText.Size = UDim2.new(1, -78, 1, 0)
	nextText.Parent = nextCard
	MenuKit.list(nextText, 4)
	MenuKit.label(nextText, t("ranks.next"), 13, Theme.Colors.Sky, true, 1)
	local nextName = MenuKit.wrapLabel(nextText, "", 18, Theme.Colors.Text, 2)
	nextName.FontFace = Theme.FontBold
	local nextWhen = MenuKit.wrapLabel(nextText, "", 14, Theme.Colors.Gold, 3)

	-- Дорога ступеней.
	local road = Instance.new("Frame")
	road.Name = "Road"
	road.LayoutOrder = 3
	road.BackgroundTransparency = 1
	road.Size = UDim2.new(1, 0, 0, 180)
	road.Parent = window
	local count = Ranks.Count
	local step = (W - 56 - NODE_W) / math.max(1, count - 1)
	local lineY = 30 + 8 * NODE_BADGE -- середина знака
	local line = Instance.new("Frame")
	line.BackgroundColor3 = Theme.Colors.Slate
	line.BorderSizePixel = 0
	line.Position = UDim2.fromOffset(NODE_W / 2, lineY - 2)
	line.Size = UDim2.fromOffset(step * (count - 1), 4)
	line.Parent = road
	local done = Instance.new("Frame")
	done.BackgroundColor3 = Theme.Colors.Gold
	done.BorderSizePixel = 0
	done.Position = line.Position
	done.Size = UDim2.fromOffset(0, 4)
	done.Parent = road
	type Node = { badge: Frame, ring: Frame, ringStroke: UIStroke, name: TextLabel, level: TextLabel, you: TextLabel }
	local nodes: { Node } = {}
	for rank = 1, count do
		local x = (rank - 1) * step
		local ring = Instance.new("Frame")
		ring.Name = "Step" .. rank
		ring.Position = UDim2.fromOffset(x + NODE_W / 2 - 8 * NODE_BADGE - 8, 22)
		ring.Size = UDim2.fromOffset(16 * NODE_BADGE + 16, 16 * NODE_BADGE + 16)
		ring.BackgroundColor3 = Theme.Colors.PanelBg
		ring.BorderSizePixel = 0
		ring.Parent = road
		MenuKit.corner(ring, 10)
		local ringStroke = MenuKit.stroke(ring, Theme.Colors.Slate, 2)
		local badge = MenuKit.rankIcon(ring, rank, NODE_BADGE)
		badge.Position = UDim2.fromOffset(8, 8)
		local you = MenuKit.label(road, t("ranks.you"), 12, Theme.Colors.Backdrop, true)
		you.BackgroundTransparency = 0
		you.BackgroundColor3 = Theme.Colors.Gold
		you.AnchorPoint = Vector2.new(0.5, 0)
		you.Position = UDim2.fromOffset(x + NODE_W / 2, 0)
		MenuKit.pad(you, 8, 2)
		MenuKit.corner(you, 4)
		you.Visible = false
		local level = MenuKit.label(road, string.format(t("ranks.level"), Ranks.firstLevel(rank)), 13, nil, true)
		level.AnchorPoint = Vector2.new(0.5, 0)
		level.Position = UDim2.fromOffset(x + NODE_W / 2, 30 + 16 * NODE_BADGE + 22)
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.AnchorPoint = Vector2.new(0.5, 0)
		name.Position = UDim2.fromOffset(x + NODE_W / 2, 30 + 16 * NODE_BADGE + 42)
		name.Size = UDim2.fromOffset(NODE_W, 40)
		name.FontFace = Theme.Font
		name.TextSize = 12
		name.TextWrapped = true
		name.TextYAlignment = Enum.TextYAlignment.Top
		name.Text = t("rank." .. rank)
		name.Parent = road
		table.insert(
			nodes,
			{ badge = badge, ring = ring, ringStroke = ringStroke, name = name, level = level, you = you }
		)
	end

	-- Как растёт уровень.
	local how = MenuKit.wrapLabel(window, t("ranks.how"), 14, Theme.Colors.Muted, 4)
	how.TextXAlignment = Enum.TextXAlignment.Center

	local function draw()
		local p = cs.profile
		local level = if p ~= nil then p.level else 1
		local rank = Ranks.of(level)
		MenuKit.setRank(bigBadge, rank, 7)
		mineName.Text = t("rank." .. rank)
		mineName.TextColor3 = groupColor(rank)
		mineLevel.Text = string.format(t("ranks.levelLine"), level, t("rank.troops." .. rank))
		if p ~= nil and p.need > 0 then
			xpBar.set(p.xp / p.need)
			mineXp.Text = string.format(t("ranks.xp"), p.xp, p.need, level + 1)
		else
			xpBar.set(if p ~= nil then 1 else 0)
			mineXp.Text = if p ~= nil then t("menu.maxLevel") else ""
		end
		local nextAt = Ranks.nextAt(level)
		nextCard.Visible = nextAt ~= nil
		if nextAt ~= nil then
			MenuKit.setRank(nextBadge, rank + 1, 4)
			nextName.Text = t("rank." .. (rank + 1))
			nextWhen.Text = string.format(t("ranks.nextWhen"), nextAt, nextAt - level)
		end
		-- Дорога: пройденное — золотом до вашей ступени.
		done.Size = UDim2.fromOffset(step * (rank - 1), 4)
		for k, node in nodes do
			local reached = k <= rank
			node.you.Visible = k == rank
			node.ringStroke.Color = if k == rank
				then Theme.Colors.Gold
				elseif reached then groupColor(k)
				else Theme.Colors.Slate
			node.ringStroke.Thickness = if k == rank then 3 else 2
			node.ring.BackgroundColor3 = if k == rank then Theme.Colors.Backdrop else Theme.Colors.PanelBg
			for _, px in node.badge:GetChildren() do
				if px:IsA("Frame") then
					px.BackgroundTransparency = if reached then 0 else 0.65
				end
			end
			node.name.TextColor3 = if reached then Theme.Colors.Text else Theme.Colors.Muted
			node.level.TextColor3 = if k == rank then Theme.Colors.Gold else Theme.Colors.Muted
		end
	end

	local function toggle()
		window.Visible = not window.Visible
		if window.Visible then
			draw()
		end
	end
	Session.connect(close.Activated, function()
		window.Visible = false
	end)
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
		refresh = function()
			if window.Visible then
				draw()
			end
		end,
		window = window,
	}
end

return table.freeze(RanksPanel)
