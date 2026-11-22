--!strict
--[[
	LogisticsPanel — режим карты «Логистика» (§15ч Ч5б, клавиша I или квадрат над зумом): пока включён, дороги видны
	линиями на любом зуме (своя главная сеть золотом, оторванные куски — серым, чужие — бледно), станции — точки
	(зелёная в сети, красная без дороги к столице). Сверху — плашка: легенда, счётчики (чистый Logistics.summary),
	«Показать станцию без дороги» (камера по очереди) и «Закрыть».
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Logistics = require(Shared:WaitForChild("Logistics"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))
local RailLayer = require(script.Parent.Parent:WaitForChild("Render"):WaitForChild("RailLayer"))

type ClientState = ClientState.ClientState

export type LogisticsPanel = {
	toggle: () -> (),
	isOpen: () -> boolean,
	visible: () -> boolean, -- кнопка видна только в игре
	update: (now: number) -> (),
	frame: Frame,
}

local LEGEND: { { key: string, color: string } } = {
	{ key = "main", color = Config.Render.Rail.MainColor },
	{ key = "other", color = Config.Render.Rail.OtherColor },
	{ key = "on", color = Config.Render.Rail.StationOn },
	{ key = "off", color = Config.Render.Rail.StationOff },
	{ key = "water", color = Config.Render.Rail.Water },
	{ key = "broken", color = Config.Render.Rail.Cut },
}

local LogisticsPanel = {}

function LogisticsPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	rails: RailLayer.RailLayer,
	focus: (cell: number) -> ()
): LogisticsPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local on = false
	local function playing(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
	end

	local frame = Instance.new("Frame")
	frame.Name = "LogisticsLegend"
	frame.Size = UDim2.fromOffset(Config.Render.Threat.WidthPx, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Theme.Colors.PanelBg
	frame.BackgroundTransparency = 0.06
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame:SetAttribute("FrontirStyled", true)
	frame.Parent = gui
	MenuKit.corner(frame, 10)
	MenuKit.pad(frame, 14, 10)
	MenuKit.stroke(frame, Theme.color(Config.Render.Rail.MainColor), 2)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = frame
	local title = MenuKit.wrapLabel(frame, t("logistics.title"), 15, Theme.Colors.Gold)
	title.FontFace = Theme.FontBold
	title.LayoutOrder = 1
	local legendRow = Instance.new("Frame")
	legendRow.Name = "Legend"
	legendRow.BackgroundTransparency = 1
	legendRow.Size = UDim2.fromScale(1, 0)
	legendRow.AutomaticSize = Enum.AutomaticSize.Y
	legendRow.LayoutOrder = 2
	legendRow.Parent = frame
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -4, 0, 18)
	grid.CellPadding = UDim2.fromOffset(6, 2)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = legendRow
	for k, item in LEGEND do
		local cell = Instance.new("Frame")
		cell.BackgroundTransparency = 1
		cell.LayoutOrder = k
		cell.Parent = legendRow
		local sw = Instance.new("Frame")
		sw.Size = UDim2.fromOffset(12, 12)
		sw.Position = UDim2.fromOffset(0, 3)
		sw.BackgroundColor3 = Theme.color(item.color)
		sw.BorderSizePixel = 0
		sw.Parent = cell
		MenuKit.corner(sw, 6)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(18, 0)
		l.Size = UDim2.new(1, -18, 1, 0)
		l.FontFace = Theme.Font
		l.TextSize = 12
		l.TextColor3 = Theme.Colors.Text
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.Text = t("logistics.legend." .. item.key)
		l.Parent = cell
	end
	local stats = MenuKit.wrapLabel(frame, "", 13, Theme.Colors.Text)
	stats.RichText = true
	stats.LayoutOrder = 3
	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 36)
	buttons.LayoutOrder = 4
	buttons.Parent = frame
	local bl = MenuKit.list(buttons, 8, true)
	bl.HorizontalFlex = Enum.UIFlexAlignment.Fill
	local show = MenuKit.button(buttons, t("logistics.showOffline"), "normal", 36, 1)
	local close = MenuKit.button(buttons, t("logistics.close"), "normal", 36, 2)

	local result: Logistics.Summary? = nil
	local nextAt = 0
	local offIndex = 0

	-- Свои работающие станции (как MatchSim.railStations; стройки и выведенные из строя не считаются).
	local function compute(): Logistics.Summary?
		local me = cs.myNation
		if me == nil then
			return nil
		end
		local now = os.clock()
		local stations: { Logistics.Station } = {}
		for _, c in cs.cities do
			if ClientState.ownerAt(cs, c) == me then
				table.insert(stations, { cell = c, kind = "City" })
			end
		end
		for cell, b in cs.buildings do
			local kind: string = b.kind
			if
				kind ~= "City"
				and table.find(Config.Rail.Stations, kind) ~= nil
				and ClientState.ownerAt(cs, cell) == me
				and not ClientState.isDisabled(cs, cell)
				and ClientState.siteAt(cs, cell, now) == nil
			then
				table.insert(stations, { cell = cell, kind = kind })
			end
		end
		local net = cs.rails.nets[me]
		local waterways, junctions, sealines = 0, 0, 0
		if net ~= nil then
			for _ in net.water do
				waterways += 1
			end
			for _ in net.sea do
				sealines += 1 -- §15ч Ч6
			end
			for _ in net.junctions do
				junctions += 1
			end
		end
		local broken = 0
		for _, owner in cs.rails.damagedOwner do
			if owner == me then
				broken += 1
			end
		end
		return Logistics.summary({
			stations = stations,
			connected = if net ~= nil then net.connected else {},
			waterways = waterways,
			sealines = sealines,
			junctions = junctions,
			broken = broken,
			trains = rails.trainsOf(me),
		})
	end

	local function refresh()
		result = compute()
		local r = result
		if r == nil then
			return
		end
		local dots: { { cell: number, on: boolean } } = {}
		local offline: { [number]: boolean } = {}
		for _, c in r.offline do
			offline[c] = true
		end
		local me = cs.myNation
		local net = if me ~= nil then cs.rails.nets[me] else nil
		for _, c in cs.cities do
			if me ~= nil and ClientState.ownerAt(cs, c) == me then
				table.insert(dots, { cell = c, on = not offline[c] })
			end
		end
		for cell, b in cs.buildings do
			if b.kind ~= "City" and (offline[cell] or (net ~= nil and net.connected[cell])) then
				table.insert(dots, { cell = cell, on = not offline[cell] })
			end
		end
		rails.setStations(dots)
		stats.Text = string.format(
			t("logistics.stats"),
			if #r.offline > 0 then Theme.Colors.Alert:ToHex() else Theme.color("Lime"):ToHex(),
			r.connected,
			r.total,
			r.waterways,
			r.sealines,
			r.junctions,
			r.broken,
			r.trains
		)
		show.Visible = #r.offline > 0
	end

	local function toggle()
		on = not on and playing()
		frame.Visible = on
		rails.setLogistics(on, cs.myNation)
		nextAt = 0
		if on then
			refresh()
			Theme.popIn(frame)
		else
			rails.setStations({})
		end
	end
	Session.connect(close.Activated, toggle)
	Session.connect(show.Activated, function()
		local r = result
		if r == nil or #r.offline == 0 then
			return
		end
		offIndex = offIndex % #r.offline + 1
		focus(r.offline[offIndex])
	end)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.I then
			toggle()
		end
	end)

	local function update(now: number)
		if on and not playing() then
			toggle()
		end
		if on and now >= nextAt then
			nextAt = now + Config.Render.Threat.RefreshSec
			refresh()
		end
	end

	return {
		toggle = toggle,
		isOpen = function(): boolean
			return on
		end,
		visible = playing,
		update = update,
		frame = frame,
	}
end

return table.freeze(LogisticsPanel)
