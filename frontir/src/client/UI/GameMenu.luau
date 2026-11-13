--!strict
--[[
	GameMenu — меню игры (GDD §15л; §15ф — сюда переехали окна из дока, §15ф Ф2 — док убран совсем): кнопка «≡»
	слева сверху (и Tab) во время матча и в лобби. Окно по центру: «МЕНЮ», карта и режим; «Продолжить»; сеткой по
	две — Как играть, Звук, Магазин, Дипломатия, Технологии, Стабильность, Угрозы, Метки (если доступны), Задания,
	Гардероб, Арсенал, Путь командира, Сервер (у владельца частного сервера); «Главное меню».
	Матч не на паузе — об этом строка внизу. Escape закрывает окно. Окно — в слое окон, кнопка «≡» — в HUD.
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

-- Кнопка окна из прежнего дока (visible nil — всегда видна; text — подпись, которая меняется: «Пауза» / «Продолжить»).
export type MenuItem = { label: string, action: () -> (), visible: (() -> boolean)?, text: (() -> string)? }

export type Actions = {
	help: () -> (),
	sound: () -> (),
	shop: () -> (),
	mainMenu: () -> (),
	blocked: () -> boolean, -- открыто главное меню — Tab ничего не делает
	-- §15ф: окна из прежнего дока — кнопками сеткой (visible nil — всегда).
	extra: { MenuItem }?,
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
	-- Сетка по две: Как играть, Звук, Магазин и окна из прежнего дока.
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.LayoutOrder = 5
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.Parent = window
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.5, -5, 0, MenuKit.Touch)
	gridLayout.CellPadding = UDim2.fromOffset(10, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	local help = MenuKit.button(grid, "?  " .. t("gamemenu.help"), "normal", nil, 1)
	local sound = MenuKit.button(grid, "🔊  " .. t("gamemenu.sound"), "normal", nil, 2)
	local shop = MenuKit.button(grid, "$  " .. t("gamemenu.shop"), "normal", nil, 3)
	type Extra = { button: TextButton, visible: (() -> boolean)?, text: (() -> string)? }
	local extras: { Extra } = {}
	local line2 = line:Clone()
	line2.LayoutOrder = 8
	line2.Parent = window
	local main = MenuKit.button(window, "🏠  " .. t("gamemenu.main"), "danger", nil, 9)
	local note = MenuKit.wrapLabel(window, t("gamemenu.note"), 12, Theme.Colors.Muted, 10)

	local function close()
		window.Visible = false
	end
	local extraList: { MenuItem } = act.extra or {}
	for k, e in extraList do
		local b = MenuKit.button(grid, e.label, "normal", nil, 3 + k)
		b.TextSize = 15
		Session.connect(b.Activated, function()
			close()
			e.action()
		end)
		table.insert(extras, { button = b, visible = e.visible, text = e.text })
	end
	local function toggle()
		window.Visible = not window.Visible
		if window.Visible then
			for _, e in extras do
				local fn = e.visible
				e.button.Visible = fn == nil or fn()
				local textFn = e.text
				if textFn ~= nil then
					e.button.Text = textFn()
				end
			end
			-- §15л ч.3: на сервере матча «Главное меню» — переход в хаб, держава уходит из матча.
			note.Text = t(if cs.place == "match" then "gamemenu.noteLeave" else "gamemenu.note")
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
