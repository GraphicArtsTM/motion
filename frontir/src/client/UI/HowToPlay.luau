--!strict
--[[
	HowToPlay — окно «Как играть» (H; §15ц Ц4б): шаблон CardKit с вкладками «Начало» и три группы механик
	ВОЙНА · ДЕРЖАВА · МИР (как вкладки справочника). На вкладке — шаги (значок PixelIcons и текст help.<шаг>) и
	строка клавиш группы. Главная кнопка: на «Начале» — «Понятно!» (закрыть), на группе — «Справочник: <группа>»
	(колбэк openHandbook открывает справочник на той же вкладке). Шаги и вкладки — Config.Render.Help.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

export type HowToPlay = {
	frame: Frame,
	toggle: () -> (),
	isOpen: () -> boolean,
	open: (tab: string?) -> (),
}

local HowToPlay = {}

function HowToPlay.new(gui: ScreenGui, lang: Strings.Lang, openHandbook: (tab: string) -> ()): HowToPlay
	local cfg = Config.Render.Help
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local function tabTitle(tab: string): string
		return if tab == "start" then t("help.tab.start") else t("handbook.tab." .. tab)
	end

	local tabs: { { key: string, label: string } } = {}
	local kinds: { [string]: string } = {}
	for _, tab in cfg.Tabs do
		table.insert(tabs, { key = tab, label = tabTitle(tab) })
		kinds[tab] = "list"
	end
	local win = CardKit.window(
		gui,
		"HowToPlay",
		t("help.title"),
		t("help.subtitle"),
		cfg.WidthPx,
		cfg.HeightPx,
		tabs,
		kinds,
		true
	)
	local frame = win.frame
	frame.ZIndex = 30
	local foot = win.footer :: CardKit.Footer

	local steps = cfg.Steps :: { [string]: { { key: string, icon: string } } }
	for _, tab in cfg.Tabs do
		local page = win.page(tab)
		local tabSteps: { { key: string, icon: string } } = steps[tab] or {}
		for k, step in tabSteps do
			local row = Instance.new("Frame")
			row.Name = "Step_" .. step.key
			row.LayoutOrder = k
			row.Size = UDim2.fromScale(1, 0)
			row.AutomaticSize = Enum.AutomaticSize.Y
			row.BackgroundColor3 = Theme.Colors.Backdrop
			row.BorderSizePixel = 0
			row.Parent = page
			MenuKit.stroke(row, Theme.Colors.PanelBorder, 2)
			MenuKit.pad(row, 12, 10)
			local list = MenuKit.list(row, 14, true)
			list.VerticalAlignment = Enum.VerticalAlignment.Center
			MenuKit.icon(row, step.icon, 4, 1)
			local text = MenuKit.wrapLabel(row, t("help." .. step.key), 15, Theme.Colors.Text, 2)
			text.RichText = true
			text.Size = UDim2.new(1, -48, 0, 0)
		end
		local keys = MenuKit.wrapLabel(page, t("help.keys." .. tab), 14, Theme.Colors.Sky, 100)
		keys.Name = "Keys"
	end

	local function sync(tab: string)
		if tab == "start" then
			foot.set(t("help.close"), true, "")
		else
			foot.set(string.format(t("help.toHandbook"), tabTitle(tab)), true, "")
		end
	end
	win.onTab(sync)
	sync(win.tab())
	Session.connect(foot.main.Activated, function()
		local tab = win.tab()
		frame.Visible = false
		if tab ~= "start" then
			openHandbook(tab)
		end
	end)

	local function open(tab: string?)
		if tab ~= nil and table.find(cfg.Tabs, tab) ~= nil then
			win.setTab(tab)
		end
		frame.Visible = true
		Theme.popIn(frame)
	end
	local function toggle()
		if frame.Visible then
			frame.Visible = false
		else
			open(nil)
		end
	end
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.H then
			toggle()
		end
	end)

	return {
		frame = frame,
		toggle = toggle,
		isOpen = function(): boolean
			return frame.Visible
		end,
		open = open,
	}
end

return table.freeze(HowToPlay)
