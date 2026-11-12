--!strict
--[[
	StrikeFxLayer — зрелище ударов и разрушения на карте (GDD §15х ч.7). Что показать — чистый StrikeFx.plan,
	здесь — только отрисовка частиц на canvas карты (клетки → пиксели: x · zoom) и запуск по событиям сервера:
	- «Авиаудар» генерала, буст «Авиаудар» — звено штурмовиков и ковёр разрывов (заход со стороны столицы);
	- Арсенал «Артобстрел» и налёт бомбардировщика — ковёр разрывов;
	- ракета, атомная, водородная — обломки, воронки, дым, волны и выжженная земля (огненный шар — WarFxLayer);
	- перехват ракеты — белое кольцо и осколки; налёт сбит — разрывы зениток;
	- задетые здания врага в круге — вторичный взрыв, пожар, дым.
	Видно только то, что в обзоре. Тряска экрана — по силе удара в кадре (shake из BattleFxLayer).
	Частиц не больше Render.StrikeFx.MaxParts (телефон — Render.Phone.MaxStrikeParts); кадры — из пула.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Fog = require(Shared:WaitForChild("Fog"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local PlaneSprites = require(Shared:WaitForChild("PlaneSprites"))
local RenderBudget = require(Shared:WaitForChild("RenderBudget"))
local StrikeFx = require(Shared:WaitForChild("StrikeFx"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type StrikeFxLayer = {
	onEvents: (events: { any }) -> (),
	update: (now: number, state: CameraState) -> (),
	-- §15х ч.9: запустить готовый план частиц (SpectacleFx) от державы owner через delay с; low — фоновые
	-- (кильватер, дождь, заражение): не больше Render.Spectacle.LowShare от предела, чтобы ударам хватало кадров.
	spawn: (parts: { StrikeFx.Part }, owner: number, delay: number, low: boolean) -> (),
}

type Live = {
	part: StrikeFx.Part,
	start: number,
	frame: GuiObject,
	stroke: UIStroke?,
	color: Color3,
	phase: number,
}

local StrikeFxLayer = {}

local ROUND: { [string]: boolean } = {
	flash = true,
	burst = true,
	dust = true,
	smoke = true,
	scar = true,
	scorch = true,
	fire = true,
	ring = true,
	cross = true,
	-- §15х ч.9
	wake = true,
	splash = true,
	glow = true,
	cloud = true,
	slick = true,
	wave = true,
}
-- Кольца (рамка без заливки) и составные частицы (свои кадры, не из пула).
local RING: { [string]: boolean } = { ring = true, cross = true, splash = true, wave = true }
local COMPOSITE: { [string]: boolean } = { jet = true, shadow = true, flag = true, chev = true }

function StrikeFxLayer.new(canvas: Frame, cs: ClientState, shake: (px: number) -> ()): StrikeFxLayer
	local cfg = Config.Render.StrikeFx
	local phone = RenderBudget.isPhone(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)
	local maxParts = if phone then Config.Render.Phone.MaxStrikeParts else cfg.MaxParts
	local w = cs.width
	local lastState: CameraState? = nil
	local seedCounter = 0

	local function colorOf(owner: number): Color3
		local ci = ClientState.colorIndexOf(cs, owner)
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Muted
	end
	local function visible(cell: number): boolean
		return cs.fog.all or Fog.isVisible(cs.fog, cell)
	end
	local function onScreen(x: number, y: number, r: number): boolean
		local state = lastState
		if state == nil then
			return false
		end
		local x0, y0, x1, y1 = CameraMath.visibleRect(state)
		return x >= x0 - r and x <= x1 + r and y >= y0 - r and y <= y1 + r
	end

	-- Пулы: круглые и квадратные кадры (у круглых есть UICorner и UIStroke — для колец).
	local roundPool: { Frame } = {}
	local squarePool: { Frame } = {}
	local function take(isRound: boolean): Frame
		local pool = if isRound then roundPool else squarePool
		local f = table.remove(pool)
		if f == nil then
			local made = Instance.new("Frame")
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.BorderSizePixel = 0
			if isRound then
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0.5, 0)
				c.Parent = made
				local s = Instance.new("UIStroke")
				s.Enabled = false
				s.Parent = made
			end
			made.Parent = canvas
			f = made
		end
		local frame = f :: Frame
		frame.Visible = true
		frame.Rotation = 0
		frame.BackgroundTransparency = 0
		return frame
	end
	local function drop(l: Live)
		local f = l.frame
		if COMPOSITE[l.part.kind] then
			f:Destroy()
			return
		end
		if not f:IsA("Frame") then
			f:Destroy()
			return
		end
		local frame = f :: Frame
		frame.Visible = false
		local s = l.stroke
		if s ~= nil then
			s.Enabled = false
		end
		table.insert(if ROUND[l.part.kind] then roundPool else squarePool, frame)
	end
	-- Самолёт из частей PlaneSprites (нос — вправо): части в долях рамки, рамку поворачиваем целиком.
	local function plane(color: Color3, shadow: boolean): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		local pw, ph = PlaneSprites.Width, PlaneSprites.Height
		for _, p in PlaneSprites.Shapes.Bomber do
			local part = Instance.new("Frame")
			part.BorderSizePixel = 0
			part.Position = UDim2.fromScale(p.x / pw, p.y / ph)
			part.Size = UDim2.fromScale(p.w / pw, p.h / ph)
			part.BackgroundColor3 = if shadow
				then Theme.Colors.Backdrop
				elseif p.ink then Theme.Colors.Backdrop
				else color
			part.BackgroundTransparency = if shadow then 0.55 else 0
			part.ZIndex = if shadow then StrikeFx.Z.shadow else StrikeFx.Z.jet
			part.Parent = f
		end
		f.ZIndex = if shadow then StrikeFx.Z.shadow else StrikeFx.Z.jet
		f.Parent = canvas
		return f
	end

	-- §15х ч.9: флаг над взятым городом — древко и полотнище цвета державы (низ древка — в точке).
	local function flag(color: Color3): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 1)
		f.BackgroundTransparency = 1
		f.ZIndex = StrikeFx.Z.flag
		local pole = Instance.new("Frame")
		pole.Name = "Pole"
		pole.BorderSizePixel = 0
		pole.BackgroundColor3 = Theme.Colors.Backdrop
		pole.Position = UDim2.fromScale(0.1, 0)
		pole.Size = UDim2.fromScale(0.09, 1)
		pole.ZIndex = StrikeFx.Z.flag
		pole.Parent = f
		local cloth = Instance.new("Frame")
		cloth.Name = "Cloth"
		cloth.BorderSizePixel = 0
		cloth.BackgroundColor3 = color
		cloth.Position = UDim2.fromScale(0.19, 0.02)
		cloth.Size = UDim2.fromScale(0.72, 0.46)
		cloth.ZIndex = StrikeFx.Z.flag
		local st = Instance.new("UIStroke")
		st.Color = Theme.Colors.Backdrop
		st.Thickness = 2
		st.Parent = cloth
		cloth.Parent = f
		local knob = Instance.new("Frame")
		knob.Name = "Knob"
		knob.BorderSizePixel = 0
		knob.BackgroundColor3 = Theme.Colors.Gold
		knob.Position = UDim2.fromScale(0.05, -0.06)
		knob.Size = UDim2.fromScale(0.2, 0.08)
		knob.ZIndex = StrikeFx.Z.flag
		knob.Parent = f
		f.Parent = canvas
		return f
	end
	-- Шеврон «>» из двух планок (остриём вправо, поворачиваем рамку).
	local function chevron(color: Color3): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundTransparency = 1
		f.ZIndex = StrikeFx.Z.chev
		for b = 1, 2 do
			local bar = Instance.new("Frame")
			bar.Name = "Bar" .. b
			bar.AnchorPoint = Vector2.new(1, 0.5)
			bar.BorderSizePixel = 0
			bar.BackgroundColor3 = color
			bar.Rotation = if b == 1 then 40 else -40
			bar.Position = UDim2.fromScale(0.85, if b == 1 then 0.32 else 0.68)
			bar.Size = UDim2.fromScale(0.62, 0.22)
			bar.ZIndex = StrikeFx.Z.chev
			local st = Instance.new("UIStroke")
			st.Color = Theme.Colors.Backdrop
			st.Parent = bar
			bar.Parent = f
		end
		f.Parent = canvas
		return f
	end
	local function setChildrenAlpha(f: GuiObject, alpha: number)
		for _, c in f:GetChildren() do
			if c:IsA("Frame") then
				c.BackgroundTransparency = alpha
				local st = c:FindFirstChildOfClass("UIStroke")
				if st ~= nil then
					st.Transparency = alpha
				end
			end
		end
	end

	local pending: { { part: StrikeFx.Part, at: number, owner: number, low: boolean } } = {}
	local live: { Live } = {}
	local shakes: { { at: number, px: number } } = {}

	local function palette(name: string): Color3
		return Theme.color(name)
	end

	local lowLimit = math.floor(maxParts * Config.Render.Spectacle.LowShare)
	local function activate(p: StrikeFx.Part, at: number, owner: number, low: boolean)
		if #live >= maxParts or (low and #live >= lowLimit) then
			return -- предел частиц: лишнее не рисуем
		end
		local frame: GuiObject
		local stroke: UIStroke? = nil
		local color = if p.color == "nation" then colorOf(owner) else palette(p.color)
		if p.kind == "jet" or p.kind == "shadow" then
			frame = plane(color, p.kind == "shadow")
		elseif p.kind == "flag" then
			frame = flag(color)
		elseif p.kind == "chev" then
			frame = chevron(color)
		else
			local f = take(ROUND[p.kind] == true)
			f.ZIndex = p.z
			f.BackgroundColor3 = color
			if RING[p.kind] then
				f.BackgroundTransparency = 1
				local s = f:FindFirstChildOfClass("UIStroke")
				if s ~= nil then
					s.Enabled = true
					s.Color = color
					s.Thickness = if p.kind == "cross" or p.kind == "splash" then 2 else 3
					s.Transparency = 0
					stroke = s
				end
			end
			frame = f
		end
		table.insert(
			live,
			{ part = p, start = at, frame = frame, stroke = stroke, color = color, phase = math.random() * 6.283 }
		)
	end

	-- Запустить план удара kind в клетке cell от державы owner.
	local function play(
		kind: StrikeFx.Kind,
		cell: number,
		radius: number,
		owner: number,
		delay: number,
		withBuildings: boolean
	)
		if not visible(cell) then
			return
		end
		local x, y = cell % w + 0.5, cell // w + 0.5
		-- Заход — со стороны столицы державы удара.
		local dirX, dirY = 1, 0
		local n = cs.nations[owner]
		local cap = if n ~= nil then n.capital else nil
		if cap ~= nil then
			dirX, dirY = x - (cap % w + 0.5), y - (cap // w + 0.5)
		end
		local hit: { StrikeFx.Point } = {}
		if withBuildings then
			local cells: { number } = {}
			for c in cs.buildings do
				local o = ClientState.ownerAt(cs, c)
				if o ~= owner and visible(c) then
					table.insert(cells, c)
				end
			end
			hit = StrikeFx.buildingsIn(cells, w, x, y, radius)
		end
		seedCounter += 1
		local parts = StrikeFx.plan(kind, x, y, {
			radius = radius,
			seed = cell * 31 + seedCounter,
			dirX = dirX,
			dirY = dirY,
			buildings = hit,
		})
		local now = os.clock()
		local firstBoom = math.huge
		for _, p in parts do
			table.insert(pending, { part = p, at = now + delay + p.t, owner = owner, low = false })
			if p.kind == "burst" or p.kind == "ring" or p.kind == "debris" then
				firstBoom = math.min(firstBoom, p.t)
			end
		end
		local px = (cfg.ShakePx :: any)[kind]
		if type(px) == "number" and onScreen(x, y, radius) then
			table.insert(shakes, { at = now + delay + (if firstBoom < math.huge then firstBoom else 0), px = px })
		end
	end

	local function onEvents(events: { any })
		for _, e in events do
			if type(e) ~= "table" then
				continue
			end
			local owner = tonumber(e.nation) or 0
			local cell = e.cell
			if type(cell) ~= "number" then
				continue
			end
			if (e.kind == "ability" and e.ability == "Airstrike") or (e.kind == "boost" and e.boost == "Airstrike") then
				play("airstrike", cell, Config.Commanders.StrikeRadius, owner, 0, false)
			elseif e.kind == "arsenal" and e.item == "Barrage" then
				play("raid", cell, Config.Commanders.StrikeRadius, owner, 0, false) -- артиллерия: ковёр без самолётов
			elseif e.kind == "raid" then
				play("raid", cell, Config.Air.BombRadius, owner, 0, true)
			elseif e.kind == "raidIntercepted" then
				play("flak", cell, Config.Air.BombRadius, owner, 0, false)
			elseif e.kind == "missileHit" then
				play("missile", cell, tonumber(e.radius) or Config.Buildings.MissileSilo.strikeRadius, owner, 0, true)
			elseif e.kind == "nukeHit" then
				local kind: StrikeFx.Kind = if e.warhead == "hydrogen" then "hydrogen" else "atom"
				play(kind, cell, tonumber(e.radius) or 10, owner, 0, true)
			elseif e.kind == "missileShot" then
				-- Перехватчик летит Render.WarFx.InterceptSec (WarFxLayer) — кольцо в конце его пути.
				play("intercept", cell, 2, owner, Config.Render.WarFx.InterceptSec, false)
			end
		end
	end

	local function update(now: number, state: CameraState)
		lastState = state
		local zoom = state.zoom
		-- Запуск отложенных частиц.
		local k = 1
		while k <= #pending do
			local q = pending[k]
			if now >= q.at then
				activate(q.part, q.at, q.owner, q.low)
				pending[k] = pending[#pending]
				pending[#pending] = nil
			else
				k += 1
			end
		end
		local s = 1
		while s <= #shakes do
			if now >= shakes[s].at then
				shake(shakes[s].px)
				shakes[s] = shakes[#shakes]
				shakes[#shakes] = nil
			else
				s += 1
			end
		end
		-- Живые частицы.
		local i = 1
		while i <= #live do
			local l = live[i]
			local p = l.part
			local t = (now - l.start) / p.life
			if t >= 1 then
				drop(l)
				live[i] = live[#live]
				live[#live] = nil
				continue
			end
			local e = StrikeFx.ease(p.kind, t)
			local x, y = p.x + p.dx * e, p.y + p.dy * e
			local size = p.s0 + (p.s1 - p.s0) * e
			local f = l.frame
			local flicker = 0.5 + 0.5 * math.sin(now * 14 + l.phase)
			local alpha = 0 -- прозрачность фона
			local kind = p.kind
			if kind == "flash" then
				alpha = 0.1 + 0.9 * t
			elseif kind == "burst" then
				alpha = t ^ 1.5
				local hot, fire, deep = Theme.Colors.Gold, Theme.color("Orange"), Theme.Colors.Alert
				f.BackgroundColor3 = if t < 0.5 then hot:Lerp(fire, t * 2) else fire:Lerp(deep, (t - 0.5) * 2)
			elseif kind == "dust" then
				alpha = 0.45 + 0.55 * t
			elseif kind == "smoke" then
				alpha = 0.35 + 0.65 * t
				f.BackgroundColor3 = l.color:Lerp(Theme.Colors.Muted, t)
			elseif kind == "scar" then
				alpha = if t < 0.75 then 0.3 else 0.3 + 0.7 * (t - 0.75) / 0.25
			elseif kind == "scorch" then
				alpha = if t < 0.6 then 0.72 else 0.72 + 0.28 * (t - 0.6) / 0.4
			elseif kind == "fire" then
				size *= 0.85 + 0.3 * flicker
				f.BackgroundColor3 = l.color:Lerp(Theme.Colors.Gold, flicker)
				alpha = 0.05 + 0.25 * (1 - flicker) + (if t > 0.85 then (t - 0.85) / 0.15 else 0)
			elseif kind == "ember" then
				alpha = 0.25 + 0.6 * (1 - flicker) + (if t > 0.7 then (t - 0.7) / 0.3 * 0.15 else 0)
				f.BackgroundColor3 = l.color:Lerp(Theme.Colors.Alert, flicker)
			elseif kind == "debris" then
				alpha = t * t
				f.Rotation = p.rot + 360 * t
			elseif RING[kind] then
				local st = l.stroke
				if st ~= nil then
					st.Transparency = if kind == "cross" then t * t else t
				end
				alpha = 1
			elseif kind == "jet" or kind == "shadow" then
				f.Rotation = p.rot
			-- §15х ч.9
			elseif kind == "wake" then
				alpha = 0.35 + 0.65 * t
			elseif kind == "tracer" then
				alpha = 0
			elseif kind == "glow" then
				alpha = 1 - 0.8 * math.sin(math.pi * t)
			elseif kind == "rain" then
				alpha = 0.35 + 0.5 * t
				f.Rotation = p.rot
			elseif kind == "cloud" then
				alpha = 1 - 0.5 * math.sin(math.pi * t)
			elseif kind == "spark" then
				alpha = t
			elseif kind == "slick" then
				alpha = if t < 0.7 then 0.45 else 0.45 + 0.55 * (t - 0.7) / 0.3
			elseif kind == "flag" then
				setChildrenAlpha(f, if t > 0.8 then (t - 0.8) / 0.2 else 0)
			elseif kind == "chev" then
				f.Rotation = p.rot
				setChildrenAlpha(f, t * t)
			end
			f.Position = UDim2.fromOffset(x * zoom, y * zoom)
			if kind == "jet" or kind == "shadow" then
				local px = math.max(cfg.JetMinPx, size * zoom)
				f.Size = UDim2.fromOffset(px, px * PlaneSprites.Height / PlaneSprites.Width)
			elseif kind == "flag" then
				local px = math.max(cfg.JetMinPx, size * zoom)
				f.Size = UDim2.fromOffset(px, px)
			elseif kind == "chev" then
				local px = math.max(14, size * zoom)
				f.Size = UDim2.fromOffset(px, px)
			elseif kind == "rain" then
				f.Size = UDim2.fromOffset(math.max(1, 0.25 * zoom), math.max(5, 1.5 * zoom))
				f.BackgroundTransparency = math.clamp(alpha, 0, 1)
			else
				local small = kind == "burst" or kind == "flash" or kind == "fire"
				local px = math.max(if small then cfg.BurstMinPx else 2, size * zoom)
				f.Size = UDim2.fromOffset(px, px)
				f.BackgroundTransparency = math.clamp(alpha, 0, 1)
			end
			i += 1
		end
	end

	return {
		onEvents = onEvents,
		update = update,
		spawn = function(parts: { StrikeFx.Part }, owner: number, delay: number, low: boolean)
			local now = os.clock()
			for _, p in parts do
				table.insert(pending, { part = p, at = now + delay + p.t, owner = owner, low = low })
			end
		end,
	}
end

return table.freeze(StrikeFxLayer)
