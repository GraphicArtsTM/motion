--!strict
--[[
	TutorialPanel — «Обучение 2.0» (GDD §15ь Л4; было §5.5, §15ц Ц5б).
	- Карточка-наставник (рамка «Tutorial», место ставит Main.client): «🎓 ОБУЧЕНИЕ · ШАГ N / 7», полоса из делений
	  (пройденные — золотые, текущее мигает), шаг крупно, что сделать (на телефоне — без клавиш), «Свернуть» (в фишку
	  «🎓 N/7») и «Пропустить» (с подтверждением → в хаб). Шаги проверяет сервер (info.tutorialStep, события
	  tutorial / tutorialDone); шаг пройден — «✔ Отлично!» на карточке (Tutorial.DoneFlashSec).
	- Прожектор: на цель шага (Config.Tutorial.Focus / PhoneFocus — путь рамки, первую часть ищем в глубину) экран
	  вокруг темнеет на Tutorial.SpotlightSec или до первого нажатия, дальше — пульсирующая рамка и палец 👇 / 👆
	  (с той стороны, где есть место). Ничто из подсветки не ловит нажатия.
	- Финал: окно «ОБУЧЕНИЕ ПРОЙДЕНО» (награда — если первый раз), «ИГРАТЬ ПО-НАСТОЯЩЕМУ» (сервер матча — намерение
	  nextMatch: в хаб и быстрый вход) и «Остаться в матче».
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))

type ClientState = ClientState.ClientState

export type TutorialPanel = {
	refresh: () -> (),
	update: (now: number) -> (),
	onEvents: (events: { any }) -> (),
}

local TutorialPanel = {}

local WIDTH = 340
-- HUD рисуется с ZIndex Global: содержимое рамок поднимает Layering.liftAll (ZIndex рамки + свой).
local Z_SPOT = 45 -- затемнение
local Z_FOCUS = 50 -- рамка и палец
local Z_CARD = 55 -- карточка-наставник и фишка — над затемнением
local Z_MODAL = 60 -- окна «пропустить?» и «пройдено»

local function corner(g: GuiObject, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = g
end

function TutorialPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (kind: string, payload: { [string]: any }) -> ()
): TutorialPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local cfg = Config.Tutorial
	local steps = cfg.Steps
	local total = #steps
	local focusPaths = cfg.Focus :: { [string]: string }
	local phoneFocus = cfg.PhoneFocus :: { [string]: { string } }

	local collapsed = false -- карточка свёрнута в фишку
	local dismissed = false -- «Пропустить» (до конца этого матча)
	local flashUntil = 0 -- «✔ Отлично!» до этого времени (os.clock)
	local flashKind: string? = nil
	local spotUntil = 0 -- прожектор до этого времени
	local lastTarget: GuiObject? = nil
	local lastMatch: any = nil

	------------------------------------------------------------------ карточка-наставник
	local panel = Instance.new("Frame")
	panel.Name = "Tutorial"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 12, 0.5, 40)
	panel.Size = UDim2.fromOffset(WIDTH, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Theme.Colors.PanelBg
	panel.BackgroundTransparency = 0.04
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = Z_CARD
	panel.Parent = gui
	corner(panel, 12)
	local edge = MenuKit.stroke(panel, Theme.Colors.Gold, 2)
	MenuKit.pad(panel, 14, 12)
	MenuKit.list(panel, 8)

	-- Верх: «🎓 ОБУЧЕНИЕ» … «ШАГ N / 7» [Свернуть].
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 24)
	top.LayoutOrder = 1
	top.Parent = panel
	local brand = MenuKit.label(top, t("tutorial.brand"), 13, Theme.Colors.Muted, true)
	brand.AnchorPoint = Vector2.new(0, 0.5)
	brand.Position = UDim2.fromScale(0, 0.5)
	local hideButton = Instance.new("TextButton")
	hideButton.Name = "Hide"
	hideButton.AnchorPoint = Vector2.new(1, 0.5)
	hideButton.Position = UDim2.fromScale(1, 0.5)
	hideButton.Size = UDim2.fromOffset(28, 24)
	hideButton.BackgroundColor3 = Theme.Colors.Slate
	hideButton.BorderSizePixel = 0
	hideButton.FontFace = Theme.FontBold
	hideButton.TextSize = 16
	hideButton.TextColor3 = Theme.Colors.Text
	hideButton.Text = "—"
	hideButton.Parent = top
	corner(hideButton, 6)
	local stepOf = MenuKit.label(top, "", 13, Theme.Colors.Gold, true)
	stepOf.AnchorPoint = Vector2.new(1, 0.5)
	stepOf.Position = UDim2.new(1, -36, 0.5, 0)
	stepOf.TextXAlignment = Enum.TextXAlignment.Right

	-- Полоса из делений.
	local segRow = Instance.new("Frame")
	segRow.Name = "Progress"
	segRow.BackgroundTransparency = 1
	segRow.Size = UDim2.new(1, 0, 0, 6)
	segRow.LayoutOrder = 2
	segRow.Parent = panel
	MenuKit.list(segRow, 4, true)
	local segs: { Frame } = {}
	for k = 1, total do
		local f = Instance.new("Frame")
		f.Name = "Seg" .. k
		f.LayoutOrder = k
		f.Size = UDim2.new(1 / total, -4 * (total - 1) / total, 1, 0)
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.Parent = segRow
		corner(f, 3)
		segs[k] = f
	end

	local title = MenuKit.label(panel, "", 21, Theme.Colors.Gold, true, 3)
	local hint = MenuKit.wrapLabel(panel, "", 15, Theme.Colors.Text, 4)
	hint.LineHeight = 1.1

	local bottom = Instance.new("Frame")
	bottom.Name = "Bottom"
	bottom.BackgroundTransparency = 1
	bottom.Size = UDim2.new(1, 0, 0, 30)
	bottom.LayoutOrder = 5
	bottom.Parent = panel
	local skipButton = MenuKit.button(bottom, t("tutorial.skip"), "normal", 30)
	skipButton.Name = "Skip"
	skipButton.AnchorPoint = Vector2.new(1, 0)
	skipButton.Position = UDim2.fromScale(1, 0)
	skipButton.Size = UDim2.fromOffset(128, 30)
	skipButton.TextSize = 14

	-- Свёрнутая карточка — фишка на том же месте.
	local chip = Instance.new("TextButton")
	chip.Name = "TutorialChip"
	chip.Size = UDim2.fromOffset(96, 40)
	chip.BackgroundColor3 = Theme.Colors.PanelBg
	chip.BackgroundTransparency = 0.04
	chip.BorderSizePixel = 0
	chip.FontFace = Theme.FontBold
	chip.TextSize = 16
	chip.TextColor3 = Theme.Colors.Gold
	chip.Visible = false
	chip.ZIndex = Z_CARD
	chip.Parent = gui
	corner(chip, 12)
	local chipEdge = MenuKit.stroke(chip, Theme.Colors.Gold, 2)

	------------------------------------------------------------------ прожектор, рамка, палец
	local spot = Instance.new("Frame")
	spot.Name = "TutorialSpot"
	spot.BackgroundTransparency = 1
	spot.Active = false
	spot.Size = UDim2.fromOffset(0, 0)
	spot.ZIndex = Z_SPOT
	spot.Visible = false
	spot.Parent = gui
	local dims: { Frame } = {}
	for k = 1, 4 do
		local d = Instance.new("Frame")
		d.Name = "Dim" .. k
		d.Active = false
		d.BackgroundColor3 = Theme.Colors.Backdrop
		d.BackgroundTransparency = 1
		d.BorderSizePixel = 0
		d.Parent = spot
		dims[k] = d
	end

	local focus = Instance.new("Frame")
	focus.Name = "TutorialFocus"
	focus.BackgroundTransparency = 1
	focus.Active = false
	focus.Visible = false
	focus.ZIndex = Z_FOCUS
	focus.Parent = gui
	corner(focus, 10)
	local ring = MenuKit.stroke(focus, Theme.Colors.Gold, 3)
	local finger = Instance.new("TextLabel")
	finger.Name = "TutorialFinger"
	finger.BackgroundTransparency = 1
	finger.Active = false
	finger.Size = UDim2.fromOffset(44, 44)
	finger.TextSize = 36
	finger.Text = "👇"
	finger.ZIndex = Z_FOCUS
	finger.Visible = false
	finger.Parent = gui

	------------------------------------------------------------------ окна: «Пропустить?» и «Пройдено»
	-- Окно по центру поверх всего; под ним — затемнение, которое ловит нажатия (модальное).
	local function modal(name: string): (Frame, Frame)
		local back = Instance.new("TextButton")
		back.Name = name
		back.Text = ""
		back.AutoButtonColor = false
		back.BackgroundColor3 = Theme.Colors.Backdrop
		back.BackgroundTransparency = 0.35
		back.BorderSizePixel = 0
		back.ZIndex = Z_MODAL
		back.Visible = false
		back.Parent = gui
		local box = Instance.new("Frame")
		box.Name = "Box"
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Size = UDim2.fromOffset(420, 0)
		box.AutomaticSize = Enum.AutomaticSize.Y
		box.BackgroundColor3 = Theme.Colors.PanelBg
		box.BorderSizePixel = 0
		box.Parent = back
		corner(box, 14)
		MenuKit.stroke(box, Theme.Colors.Gold, 2)
		MenuKit.pad(box, 22, 18)
		local l = MenuKit.list(box, 12)
		l.HorizontalAlignment = Enum.HorizontalAlignment.Center
		return back :: any, box
	end
	-- Размер затемнения — по экрану в условных пикселях (слой HUD в масштабе, §15ц Ц1).
	local function fitModal(back: Frame)
		local size = UiScale.size(gui)
		back.Size = UDim2.fromOffset(size.X, size.Y)
		local box = back:FindFirstChild("Box") :: Frame
		box.Position = UDim2.fromOffset(size.X / 2, size.Y / 2)
		box.Size = UDim2.fromOffset(math.min(420, size.X - 32), 0)
	end
	local function centered(label: TextLabel)
		label.TextXAlignment = Enum.TextXAlignment.Center
	end

	local skipBack, skipBox = modal("TutorialSkip")
	centered(MenuKit.label(skipBox, t("tutorial.skipTitle"), 20, Theme.Colors.Text, true, 1))
	centered(MenuKit.wrapLabel(skipBox, t("tutorial.skipText"), 15, Theme.Colors.Muted, 2))
	local skipNo = MenuKit.button(skipBox, t("tutorial.skipNo"), "primary", 48, 3)
	local skipYes = MenuKit.button(skipBox, t("tutorial.skipYes"), "danger", 40, 4)

	local doneBack, doneBox = modal("TutorialDone")
	centered(MenuKit.label(doneBox, t("tutorial.doneTitle"), 22, Theme.Colors.Gold, true, 1))
	centered(MenuKit.wrapLabel(doneBox, t("tutorial.doneText"), 15, Theme.Colors.Text, 2))
	local doneReward = MenuKit.wrapLabel(doneBox, "", 16, Theme.Colors.Good, 3)
	centered(doneReward)
	doneReward.FontFace = Theme.FontBold
	local playReal = MenuKit.button(doneBox, t("tutorial.playReal"), "primary", 56, 4)
	local stay = MenuKit.button(doneBox, t("tutorial.stay"), "normal", 40, 5)

	------------------------------------------------------------------ состояние
	local function stepNow(): number?
		local step = cs.tutorialStep
		if dismissed or not cs.rules.tutorial or step == nil then
			return nil
		end
		if cs.phase == "Pick" then
			return 1
		end
		if cs.phase ~= "Play" or step > total then
			return nil
		end
		return step
	end

	local function refresh()
		-- Новый матч — всё сначала (пропуск и свёрнутость — до конца матча).
		if cs.matchId ~= lastMatch then
			lastMatch = cs.matchId
			dismissed, collapsed, flashUntil, flashKind = false, false, 0, nil
		end
		local k = stepNow()
		local flashing = flashKind ~= nil and os.clock() < flashUntil
		panel.Visible = k ~= nil and not collapsed
		chip.Visible = k ~= nil and collapsed
		if k == nil then
			return
		end
		stepOf.Text = string.format(t("tutorial.stepOf"), math.min(k, total), total)
		chip.Text = string.format(t("tutorial.chip"), math.min(k, total), total)
		for j, f in segs do
			f.BackgroundColor3 = if j < k then Theme.Colors.Gold else Theme.Colors.Backdrop
		end
		if flashing then
			title.Text = t("tutorial.great")
			title.TextColor3 = Theme.Colors.Good
			hint.Text = string.format(t("tutorial.stepDone"), t("tutorial." .. (flashKind :: string)))
			edge.Color = Theme.Colors.Good
			return
		end
		edge.Color = Theme.Colors.Gold
		title.TextColor3 = Theme.Colors.Gold
		local kind = steps[k]
		title.Text = string.format("%d. %s", k, t("tutorial." .. kind))
		hint.Text = UiScale.touchText(gui, t("tutorial.hint." .. kind)) -- §15ё: на телефоне без клавиш
	end

	------------------------------------------------------------------ цель подсветки
	-- Путь «Рамка.Дочерняя…» от HUD (и слоя FrontirTopbar на телефоне); первую часть ищем в глубину — рамка может
	-- стоять в столбике TopRight / TopCenter.
	local function target(path: string): GuiObject?
		local roots: { Instance } = { gui }
		local topbar = if gui.Parent ~= nil then gui.Parent:FindFirstChild("FrontirTopbar") else nil
		if topbar ~= nil then
			table.insert(roots, topbar)
		end
		for _, root in roots do
			local node: Instance? = nil
			for part in string.gmatch(path, "[^%.]+") do
				if node == nil then
					node = root:FindFirstChild(part, true)
				else
					node = node:FindFirstChild(part)
				end
				if node == nil then
					break
				end
			end
			if node ~= nil and node:IsA("GuiObject") then
				return node
			end
		end
		return nil
	end

	-- Видно ли на экране: сам и все предки до слоя.
	local function shown(g: GuiObject?): boolean
		if g == nil then
			return false
		end
		local node: Instance? = g
		while node ~= nil and not node:IsA("LayerCollector") do
			if node:IsA("GuiObject") and not node.Visible then
				return false
			end
			node = node.Parent
		end
		if node ~= nil and node:IsA("ScreenGui") and not node.Enabled then
			return false
		end
		return g.AbsoluteSize.X > 0
	end

	local function focusOf(kind: string): GuiObject?
		local touch = UiScale.isPhone(gui) or UserInputService.TouchEnabled
		-- Касание — сначала список телефона (кнопка «✔ Строить», ящик, веер), потом общий путь; мышь — наоборот.
		local order: { string } = {}
		local alts: { string } = phoneFocus[kind] or {}
		local main = focusPaths[kind]
		if touch then
			for _, a in alts do
				table.insert(order, a)
			end
		end
		if main ~= nil then
			table.insert(order, main)
		end
		if not touch then
			for _, a in alts do
				table.insert(order, a)
			end
		end
		for _, path in order do
			local g = target(path)
			if shown(g) then
				return g
			end
		end
		return nil
	end

	local function hideFocus()
		focus.Visible = false
		finger.Visible = false
		spot.Visible = false
	end

	local function update(_now: number)
		local clock = os.clock()
		if flashKind ~= nil and clock >= flashUntil then
			flashKind = nil
			refresh()
		end
		-- Фишка — на месте карточки (место карточки ставит Main.client).
		chip.AnchorPoint = panel.AnchorPoint
		chip.Position = panel.Position
		chipEdge.Transparency = 0.4 + 0.4 * math.sin(clock * 4)
		local k = stepNow()
		local kind = if k ~= nil then steps[k] else nil
		local modalOpen = skipBack.Visible or doneBack.Visible
		if kind == nil or modalOpen or flashKind ~= nil then
			hideFocus()
			return
		end
		local g = focusOf(kind)
		if g == nil then
			lastTarget = nil
			hideFocus()
			return
		end
		if g ~= lastTarget then
			lastTarget = g
			spotUntil = clock + cfg.SpotlightSec -- новая цель — прожектор снова
		end
		-- Настоящие пиксели → условные (слой HUD в масштабе экрана, §15ц Ц1).
		local f = UiScale.factor()
		local pos = (g.AbsolutePosition - gui.AbsolutePosition) / f
		local size = g.AbsoluteSize / f
		local x0, y0 = pos.X - 6, pos.Y - 6
		local x1, y1 = pos.X + size.X + 6, pos.Y + size.Y + 6
		focus.Position = UDim2.fromOffset(x0, y0)
		focus.Size = UDim2.fromOffset(x1 - x0, y1 - y0)
		local pulse = 0.5 + 0.5 * math.sin(clock * 5)
		ring.Transparency = 0.45 * pulse
		ring.Thickness = 2 + 2 * (1 - pulse)
		focus.Visible = true

		-- Палец — сверху, если над целью есть место, иначе снизу.
		local screen = UiScale.size(gui)
		local cx = (x0 + x1) / 2
		local bounce = 8 * pulse
		if y0 > 60 then
			finger.Text = "👇"
			finger.AnchorPoint = Vector2.new(0.5, 1)
			finger.Position = UDim2.fromOffset(math.clamp(cx, 22, screen.X - 22), y0 - 2 - bounce)
		else
			finger.Text = "👆"
			finger.AnchorPoint = Vector2.new(0.5, 0)
			finger.Position = UDim2.fromOffset(math.clamp(cx, 22, screen.X - 22), y1 + 2 + bounce)
		end
		finger.Visible = true

		-- Прожектор: четыре полосы вокруг цели, плавно гаснут к концу срока.
		local left = spotUntil - clock
		if left <= 0 then
			spot.Visible = false
			return
		end
		local fade = math.clamp(left / 0.4, 0, 1)
		local alpha = 1 - (1 - cfg.SpotlightDark) * fade
		local W, H = screen.X, screen.Y
		local rects = {
			{ 0, 0, W, math.max(0, y0) },
			{ 0, y1, W, math.max(0, H - y1) },
			{ 0, y0, math.max(0, x0), y1 - y0 },
			{ x1, y0, math.max(0, W - x1), y1 - y0 },
		}
		for j, r in rects do
			local d = dims[j]
			d.Position = UDim2.fromOffset(r[1], r[2])
			d.Size = UDim2.fromOffset(r[3], r[4])
			d.BackgroundTransparency = alpha
		end
		spot.Visible = true
	end

	------------------------------------------------------------------ кнопки
	-- Любое нажатие гасит прожектор (рамка и палец остаются).
	Session.connect(UserInputService.InputBegan, function(input: InputObject)
		local tp = input.UserInputType
		if
			tp == Enum.UserInputType.MouseButton1
			or tp == Enum.UserInputType.Touch
			or tp == Enum.UserInputType.Keyboard
		then
			spotUntil = 0
		end
	end)
	Session.connect(hideButton.Activated, function()
		collapsed = true
		refresh()
	end)
	Session.connect(chip.Activated, function()
		collapsed = false
		refresh()
	end)
	Session.connect(skipButton.Activated, function()
		fitModal(skipBack)
		skipBack.Visible = true
	end)
	Session.connect(skipNo.Activated, function()
		skipBack.Visible = false
	end)
	Session.connect(skipYes.Activated, function()
		skipBack.Visible = false
		dismissed = true
		hideFocus()
		refresh()
		if cs.place == "match" then
			send("toHub", {}) -- обучение — свой сервер: выйти = в главное меню хаба
		end
	end)
	Session.connect(playReal.Activated, function()
		doneBack.Visible = false
		if cs.place == "match" then
			playReal.Active = false
			send("nextMatch", {}) -- §15ь Л1: в хаб и сразу быстрый вход
		end
	end)
	Session.connect(stay.Activated, function()
		doneBack.Visible = false
	end)
	UiScale.onResize(gui, function()
		if skipBack.Visible then
			fitModal(skipBack)
		end
		if doneBack.Visible then
			fitModal(doneBack)
		end
	end)

	return {
		refresh = refresh,
		update = update,
		onEvents = function(events: { any })
			for _, e in events do
				if e.nation == cs.myNation then
					if e.kind == "tutorial" then
						local kind = steps[tonumber(e.step) or 0]
						if kind ~= nil then
							flashKind = kind
							flashUntil = os.clock() + cfg.DoneFlashSec
							refresh()
						end
					elseif e.kind == "tutorialDone" then
						-- Награда — только за первый раз (профиль ещё не обновился: сервер шлёт его следом).
						local first = cs.profile == nil or not cs.profile.tutorialDone
						doneReward.Visible = first
						doneReward.Text = string.format(t("tutorial.doneReward"), cfg.RewardTokens, cfg.RewardMedals)
						playReal.Visible = cs.place == "match"
						playReal.Active = true
						fitModal(doneBack)
						doneBack.Visible = true
						hideFocus()
					end
				end
			end
		end,
	}
end

return table.freeze(TutorialPanel)
