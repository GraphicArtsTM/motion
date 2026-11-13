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

	local window = Instance.new("Frame")
	window.Name = "Sound"
	window.AnchorPoint = Vector2.new(1, 1)
	window.Position = UDim2.new(1, -12 - BUTTON - 6, 1, -12 - Config.Render.MinimapSide - 8)
	window.Size = UDim2.fromOffset(280, 3 * (BUTTON + 6) + 36)
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BackgroundTransparency = 0.05
	window.BorderSizePixel = 0
	window.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Parent = window
	window.Parent = gui
	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(10, 6)
	title.Size = UDim2.new(1, -20, 0, 22)
	title.BackgroundTransparency = 1
	title.FontFace = Theme.FontBold
	title.TextSize = 16
	title.TextColor3 = Theme.Colors.Gold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = Strings.get("sound.title", lang)
	title.Parent = window

	local sfx, music = Audio.volumes()
	local saved = { sfx = sfx, music = music } -- до «Без звука»

	local function apply(save: boolean)
		Audio.setVolumes(sfx, music)
		if save then
			send("volume", { sfx = sfx, music = music })
		end
	end

	local rows: { { label: TextLabel, key: string } } = {}
	local function row(index: number, key: string, change: (dir: number) -> ())
		local y = 32 + (index - 1) * (BUTTON + 6)
		local label = Instance.new("TextLabel")
		label.Position = UDim2.fromOffset(10, y)
		label.Size = UDim2.fromOffset(150, BUTTON)
		label.BackgroundTransparency = 1
		label.FontFace = Theme.Font
		label.TextSize = 15
		label.TextColor3 = Theme.Colors.Text
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = window
		local minus = button(window, "−", BUTTON)
		minus.Position = UDim2.fromOffset(170, y)
		local plus = button(window, "+", BUTTON)
		plus.Position = UDim2.fromOffset(170 + BUTTON + 6, y)
		minus.Activated:Connect(function()
			change(-1)
		end)
		plus.Activated:Connect(function()
			change(1)
		end)
		table.insert(rows, { label = label, key = key })
	end

	local muteButton: TextButton

	local function draw()
		for _, r in rows do
			local v = if r.key == "sfx" then sfx else music
			r.label.Text = string.format(Strings.get("sound." .. r.key, lang), math.round(v * 100))
		end
		muteButton.Text = Strings.get(if sfx == 0 and music == 0 then "sound.unmute" else "sound.mute", lang)
	end

	row(1, "sfx", function(dir: number)
		sfx = AudioCues.stepVolume(sfx, dir)
		apply(true)
		draw()
		Audio.play("Click")
	end)
	row(2, "music", function(dir: number)
		music = AudioCues.stepVolume(music, dir)
		apply(true)
		draw()
	end)
	muteButton = button(window, "", 260)
	muteButton.Position = UDim2.fromOffset(10, 32 + 2 * (BUTTON + 6))
	muteButton.TextSize = 14
	muteButton.Activated:Connect(function()
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
