--!strict
--[[
	GameMenu — меню игры (GDD §15л): кнопка «≡» слева сверху (и Tab) во время матча и в лобби. Окно по центру:
	«МЕНЮ», карта и режим; «Продолжить», «Как играть», «Звук», «Магазин», «Главное меню». Матч не на паузе —
	об этом строка внизу. Escape закрывает окно. Окно — в слое окон, кнопка «≡» — в HUD.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type Actions = {
	help: () -> (),
	sound: () -> (),
	shop: () -> (),
	mainMenu: () -> (),
	blocked: () -> boolean, -- открыто главное меню — Tab ничего не делает
}

export type GameMenu = {
	toggle: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	button: TextButton,
	window: Frame,
}

local GameMenu = {}

function GameMenu.new(
	hudGui: ScreenGui,
	windows: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	mapName: string,
	act: Actions
): GameMenu
	local cfg = Config.Render.Menu
	local function t(key: string): string
		return Strings.get(key, lang)
	end

	-- Кнопка «≡» в HUD слева сверху.
	local button = Instance.new("TextButton")
	button.Name = "MenuButton"
	button.Position = UDim2.fromOffset(12, 8)
	button.Size = UDim2.fromOffset(MenuKit.Touch, MenuKit.Touch)
	button.BackgroundColor3 = Theme.Colors.PanelBg
	button.BorderSizePixel = 0
	button.FontFace = Theme.FontBold
	button.TextSize = 24
	button.TextColor3 = Theme.Colors.Gold
	button.Text = "≡"
	button.Parent = hudGui
	MenuKit.corner(button, 8)
	MenuKit.stroke(button, Theme.Colors.PanelBorder, 2)

	local window = Instance.new("Frame")
	window.Name = "GameMenuWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(cfg.GameMenuWidthPx, 0)
	window.AutomaticSize = Enum.AutomaticSize.Y
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BorderSizePixel = 0
	window.Active = true
	window.Visible = false
	window.Parent = windows
	MenuKit.corner(window, 8)
	MenuKit.stroke(window, Theme.Colors.PanelBorder, 2)
	MenuKit.pad(window, 18, 16)
	MenuKit.list(window, 10)

	MenuKit.label(window, t("gamemenu.title"), 26, Theme.Colors.Gold, true, 1)
	local sub = MenuKit.label(window, "", 13, Theme.Colors.Muted, false, 2)
	local line = Instance.new("Frame")
	line.LayoutOrder = 3
	line.Size = UDim2.new(1, 0, 0, 1)
	line.BackgroundColor3 = Theme.Colors.Slate
	line.BorderSizePixel = 0
	line.Parent = window

	local resume = MenuKit.button(window, "▶  " .. t("gamemenu.resume"), "good", 52, 4)
	local help = MenuKit.button(window, "?  " .. t("gamemenu.help"), "normal", nil, 5)
	local sound = MenuKit.button(window, "♪  " .. t("gamemenu.sound"), "normal", nil, 6)
	local shop = MenuKit.button(window, "$  " .. t("gamemenu.shop"), "normal", nil, 7)
	local line2 = line:Clone()
	line2.LayoutOrder = 8
	line2.Parent = window
	local main = MenuKit.button(window, "⌂  " .. t("gamemenu.main"), "danger", nil, 9)
	MenuKit.wrapLabel(window, t("gamemenu.note"), 12, Theme.Colors.Muted, 10)

	local function close()
		window.Visible = false
	end
	local function toggle()
		window.Visible = not window.Visible
		if window.Visible then
			sub.Text = Strings.get("map." .. mapName, lang)
				.. "  ·  "
				.. Strings.get("mode." .. cs.mode.mode, lang)
				.. (if cs.phase == "Play" then "  ·  " .. MenuKit.clock(ClientState.matchTime(cs, os.clock())) else "")
		end
	end
	Session.connect(button.Activated, toggle)
	Session.connect(resume.Activated, close)
	Session.connect(help.Activated, function()
		close()
		act.help()
	end)
	Session.connect(sound.Activated, function()
		close()
		act.sound()
	end)
	Session.connect(shop.Activated, function()
		close()
		act.shop()
	end)
	Session.connect(main.Activated, function()
		close()
		act.mainMenu()
	end)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.Tab and not act.blocked() then
			toggle()
		elseif input.KeyCode == Enum.KeyCode.Escape and window.Visible then
			close()
		end
	end)

	return {
		toggle = toggle,
		close = close,
		isOpen = function(): boolean
			return window.Visible
		end,
		button = button,
		window = window,
	}
end

return table.freeze(GameMenu)
