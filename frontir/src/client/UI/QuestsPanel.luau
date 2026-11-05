--!strict
--[[
	QuestsPanel — задания дня и таблицы лидеров (GDD §11.5, этап 9г), клавиша J и кнопка справа сверху.
	- Три задания с прогрессом и наградой, жетон за все три, «новые через N ч».
	- Топ-10 побед за неделю и топ-10 рейтинга дуэлей, свой рейтинг. Своя строка — золотая.
	- Тосты «Задание выполнено» приходят через onShopEvent (сообщение quests).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type QuestsPanel = {
	refresh: () -> (),
	onQuests: (msg: any) -> (),
}

local QuestsPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local W = 480

local function label(parent: Instance, size: number, bold: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = if bold then Theme.FontBold else Theme.Font
	t.TextSize = size
	t.TextColor3 = Theme.Colors.Text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.TextWrapped = true
	t.RichText = true
	t.Parent = parent
	return t
end

function QuestsPanel.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang, toast: (text: string) -> ()): QuestsPanel
	local me = Players.LocalPlayer.UserId
	local gold, muted = Theme.Colors.Gold, Theme.Colors.Muted
	local function hex(c: Color3): string
		return "#" .. c:ToHex()
	end

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

	local window = Instance.new("Frame")
	window.Name = "Quests"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(W, 520)
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BorderSizePixel = 0
	window.Visible = false
	window.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = window
	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function fit()
		scale.Scale = math.clamp(math.min((gui.AbsoluteSize.X - 24) / W, (gui.AbsoluteSize.Y - 24) / 520), 0.5, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()
	local body = label(window, 13)
	body.Position = UDim2.fromOffset(12, 10)
	body.Size = UDim2.new(1, -24, 1, -20)

	local function questText(q: {
		kind: string,
		target: number,
		progress: number,
		done: boolean,
		medals: number,
		xp: number,
	}): string
		local name = string.format(Strings.get("quest." .. q.kind, lang), q.target)
		local mark = if q.done then "✓ " else ""
		local color = if q.done then hex(gold) else hex(Theme.Colors.Text)
		return string.format(
			'<font color="%s">%s%s</font>  %d/%d  <font color="%s">+%d 🏅, +%d %s</font>',
			color,
			mark,
			name,
			q.progress,
			q.target,
			hex(muted),
			q.medals,
			q.xp,
			Strings.get("quests.passXp", lang)
		)
	end
	local function board(title: string, list: { ClientState.LeaderEntry }): { string }
		local lines = { string.format('\n<font color="%s"><b>%s</b></font>', hex(gold), title) }
		if #list == 0 then
			table.insert(
				lines,
				string.format('<font color="%s">%s</font>', hex(muted), Strings.get("leaders.empty", lang))
			)
		end
		for k, e in list do
			local line = string.format("%d. %s — %s", k, e.name, Strings.formatInt(e.value))
			if e.userId == me then
				line = string.format('<font color="%s">%s</font>', hex(gold), line)
			end
			table.insert(lines, line)
		end
		return lines
	end

	local function draw()
		local p = cs.profile
		openButton.Visible = p ~= nil
		if p == nil or not window.Visible then
			return
		end
		local lines =
			{ string.format('<font color="%s"><b>%s</b></font>', hex(gold), Strings.get("quests.title", lang)) }
		for _, q in p.quests do
			table.insert(lines, questText(q))
		end
		table.insert(
			lines,
			string.format(
				'<font color="%s">%s</font>',
				hex(muted),
				string.format(
					Strings.get(if p.questsBonus then "quests.bonusDone" else "quests.bonus", lang),
					Config.Quests.AllDoneTokens,
					p.dayLeft // 3600
				)
			)
		)
		local leaders = cs.leaders or { weekly = {}, duel = {} }
		for _, l in board(Strings.get("leaders.weekly", lang), leaders.weekly) do
			table.insert(lines, l)
		end
		for _, l in board(Strings.get("leaders.duel", lang), leaders.duel) do
			table.insert(lines, l)
		end
		table.insert(lines, string.format(Strings.get("leaders.myElo", lang), p.elo))
		body.Text = table.concat(lines, "\n")
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
		refresh = draw,
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
