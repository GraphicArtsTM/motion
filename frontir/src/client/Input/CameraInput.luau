--!strict
--[[
	CameraInput — управление камерой (GDD §3):
	- мышь: колесо — зум к курсору, перетаскивание правой или средней кнопкой — сдвиг;
	- клавиатура: WASD и стрелки — сдвиг, Space — показать всю карту;
	- телефон: перетаскивание пальцем — сдвиг, щипок двумя пальцами — зум к центру щипка.
	Координаты ввода переводятся в координаты области карты через её AbsolutePosition,
	поэтому верхняя панель Roblox (GUI inset) не сбивает зум к курсору.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local Config = require(Shared:WaitForChild("Config"))

local Camera2DModule = require(script.Parent.Parent:WaitForChild("Render"):WaitForChild("Camera2D"))

type Camera2D = Camera2DModule.Camera2D

export type Binding = {
	-- Последняя позиция мыши в координатах области карты (для F3), nil — мыши нет.
	hover: () -> (number?, number?),
	disconnect: () -> (),
}

local CameraInput = {}

local PAN_KEYS_LEFT = { Enum.KeyCode.A, Enum.KeyCode.Left }
local PAN_KEYS_RIGHT = { Enum.KeyCode.D, Enum.KeyCode.Right }
local PAN_KEYS_UP = { Enum.KeyCode.W, Enum.KeyCode.Up }
local PAN_KEYS_DOWN = { Enum.KeyCode.S, Enum.KeyCode.Down }

local function anyDown(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

function CameraInput.bind(camera: Camera2D, viewport: GuiObject): Binding
	local state = camera.state
	local connections: { RBXScriptConnection } = {}

	local function toLocal(pos: Vector3): (number, number)
		local origin = viewport.AbsolutePosition
		return pos.X - origin.X, pos.Y - origin.Y
	end

	-- Мышь
	local dragging = false
	local lastX, lastY = 0, 0
	local hoverX: number?, hoverY: number? = nil, nil

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then
				return
			end
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
				dragging = true
				lastX, lastY = toLocal(input.Position)
			elseif t == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Space then
				camera.fit()
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
				dragging = false
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseMovement then
				local x, y = toLocal(input.Position)
				hoverX, hoverY = x, y
				if dragging then
					CameraMath.pan(state, x - lastX, y - lastY)
					lastX, lastY = x, y
					camera.refresh()
				end
			elseif t == Enum.UserInputType.MouseWheel and not gameProcessed then
				local x, y = toLocal(input.Position)
				local step = if input.Position.Z > 0 then 1 elseif input.Position.Z < 0 then -1 else 0
				if step ~= 0 then
					CameraMath.zoomAt(state, state.zoom + step, x, y)
					camera.refresh()
				end
			end
		end)
	)

	-- Касания: один палец — сдвиг, два — щипок.
	type Touch = { x: number, y: number }
	local touches: { [InputObject]: Touch } = {}
	local touchCount = 0
	local pinchStartDist = 0
	local pinchStartZoom = state.zoom
	local pinchMidX, pinchMidY = 0, 0

	local function twoTouches(): (Touch?, Touch?)
		local a: Touch?, b: Touch? = nil, nil
		for _, touch in touches do
			if a == nil then
				a = touch
			elseif b == nil then
				b = touch
			end
		end
		return a, b
	end

	local function beginPinch()
		local a, b = twoTouches()
		if a and b then
			pinchStartDist = math.max(1, math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2))
			pinchStartZoom = state.zoom
			pinchMidX, pinchMidY = (a.x + b.x) / 2, (a.y + b.y) / 2
		end
	end

	table.insert(
		connections,
		UserInputService.TouchStarted:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then
				return
			end
			local x, y = toLocal(input.Position)
			touches[input] = { x = x, y = y }
			touchCount += 1
			if touchCount == 2 then
				beginPinch()
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.TouchMoved:Connect(function(input: InputObject)
			local touch = touches[input]
			if touch == nil then
				return
			end
			local x, y = toLocal(input.Position)
			if touchCount == 1 then
				CameraMath.pan(state, x - touch.x, y - touch.y)
				touch.x, touch.y = x, y
				camera.refresh()
			else
				touch.x, touch.y = x, y
				local a, b = twoTouches()
				if a and b then
					local dist = math.max(1, math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2))
					local midX, midY = (a.x + b.x) / 2, (a.y + b.y) / 2
					CameraMath.zoomAt(state, pinchStartZoom * dist / pinchStartDist, midX, midY)
					CameraMath.pan(state, midX - pinchMidX, midY - pinchMidY)
					pinchMidX, pinchMidY = midX, midY
					camera.refresh()
				end
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.TouchEnded:Connect(function(input: InputObject)
			if touches[input] ~= nil then
				touches[input] = nil
				touchCount -= 1
				if touchCount == 2 then
					beginPinch()
				end
			end
		end)
	)

	-- Клавиатура: плавный сдвиг каждый кадр.
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt: number)
			if UserInputService:GetFocusedTextBox() ~= nil then
				return
			end
			local dx = (if anyDown(PAN_KEYS_RIGHT) then 1 else 0) - (if anyDown(PAN_KEYS_LEFT) then 1 else 0)
			local dy = (if anyDown(PAN_KEYS_DOWN) then 1 else 0) - (if anyDown(PAN_KEYS_UP) then 1 else 0)
			if dx ~= 0 or dy ~= 0 then
				local speed = Config.Render.KeyPanSpeedPx * dt
				CameraMath.pan(state, -dx * speed, -dy * speed)
				camera.refresh()
			end
		end)
	)

	return {
		hover = function()
			return hoverX, hoverY
		end,
		disconnect = function()
			for _, conn in connections do
				conn:Disconnect()
			end
			table.clear(connections)
		end,
	}
end

return table.freeze(CameraInput)
