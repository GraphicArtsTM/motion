--!strict
--[[
	WarPanel — война и мир в интерфейсе (GDD §6.7а, §10):
	- баннер сверху под фазой: «ВОЙНА: A — B» в цветах стран (или «МОБИЛИЗАЦИЯ … · N с»), полоска перевеса
	  (вся сила сторон), земля, взятая в этой войне, и потери обеих сторон; кнопки «К фронту» и «Мир»;
	  несколько войн — стрелки ◀ ▶;
	- на вас напали — баннер мигает красным, сирена (Audio, пока заглушка), строка в ленте (MatchHud);
	- нажатие на страну без войны (MatchHud → offerDeclare) — окно «Объявить войну» (после мира — «Мир: ещё N с»);
	- «Мир» — окно условий: белый мир, забрать захваченное, капитуляция (неактивна до этапа 6);
	- предложение мира от врага — окно «X предлагает мир: … · N с» с «Принять» / «Отклонить».
	Все кнопки от 44 px (телефоны). Esc закрывает окна.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Protocol = require(Shared:WaitForChild("Net"):WaitForChild("Protocol"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Audio = require(script.Parent.Parent:WaitForChild("Audio"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type WarPanel = {
	refresh: () -> (),
	update: (now: number) -> (),
	offerDeclare: (target: number) -> (),
	onEvents: (events: { any }) -> (),
}

local WarPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local WIDTH = 420

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

local function escape(s: string): string
	return (
		string.gsub(s, "[&<>\"']", {
			["&"] = "&amp;",
			["<"] = "&lt;",
			[">"] = "&gt;",
			['"'] = "&quot;",
			["'"] = "&apos;",
		})
	)
end

local function panel(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Theme.Colors.PanelBg
	f.BackgroundTransparency = 0.1
	f.BorderSizePixel = 0
	f.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = f
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = f
	f.Parent = parent
	return f
end

local function label(parent: Instance, size: number, order: number): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.RichText = true
	t.TextWrapped = true
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.fromScale(1, 0)
	t.FontFace = Theme.Font
	t.TextSize = size
	t.TextColor3 = Theme.Colors.Text
	t.LayoutOrder = order
	t.Parent = parent
	return t
end

local function button(parent: Instance, text: string, width: number, height: number?): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, height or BUTTON)
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.RichText = true
	b.TextWrapped = true
	b.FontFace = Theme.FontBold
	b.TextSize = 15
	b.TextColor3 = Theme.Colors.Text
	b.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = b
	b.Parent = parent
	return b
end

local function row(parent: Instance, order: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, BUTTON)
	f.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = f
	f.Parent = parent
	return f
end

function WarPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> (),
	toast: (text: string) -> (),
	toFront: (x: number, y: number) -> ()
): WarPanel
	local gold, muted = hex(Theme.Colors.Gold), hex(Theme.Colors.Muted)
	local selectedKey: number? = nil
	local flashUntil = 0
	local declareTarget: number? = nil
	local declareUntil = 0
	local peaceTarget: number? = nil

	local function nationName(id: number): string
		local n = cs.nations[id]
		if n == nil then
			return "?"
		end
		return if lang == "en" then n.nameEn else n.name
	end
	local function colorOf(id: number): Color3
		local n = cs.nations[id]
		if n ~= nil and n.colorIndex >= 1 then
			local c = NationColors.Colors[n.colorIndex]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Muted
	end
	local function coloredName(id: number): string
		return string.format('<font color="%s">%s</font>', hex(colorOf(id)), escape(nationName(id)))
	end
	local function keyOf(war: Protocol.WarStats): number
		return war.a * 65536 + war.b
	end

	-- Баннер войны.
	local banner = panel(gui, "WarBanner")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 58)
	banner.AutomaticSize = Enum.AutomaticSize.Y
	local function fitWidth()
		banner.Size = UDim2.fromOffset(math.min(WIDTH, gui.AbsoluteSize.X - 24), 0)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fitWidth)
	fitWidth()
	local titleRow = Instance.new("Frame")
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, 0, 0, BUTTON)
	titleRow.LayoutOrder = 1
	titleRow.Parent = banner
	local prevButton = button(titleRow, "◀", BUTTON)
	local nextButton = button(titleRow, "▶", BUTTON)
	nextButton.AnchorPoint = Vector2.new(1, 0)
	nextButton.Position = UDim2.fromScale(1, 0)
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.RichText = true
	title.TextWrapped = true
	title.Size = UDim2.new(1, -2 * (BUTTON + 4), 1, 0)
	title.Position = UDim2.fromOffset(BUTTON + 4, 0)
	title.FontFace = Theme.FontBold
	title.TextSize = 16
	title.TextColor3 = Theme.Colors.Text
	title.Parent = titleRow
	local bar = Instance.new("Frame")
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Theme.Colors.Backdrop
	bar.Size = UDim2.new(1, 0, 0, 10)
	bar.LayoutOrder = 2
	bar.Parent = banner
	local barA = Instance.new("Frame")
	barA.BorderSizePixel = 0
	barA.Size = UDim2.fromScale(0.5, 1)
	barA.Parent = bar
	local barB = Instance.new("Frame")
	barB.BorderSizePixel = 0
	barB.AnchorPoint = Vector2.new(1, 0)
	barB.Position = UDim2.fromScale(1, 0)
	barB.Size = UDim2.fromScale(0.5, 1)
	barB.Parent = bar
	local statsLabel = label(banner, 13, 3)
	local buttons = row(banner, 4)
	local frontButton = button(buttons, Strings.get("war.toFront", lang), 140)
	local peaceButton = button(buttons, Strings.get("war.peace", lang), 140)
	peaceButton.TextColor3 = Theme.Colors.Sky

	-- Окно объявления войны.
	local declarePanel = panel(gui, "DeclareWar")
	declarePanel.AnchorPoint = Vector2.new(0.5, 1)
	declarePanel.Position = UDim2.new(0.5, 0, 1, -150)
	declarePanel.Size = UDim2.fromOffset(300, 0)
	declarePanel.AutomaticSize = Enum.AutomaticSize.Y
	local declareTitle = label(declarePanel, 16, 1)
	local declareRow = row(declarePanel, 2)
	local declareButton = button(declareRow, Strings.get("war.declare", lang), 170)
	declareButton.TextColor3 = Theme.Colors.Alert
	local declareCancel = button(declareRow, Strings.get("war.cancel", lang), 100)

	-- Окно условий мира.
	local peacePanel = panel(gui, "PeaceTerms")
	peacePanel.AnchorPoint = Vector2.new(0.5, 0.5)
	peacePanel.Position = UDim2.fromScale(0.5, 0.5)
	peacePanel.Size = UDim2.fromOffset(320, 0)
	peacePanel.AutomaticSize = Enum.AutomaticSize.Y
	peacePanel.ZIndex = 5
	local peaceTitle = label(peacePanel, 16, 1)
	local function termButton(key: string, order: number): TextButton
		local b = button(peacePanel, "", 300, 52)
		b.LayoutOrder = order
		b.Text = string.format(
			'%s\n<font size="12" color="%s">%s</font>',
			Strings.get("peace." .. key, lang),
			muted,
			Strings.get("peace." .. key .. ".hint", lang)
		)
		return b
	end
	local whiteButton = termButton("white", 2)
	local keepButton = termButton("keep", 3)
	local capitulateButton = termButton("capitulate", 4)
	local peaceCancel = button(peacePanel, Strings.get("war.cancel", lang), 140)
	peaceCancel.LayoutOrder = 5

	-- Входящее предложение мира.
	local offerPanel = panel(gui, "PeaceOffer")
	offerPanel.AnchorPoint = Vector2.new(0.5, 0)
	offerPanel.Position = UDim2.new(0.5, 0, 0, 230)
	offerPanel.Size = UDim2.fromOffset(340, 0)
	offerPanel.AutomaticSize = Enum.AutomaticSize.Y
	local offerText = label(offerPanel, 15, 1)
	local offerRow = row(offerPanel, 2)
	local acceptButton = button(offerRow, Strings.get("peace.accept", lang), 140)
	acceptButton.TextColor3 = Theme.Colors.Sky
	local declineButton = button(offerRow, Strings.get("peace.decline", lang), 140)
	local offerFrom: number? = nil

	local function myWars(): { Protocol.WarStats }
		local me = cs.myNation
		if me == nil then
			return {}
		end
		return ClientState.warsOf(cs, me)
	end

	local function selectedWar(): Protocol.WarStats?
		local wars = myWars()
		for _, w in wars do
			if keyOf(w) == selectedKey then
				return w
			end
		end
		local last = wars[#wars]
		selectedKey = if last ~= nil then keyOf(last) else nil
		return last
	end

	local function enemyOf(war: Protocol.WarStats): number
		return if war.a == cs.myNation then war.b else war.a
	end

	local function drawBanner(now: number)
		local war = selectedWar()
		local wars = myWars()
		banner.Visible = war ~= nil and cs.phase == "Play"
		if war == nil then
			return
		end
		prevButton.Visible = #wars > 1
		nextButton.Visible = #wars > 1
		if war.active then
			title.Text = string.format(Strings.get("war.banner", lang), coloredName(war.a), coloredName(war.b))
		else
			local left = math.max(0, math.ceil(war.timeLeft - (now - cs.warsAt)))
			title.Text =
				string.format(Strings.get("war.mobilizing", lang), coloredName(war.a), coloredName(war.b), left)
		end
		-- Скрытая мощь (§6.11а): сила стороны −1 — без разведки, полоса пополам.
		local hidden = war.powerA < 0 or war.powerB < 0
		local total = war.powerA + war.powerB
		local share = if total > 0 and not hidden then war.powerA / total else 0.5
		barA.BackgroundColor3 = colorOf(war.a)
		barB.BackgroundColor3 = colorOf(war.b)
		barA.Size = UDim2.fromScale(share, 1)
		barB.Size = UDim2.fromScale(1 - share, 1)
		local function num(id: number, value: number): string
			return string.format('<font color="%s">%s</font>', hex(colorOf(id)), Strings.formatInt(value))
		end
		statsLabel.Text = string.format(
			Strings.get("war.stats", lang),
			num(war.a, war.takenA),
			num(war.b, war.takenB),
			num(war.a, war.lossesA),
			num(war.b, war.lossesB)
		)
	end

	local function drawOffer(now: number)
		local me = cs.myNation
		offerFrom = nil
		if me ~= nil then
			for _, war in myWars() do
				if war.proposalFrom ~= 0 and war.proposalFrom ~= me then
					offerFrom = war.proposalFrom
					local left = math.max(0, math.ceil(war.proposalLeft - (now - cs.warsAt)))
					offerText.Text = string.format(
						Strings.get("peace.offer", lang),
						coloredName(war.proposalFrom),
						string.format(
							'<font color="%s">%s</font>',
							gold,
							Strings.get("peace.terms." .. war.proposalTerms, lang)
						),
						left
					)
					break
				end
			end
		end
		offerPanel.Visible = offerFrom ~= nil
	end

	local function drawDeclare(now: number)
		local target = declareTarget
		if target == nil or now > declareUntil or cs.phase ~= "Play" then
			declarePanel.Visible = false
			declareTarget = nil
			return
		end
		local me = cs.myNation
		local cooldown = if me ~= nil
			then math.max(0, math.ceil(ClientState.cooldownBetween(cs, me, target) - (now - cs.warsAt)))
			else 0
		-- Бот — уровень и личность (§9.1): знать, с кем связываешься.
		local tn = cs.nations[target]
		declareTitle.Text = coloredName(target)
			.. if tn ~= nil
					and tn.isBot
					and tn.botLevel ~= nil
					and tn.personality ~= nil
				then string.format(
					' <font size="12" color="#%s">%s, %s</font>',
					Theme.Colors.Muted:ToHex(),
					Strings.get("bot.level." .. tn.botLevel, lang),
					Strings.get("bot.personality." .. tn.personality, lang)
				)
				else ""
		if cooldown > 0 then
			declareButton.Text = string.format(Strings.get("war.declare.cooldown", lang), cooldown)
			declareButton.TextColor3 = Theme.Colors.Muted
			declareButton.AutoButtonColor = false
		else
			declareButton.Text = Strings.get("war.declare", lang)
			declareButton.TextColor3 = Theme.Colors.Alert
			declareButton.AutoButtonColor = true
		end
		declarePanel.Visible = true
	end

	local function refresh()
		local now = os.clock()
		drawBanner(now)
		drawOffer(now)
		if peaceTarget ~= nil then
			local me = cs.myNation
			if me == nil or ClientState.warBetween(cs, me, peaceTarget) == nil then
				peaceTarget = nil -- войны уже нет
			end
		end
		peacePanel.Visible = peaceTarget ~= nil
	end

	local function step(dir: number)
		local wars = myWars()
		if #wars < 2 then
			return
		end
		local idx = 1
		for k, w in wars do
			if keyOf(w) == selectedKey then
				idx = k
			end
		end
		idx = (idx - 1 + dir) % #wars + 1
		selectedKey = keyOf(wars[idx])
		refresh()
	end
	Session.connect(prevButton.Activated, function()
		step(-1)
	end)
	Session.connect(nextButton.Activated, function()
		step(1)
	end)

	-- «К фронту»: центр нашей общей границы с врагом (или его столица).
	Session.connect(frontButton.Activated, function()
		local war = selectedWar()
		local me = cs.myNation
		if war == nil or me == nil then
			return
		end
		local enemy = enemyOf(war)
		local w, size = cs.width, cs.size
		local sx, sy, n = 0, 0, 0
		for i = 0, size - 1 do
			if ClientState.ownerAt(cs, i) == me then
				local x = i % w
				local touches = (x > 0 and ClientState.ownerAt(cs, i - 1) == enemy)
					or (x < w - 1 and ClientState.ownerAt(cs, i + 1) == enemy)
					or (i >= w and ClientState.ownerAt(cs, i - w) == enemy)
					or (i + w < size and ClientState.ownerAt(cs, i + w) == enemy)
				if touches then
					sx += x
					sy += i // w
					n += 1
				end
			end
		end
		if n > 0 then
			toFront(sx / n + 0.5, sy / n + 0.5)
			return
		end
		local enemyNation = cs.nations[enemy]
		local capital = if enemyNation ~= nil then enemyNation.capital else nil
		if capital ~= nil then
			toFront(capital % w + 0.5, capital // w + 0.5)
		end
	end)

	Session.connect(peaceButton.Activated, function()
		local war = selectedWar()
		if war ~= nil then
			peaceTarget = enemyOf(war)
			peaceTitle.Text = string.format(Strings.get("peace.title", lang), coloredName(peaceTarget :: number))
			peacePanel.Visible = true
		end
	end)
	local function proposePeace(terms: string)
		local target = peaceTarget
		if target == nil then
			return
		end
		send("peace", { target = target, terms = terms })
		toast(Strings.get("peace.sent", lang))
		peaceTarget = nil
		peacePanel.Visible = false
	end
	Session.connect(whiteButton.Activated, function()
		proposePeace("white")
	end)
	Session.connect(keepButton.Activated, function()
		proposePeace("keep")
	end)
	Session.connect(capitulateButton.Activated, function()
		proposePeace("capitulate") -- сервер проверит, что войск меньше трети врага (§8.1)
	end)
	Session.connect(peaceCancel.Activated, function()
		peaceTarget = nil
		peacePanel.Visible = false
	end)

	Session.connect(acceptButton.Activated, function()
		if offerFrom ~= nil then
			send("peaceReply", { target = offerFrom, accept = true })
			offerPanel.Visible = false
		end
	end)
	Session.connect(declineButton.Activated, function()
		if offerFrom ~= nil then
			send("peaceReply", { target = offerFrom, accept = false })
			offerPanel.Visible = false
		end
	end)

	Session.connect(declareButton.Activated, function()
		local target = declareTarget
		local me = cs.myNation
		if target == nil or me == nil then
			return
		end
		if ClientState.cooldownBetween(cs, me, target) - (os.clock() - cs.warsAt) > 0 then
			return
		end
		send("declare", { target = target })
		declareTarget = nil
		declarePanel.Visible = false
	end)
	Session.connect(declareCancel.Activated, function()
		declareTarget = nil
		declarePanel.Visible = false
	end)

	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or input.KeyCode ~= Enum.KeyCode.Escape then
			return
		end
		declareTarget = nil
		declarePanel.Visible = false
		peaceTarget = nil
		peacePanel.Visible = false
	end)

	local function offerDeclare(target: number)
		declareTarget = target
		declareUntil = os.clock() + Config.Render.FeedSec
		drawDeclare(os.clock())
	end

	local function onEvents(events: { any })
		local me = cs.myNation
		for _, e in events do
			if type(e) == "table" and e.kind == "warDeclared" and me ~= nil then
				if e.target == me then
					-- На нас напали: сирена, баннер мигает и показывает эту войну.
					flashUntil = os.clock() + Config.Render.AttackedFlashSec
					selectedKey = (tonumber(e.nation) or 0) * 65536 + me
					Audio.play("Siren")
				elseif e.nation == me then
					selectedKey = me * 65536 + (tonumber(e.target) or 0)
				end
			end
		end
	end

	local lastSecond = -1
	local function update(now: number)
		-- Обратные отсчёты — раз в секунду, мигание — каждый кадр.
		local second = math.floor(now)
		if second ~= lastSecond then
			lastSecond = second
			drawBanner(now)
			drawOffer(now)
			drawDeclare(now)
		end
		if now < flashUntil and math.floor(now * 4) % 2 == 0 then
			banner.BackgroundColor3 = Theme.Colors.Alert
		else
			banner.BackgroundColor3 = Theme.Colors.PanelBg
		end
	end

	return {
		refresh = refresh,
		update = update,
		offerDeclare = offerDeclare,
		onEvents = onEvents,
	}
end

return table.freeze(WarPanel)
