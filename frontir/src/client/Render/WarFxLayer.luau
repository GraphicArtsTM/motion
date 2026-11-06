--!strict
--[[
	WarFxLayer — зрелищная война (GDD §15б). Расчёты — Shared.WarFx, числа — Config.Render.WarFx.
	- Объявление войны (warDeclared): баннер «ВОЙНА» с цветами держав по центру экрана (крупный — если война касается
	  вас или союзника), красные искры на общей границе; война против вас — красная виньетка по краям экрана.
	- Начало боёв (warStarted): баннер «НАСТУПЛЕНИЕ», искры цветом нападающего; «Первый удар» — стрелки ярче.
	- Стрелки наступления: шевроны цвета нападающего на видимых фронтах против держав бегут к врагу; побеждающий
	  фронт — быстрее и ярче.
	- Вспышки захвата: клетки, отнятые у другой державы, коротко вспыхивают (пул ограничен).
	Всё на canvas карты (клетки → пиксели — CameraMath.cellEdge) и в своём ScreenGui (баннер, виньетка).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Fog = require(Shared:WaitForChild("Fog"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local RenderBudget = require(Shared:WaitForChild("RenderBudget"))
local Strings = require(Shared:WaitForChild("Strings"))
local WarFx = require(Shared:WaitForChild("WarFx"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type WarFxLayer = {
	onEvents: (events: { any }) -> (),
	onSnapshot: () -> (), -- вся сетка пришла заново: запомнить владельцев
	onDelta: (cells: { number }) -> (), -- клетки сменили владельца
	update: (now: number, state: CameraState) -> (),
}

type Spark = { frame: Frame, cell: number, phase: number }
type Flash = { frame: Frame, cell: number, born: number }
type Chevron = { root: Frame, bars: { Frame } }
type ArrowView = { x: number, y: number, dx: number, dy: number, color: Color3, strength: number, fast: boolean }

local WarFxLayer = {}

function WarFxLayer.new(canvas: Frame, screen: ScreenGui, cs: ClientState, lang: Strings.Lang): WarFxLayer
	local cfg = Config.Render.WarFx
	local phone = RenderBudget.isPhone(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)
	local function limit(name: string): number
		local p = (Config.Render.Phone :: any)[name]
		return if phone and p ~= nil then p else (cfg :: any)[name]
	end
	local maxSparks, maxArrows, maxFlashes = limit("BorderSparks"), limit("MaxArrows"), limit("MaxCaptureFlashes")
	local w, h = cs.width, cs.height
	local memory = WarFx.newMemory(w * h)
	local lastState: CameraState? = nil

	local function ownerAt(i: number): number
		return ClientState.ownerAt(cs, i)
	end
	local function colorOf(owner: number): Color3
		local ci = ClientState.colorIndexOf(cs, owner)
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Muted
	end
	local function nameOf(id: number): string
		local n = cs.nations[id]
		return if n ~= nil then n.name else "?"
	end
	local function visible(cell: number): boolean
		return cs.fog.all or Fog.isVisible(cs.fog, cell)
	end

	-- Пул квадратов на карте.
	local pool: { Frame } = {}
	local function take(z: number): Frame
		local f = table.remove(pool)
		if f == nil then
			local made = Instance.new("Frame")
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.BorderSizePixel = 0
			made.Parent = canvas
			f = made
		end
		local frame = f :: Frame
		frame.ZIndex = z
		frame.Rotation = 0
		frame.Visible = true
		return frame
	end
	local function drop(f: Frame)
		f.Visible = false
		table.insert(pool, f)
	end

	-- Баннер (экран).
	local banner = Instance.new("Frame")
	banner.Name = "WarBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.28)
	banner.BackgroundColor3 = Theme.Colors.PanelBg
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.ZIndex = 50
	banner.Parent = screen
	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Thickness = 3
	bannerStroke.Parent = banner
	local leftBar, rightBar = Instance.new("Frame"), Instance.new("Frame")
	for k, bar in { leftBar, rightBar } do
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(if k == 1 then 0 else 1, 0)
		bar.Position = UDim2.fromScale(if k == 1 then 0 else 1, 0)
		bar.Size = UDim2.new(0, 14, 1, 0)
		bar.ZIndex = 51
		bar.Parent = banner
	end
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.FontFace = Theme.FontBold
	title.TextColor3 = Theme.Colors.Text
	title.TextStrokeTransparency = 0.4
	title.Size = UDim2.new(1, -36, 0.6, 0)
	title.Position = UDim2.fromOffset(18, 4)
	title.ZIndex = 52
	title.Parent = banner
	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.FontFace = Theme.Font
	subtitle.TextColor3 = Theme.Colors.Text
	subtitle.Size = UDim2.new(1, -36, 0.4, -6)
	subtitle.Position = UDim2.new(0, 18, 0.6, 0)
	subtitle.ZIndex = 52
	subtitle.Parent = banner
	local bannerFrom, bannerUntil, bannerBig = 0, 0, false

	local function showBanner(key: string, a: number, b: number, big: boolean, accent: Color3)
		local now = os.clock()
		-- Крупный баннер не перебивается малым.
		if not big and bannerBig and now < bannerUntil then
			return
		end
		bannerBig = big
		bannerFrom = now
		bannerUntil = now + (if big then cfg.BannerSec else cfg.BannerSmallSec)
		banner.Size = if big then UDim2.fromOffset(420, 84) else UDim2.fromOffset(300, 56)
		title.TextSize = if big then 34 else 22
		subtitle.TextSize = if big then 16 else 13
		title.Text = Strings.get(key, lang)
		subtitle.Text = string.format(Strings.get("warfx.vs", lang), nameOf(a), nameOf(b))
		leftBar.BackgroundColor3 = colorOf(a)
		rightBar.BackgroundColor3 = colorOf(b)
		bannerStroke.Color = accent
		banner.Visible = true
	end

	-- Виньетка (экран): четыре края с градиентом прозрачности.
	local edges: { Frame } = {}
	for k = 1, 4 do
		local e = Instance.new("Frame")
		e.BorderSizePixel = 0
		e.BackgroundColor3 = Theme.Colors.Alert
		e.ZIndex = 45
		e.Visible = false
		local horizontal = k <= 2
		e.Size = if horizontal then UDim2.fromScale(1, 0.18) else UDim2.fromScale(0.12, 1)
		e.AnchorPoint = Vector2.new(if k == 4 then 1 else 0, if k == 2 then 1 else 0)
		e.Position = UDim2.fromScale(if k == 4 then 1 else 0, if k == 2 then 1 else 0)
		local g = Instance.new("UIGradient")
		g.Rotation = ({ 90, 270, 0, 180 })[k]
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = e
		e.Parent = screen
		table.insert(edges, e)
	end
	local vignetteUntil = 0

	-- Искры на общей границе.
	local sparks: { Spark } = {}
	local sparksUntil = 0
	local sparkColor = Theme.Colors.Alert
	local function borderFlash(a: number, b: number, color: Color3)
		for _, s in sparks do
			drop(s.frame)
		end
		table.clear(sparks)
		local half = math.max(1, maxSparks // 2)
		local cells = WarFx.borderSamples(ownerAt, w, h, a, b, 0, 0, w - 1, h - 1, cfg.BorderStride, half)
		for _, c in WarFx.borderSamples(ownerAt, w, h, b, a, 0, 0, w - 1, h - 1, cfg.BorderStride, half) do
			table.insert(cells, c)
		end
		for k, c in cells do
			if visible(c) then
				local f = take(11)
				f.BackgroundColor3 = color
				table.insert(sparks, { frame = f, cell = c, phase = (k * 0.37) % 1 })
			end
		end
		sparkColor = color
		sparksUntil = os.clock() + cfg.BorderFlashSec
	end

	-- Вспышки захвата.
	local flashes: { Flash } = {}
	local white = Theme.color("White")

	-- Стрелки наступления: шевроны (корень повёрнут, внутри две планки «>»).
	local chevrons: { Chevron } = {}
	local function chevron(k: number): Chevron
		local c = chevrons[k]
		if c ~= nil then
			return c
		end
		local root = Instance.new("Frame")
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.BackgroundTransparency = 1
		root.ZIndex = 8
		root.Parent = canvas
		local bars: { Frame } = {}
		for _ = 1, 2 do
			local bar = Instance.new("Frame")
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.BorderSizePixel = 0
			bar.ZIndex = 8
			bar.Parent = root
			table.insert(bars, bar)
		end
		local made: Chevron = { root = root, bars = bars }
		chevrons[k] = made
		return made
	end
	local arrows: { ArrowView } = {}
	local lastScan = -math.huge
	local opening: { [number]: number } = {} -- нападающий * 65536 + цель → до когда «Первый удар» (os.clock)

	local function scanArrows(state: CameraState)
		table.clear(arrows)
		local stats = cs.stats
		if stats == nil or cs.phase ~= "Play" then
			return
		end
		local x0, y0, x1, y1 = CameraMath.visibleRect(state)
		local now = os.clock()
		for _, a in stats.attacks do
			if a.target ~= 0 and #arrows < maxArrows then
				local list = WarFx.frontArrows(
					ownerAt,
					w,
					h,
					a.attacker,
					a.target,
					x0 - 2,
					y0 - 2,
					x1 + 2,
					y1 + 2,
					cfg.ArrowStride,
					cfg.MaxArrowsPerFront,
					cfg.ArrowMinCells
				)
				local isOpening = (opening[a.attacker * 65536 + a.target] or 0) > now
				local strength = WarFx.arrowStrength(a.ratio, Config.Combat.FullSpeedRatio, isOpening)
				for _, ar in list do
					local cell = math.floor(ar.y) * w + math.floor(ar.x)
					if #arrows < maxArrows and visible(cell) then
						table.insert(arrows, {
							x = ar.x,
							y = ar.y,
							dx = ar.dx,
							dy = ar.dy,
							color = colorOf(a.attacker),
							strength = strength,
							fast = isOpening or a.ratio >= Config.Combat.FullSpeedRatio,
						})
					end
				end
			end
		end
	end

	local function onEvents(events: { any })
		local me = cs.myNation
		local friends: { [number]: boolean } = if me ~= nil then ClientState.friendsOf(cs, me) else {}
		if me ~= nil then
			friends[me] = true
		end
		local now = os.clock()
		for _, e in events do
			if type(e) ~= "table" or type(e.nation) ~= "number" or type(e.target) ~= "number" then
				continue
			end
			local a, b = e.nation :: number, e.target :: number
			local big = friends[a] == true or friends[b] == true
			if e.kind == "warDeclared" then
				showBanner("warfx.war", a, b, big, Theme.Colors.Alert)
				borderFlash(a, b, Theme.Colors.Alert)
				if me ~= nil and b == me then
					vignetteUntil = now + cfg.VignetteSec
				end
			elseif e.kind == "warStarted" then
				showBanner("warfx.offensive", a, b, big, colorOf(a))
				borderFlash(a, b, colorOf(a))
				local rate = math.max(ClientState.simRate(cs), 1e-3)
				opening[a * 65536 + b] = now + Config.Combat.OpeningSec / rate
				lastScan = -math.huge -- стрелки — сразу
			end
		end
	end

	local function onSnapshot()
		WarFx.remember(memory, ownerAt)
	end

	local function onDelta(cells: { number })
		local taken = WarFx.captures(memory, cells, ownerAt)
		local state = lastState
		if #taken == 0 or state == nil then
			return
		end
		local x0, y0, x1, y1 = CameraMath.visibleRect(state)
		local now = os.clock()
		local made = 0
		local step = math.max(1, #taken // cfg.CaptureFlashPerDelta)
		for k = 1, #taken, step do
			local c = taken[k]
			local cx, cy = c % w, c // w
			if #flashes >= maxFlashes or made >= cfg.CaptureFlashPerDelta then
				break
			end
			if cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1 and visible(c) then
				local f = take(10)
				f.BackgroundColor3 = white
				table.insert(flashes, { frame = f, cell = c, born = now })
				made += 1
			end
		end
	end

	local function place(f: Frame, zoom: number, cell: number, scale: number)
		local cx, cy = cell % w, cell // w
		local px = (CameraMath.cellEdge(zoom, cx) + CameraMath.cellEdge(zoom, cx + 1)) / 2
		local py = (CameraMath.cellEdge(zoom, cy) + CameraMath.cellEdge(zoom, cy + 1)) / 2
		local size = math.max(2, zoom * scale)
		f.Position = UDim2.fromOffset(px, py)
		f.Size = UDim2.fromOffset(size, size)
	end

	local function update(now: number, state: CameraState)
		lastState = state
		local zoom = state.zoom
		-- Баннер: появляется и тает.
		if banner.Visible then
			if now >= bannerUntil then
				banner.Visible = false
				bannerBig = false
			else
				local fade = cfg.BannerFadeSec
				local t = math.min((now - bannerFrom) / fade, (bannerUntil - now) / fade, 1)
				banner.BackgroundTransparency = 1 - 0.9 * t
				title.TextTransparency = 1 - t
				subtitle.TextTransparency = 1 - t
				leftBar.BackgroundTransparency = 1 - t
				rightBar.BackgroundTransparency = 1 - t
				bannerStroke.Transparency = 1 - t
				-- Крупный баннер въезжает сверху и чуть увеличивается.
				local slide = (1 - t) * 24
				banner.Position = UDim2.new(0.5, 0, 0.28, -slide)
			end
		end
		-- Виньетка: три пульса.
		local vLeft = vignetteUntil - now
		for _, e in edges do
			e.Visible = vLeft > 0
			if vLeft > 0 then
				local pulse = 0.5 + 0.5 * math.cos((cfg.VignetteSec - vLeft) / cfg.VignetteSec * math.pi * 6)
				e.BackgroundTransparency = 0.35 + 0.5 * (1 - pulse * (vLeft / cfg.VignetteSec))
			end
		end
		-- Искры на границе: мигают, к концу гаснут.
		if #sparks > 0 then
			local left = sparksUntil - now
			if left <= 0 then
				for _, s in sparks do
					drop(s.frame)
				end
				table.clear(sparks)
			else
				local life = left / cfg.BorderFlashSec
				for _, s in sparks do
					local blink = 0.5 + 0.5 * math.sin((now * 6 + s.phase * 6.283))
					s.frame.BackgroundColor3 = sparkColor:Lerp(white, blink * 0.5)
					s.frame.BackgroundTransparency = 1 - life * (0.4 + 0.6 * blink)
					place(s.frame, zoom, s.cell, 1 + blink)
				end
			end
		end
		-- Вспышки захвата.
		local k = 1
		while k <= #flashes do
			local f = flashes[k]
			local t = (now - f.born) / cfg.CaptureFlashSec
			if t >= 1 then
				drop(f.frame)
				flashes[k] = flashes[#flashes]
				flashes[#flashes] = nil
			else
				f.frame.BackgroundTransparency = 0.15 + 0.85 * t
				place(f.frame, zoom, f.cell, 1 + 0.8 * t)
				k += 1
			end
		end
		-- Стрелки наступления.
		if now - lastScan >= cfg.ArrowScanSec then
			lastScan = now
			scanArrows(state)
		end
		local per = cfg.ArrowChevrons
		local used = 0
		local length = math.max(cfg.ArrowMinPx, cfg.ArrowLengthCells * zoom)
		local size = math.max(8, length / per * 1.1)
		for _, ar in arrows do
			local angle = math.deg(math.atan2(ar.dy, ar.dx))
			local cycle = cfg.ArrowCycleSec / (if ar.fast then 2 else 1)
			local base = (now / cycle) % 1
			local px, py = ar.x * zoom, ar.y * zoom
			for j = 0, per - 1 do
				used += 1
				local c = chevron(used)
				local s = (base + j / per) % 1 -- 0 — у своей земли, 1 — у врага
				local along = (s - 0.35) * length
				c.root.Visible = true
				c.root.Position = UDim2.fromOffset(px + ar.dx * along, py + ar.dy * along)
				c.root.Size = UDim2.fromOffset(size, size)
				c.root.Rotation = angle
				-- «>» острием вперёд: две планки от острия назад-вверх и назад-вниз.
				local barLen, thick = size * 0.62, math.max(3, size * 0.25)
				local back = barLen / 2 * 0.7071
				local alpha = 1 - ar.strength * math.sin(s * math.pi)
				for b, bar in c.bars do
					bar.BackgroundColor3 = ar.color
					bar.BackgroundTransparency = alpha
					bar.Size = UDim2.fromOffset(barLen, thick)
					bar.Position = UDim2.new(0.75, -back, 0.5, if b == 1 then -back else back)
					bar.Rotation = if b == 1 then 45 else -45
				end
			end
		end
		for j = used + 1, #chevrons do
			chevrons[j].root.Visible = false
		end
	end

	return { onEvents = onEvents, onSnapshot = onSnapshot, onDelta = onDelta, update = update }
end

return table.freeze(WarFxLayer)
