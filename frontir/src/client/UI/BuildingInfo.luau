--!strict
--[[
	BuildingInfo — окно своего здания (§15д): нажатие на своё здание (±1 клетка) — карточка над кнопкой
	«Построить»: название и уровень, что даёт, район города, содержание; кнопки «Улучшить ($…)» и «Снести (+$…)».
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

	local card = Instance.new("Frame")
	card.Name = "BuildingInfoPanel"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -12 - 56 - 6 - BUTTON - 10)
	card.Size = UDim2.fromOffset(340, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Theme.Colors.PanelBg
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = gui
	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
		(pad :: any)[side] = UDim.new(0, 10)
	end
	pad.Parent = card
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = card

	local function label(order: number, size: number, bold: boolean): TextLabel
		local t = Instance.new("TextLabel")
		t.LayoutOrder = order
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 0)
		t.AutomaticSize = Enum.AutomaticSize.Y
		t.TextWrapped = true
		t.RichText = true
		t.FontFace = if bold then Theme.FontBold else Theme.Font
		t.TextSize = size
		t.TextColor3 = Theme.Colors.Text
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.Parent = card
		return t
	end
	local title = label(1, 18, true)
	title.TextColor3 = Theme.Colors.Gold
	local effect = label(2, 14, false)
	local district = label(3, 13, false)
	district.TextColor3 = Theme.Colors.Sky
	local upkeep = label(4, 13, false)
	upkeep.TextColor3 = Theme.Colors.Muted

	local row = Instance.new("Frame")
	row.LayoutOrder = 5
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, BUTTON)
	row.Parent = card
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.Padding = UDim.new(0, 6)
	rowList.Parent = row
	local function button(text: string, width: number): TextButton
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(width, BUTTON)
		b.BackgroundColor3 = Theme.Colors.Slate
		b.BorderSizePixel = 0
		b.FontFace = Theme.FontBold
		b.TextSize = 14
		b.TextColor3 = Theme.Colors.Text
		b.Text = text
		b.Parent = row
		Theme.decorate(b)
		return b
	end
	local upgrade = button("", 150)
	upgrade.TextColor3 = Theme.Colors.Gold
	local demolish = button("", 120)
	local close = button("×", BUTTON)

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
		local name = Strings.get("building." .. b.kind, lang)
		title.Text = string.format(Strings.get("build.levelOf", lang), name, b.level, max)
		effect.Text = Strings.get("building." .. b.kind .. ".hint", lang)
		local bonus = if b.kind == "City" then 0 else districtBonus(cell)
		district.Visible = bonus > 0
		district.Text = string.format(Strings.get("build.district", lang), math.round(bonus * 100))
		upkeep.Visible = b.kind ~= "City"
		upkeep.Text =
			string.format(Strings.get("build.upkeep", lang), string.format("%.1f", Buildings.upkeepOf(b.kind, b.level)))
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
