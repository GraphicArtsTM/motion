--!strict
--[[
	AlarmBanner — тревога «НА ВАС АТАКУЮТ — НЕТ ВОЙСК» (GDD §15ш Ш2): первой в столбике сверху по центру.
	Когда показывать — чистый Alarm.state (входящие атаки из AttackList, войска — ForcesPanel.army);
	кнопка «Пехота [Z]» нанимает, как клавиша Z. Рамка и заголовок — цветом тревоги (Alarm.alertName), рамка мигает.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Alarm = require(Shared:WaitForChild("Alarm"))
local AttackList = require(Shared:WaitForChild("AttackList"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type AlarmBanner = {
	frame: Frame, -- «Alarm» (в столбике TopCenter)
	update: (now: number) -> (),
	isShown: () -> boolean,
}

local AlarmBanner = {}

function AlarmBanner.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	army: () -> (number, number), -- войска дома и на фронтах
	hire: () -> () -- нанять пехоту (как Z)
): AlarmBanner
	local cfg = Config.Render.Alarm
	local frame = Instance.new("Frame")
	frame.Name = "Alarm"
	frame.Size = UDim2.fromOffset(560, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Theme.Colors.Backdrop
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui
	frame:SetAttribute("FrontirStyled", true)
	MenuKit.corner(frame, 10)
	MenuKit.pad(frame, 14, 10)
	local edge = MenuKit.stroke(frame, Theme.Colors.Alert, 3)
	local title = MenuKit.label(frame, "", 20, Theme.Colors.Alert, true)
	title.Position = UDim2.fromOffset(0, 0)
	local hint = MenuKit.label(frame, Strings.get("alarm.hint", lang), 14, Theme.Colors.Text, false)
	hint.Position = UDim2.fromOffset(0, 28)
	local hireButton =
		MenuKit.button(frame, string.format("%s [Z]", Strings.get("unit.Infantry.short", lang)), "good", 44)
	hireButton.AnchorPoint = Vector2.new(1, 0.5)
	hireButton.Position = UDim2.fromScale(1, 0.5)
	hireButton.Size = UDim2.fromOffset(140, 44)
	-- Высота рамки — по двум строкам текста (кнопка стоит по центру справа).
	local spacer = Instance.new("Frame")
	spacer.BackgroundTransparency = 1
	spacer.Size = UDim2.fromOffset(1, 48)
	spacer.Parent = frame
	Session.connect(hireButton.Activated, hire)

	local shown = false
	local function update(now: number)
		local stats = cs.stats
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		local state: Alarm.State? = nil
		if cs.phase == "Play" and stats ~= nil and me ~= nil and me.alive then
			local _, counts = AttackList.rows(stats.attacks :: any, cs.myNation, 0)
			local home, front = army()
			state = Alarm.state(counts.inc, home + front)
		end
		shown = state ~= nil
		frame.Visible = shown
		if state == nil or me == nil then
			return
		end
		local rgb = if me.colorIndex >= 1 then NationColors.Colors[me.colorIndex] else nil
		local color = Theme.color(Alarm.alertName(rgb))
		title.Text = string.format(Strings.get("alarm.noTroops", lang), state.attacks)
		title.TextColor3 = color
		edge.Color = color
		-- Рамка мигает: заметно краем глаза, но текст не дёргается.
		local phase = (now % cfg.PulseSec) / cfg.PulseSec
		edge.Transparency = if phase < 0.5 then 0 else 0.6
	end

	return {
		frame = frame,
		update = update,
		isShown = function(): boolean
			return shown
		end,
	}
end

return table.freeze(AlarmBanner)
