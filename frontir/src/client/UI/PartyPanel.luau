--!strict
--[[
	PartyPanel — §15ь Л3 «Отряд» (только хаб):
	- плашка «ОТРЯД» в главном меню (колонка слева): участники (лидер — «★»-корона словом «лидер»), «Пригласить»,
	  «Выйти» (в отряде);
	- окно «Пригласить»: поиск по имени, игроки этого сервера (имя, уровень — атрибут FrontirLevel, «Пригласить»;
	  отправленным — «Отправлено» до конца срока приглашения), внизу «Пригласить друзей» (окно Roblox — inviteFriends);
	- карточка «X зовёт в отряд» с отсчётом и «Принять» / «Нет».
	В матч отряд ведёт лидер: «Играть» участника сервер отклонит (reject.partyLeaderOnly).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type PartyPanel = {
	panel: Frame,
	window: Frame,
	update: (now: number) -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
}

local PartyPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local WIN_W, ROW_H = 420, 52

function PartyPanel.new(
	side: GuiObject, -- колонка главного меню
	phoneSide: GuiObject, -- на телефоне колонка слева скрыта — плашка в колонке справа (с логотипом и плитками)
	windows: ScreenGui, -- слой окон
	cs: ClientState,
	lang: Strings.Lang,
	send: (kind: string, payload: any) -> (),
	inviteFriends: () -> ()
): PartyPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local me = Players.LocalPlayer

	------------------------------------------------------------------ плашка «ОТРЯД»
	local panel = Instance.new("Frame")
	panel.Name = "PartyPanel"
	panel.LayoutOrder = 2
	panel.Size = UDim2.fromScale(1, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Theme.Colors.PanelBg
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = side
	MenuKit.corner(panel, 10)
	MenuKit.stroke(panel, Theme.Colors.PanelBorder, 2)
	MenuKit.pad(panel, 14, 12)
	MenuKit.list(panel, 8)
	MenuKit.label(panel, t("party.kicker"), 12, Theme.Colors.Gold, true, 1)
	MenuKit.label(panel, t("party.title"), 20, Theme.Colors.Text, true, 2).FontFace = Theme.FontHeavy
	local memberList = MenuKit.box(panel, "Members", 3)
	memberList.Size = UDim2.fromScale(1, 0)
	memberList.AutomaticSize = Enum.AutomaticSize.Y
	MenuKit.list(memberList, 4)
	local memberLabels: { TextLabel } = {}
	for k = 1, Config.Party.Max do
		local l = MenuKit.label(memberList, "", 14, Theme.Colors.Text, true, k)
		l.RichText = true
		l.Visible = false
		table.insert(memberLabels, l)
	end
	local hint = MenuKit.wrapLabel(panel, t("party.hint"), 12, Theme.Colors.Muted, 4)
	local buttons = MenuKit.box(panel, "Buttons", 5)
	buttons.AutomaticSize = Enum.AutomaticSize.None
	buttons.Size = UDim2.new(1, 0, 0, BUTTON)
	local bl = MenuKit.list(buttons, 8, true)
	bl.HorizontalFlex = Enum.UIFlexAlignment.Fill
	local inviteButton = MenuKit.button(buttons, t("party.invite"), "primary", BUTTON, 1)
	local leaveButton = MenuKit.button(buttons, t("party.leave"), "normal", BUTTON, 2)

	------------------------------------------------------------------ окно «Пригласить»
	local window = Instance.new("Frame")
	window.Name = "PartyInvite"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(WIN_W, 0)
	window.AutomaticSize = Enum.AutomaticSize.Y
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BorderSizePixel = 0
	window.Active = true
	window.Visible = false
	window.ZIndex = 20
	window.Parent = windows
	MenuKit.corner(window, 12)
	MenuKit.stroke(window, Theme.Colors.PanelBorder, 2)
	MenuKit.pad(window, 16, 14)
	MenuKit.list(window, 8)
	local head = MenuKit.box(window, "Head", 1)
	head.AutomaticSize = Enum.AutomaticSize.None
	head.Size = UDim2.new(1, 0, 0, BUTTON)
	local titles = MenuKit.box(head, "Titles", 1)
	MenuKit.list(titles, 2)
	MenuKit.label(titles, t("party.inviteKicker"), 12, Theme.Colors.Gold, true, 1)
	MenuKit.label(titles, t("party.inviteTitle"), 20, Theme.Colors.Text, true, 2).FontFace = Theme.FontHeavy
	local close = MenuKit.button(head, "×", "normal", BUTTON)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(BUTTON, BUTTON)
	close.TextSize = 22
	MenuKit.label(window, t("party.here"), 14, Theme.Colors.Text, true, 2)
	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.LayoutOrder = 3
	search.Size = UDim2.new(1, 0, 0, BUTTON)
	search.BackgroundColor3 = Theme.Colors.Backdrop
	search.BorderSizePixel = 0
	search.ClearTextOnFocus = false
	search.FontFace = Theme.FontBold
	search.TextSize = 15
	search.TextColor3 = Theme.Colors.Text
	search.PlaceholderText = t("party.search")
	search.PlaceholderColor3 = Theme.Colors.Muted
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.Text = ""
	search.Parent = window
	MenuKit.corner(search, 8)
	MenuKit.pad(search, 12, 0)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.LayoutOrder = 4
	scroll.Size = UDim2.new(1, 0, 0, ROW_H * 6)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Theme.Colors.PanelBorder
	scroll.Parent = window
	MenuKit.list(scroll, 6)
	local empty = MenuKit.wrapLabel(window, t("party.empty"), 13, Theme.Colors.Muted, 5)
	local friends = MenuKit.button(window, t("party.friends"), "normal", BUTTON, 6)
	friends.Size = UDim2.new(1, 0, 0, BUTTON)

	type Row = { frame: Frame, name: TextLabel, level: TextLabel, go: TextButton, user: number }
	local rows: { [number]: Row } = {}
	local sentUntil: { [number]: number } = {}
	local function rowFor(p: Player): Row
		local existing = rows[p.UserId]
		if existing ~= nil then
			return existing
		end
		local f = Instance.new("Frame")
		f.Name = "Player" .. p.UserId
		f.Size = UDim2.new(1, -8, 0, ROW_H)
		f.BackgroundTransparency = 1
		f.Parent = scroll
		local name = MenuKit.label(f, p.DisplayName, 15, Theme.Colors.Text, true)
		name.AnchorPoint = Vector2.new(0, 0.5)
		name.Position = UDim2.fromScale(0, 0.5)
		local level = MenuKit.label(f, "", 13, Theme.Colors.Muted, true)
		level.AnchorPoint = Vector2.new(1, 0.5)
		level.Position = UDim2.new(1, -150, 0.5, 0)
		local go = MenuKit.button(f, t("party.inviteOne"), "primary", BUTTON)
		go.AnchorPoint = Vector2.new(1, 0.5)
		go.Position = UDim2.fromScale(1, 0.5)
		go.Size = UDim2.fromOffset(140, BUTTON)
		go.TextSize = 14
		local row: Row = { frame = f, name = name, level = level, go = go, user = p.UserId }
		Session.connect(go.Activated, function()
			if (sentUntil[row.user] or 0) > os.clock() then
				return
			end
			sentUntil[row.user] = os.clock() + Config.Party.InviteSec
			send("partyInvite", { user = row.user })
		end)
		rows[p.UserId] = row
		return row
	end

	local function inParty(user: number): boolean
		local party = cs.party
		if party == nil then
			return false
		end
		for _, m in party.members do
			if m.id == user then
				return true
			end
		end
		return false
	end
	local function drawWindow()
		local query = string.lower(search.Text)
		local shown = 0
		local seen: { [number]: boolean } = {}
		for _, p in Players:GetPlayers() do
			if p ~= me then
				seen[p.UserId] = true
				local row = rowFor(p)
				local match = query == "" or string.find(string.lower(p.DisplayName), query, 1, true) ~= nil
				local visible = match and not inParty(p.UserId)
				row.frame.Visible = visible
				if visible then
					shown += 1
					row.level.Text = string.format(t("party.level"), tonumber(p:GetAttribute("FrontirLevel")) or 1)
					local sent = (sentUntil[p.UserId] or 0) > os.clock()
					row.go.Text = t(if sent then "party.sent" else "party.inviteOne")
					row.go.AutoButtonColor = not sent
					row.go.BackgroundTransparency = if sent then 0.5 else 0
				end
			end
		end
		for user, row in rows do
			if not seen[user] then
				row.frame:Destroy()
				rows[user] = nil
			end
		end
		empty.Visible = shown == 0
	end

	------------------------------------------------------------------ карточка «X зовёт в отряд»
	local card = Instance.new("Frame")
	card.Name = "PartyInviteCard"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 16)
	card.Size = UDim2.fromOffset(380, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Theme.Colors.PanelBg
	card.BorderSizePixel = 0
	card.Visible = false
	card.ZIndex = 30
	card.Parent = windows
	MenuKit.corner(card, 10)
	MenuKit.stroke(card, Theme.Colors.Gold, 2)
	MenuKit.pad(card, 14, 12)
	MenuKit.list(card, 8)
	local cardText = MenuKit.wrapLabel(card, "", 15, Theme.Colors.Text, 1)
	cardText.RichText = true
	local cardButtons = MenuKit.box(card, "Buttons", 2)
	cardButtons.AutomaticSize = Enum.AutomaticSize.None
	cardButtons.Size = UDim2.new(1, 0, 0, BUTTON)
	local cl = MenuKit.list(cardButtons, 8, true)
	cl.HorizontalFlex = Enum.UIFlexAlignment.Fill
	local accept = MenuKit.button(cardButtons, t("party.accept"), "good", BUTTON, 1)
	local decline = MenuKit.button(cardButtons, t("party.decline"), "normal", BUTTON, 2)

	------------------------------------------------------------------ действия
	local function toggle()
		window.Visible = not window.Visible and cs.place == "hub"
		if window.Visible then
			drawWindow()
		end
	end
	Session.connect(inviteButton.Activated, toggle)
	Session.connect(close.Activated, function()
		window.Visible = false
	end)
	Session.connect(friends.Activated, inviteFriends)
	Session.connect(leaveButton.Activated, function()
		send("partyLeave", {})
	end)
	Session.connect(search:GetPropertyChangedSignal("Text"), drawWindow)
	Session.connect(accept.Activated, function()
		cs.partyInvite = nil
		card.Visible = false
		send("partyReply", { accept = true })
	end)
	Session.connect(decline.Activated, function()
		cs.partyInvite = nil
		card.Visible = false
		send("partyReply", { accept = false })
	end)

	local nextAt = 0
	local function update(now: number)
		if now < nextAt then
			return
		end
		nextAt = now + 0.25
		local hub = cs.place == "hub"
		panel.Visible = hub
		-- Телефон: колонка слева скрыта — плашка в колонке справа, уже и без подсказки.
		local host = if side.Visible then side else phoneSide
		if panel.Parent ~= host then
			panel.Parent = host
			panel.LayoutOrder = if host == phoneSide then 3 else 2
			panel.Size = if host == phoneSide then UDim2.fromOffset(240, 0) else UDim2.fromScale(1, 0)
		end
		if not hub then
			window.Visible = false
			card.Visible = false
			return
		end
		-- Плашка: участники отряда (лидер — словом), «Выйти» — только в отряде.
		local party = cs.party
		for k, l in memberLabels do
			local m = if party ~= nil then party.members[k] else nil
			l.Visible = m ~= nil
			if m ~= nil and party ~= nil then
				local lead = if m.id == party.leader
					then string.format(' <font color="#%s">%s</font>', Theme.Colors.Gold:ToHex(), t("party.leader"))
					else ""
				l.Text = string.format(t("party.member"), m.name, m.level) .. lead
			end
		end
		hint.Visible = party == nil and host == side
		leaveButton.Visible = party ~= nil
		local leadOrSolo = party == nil or party.leader == me.UserId
		inviteButton.Visible = leadOrSolo and (party == nil or #party.members < Config.Party.Max)
		if window.Visible then
			drawWindow()
		end
		-- Приглашение в отряд: с отсчётом; срок вышел — карточка уходит.
		local inv = cs.partyInvite
		if inv ~= nil and now >= inv.untilAt then
			cs.partyInvite = nil
			inv = nil
		end
		card.Visible = inv ~= nil
		if inv ~= nil then
			cardText.Text = string.format(t("party.invited"), inv.name, math.ceil(inv.untilAt - now))
		end
	end

	return {
		panel = panel,
		window = window,
		update = update,
		toggle = toggle,
		isOpen = function(): boolean
			return window.Visible
		end,
	}
end

return table.freeze(PartyPanel)
