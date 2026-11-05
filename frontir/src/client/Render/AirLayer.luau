--!strict
--[[
	AirLayer — самолёты на карте (GDD §6.13, этап 7б-2). Позиции приходят сообщением AIR Net.StatsHz раз в секунду;
	между ними самолёт плавно летит от прошлой точки к новой. Спрайт — Shared.PlaneSprites (общие с превью), под
	ним тень со сдвигом Render.PlaneShadow. Чужой самолёт вне обзора не рисуется (туман, §6.11). Выбранный
	истребитель — золотая обводка и круг перехвата. Выведенные из строя здания — тёмная рамка.
	Видимость (Render.Air): самолёт не мельче MinPlanePx на экране при любом зуме; налёт — вспышки бомб в круге
	Air.BombRadius; сбитый самолёт падает, крутясь, и взрывается (события raid и planeShot, только в обзоре).
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
	onEvents: (events: { any }) -> (), -- налёты и сбитые самолёты — эффекты
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

	-- Эффекты: вспышки бомб, падение сбитого самолёта и взрыв. Координаты — в клетках.
	type Effect = {
		kind: "flash" | "fall" | "boom",
		frame: Frame,
		x: number,
		y: number,
		start: number,
		life: number,
		size: number, -- при зуме ×1, пикселей
	}
	local fx = Config.Render.Air
	local effects: { Effect } = {}
	local orange, gold, white = Theme.color("Orange"), Theme.Colors.Gold, Theme.Colors.Text

	local function addEffect(e: Effect)
		if #effects >= fx.MaxEffects then
			e.frame:Destroy()
			return
		end
		e.frame.Parent = canvas
		table.insert(effects, e)
	end
	local function round(color: Color3, z: number): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.ZIndex = z
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
		return f
	end
	local function visibleAt(x: number, y: number, owner: number?): boolean
		local w = cs.width
		local cx, cy = math.floor(x), math.floor(y)
		if cx < 0 or cy < 0 or cx >= w or cy >= cs.height then
			return false
		end
		if owner ~= nil and cs.myNation ~= nil then
			local friends = ClientState.friendsOf(cs, cs.myNation :: number)
			if friends[owner] then
				return true
			end
		end
		return Fog.isVisible(cs.fog, cy * w + cx)
	end

	local function onEvents(events: { any })
		local now = os.clock()
		local w = cs.width
		for _, e in events do
			if type(e) ~= "table" then
				continue
			end
			if e.kind == "raid" and type(e.cell) == "number" then
				local cx, cy = e.cell % w + 0.5, e.cell // w + 0.5
				if visibleAt(cx, cy, tonumber(e.nation)) then
					-- Вспышки бомб — по кругу налёта, одна за другой.
					local r = Config.Air.BombRadius
					for k = 1, fx.BombFlashes do
						local a = math.random() * math.pi * 2
						local d = math.sqrt(math.random()) * r
						local color = if k % 3 == 0 then white elseif k % 2 == 0 then gold else orange
						addEffect({
							kind = "flash",
							frame = round(color, 14),
							x = cx + math.cos(a) * d,
							y = cy + math.sin(a) * d,
							start = now + (k - 1) / fx.BombFlashes * fx.BombFlashSec,
							life = fx.FlashLifeSec,
							size = fx.FlashPx,
						})
					end
				end
			elseif e.kind == "planeShot" and type(e.x) == "number" and type(e.y) == "number" then
				if visibleAt(e.x, e.y, nil) then
					-- Сбитый самолёт: копия спрайта цветом державы падает, крутясь; потом взрыв.
					local kind = if e.plane == "Fighter" then "Fighter" else "Bomber"
					local f = Instance.new("Frame")
					f.AnchorPoint = Vector2.new(0.5, 0.5)
					f.BackgroundTransparency = 1
					f.ZIndex = 14
					for _, p in PlaneSprites.Shapes[kind] do
						local part = Instance.new("Frame")
						part.BorderSizePixel = 0
						part.ZIndex = 15
						part.BackgroundColor3 = if p.ink
							then Theme.Colors.Backdrop
							else colorOf(tonumber(e.nation) or 0)
						part.Name = string.format("%d_%d_%d_%d", p.x, p.y, p.w, p.h)
						part.Parent = f
					end
					addEffect({ kind = "fall", frame = f, x = e.x, y = e.y, start = now, life = fx.FallSec, size = 0 })
				end
			end
		end
	end

	local function drawEffects(now: number, zoom: number, scale: number)
		local j = 1
		while j <= #effects do
			local e = effects[j]
			local t = (now - e.start) / e.life
			if t >= 1 then
				if e.kind == "fall" then
					-- Конец падения — взрыв.
					local y = e.y + fx.FallCells
					local boom = round(orange, 14)
					boom.Parent = canvas
					effects[j] = {
						kind = "boom",
						frame = boom,
						x = e.x,
						y = y,
						start = now,
						life = fx.ExplosionSec,
						size = fx.FlashPx * 2,
					}
					e.frame:Destroy()
					j += 1
				else
					e.frame:Destroy()
					table.remove(effects, j)
				end
				continue
			end
			local f = e.frame
			if t < 0 then
				f.Visible = false
			elseif e.kind == "fall" then
				f.Visible = true
				local sw, sh = PlaneSprites.Width * scale, PlaneSprites.Height * scale
				f.Size = UDim2.fromOffset(sw, sh)
				f.Position = UDim2.fromOffset(math.round(e.x * zoom), math.round((e.y + fx.FallCells * t * t) * zoom))
				f.Rotation = 200 * t
				for _, part in f:GetChildren() do
					if part:IsA("Frame") then
						local n = string.split(part.Name, "_")
						part.Position = UDim2.fromOffset((tonumber(n[1]) or 0) * scale, (tonumber(n[2]) or 0) * scale)
						part.Size = UDim2.fromOffset((tonumber(n[3]) or 0) * scale, (tonumber(n[4]) or 0) * scale)
						part.BackgroundTransparency = t * 0.5
					end
				end
			else
				f.Visible = true
				local grow = math.sin(t * math.pi) -- растёт и гаснет
				local px = e.size * math.max(1, zoom / 2) * (0.4 + grow)
				f.Size = UDim2.fromOffset(px, px)
				f.Position = UDim2.fromOffset(math.round(e.x * zoom), math.round(e.y * zoom))
				f.BackgroundTransparency = 0.1 + 0.9 * t
			end
			j += 1
		end
	end

	local function update(now: number, state: CameraState)
		local zoom = state.zoom
		-- Самолёт не мельче MinPlanePx на экране при любом зуме.
		local scale = math.max(UnitSprites.scaleFor(zoom), math.ceil(fx.MinPlanePx / PlaneSprites.Width))
		drawEffects(now, zoom, scale)
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
		onEvents = onEvents,
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
