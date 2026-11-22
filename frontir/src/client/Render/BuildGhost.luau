--!strict
--[[
	BuildGhost — «призрак» стройки на карте (§15г): значок здания под курсором (на телефоне — по первому нажатию),
	зелёная рамка — можно, красная — нельзя; у радара, батареи ПВО и аэродрома — круг действия; над значком —
	цена или причина отказа. Логику (можно ли) решает UI/BuildPanel тем же Buildings.check, что и сервер.

	§15ч Ч5б: у станции (город, завод, порт, вышка) — пунктир будущей дороги к сети (rail, клетки пути; Rails.ghost).
	§15ы: значок призрака — того же размера и на том же месте, что будущий значок (MapIcons, центр в клетке);
	слишком близко — у мешающего здания или города красная зона «здесь не строить» (blocker).

	Плюс эффект постройки: новое здание «вырастает» (UIScale с пружинкой), пыль разлетается, своё — «−$цена».
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildingSprites = require(Shared:WaitForChild("BuildingSprites"))
local CitySprites = require(Shared:WaitForChild("CitySprites"))
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local Config = require(Shared:WaitForChild("Config"))
local IconArt = require(Shared:WaitForChild("IconArt"))
local MapIcons = require(Shared:WaitForChild("MapIcons"))

local IconImage = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("IconImage"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type CameraState = CameraMath.CameraState

export type GhostView = {
	kind: string,
	cell: number,
	ok: boolean,
	label: string,
	range: number?,
	color: Color3, -- цвет державы игрока
	rail: { number }?, -- §15ч Ч5б: будущая дорога к сети (клетки)
	blocker: number?, -- §15ы: клетка здания или города, из-за которого «слишком близко»
}

export type BuildGhost = {
	show: (view: GhostView) -> (),
	hide: () -> (),
	onCamera: (state: CameraState) -> (),
	built: (cell: number, label: string?) -> (), -- эффект постройки (label — «−$цена» для своего)
}

local BuildGhost = {}

local GHOST_SCALE = 2 -- пиксельный значок (без картинки) — в клетках спрайта; сторона — MapIcons.buildingBase

function BuildGhost.new(canvas: Frame, mapWidth: number): BuildGhost
	local zoom = 1
	local current: GhostView? = nil
	local size = BuildingSprites.Size

	local root = Instance.new("Frame")
	root.Name = "BuildGhost"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(size * GHOST_SCALE, size * GHOST_SCALE)
	root.ZIndex = 40
	root.Visible = false
	root.Parent = canvas

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.new(1, 8, 1, 8)
	plate.BackgroundColor3 = Theme.Colors.Backdrop
	plate.BackgroundTransparency = 0.45
	plate.BorderSizePixel = 0
	plate.ZIndex = 40
	plate.Parent = root
	local plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(0, 4)
	plateCorner.Parent = plate
	local plateStroke = Instance.new("UIStroke")
	plateStroke.Thickness = 2
	plateStroke.Parent = plate

	local parts: { Frame } = {}
	type Rect = { x: number, y: number, w: number, h: number }
	local partRects: { Rect } = {}
	local shown = ""

	-- §15я Я4: картинка здания (та же, что на карте и в полосе стройки); у «Города» — посёлок City1.
	local picture = Instance.new("ImageLabel")
	picture.Name = "Picture"
	picture.AnchorPoint = Vector2.new(0.5, 0.5)
	picture.Position = UDim2.fromScale(0.5, 0.5)
	picture.Size = UDim2.fromScale(1.05, 1.05)
	picture.BackgroundTransparency = 1
	picture.ScaleType = Enum.ScaleType.Fit
	picture.ResampleMode = Enum.ResamplerMode.Pixelated
	picture.ZIndex = 41
	picture.Visible = false
	picture.Parent = root

	local function pictureOf(kind: string): Content?
		local name = if BuildingSprites.Shapes[kind] == nil then "City1" else kind
		-- §15ы Ы4: город — гладкой картинкой, как на карте (плавно, без Pixelated).
		local smooth = if name == "City1" then IconImage.mapArt(name) else nil
		picture.ResampleMode = if smooth ~= nil then Enum.ResamplerMode.Default else Enum.ResamplerMode.Pixelated
		if smooth ~= nil then
			return smooth
		end
		if not IconArt.has(name) then
			name = if name == "City1" then "City" else name
		end
		return if IconArt.has(name) then IconImage.content(name) else nil
	end

	local function setShape(kind: string, color: Color3, ok: boolean)
		for _, f in parts do
			f:Destroy()
		end
		table.clear(parts)
		table.clear(partRects)
		local content = pictureOf(kind)
		picture.Visible = content ~= nil
		if content ~= nil then
			picture.ImageContent = content
			-- Нельзя поставить — картинка красноватая и бледнее.
			picture.ImageColor3 = if ok then Color3.new(1, 1, 1) else Color3.fromRGB(255, 130, 130)
			picture.ImageTransparency = if ok then 0.05 else 0.3
			plate.BackgroundColor3 = color
			plate.BackgroundTransparency = 0.35
			return
		end
		plate.BackgroundColor3 = Theme.Colors.Backdrop
		plate.BackgroundTransparency = 0.45
		local r, g, b = math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255)
		local shape = BuildingSprites.Shapes[kind]
		local rects: { { x: number, y: number, w: number, h: number, c: Color3 } } = {}
		if shape == nil then
			-- Город (§15д ч.4): посёлок из CitySprites.
			for _, cp in CitySprites.parts(1, false) do
				table.insert(
					rects,
					{ x = cp.x, y = cp.y, w = cp.w, h = cp.h, c = Color3.fromRGB(CitySprites.rgb(cp, r, g, b)) }
				)
			end
		else
			for _, bp in shape do
				table.insert(
					rects,
					{ x = bp.x, y = bp.y, w = bp.w, h = bp.h, c = Color3.fromRGB(BuildingSprites.rgb(bp, r, g, b)) }
				)
			end
		end
		for _, p in rects do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = p.c
			f.BackgroundTransparency = 0.15
			f.Position = UDim2.fromOffset(p.x * GHOST_SCALE, p.y * GHOST_SCALE)
			f.Size = UDim2.fromOffset(p.w * GHOST_SCALE, p.h * GHOST_SCALE)
			f.ZIndex = 41
			f.Parent = root
			table.insert(parts, f)
			table.insert(partRects, { x = p.x, y = p.y, w = p.w, h = p.h })
		end
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 0, -8)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	label.BackgroundColor3 = Theme.Colors.PanelBg
	label.BackgroundTransparency = 0.1
	label.FontFace = Theme.FontBold
	label.TextSize = 14
	label.TextColor3 = Theme.Colors.Text
	label.ZIndex = 42
	label.Parent = root
	local labelPad = Instance.new("UIPadding")
	labelPad.PaddingLeft = UDim.new(0, 6)
	labelPad.PaddingRight = UDim.new(0, 6)
	labelPad.PaddingTop = UDim.new(0, 2)
	labelPad.PaddingBottom = UDim.new(0, 2)
	labelPad.Parent = label
	local labelCorner = Instance.new("UICorner")
	labelCorner.CornerRadius = UDim.new(0, 4)
	labelCorner.Parent = label
	local labelStroke = Instance.new("UIStroke")
	labelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	labelStroke.Parent = label

	-- Круг действия (радар, ПВО, аэродром).
	local ring = Instance.new("Frame")
	ring.Name = "Range"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 0.88
	ring.BorderSizePixel = 0
	ring.ZIndex = 39
	ring.Visible = false
	ring.Parent = canvas
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 2
	ringStroke.Transparency = 0.2
	ringStroke.Parent = ring

	-- §15ы: зона «здесь не строить» вокруг мешающего здания или города (Build.MinGap клеток во все стороны).
	local zone = Instance.new("Frame")
	zone.Name = "Blocker"
	zone.AnchorPoint = Vector2.new(0.5, 0.5)
	zone.BackgroundColor3 = Theme.Colors.Alert
	zone.BackgroundTransparency = 0.8
	zone.BorderSizePixel = 0
	zone.ZIndex = 39
	zone.Visible = false
	zone.Parent = canvas
	local zoneStroke = Instance.new("UIStroke")
	zoneStroke.Color = Theme.Colors.Alert
	zoneStroke.Thickness = 2
	zoneStroke.Parent = zone

	local function cellCenter(cell: number): (number, number)
		local cx, cy = cell % mapWidth, cell // mapWidth
		local left = CameraMath.cellEdge(zoom, cx)
		local top = CameraMath.cellEdge(zoom, cy)
		return left + (CameraMath.cellEdge(zoom, cx + 1) - left) / 2,
			top + (CameraMath.cellEdge(zoom, cy + 1) - top) / 2
	end

	-- §15ч Ч5б: пунктир будущей дороги — кусок через Render.Rail.GhostDash клеток, промежуток такой же.
	local railRoot = Instance.new("Frame")
	railRoot.Name = "GhostRail"
	railRoot.BackgroundTransparency = 1
	railRoot.Size = UDim2.fromScale(1, 1)
	railRoot.ZIndex = 39
	railRoot.Parent = canvas
	type Dash = { frame: Frame, a: number, b: number }
	local dashes: { Dash } = {}
	local railShown: { number }? = nil
	local railCfg = Config.Render.Rail
	local function setRail(path: { number }?)
		if path == railShown then
			return
		end
		railShown = path
		for _, d in dashes do
			d.frame:Destroy()
		end
		table.clear(dashes)
		if path == nil then
			return
		end
		local step = railCfg.GhostDash
		local k = 1
		while k < #path do
			local nextK = math.min(#path, k + step)
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.BorderSizePixel = 0
			f.BackgroundColor3 = Theme.color(railCfg.GhostColor)
			f.ZIndex = 39
			f.Parent = railRoot
			table.insert(dashes, { frame = f, a = path[k], b = path[nextK] })
			k = nextK + step
		end
	end
	local function placeRail()
		for _, d in dashes do
			local ax, ay = (d.a % mapWidth + 0.5) * zoom, (d.a // mapWidth + 0.5) * zoom
			local bx, by = (d.b % mapWidth + 0.5) * zoom, (d.b // mapWidth + 0.5) * zoom
			local dx, dy = bx - ax, by - ay
			d.frame.Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2)
			d.frame.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + railCfg.GhostPx, railCfg.GhostPx)
			d.frame.Rotation = math.deg(math.atan2(dy, dx))
		end
	end

	local function place()
		local v = current
		if v == nil then
			return
		end
		placeRail()
		local x, y = cellCenter(v.cell)
		-- §15ы: как будущий значок — сторона от зума, центр в клетке.
		local px = MapIcons.buildingBase(zoom)
		root.Size = UDim2.fromOffset(px, px)
		root.Position = UDim2.fromOffset(math.round(x - px / 2), math.round(y - px / 2))
		local k = px / size
		for i, r in partRects do
			parts[i].Position = UDim2.fromOffset(math.floor(r.x * k), math.floor(r.y * k))
			parts[i].Size = UDim2.fromOffset(math.ceil(r.w * k), math.ceil(r.h * k))
		end
		local b = v.blocker
		zone.Visible = b ~= nil
		if b ~= nil then
			local bx, by = cellCenter(b)
			local d = (2 * Config.Build.MinGap - 1) * zoom
			zone.Size = UDim2.fromOffset(d, d)
			zone.Position = UDim2.fromOffset(math.round(bx), math.round(by))
		end
		if v.range ~= nil then
			local d = math.max(4, v.range * 2 * zoom)
			ring.Size = UDim2.fromOffset(d, d)
			ring.Position = UDim2.fromOffset(math.round(x), math.round(y))
		end
	end

	local function show(v: GhostView)
		local key = v.kind .. "|" .. tostring(v.ok) .. "|" .. v.color:ToHex()
		if key ~= shown then
			shown = key
			setShape(v.kind, v.color, v.ok)
		end
		current = v
		local tone = if v.ok then Theme.Colors.Good else Theme.Colors.Alert
		plateStroke.Color = tone
		labelStroke.Color = tone
		label.Text = v.label
		label.TextColor3 = if v.ok then Theme.Colors.Text else Theme.Colors.Alert
		ring.Visible = v.range ~= nil
		ring.BackgroundColor3 = tone
		ringStroke.Color = tone
		root.Visible = true
		setRail(v.rail)
		place()
	end

	local function hide()
		current = nil
		root.Visible = false
		ring.Visible = false
		zone.Visible = false
		setRail(nil)
	end

	-- Эффект постройки: вспышка-кольцо, пыль, «−$цена».
	local function built(cell: number, text: string?)
		local x, y = cellCenter(cell)
		local burst = Instance.new("Frame")
		burst.AnchorPoint = Vector2.new(0.5, 0.5)
		burst.Position = UDim2.fromOffset(x, y)
		burst.Size = UDim2.fromOffset(6, 6)
		burst.BackgroundTransparency = 1
		burst.ZIndex = 38
		burst.Parent = canvas
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0.5, 0)
		bc.Parent = burst
		local bs = Instance.new("UIStroke")
		bs.Color = Theme.Colors.Gold
		bs.Thickness = 3
		bs.Parent = burst
		local grow = math.max(36, 10 * zoom)
		TweenService:Create(burst, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(grow, grow),
		}):Play()
		TweenService:Create(bs, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		task.delay(0.55, function()
			burst:Destroy()
		end)
		for k = 1, Config.Build.DustPuffs do
			local a = (k / Config.Build.DustPuffs) * math.pi * 2
			local puff = Instance.new("Frame")
			puff.AnchorPoint = Vector2.new(0.5, 0.5)
			puff.Position = UDim2.fromOffset(x, y)
			puff.Size = UDim2.fromOffset(4, 4)
			puff.BorderSizePixel = 0
			puff.BackgroundColor3 = Theme.Colors.Muted
			puff.BackgroundTransparency = 0.2
			puff.ZIndex = 38
			puff.Parent = canvas
			local r = math.max(14, 4 * zoom) * (0.7 + 0.3 * ((k * 7) % 5) / 4)
			TweenService:Create(puff, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(x + math.cos(a) * r, y + math.sin(a) * r * 0.6),
				Size = UDim2.fromOffset(7, 7),
				BackgroundTransparency = 1,
			}):Play()
			task.delay(0.65, function()
				puff:Destroy()
			end)
		end
		if text ~= nil then
			local t = Instance.new("TextLabel")
			t.AnchorPoint = Vector2.new(0.5, 1)
			t.Position = UDim2.fromOffset(x, y - 10)
			t.Size = UDim2.fromOffset(0, 0)
			t.AutomaticSize = Enum.AutomaticSize.XY
			t.BackgroundTransparency = 1
			t.FontFace = Theme.FontBold
			t.TextSize = 18
			t.TextColor3 = Theme.Colors.Gold
			t.TextStrokeTransparency = 0.3
			t.Text = text
			t.ZIndex = 45
			t.Parent = canvas
			local sec = Config.Build.CostFloatSec
			TweenService:Create(t, TweenInfo.new(sec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(x, y - 46),
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
			task.delay(sec + 0.05, function()
				t:Destroy()
			end)
		end
	end

	return {
		show = show,
		hide = hide,
		built = built,
		onCamera = function(state: CameraState)
			zoom = state.zoom
			place()
		end,
	}
end

return table.freeze(BuildGhost)
