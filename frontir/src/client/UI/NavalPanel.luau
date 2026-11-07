--!strict
--[[
	NavalPanel — флот (GDD §6.12, этап 7б-1): каждый приказ — два нажатия.
	- Нажатие на свою провинцию с портом → меню порта: «Транспорт», «Эсминец» (найм), «Высадка» (следующее нажатие —
	  берег; сколько войск — ползунок «Атака»), строка с флотом и очередью.
	- Нажатие на свой эсминец → «Патруль»: следующее нажатие — море.
	Esc или «Отмена» — выйти из режима. Все кнопки от 44 px.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Commanders = require(Shared:WaitForChild("Commanders"))
local Config = require(Shared:WaitForChild("Config"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local Naval = require(Shared:WaitForChild("Naval"))
local Protocol = require(Shared:WaitForChild("Net"):WaitForChild("Protocol"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState
type MapData = MapDataModule.MapData

export type NavalPanel = {
	refresh: () -> (),
	tap: (cell: number, zoom: number) -> boolean, -- true — нажатие ушло флоту
	-- Самопроверка (сводная правка, часть 1): закрыть меню и узнать, открыто ли.
	close: () -> (),
	isOpen: () -> boolean,
}

export type ShipPicker = (x: number, y: number, owner: number, reach: number) -> Protocol.ShipInfo?

local NavalPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx

function NavalPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	map: MapData,
	provinces: Provinces.ProvinceSet,
	send: (string, { [string]: any }) -> (),
	percent: () -> number,
	pick: ShipPicker,
	selectShip: (id: number?) -> ()
): NavalPanel
	local w = map.width
	local sea: Naval.SeaMap? = nil -- море считаем при первом открытии меню порта (~0.2 с)
	local port: number? = nil -- открытый порт (клетка здания)
	local mode: "land" | "patrol" | nil = nil
	local ship: number? = nil

	local function seaMap(): Naval.SeaMap
		if sea == nil then
			sea = Naval.buildSea(map, provinces)
		end
		return sea :: Naval.SeaMap
	end

	local function playing(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
	end

	-- Меню порта (§15л ч.11): шапка с картинкой порта, плитки найма кораблей, кнопка «Высадка».
	local dock = CardKit.dock(
		gui,
		"NavalPanel",
		"naval.port",
		{ "naval.Transport", "naval.Destroyer" },
		Strings.get("dock.hire", lang)
	)
	local panel = dock.frame
	local title, status = dock.title, dock.status
	local hireTransport, hireDestroyer = dock.hires[1].button, dock.hires[2].button
	local landButton = dock.action
	local closeButton = dock.close

	-- Строка режима (выбор берега или моря) сверху по центру.
	local modeLine = Instance.new("TextButton")
	modeLine.Name = "NavalMode"
	modeLine.AnchorPoint = Vector2.new(0.5, 0)
	modeLine.Position = UDim2.new(0.5, 0, 0, 132)
	modeLine.Size = UDim2.fromOffset(460, BUTTON)
	modeLine.BackgroundColor3 = Theme.Colors.PanelBg
	modeLine.BorderSizePixel = 0
	modeLine.FontFace = Theme.FontBold
	modeLine.TextSize = 14
	modeLine.TextColor3 = Theme.Colors.Gold
	modeLine.TextWrapped = true
	modeLine.Visible = false
	modeLine.Parent = gui

	local function setMode(m: "land" | "patrol" | nil, text: string?)
		mode = m
		modeLine.Visible = m ~= nil
		if text ~= nil then
			modeLine.Text = text .. "  ·  " .. Strings.get("naval.cancel", lang)
		end
		if m ~= "patrol" then
			ship = nil
			selectShip(nil)
		end
	end
	Session.connect(modeLine.Activated, function()
		setMode(nil)
	end)

	-- Свои транспорты у причала порта (стоят).
	local function readyTransports(at: number): number
		local dock = seaMap().docks[MapDataModule.getProvince(map, at)]
		if dock == nil then
			return 0
		end
		local count = 0
		for _, s in cs.ships.ships do
			if s.owner == cs.myNation and s.kind == "Transport" and s.state == "docked" then
				if math.floor(s.y) * w + math.floor(s.x) == dock then
					count += 1
				end
			end
		end
		return count
	end

	local function drawPanel()
		local at = port
		if at == nil then
			panel.Visible = false
			return
		end
		local transports, destroyers = 0, 0
		for _, s in cs.ships.ships do
			if s.owner == cs.myNation then
				if s.kind == "Transport" then
					transports += 1
				elseif s.kind == "Destroyer" then -- торговые суда (§15е) в счёт не идут
					destroyers += 1
				end
			end
		end
		title.Text = Strings.get("naval.title", lang)
		local blocked = ClientState.isBlocked(cs, at)
		status.Text = if blocked
			then Strings.get("naval.blocked", lang)
			else string.format(Strings.get("naval.status", lang), transports, destroyers, #cs.ships.queue)
		status.TextColor3 = if blocked then Theme.Colors.Alert else Theme.Colors.Muted
		local function hireText(kind: string): string
			local stats = (Config.Units :: any)[kind]
			-- «Верфи» (§6.14): корабли дешевле; цену считает сервер, здесь — та же формула.
			local cost = stats.cost
				* (if cs.tech.levels.Fleet >= 1 then 1 - Config.Tech.ShipyardDiscount else 1)
				* Commanders.shipCostMul(ClientState.myCommander(cs)) -- Адмирал (§6.15)
			return string.format(Strings.get("dock.price", lang), Strings.formatInt(cost), Strings.formatInt(stats.oil))
		end
		for k, kind in { "Transport", "Destroyer" } do
			local tile = dock.hires[k]
			tile.name.Text = string.format(
				'%s  <font color="#%s">×%d</font>',
				Strings.get("ship." .. kind, lang),
				Theme.Colors.Muted:ToHex(),
				if kind == "Transport" then transports else destroyers
			)
			tile.price.Text = hireText(kind)
		end
		local ready = readyTransports(at)
		landButton.Text = string.format(Strings.get("naval.land", lang), ready)
		landButton.TextTransparency = if ready > 0 then 0 else 0.4
		panel.Visible = true
	end

	local function close()
		port = nil
		panel.Visible = false
	end
	Session.connect(closeButton.Activated, close)
	Session.connect(hireTransport.Activated, function()
		if port ~= nil then
			send("ship", { ship = "Transport", port = port })
		end
	end)
	Session.connect(hireDestroyer.Activated, function()
		if port ~= nil then
			send("ship", { ship = "Destroyer", port = port })
		end
	end)
	Session.connect(landButton.Activated, function()
		if port ~= nil then
			panel.Visible = false
			setMode("land", Strings.get("naval.pickCoast", lang))
		end
	end)

	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			setMode(nil)
			close()
		end
	end)

	-- Свой порт в провинции клетки cell (клетка здания) или nil.
	local function portAt(cell: number): number?
		local id = MapDataModule.getProvince(map, cell)
		local province = if id ~= 0 then provinces.list[id] else nil
		if province == nil then
			return nil
		end
		local b = cs.buildings[province.center]
		if b ~= nil and b.kind == "Port" and ClientState.ownerAt(cs, province.center) == cs.myNation then
			return province.center
		end
		return nil
	end

	local function tap(cell: number, zoom: number): boolean
		if not playing() then
			return false
		end
		local me = cs.myNation :: number
		if mode == "land" and port ~= nil then
			send("land", { port = port, target = cell, percent = percent() })
			setMode(nil)
			close()
			return true
		elseif mode == "patrol" and ship ~= nil then
			send("patrol", { ship = ship, cell = cell })
			setMode(nil)
			return true
		end
		-- Свой эсминец рядом с нажатием (с запасом на палец): патруль.
		local reach = math.max(1.5, 14 / math.max(zoom, 0.5))
		local picked = pick(cell % w + 0.5, cell // w + 0.5, me, reach)
		if picked ~= nil and picked.kind == "Destroyer" then
			close()
			ship = picked.id
			selectShip(picked.id)
			setMode("patrol", Strings.get("naval.pickSea", lang))
			return true
		end
		local at = portAt(cell)
		if at ~= nil then
			setMode(nil)
			port = at
			drawPanel()
			return true
		end
		return false
	end

	return {
		close = close,
		isOpen = function(): boolean
			return panel.Visible
		end,
		refresh = function()
			if not playing() then
				setMode(nil)
				close()
				return
			end
			if panel.Visible then
				drawPanel()
			end
		end,
		tap = tap,
	}
end

return table.freeze(NavalPanel)
