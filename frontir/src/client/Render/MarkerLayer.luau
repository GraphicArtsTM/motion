--!strict
--[[
	MarkerLayer — круги на карте (этап 7г): шторм на море (§6.16, голубой) и ракеты в полёте (§6.9, красный круг
	удара с обратным отсчётом). Рамки на canvas карты; положение — по камере (CameraMath.cellEdge), данные — из
	ClientState.world (раз в секунду) и события missileLaunched (сразу).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type MarkerLayer = {
	refresh: () -> (), -- пришло сообщение world
	onEvents: (events: { any }) -> (),
	update: (now: number, state: CameraState) -> (),
}

type Marker = { frame: Frame, label: TextLabel?, cell: number, radius: number, endsAt: number }

local MarkerLayer = {}

function MarkerLayer.new(canvas: Frame, cs: ClientState): MarkerLayer
	local markers: { [string]: Marker } = {}
	local width = cs.width

	local function make(key: string, color: Color3, withLabel: boolean): Marker
		local f = Instance.new("Frame")
		f.Name = "Marker_" .. key
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 0.8
		f.BorderSizePixel = 0
		f.ZIndex = 9
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 2
		stroke.Parent = f
		local label: TextLabel? = nil
		if withLabel then
			local l = Instance.new("TextLabel")
			l.AnchorPoint = Vector2.new(0.5, 0.5)
			l.Position = UDim2.fromScale(0.5, 0.5)
			l.Size = UDim2.fromOffset(40, 20)
			l.BackgroundTransparency = 1
			l.FontFace = Theme.FontBold
			l.TextSize = 16
			l.TextColor3 = Theme.Colors.Text
			l.TextStrokeTransparency = 0.3
			l.ZIndex = 10
			l.Parent = f
			label = l
		end
		f.Parent = canvas
		local m: Marker = { frame = f, label = label, cell = 0, radius = 1, endsAt = 0 }
		markers[key] = m
		return m
	end

	local function set(key: string, color: Color3, cell: number, radius: number, endsAt: number, withLabel: boolean)
		local m = markers[key] or make(key, color, withLabel)
		m.cell, m.radius, m.endsAt = cell, radius, endsAt
	end

	local function refresh()
		local now = os.clock()
		local speed = Config.Match.Speed
		local live: { [string]: boolean } = {}
		local storm = cs.world.storm
		if storm ~= nil then
			set("storm", Theme.Colors.Sky, storm.cell, storm.radius, now + storm.left / speed, false)
			live.storm = true
		end
		for _, mi in cs.world.missiles do
			local key = "missile_" .. mi.cell
			set(
				key,
				Theme.Colors.Alert,
				mi.cell,
				Config.Buildings.MissileSilo.strikeRadius,
				now + mi.left / speed,
				true
			)
			live[key] = true
		end
		for key, m in markers do
			if not live[key] and os.clock() >= m.endsAt then
				m.frame:Destroy()
				markers[key] = nil
			end
		end
	end

	local function onEvents(events: { any })
		local now = os.clock()
		for _, e in events do
			if type(e) == "table" and e.kind == "missileLaunched" and type(e.cell) == "number" then
				local left = (tonumber(e.impactIn) or 0) / Config.Match.Speed
				set(
					"missile_" .. e.cell,
					Theme.Colors.Alert,
					e.cell,
					Config.Buildings.MissileSilo.strikeRadius,
					now + left,
					true
				)
			elseif
				type(e) == "table"
				and (e.kind == "missileHit" or e.kind == "missileShot")
				and type(e.cell) == "number"
			then
				local m = markers["missile_" .. e.cell]
				if m ~= nil then
					m.frame:Destroy()
					markers["missile_" .. e.cell] = nil
				end
			end
		end
	end

	local function update(now: number, state: CameraState)
		local zoom = state.zoom
		for key, m in markers do
			if now >= m.endsAt + 1 then
				m.frame:Destroy()
				markers[key] = nil
				continue
			end
			local cx, cy = m.cell % width, m.cell // width
			local x0 = CameraMath.cellEdge(zoom, cx - m.radius)
			local x1 = CameraMath.cellEdge(zoom, cx + m.radius + 1)
			local y0 = CameraMath.cellEdge(zoom, cy - m.radius)
			local y1 = CameraMath.cellEdge(zoom, cy + m.radius + 1)
			m.frame.Position = UDim2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2)
			m.frame.Size = UDim2.fromOffset(x1 - x0, y1 - y0)
			local label = m.label
			if label ~= nil then
				label.Text = tostring(math.max(0, math.ceil((m.endsAt - now) * Config.Match.Speed)))
			end
		end
	end

	return { refresh = refresh, onEvents = onEvents, update = update }
end

return table.freeze(MarkerLayer)
