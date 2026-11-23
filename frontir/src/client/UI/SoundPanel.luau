--!strict
--[[
	SoundPanel — громкости (GDD §13, этап 10б): кнопка «🔊» над мини-картой → окно: «Звуки» и «Музыка» с кнопками
	− / + (шаг Audio.VolumeStep), «Без звука» / «Вернуть звук». Сразу меняет громкость у клиента и шлёт намерение
	volume — сервер сохраняет в профиле, при входе громкости приходят в profile.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioCues = require(Shared:WaitForChild("AudioCues"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Audio = require(script.Parent.Parent:WaitForChild("Audio"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type SoundPanel = {
	refresh: () -> (), -- пришёл profile (громкости)
	button: GuiButton, -- §15з: кнопка прячется в док
	toggle: () -> (),
	isOpen: () -> boolean,
}

local SoundPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx

local function button(parent: Instance, text: string, width: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, BUTTON)
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BackgroundTransparency = 0.05
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.FontFace = Theme.FontBold
	b.TextSize = 16
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

function SoundPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> ()
): SoundPanel
	local main = button(gui, "🔊", BUTTON)
	main.Name = "SoundButton"
	main.AnchorPoint = Vector2.new(1, 1)
	main.Position = UDim2.new(1, -12, 1, -12 - Config.Render.MinimapSide - 8)

	-- §15я: окно звука — заголовок со значком, две строки «значок · название · полоса громкости · − / +»,
	-- кнопки «Без звука» и «Проверить звук».
	local W = 340
	local window = Instance.new("Frame")
	window.Name = "Sound"
	window.AnchorPoint = Vector2.new(1, 1)
	window.Position = UDim2.new(1, -12 - BUTTON - 6, 1, -12 - Config.Render.MinimapSide - 8)
	window.Size = UDim2.fromOffset(W, 0)
	window.AutomaticSize = Enum.AutomaticSize.Y
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BackgroundTransparency = 0.05
	window.BorderSizePixel = 0
	window.Visible = false
	window.Parent = gui
	MenuKit.corner(window, 10)
	MenuKit.stroke(window, Theme.Colors.PanelBorder, 2)
	MenuKit.pad(window, 14, 12)
	MenuKit.list(window, 10)
	-- Заголовок во всю ширину: слева значок и название, справа «×» (§15ъ: закрыть окно было нечем, кроме «🔊»).
	local head = MenuKit.box(window, "Head", 1)
	head.AutomaticSize = Enum.AutomaticSize.None
	head.Size = UDim2.new(1, 0, 0, BUTTON)
	local title = MenuKit.box(head, "Title", 1)
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.fromScale(0, 0.5)
	MenuKit.list(title, 8, true)
	MenuKit.icon(title, "sound", 3, 1)
	MenuKit.label(title, Strings.get("sound.title", lang), 18, Theme.Colors.Gold, true, 2)
	local close = MenuKit.button(head, "×", "normal", BUTTON)
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(BUTTON, BUTTON)
	close.TextSize = 22
	Session.connect(close.Activated, function()
		window.Visible = false
	end)

	local sfx, music = Audio.volumes()
	local saved = { sfx = sfx, music = music } -- до «Без звука»
	local function apply(save: boolean)
		Audio.setVolumes(sfx, music)
		if save then
			send("volume", { sfx = sfx, music = music })
		end
	end
	type Row = { label: TextLabel, value: TextLabel, bar: MenuKit.Bar, key: string }
	local rows: { Row } = {}
	local function row(index: number, key: string, icon: string, change: (dir: number) -> ())
		local f = MenuKit.box(window, "Row_" .. key, 1 + index)
		f.AutomaticSize = Enum.AutomaticSize.None
		f.Size = UDim2.new(1, 0, 0, BUTTON + 18)
		local ic = MenuKit.icon(f, icon, 3)
		ic.Position = UDim2.fromOffset(0, 4)
		local label = MenuKit.label(f, "", 15, Theme.Colors.Text, true)
		label.Position = UDim2.fromOffset(32, 2)
		local value = MenuKit.label(f, "", 15, Theme.Colors.Gold, true)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -2 * (BUTTON + 6), 0, 2)
		value.TextXAlignment = Enum.TextXAlignment.Right
		local host = Instance.new("Frame")
		host.BackgroundTransparency = 1
		host.Position = UDim2.fromOffset(32, 30)
		host.Size = UDim2.new(1, -32 - 2 * (BUTTON + 6), 0, 10)
		host.Parent = f
		local bar = MenuKit.bar(host, 10, Theme.Colors.Sky)
		local minus = MenuKit.button(f, "−", "normal", BUTTON)
		minus.AnchorPoint = Vector2.new(1, 0)
		minus.Position = UDim2.new(1, -(BUTTON + 6), 0, 4)
		minus.Size = UDim2.fromOffset(BUTTON, BUTTON)
		minus.TextSize = 20
		local plus = MenuKit.button(f, "+", "normal", BUTTON)
		plus.AnchorPoint = Vector2.new(1, 0)
		plus.Position = UDim2.new(1, 0, 0, 4)
		plus.Size = UDim2.fromOffset(BUTTON, BUTTON)
		plus.TextSize = 20
		Session.connect(minus.Activated, function()
			change(-1)
		end)
		Session.connect(plus.Activated, function()
			change(1)
		end)
		table.insert(rows, { label = label, value = value, bar = bar, key = key })
	end
	local muteButton: TextButton
	local function draw()
		for _, r in rows do
			local v = if r.key == "sfx" then sfx else music
			r.label.Text = Strings.get("sound.name." .. r.key, lang)
			r.value.Text = string.format("%d%%", math.round(v * 100))
			r.value.TextColor3 = if v > 0 then Theme.Colors.Gold else Theme.Colors.Muted
			r.bar.set(v)
		end
		muteButton.Text = Strings.get(if sfx == 0 and music == 0 then "sound.unmute" else "sound.mute", lang)
	end
	row(1, "sfx", "sound", function(dir: number)
		sfx = AudioCues.stepVolume(sfx, dir)
		apply(true)
		draw()
		Audio.play("Click")
	end)
	row(2, "music", "quests", function(dir: number)
		music = AudioCues.stepVolume(music, dir)
		apply(true)
		draw()
	end)
	local buttons = MenuKit.box(window, "Buttons", 5)
	buttons.AutomaticSize = Enum.AutomaticSize.None
	buttons.Size = UDim2.new(1, 0, 0, BUTTON)
	local bl = MenuKit.list(buttons, 8, true)
	bl.HorizontalFlex = Enum.UIFlexAlignment.Fill
	muteButton = MenuKit.button(buttons, "", "normal", BUTTON, 1)
	muteButton.TextSize = 14
	local testButton = MenuKit.button(buttons, Strings.get("sound.test", lang), "good", BUTTON, 2)
	testButton.TextSize = 14
	Session.connect(testButton.Activated, function()
		Audio.play("Click")
	end)
	Session.connect(muteButton.Activated, function()
		if sfx == 0 and music == 0 then
			sfx, music = saved.sfx, saved.music
			if sfx == 0 and music == 0 then
				sfx, music = Config.Audio.DefaultSfx, Config.Audio.DefaultMusic
			end
		else
			saved.sfx, saved.music = sfx, music
			sfx, music = 0, 0
		end
		apply(true)
		draw()
	end)
	MenuKit.wrapLabel(window, Strings.get("sound.hint", lang), 12, Theme.Colors.Muted, 6)
	local function toggle()
		window.Visible = not window.Visible
		if window.Visible then
			draw()
		end
	end
	Session.connect(main.Activated, toggle)

	local function refresh()
		local p = cs.profile
		local v = if p ~= nil then p.volume else nil
		if v ~= nil and type(v.sfx) == "number" and type(v.music) == "number" then
			sfx, music = v.sfx, v.music
			apply(false)
		end
		draw()
	end
	draw()
	return {
		refresh = refresh,
		button = main,
		toggle = toggle,
		isOpen = function(): boolean
			return window.Visible
		end,
	}
end

return table.freeze(SoundPanel)
