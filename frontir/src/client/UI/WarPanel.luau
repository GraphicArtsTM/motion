--!strict
--[[
	WarPanel — война и мир в интерфейсе (GDD §6.7а, §10):
	- баннер сверху под фазой: «ВОЙНА: A — B» в цветах стран (или «МОБИЛИЗАЦИЯ … · N с»), полоска перевеса
	  (вся сила сторон), земля, взятая в этой войне, и потери обеих сторон; кнопки «К фронту» и «Мир»;
	  несколько войн — стрелки ◀ ▶;
	- на вас напали — баннер мигает красным, сирена (AudioCues → Audio), строка в ленте (MatchHud);
	- нажатие на страну без войны (MatchHud → offerDeclare) — окно «Объявить войну» (после мира — «Мир: ещё N с»);
	- «Мир» — окно условий: три карточки с картинками — белый мир, забрать захваченное, капитуляция (§15л ч.11);
	- «Объявить войну» — два портрета держав «VS» и их сила;
	- предложение мира от врага — портрет, условия картинкой, «X предлагает мир: … · N с», «Принять» / «Отклонить».
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

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))
local NationWindow = require(script.Parent:WaitForChild("NationWindow"))

type ClientState = ClientState.ClientState

export type WarPanel = {
	refresh: () -> (),
	update: (now: number) -> (),
	offerDeclare: (target: number) -> (),
	onEvents: (events: { any }) -> (),
	-- Окно «Объявить войну» стоит там же, где меню порта и здания (Main.client → closeSheets).
	declareOpen: () -> boolean,
	closeDeclare: () -> (),
}

local WarPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local WIDTH = 560 -- §15ш Ш2: баннер одной строкой — заголовок и обе кнопки в ряд

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
	f.BackgroundTransparency = 0.03 -- §15ъ: непрозрачная — текст снизу не просвечивает
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

function WarPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> (),
	toast: (text: string) -> (),
	toFront: (x: number, y: number) -> (),
	nationWindow: NationWindow.NationWindow -- §15й Й7: окно державы вместо «Объявить войну»
): WarPanel
	local gold = hex(Theme.Colors.Gold)
	local selectedKey: number? = nil
	local flashUntil = 0
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
	local banner = panel(gui, "WarStatus") -- не «WarBanner»: так зовётся заставка WarFxLayer
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 58)
	banner.AutomaticSize = Enum.AutomaticSize.Y
	local function fitWidth()
		banner.Size = UDim2.fromOffset(math.min(WIDTH, UiScale.size(gui).X - 24), 0)
	end
	UiScale.onResize(gui, fitWidth)
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
	-- §15ш Ш2: «◀ ВОЙНА 1/3: A — B [К фронту] [Мир] ▶» — одной строкой, справа налево: ▶, Мир, К фронту.
	local ACTION_W = 104
	local frontButton = button(titleRow, Strings.get("war.toFront", lang), ACTION_W)
	frontButton.AnchorPoint = Vector2.new(1, 0)
	frontButton.Position = UDim2.new(1, -(BUTTON + 4 + ACTION_W + 4), 0, 0)
	local peaceButton = button(titleRow, Strings.get("war.peace", lang), ACTION_W)
	peaceButton.AnchorPoint = Vector2.new(1, 0)
	peaceButton.Position = UDim2.new(1, -(BUTTON + 4), 0, 0)
	peaceButton.TextColor3 = Theme.Colors.Sky
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.RichText = true
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, -(2 * (BUTTON + 4) + 2 * (ACTION_W + 4)), 1, 0)
	title.Position = UDim2.fromOffset(BUTTON + 4, 0)
	title.FontFace = Theme.FontBold
	title.TextSize = 15
	title.TextColor3 = Theme.Colors.Text
	title.Parent = titleRow
	local bar = Instance.new("Frame")
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Theme.Colors.Backdrop
	bar.Size = UDim2.new(1, 0, 0, 6)
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
	local statsLabel = label(banner, 12, 3)
	-- §15ъ Ч2: полоса тонкая — одна строка; перевес и счёт — по нажатию на строку (и снова — свернуть).
	local details = false
	bar.Visible = false
	statsLabel.Visible = false
	local titleTap = Instance.new("TextButton")
	titleTap.Name = "Details"
	titleTap.BackgroundTransparency = 1
	titleTap.Text = ""
	titleTap.Size = title.Size
	titleTap.Position = title.Position
	titleTap.ZIndex = title.ZIndex + 1
	titleTap.Parent = titleRow
	Session.connect(titleTap.Activated, function()
		details = not details
		bar.Visible = details
		statsLabel.Visible = details
	end)

	-- Окна войны и мира (§15л ч.11): рамка с картинками, кнопки во всю ширину.
	local function window(name: string, width: number, edge: Color3): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.Size = UDim2.fromOffset(width, 0)
		f.AutomaticSize = Enum.AutomaticSize.Y
		f.BackgroundColor3 = Theme.Colors.PanelBg
		f.BorderSizePixel = 0
		f.Active = true
		f.Visible = false
		f.Parent = gui
		MenuKit.stroke(f, edge, 2)
		MenuKit.pad(f, 12, 10)
		MenuKit.list(f, 10)
		local scale = Instance.new("UIScale")
		scale.Parent = f
		UiScale.fitSheet(gui, f, scale, width, 8, 0.45) -- §15ё: на телефоне — и по высоте
		return f
	end
	-- Окно условий мира: три карточки с картинками.
	local peacePanel = window("PeaceTerms", 3 * CardKit.CardW + 2 * CardKit.Gap + 24, Theme.Colors.Sky)
	peacePanel.AnchorPoint = Vector2.new(0.5, 0.5)
	peacePanel.Position = UDim2.fromScale(0.5, 0.5)
	peacePanel.ZIndex = 5
	local peaceHead = MenuKit.box(peacePanel, "Head", 1)
	peaceHead.AutomaticSize = Enum.AutomaticSize.None
	peaceHead.Size = UDim2.new(1, 0, 0, 48)
	local peaceArt = CardKit.art(peaceHead, "peace.offer", 72, 48) -- §15я: гладкая картинка «голубь мира»
	peaceArt.Name = "HeadArt"
	local peaceTitle = MenuKit.label(peaceHead, "", 20, Theme.Colors.Text, true)
	peaceTitle.Position = UDim2.fromOffset(84, 0)
	local peaceSub = MenuKit.label(peaceHead, Strings.get("peace.pick", lang), 13, Theme.Colors.Muted)
	peaceSub.Position = UDim2.fromOffset(84, 26)
	local peaceCancel = MenuKit.button(peaceHead, "×", "normal")
	peaceCancel.AnchorPoint = Vector2.new(1, 0)
	peaceCancel.Position = UDim2.fromScale(1, 0)
	peaceCancel.Size = UDim2.fromOffset(BUTTON, BUTTON)
	peaceCancel.TextSize = 24
	local terms = MenuKit.box(peacePanel, "Terms", 2)
	terms.AutomaticSize = Enum.AutomaticSize.None
	terms.Size = UDim2.new(1, 0, 0, CardKit.CardH)
	MenuKit.list(terms, CardKit.Gap, true)
	local function termButton(key: string, order: number): TextButton
		local c = CardKit.card(
			terms,
			"peace." .. key,
			Strings.get("peace." .. key, lang),
			Strings.get("peace." .. key .. ".hint", lang),
			order
		)
		c.frame.Size = UDim2.fromOffset(CardKit.CardW, CardKit.CardH)
		return CardKit.button(
			c.actions,
			Strings.get("peace.propose", lang),
			if key == "capitulate" then "danger" else "good",
			1
		)
	end
	local whiteButton = termButton("white", 1)
	local keepButton = termButton("keep", 2)
	local capitulateButton = termButton("capitulate", 3)

	-- Входящее предложение мира. §15ъ: строкой в столбике сверху по центру (HudFocus — по одной карточке), без
	-- картинок: «X предлагает мир: … · N с», «Принять» / «Отклонить».
	local offerPanel = window("PeaceOffer", Config.Render.Offers.WidthPx, Theme.Colors.Sky)
	offerPanel.BackgroundTransparency = 0.03
	-- Одной строкой: текст слева, справа ✓ / ✗ / 🚫 («Всегда нет»).
	local offerLine = MenuKit.box(offerPanel, "Line", 1)
	offerLine.AutomaticSize = Enum.AutomaticSize.Y
	offerLine.Size = UDim2.fromScale(1, 0)
	local OFFER_BUTTONS = 3 * BUTTON + 2 * 6
	local offerText = MenuKit.label(offerLine, "", 14, Theme.Colors.Text, true)
	offerText.AutomaticSize = Enum.AutomaticSize.Y
	offerText.Size = UDim2.new(1, -(OFFER_BUTTONS + 8), 0, 0)
	offerText.TextWrapped = true
	local offerRow = MenuKit.box(offerLine, "Buttons", 2)
	offerRow.AutomaticSize = Enum.AutomaticSize.None
	offerRow.AnchorPoint = Vector2.new(1, 0)
	offerRow.Position = UDim2.fromScale(1, 0)
	offerRow.Size = UDim2.fromOffset(OFFER_BUTTONS, BUTTON)
	MenuKit.list(offerRow, 6, true)
	local acceptButton = MenuKit.button(offerRow, "✓", "good", BUTTON, 1)
	local declineButton = MenuKit.button(offerRow, "×", "danger", BUTTON, 2)
	local neverButton = MenuKit.button(offerRow, "🚫", "normal", BUTTON, 3) -- §15ъ Ч3 «Всегда нет»
	for _, b in { acceptButton, declineButton, neverButton } do
		b.Size = UDim2.fromOffset(BUTTON, BUTTON)
		b.TextSize = 20
	end
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
			-- §15ш Ш2: несколько войн — «ВОЙНА 1/3», стрелки листают.
			local index = 1
			for k, w in wars do
				if keyOf(w) == keyOf(war) then
					index = k
				end
			end
			title.Text = if #wars > 1
				then string.format(
					Strings.get("war.bannerOf", lang),
					index,
					#wars,
					coloredName(war.a),
					coloredName(war.b)
				)
				else string.format(Strings.get("war.banner", lang), coloredName(war.a), coloredName(war.b))
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
		-- §15ш Ш2: счёт со стороны игрока — «вы взяли / потеряли · враг: взял / потерял».
		local me = cs.myNation
		if me == war.a or me == war.b then
			local mineA = me == war.a
			local enemy = if mineA then war.b else war.a
			statsLabel.Text = string.format(
				Strings.get("war.statsMine", lang),
				num(me :: number, if mineA then war.takenA else war.takenB),
				num(me :: number, if mineA then war.lossesA else war.lossesB),
				num(enemy, if mineA then war.takenB else war.takenA),
				num(enemy, if mineA then war.lossesB else war.lossesA)
			)
		else
			statsLabel.Text = string.format(
				Strings.get("war.stats", lang),
				num(war.a, war.takenA),
				num(war.b, war.takenB),
				num(war.a, war.lossesA),
				num(war.b, war.lossesB)
			)
		end
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
	-- §15ъ Ч3: «Всегда нет» — мир дальше отклоняет сервер сам (сброс — в настройках).
	Session.connect(neverButton.Activated, function()
		if offerFrom ~= nil then
			send("prefs", { autoNo = "peace", on = true })
			send("peaceReply", { target = offerFrom, accept = false })
			toast(Strings.get("offer.neverSet", lang))
			offerPanel.Visible = false
		end
	end)

	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or input.KeyCode ~= Enum.KeyCode.Escape then
			return
		end
		peaceTarget = nil
		peacePanel.Visible = false
	end)

	-- §15й Й7: нажатие на чужую державу — окно державы (война, дипломатия, разведка).
	local function offerDeclare(target: number)
		nationWindow.open(target)
	end
	-- Окно условий мира с этой державой (из окна державы).
	nationWindow.connect({
		openPeace = function(target: number)
			peaceTarget = target
			peaceTitle.Text = string.format(Strings.get("peace.title", lang), coloredName(target))
			peacePanel.Visible = true
		end,
	})

	local function onEvents(events: { any })
		local me = cs.myNation
		for _, e in events do
			if type(e) == "table" and e.kind == "warDeclared" and me ~= nil then
				if e.target == me then
					-- На нас напали: баннер мигает и показывает эту войну (сирена — AudioCues в Main, §13).
					flashUntil = os.clock() + Config.Render.AttackedFlashSec
					selectedKey = (tonumber(e.nation) or 0) * 65536 + me
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
		declareOpen = nationWindow.isOpen,
		closeDeclare = nationWindow.close,
	}
end

return table.freeze(WarPanel)
