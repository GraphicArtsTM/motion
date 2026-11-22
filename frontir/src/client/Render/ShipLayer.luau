--!strict
--[[
	ShipLayer — корабли на карте (GDD §6.12, этап 7б-1). Позиции приходят сообщением SHIPS Net.StatsHz раз
	в секунду; между ними корабль плавно идёт от прошлой точки к новой. Спрайты — Shared.ShipSprites (общие
	с превью), цвет — цвет державы. Чужой корабль вне обзора не рисуется (туман, §6.11; сервер и так шлёт только
	то, что в грубом обзоре). Выбранный корабль — золотая обводка, у эсминца — круг дальности.
	У заблокированного порта — красная рамка.
	§15ы: корабль крупнее (MapIcons.shipSide — от зума), картинка слегка в цвет державы (Render.ShipAnim.Tint), под
	корпусом — «лодочка» цвета державы со светлым кантом (тёмный пропадал на тёмной воде).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Fog = require(Shared:WaitForChild("Fog"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Protocol = require(Shared:WaitForChild("Net"):WaitForChild("Protocol"))
local ShipSprites = require(Shared:WaitForChild("ShipSprites"))
local UnitSprites = require(Shared:WaitForChild("UnitSprites"))
local IconArt = require(Shared:WaitForChild("IconArt"))
local MapArt = require(Shared:WaitForChild("MapArt"))
local MapIcons = require(Shared:WaitForChild("MapIcons"))

local IconImage = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("IconImage"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type ShipLayer = {
	refresh: () -> (), -- пришло SHIPS
	update: (now: number, state: CameraState) -> (),
	select: (id: number?) -> (),
	-- Ближайший к точке (в клетках) корабль державы owner не дальше reach клеток.
	pick: (x: number, y: number, owner: number, reach: number) -> Protocol.ShipInfo?,
	-- §15х ч.9: видимые сейчас корабли (плавная позиция и куда идут) — для кильватера и морского боя.
	visible: () -> { VisibleShip },
}

export type VisibleShip = { id: number, owner: number, kind: string, x: number, y: number, dx: number, dy: number }

type Sprite = {
	root: Frame,
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
	info: Protocol.ShipInfo,
	stroke: UIStroke,
	-- §15я Я4: корабль картинкой (assets/icons/units) на овале цвета державы; nil — пиксельный спрайт.
	image: ImageLabel?,
	base: Frame?,
	shownFlip: boolean?, -- в какую сторону сейчас смотрит картинка
	smooth: boolean, -- §15ы Ы4: гладкая картинка MapArt (обрезана по кораблю, h/w — aspect)
	aspect: number,
	phase: number, -- покачивание на волне
}

local ShipLayer = {}

function ShipLayer.new(canvas: Frame, cs: ClientState): ShipLayer
	local sprites: { [number]: Sprite } = {}
	local blockMarks: { [number]: Frame } = {}
	local selected: number? = nil
	local ring = Instance.new("Frame")
	ring.Name = "DestroyerRange"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.ZIndex = 8
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Theme.Colors.Gold
	ringStroke.Thickness = 1
	ringStroke.Transparency = 0.3
	ringStroke.Parent = ring
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	ring.Parent = canvas
	local stepSec = 1 / Config.Net.StatsHz

	local function colorOf(owner: number): Color3
		local ci = ClientState.colorIndexOf(cs, owner)
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Muted
	end

	local function newSprite(info: Protocol.ShipInfo): Sprite
		local root = Instance.new("Frame")
		root.Name = "Ship" .. info.id
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.BackgroundTransparency = 1
		root.ZIndex = 9
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Colors.Gold
		stroke.Thickness = 1
		stroke.Enabled = false
		stroke.Parent = root
		local parts: { Frame } = {}
		-- §15ы Ы4: сначала гладкая картинка MapArt (корабль во всю ширину, с контуром), иначе — иконка палитры.
		local smoothContent = IconImage.mapArt(info.kind)
		local content = smoothContent or (if IconArt.has(info.kind) then IconImage.content(info.kind) else nil)
		local artW, artH = MapArt.size(info.kind)
		local smooth = smoothContent ~= nil and artW > 0
		local image: ImageLabel? = nil
		local base: Frame? = nil
		if content ~= nil then
			local owner = colorOf(info.owner)
			local b = Instance.new("Frame")
			b.Name = "Base"
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.BackgroundColor3 = owner
			b.BackgroundTransparency = 0
			b.BorderSizePixel = 0
			b.ZIndex = 9
			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0.5, 0)
			bc.Parent = b
			-- §15ы: светлый кант — «лодочку» видно на тёмной воде.
			local bs = Instance.new("UIStroke")
			bs.Color = Theme.color("White")
			bs.Thickness = 1.5
			bs.Transparency = 0.15
			bs.Parent = b
			b.Parent = root
			base = b
			local img = Instance.new("ImageLabel")
			img.Name = "Picture"
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.BackgroundTransparency = 1
			img.ScaleType = Enum.ScaleType.Fit
			img.ResampleMode = if smooth then Enum.ResamplerMode.Default else Enum.ResamplerMode.Pixelated
			img.ImageContent = content
			-- §15ы: серый корпус чуть в цвет державы — свой и чужой флот различимы и без «лодочки».
			img.ImageColor3 = Color3.new(1, 1, 1):Lerp(owner, Config.Render.ShipAnim.Tint)
			img.ZIndex = 10
			img.Parent = root
			image = img
		else
			for _, p in ShipSprites.Shapes[info.kind] do
				local f = Instance.new("Frame")
				f.BorderSizePixel = 0
				f.ZIndex = 10
				f.BackgroundColor3 = if p.ink
					then Theme.Colors.Backdrop
					elseif p.light then Theme.Colors.Text
					else colorOf(info.owner)
				f.Parent = root
				table.insert(parts, f)
			end
		end
		root.Parent = canvas
		return {
			root = root,
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
			image = image,
			base = base,
			shownFlip = nil,
			smooth = smooth,
			aspect = if smooth then artH / artW else 1,
			phase = (info.id * 0.7) % (math.pi * 2),
		}
	end

	local function refresh()
		local seen: { [number]: boolean } = {}
		for _, info in cs.ships.ships do
			seen[info.id] = true
			local s = sprites[info.id]
			if s == nil or s.kind ~= info.kind or s.owner ~= info.owner then
				if s ~= nil then
					s.root:Destroy()
				end
				s = newSprite(info)
				sprites[info.id] = s
			end
			local sprite = s :: Sprite
			sprite.fromX, sprite.fromY = sprite.x, sprite.y
			sprite.toX, sprite.toY = info.x, info.y
			if math.abs(info.x - sprite.fromX) > 0.01 then
				sprite.flip = info.x < sprite.fromX
			end
			sprite.info = info
		end
		for id, s in sprites do
			if not seen[id] then
				s.root:Destroy()
				sprites[id] = nil
			end
		end
		-- Заблокированные порты.
		local blocked: { [number]: boolean } = {}
		for _, cell in cs.ships.blocked do
			blocked[cell] = true
			local mark: Frame? = blockMarks[cell]
			if mark == nil then
				local f = Instance.new("Frame")
				f.Name = "Blockade_" .. cell
				f.AnchorPoint = Vector2.new(0.5, 0.5)
				f.BackgroundTransparency = 1
				f.ZIndex = 8
				local st = Instance.new("UIStroke")
				st.Color = Theme.Colors.Alert
				st.Thickness = 2
				st.Parent = f
				f.Parent = canvas
				blockMarks[cell] = f
			end
		end
		for cell, f in blockMarks do
			if not blocked[cell] then
				f:Destroy()
				blockMarks[cell] = nil
			end
		end
	end

	local function update(now: number, state: CameraState)
		local zoom = state.zoom
		local scale = UnitSprites.scaleFor(zoom)
		local t = math.clamp((now - cs.shipsAt) / stepSec, 0, 1)
		local friends = if cs.myNation ~= nil then ClientState.friendsOf(cs, cs.myNation :: number) else {}
		local w = cs.width
		for id, s in sprites do
			s.x = s.fromX + (s.toX - s.fromX) * t
			s.y = s.fromY + (s.toY - s.fromY) * t
			local cell = math.floor(s.y) * w + math.floor(s.x)
			local visible = friends[s.owner] == true or Fog.isVisible(cs.fog, cell)
			s.root.Visible = visible
			if visible then
				local sw, sh = ShipSprites.Width * scale, ShipSprites.Height * scale
				s.root.Size = UDim2.fromOffset(sw, sh)
				s.root.Position = UDim2.fromOffset(math.round(s.x * zoom), math.round(s.y * zoom))
				local img, base = s.image, s.base
				if img ~= nil and base ~= nil then
					-- §15я Я4: картинка по ходу движения, покачивается на волне; овал цвета державы — под корпусом.
					if s.shownFlip ~= s.flip then
						s.shownFlip = s.flip
						local mirror = IconArt.mirror(s.kind, s.flip)
						local content = if s.smooth
							then IconImage.mapArt(s.kind, mirror)
							elseif mirror then IconImage.mirrored(s.kind)
							else IconImage.content(s.kind)
						if content ~= nil then
							img.ImageContent = content
						end
					end
					local a = Config.Render.ShipAnim
					-- §15ы: сторона картинки — от зума; корпус на ней — примерно 0.9 ширины и 0.35 высоты.
					local side = MapIcons.shipSide(zoom)
					local wave = math.sin(now * a.Rate + s.phase)
					local bob = wave * a.BobPx * scale
					img.Rotation = wave * a.RollDeg
					if s.smooth then
						-- §15ы Ы4: гладкая картинка обрезана по кораблю — во всю ширину, высота по её пропорции;
						-- «лодочка» цвета державы — под нижней частью корпуса (ватерлиния).
						local imgH = math.round(side * s.aspect)
						s.root.Size = UDim2.fromOffset(side, imgH)
						img.Size = UDim2.fromOffset(side, imgH)
						img.Position = UDim2.new(0.5, 0, 0.5, math.round(-imgH * 0.06 + bob))
						base.Size = UDim2.fromOffset(math.round(side * 0.86), math.max(6, math.round(side * 0.17)))
						base.Position = UDim2.new(0.5, 0, 0.5, math.round(imgH * 0.3))
					else
						s.root.Size = UDim2.fromOffset(side, math.round(side * 0.5))
						img.Size = UDim2.fromOffset(side, side)
						img.Position = UDim2.new(0.5, 0, 0.5, math.round(-side * 0.08 + bob))
						base.Size = UDim2.fromOffset(math.round(side * 0.82), math.max(6, math.round(side * 0.2)))
						base.Position = UDim2.new(0.5, 0, 0.5, math.round(side * 0.14))
					end
				else
					for k, p in ShipSprites.Shapes[s.kind] do
						local px = if s.flip then ShipSprites.Width - p.x - p.w else p.x
						s.parts[k].Position = UDim2.fromOffset(px * scale, p.y * scale)
						s.parts[k].Size = UDim2.fromOffset(p.w * scale, p.h * scale)
					end
				end
			end
			s.stroke.Enabled = id == selected
		end
		local sel = if selected ~= nil then sprites[selected :: number] else nil
		if sel ~= nil and sel.kind == "Destroyer" and sel.root.Visible then
			local r = Config.Naval.DestroyerRange * w / Config.UnitsReferenceMapWidth * zoom
			ring.Visible = true
			ring.Size = UDim2.fromOffset(r * 2, r * 2)
			ring.Position = UDim2.fromOffset(math.round(sel.x * zoom), math.round(sel.y * zoom))
		else
			ring.Visible = false
		end
		for cell, f in blockMarks do
			local size = math.max(10, 9 * scale)
			f.Size = UDim2.fromOffset(size, size)
			f.Position = UDim2.fromOffset(math.round((cell % w + 0.5) * zoom), math.round((cell // w + 0.5) * zoom))
		end
	end

	return {
		refresh = refresh,
		update = update,
		select = function(id: number?)
			selected = id
		end,
		visible = function(): { VisibleShip }
			local out: { VisibleShip } = {}
			for id, s in sprites do
				if s.root.Visible then
					table.insert(out, {
						id = id,
						owner = s.owner,
						kind = s.kind,
						x = s.x,
						y = s.y,
						dx = s.toX - s.fromX,
						dy = s.toY - s.fromY,
					})
				end
			end
			table.sort(out, function(a: VisibleShip, b: VisibleShip): boolean
				return a.id < b.id
			end)
			return out
		end,
		pick = function(x: number, y: number, owner: number, reach: number): Protocol.ShipInfo?
			local best: Protocol.ShipInfo? = nil
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

return table.freeze(ShipLayer)
