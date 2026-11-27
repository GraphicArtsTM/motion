--!strict
--[[
	TutorialWelcome — окно «Добро пожаловать, командир!» при первом входе (GDD §15ь Л4).
	Показывается над главным меню (слой окон), когда профиль загружен, обучение не пройдено и вопрос ещё не задавали
	(профиль tutorialAsked). «ПРОЙТИ ОБУЧЕНИЕ» — запуск обучения, «Пропустить» — просто закрыть; любой ответ —
	намерение prefs { tutorialAsked = true }: окно больше не появится, кнопка «Обучение» в меню останется.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))

type ClientState = ClientState.ClientState

export type TutorialWelcome = {
	update: (menuOpen: boolean) -> (),
	isOpen: () -> boolean,
}

local TutorialWelcome = {}

local Z = 40 -- над окнами меню

function TutorialWelcome.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (kind: string, payload: { [string]: any }) -> (),
	start: () -> ()
): TutorialWelcome
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local answered = false

	local back = Instance.new("TextButton")
	back.Name = "TutorialWelcome"
	back.Text = ""
	back.AutoButtonColor = false
	back.BackgroundColor3 = Theme.Colors.Backdrop
	back.BackgroundTransparency = 0.3
	back.BorderSizePixel = 0
	back.Visible = false
	back.Parent = gui

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Size = UDim2.fromOffset(460, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundColor3 = Theme.Colors.PanelBg
	box.BorderSizePixel = 0
	box.Parent = back
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 16)
	c.Parent = box
	MenuKit.stroke(box, Theme.Colors.Gold, 2)
	MenuKit.pad(box, 26, 22)
	MenuKit.list(box, 12, false, Enum.HorizontalAlignment.Center)

	local function centered(l: TextLabel): TextLabel
		l.TextXAlignment = Enum.TextXAlignment.Center
		return l
	end
	centered(MenuKit.label(box, "🎓", 44, Theme.Colors.Gold, true, 1))
	centered(MenuKit.label(box, t("tutorial.welcomeTitle"), 24, Theme.Colors.Gold, true, 2))
	centered(MenuKit.wrapLabel(box, t("tutorial.welcomeText"), 16, Theme.Colors.Text, 3))
	centered(
		MenuKit.wrapLabel(
			box,
			string.format(t("tutorial.welcomeMeta"), #Config.Tutorial.Steps)
				.. "\n"
				.. string.format(t("tutorial.doneReward"), Config.Tutorial.RewardTokens, Config.Tutorial.RewardMedals),
			14,
			Theme.Colors.Muted,
			4
		)
	)
	local yes = MenuKit.button(box, t("tutorial.welcomeYes"), "primary", 56, 5)
	yes.Name = "Yes"
	local no = MenuKit.button(box, t("tutorial.welcomeNo"), "normal", 40, 6)
	no.Name = "No"

	-- Слой окон может рисовать с ZIndex Global: всё окно — над меню и содержимое — над фоном.
	back.ZIndex = Z
	for _, d in back:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = Z + 1
		end
	end

	local function fit()
		local size = UiScale.size(gui)
		back.Size = UDim2.fromOffset(size.X, size.Y)
		box.Position = UDim2.fromOffset(size.X / 2, size.Y / 2)
		box.Size = UDim2.fromOffset(math.min(460, size.X - 32), 0)
	end
	UiScale.onResize(gui, fit)
	fit()

	local function answer()
		answered = true
		back.Visible = false
		local p = cs.profile
		if p ~= nil then
			p.tutorialAsked = true -- сразу, не ждать профиля от сервера
		end
		send("prefs", { tutorialAsked = true })
	end
	Session.connect(yes.Activated, function()
		answer()
		start()
	end)
	Session.connect(no.Activated, answer)

	return {
		update = function(menuOpen: boolean)
			local p = cs.profile
			local want = not answered
				and menuOpen
				and p ~= nil
				and not p.tutorialDone
				and not p.tutorialAsked
				and (cs.place == "hub" or cs.place == "combined")
				and cs.travel ~= "going"
			if want and not back.Visible then
				fit()
			end
			back.Visible = want
		end,
		isOpen = function(): boolean
			return back.Visible
		end,
	}
end

return table.freeze(TutorialWelcome)
