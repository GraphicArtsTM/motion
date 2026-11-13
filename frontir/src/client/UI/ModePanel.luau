--!strict
--[[
	ModePanel — режим матча (GDD §5.1, этап 8а).
	- Лобби: сверху три карточки голосования (имя режима, описание, «голосов: N»; режим недели подписан);
	  нажатие — голос (намерение modeVote), свой голос — золотая рамка. Если игрок в лобби один — строка
	  «Против ботов — сложность» (намерение difficulty).
	- Игра «Против ботов»: кнопки «Пауза (P)» и «Скорость ×2» (намерение solo); P — пауза с клавиатуры.
	Решения — на сервере; панель только показывает info и шлёт намерения.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type ModePanel = {
	refresh: () -> (), -- пришло info
	voteFrame: Frame, -- §15и: на время лобби переезжает в экран лобби
	mapVoteFrame: Frame, -- §15к: голосование за карту — тоже в экране лобби
	-- §15ц Ц3: пауза и ×2 «одному» — пунктами меню игры (Tab); P — пауза.
	soloOn: () -> boolean,
	togglePause: () -> (),
	toggleFast: () -> (),
	pauseText: () -> string,
	fastText: () -> string,
}

local ModePanel = {}

local CARD_W, CARD_H = 200, 70
local GAP = 6
local TOP = 96 -- под баннером HUD
local BUTTON = Config.Render.MinTouchTargetPx
local MAX_CARDS = 4 -- три режима и «Дуэль» (§5.2)

local function stroke(parent: Instance, color: Color3): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = Theme.BorderPx
	s.Parent = parent
	return s
end

local function text(parent: Instance, size: number, bold: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextWrapped = true
	t.FontFace = if bold then Theme.FontBold else Theme.Font
	t.TextSize = size
	t.TextColor3 = Theme.Colors.Text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Parent = parent
	return t
end

local function button(parent: Instance, w: number, h: number): (TextButton, UIStroke)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(w, h)
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BackgroundTransparency = 0.05
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.FontFace = Theme.Font
	b.TextSize = 14
	b.TextColor3 = Theme.Colors.Text
	b.Text = ""
	b.Parent = parent
	return b, stroke(b, Theme.Colors.PanelBorder)
end

function ModePanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> ()
): ModePanel
	-- Голосование (лобби).
	local vote = Instance.new("Frame")
	vote.Name = "ModeVote"
	vote.AnchorPoint = Vector2.new(0.5, 0)
	vote.Position = UDim2.new(0.5, 0, 0, TOP)
	vote.Size = UDim2.fromOffset(3 * CARD_W + 2 * GAP, 24 + CARD_H + 8 + BUTTON)
	vote.BackgroundTransparency = 1
	vote.Visible = false
	vote.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = vote
	local function fit()
		scale.Scale = math.clamp((UiScale.size(gui).X - 24) / (MAX_CARDS * CARD_W + (MAX_CARDS - 1) * GAP), 0.5, 1)
	end
	UiScale.onResize(gui, fit)
	fit()
	local title = text(vote, 15, true)
	title.Size = UDim2.new(1, 0, 0, 20)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextColor3 = Theme.Colors.Gold
	title.Text = Strings.get("mode.vote.title", lang)

	type Card = { button: TextButton, edge: UIStroke, name: TextLabel, body: TextLabel, count: TextLabel }
	local cards: { Card } = {}
	for k = 1, MAX_CARDS do
		local b, edge = button(vote, CARD_W, CARD_H)
		b.Position = UDim2.fromOffset((k - 1) * (CARD_W + GAP), 24)
		local name = text(b, 15, true)
		name.Position = UDim2.fromOffset(8, 4)
		name.Size = UDim2.new(1, -16, 0, 18)
		local body = text(b, 12)
		body.Position = UDim2.fromOffset(8, 24)
		body.Size = UDim2.new(1, -16, 0, 30)
		body.TextColor3 = Theme.Colors.Muted
		local count = text(b, 12)
		count.Position = UDim2.fromOffset(8, CARD_H - 18)
		count.Size = UDim2.new(1, -16, 0, 14)
		count.TextColor3 = Theme.Colors.Sky
		Session.connect(b.Activated, function()
			local mode = cs.mode.options[k]
			if mode ~= nil then
				send("modeVote", { mode = mode })
			end
		end)
		cards[k] = { button = b, edge = edge, name = name, body = body, count = count }
	end

	-- Сложность ботов (один игрок в лобби).
	local levels = Instance.new("Frame")
	levels.Name = "Difficulty"
	levels.Position = UDim2.fromOffset(0, 24 + CARD_H + 8)
	levels.Size = UDim2.new(1, 0, 0, BUTTON)
	levels.BackgroundTransparency = 1
	levels.Parent = vote
	local levelLabel = text(levels, 13, true)
	levelLabel.Size = UDim2.fromOffset(CARD_W, BUTTON)
	levelLabel.TextYAlignment = Enum.TextYAlignment.Center
	levelLabel.Text = Strings.get("mode.difficulty", lang)
	local levelButtons: { [string]: { button: TextButton, edge: UIStroke } } = {}
	local LEVEL_W = math.floor((2 * CARD_W + GAP - 2 * GAP) / 3)
	for k, raw in Types.BotLevels do
		local level: Types.BotLevel = raw :: any
		local b, edge = button(levels, LEVEL_W, BUTTON)
		b.Position = UDim2.fromOffset(CARD_W + GAP + (k - 1) * (LEVEL_W + GAP), 0)
		b.Text = Strings.get("mode.level." .. level, lang)
		Session.connect(b.Activated, function()
			send("difficulty", { level = level })
		end)
		levelButtons[level] = { button = b, edge = edge }
	end

	-- Голосование за карту (§15к: в лобби, рядом с режимом; экран лобби забирает рамку к себе).
	local MAP_CARDS = Config.MapVote.Options
	local MAP_H = 52
	local mapVote = Instance.new("Frame")
	mapVote.Name = "MapVote"
	mapVote.AnchorPoint = Vector2.new(0.5, 1)
	mapVote.Position = UDim2.new(0.5, 0, 1, -(BUTTON + 24))
	mapVote.Size = UDim2.fromOffset(MAP_CARDS * CARD_W + (MAP_CARDS - 1) * GAP, 24 + MAP_H)
	mapVote.BackgroundTransparency = 1
	mapVote.Visible = false
	mapVote.Parent = gui
	local mapScale = Instance.new("UIScale")
	mapScale.Parent = mapVote
	local function fitMap()
		mapScale.Scale = math.clamp((UiScale.size(gui).X - 24) / (MAP_CARDS * CARD_W + (MAP_CARDS - 1) * GAP), 0.5, 1)
	end
	UiScale.onResize(gui, fitMap)
	fitMap()
	local mapTitle = text(mapVote, 15, true)
	mapTitle.Size = UDim2.new(1, 0, 0, 20)
	mapTitle.TextXAlignment = Enum.TextXAlignment.Center
	mapTitle.TextColor3 = Theme.Colors.Gold
	mapTitle.Text = Strings.get("mapVote.title", lang)
	local mapCards: { Card } = {}
	for k = 1, MAP_CARDS do
		local b, edge = button(mapVote, CARD_W, MAP_H)
		b.Position = UDim2.fromOffset((k - 1) * (CARD_W + GAP), 24)
		local name = text(b, 15, true)
		name.Position = UDim2.fromOffset(8, 4)
		name.Size = UDim2.new(0.6, -8, 0, 18)
		local body = text(b, 12)
		body.Position = UDim2.fromOffset(8, 26)
		body.Size = UDim2.new(1, -16, 0, 14)
		body.TextColor3 = Theme.Colors.Muted
		local count = text(b, 12)
		count.Position = UDim2.new(0.6, 0, 0, 6)
		count.Size = UDim2.new(0.4, -8, 0, 14)
		count.TextXAlignment = Enum.TextXAlignment.Right
		count.TextColor3 = Theme.Colors.Sky
		Session.connect(b.Activated, function()
			local mv = cs.mapVote
			local id = if mv ~= nil then mv.options[k] else nil
			if id ~= nil then
				send("mapVote", { map = id })
			end
		end)
		mapCards[k] = { button = b, edge = edge, name = name, body = body, count = count }
	end

	-- Пауза и ×2 («Против ботов», игра). §15ц Ц3: кнопки — пунктами меню игры (Tab) и клавишей P; на паузе
	-- сверху по центру — плашка «ПАУЗА · P — продолжить» (нажатие — продолжить).
	local solo = Instance.new("TextButton")
	solo.Name = "Solo"
	solo.AnchorPoint = Vector2.new(0.5, 0)
	solo.Position = UDim2.new(0.5, 0, 0, TOP)
	solo.Size = UDim2.fromOffset(0, BUTTON)
	solo.AutomaticSize = Enum.AutomaticSize.X
	solo.BackgroundColor3 = Theme.Colors.PanelBg
	solo.BorderSizePixel = 0
	solo.FontFace = Theme.FontBold
	solo.TextSize = 18
	solo.TextColor3 = Theme.Colors.Gold
	solo.Visible = false
	solo.Parent = gui
	local soloPad = Instance.new("UIPadding")
	soloPad.PaddingLeft = UDim.new(0, 18)
	soloPad.PaddingRight = UDim.new(0, 18)
	soloPad.Parent = solo
	local soloEdge = Instance.new("UIStroke")
	soloEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	soloEdge.Color = Theme.Colors.Gold
	soloEdge.Thickness = 2
	soloEdge.Parent = solo
	local function soloOn(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.mode.solo and cs.phase == "Play" and me ~= nil
	end
	local function togglePause()
		if cs.mode.solo and cs.phase == "Play" then
			send("solo", { pause = not cs.mode.paused, fast = cs.mode.fast })
		end
	end
	local function toggleFast()
		if cs.mode.solo and cs.phase == "Play" then
			send("solo", { pause = false, fast = not cs.mode.fast })
		end
	end
	Session.connect(solo.Activated, togglePause)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.P then
			togglePause()
		end
	end)

	local function refresh()
		local info = cs.mode
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		local voting = me ~= nil and (cs.phase == "Lobby" or cs.phase == "Waiting") and #info.options > 0
		vote.Visible = voting
		if voting then
			local n = #info.options
			vote.Size = UDim2.fromOffset(n * CARD_W + (n - 1) * GAP, 24 + CARD_H + 8 + BUTTON)
			for k, card in cards do
				local mode = info.options[k]
				card.button.Visible = mode ~= nil
				if mode ~= nil then
					card.name.Text = Strings.get("mode." .. mode, lang)
					local desc = Strings.get("mode.desc." .. mode, lang)
					if k == 3 then
						desc = Strings.get("mode.vote.weekly", lang) .. " · " .. desc
					end
					card.body.Text = desc
					card.count.Text = string.format(Strings.get("mode.vote.count", lang), info.counts[k] or 0)
					local mine = info.myVote == mode
					card.edge.Color = if mine then Theme.Colors.Gold else Theme.Colors.PanelBorder
					card.edge.Thickness = if mine then 2 else Theme.BorderPx
				end
			end
			levels.Visible = info.humans == 1
			for level, lb in levelButtons do
				local chosen = info.difficulty == level
				lb.edge.Color = if chosen then Theme.Colors.Gold else Theme.Colors.PanelBorder
				lb.edge.Thickness = if chosen then 2 else Theme.BorderPx
			end
		end
		-- Голосование за карту в лобби (§15к).
		local mv = cs.mapVote
		mapVote.Visible = mv ~= nil and cs.phase == "Lobby" and me ~= nil
		if mv ~= nil and mapVote.Visible then
			for k, card in mapCards do
				local id = mv.options[k]
				card.button.Visible = id ~= nil
				if id ~= nil then
					card.name.Text = Strings.get("map." .. id, lang)
					card.body.Text = if k == 1 then Strings.get("mapVote.current", lang) else ""
					card.count.Text = string.format(Strings.get("mode.vote.count", lang), mv.counts[k] or 0)
					local mine = mv.myVote == id
					card.edge.Color = if mine then Theme.Colors.Gold else Theme.Colors.PanelBorder
					card.edge.Thickness = if mine then 2 else Theme.BorderPx
				end
			end
		end
		solo.Visible = soloOn() and info.paused
		solo.Text = Strings.get("solo.paused", lang)
	end

	return {
		refresh = refresh,
		voteFrame = vote,
		mapVoteFrame = mapVote,
		soloOn = soloOn,
		togglePause = togglePause,
		toggleFast = toggleFast,
		pauseText = function(): string
			return Strings.get(if cs.mode.paused then "solo.resume" else "solo.pause", lang)
		end,
		fastText = function(): string
			return Strings.get(if cs.mode.fast then "solo.normal" else "solo.fast", lang)
		end,
	}
end

return table.freeze(ModePanel)
