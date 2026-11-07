--!strict
--[[
	BuildingInfo — окно своего здания (§15д; вид — §15л ч.11): нажатие на своё здание (±1 клетка) — карточка над
	кнопкой «Построить»: картинка здания, название, уровень квадратиками, что даёт, район города, содержание;
	кнопки «Улучшить ($…)» и «Снести (+$…)».
	Порт и аэродром открывают свои меню (NavalPanel, AirPanel) — сюда не попадают. Решает сервер (build / demolish).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Buildings = require(Shared:WaitForChild("Buildings"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Commanders = require(Shared:WaitForChild("Commanders"))
local Config = require(Shared:WaitForChild("Config"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type BuildingInfo = {
	tap: (cell: number) -> boolean, -- true — нажатие открыло окно здания
	refresh: () -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
}

local BuildingInfo = {}

local BUTTON = Config.Render.MinTouchTargetPx
local SKIP: { [string]: boolean } = { Port = true, Airfield = true }

function BuildingInfo.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> (),
	map: MapDataModule.MapData
): BuildingInfo
	local w = map.width
	local open: number? = nil

	-- Карточка здания (§15л ч.11): картинка, название, уровень квадратиками, что даёт, район и содержание, кнопки.
	local WIDTH, ART_W, ART_H = 420, 120, 80
	local card = Instance.new("Frame")
	card.Name = "BuildingInfoPanel"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -12 - 56 - 6 - BUTTON - 10)
	card.Size = UDim2.fromOffset(WIDTH, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Theme.Colors.PanelBg
	card.BorderSizePixel = 0
	card.Active = true
	card.Visible = false
	card.Parent = gui
	MenuKit.stroke(card, Theme.Colors.PanelBorder, 2)
	MenuKit.pad(card, 10, 10)
	MenuKit.list(card, 8)
	local scale = Instance.new("UIScale")
	scale.Parent = card
	local function fit()
		scale.Scale = math.clamp((gui.AbsoluteSize.X - 16) / WIDTH, 0.5, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()

	local head = MenuKit.box(card, "Head", 1)
	head.AutomaticSize = Enum.AutomaticSize.None
	head.Size = UDim2.new(1, 0, 0, ART_H)
	local art = CardKit.art(head, "building.Factory", ART_W, ART_H)
	local textX = ART_W + 12
	local title = MenuKit.label(head, "", 19, Theme.Colors.Gold, true)
	title.Position = UDim2.fromOffset(textX, 0)
	-- Уровень: квадратики (золотые — достигнутые).
	local pips = MenuKit.box(head, "Level")
	pips.Position = UDim2.fromOffset(textX, 26)
	MenuKit.list(pips, 4, true)
	local levelText = MenuKit.label(pips, "", 12, Theme.Colors.Muted, true, 99)
	local pipFrames: { Frame } = {}
	local effect = MenuKit.label(head, "", 13, Theme.Colors.Text)
	effect.AutomaticSize = Enum.AutomaticSize.None
	effect.Position = UDim2.fromOffset(textX, 46)
	effect.Size = UDim2.new(1, -textX, 0, 34)
	effect.TextWrapped = true
	effect.TextYAlignment = Enum.TextYAlignment.Top
	local close = MenuKit.button(head, "×", "normal")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(BUTTON, BUTTON)
	close.TextSize = 24

	local infoRow = MenuKit.box(card, "Info", 2)
	MenuKit.list(infoRow, 14, true)
	local district = MenuKit.label(infoRow, "", 13, Theme.Colors.Sky, true, 1)
	local upkeep = MenuKit.label(infoRow, "", 13, Theme.Colors.Muted, false, 2)

	local row = MenuKit.box(card, "Buttons", 3)
	row.AutomaticSize = Enum.AutomaticSize.None
	row.Size = UDim2.new(1, 0, 0, BUTTON)
	local rowList = MenuKit.list(row, 8, true)
	rowList.HorizontalFlex = Enum.UIFlexAlignment.Fill
	local upgrade = MenuKit.button(row, "", "primary", BUTTON, 1)
	upgrade.Size = UDim2.new(0, 220, 1, 0)
	upgrade.TextSize = 15
	local demolish = MenuKit.button(row, "", "danger", BUTTON, 2)
	demolish.Size = UDim2.new(0, 150, 1, 0)
	demolish.TextSize = 15

	local function setLevel(level: number, max: number)
		for k = #pipFrames + 1, max do
			local f = Instance.new("Frame")
			f.Name = "Pip"
			f.LayoutOrder = k
			f.Size = UDim2.fromOffset(14, 14)
			f.BorderSizePixel = 0
			f.Parent = pips
			MenuKit.stroke(f, Theme.color("Ink"), 2)
			pipFrames[k] = f
		end
		for k, f in pipFrames do
			f.Visible = k <= max
			f.BackgroundColor3 = if k <= level then Theme.Colors.Gold else Theme.Colors.Backdrop
		end
		levelText.Text = string.format(Strings.get("info.level", lang), level, max)
	end

	local citySet: { [number]: boolean } = {}
	local cityCount = -1
	-- Здание в клетке: из списка или свой город ур. 1 (у него записи нет).
	local function buildingAt(cell: number): Types.Building?
		local b = cs.buildings[cell]
		if b ~= nil then
			return b
		end
		if #cs.cities ~= cityCount then
			cityCount = #cs.cities
			table.clear(citySet)
			for _, c in cs.cities do
				citySet[c] = true
			end
		end
		return if citySet[cell] then { kind = "City", cell = cell, level = 1 } else nil
	end

	-- Своё здание (или город) в клетке cell или рядом (±1).
	local function buildingNear(cell: number): number?
		local me = cs.myNation
		if me == nil then
			return nil
		end
		local x, y = cell % w, cell // w
		for dy = -1, 1 do
			for dx = -1, 1 do
				local nx, ny = x + dx, y + dy
				if nx >= 0 and ny >= 0 and nx < w and ny < map.height then
					local j = ny * w + nx
					local b = buildingAt(j)
					if b ~= nil and not SKIP[b.kind] and ClientState.ownerAt(cs, j) == me then
						return j
					end
				end
			end
		end
		return nil
	end

	-- Район: лучший уровень своего города не дальше Build.DistrictRadius (как Buildings.owned).
	local function districtBonus(cell: number): number
		local r = Config.Build.DistrictRadius
		local x, y = cell % w, cell // w
		local best = 0
		for _, c in cs.cities do
			if math.abs(c % w - x) <= r and math.abs(c // w - y) <= r and ClientState.ownerAt(cs, c) == cs.myNation then
				best = math.max(best, ClientState.cityLevel(cs, c))
			end
		end
		return best * Config.Build.DistrictPerCityLevel
	end

	local function myPrice(kind: Types.BuildingKind, cell: number): number?
		local set = Buildings.fromList(cs.buildings, map)
		local levels = if kind == "City"
			then 0
			else Buildings.levelsOf(set, function(c: number): number
				return ClientState.ownerAt(cs, c)
			end, cs.myNation or 0, kind)
		local base = Buildings.cost(set, kind, cell, levels)
		return if base ~= nil then base * Commanders.buildCostMul(ClientState.myCommander(cs)) else nil
	end

	local function refresh()
		local cell = open
		local b = if cell ~= nil then buildingAt(cell) else nil
		if cell == nil or b == nil or ClientState.ownerAt(cs, cell) ~= cs.myNation or cs.phase ~= "Play" then
			open = nil
			card.Visible = false
			return
		end
		local max = Buildings.maxLevel(b.kind)
		title.Text = Strings.get("building." .. b.kind, lang)
		CardKit.repaint(art, "building." .. b.kind)
		setLevel(b.level, max)
		effect.Text = Strings.get("building." .. b.kind .. ".hint", lang)
		local bonus = if b.kind == "City" then 0 else districtBonus(cell)
		district.Visible = bonus > 0
		district.Text = string.format(Strings.get("build.district", lang), math.round(bonus * 100))
		upkeep.Visible = b.kind ~= "City"
		upkeep.Text =
			string.format(Strings.get("build.upkeep", lang), string.format("%.1f", Buildings.upkeepOf(b.kind, b.level)))
		infoRow.Visible = district.Visible or upkeep.Visible
		local cost = myPrice(b.kind, cell)
		if cost == nil then
			upgrade.Text = Strings.get("build.maxed", lang)
			upgrade.Active = false
			upgrade.TextTransparency = 0.4
		else
			local money = if cs.myForces ~= nil then cs.myForces.economy.money else 0
			upgrade.Text = string.format(Strings.get("build.upgradeButton", lang), Strings.formatInt(cost))
			upgrade.Active = true
			upgrade.TextTransparency = if money >= cost then 0 else 0.45
		end
		demolish.Visible = b.kind ~= "City"
		demolish.Text = string.format(Strings.get("build.demolish", lang), Strings.formatInt(Buildings.refundOf(b)))
	end

	local function hide()
		open = nil
		card.Visible = false
	end

	Session.connect(upgrade.Activated, function()
		local cell = open
		local b = if cell ~= nil then buildingAt(cell) else nil
		if cell ~= nil and b ~= nil and upgrade.Active then
			send("build", { building = b.kind, cell = cell })
		end
	end)
	Session.connect(demolish.Activated, function()
		local cell = open
		if cell ~= nil then
			send("demolish", { cell = cell })
			hide()
		end
	end)
	Session.connect(close.Activated, hide)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.Escape then
			hide()
		end
	end)

	local function tap(cell: number): boolean
		local found = buildingNear(cell)
		if found == nil or cs.phase ~= "Play" then
			if card.Visible then
				hide()
			end
			return false
		end
		open = found
		card.Visible = true
		refresh()
		return true
	end

	return {
		tap = tap,
		refresh = refresh,
		toggle = function()
			if card.Visible then
				hide()
			end
		end,
		isOpen = function(): boolean
			return card.Visible
		end,
	}
end

return table.freeze(BuildingInfo)
