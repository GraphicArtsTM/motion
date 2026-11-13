--!strict
--[[
	QuestsPanel — задания дня и таблицы лидеров (GDD §11.5, этап 9г), клавиша J и кнопка справа сверху.
	- Три задания с прогрессом и наградой, жетон за все три, «новые через N ч».
	- Топ-10 побед за неделю и топ-10 рейтинга дуэлей, свой рейтинг. Своя строка — золотая.
	- Тосты «Задание выполнено» приходят через onShopEvent (сообщение quests).
	§15л ч.9: витрина CardKit — задания карточками с картинкой и полосой, лидеры — места 1–3 золото/серебро/бронза.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type QuestsPanel = {
	button: GuiButton, -- §15з: кнопка прячется в док
	refresh: () -> (),
	onQuests: (msg: any) -> (),
	-- Самопроверка (сводная правка, часть 1): открыть/закрыть окно и узнать, открыто ли.
	toggle: () -> (),
	isOpen: () -> boolean,
}

local QuestsPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx

function QuestsPanel.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang, toast: (text: string) -> ()): QuestsPanel
	local me = Players.LocalPlayer.UserId

	local openButton = Instance.new("TextButton")
	openButton.AnchorPoint = Vector2.new(1, 0)
	openButton.Position = UDim2.new(1, -12, 0, 124 + 2 * BUTTON + 30)
	openButton.Size = UDim2.fromOffset(220, BUTTON)
	openButton.BackgroundColor3 = Theme.Colors.PanelBg
	openButton.BorderSizePixel = 0
	openButton.FontFace = Theme.FontBold
	openButton.TextSize = 13
	openButton.TextColor3 = Theme.Colors.Text
	openButton.Text = Strings.get("quests.open", lang)
	openButton.Parent = gui

	-- §15л ч.9: витрина CardKit — слева задания дня карточками (картинка, полоса, награда), справа таблицы лидеров.
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local win = CardKit.window(
		gui,
		"Quests",
		t("quests.titleBig"),
		t("quests.subtitle"),
		900,
		580,
		{},
		{ main = "list" }
	)
	local window = win.frame
	local tokensChip = CardKit.chip(win.chips, "hint", 1)
	local page = win.page("main")
	local cols = Instance.new("Frame")
	cols.BackgroundTransparency = 1
	cols.Size = UDim2.new(1, 0, 0, 460)
	cols.Parent = page
	local left = MenuKit.box(cols, "Quests")
	left.AutomaticSize = Enum.AutomaticSize.None
	left.Size = UDim2.new(0.56, -8, 1, 0)
	MenuKit.list(left, 10)
	local right = MenuKit.box(cols, "Leaders")
	right.AutomaticSize = Enum.AutomaticSize.None
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.fromScale(1, 0)
	right.Size = UDim2.new(0.44, -8, 1, 0)
	MenuKit.list(right, 8)

	-- Три задания: строки пересоздаются, когда меняется вид задания (картинка — по виду).
	type QuestRow = {
		kind: string,
		frame: Frame,
		edge: UIStroke,
		name: TextLabel,
		bar: MenuKit.Bar,
		count: TextLabel,
		reward: TextLabel,
	}
	local questRows: { QuestRow? } = {}
	local function questRow(k: number, kind: string): QuestRow
		local old = questRows[k]
		if old ~= nil and old.kind == kind then
			return old
		end
		if old ~= nil then
			old.frame:Destroy()
		end
		local f, body, edge = CardKit.row(left, "quest." .. kind, 150, 112, k)
		MenuKit.list(body, 6)
		local name = MenuKit.label(body, "", 16, Theme.Colors.Text, true, 1)
		local bar = MenuKit.bar(body, 10, Theme.Colors.Sky, 2)
		local count = MenuKit.label(body, "", 13, Theme.Colors.Muted, true, 3)
		local reward = MenuKit.label(body, "", 13, Theme.Colors.Gold, true, 4)
		local row: QuestRow =
			{ kind = kind, frame = f, edge = edge, name = name, bar = bar, count = count, reward = reward }
		questRows[k] = row
		return row
	end
	local bonus = MenuKit.wrapLabel(left, "", 13, Theme.Colors.Muted, 10)

	-- Таблицы лидеров: значок места (1–3 — золото, серебро, бронза), имя, число; своя строка — золотая рамка.
	type BoardRow = { frame: Frame, edge: UIStroke, badge: TextLabel, name: TextLabel, value: TextLabel }
	local function board(titleKey: string, order: number): { BoardRow }
		MenuKit.label(right, t(titleKey), 16, Theme.Colors.Gold, true, order)
		local out: { BoardRow } = {}
		for k = 1, 5 do
			local f = Instance.new("Frame")
			f.LayoutOrder = order + k
			f.Size = UDim2.new(1, 0, 0, 30)
			f.BackgroundColor3 = Theme.Colors.Backdrop
			f.BorderSizePixel = 0
			f.Parent = right
			local edge = MenuKit.stroke(f, Theme.Colors.PanelBorder, 2)
			local badge = MenuKit.label(f, tostring(k), 14, Theme.color("Ink"), true)
			badge.AutomaticSize = Enum.AutomaticSize.None
			badge.Size = UDim2.fromOffset(30, 30)
			badge.TextXAlignment = Enum.TextXAlignment.Center
			badge.BackgroundTransparency = 0
			badge.BackgroundColor3 =
				Theme.color(if k == 1 then "Gold" elseif k == 2 then "Mist" elseif k == 3 then "Orange" else "Slate")
			local name = MenuKit.label(f, "", 14, Theme.Colors.Text, false)
			name.AutomaticSize = Enum.AutomaticSize.None
			name.Position = UDim2.fromOffset(40, 0)
			name.Size = UDim2.new(1, -120, 1, 0)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local value = MenuKit.label(f, "", 14, Theme.Colors.Gold, true)
			value.AutomaticSize = Enum.AutomaticSize.None
			value.AnchorPoint = Vector2.new(1, 0)
			value.Position = UDim2.new(1, -8, 0, 0)
			value.Size = UDim2.new(0, 70, 1, 0)
			value.TextXAlignment = Enum.TextXAlignment.Right
			table.insert(out, { frame = f, edge = edge, badge = badge, name = name, value = value })
		end
		return out
	end
	local weekly = board("leaders.weekly", 10)
	local duel = board("leaders.duel", 30)
	local myElo = MenuKit.label(right, "", 14, Theme.Colors.Sky, true, 50)

	local function fill(rows: { BoardRow }, list: { ClientState.LeaderEntry })
		for k, row in rows do
			local e = list[k]
			row.frame.Visible = e ~= nil or k == 1
			if e ~= nil then
				row.name.Text = e.name
				row.value.Text = Strings.formatInt(e.value)
				row.edge.Color = if e.userId == me then Theme.Colors.Gold else Theme.Colors.PanelBorder
				row.name.TextColor3 = if e.userId == me then Theme.Colors.Gold else Theme.Colors.Text
			else
				row.name.Text = t("leaders.empty")
				row.value.Text = ""
				row.edge.Color = Theme.Colors.PanelBorder
				row.name.TextColor3 = Theme.Colors.Muted
			end
		end
	end

	local function draw()
		local p = cs.profile
		openButton.Visible = p ~= nil
		if p == nil or not window.Visible then
			return
		end
		tokensChip.Text = tostring(p.tokens)
		for k, q in p.quests do
			local row = questRow(k, q.kind)
			row.name.Text = (if q.done then "✔ " else "")
				.. string.format(Strings.get("quest." .. q.kind, lang), q.target)
			row.name.TextColor3 = if q.done then Theme.Colors.Gold else Theme.Colors.Text
			row.bar.set(q.progress / math.max(1, q.target))
			row.bar.fill.BackgroundColor3 = if q.done then Theme.Colors.Good else Theme.Colors.Sky
			row.count.Text = string.format("%d / %d", math.min(q.progress, q.target), q.target)
			row.reward.Text = string.format(t("quests.reward"), q.medals, q.xp)
			row.edge.Color = if q.done then Theme.Colors.Gold else Theme.Colors.PanelBorder
		end
		for k = #p.quests + 1, #questRows do
			local row = questRows[k]
			if row ~= nil then
				row.frame.Visible = false
			end
		end
		bonus.Text = string.format(
			t(if p.questsBonus then "quests.bonusDone" else "quests.bonus"),
			Config.Quests.AllDoneTokens,
			p.dayLeft // 3600
		)
		local leaders = cs.leaders or { weekly = {}, duel = {} }
		fill(weekly, leaders.weekly)
		fill(duel, leaders.duel)
		myElo.Text = string.format(t("leaders.myElo"), p.elo)
	end

	local function toggle()
		window.Visible = not window.Visible
		draw()
	end
	Session.connect(openButton.Activated, toggle)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.J then
			toggle()
		end
	end)

	return {
		button = openButton,
		refresh = draw,
		toggle = toggle,
		isOpen = function(): boolean
			return window.Visible
		end,
		onQuests = function(msg: any)
			for _, d in msg.done or {} do
				local row = Config.Quests.Pool[d.pool]
				if row ~= nil then
					toast(
						string.format(
							Strings.get("quests.done", lang),
							string.format(Strings.get("quest." .. row.kind, lang), row.target),
							d.medals
						)
					)
				end
			end
			if (msg.tokens or 0) > 0 then
				toast(string.format(Strings.get("quests.allDone", lang), msg.tokens))
			end
		end,
	}
end

return table.freeze(QuestsPanel)
