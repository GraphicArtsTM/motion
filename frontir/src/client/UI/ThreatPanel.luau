--!strict
--[[
	ThreatPanel — «Карта угроз» (§15х ч.4б, клавиша L или кнопка «Угрозы» в доке): пока включена, на карте круги
	своей ПВО и ПВО врага, куда летают самолёты врага, метки его шахт и красные точки «дыр» — свои города и здания,
	которых ракета достанет без перехвата (чистый ThreatMap). Сверху — плашка: что значит цвет, счётчики и кнопка
	«Показать дыру» (камера по очереди к каждой).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local ThreatMap = require(Shared:WaitForChild("ThreatMap"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type ThreatPanel = {
	toggle: () -> (),
	isOpen: () -> boolean,
	visible: () -> boolean, -- кнопка в доке видна только в игре
	update: (now: number) -> (),
	frame: Frame,
}

-- Круг на карте: ключ (с цветом — цвет задаётся при создании), клетка, радиус, цвет.
export type DrawZone = (key: string, cell: number, radius: number, color: Color3) -> ()

local COLORS: { [string]: string } = {
	myAA = "Sky",
	myAALong = "Teal",
	enemyAA = "Orange",
	enemyAALong = "Red",
	enemyAir = "Gold",
	enemySilo = "Red",
}

local ThreatPanel = {}

function ThreatPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	draw: DrawZone,
	focus: (cell: number) -> ()
): ThreatPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local on = false
	local function playing(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
	end

	local frame = Instance.new("Frame")
	frame.Name = "ThreatLegend"
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
	MenuKit.stroke(frame, Theme.Colors.Alert, 2)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = frame
	local title = MenuKit.wrapLabel(frame, t("threat.title"), 15, Theme.Colors.Gold)
	title.FontFace = Theme.FontBold
	title.LayoutOrder = 1
	-- Легенда: цветной квадрат и подпись.
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
	for k, kind in { "myAA", "myAALong", "enemyAA", "enemyAALong", "enemyAir", "hole" } do
		local cell = Instance.new("Frame")
		cell.BackgroundTransparency = 1
		cell.LayoutOrder = k
		cell.Parent = legendRow
		local sw = Instance.new("Frame")
		sw.Size = UDim2.fromOffset(12, 12)
		sw.Position = UDim2.fromOffset(0, 3)
		sw.BackgroundColor3 = Theme.color(if kind == "hole" then "Rose" else COLORS[kind])
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
		l.Text = t("threat.legend." .. kind)
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
	local show = MenuKit.button(buttons, t("threat.showHole"), "normal", 36, 1)
	local close = MenuKit.button(buttons, t("threat.close"), "normal", 36, 2)

	local result: ThreatMap.Result? = nil
	local nextAt = 0
	local holeIndex = 0
	local function compute(): ThreatMap.Result?
		local me = cs.myNation
		if me == nil then
			return nil
		end
		local friends = ClientState.trustFriendsOf(cs, me)
		-- Враг — с кем война (и мобилизация); войн нет — все, кроме друзей и союзников.
		local enemies: { [number]: boolean } = {}
		local any = false
		for _, war in ClientState.warsOf(cs, me) do
			enemies[if war.a == me then war.b else war.a] = true
			any = true
		end
		if not any then
			local allies: { [number]: boolean } = {}
			for _, id in ClientState.alliesOf(cs, me) do
				allies[id] = true
			end
			for id in cs.nations do
				if id ~= me and not friends[id] and not allies[id] then
					enemies[id] = true
				end
			end
		end
		local buildings: { ThreatMap.Building } = {}
		for cell, b in cs.buildings do
			local kind: string = b.kind
			table.insert(buildings, {
				cell = cell,
				kind = kind,
				level = b.level,
				owner = ClientState.ownerAt(cs, cell),
				off = ClientState.isDisabled(cs, cell),
			})
		end
		local cities: { { cell: number, owner: number } } = {}
		for _, c in cs.cities do
			table.insert(cities, { cell = c, owner = ClientState.ownerAt(cs, c) })
		end
		return ThreatMap.compute({
			width = cs.width,
			me = me,
			friends = friends,
			enemies = enemies,
			buildings = buildings,
			cities = cities,
		})
	end

	local function toggle()
		on = not on and playing()
		frame.Visible = on
		nextAt = 0
		if on then
			Theme.popIn(frame)
		end
	end
	Session.connect(close.Activated, toggle)
	Session.connect(show.Activated, function()
		local r = result
		if r == nil or #r.holes == 0 then
			return
		end
		holeIndex = holeIndex % #r.holes + 1
		focus(r.holes[holeIndex])
	end)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.L then
			toggle()
		end
	end)

	local function update(now: number)
		if on and not playing() then
			on = false
			frame.Visible = false
		end
		if not on then
			return
		end
		if now >= nextAt then
			nextAt = now + Config.Render.Threat.RefreshSec
			result = compute()
			local r = result
			if r ~= nil then
				local covered = r.targets - #r.holes
				stats.Text = string.format(
					t("threat.stats"),
					r.enemySilos,
					r.enemyAirfields,
					r.enemyAA,
					if #r.holes > 0 then Theme.Colors.Alert:ToHex() else Theme.color("Lime"):ToHex(),
					covered,
					r.targets
				)
				show.Visible = #r.holes > 0
			end
		end
		local r = result
		if r == nil then
			return
		end
		for _, z in r.zones do
			draw("threat_" .. z.kind .. "_" .. z.cell, z.cell, z.radius, Theme.color(COLORS[z.kind]))
		end
		for _, cell in r.holes do
			draw("threat_hole_" .. cell, cell, Config.Render.Threat.HoleRadius, Theme.color("Rose"))
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

return table.freeze(ThreatPanel)
