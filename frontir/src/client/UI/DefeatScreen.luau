--!strict
--[[
	DefeatScreen — «Держава пала» (GDD §15й Й5): своё выбывание — карточка по центру: кто добил, сколько продержались,
	плитки «Пик суши · Взято городов · Задач · Трофеи» (счётчики матча — cs.task.stats). Кнопки: «Смотреть»
	(закрыть и следить за лидером), «Новый матч» (только один человек в матче — намерение endSolo), «В меню».
	Карточка уходит сама, когда матч кончился (итоги — ResultsPanel).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type DefeatScreen = {
	frame: Frame,
	onEvents: (events: { any }) -> (),
	update: (now: number) -> (),
}

local DefeatScreen = {}

local WIDTH, TILE_W, TILE_H = 520, 236, 64

function DefeatScreen.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (kind: string, payload: any) -> (),
	isSolo: () -> boolean,
	onWatch: () -> (),
	onMenu: () -> ()
): DefeatScreen
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local frame = Instance.new("Frame")
	frame.Name = "DefeatScreen"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.45)
	frame.Size = UDim2.fromOffset(WIDTH, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Theme.Colors.PanelBg
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 25
	frame.Parent = gui
	frame:SetAttribute("FrontirStyled", true)
	MenuKit.corner(frame, 12)
	MenuKit.pad(frame, 20, 16)
	MenuKit.stroke(frame, Theme.Colors.Alert, 3)
	local pop = Instance.new("UIScale")
	pop.Parent = frame
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = frame

	local title = MenuKit.label(frame, t("defeat.title"), 40, Theme.Colors.Alert, true, 1)
	title.FontFace = Theme.FontHeavy
	local sub = MenuKit.wrapLabel(frame, "", 16, Theme.Colors.Muted, 2)
	sub.TextXAlignment = Enum.TextXAlignment.Center

	local tiles = Instance.new("Frame")
	tiles.Name = "Tiles"
	tiles.BackgroundTransparency = 1
	tiles.Size = UDim2.fromOffset(2 * TILE_W + 10, 2 * TILE_H + 10)
	tiles.LayoutOrder = 3
	tiles.Parent = frame
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = tiles
	local function tile(order: number, caption: string): TextLabel
		local f = Instance.new("Frame")
		f.LayoutOrder = order
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.Parent = tiles
		MenuKit.corner(f, 8)
		MenuKit.stroke(f, Theme.Colors.PanelBorder, 1)
		local cap = MenuKit.label(f, caption, 12, Theme.Colors.Muted, true)
		cap.Position = UDim2.fromOffset(12, 8)
		local value = MenuKit.label(f, "—", 24, Theme.Colors.Text, true)
		value.FontFace = Theme.FontHeavy
		value.Position = UDim2.fromOffset(12, 28)
		return value
	end
	local peak = tile(1, t("defeat.peak"))
	local cities = tile(2, t("defeat.cities"))
	local tasks = tile(3, t("defeat.tasks"))
	local trophies = tile(4, t("defeat.trophies"))

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromOffset(2 * TILE_W + 10, 48)
	row.LayoutOrder = 4
	row.Parent = frame
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowList.Padding = UDim.new(0, 10)
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = row
	local function btn(text: string, style: any, order: number): TextButton
		local b = MenuKit.button(row, text, style, 48, order)
		b.Size = UDim2.fromOffset(150, 48)
		return b
	end
	local watch = btn(t("defeat.watch"), "normal", 1)
	local again = btn(t("defeat.again"), "primary", 2)
	local menu = btn(t("defeat.menu"), "normal", 3)

	local shown = false
	Session.connect(watch.Activated, function()
		frame.Visible = false
		onWatch()
	end)
	Session.connect(again.Activated, function()
		frame.Visible = false
		send("endSolo", {})
	end)
	Session.connect(menu.Activated, function()
		frame.Visible = false
		onMenu()
	end)

	local function nameOf(id: number): string
		local n = cs.nations[id]
		if n == nil then
			return "?"
		end
		return if lang == "en" then n.nameEn else n.name
	end
	local function clock(sec: number): string
		local s = math.max(0, math.floor(sec))
		return string.format("%d:%02d", s // 60, s % 60)
	end
	local function fill()
		local msg = cs.task
		local st = if msg ~= nil then msg.stats else nil
		peak.Text = if st ~= nil then tostring(st.peak) .. "%" else "—"
		cities.Text = if st ~= nil then Strings.formatInt(st.cities) else "—"
		tasks.Text = if st ~= nil then Strings.formatInt(st.tasks) else "—"
		trophies.Text = if st ~= nil then "$" .. Strings.formatInt(st.trophies) else "—"
	end

	local function onEvents(events: { any })
		local me = cs.myNation
		if me == nil or shown then
			return
		end
		for _, e in events do
			if type(e) == "table" and e.kind == "eliminated" and e.nation == me then
				shown = true
				local by = tonumber(e.by) or 0
				local lived = clock(ClientState.matchTime(cs, os.clock()))
				sub.Text = if by ~= 0 and by ~= me
					then string.format(t("defeat.by"), nameOf(by), lived)
					else string.format(t("defeat.nobody"), lived)
				again.Visible = isSolo()
				fill()
				frame.Visible = true
				pop.Scale = 0.7
				TweenService:Create(pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				}):Play()
			end
		end
	end

	local function update(_now: number)
		if frame.Visible then
			if cs.phase ~= "Play" then
				frame.Visible = false
			else
				fill()
			end
		end
		if cs.phase ~= "Play" then
			shown = false -- новый матч — новая карточка
		end
	end

	return { frame = frame, onEvents = onEvents, update = update }
end

return table.freeze(DefeatScreen)
