--!strict
--[[
	Camera2D — состояние 2D-камеры на клиенте, плавный зум и рассылка изменений подписчикам
	(рендер, блики, F3). Вся математика — в Shared.CameraMath (покрыта тестами); здесь только связь с GUI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local Config = require(Shared:WaitForChild("Config"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type CameraState = CameraMath.CameraState

export type Camera2D = {
	state: CameraState,
	onChanged: (fn: (state: CameraState) -> ()) -> (),
	refresh: () -> (),
	fit: () -> (),
	-- Плавно приблизить/отдалить к зуму target, держа точку экрана (sx, sy) на месте.
	zoomTo: (target: number, sx: number, sy: number) -> (),
	-- Куда сейчас едет зум (для накопления быстрых щелчков колеса).
	targetZoom: () -> number,
	cancelZoom: () -> (),
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

	local target: number? = nil
	local anchorX, anchorY = 0, 0

	local function refresh()
		for _, fn in listeners do
			fn(state)
		end
	end

	local function fit()
		target = nil
		local fresh = CameraMath.new(mapW, mapH, state.viewW, state.viewH)
		state.x, state.y, state.zoom = fresh.x, fresh.y, fresh.zoom
		refresh()
	end

	local sizeConn = Session.connect(viewport:GetPropertyChangedSignal("AbsoluteSize"), function()
		local s = viewport.AbsoluteSize
		if s.X > 0 and s.Y > 0 then
			CameraMath.setViewSize(state, s.X, s.Y)
			refresh()
		end
	end)

	local stepConn = Session.connect(RunService.RenderStepped, function(dt: number)
		local t = target
		if t == nil then
			return
		end
		local k = 1 - math.exp(-Config.Render.ZoomLerpPerSec * dt)
		local z = state.zoom + (t - state.zoom) * k
		if math.abs(t - z) < 0.01 then
			z = t
			target = nil
		end
		CameraMath.zoomAt(state, z, anchorX, anchorY)
		refresh()
	end)

	return {
		state = state,
		onChanged = function(fn: (CameraState) -> ())
			table.insert(listeners, fn)
			fn(state)
		end,
		refresh = refresh,
		fit = fit,
		zoomTo = function(z: number, sx: number, sy: number)
			target = CameraMath.clampZoom(state, z)
			anchorX, anchorY = sx, sy
		end,
		targetZoom = function(): number
			return target or state.zoom
		end,
		cancelZoom = function()
			target = nil
		end,
		destroy = function()
			sizeConn:Disconnect()
			stepConn:Disconnect()
			table.clear(listeners)
		end,
	}
end

return table.freeze(Camera2D)
