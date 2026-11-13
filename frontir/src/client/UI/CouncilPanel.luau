--!strict
--[[
	CouncilPanel — Совет держав (GDD §8.2, этап 6б; окно — §15ц Ц4а).
	- Окно шаблона CardKit с вкладками «Голосование» (карточки резолюций: картинка ItemArt, что делает, голоса;
	  нажатие — выбор, главная кнопка «Голосовать: …», таймер в подсказке) и «Действуют» (что действует и сколько
	  осталось; нет созыва — «Совет через M:SS»).
	- Созыв открывает окно сам, только если никакое окно не открыто (canOpen); иначе — строка в ленте (MatchHud).
	- Действующие резолюции — строка сверху «Действует: Перемирие (0:42)»; нажатие — окно на вкладке «Действуют».
	Все решения — на сервере: клиент шлёт намерение vote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Strings = require(Shared:WaitForChild("Strings"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type CouncilPanel = {
	refresh: () -> (),
	update: (now: number) -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
	close: () -> (),
	window: Frame,
}

local CouncilPanel = {}

function CouncilPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> (),
	canOpen: () -> boolean
): CouncilPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local gold = "#" .. Theme.Colors.Gold:ToHex()

	local n = Config.Council.Options
	local width = math.max(640, n * CardKit.CardW + (n - 1) * CardKit.Gap + 60)
	local win = CardKit.window(
		gui,
		"Council",
		t("council.titleBig"),
		t("council.subtitle"),
		width,
		500,
		{ { key = "vote", label = t("council.tab.vote") }, { key = "active", label = t("council.tab.active") } },
		{ active = "list" },
		true
	)
	local window = win.frame
	local foot = win.footer :: CardKit.Footer
	local votePage = win.page("vote")
	local activePage = win.page("active")
	local noVote = MenuKit.wrapLabel(activePage, "", 15, Theme.Colors.Muted, 0)
	local nextLine = MenuKit.wrapLabel(activePage, "", 14, Theme.Colors.Sky, 1)

	local function playing(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
	end
	local function clock(sec: number): string
		local s = math.max(0, math.ceil(sec))
		return string.format("%d:%02d", s // 60, s % 60)
	end
	local function nameOf(id: number): string
		local nation = cs.nations[id]
		if nation == nil then
			return "?"
		end
		local c = if nation.colorIndex >= 1 then NationColors.Colors[nation.colorIndex] else nil
		local color = if c ~= nil then string.format("#%02x%02x%02x", c.r, c.g, c.b) else gold
		return string.format('<font color="%s">%s</font>', color, if lang == "en" then nation.nameEn else nation.name)
	end

	-- Карточки резолюций: нажатие — выбор (золотая рамка), «✔ ваш голос» — метка в углу.
	local myVote, picked = 0, 0
	local draw: (now: number) -> ()
	type Option = { card: CardKit.Card, kind: string }
	local options: { Option } = {}
	for k = 1, n do
		local card = CardKit.card(votePage, "council.truce", "", "", k)
		local tap = Instance.new("TextButton")
		tap.Name = "Pick"
		tap.Text = ""
		tap.BackgroundTransparency = 1
		tap.Size = UDim2.fromScale(1, 1)
		tap.ZIndex = 4
		tap.Parent = card.frame
		Session.connect(tap.Activated, function()
			picked = k
			draw(os.clock())
		end)
		table.insert(options, { card = card, kind = "" })
	end

	local lines: { TextLabel } = {}
	local hadVote = false

	draw = function(now: number)
		local council = cs.diplo.council
		local vote = council.vote
		local voting = vote ~= nil and playing()
		if not voting then
			myVote, picked = 0, 0
		end
		-- Созыв: окно открывается само, если ничего другого не открыто. hadVote — до setTab: setTab зовёт onTab → draw.
		local started, ended = voting and not hadVote, not voting and hadVote
		hadVote = voting
		if started and canOpen() then
			win.setTab("vote")
			window.Visible = true
		end
		if ended and window.Visible and win.tab() == "vote" then
			win.setTab("active")
		end
		if not window.Visible then
			return
		end
		local rate = ClientState.simRate(cs)
		-- Голосование.
		if vote ~= nil and voting then
			local total = 0
			for k = 1, #options do
				total += vote.tallies[k] or 0
			end
			for k, o in options do
				local option = vote.options[k]
				o.card.frame.Visible = option ~= nil
				if option ~= nil then
					if o.kind ~= option then
						o.kind = option
						CardKit.repaint(o.card.art, "council." .. option)
					end
					local count = vote.tallies[k] or 0
					o.card.title.Text = t("council.res." .. option)
					o.card.desc.Text = t("council.res." .. option .. ".hint")
					o.card.price.Text = string.format(t("council.votes"), count)
					o.card.tag.Visible = myVote == k
					o.card.tag.Text = t("council.myVote")
					local on = picked == k
					o.card.edge.Color = if on or myVote == k then Theme.Colors.Gold else Theme.Colors.PanelBorder
					o.card.edge.Thickness = if on then 4 else 2
				end
			end
			local left = ClientState.diploLeft(cs, vote.left, now, rate) / cs.speed
			local chosen = vote.options[picked]
			local timer = string.format(t("council.timer"), clock(left), total)
			if chosen == nil then
				foot.set(t("council.pick"), false, timer)
			else
				local text = string.format(t("council.voteFor"), t("council.res." .. chosen))
				foot.set(text, picked ~= myVote, timer)
			end
		else
			for _, o in options do
				o.card.frame.Visible = false
			end
			foot.set("", false, t("council.noVote"))
		end
		-- Действуют.
		local k = 0
		for _, a in council.active do
			local left = ClientState.diploLeft(cs, a.left, now, rate) / cs.speed
			if left > 0 then
				k += 1
				local name = t("council.res." .. a.kind)
				if a.kind == "sanctions" and a.target ~= nil then
					name ..= " → " .. nameOf(a.target)
				end
				local existing: TextLabel? = lines[k]
				local l: TextLabel
				if existing ~= nil then
					l = existing
				else
					l = MenuKit.wrapLabel(activePage, "", 15, Theme.Colors.Text, 10 + k)
					l.RichText = true
					lines[k] = l
				end
				l.Visible = true
				l.Text = string.format(t("council.activeRow"), name, clock(left))
			end
		end
		for j = k + 1, #lines do
			lines[j].Visible = false
		end
		noVote.Visible = k == 0
		noVote.Text = t("council.noneActive")
		local nextLeft = ClientState.diploLeft(cs, council.nextLeft, now, rate) / cs.speed
		nextLine.Visible = vote == nil and nextLeft > 0
		nextLine.Text = string.format(t("council.next"), clock(nextLeft))
		if win.tab() == "active" and vote == nil then
			foot.set("", false, "")
		end
	end

	Session.connect(foot.main.Activated, function()
		local vote = cs.diplo.council.vote
		if vote ~= nil and playing() and picked > 0 and vote.options[picked] ~= nil and picked ~= myVote then
			myVote = picked
			send("vote", { option = picked })
			draw(os.clock())
		end
	end)
	-- Смена вкладки игроком — перерисовать (вкладку, сменённую из draw, draw дорисует сам).
	local drawing = false
	local inner = draw
	draw = function(now: number)
		if drawing then
			return
		end
		drawing = true
		inner(now)
		drawing = false
	end
	win.onTab(function()
		draw(os.clock())
	end)

	-- Действующие резолюции — строка сверху; нажатие — окно на вкладке «Действуют».
	local activeLine = Instance.new("TextButton")
	activeLine.Name = "Resolutions"
	activeLine.AnchorPoint = Vector2.new(0.5, 0)
	activeLine.Position = UDim2.new(0.5, 0, 0, 96)
	activeLine.Size = UDim2.fromOffset(0, 22)
	activeLine.AutomaticSize = Enum.AutomaticSize.X
	activeLine.BackgroundColor3 = Theme.Colors.PanelBg
	activeLine.BackgroundTransparency = 0.2
	activeLine.BorderSizePixel = 0
	activeLine.RichText = true
	activeLine.FontFace = Theme.Font
	activeLine.TextSize = 13
	activeLine.TextColor3 = Theme.Colors.Text
	activeLine.Visible = false
	activeLine.Parent = gui
	MenuKit.pad(activeLine, 8, 0)
	Session.connect(activeLine.Activated, function()
		win.setTab("active")
		window.Visible = true
		draw(os.clock())
	end)

	local function drawLine(now: number)
		local parts: { string } = {}
		for _, a in cs.diplo.council.active do
			local left = ClientState.diploLeft(cs, a.left, now, ClientState.simRate(cs)) / cs.speed
			if left > 0 then
				local name = t("council.res." .. a.kind)
				if a.kind == "sanctions" and a.target ~= nil then
					name ..= " → " .. nameOf(a.target)
				end
				table.insert(parts, string.format(t("council.active"), name, clock(left)))
			end
		end
		activeLine.Visible = cs.phase == "Play" and #parts > 0
		activeLine.Text = table.concat(parts, "   ")
	end

	local function all(now: number)
		if window.Visible and not playing() then
			window.Visible = false
		end
		draw(now)
		drawLine(now)
	end

	local lastSecond = -1
	local function toggle()
		if window.Visible then
			window.Visible = false
		elseif playing() then
			win.setTab(if cs.diplo.council.vote ~= nil then "vote" else "active")
			window.Visible = true
			draw(os.clock())
		end
	end
	-- §15ш Ш3: клавиша F — как у Дипломатии (T), Технологий (Y), Стабильности (N); кнопка — у мини-карты.
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.F and (window.Visible or playing()) then
			toggle()
		end
	end)

	return {
		window = window,
		refresh = function()
			all(os.clock())
		end,
		update = function(now: number)
			local second = math.floor(now)
			if second ~= lastSecond then
				lastSecond = second
				all(now)
			end
		end,
		toggle = toggle,
		isOpen = function(): boolean
			return window.Visible
		end,
		close = function()
			window.Visible = false
		end,
	}
end

return table.freeze(CouncilPanel)
