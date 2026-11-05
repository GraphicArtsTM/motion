--!strict
--[[
	AirLayer — самолёты на карте (GDD §6.13, этап 7б-2). Позиции приходят сообщением AIR Net.StatsHz раз в секунду;
	между ними самолёт плавно летит от прошлой точки к новой. Спрайт — Shared.PlaneSprites (общие с превью), под
	ним тень со сдвигом Render.PlaneShadow. Чужой самолёт вне обзора не рисуется (туман, §6.11). Выбранный
	истребитель — золотая обводка и круг перехвата. Выведенные из строя здания — тёмная рамка.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Fog = require(Shared:WaitForChild("Fog"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local PlaneSprites = require(Shared:WaitForChild("PlaneSprites"))
local Protocol = require(Shared:WaitForChild("Net"):WaitForChild("Protocol"))
local UnitSprites = require(Shared:WaitForChild("UnitSprites"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type AirLayer = {
	refresh: () -> (), -- пришло AIR
	update: (now: number, state: CameraState) -> (),
	select: (id: number?) -> (),
	-- Ближайший к точке (в клетках) самолёт державы owner не дальше reach клеток.
	pick: (x: number, y: number, owner: number, reach: number) -> Protocol.PlaneInfo?,
}

type Sprite = {
	root: Frame,
	shadow: Frame,
	parts: { Frame },
	kind: string,
	owner: number,
	fromX: number,
	fromY: number,
	toX: number,
	toY: number,
	x: number,
	y: number,
	flip: boolean,
	info: Protocol.PlaneInfo,
	stroke: UIStroke,
}

local AirLayer = {}

function AirLayer.new(canvas: Frame, cs: ClientState): AirLayer
	local sprites: { [number]: Sprite } = {}
	local marks: { [number]: Frame } = {}
	local selected: number? = nil
	local stepSec = 1 / Config.Net.StatsHz

	local ring = Instance.new("Frame")
	ring.Name = "FighterCover"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.ZIndex = 11
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Theme.Colors.Gold
	ringStroke.Transparency = 0.3
	ringStroke.Parent = ring
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	ring.Parent = canvas

	local function colorOf(owner: number): Color3
		local ci = ClientState.colorIndexOf(cs, owner)
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Muted
	end

	local function newSprite(info: Protocol.PlaneInfo): Sprite
		local shadow = Instance.new("Frame")
		shadow.Name = "PlaneShadow" .. info.id
		shadow.AnchorPoint = Vector2.new(0.5, 0.5)
		shadow.BackgroundColor3 = Theme.Colors.Backdrop
		shadow.BackgroundTransparency = 0.55
		shadow.BorderSizePixel = 0
		shadow.ZIndex = 11
		shadow.Parent = canvas
		local root = Instance.new("Frame")
		root.Name = "Plane" .. info.id
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.BackgroundTransparency = 1
		root.ZIndex = 12
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Colors.Gold
		stroke.Enabled = false
		stroke.Parent = root
		local parts: { Frame } = {}
		for _, p in PlaneSprites.Shapes[info.kind] do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.ZIndex = 13
			f.BackgroundColor3 = if p.ink then Theme.Colors.Backdrop else colorOf(info.owner)
			f.Parent = root
			table.insert(parts, f)
		end
		root.Parent = canvas
		return {
			root = root,
			shadow = shadow,
			parts = parts,
			kind = info.kind,
			owner = info.owner,
			fromX = info.x,
			fromY = info.y,
			toX = info.x,
			toY = info.y,
			x = info.x,
			y = info.y,
			flip = false,
			info = info,
			stroke = stroke,
		}
	end

	local function refresh()
		local seen: { [number]: boolean } = {}
		for _, info in cs.air.planes do
			seen[info.id] = true
			local existing: Sprite? = sprites[info.id]
			local s: Sprite
			if existing == nil or existing.kind ~= info.kind or existing.owner ~= info.owner then
				if existing ~= nil then
					existing.root:Destroy()
					existing.shadow:Destroy()
				end
				s = newSprite(info)
				sprites[info.id] = s
			else
				s = existing
			end
			s.fromX, s.fromY = s.x, s.y
			s.toX, s.toY = info.x, info.y
			if math.abs(info.x - s.fromX) > 0.01 then
				s.flip = info.x < s.fromX
			end
			s.info = info
		end
		for id, s in sprites do
			if not seen[id] then
				s.root:Destroy()
				s.shadow:Destroy()
				sprites[id] = nil
			end
		end
		-- Выведенные из строя здания.
		local off: { [number]: boolean } = {}
		for _, d in cs.air.disabled do
			off[d.cell] = true
			local mark: Frame? = marks[d.cell]
			if mark == nil then
				local f = Instance.new("Frame")
				f.Name = "Disabled_" .. d.cell
				f.AnchorPoint = Vector2.new(0.5, 1)
				f.BackgroundColor3 = Theme.Colors.Backdrop
				f.BackgroundTransparency = 0.35
				f.BorderSizePixel = 0
				f.ZIndex = 8
				f.Parent = canvas
				marks[d.cell] = f
			end
		end
		for cell, f in marks do
			if not off[cell] then
				f:Destroy()
				marks[cell] = nil
			end
		end
	end

	local function update(now: number, state: CameraState)
		local zoom = state.zoom
		local scale = UnitSprites.scaleFor(zoom)
		local t = math.clamp((now - cs.airAt) / stepSec, 0, 1)
		local friends = if cs.myNation ~= nil then ClientState.friendsOf(cs, cs.myNation :: number) else {}
		local w = cs.width
		local shadowOffset = Config.Render.PlaneShadow * scale
		for id, s in sprites do
			s.x = s.fromX + (s.toX - s.fromX) * t
			s.y = s.fromY + (s.toY - s.fromY) * t
			local cell = math.floor(s.y) * w + math.floor(s.x)
			local visible = friends[s.owner] == true or Fog.isVisible(cs.fog, cell)
			local flying = s.info.state ~= "based"
			s.root.Visible = visible
			s.shadow.Visible = visible and flying
			if visible then
				local sw, sh = PlaneSprites.Width * scale, PlaneSprites.Height * scale
				local px, py = math.round(s.x * zoom), math.round(s.y * zoom)
				s.root.Size = UDim2.fromOffset(sw, sh)
				s.root.Position = UDim2.fromOffset(px, py)
				s.shadow.Size = UDim2.fromOffset(sw - scale * 2, sh // 2)
				s.shadow.Position = UDim2.fromOffset(px + shadowOffset, py + shadowOffset + sh // 2)
				for k, p in PlaneSprites.Shapes[s.kind] do
					local x = if s.flip then PlaneSprites.Width - p.x - p.w else p.x
					s.parts[k].Position = UDim2.fromOffset(x * scale, p.y * scale)
					s.parts[k].Size = UDim2.fromOffset(p.w * scale, p.h * scale)
				end
			end
			s.stroke.Enabled = id == selected
		end
		local sel = if selected ~= nil then sprites[selected :: number] else nil
		if sel ~= nil and sel.kind == "Fighter" and sel.root.Visible then
			local r = Config.Air.InterceptRadius * w / Config.UnitsReferenceMapWidth * zoom
			ring.Visible = true
			ring.Size = UDim2.fromOffset(r * 2, r * 2)
			ring.Position = UDim2.fromOffset(math.round(sel.x * zoom), math.round(sel.y * zoom))
		else
			ring.Visible = false
		end
		for cell, f in marks do
			local size = 7 * (if zoom >= 6 then 2 else 1) + 2
			f.Size = UDim2.fromOffset(size, size)
			f.Position = UDim2.fromOffset(math.round((cell % w + 0.5) * zoom), math.round((cell // w) * zoom) + 1)
		end
	end

	return {
		refresh = refresh,
		update = update,
		select = function(id: number?)
			selected = id
		end,
		pick = function(x: number, y: number, owner: number, reach: number): Protocol.PlaneInfo?
			local best: Protocol.PlaneInfo? = nil
			local bestD = reach * reach
			for _, s in sprites do
				if s.owner == owner then
					local dx, dy = s.x - x, s.y - y
					local d = dx * dx + dy * dy
					if d <= bestD then
						best, bestD = s.info, d
					end
				end
			end
			return best
		end,
	}
end

return table.freeze(AirLayer)
