--!strict
--[[
	NationLabels — города, столицы и названия держав на карте (GDD §6.5).
	- Город: квадрат цвета владельца (ничей — серый) с белой точкой посередине.
	- Столица: квадрат цвета державы с обводкой (своя — золотая, толще) и подпись названия над ним.
	До раздачи цветов (выбор старта) выбранные точки — белые квадраты с именем.
	Метки живут на холсте карты и едут вместе с камерой; при смене зума пересчитываются позиции,
	при смене владельца клеток (recolor) — цвета городов. Спрайты города и столицы — docs/ART_LIST.md.
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

type Marker = { cell: number, frame: Frame, dot: Frame?, text: TextLabel?, owner: number }

export type NationLabels = {
	refresh: () -> (),
	recolor: () -> (),
	onCamera: (state: CameraState) -> (),
}

local NationLabels = {}

function NationLabels.new(canvas: Frame, cs: ClientState, lang: Strings.Lang, mapWidth: number): NationLabels
	local markers: { Marker } = {}
	local zoom = 1

	local function ownerColor(owner: number): Color3
		local ci = ClientState.colorIndexOf(cs, owner)
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return if owner == 0 then Theme.Colors.Muted else Theme.color("White")
	end

	local function place(m: Marker)
		local cx, cy = m.cell % mapWidth, m.cell // mapWidth
		local left, top = CameraMath.cellEdge(zoom, cx), CameraMath.cellEdge(zoom, cy)
		local cellW = CameraMath.cellEdge(zoom, cx + 1) - left
		local side = math.max(if m.text ~= nil then 6 else 5, cellW)
		local centerX, centerY = left + cellW / 2, top + (CameraMath.cellEdge(zoom, cy + 1) - top) / 2
		m.frame.Size = UDim2.fromOffset(side, side)
		m.frame.Position = UDim2.fromOffset(centerX, centerY)
		local text = m.text
		if text ~= nil then
			text.Position = UDim2.fromOffset(centerX, centerY - side / 2 - 2)
		end
	end

	local function clear()
		for _, m in markers do
			m.frame:Destroy()
			if m.text ~= nil then
				m.text:Destroy()
			end
		end
		table.clear(markers)
	end

	local function addMarker(cell: number, capitalOf: ClientState.NationInfo?)
		local owner = if capitalOf ~= nil then capitalOf.id else ClientState.ownerAt(cs, cell)
		local frame = Instance.new("Frame")
		frame.Name = if capitalOf ~= nil then "Capital_" .. capitalOf.id else "City_" .. cell
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundColor3 = ownerColor(owner)
		frame.BorderSizePixel = 0
		frame.ZIndex = 4
		local isMe = capitalOf ~= nil and capitalOf.id == cs.myNation
		local stroke = Instance.new("UIStroke")
		stroke.Color = if isMe then Theme.Colors.Gold else Theme.Colors.Backdrop
		stroke.Thickness = if isMe then 2 else 1
		stroke.Parent = frame
		local dot: Frame? = nil
		if capitalOf == nil then
			local d = Instance.new("Frame")
			d.AnchorPoint = Vector2.new(0.5, 0.5)
			d.Position = UDim2.fromScale(0.5, 0.5)
			d.Size = UDim2.fromScale(0.4, 0.4)
			d.BackgroundColor3 = Theme.color("White")
			d.BorderSizePixel = 0
			d.ZIndex = 5
			d.Parent = frame
			dot = d
		end
		frame.Parent = canvas

		local text: TextLabel? = nil
		if capitalOf ~= nil then
			local t = Instance.new("TextLabel")
			t.Name = "Name_" .. capitalOf.id
			t.AnchorPoint = Vector2.new(0.5, 1)
			t.Size = UDim2.fromOffset(0, Config.Render.NationLabelSize + 4)
			t.AutomaticSize = Enum.AutomaticSize.X
			t.BackgroundTransparency = 1
			t.FontFace = Theme.FontBold
			t.TextSize = Config.Render.NationLabelSize
			t.TextColor3 = if isMe then Theme.Colors.Gold else Theme.Colors.Text
			t.TextStrokeColor3 = Theme.Colors.Backdrop
			t.TextStrokeTransparency = 0.2
			t.Text = if lang == "en" then capitalOf.nameEn else capitalOf.name
			t.ZIndex = 5
			t.Parent = canvas
			text = t
		end
		local m: Marker = { cell = cell, frame = frame, dot = dot, text = text, owner = owner }
		place(m)
		table.insert(markers, m)
	end

	local function refresh()
		clear()
		local capitals: { [number]: ClientState.NationInfo } = {}
		for _, n in cs.nations do
			if n.capital ~= nil and n.alive then
				capitals[n.capital] = n
			end
		end
		for cell, n in capitals do
			addMarker(cell, n)
		end
		for _, cell in cs.cities do
			if capitals[cell] == nil then
				addMarker(cell, nil)
			end
		end
	end

	-- Владельцы городов меняются вместе с клетками: перекрашиваем только изменившиеся.
	local function recolor()
		for _, m in markers do
			if m.text == nil then
				local owner = ClientState.ownerAt(cs, m.cell)
				if owner ~= m.owner then
					m.owner = owner
					m.frame.BackgroundColor3 = ownerColor(owner)
				end
			end
		end
	end

	return {
		refresh = refresh,
		recolor = recolor,
		onCamera = function(state: CameraState)
			if state.zoom ~= zoom then
				zoom = state.zoom
				for _, m in markers do
					place(m)
				end
			end
		end,
	}
end

return table.freeze(NationLabels)
