--!strict
--[[
	Minimap — мини-карта справа снизу (HUD v1, §10): территории цветом держав, рамка камеры; нажатие или
	перетаскивание по ней — камера туда. Своё маленькое EditableImage, перерисовка не чаще
	Render.MinimapEverySec и только если сетка менялась (на экране обновляется один EditableImage за кадр).
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local MinimapPaint = require(Shared:WaitForChild("MinimapPaint"))
local NationColors = require(Shared:WaitForChild("NationColors"))

local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type Minimap = {
	changed: () -> (), -- сетка поменялась
	update: (now: number, state: CameraState) -> (),
	height: number, -- высота на экране (под ней F3 не прячется)
}

local Minimap = {}

function Minimap.new(
	gui: ScreenGui,
	cs: ClientState,
	terrainColors: buffer,
	mapW: number,
	mapH: number,
	moveCamera: (wx: number, wy: number) -> ()
): Minimap?
	local outW, outH = MinimapPaint.size(mapW, mapH, Config.Render.MinimapSide)
	local ok, image = pcall(function(): EditableImage?
		return AssetService:CreateEditableImage({ Size = Vector2.new(outW, outH) })
	end)
	if not ok or image == nil then
		warn("[Frontir] мини-карта: нет памяти под EditableImage")
		return nil
	end
	local editable = image :: EditableImage

	local frame = Instance.new("Frame")
	frame.Name = "Minimap"
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.new(1, -12, 1, -12)
	frame.Size = UDim2.fromOffset(outW, outH)
	frame.BackgroundColor3 = Theme.Colors.Backdrop
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Active = true
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = frame
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.ImageContent = Content.fromObject(editable)
	label.Parent = frame
	local view = Instance.new("Frame")
	view.Name = "CameraFrame"
	view.BackgroundTransparency = 1
	view.ZIndex = 2
	local viewStroke = Instance.new("UIStroke")
	viewStroke.Color = Theme.Colors.Gold
	viewStroke.Thickness = 1
	viewStroke.Parent = view
	view.Parent = frame
	frame.Parent = gui

	local function colorOf(owner: number): (number?, number?, number?)
		local ci = ClientState.colorIndexOf(cs, owner)
		if ci < 1 then
			return nil, nil, nil
		end
		local c = NationColors.Colors[ci]
		return c.r, c.g, c.b
	end

	local dirty = true
	local nextPaint = 0
	local dragging = false
	local function jump(pos: Vector3)
		local rel = Vector2.new(pos.X, pos.Y) - frame.AbsolutePosition
		local fx = math.clamp(rel.X / frame.AbsoluteSize.X, 0, 1)
		local fy = math.clamp(rel.Y / frame.AbsoluteSize.Y, 0, 1)
		moveCamera(fx * mapW, fy * mapH)
	end
	frame.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = true
			jump(input.Position)
		end
	end)
	frame.InputChanged:Connect(function(input: InputObject)
		local t = input.UserInputType
		if dragging and (t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch) then
			jump(input.Position)
		end
	end)
	frame.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	local function update(now: number, state: CameraState)
		frame.Visible = cs.hasSnapshot
		if dirty and now >= nextPaint and cs.hasSnapshot then
			dirty = false
			nextPaint = now + Config.Render.MinimapEverySec
			-- Туман (§6.11): мини-карта — по последнему увиденному владельцу.
			local pixels =
				MinimapPaint.paint(terrainColors, ClientState.knownOwners(cs), mapW, mapH, outW, outH, colorOf)
			editable:WritePixelsBuffer(Vector2.zero, Vector2.new(outW, outH), pixels)
		end
		local x0, y0, x1, y1 = CameraMath.visibleRect(state)
		view.Position = UDim2.fromOffset(x0 / mapW * outW, y0 / mapH * outH)
		view.Size = UDim2.fromOffset((x1 - x0 + 1) / mapW * outW, (y1 - y0 + 1) / mapH * outH)
	end

	return {
		changed = function()
			dirty = true
		end,
		update = update,
		height = outH,
	}
end

return table.freeze(Minimap)
