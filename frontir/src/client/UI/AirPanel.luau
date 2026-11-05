--!strict
--[[
	AirPanel — авиация (GDD §6.13, этап 7б-2).
	- Нажатие на свою провинцию с аэродромом → меню аэродрома: «Истребитель», «Бомбардировщик» (найм), «Налёт»
	  (следующее нажатие — цель: линия фронта или здание врага), строка с самолётами и очередью.
	- Нажатие на свой истребитель → «Прикрытие»: следующее нажатие — точка, вокруг которой он перехватывает.
	Esc или нажатие на строку режима — отмена. Все кнопки от 44 px.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local Protocol = require(Shared:WaitForChild("Net"):WaitForChild("Protocol"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type MapData = MapDataModule.MapData

export type AirPanel = {
	refresh: () -> (),
	tap: (cell: number, zoom: number) -> boolean, -- true — нажатие ушло авиации
}

export type PlanePicker = (x: number, y: number, owner: number, reach: number) -> Protocol.PlaneInfo?

local AirPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx

function AirPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	map: MapData,
	provinces: Provinces.ProvinceSet,
	send: (string, { [string]: any }) -> (),
	pick: PlanePicker,
	selectPlane: (id: number?) -> ()
): AirPanel
	local w = map.width
	local airfield: number? = nil -- открытый аэродром (клетка здания)
	local mode: "raid" | "cover" | nil = nil
	local plane: number? = nil

	local function playing(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
	end

	local function makeButton(parent: Instance): TextButton
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, 0, 0, BUTTON)
		b.BackgroundColor3 = Theme.Colors.Backdrop
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.FontFace = Theme.FontBold
		b.TextSize = 14
		b.TextColor3 = Theme.Colors.Text
		b.Parent = parent
		return b
	end

	local panel = Instance.new("Frame")
	panel.Name = "AirPanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -150)
	panel.Size = UDim2.fromOffset(300, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Theme.Colors.PanelBg
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 15
	panel.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 8)
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 22)
	title.FontFace = Theme.FontBold
	title.TextSize = 15
	title.TextColor3 = Theme.Colors.Gold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.LayoutOrder = 1
	title.Parent = panel
	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, 0, 0, 18)
	status.FontFace = Theme.Font
	status.TextSize = 13
	status.TextColor3 = Theme.Colors.Muted
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextWrapped = true
	status.LayoutOrder = 2
	status.Parent = panel
	local hireFighter = makeButton(panel)
	hireFighter.LayoutOrder = 3
	local hireBomber = makeButton(panel)
	hireBomber.LayoutOrder = 4
	local raidButton = makeButton(panel)
	raidButton.LayoutOrder = 5
	local closeButton = makeButton(panel)
	closeButton.LayoutOrder = 6

	local modeLine = Instance.new("TextButton")
	modeLine.Name = "AirMode"
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

	local function setMode(m: "raid" | "cover" | nil, text: string?)
		mode = m
		modeLine.Visible = m ~= nil
		if text ~= nil then
			modeLine.Text = text .. "  ·  " .. Strings.get("naval.cancel", lang)
		end
		if m ~= "cover" then
			plane = nil
			selectPlane(nil)
		end
	end
	modeLine.Activated:Connect(function()
		setMode(nil)
	end)

	local function drawPanel()
		local at = airfield
		if at == nil then
			panel.Visible = false
			return
		end
		local fighters, bombers, ready = 0, 0, 0
		for _, p in cs.air.planes do
			if p.owner == cs.myNation then
				if p.kind == "Fighter" then
					fighters += 1
				else
					bombers += 1
					if p.state == "based" then
						ready += 1
					end
				end
			end
		end
		title.Text = Strings.get("air.title", lang)
		local off = ClientState.isDisabled(cs, at)
		status.Text = if off
			then Strings.get("air.disabled", lang)
			else string.format(Strings.get("air.status", lang), fighters, bombers, #cs.air.queue)
		status.TextColor3 = if off then Theme.Colors.Alert else Theme.Colors.Muted
		local function hireText(kind: string): string
			local stats = (Config.Units :: any)[kind]
			return string.format(
				Strings.get("naval.hire", lang),
				Strings.get("plane." .. kind, lang),
				Strings.formatInt(stats.cost),
				Strings.formatInt(stats.oil)
			)
		end
		hireFighter.Text = hireText("Fighter")
		hireBomber.Text = hireText("Bomber")
		raidButton.Text = string.format(Strings.get("air.raid", lang), ready)
		closeButton.Text = Strings.get("naval.close", lang)
		panel.Visible = true
	end

	local function close()
		airfield = nil
		panel.Visible = false
	end
	closeButton.Activated:Connect(close)
	hireFighter.Activated:Connect(function()
		if airfield ~= nil then
			send("plane", { plane = "Fighter", airfield = airfield })
		end
	end)
	hireBomber.Activated:Connect(function()
		if airfield ~= nil then
			send("plane", { plane = "Bomber", airfield = airfield })
		end
	end)
	raidButton.Activated:Connect(function()
		if airfield ~= nil then
			close()
			setMode("raid", Strings.get("air.pickTarget", lang))
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			setMode(nil)
			close()
		end
	end)

	-- Свой аэродром в провинции клетки cell (клетка здания) или nil.
	local function airfieldAt(cell: number): number?
		local id = MapDataModule.getProvince(map, cell)
		local province = if id ~= 0 then provinces.list[id] else nil
		if province == nil then
			return nil
		end
		local b = cs.buildings[province.center]
		if b ~= nil and b.kind == "Airfield" and ClientState.ownerAt(cs, province.center) == cs.myNation then
			return province.center
		end
		return nil
	end

	local function tap(cell: number, zoom: number): boolean
		if not playing() then
			return false
		end
		local me = cs.myNation :: number
		if mode == "raid" then
			send("raid", { cell = cell })
			setMode(nil)
			return true
		elseif mode == "cover" and plane ~= nil then
			send("cover", { plane = plane, cell = cell })
			setMode(nil)
			return true
		end
		-- Свой истребитель рядом с нажатием: прикрытие.
		local reach = math.max(1.5, 14 / math.max(zoom, 0.5))
		local picked = pick(cell % w + 0.5, cell // w + 0.5, me, reach)
		if picked ~= nil and picked.kind == "Fighter" then
			close()
			plane = picked.id
			selectPlane(picked.id)
			setMode("cover", Strings.get("air.pickCover", lang))
			return true
		end
		local at = airfieldAt(cell)
		if at ~= nil then
			setMode(nil)
			airfield = at
			drawPanel()
			return true
		end
		return false
	end

	return {
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

return table.freeze(AirPanel)
