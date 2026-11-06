--!strict
--[[
	CloudLayer — тени облаков медленно плывут над картой (§15г): карта не «мёртвая» даже в затишье.
	Несколько мягких тёмных овалов в координатах карты (клетки), ветер — Render.Clouds.Wind; ушедшее за край
	облако возвращается с другой стороны. Под юнитами и зданиями, над землёй. На телефоне облаков меньше.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local Config = require(Shared:WaitForChild("Config"))
local RenderBudget = require(Shared:WaitForChild("RenderBudget"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type CameraState = CameraMath.CameraState

export type CloudLayer = {
	update: (dt: number, state: CameraState) -> (),
}

type Cloud = { frame: Frame, x: number, y: number, w: number, h: number }

local CloudLayer = {}

function CloudLayer.new(canvas: Frame, mapW: number, mapH: number): CloudLayer
	local cfg = Config.Render.Clouds
	local phone = RenderBudget.isPhone(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)
	local count = if phone then cfg.PhoneCount else cfg.Count
	local rng = Random.new(7)
	local clouds: { Cloud } = {}
	local scale = mapW / 512 -- размеры облаков заданы для ширины 512
	for _ = 1, count do
		local f = Instance.new("Frame")
		f.Name = "CloudShadow"
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BackgroundTransparency = cfg.Transparency
		f.ZIndex = 3
		f.Parent = canvas
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		local w = rng:NextNumber(cfg.MinSize, cfg.MaxSize) * scale
		table.insert(clouds, {
			frame = f,
			x = rng:NextNumber(0, mapW),
			y = rng:NextNumber(0, mapH),
			w = w,
			h = w * rng:NextNumber(0.35, 0.55),
		})
	end

	local function update(dt: number, state: CameraState)
		local zoom = state.zoom
		local vx, vy = cfg.Wind[1] * scale * dt, cfg.Wind[2] * scale * dt
		for _, c in clouds do
			c.x += vx
			c.y += vy
			if c.x - c.w / 2 > mapW then
				c.x = -c.w / 2
			end
			if c.y - c.h / 2 > mapH then
				c.y = -c.h / 2
			elseif c.y + c.h / 2 < 0 then
				c.y = mapH + c.h / 2
			end
			c.frame.Position = UDim2.fromOffset(math.round((c.x - c.w / 2) * zoom), math.round((c.y - c.h / 2) * zoom))
			c.frame.Size = UDim2.fromOffset(math.round(c.w * zoom), math.round(c.h * zoom))
		end
	end

	return { update = update }
end

return table.freeze(CloudLayer)
