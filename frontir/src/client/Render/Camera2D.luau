--!strict
--[[
	Camera2D — состояние 2D-камеры на клиенте и рассылка изменений подписчикам (рендер, блики, F3).
	Вся математика — в Shared.CameraMath (покрыта тестами); здесь только связь с GUI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CameraMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CameraMath"))

type CameraState = CameraMath.CameraState

export type Camera2D = {
	state: CameraState,
	onChanged: (fn: (state: CameraState) -> ()) -> (),
	refresh: () -> (),
	fit: () -> (),
	destroy: () -> (),
}

local Camera2D = {}

function Camera2D.new(mapW: number, mapH: number, viewport: GuiObject): Camera2D
	-- До первой раскладки GUI размер может быть нулевым.
	while viewport.AbsoluteSize.X <= 0 or viewport.AbsoluteSize.Y <= 0 do
		RunService.RenderStepped:Wait()
	end
	local state = CameraMath.new(mapW, mapH, viewport.AbsoluteSize.X, viewport.AbsoluteSize.Y)
	local listeners: { (CameraState) -> () } = {}

	local function refresh()
		for _, fn in listeners do
			fn(state)
		end
	end

	local function fit()
		local fresh = CameraMath.new(mapW, mapH, state.viewW, state.viewH)
		state.x, state.y, state.zoom = fresh.x, fresh.y, fresh.zoom
		refresh()
	end

	local sizeConn = viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local s = viewport.AbsoluteSize
		if s.X > 0 and s.Y > 0 then
			CameraMath.setViewSize(state, s.X, s.Y)
			refresh()
		end
	end)

	return {
		state = state,
		onChanged = function(fn: (CameraState) -> ())
			table.insert(listeners, fn)
			fn(state)
		end,
		refresh = refresh,
		fit = fit,
		destroy = function()
			sizeConn:Disconnect()
			table.clear(listeners)
		end,
	}
end

return table.freeze(Camera2D)
