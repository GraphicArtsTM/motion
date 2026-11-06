--!strict
--[[
	BuildGhost — «призрак» стройки на карте (§15г): значок здания под курсором (на телефоне — по первому нажатию),
	зелёная рамка — можно, красная — нельзя; у радара, батареи ПВО и аэродрома — круг действия; над значком —
	цена или причина отказа. Логику (можно ли) решает UI/BuildPanel тем же Buildings.check, что и сервер.

	Плюс эффект постройки: новое здание «вырастает» (UIScale с пружинкой), пыль разлетается, своё — «−$цена».
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildingSprites = require(Shared:WaitForChild("BuildingSprites"))
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local Config = require(Shared:WaitForChild("Config"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type CameraState = CameraMath.CameraState

export type GhostView = {
	kind: string,
	cell: number,
	ok: boolean,
	label: string,
	range: number?,
	color: Color3, -- цвет державы игрока
}

export type BuildGhost = {
	show: (view: GhostView) -> (),
	hide: () -> (),
	onCamera: (state: CameraState) -> (),
	built: (cell: number, label: string?) -> (), -- эффект постройки (label — «−$цена» для своего)
}

local BuildGhost = {}

local GHOST_SCALE = 3 -- значок призрака крупный, чтобы было видно, что ставишь

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
	local shown = ""

	local function setShape(kind: string, color: Color3)
		for _, f in parts do
			f:Destroy()
		end
		table.clear(parts)
		local shape = BuildingSprites.Shapes[kind]
		if shape == nil then
			-- Город: золотой квадрат-«площадь» (у города нет своего значка).
			shape = { { x = 1, y = 1, w = 5, h = 5, ink = false } }
			color = Theme.Colors.Gold
		end
		for _, p in shape do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = if p.ink then Theme.Colors.Backdrop else color
			f.BackgroundTransparency = 0.15
			f.Position = UDim2.fromOffset(p.x * GHOST_SCALE, p.y * GHOST_SCALE)
			f.Size = UDim2.fromOffset(p.w * GHOST_SCALE, p.h * GHOST_SCALE)
			f.ZIndex = 41
			f.Parent = root
			table.insert(parts, f)
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

	local function cellCenter(cell: number): (number, number)
		local cx, cy = cell % mapWidth, cell // mapWidth
		local left = CameraMath.cellEdge(zoom, cx)
		local top = CameraMath.cellEdge(zoom, cy)
		return left + (CameraMath.cellEdge(zoom, cx + 1) - left) / 2,
			top + (CameraMath.cellEdge(zoom, cy + 1) - top) / 2
	end

	local function place()
		local v = current
		if v == nil then
			return
		end
		local x, y = cellCenter(v.cell)
		local px = size * GHOST_SCALE
		root.Position = UDim2.fromOffset(math.round(x - px / 2), math.round(y - px))
		if v.range ~= nil then
			local d = math.max(4, v.range * 2 * zoom)
			ring.Size = UDim2.fromOffset(d, d)
			ring.Position = UDim2.fromOffset(math.round(x), math.round(y))
		end
	end

	local function show(v: GhostView)
		local key = v.kind .. "|" .. tostring(v.ok)
		if key ~= shown then
			shown = key
			setShape(v.kind, v.color)
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
		place()
	end

	local function hide()
		current = nil
		root.Visible = false
		ring.Visible = false
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
