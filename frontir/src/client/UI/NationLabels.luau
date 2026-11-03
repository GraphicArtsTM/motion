--!strict
--[[
	NationLabels — столицы и названия держав на карте. Метка — квадрат на клетке столицы (цвет державы,
	до раздачи цветов — белый) и подпись над ним. Живут на холсте карты, поэтому едут вместе с камерой;
	при смене зума пересчитываются позиции (CameraMath.cellEdge).
	Своя держава подписана золотым.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

type Label = { capital: number, marker: Frame, text: TextLabel }

export type NationLabels = {
	refresh: () -> (),
	onCamera: (state: CameraState) -> (),
}

local NationLabels = {}

function NationLabels.new(canvas: Frame, cs: ClientState, lang: Strings.Lang, mapWidth: number): NationLabels
	local labels: { Label } = {}
	local zoom = 1

	local function place(l: Label)
		local cx, cy = l.capital % mapWidth, l.capital // mapWidth
		local left, top = CameraMath.cellEdge(zoom, cx), CameraMath.cellEdge(zoom, cy)
		local side = math.max(4, CameraMath.cellEdge(zoom, cx + 1) - left)
		local centerX = left + (CameraMath.cellEdge(zoom, cx + 1) - left) / 2
		local centerY = top + (CameraMath.cellEdge(zoom, cy + 1) - top) / 2
		l.marker.Size = UDim2.fromOffset(side, side)
		l.marker.Position = UDim2.fromOffset(centerX, centerY)
		l.text.Position = UDim2.fromOffset(centerX, centerY - side / 2 - 2)
	end

	local function clear()
		for _, l in labels do
			l.marker:Destroy()
			l.text:Destroy()
		end
		table.clear(labels)
	end

	local function refresh()
		clear()
		for _, n in cs.nations do
			local capital = n.capital
			if capital ~= nil and n.alive then
				local isMe = n.id == cs.myNation
				local color = Theme.color("White")
				if n.colorIndex >= 1 then
					local c = NationColors.Colors[n.colorIndex]
					color = Color3.fromRGB(c.r, c.g, c.b)
				end

				local marker = Instance.new("Frame")
				marker.Name = "Capital_" .. n.id
				marker.AnchorPoint = Vector2.new(0.5, 0.5)
				marker.BackgroundColor3 = color
				marker.BorderSizePixel = 0
				marker.ZIndex = 4
				local stroke = Instance.new("UIStroke")
				stroke.Color = if isMe then Theme.Colors.Gold else Theme.Colors.Backdrop
				stroke.Thickness = if isMe then 2 else 1
				stroke.Parent = marker
				marker.Parent = canvas

				local text = Instance.new("TextLabel")
				text.Name = "Name_" .. n.id
				text.AnchorPoint = Vector2.new(0.5, 1)
				text.Size = UDim2.fromOffset(0, Config.Render.NationLabelSize + 4)
				text.AutomaticSize = Enum.AutomaticSize.X
				text.BackgroundTransparency = 1
				text.FontFace = Theme.FontBold
				text.TextSize = Config.Render.NationLabelSize
				text.TextColor3 = if isMe then Theme.Colors.Gold else Theme.Colors.Text
				text.TextStrokeColor3 = Theme.Colors.Backdrop
				text.TextStrokeTransparency = 0.2
				text.Text = if lang == "en" then n.nameEn else n.name
				text.ZIndex = 5
				text.Parent = canvas

				local l: Label = { capital = capital, marker = marker, text = text }
				place(l)
				table.insert(labels, l)
			end
		end
	end

	return {
		refresh = refresh,
		onCamera = function(state: CameraState)
			if state.zoom ~= zoom then
				zoom = state.zoom
				for _, l in labels do
					place(l)
				end
			end
		end,
	}
end

return table.freeze(NationLabels)
