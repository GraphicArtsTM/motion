--!strict
--[[
	Pings — быстрые фразы и пинги на карте (GDD §8.2, этап 6б).
	«Пинг (G)» → фраза («Помоги здесь», «Атакую сюда», «Союз?», «Спасибо», «Предатель!») → нажатие на карту:
	сервер рассылает событие ping всем. Метка — фраза в рамке цвета державы над клеткой, Pings.ShowSec секунд.
	Текста от игроков нет — только фразы из Strings, фильтр не нужен.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type Pings = {
	refresh: () -> (),
	tap: (cell: number) -> boolean, -- выбрана фраза — нажатие на карту ставит пинг
	onEvents: (events: { any }) -> (),
	onCamera: (state: CameraState) -> (),
	update: (now: number) -> (),
	button: GuiButton, -- §15з: кнопка прячется в док
	toggle: () -> (),
	isOpen: () -> boolean,
}

type Marker = { label: TextLabel, cell: number, untilTime: number }

local Pings = {}

local BUTTON = Config.Render.MinTouchTargetPx

function Pings.new(
	gui: ScreenGui,
	canvas: Frame,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> (),
	toast: (text: string) -> ()
): Pings
	local zoom = 1
	local phrase: string? = nil
	local markers: { Marker } = {}

	local function playing(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
	end

	local function makeButton(parent: Instance, text: string, width: number): TextButton
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(width, BUTTON)
		b.BackgroundColor3 = Theme.Colors.PanelBg
		b.BackgroundTransparency = 0.1
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.FontFace = Theme.FontBold
		b.TextSize = 14
		b.TextColor3 = Theme.Colors.Text
		b.Text = text
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = Theme.Colors.PanelBorder
		stroke.Thickness = Theme.BorderPx
		stroke.Parent = b
		b.Parent = parent
		return b
	end

	-- Кнопка слева от «Дипломатии» (на узком экране — над ней).
	local main = makeButton(gui, Strings.get("ping.button", lang), 130)
	main.Name = "PingButton"
	local function placeMain()
		main.AnchorPoint = Vector2.new(1, 1)
		if gui.AbsoluteSize.X < Config.Render.NarrowScreenPx then
			main.Position = UDim2.new(1, -20 - Config.Render.MinimapSide - 208, 1, -12 - 3 * 56 - 18)
		else
			main.Position = UDim2.new(0.5, -296, 1, -12 - 56 - 6)
		end
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), placeMain)
	placeMain()

	-- Меню фраз над кнопкой.
	local menu = Instance.new("Frame")
	menu.Name = "Phrases"
	menu.AnchorPoint = Vector2.new(0, 1)
	menu.Position = UDim2.fromOffset(0, -6)
	menu.Size = UDim2.fromOffset(170, 0)
	menu.AutomaticSize = Enum.AutomaticSize.Y
	menu.BackgroundTransparency = 1
	menu.Visible = false
	menu.Parent = main
	local menuLayout = Instance.new("UIListLayout")
	menuLayout.Padding = UDim.new(0, 4)
	menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuLayout.Parent = menu
	for k, key in Config.Pings.Phrases do
		local b = makeButton(menu, Strings.get("ping." .. key, lang), 170)
		b.LayoutOrder = k
		Session.connect(b.Activated, function()
			phrase = key
			menu.Visible = false
			toast(Strings.get("ping.hint", lang))
		end)
	end
	Session.connect(main.Activated, function()
		if playing() then
			menu.Visible = not menu.Visible
		end
	end)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.G and playing() then
			menu.Visible = not menu.Visible
		elseif input.KeyCode == Enum.KeyCode.Escape then
			menu.Visible = false
			phrase = nil
		end
	end)

	local function place(marker: Marker)
		local w = cs.width
		local cx, cy = marker.cell % w, marker.cell // w
		local left = CameraMath.cellEdge(zoom, cx)
		marker.label.Position =
			UDim2.fromOffset(left + (CameraMath.cellEdge(zoom, cx + 1) - left) / 2, CameraMath.cellEdge(zoom, cy))
	end

	local function show(nation: number, cell: number, key: string)
		local n = cs.nations[nation]
		local color = Theme.Colors.Gold
		if n ~= nil and n.colorIndex >= 1 then
			local c = NationColors.Colors[n.colorIndex]
			color = Color3.fromRGB(c.r, c.g, c.b)
		end
		local label = Instance.new("TextLabel")
		label.Name = "Ping"
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Size = UDim2.fromOffset(0, 22)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.BackgroundColor3 = Theme.Colors.PanelBg
		label.BackgroundTransparency = 0.1
		label.BorderSizePixel = 0
		label.FontFace = Theme.FontBold
		label.TextSize = 14
		label.TextColor3 = Theme.Colors.Text
		label.Text = "◆ " .. Strings.get("ping." .. key, lang)
		label.ZIndex = 8
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingRight = UDim.new(0, 6)
		pad.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = color
		stroke.Thickness = 2
		stroke.Parent = label
		label.Parent = canvas
		local marker: Marker = { label = label, cell = cell, untilTime = os.clock() + Config.Pings.ShowSec }
		place(marker)
		table.insert(markers, marker)
	end

	local function tap(cell: number): boolean
		local key = phrase
		if key == nil then
			return false
		end
		phrase = nil
		if playing() then
			send("ping", { cell = cell, phrase = key })
		end
		return true
	end

	local function onEvents(events: { any })
		for _, e in events do
			if type(e) == "table" and e.kind == "ping" and type(e.cell) == "number" and type(e.phrase) == "string" then
				if table.find(Config.Pings.Phrases, e.phrase) ~= nil and e.cell >= 0 and e.cell < cs.size then
					show(tonumber(e.nation) or 0, e.cell, e.phrase)
				end
			end
		end
	end

	local function onCamera(state: CameraState)
		zoom = state.zoom
		for _, marker in markers do
			place(marker)
		end
	end

	local function update(now: number)
		local j = 1
		while j <= #markers do
			if now >= markers[j].untilTime then
				markers[j].label:Destroy()
				table.remove(markers, j)
			else
				j += 1
			end
		end
	end

	local function refresh()
		main.Visible = playing()
		if not main.Visible then
			menu.Visible = false
			phrase = nil
		end
	end

	return {
		refresh = refresh,
		tap = tap,
		onEvents = onEvents,
		onCamera = onCamera,
		update = update,
		button = main,
		toggle = function()
			if playing() then
				menu.Visible = not menu.Visible
			end
		end,
		isOpen = function(): boolean
			return menu.Visible
		end,
	}
end

return table.freeze(Pings)
