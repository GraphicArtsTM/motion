--!strict
--[[
	SpectatePanel — «Следить за лидером» (GDD §15й Й5): кнопка в столбике сверху у зрителя (держава выбыла или её
	нет); включена — раз в Render.Spectate.EverySec цель — главный удар лидера (чистый Spectate.target), камера
	плавно догоняет её (Spectate.step). Своё движение камеры (правая / средняя кнопка, колесо, клавиши, палец)
	выключает слежку.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Spectate = require(Shared:WaitForChild("Spectate"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type SpectatePanel = {
	frame: TextButton,
	setFollow: (on: boolean) -> (),
	update: (now: number, state: CameraState, refresh: () -> ()) -> (),
}

local SpectatePanel = {}

local MANUAL: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true,
	[Enum.KeyCode.Left] = true,
	[Enum.KeyCode.Right] = true,
	[Enum.KeyCode.Space] = true,
}

function SpectatePanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	freeCenter: () -> (number, number) -- §15й Й6: куда на экране ставить цель (свободная часть)
): SpectatePanel
	local cfg = Config.Render.Spectate
	local button = MenuKit.button(gui, "", "normal", 34)
	button.Name = "SpectateChip"
	button.Size = UDim2.fromOffset(0, 34)
	button.AutomaticSize = Enum.AutomaticSize.X
	button.TextSize = 14
	button.Visible = false
	MenuKit.pad(button, 14, 0)

	local follow = false
	local target: number? = nil
	local nextAt = 0
	local lastNow = 0
	local function paint()
		button.Text = Strings.get(if follow then "spectate.on" else "spectate.off", lang)
		button.TextColor3 = if follow then Theme.Colors.Gold else Theme.Colors.Text
	end
	paint()
	local function setFollow(on: boolean)
		follow = on
		nextAt = 0
		paint()
	end
	Session.connect(button.Activated, function()
		setFollow(not follow)
	end)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
		if processed or not follow then
			return
		end
		local t = input.UserInputType
		if
			t == Enum.UserInputType.MouseButton2
			or t == Enum.UserInputType.MouseButton3
			or t == Enum.UserInputType.Touch
			or (t == Enum.UserInputType.Keyboard and MANUAL[input.KeyCode])
		then
			setFollow(false)
		end
	end)
	Session.connect(UserInputService.InputChanged, function(input: InputObject, processed: boolean)
		if not processed and follow and input.UserInputType == Enum.UserInputType.MouseWheel then
			setFollow(false)
		end
	end)

	local function update(now: number, state: CameraState, refresh: () -> ())
		local dt = math.clamp(now - lastNow, 0, 0.1)
		lastNow = now
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		local spectator = cs.phase == "Play" and (me == nil or not me.alive) and not cs.demo
		button.Visible = spectator
		if not spectator or not follow then
			return
		end
		if now >= nextAt then
			nextAt = now + cfg.EverySec
			local leader = ClientState.victoryLeader(cs)
			local n = cs.nations[leader]
			local stats = cs.stats
			target = Spectate.target(
				if stats ~= nil then stats.attacks :: any else {},
				leader,
				if n ~= nil then n.capital else nil
			)
		end
		local cell = target
		if cell == nil then
			return
		end
		local w = cs.width
		local fx, fy = freeCenter()
		local cx, cy = CameraMath.screenToWorld(state, fx, fy)
		local nx, ny = Spectate.step(cx, cy, cell % w + 0.5, cell // w + 0.5, dt)
		CameraMath.showAt(state, nx, ny, fx, fy)
		refresh()
	end

	return { frame = button, setFollow = setFollow, update = update }
end

return table.freeze(SpectatePanel)
