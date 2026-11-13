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
local CitySprites = require(Shared:WaitForChild("CitySprites"))
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

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))
local BuildGhost = require(script.Parent.Parent:WaitForChild("Render"):WaitForChild("BuildGhost"))

type ClientState = ClientState.ClientState

export type BuildPanel = {
	refresh: () -> (),
	tap: (cell: number) -> boolean, -- true — нажатие ушло на стройку
	hover: (cell: number?) -> (), -- курсор над клеткой (ПК)
	active: () -> boolean, -- идёт выбор места
	onBuildings: () -> (), -- здания поменялись (эффект постройки)
	open: () -> (), -- открыть меню стройки (кольцо действий, §15е)
	button: GuiButton, -- §15з: кнопка прячется в док
	toggle: () -> (),
	isOpen: () -> boolean,
	-- §15л ч.2: быстрые клетки стройки в командной полосе.
	menu: Frame,
	pick: (kind: Types.BuildingKind) -> (),
	price: (kind: Types.BuildingKind) -> number?,
	unlocked: (kind: Types.BuildingKind) -> boolean, -- технология открыта
	selected: () -> Types.BuildingKind?,
	canBuild: () -> boolean,
	color: () -> Color3, -- цвет своей державы (значки)
}

local BuildPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local ITEM_W, ITEM_H = 120, 152 -- §15л ч.10: карточка здания в меню стройки
local ICON_SCALE = 3 -- значок 12×12 → 36 px (§15д ч.4)
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
	local r, g, b = math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255)
	local rects: { { x: number, y: number, w: number, h: number, c: Color3 } } = {}
	if shape == nil then
		-- Город (§15д ч.4): посёлок из CitySprites.
		for _, cp in CitySprites.parts(1, false) do
			table.insert(
				rects,
				{ x = cp.x, y = cp.y, w = cp.w, h = cp.h, c = Color3.fromRGB(CitySprites.rgb(cp, r, g, b)) }
			)
		end
	else
		for _, bp in shape do
			table.insert(
				rects,
				{ x = bp.x, y = bp.y, w = bp.w, h = bp.h, c = Color3.fromRGB(BuildingSprites.rgb(bp, r, g, b)) }
			)
		end
	end
	for _, p in rects do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = p.c
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

	-- Клетка — город (по списку городов клиента).
	local function isCityCell(cell: number): boolean
		return table.find(cs.cities, cell) ~= nil
	end
	-- Основанные мной города: города не из карты (реальные и придуманные при сборке — в provinces.cityNames).
	local function foundedMine(): number
		local n = 0
		for _, c in cs.cities do
			if provinces.cityNames[c] == nil and ClientState.ownerAt(cs, c) == cs.myNation then
				n += 1
			end
		end
		return n
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
		if kind == "City" and cell ~= nil and not isCityCell(cell) then
			return Buildings.foundPrice(foundedMine()) * Commanders.buildCostMul(ClientState.myCommander(cs))
		end
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
		elseif kind == "City" and not isCityCell(spot) then
			-- Новый город (§15д ч.4): название — то же, что даст сервер.
			local name = Provinces.foundedName(map, spot)
			label = string.format(
				Strings.get("build.found", lang),
				if lang == "en" then name.en else name.ru,
				Strings.formatInt(cost)
			)
			if touch then
				label ..= "\n" .. Strings.get("build.tapAgain", lang)
			end
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
		if UiScale.size(gui).X < Config.Render.NarrowScreenPx then
			main.AnchorPoint = Vector2.new(1, 1)
			main.Position = UDim2.new(1, -20 - Config.Render.MinimapSide, 1, -12 - 2 * 56 - 12)
		else
			main.AnchorPoint = Vector2.new(0.5, 1)
			main.Position = UDim2.new(0.5, 0, 1, -12 - 56 - 6)
		end
	end
	UiScale.onResize(gui, placeMain)
	placeMain()

	-- §15л ч.10: меню стройки — карточки зданий (картинка ItemArt, название, цена, подсказка, клавиша).
	local COLS = 7
	local MENU_W = COLS * ITEM_W + (COLS - 1) * 6 + 24
	local menu = Instance.new("Frame")
	menu.Name = "BuildMenu"
	menu.BackgroundColor3 = Theme.Colors.PanelBg
	menu.BorderSizePixel = 0
	-- §15л ч.2: меню — прямо в HUD снизу по центру; над командной полосой его ставит Main.client.
	menu.AnchorPoint = Vector2.new(0.5, 1)
	menu.Position = UDim2.new(0.5, 0, 1, -110)
	menu.Size = UDim2.fromOffset(MENU_W, 0)
	menu.AutomaticSize = Enum.AutomaticSize.Y
	menu.Visible = false
	menu.Parent = gui
	MenuKit.stroke(menu, Theme.Colors.PanelBorder, 2)
	MenuKit.pad(menu, 12, 10)
	MenuKit.list(menu, 8)
	local menuScale = Instance.new("UIScale")
	menuScale.Parent = menu
	local function fitMenu()
		menuScale.Scale = math.clamp((UiScale.size(gui).X - 24) / MENU_W, 0.45, 1)
	end
	UiScale.onResize(gui, fitMenu)
	fitMenu()
	local menuHead = Instance.new("Frame")
	menuHead.BackgroundTransparency = 1
	menuHead.Size = UDim2.new(1, 0, 0, 24)
	menuHead.LayoutOrder = 1
	menuHead.Parent = menu
	MenuKit.label(menuHead, Strings.get("build.title", lang), 18, Theme.Colors.Gold, true)
	local keysHint = MenuKit.label(menuHead, Strings.get("build.keys", lang), 12, Theme.Colors.Muted)
	keysHint.AnchorPoint = Vector2.new(1, 0)
	keysHint.Position = UDim2.new(1, 0, 0, 4)
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 2
	grid.Parent = menu
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(ITEM_W, ITEM_H)
	gridLayout.CellPadding = UDim2.fromOffset(6, 6)
	gridLayout.FillDirectionMaxCells = COLS
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

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

	type Item = { name: TextLabel, price: TextLabel, hint: TextLabel, dim: Frame }
	local cards: { [string]: Item } = {}
	for k, kind in Config.Buildable do
		local b = Instance.new("TextButton")
		b.Name = kind
		b.LayoutOrder = k
		b.Text = ""
		b.AutoButtonColor = true
		b.BackgroundColor3 = Theme.Colors.Backdrop
		b.BorderSizePixel = 0
		b.Parent = grid
		MenuKit.stroke(b, Theme.Colors.PanelBorder, 2)
		local art = CardKit.art(b, "building." .. kind, ITEM_W - 12, 72)
		art.Position = UDim2.fromOffset(6, 6)
		local dim = Instance.new("Frame")
		dim.BackgroundColor3 = Theme.color("Ink")
		dim.BackgroundTransparency = 0.6
		dim.BorderSizePixel = 0
		dim.Position = UDim2.fromOffset(6, 6)
		dim.Size = UDim2.fromOffset(ITEM_W - 12, 72)
		dim.Visible = false
		dim.Parent = b
		if k <= #KEYS then
			local badge = MenuKit.label(b, if k == 10 then "0" else tostring(k), 12, Theme.Colors.Gold, true)
			badge.AutomaticSize = Enum.AutomaticSize.None
			badge.Position = UDim2.fromOffset(8, 8)
			badge.Size = UDim2.fromOffset(18, 18)
			badge.TextXAlignment = Enum.TextXAlignment.Center
			badge.BackgroundTransparency = 0
			badge.BackgroundColor3 = Theme.color("Ink")
			badge.ZIndex = 3
		end
		local name = MenuKit.label(b, Strings.get("building." .. kind, lang), 13, Theme.Colors.Text, true)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.Position = UDim2.fromOffset(6, 82)
		name.Size = UDim2.fromOffset(ITEM_W - 12, 16)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local priceLabel = MenuKit.label(b, "", 13, Theme.Colors.Gold, true)
		priceLabel.AutomaticSize = Enum.AutomaticSize.None
		priceLabel.Position = UDim2.fromOffset(6, 100)
		priceLabel.Size = UDim2.fromOffset(ITEM_W - 12, 16)
		local hint = MenuKit.label(b, "", 10, Theme.Colors.Muted)
		hint.AutomaticSize = Enum.AutomaticSize.None
		hint.Position = UDim2.fromOffset(6, 118)
		hint.Size = UDim2.fromOffset(ITEM_W - 12, 28)
		hint.TextWrapped = true
		hint.TextYAlignment = Enum.TextYAlignment.Top
		cards[kind] = { name = name, price = priceLabel, hint = hint, dim = dim }
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
		elseif menu.Visible or canBuild() then
			-- §15л ч.2: 1–0 выбирают здание сразу (как клетки командной полосы), меню не нужно.
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
		for kind, c in cards do
			local cost = price(kind :: Types.BuildingKind, nil) or 0
			-- Радар и аэродром открывает технология (§6.14): без неё — какая нужна.
			local open, need = techOpen(kind)
			c.hint.Text = if open
				then Strings.get("building." .. kind .. ".hint", lang)
				else string.format(
					Strings.get("build.needTech", lang),
					Strings.get("tech." .. need.branch .. "." .. need.level, lang)
				)
			c.price.Text = "$" .. Strings.formatInt(cost)
			local can = money >= cost and open
			c.price.TextColor3 = if can
				then Theme.Colors.Gold
				elseif open then Theme.Colors.Alert
				else Theme.Colors.Muted
			c.name.TextColor3 = if can then Theme.Colors.Text else Theme.Colors.Muted
			c.dim.Visible = not can
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
		open = function()
			if canBuild() and not menu.Visible then
				toggleMenu()
			end
		end,
		button = main,
		toggle = function()
			if canBuild() or selected ~= nil or menu.Visible then
				toggleMenu()
			end
		end,
		isOpen = function(): boolean
			return menu.Visible or selected ~= nil
		end,
		menu = menu,
		pick = function(kind: Types.BuildingKind)
			if not canBuild() then
				return
			end
			if selected == kind then
				cancel() -- повторное нажатие на ту же клетку — отмена
			else
				pick(kind)
			end
		end,
		price = function(kind: Types.BuildingKind): number?
			return price(kind, nil)
		end,
		unlocked = function(kind: Types.BuildingKind): boolean
			return (techOpen(kind))
		end,
		selected = function(): Types.BuildingKind?
			return selected
		end,
		canBuild = canBuild,
		color = myColor,
	}
end

-- §15л ч.2: значок здания (цветом державы) — и для клеток командной полосы.
BuildPanel.icon = icon

return table.freeze(BuildPanel)
