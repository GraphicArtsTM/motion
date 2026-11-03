--!strict
--[[
	BuildPanel — стройка (GDD §6.9, §10): кнопка «Построить (B)» над карточками найма, меню зданий
	(название, цена, что даёт; не хватает денег — блёкло), выбор здания → режим стройки: следующее нажатие
	на карту — намерение build в эту клетку (сервер ставит здание в центр провинции или улучшает город).
	Esc или кнопка — отмена. Все кнопки от 44 px.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState

export type BuildPanel = {
	refresh: () -> (),
	tap: (cell: number) -> boolean, -- true — нажатие ушло на стройку
}

local BuildPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

local function button(parent: Instance, width: number, height: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, height)
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BackgroundTransparency = 0.1
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.RichText = true
	b.TextWrapped = true
	b.FontFace = Theme.FontBold
	b.TextSize = 14
	b.TextColor3 = Theme.Colors.Text
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = b
	b.Parent = parent
	return b
end

function BuildPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> (),
	toast: (text: string) -> ()
): BuildPanel
	local gold, muted = hex(Theme.Colors.Gold), hex(Theme.Colors.Muted)
	local selected: string? = nil

	local function canBuild(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
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
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeMain)
	placeMain()

	local menu = Instance.new("Frame")
	menu.Name = "BuildMenu"
	menu.BackgroundTransparency = 1
	menu.AnchorPoint = Vector2.new(0.5, 1)
	menu.Position = UDim2.new(0.5, 0, 0, -6)
	menu.Size = UDim2.fromOffset(240, 0)
	menu.AutomaticSize = Enum.AutomaticSize.Y
	menu.Visible = false
	menu.Parent = main
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = menu

	local items: { [string]: TextButton } = {}
	local function cost(kind: string): number
		local stats = (Config.Buildings :: any)[kind]
		return stats.cost
	end
	for k, kind in Config.Buildable do
		local b = button(menu, 240, 52)
		b.LayoutOrder = k
		b.TextXAlignment = Enum.TextXAlignment.Left
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.Parent = b
		items[kind] = b
		b.Activated:Connect(function()
			selected = kind
			menu.Visible = false
			local key = if kind == "City" then "build.pickCity" else "build.pick"
			toast(string.format(Strings.get(key, lang), Strings.get("building." .. kind, lang)))
			main.Text = string.format(Strings.get("build.cancel", lang), Strings.get("building." .. kind, lang))
		end)
	end

	local function cancel()
		selected = nil
		menu.Visible = false
		main.Text = Strings.get("build.button", lang)
	end
	main.Text = Strings.get("build.button", lang)
	main.Activated:Connect(function()
		if selected ~= nil then
			cancel()
		else
			menu.Visible = not menu.Visible
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.B and canBuild() then
			if selected ~= nil then
				cancel()
			else
				menu.Visible = not menu.Visible
			end
		elseif input.KeyCode == Enum.KeyCode.Escape then
			cancel()
		end
	end)

	local function refresh()
		main.Visible = canBuild()
		if not canBuild() then
			cancel()
			return
		end
		local money = if cs.myForces ~= nil then cs.myForces.economy.money else 0
		for kind, b in items do
			local price = cost(kind)
			b.Text = string.format(
				'%s  <font color="%s">$%s</font>\n<font size="12" color="%s">%s</font>',
				Strings.get("building." .. kind, lang),
				gold,
				Strings.formatInt(price),
				muted,
				Strings.get("building." .. kind .. ".hint", lang)
			)
			b.TextTransparency = if money >= price then 0 else 0.5
		end
	end

	local function tap(cell: number): boolean
		local kind = selected
		if kind == nil or not canBuild() then
			return false
		end
		send("build", { building = kind, cell = cell })
		cancel()
		return true
	end

	return { refresh = refresh, tap = tap }
end

return table.freeze(BuildPanel)
