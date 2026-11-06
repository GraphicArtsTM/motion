--!strict
--[[
	BuildPanel — стройка (GDD §6.9, §15г): кнопка «Построить (B)» над карточками найма и меню-карточки зданий
	(значок, название, цена, что даёт; клавиши 1–9 и 0; не хватает денег или технологии — блёкло).
	Выбор здания → режим стройки: за курсором идёт «призрак» (Render/BuildGhost) — зелёный можно, красный нельзя
	и почему, у радара / ПВО / аэродрома круг действия. Проверка — тот же Buildings.check, что на сервере.
	ПК: клик строит (Shift — строить ещё такое же); телефон: первое нажатие ставит призрак, второе туда же —
	строит. Esc или кнопка — отмена. Все кнопки от 44 px.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildingSprites = require(Shared:WaitForChild("BuildingSprites"))
local Buildings = require(Shared:WaitForChild("Buildings"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Commanders = require(Shared:WaitForChild("Commanders"))
local Config = require(Shared:WaitForChild("Config"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local Naval = require(Shared:WaitForChild("Naval"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))
local BuildGhost = require(script.Parent.Parent:WaitForChild("Render"):WaitForChild("BuildGhost"))

type ClientState = ClientState.ClientState

export type BuildPanel = {
	refresh: () -> (),
	tap: (cell: number) -> boolean, -- true — нажатие ушло на стройку
	hover: (cell: number?) -> (), -- курсор над клеткой (ПК)
	active: () -> boolean, -- идёт выбор места
	onBuildings: () -> (), -- здания поменялись (эффект постройки)
}

local BuildPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local CARD_W, CARD_H = 236, 56
local ICON_SCALE = 4
local KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
	Enum.KeyCode.Zero,
}

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

local function button(parent: Instance, width: number, height: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, height)
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BackgroundTransparency = 0.05
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.RichText = true
	b.TextWrapped = true
	b.FontFace = Theme.FontBold
	b.TextSize = 14
	b.TextColor3 = Theme.Colors.Text
	b.Parent = parent
	Theme.decorate(b)
	return b
end

-- Значок здания из BuildingSprites (у «Города» значка нет — золотой квадрат).
local function icon(parent: Instance, kind: string, color: Color3): Frame
	local size = BuildingSprites.Size * ICON_SCALE
	local root = Instance.new("Frame")
	root.Name = "Icon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(size, size)
	root.Position = UDim2.new(0, 8, 0.5, -size // 2)
	root.Parent = parent
	local shape = BuildingSprites.Shapes[kind]
	local tint = color
	if shape == nil then
		shape = { { x = 1, y = 2, w = 5, h = 5, ink = false }, { x = 2, y = 0, w = 3, h = 2, ink = false } }
		tint = Theme.Colors.Gold
	end
	for _, p in shape do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = if p.ink then Theme.Colors.Backdrop else tint
		f.Position = UDim2.fromOffset(p.x * ICON_SCALE, p.y * ICON_SCALE)
		f.Size = UDim2.fromOffset(p.w * ICON_SCALE, p.h * ICON_SCALE)
		f.Parent = root
	end
	return root
end

function BuildPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> (),
	toast: (text: string) -> (),
	map: MapDataModule.MapData,
	provinces: Provinces.ProvinceSet,
	ghost: BuildGhost.BuildGhost
): BuildPanel
	local gold, muted = hex(Theme.Colors.Gold), hex(Theme.Colors.Muted)
	local selected: Types.BuildingKind? = nil
	local pending: number? = nil -- телефон: клетка, где стоит призрак (второе нажатие туда — стройка)
	local lastHover: number? = nil
	local lastCheckAt = 0
	local docks: { [number]: number }? = nil
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

	local function canBuild(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
	end

	local function myColor(): Color3
		local ci = if cs.myNation ~= nil then ClientState.colorIndexOf(cs, cs.myNation) else 0
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Sky
	end

	local function techOpen(kind: string): (boolean, any)
		local need = (Config.Tech.Unlocks :: any)[kind]
		return need == nil or (cs.tech.levels :: any)[need.branch] >= need.level, need
	end

	-- Цена как на сервере (MatchSim.buildPrice): рост цены по своим зданиям этого типа (§15д), скидка Инженера.
	local function price(kind: Types.BuildingKind, cell: number?): number?
		local set = Buildings.fromList(cs.buildings, map)
		local me = cs.myNation or 0
		local levels = if kind == "City"
			then 0
			else Buildings.levelsOf(set, function(c: number): number
				return ClientState.ownerAt(cs, c)
			end, me, kind)
		local base = if cell ~= nil
			then (Buildings.cost(set, kind, cell, levels))
			elseif kind == "City" then (Config.Buildings :: any)[kind].cost :: number
			else Buildings.priceFor(kind, 1, levels)
		if base == nil then
			return nil
		end
		return base * Commanders.buildCostMul(ClientState.myCommander(cs))
	end

	-- Тот же Buildings.check, что на сервере, по клиентской копии мира.
	local function check(kind: Types.BuildingKind, cell: number): (number?, string?)
		local me = cs.myNation
		if me == nil then
			return nil, "focus"
		end
		local citySet: { [number]: boolean } = {}
		for _, c in cs.cities do
			citySet[c] = true
		end
		return Buildings.check(
			Buildings.fromList(cs.buildings, map),
			function(c: number): number
				return ClientState.ownerAt(cs, c)
			end,
			map,
			provinces,
			function(c: number): boolean
				return citySet[c] == true
			end,
			me,
			kind,
			cell,
			function(province: number): boolean
				if docks == nil then
					docks = Naval.buildSea(map, provinces).docks
				end
				return (docks :: { [number]: number })[province] ~= nil
			end,
			function(k: Types.BuildingKind): boolean
				return (techOpen(k))
			end
		)
	end

	local function showGhost(cell: number)
		local kind: Types.BuildingKind? = selected
		if kind == nil then
			ghost.hide()
			return
		end
		local spot, reason = check(kind, cell)
		local money = if cs.myForces ~= nil then cs.myForces.economy.money else 0
		local cost = price(kind, spot or cell)
		local ok = spot ~= nil and cost ~= nil and money >= cost
		local label: string
		if spot == nil then
			label = Strings.get("reject." .. (reason or "focus"), lang)
		elseif cost == nil then
			label = Strings.get("reject.maxLevel", lang)
		elseif money < cost then
			label = string.format("$%s — %s", Strings.formatInt(cost), Strings.get("reject.noMoney", lang))
		else
			local here = cs.buildings[spot]
			label = if here ~= nil
					and here.kind == kind
					and kind ~= "City"
				then string.format(
					Strings.get("build.upgrade", lang),
					Strings.get("building." .. kind, lang),
					here.level + 1,
					Strings.formatInt(cost)
				)
				else string.format("%s  $%s", Strings.get("building." .. kind, lang), Strings.formatInt(cost))
			if touch then
				label ..= "\n" .. Strings.get("build.tapAgain", lang)
			end
		end
		ghost.show({
			kind = kind,
			cell = spot or cell,
			ok = ok,
			label = label,
			range = if ok or spot ~= nil then Buildings.rangeOf(kind, map.width) else nil,
			color = myColor(),
		})
	end

	local main = button(gui, 200, BUTTON)
	main.Name = "BuildButton"
	local function placeMain()
		if gui.AbsoluteSize.X < Config.Render.NarrowScreenPx then
			main.AnchorPoint = Vector2.new(1, 1)
			main.Position = UDim2.new(1, -20 - Config.Render.MinimapSide, 1, -12 - 2 * 56 - 12)
		else
			main.AnchorPoint = Vector2.new(0.5, 1)
			main.Position = UDim2.new(0.5, 0, 1, -12 - 56 - 6)
		end
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), placeMain)
	placeMain()

	local menu = Instance.new("Frame")
	menu.Name = "BuildMenu"
	menu.BackgroundColor3 = Theme.Colors.PanelBg
	menu.BackgroundTransparency = 0.15
	menu.BorderSizePixel = 0
	-- Две колонки: меню не выше экрана телефона; правый край — у кнопки.
	menu.AnchorPoint = Vector2.new(1, 1)
	menu.Position = UDim2.new(1, 0, 0, -8)
	menu.Size = UDim2.fromOffset(2 * CARD_W + 4 + 16, 0)
	menu.AutomaticSize = Enum.AutomaticSize.Y
	menu.Visible = false
	menu.Parent = main
	Theme.decorate(menu)
	local menuPad = Instance.new("UIPadding")
	for _, side in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
		(menuPad :: any)[side] = UDim.new(0, 8)
	end
	menuPad.Parent = menu
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	layout.CellPadding = UDim2.fromOffset(4, 4)
	layout.FillDirectionMaxCells = 2
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = menu
	local keysHint = Instance.new("TextLabel")
	keysHint.Name = "Keys"
	keysHint.LayoutOrder = 100
	keysHint.BackgroundTransparency = 1
	keysHint.FontFace = Theme.Font
	keysHint.TextSize = 12
	keysHint.TextColor3 = Theme.Colors.Muted
	keysHint.TextWrapped = true
	keysHint.Text = Strings.get("build.keys", lang)
	keysHint.Parent = menu

	local items: { [string]: TextButton } = {}
	local icons: { [string]: Frame } = {}

	local function cancel()
		selected = nil
		pending = nil
		menu.Visible = false
		ghost.hide()
		main.Text = Strings.get("build.button", lang)
	end

	local function pick(kind: Types.BuildingKind)
		local open, need = techOpen(kind)
		if not open then
			toast(
				string.format(
					Strings.get("build.needTech", lang),
					Strings.get("tech." .. need.branch .. "." .. need.level, lang)
				)
			)
			return
		end
		selected = kind
		pending = nil
		menu.Visible = false
		local key = if kind == "City" then "build.pickCity" else "build.pick"
		toast(string.format(Strings.get(key, lang), Strings.get("building." .. kind, lang)))
		main.Text = string.format(Strings.get("build.cancel", lang), Strings.get("building." .. kind, lang))
		if lastHover ~= nil and not touch then
			showGhost(lastHover)
		end
	end

	for k, kind in Config.Buildable do
		local b = button(menu, CARD_W, CARD_H)
		b.Name = kind
		b.LayoutOrder = k
		b.TextXAlignment = Enum.TextXAlignment.Left
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8 + BuildingSprites.Size * ICON_SCALE + 8)
		pad.PaddingRight = UDim.new(0, 22)
		pad.Parent = b
		icons[kind] = icon(b, kind, Theme.Colors.Sky)
		icons[kind].Position = UDim2.new(0, -(BuildingSprites.Size * ICON_SCALE + 8), 0.5, -BuildingSprites.Size * 2)
		if k <= #KEYS then
			local badge = Instance.new("TextLabel")
			badge.Name = "Key"
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, 18, 0, 4)
			badge.Size = UDim2.fromOffset(16, 16)
			badge.BackgroundColor3 = Theme.Colors.Slate
			badge.BorderSizePixel = 0
			badge.FontFace = Theme.FontBold
			badge.TextSize = 11
			badge.TextColor3 = Theme.Colors.Gold
			badge.Text = if k == 10 then "0" else tostring(k)
			badge.Parent = b
			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0, 4)
			bc.Parent = badge
		end
		items[kind] = b
		Session.connect(b.Activated, function()
			pick(kind :: Types.BuildingKind)
		end)
	end

	main.Text = Strings.get("build.button", lang)
	local function toggleMenu()
		if selected ~= nil then
			cancel()
		else
			menu.Visible = not menu.Visible
			if menu.Visible then
				Theme.popIn(menu)
			end
		end
	end
	Session.connect(main.Activated, toggleMenu)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.B and canBuild() then
			toggleMenu()
		elseif input.KeyCode == Enum.KeyCode.Escape then
			cancel()
		elseif menu.Visible then
			local k = table.find(KEYS, input.KeyCode)
			if k ~= nil and Config.Buildable[k] ~= nil then
				pick(Config.Buildable[k] :: Types.BuildingKind)
			end
		end
	end)

	local function refresh()
		main.Visible = canBuild()
		if not canBuild() then
			cancel()
			return
		end
		local money = if cs.myForces ~= nil then cs.myForces.economy.money else 0
		local color = myColor()
		for kind, b in items do
			local cost = price(kind :: Types.BuildingKind, nil) or 0
			-- Радар и аэродром открывает технология (§6.14): без неё — какая нужна.
			local open, need = techOpen(kind)
			local hint = if open
				then Strings.get("building." .. kind .. ".hint", lang)
				else string.format(
					Strings.get("build.needTech", lang),
					Strings.get("tech." .. need.branch .. "." .. need.level, lang)
				)
			b.Text = string.format(
				'%s  <font color="%s">$%s</font>\n<font size="12" color="%s">%s</font>',
				Strings.get("building." .. kind, lang),
				gold,
				Strings.formatInt(cost),
				muted,
				hint
			)
			local can = money >= cost and open
			b.TextTransparency = if can then 0 else 0.5
			for _, f in icons[kind]:GetChildren() do
				if f:IsA("Frame") then
					local ink = f.BackgroundColor3 == Theme.Colors.Backdrop
					if not ink and kind ~= "City" then
						f.BackgroundColor3 = color
					end
					f.BackgroundTransparency = if can then 0 else 0.55
				end
			end
		end
		if selected ~= nil and lastHover ~= nil and not touch then
			showGhost(lastHover)
		end
	end

	local function hover(cell: number?)
		lastHover = cell
		if selected == nil or touch then
			return
		end
		if cell == nil then
			ghost.hide()
			return
		end
		local now = os.clock()
		if now - lastCheckAt < Config.Build.GhostEveryMs / 1000 then
			return
		end
		lastCheckAt = now
		showGhost(cell)
	end

	local function tap(cell: number): boolean
		local kind: Types.BuildingKind? = selected
		if kind == nil or not canBuild() then
			return false
		end
		local spot, reason = check(kind, cell)
		if spot == nil then
			-- Нельзя — сразу причина (сервер всё равно проверит сам).
			showGhost(cell)
			toast(Strings.get("reject." .. (reason or "focus"), lang))
			return true
		end
		if touch and pending ~= spot then
			pending = spot
			showGhost(cell)
			return true
		end
		send("build", { building = kind, cell = spot })
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		if shift and not touch then
			pending = nil
		else
			cancel()
		end
		return true
	end

	-- Эффект постройки: новые здания (сравнение с прошлым списком), своё — «−$цена».
	local known: { [number]: string } = {}
	local first = true
	local function onBuildings()
		local fresh: { [number]: string } = {}
		for cell, b in cs.buildings do
			local key = b.kind .. b.level
			fresh[cell] = key
			if not first and known[cell] ~= key then
				local mine = cs.myNation ~= nil and ClientState.ownerAt(cs, cell) == cs.myNation
				local cost = if mine then price(b.kind, nil) else nil
				ghost.built(cell, if cost ~= nil and b.kind ~= "City" then "−$" .. Strings.formatInt(cost) else nil)
			end
		end
		known = fresh
		first = false
	end

	return {
		refresh = refresh,
		tap = tap,
		hover = hover,
		active = function(): boolean
			return selected ~= nil
		end,
		onBuildings = onBuildings,
	}
end

return table.freeze(BuildPanel)
