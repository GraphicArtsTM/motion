--!strict
--[[
	DevPanel — панель разработчика (F4). Только в Studio: панель создаётся, если RunService:IsStudio(), и шлёт
	команды в Remotes.Dev, который сервер создаёт тоже только в Studio. В опубликованной игре её нет.
	Действия: дать себе войска / людей / деньги, время ×5, выбранный бот присылает союз / пакт / торговлю /
	требование или объявляет войну, мгновенная война и мир с выбранным ботом, Совет сейчас, к концу матча.
	Этап 7а: туман вкл/выкл (для себя), стабильность своих провинций 10 / 100, восстание сейчас.
	Этап 7б-1: «Порт и флот» (порт, транспорт и эсминец себе), «Бот: десант на вас».
	Этап 7б-2: «Аэродром и авиация» (аэродром, истребитель и бомбардировщик себе), «Бот: налёт на вас».
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioCues = require(Shared:WaitForChild("AudioCues"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))
local Audio = require(script.Parent.Parent:WaitForChild("Audio"))

type ClientState = ClientState.ClientState

export type DevPanel = {
	onDev: (msg: any) -> (),
}

local DevPanel = {}

local ROW = 30

function DevPanel.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang, selfCheck: (() -> ())?): DevPanel?
	if not RunService:IsStudio() then
		return nil
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local devEvent = remotes:WaitForChild("Dev", 10) :: RemoteEvent?
	if devEvent == nil then
		return nil
	end
	local event = devEvent :: RemoteEvent

	local panel = Instance.new("Frame")
	panel.Name = "DevPanel"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 12, 0.5, 0)
	panel.Size = UDim2.fromOffset(250, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Theme.Colors.PanelBg
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 20
	panel.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Alert
	stroke.Thickness = 2
	stroke.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = panel

	local order = 0
	local function text(t: string): TextLabel
		order += 1
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.RichText = true
		l.Size = UDim2.new(1, 0, 0, 22)
		l.FontFace = Theme.FontBold
		l.TextSize = 14
		l.TextColor3 = Theme.Colors.Alert
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = t
		l.LayoutOrder = order
		l.ZIndex = 21
		l.Parent = panel
		return l
	end
	local function button(t: string, onClick: () -> ()): TextButton
		order += 1
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, 0, 0, ROW)
		b.BackgroundColor3 = Theme.Colors.Backdrop
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.RichText = true
		b.FontFace = Theme.Font
		b.TextSize = 14
		b.TextColor3 = Theme.Colors.Text
		b.Text = t
		b.LayoutOrder = order
		b.ZIndex = 21
		Session.connect(b.Activated, onClick)
		b.Parent = panel
		return b
	end
	local function fire(action: string, arg: any)
		event:FireServer(action, arg)
	end

	text(Strings.get("dev.title", lang))
	-- Самопроверка (сводная правка, часть 1): шаги и итог — в Output.
	if selfCheck ~= nil then
		button(Strings.get("dev.selfCheck", lang), selfCheck)
	end
	local dev = Config.Dev
	button(string.format(Strings.get("dev.grantForces", lang), Strings.formatInt(dev.GrantForces)), function()
		fire("grant", "forces")
	end)
	button(string.format(Strings.get("dev.grantPeople", lang), Strings.formatInt(dev.GrantPeople)), function()
		fire("grant", "people")
	end)
	button(string.format(Strings.get("dev.grantMoney", lang), Strings.formatInt(dev.GrantMoney)), function()
		fire("grant", "money")
	end)
	local speedButton = button(string.format(Strings.get("dev.speed", lang), dev.FastSpeed), function()
		fire("speed", nil)
	end)

	-- Выбор бота: ◀ имя ▶.
	local bot: number? = nil
	local function bots(): { number }
		local out: { number } = {}
		for id, n in cs.nations do
			if n.alive and n.isBot and id ~= cs.myNation then
				table.insert(out, id)
			end
		end
		table.sort(out)
		return out
	end
	order += 1
	local selector = Instance.new("Frame")
	selector.BackgroundTransparency = 1
	selector.Size = UDim2.new(1, 0, 0, ROW)
	selector.LayoutOrder = order
	selector.Parent = panel
	local prev = Instance.new("TextButton")
	prev.Size = UDim2.fromOffset(ROW, ROW)
	prev.BackgroundColor3 = Theme.Colors.Backdrop
	prev.BorderSizePixel = 0
	prev.FontFace = Theme.FontBold
	prev.TextSize = 16
	prev.TextColor3 = Theme.Colors.Text
	prev.Text = "◀"
	prev.ZIndex = 21
	prev.Parent = selector
	local next = prev:Clone()
	next.Text = "▶"
	next.AnchorPoint = Vector2.new(1, 0)
	next.Position = UDim2.fromScale(1, 0)
	next.Parent = selector
	local botLabel = Instance.new("TextLabel")
	botLabel.BackgroundTransparency = 1
	botLabel.RichText = true
	botLabel.Position = UDim2.fromOffset(ROW + 4, 0)
	botLabel.Size = UDim2.new(1, -2 * ROW - 8, 1, 0)
	botLabel.FontFace = Theme.FontBold
	botLabel.TextSize = 14
	botLabel.TextColor3 = Theme.Colors.Text
	botLabel.TextTruncate = Enum.TextTruncate.AtEnd
	botLabel.ZIndex = 21
	botLabel.Parent = selector

	local function drawBot()
		local list = bots()
		if bot == nil or table.find(list, bot :: number) == nil then
			bot = list[1]
		end
		local n = if bot ~= nil then cs.nations[bot] else nil
		if n == nil then
			botLabel.Text = Strings.get("dev.noBot", lang)
			return
		end
		local c = if n.colorIndex >= 1 then NationColors.Colors[n.colorIndex] else nil
		local color = if c ~= nil then string.format("#%02x%02x%02x", c.r, c.g, c.b) else "#ffffff"
		botLabel.Text = string.format(
			Strings.get("dev.bot", lang),
			string.format('<font color="%s">%s</font>', color, if lang == "en" then n.nameEn else n.name)
		)
	end
	local function step(delta: number)
		local list = bots()
		if #list == 0 then
			return
		end
		local k = (table.find(list, bot or list[1]) or 1) + delta
		bot = list[(k - 1) % #list + 1]
		drawBot()
	end
	Session.connect(prev.Activated, function()
		step(-1)
	end)
	Session.connect(next.Activated, function()
		step(1)
	end)

	local function withBot(action: string, arg: (id: number) -> any)
		return function()
			if bot ~= nil then
				fire(action, arg(bot))
			end
		end
	end
	local function offer(kind: string)
		return withBot("offer", function(id: number): any
			return { bot = id, offer = kind }
		end)
	end
	local function same(id: number): any
		return id
	end
	button(Strings.get("dev.botAlliance", lang), offer("alliance"))
	button(Strings.get("dev.botPact", lang), offer("pact"))
	button(Strings.get("dev.botTrade", lang), offer("trade"))
	button(Strings.get("dev.botDemand", lang), offer("demand"))
	button(Strings.get("dev.botWar", lang), withBot("botWar", same))
	button(Strings.get("dev.war", lang), withBot("war", same))
	button(Strings.get("dev.peace", lang), withBot("peace", same))
	button(Strings.get("dev.council", lang), function()
		fire("council", nil)
	end)
	button(Strings.get("dev.end", lang), function()
		fire("end", nil)
	end)

	-- Этап 7а: туман и стабильность (§6.10, §6.11).
	local fogButton = button(Strings.get("dev.fogOn", lang), function()
		fire("fog", nil)
	end)
	order += 1
	local pair = Instance.new("Frame")
	pair.BackgroundTransparency = 1
	pair.Size = UDim2.new(1, 0, 0, ROW)
	pair.LayoutOrder = order
	pair.Parent = panel
	local pairLayout = Instance.new("UIListLayout")
	pairLayout.FillDirection = Enum.FillDirection.Horizontal
	pairLayout.Padding = UDim.new(0, 4)
	pairLayout.Parent = pair
	for _, high in { false, true } do
		local b = button(
			string.format(
				Strings.get(if high then "dev.stabilityHigh" else "dev.stabilityLow", lang),
				if high then dev.StabilityHigh else dev.StabilityLow
			),
			function()
				fire("stability", if high then "high" else "low")
			end
		)
		b.Size = UDim2.new(0.5, -2, 1, 0)
		b.Parent = pair
	end
	button(Strings.get("dev.revolt", lang), function()
		fire("revolt", nil)
	end)
	-- Этап 7б-1: флот (§6.12).
	button(Strings.get("dev.navy", lang), function()
		fire("navy", nil)
	end)
	button(Strings.get("dev.botLanding", lang), withBot("botLanding", same))
	-- Этап 7б-2: авиация (§6.13).
	button(Strings.get("dev.airForce", lang), function()
		fire("airForce", nil)
	end)
	button(Strings.get("dev.botRaid", lang), withBot("botRaid", same))
	-- Этап 10б: звуки и музыка (§13) — только у этого клиента, без сервера.
	local soundTurn, musicTurn = 0, 0
	local soundButton: TextButton
	soundButton = button(Strings.get("dev.nextSound", lang), function()
		soundTurn = soundTurn % #AudioCues.SoundNames + 1
		local name = AudioCues.SoundNames[soundTurn]
		Audio.play(name)
		soundButton.Text = string.format(Strings.get("dev.soundName", lang), name)
	end)
	local musicButton: TextButton
	musicButton = button(Strings.get("dev.nextMusic", lang), function()
		musicTurn = musicTurn % #AudioCues.MusicNames + 1
		local name = AudioCues.MusicNames[musicTurn]
		Audio.music(name)
		musicButton.Text = string.format(Strings.get("dev.musicName", lang), name)
	end)
	-- Этап 7г: события и ракеты (§6.16, §6.9).
	button(Strings.get("dev.eventNow", lang), function()
		fire("eventNow", nil)
	end)
	button(Strings.get("dev.silo", lang), function()
		fire("silo", nil)
	end)
	button(Strings.get("dev.botMissile", lang), withBot("botMissile", same))
	-- Этап 7в-2: генералы (§6.15).
	button(Strings.get("dev.resetCooldowns", lang), function()
		fire("resetCooldowns", nil)
	end)
	button(Strings.get("dev.nextCommander", lang), function()
		fire("nextCommander", nil)
	end)
	button(Strings.get("dev.botAbility", lang), withBot("botAbility", same))
	-- Этап 7в-1: технологии (§6.14).
	button(Strings.get("dev.researchAll", lang), function()
		fire("researchAll", nil)
	end)
	button(Strings.get("dev.finishResearch", lang), function()
		fire("finishResearch", nil)
	end)
	-- Этап 8а: режим без голосования (§5.1) — по кругу; в лобби — сразу, иначе — со следующего матча.
	local modeButton = button(string.format(Strings.get("dev.mode", lang), "—"), function()
		fire("mode", nil)
	end)
	-- Этап 9а: профиль — жетоны штаба и опыт (§11.2).
	button(string.format(Strings.get("dev.tokens", lang), Config.Dev.GrantTokens), function()
		fire("tokens", nil)
	end)
	button(string.format(Strings.get("dev.xp", lang), Config.Dev.GrantXp), function()
		fire("xp", nil)
	end)
	button(string.format(Strings.get("dev.medals", lang), Config.Dev.GrantMedals), function()
		fire("medals", nil)
	end)
	-- Этап 8в: «Потоп» — ступень воды сейчас (§5.3).
	button(Strings.get("dev.flood", lang), function()
		fire("flood", nil)
	end)
	-- Этап 8б: карта следующего матча без голосования (§5.2) — по кругу пула.
	local mapButton = button(string.format(Strings.get("dev.map", lang), "—"), function()
		fire("map", nil)
	end)

	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.F4 then
			panel.Visible = not panel.Visible
			if panel.Visible then
				drawBot()
			end
		end
	end)

	return {
		onDev = function(msg: any)
			if type(msg.fog) == "boolean" then
				fogButton.Text = Strings.get(if msg.fog then "dev.fogOn" else "dev.fogOff", lang)
			end
			if type(msg.map) == "string" then
				mapButton.Text = string.format(Strings.get("dev.map", lang), Strings.get("map." .. msg.map, lang))
			end
			if type(msg.mode) == "string" then
				modeButton.Text = string.format(Strings.get("dev.mode", lang), Strings.get("mode." .. msg.mode, lang))
			end
			if type(msg.speed) == "number" then
				speedButton.Text = string.format(
					Strings.get(if msg.speed > 1 then "dev.speedOn" else "dev.speed", lang),
					Config.Dev.FastSpeed
				)
			end
		end,
	}
end

return table.freeze(DevPanel)
