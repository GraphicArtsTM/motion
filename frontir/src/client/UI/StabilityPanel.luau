--!strict
--[[
	StabilityPanel — режим карты «Стабильность» (GDD §6.10, этап 7а): кнопка «Стабильность (N)» рядом с «Построить»
	(на узком экране — над ней) и клавиша N. Включён — свои провинции на карте цветом стабильности (рисует
	TerritoryLayer), а с зума Render.StabilityLabelZoom в центре каждой своей провинции — число.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))
local TerritoryPaint = require(Shared:WaitForChild("TerritoryPaint"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type StabilityPanel = {
	refresh: () -> (), -- пришла стабильность или сменилась фаза
	onCamera: (state: CameraState) -> (),
	-- §15з док: кнопка (прячется в док) и включение режима карты.
	button: GuiButton,
	toggle: () -> (),
	isOpen: () -> boolean,
}

local StabilityPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx

function StabilityPanel.new(
	gui: ScreenGui,
	canvas: Frame,
	cs: ClientState,
	lang: Strings.Lang,
	provinces: Provinces.ProvinceSet,
	setMode: (on: boolean) -> ()
): StabilityPanel
	local on = false
	local zoom = 1
	local labels: { [number]: TextLabel } = {}

	local main = Instance.new("TextButton")
	main.Name = "StabilityButton"
	main.Size = UDim2.fromOffset(180, BUTTON)
	main.BackgroundColor3 = Theme.Colors.PanelBg
	main.BackgroundTransparency = 0.1
	main.BorderSizePixel = 0
	main.AutoButtonColor = true
	main.FontFace = Theme.FontBold
	main.TextSize = 14
	main.TextColor3 = Theme.Colors.Text
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = main
	main.Parent = gui
	-- Справа от «Построить» (на узком экране — над ней).
	local function place()
		if gui.AbsoluteSize.X < Config.Render.NarrowScreenPx then
			main.AnchorPoint = Vector2.new(1, 1)
			main.Position = UDim2.new(1, -20 - Config.Render.MinimapSide, 1, -12 - 3 * 56 - 18)
		else
			main.AnchorPoint = Vector2.new(0, 1)
			main.Position = UDim2.new(0.5, 108, 1, -12 - 56 - 6)
		end
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), place)
	place()

	local function playing(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
	end

	local function clearLabels()
		for _, l in labels do
			l:Destroy()
		end
		table.clear(labels)
	end

	local function placeLabel(l: TextLabel, cell: number)
		local w = cs.width
		local cx, cy = cell % w, cell // w
		local left, top = CameraMath.cellEdge(zoom, cx), CameraMath.cellEdge(zoom, cy)
		l.Position = UDim2.fromOffset(
			left + (CameraMath.cellEdge(zoom, cx + 1) - left) / 2,
			top + (CameraMath.cellEdge(zoom, cy + 1) - top) / 2
		)
	end

	-- Числа на своих провинциях: только в режиме и с достаточного зума.
	local function drawLabels()
		local show = on and playing() and zoom >= Config.Render.StabilityLabelZoom
		if not show then
			clearLabels()
			return
		end
		local seen: { [number]: boolean } = {}
		for k, p in cs.stability.ids do
			local province = provinces.list[p]
			if province ~= nil then
				seen[p] = true
				local label: TextLabel
				local existing: TextLabel? = labels[p]
				if existing ~= nil then
					label = existing
				else
					local made = Instance.new("TextLabel")
					made.Name = "Stability_" .. p
					made.AnchorPoint = Vector2.new(0.5, 0.5)
					made.Size = UDim2.fromOffset(34, 18)
					made.BackgroundColor3 = Theme.Colors.Backdrop
					made.BackgroundTransparency = 0.25
					made.BorderSizePixel = 0
					made.FontFace = Theme.FontBold
					made.TextSize = 13
					made.ZIndex = 8
					made.Parent = canvas
					labels[p] = made
					label = made
				end
				local value = cs.stability.values[k] or 0
				local r, g, b = TerritoryPaint.stabilityColor(value)
				label.Text = tostring(value)
				label.TextColor3 = Color3.fromRGB(r, g, b)
				placeLabel(label, province.center)
			end
		end
		for p, l in labels do
			if not seen[p] then
				l:Destroy()
				labels[p] = nil
			end
		end
	end

	local function setOn(value: boolean)
		on = value
		main.Text = Strings.get(if on then "stability.buttonOn" else "stability.button", lang)
		setMode(on)
		drawLabels()
	end
	setOn(false)

	Session.connect(main.Activated, function()
		setOn(not on)
	end)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.N and playing() then
			setOn(not on)
		end
	end)

	return {
		button = main,
		toggle = function()
			setOn(not on)
		end,
		isOpen = function(): boolean
			return on
		end,
		refresh = function()
			main.Visible = playing()
			if not playing() and on then
				setOn(false)
			end
			drawLabels()
		end,
		onCamera = function(state: CameraState)
			if state.zoom ~= zoom then
				zoom = state.zoom
				drawLabels()
			end
		end,
	}
end

return table.freeze(StabilityPanel)
