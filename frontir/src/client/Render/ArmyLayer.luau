--!strict
--[[
	ArmyLayer — армии на карте (GDD §3, §6.6): программный пиксельный спрайт 12×8 (пока нет арта),
	полоска силы над армией, кольцо прогресса из 16 «пикселей» при захвате провинции (голубое)
	и при найме (серое). Позиция плавно идёт между тиками сервера (ClientState.armyPosition).
	Выделенная армия обведена золотом. Спрайты — docs/ART_LIST.md.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local NationColors = require(Shared:WaitForChild("NationColors"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

local RING = 16
local PICK_RADIUS = 14 -- пикселей экрана: попадание по армии

-- Детали спрайта: { x, y, w, h, цвет: "body" | "ink" } в пикселях спрайта 12×8.
type Part = { x: number, y: number, w: number, h: number, ink: boolean }
local SHAPES: { [string]: { Part } } = {
	Infantry = {
		{ x = 2, y = 1, w = 8, h = 6, ink = false },
		{ x = 5, y = 3, w = 2, h = 2, ink = true },
	},
	Tanks = {
		{ x = 0, y = 3, w = 11, h = 5, ink = false },
		{ x = 3, y = 1, w = 5, h = 2, ink = false },
		{ x = 8, y = 1, w = 4, h = 1, ink = true },
		{ x = 1, y = 6, w = 9, h = 1, ink = true },
	},
	Artillery = {
		{ x = 1, y = 4, w = 8, h = 4, ink = false },
		{ x = 5, y = 2, w = 7, h = 1, ink = true },
		{ x = 3, y = 3, w = 2, h = 1, ink = true },
	},
}

type Visual = {
	root: Frame,
	body: { Frame },
	stroke: UIStroke,
	bar: Frame,
	fill: Frame,
	ring: { Frame },
	scale: number,
	kind: string,
	lastRing: number,
	lastFill: number,
	lastSelected: boolean,
}

export type ArmyLayer = {
	update: (now: number, state: CameraState) -> (),
	armyAt: (sx: number, sy: number, state: CameraState, owner: number?, now: number) -> number?,
	armiesInRect: (
		x0: number,
		y0: number,
		x1: number,
		y1: number,
		state: CameraState,
		owner: number,
		now: number
	) -> { number },
	setSelected: (selected: { [number]: boolean }) -> (),
}

local ArmyLayer = {}

function ArmyLayer.new(canvas: Frame, cs: ClientState): ArmyLayer
	local visuals: { [number]: Visual } = {}
	local selected: { [number]: boolean } = {}

	local function nationColor(owner: number): Color3
		local ci = ClientState.colorIndexOf(cs, owner)
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Muted
	end

	local function build(kind: string, owner: number, scale: number): Visual
		local root = Instance.new("Frame")
		root.Name = "Army"
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Size = UDim2.fromOffset(12 * scale, 8 * scale)
		root.BackgroundTransparency = 1
		root.ZIndex = 7
		local body: { Frame } = {}
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Colors.Backdrop
		stroke.Thickness = 1
		for k, part in SHAPES[kind] or SHAPES.Infantry do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.Position = UDim2.fromOffset(part.x * scale, part.y * scale)
			f.Size = UDim2.fromOffset(part.w * scale, part.h * scale)
			f.BackgroundColor3 = if part.ink then Theme.Colors.Backdrop else nationColor(owner)
			f.ZIndex = 8
			f.Parent = root
			if k == 1 then
				stroke.Parent = f
			end
			table.insert(body, f)
		end
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Theme.Colors.Backdrop
		bar.Position = UDim2.fromOffset(0, -3 * scale)
		bar.Size = UDim2.fromOffset(12 * scale, 2 * scale)
		bar.ZIndex = 8
		bar.Parent = root
		local fill = Instance.new("Frame")
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = Theme.Colors.Gold
		fill.Size = UDim2.fromScale(1, 1)
		fill.ZIndex = 9
		fill.Parent = bar
		local ring: { Frame } = {}
		local radius = 9 * scale
		for k = 0, RING - 1 do
			local a = k / RING * 2 * math.pi - math.pi / 2
			local dot = Instance.new("Frame")
			dot.BorderSizePixel = 0
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Size = UDim2.fromOffset(2 * scale, 2 * scale)
			dot.Position = UDim2.fromOffset(6 * scale + math.cos(a) * radius, 4 * scale + math.sin(a) * radius)
			dot.BackgroundTransparency = 1
			dot.ZIndex = 7
			dot.Parent = root
			table.insert(ring, dot)
		end
		root.Parent = canvas
		return {
			root = root,
			body = body,
			stroke = stroke,
			bar = bar,
			fill = fill,
			ring = ring,
			scale = scale,
			kind = kind,
			lastRing = -1,
			lastFill = -1,
			lastSelected = false,
		}
	end

	local function update(now: number, state: CameraState)
		local scale = if state.zoom >= 6 then 2 else 1
		for id, v in visuals do
			local a = cs.armies[id]
			if a == nil or v.scale ~= scale or v.kind ~= a.kind then
				v.root:Destroy()
				visuals[id] = nil
			end
		end
		for id, a in cs.armies do
			local v = visuals[id]
			if v == nil then
				v = build(a.kind, a.owner, scale)
				visuals[id] = v
			end
			local x, y = ClientState.armyPosition(a, now)
			v.root.Position = UDim2.fromOffset(math.round(x * state.zoom), math.round(y * state.zoom))
			-- Полоска силы.
			local fillShare = math.clamp(a.strength / math.max(1, a.maxStrength), 0, 1)
			if fillShare ~= v.lastFill then
				v.lastFill = fillShare
				v.fill.Size = UDim2.fromScale(fillShare, 1)
			end
			-- Кольцо прогресса: захват — голубое, найм — серое, иначе скрыто.
			local showRing = a.state == "capture" or a.state == "recruit"
			local lit = if showRing then math.floor(a.progress * RING + 0.5) else -1
			local ringKey = lit * 2 + (if a.state == "recruit" then 1 else 0)
			if ringKey ~= v.lastRing then
				v.lastRing = ringKey
				local color = if a.state == "recruit" then Theme.Colors.Muted else Theme.Colors.Sky
				for k, dot in v.ring do
					if showRing then
						dot.BackgroundColor3 = if k <= lit then color else Theme.Colors.Backdrop
						dot.BackgroundTransparency = if k <= lit then 0 else 0.4
					else
						dot.BackgroundTransparency = 1
					end
				end
				for k, part in v.body do
					if k == 1 then
						part.BackgroundTransparency = if a.state == "recruit" then 0.5 else 0
					end
				end
			end
			local isSelected = selected[id] == true
			if isSelected ~= v.lastSelected then
				v.lastSelected = isSelected
				v.stroke.Color = if isSelected then Theme.Colors.Gold else Theme.Colors.Backdrop
				v.stroke.Thickness = if isSelected then 2 else 1
				v.root.ZIndex = if isSelected then 9 else 7
			end
		end
	end

	local function screenOf(a: ClientState.ClientArmy, state: CameraState, now: number): (number, number)
		local x, y = ClientState.armyPosition(a, now)
		return CameraMath.worldToScreen(state, x, y)
	end

	local function armyAt(sx: number, sy: number, state: CameraState, owner: number?, now: number): number?
		local best: number? = nil
		local bestD = PICK_RADIUS * PICK_RADIUS
		for id, a in cs.armies do
			if owner == nil or a.owner == owner then
				local ax, ay = screenOf(a, state, now)
				local d = (ax - sx) ^ 2 + (ay - sy) ^ 2
				if d <= bestD then
					best, bestD = id, d
				end
			end
		end
		return best
	end

	local function armiesInRect(
		x0: number,
		y0: number,
		x1: number,
		y1: number,
		state: CameraState,
		owner: number,
		now: number
	): { number }
		local out: { number } = {}
		local lx, hx = math.min(x0, x1), math.max(x0, x1)
		local ly, hy = math.min(y0, y1), math.max(y0, y1)
		for id, a in cs.armies do
			if a.owner == owner then
				local ax, ay = screenOf(a, state, now)
				if ax >= lx and ax <= hx and ay >= ly and ay <= hy then
					table.insert(out, id)
				end
			end
		end
		table.sort(out)
		return out
	end

	return {
		update = update,
		armyAt = armyAt,
		armiesInRect = armiesInRect,
		setSelected = function(s: { [number]: boolean })
			selected = s
		end,
	}
end

return table.freeze(ArmyLayer)
