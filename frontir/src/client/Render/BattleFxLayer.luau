--!strict
--[[
	BattleFxLayer — живой фронт и зрелищный матч (GDD §15м, часть 2). Числа — Config.Render.BattleFx / Shake,
	полосы перевеса и тряска — чистые WarFx.ratioBand / WarFx.shake.
	- Плашка перевеса над фронтами, которые касаются игрока: «×2.4», цвет полосы (стоит — красный, ползёт —
	  оранжевый, полная скорость — зелёный, прорыв — золотой); число и место плавно догоняют новые значения;
	  фронт против вас — со знаком ⚠ и красной рамкой.
	- Прогноз фронта под числом (§15н, FrontForecast): состояние и тренд, главная причина торможения, сколько
	  войск нужно, на сколько хватит войск, совет «Лучше отступить». На телефоне — без строки чисел.
	- Свой фронт перешёл в прорыв — всплывает «ПРОРЫВ!» (стрелки золотые — WarFxLayer).
	- Захват города: ударное кольцо цветом захватчика, «+ Город» (взяли вы) / «− Город» (потеряли вы).
	- Выбывание державы: баннер «X выбывает» и салют цветом победителя над её столицей.
	- «Сверхдержава»: корона над столицей огромной державы; если это вы — плашка с бонусом (GiantChip, справа сверху).
	- Тряска экрана: ядерный взрыв в кадре, потеря своей столицы (на телефоне — слабее).
	Всё на холсте карты (клетка → пиксели: x · zoom) и в HUD; пулы ограничены, на телефоне — меньше.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local CitySprites = require(Shared:WaitForChild("CitySprites"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Fog = require(Shared:WaitForChild("Fog"))
local FrontForecast = require(Shared:WaitForChild("FrontForecast"))
local Fronts = require(Shared:WaitForChild("Fronts"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local RenderBudget = require(Shared:WaitForChild("RenderBudget"))
local Strings = require(Shared:WaitForChild("Strings"))
local WarFx = require(Shared:WaitForChild("WarFx"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type BattleFxLayer = {
	onEvents: (events: { any }) -> (),
	onSnapshot: () -> (),
	onDelta: (cells: { number }) -> (),
	update: (now: number, state: CameraState) -> (),
	giantChip: Frame, -- плашка «Сверхдержава» (Main ставит её в столбик справа сверху)
}

type Badge = {
	key: number,
	frame: Frame,
	stroke: UIStroke,
	label: TextLabel,
	status: TextLabel, -- §15н: «Медленно ↑ · река»
	detail: TextLabel, -- «+1.2K до ×2 · войск на ~40 с»
	advice: TextLabel, -- «Лучше отступить»
	history: { { t: number, r: number } }, -- перевес по времени — для тренда
	x: number,
	y: number,
	tx: number,
	ty: number,
	shown: number,
	ratio: number,
	againstMe: boolean,
	seen: number,
	band: WarFx.RatioBand?,
}
type Ring = { frame: Frame, stroke: UIStroke, x: number, y: number, born: number }
type Floater = { label: TextLabel, x: number, y: number, born: number, life: number, rise: number }
type Spark = { frame: Frame, x: number, y: number, vx: number, vy: number, born: number }
type Crown = { root: Frame, owner: number }

local BattleFxLayer = {}

-- Корона 7×5: «#» — золото, «r» — камень.
local CROWN = { "#.#.#.#", "#######", "##r#r##", "#######", "#######" }

function BattleFxLayer.new(
	canvas: Frame,
	viewport: GuiObject,
	hud: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	map: MapDataModule.MapData
): BattleFxLayer
	local cfg = Config.Render.BattleFx
	local phone = RenderBudget.isPhone(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)
	local function limit(name: string): number
		local p = (Config.Render.Phone :: any)[name]
		return if phone and p ~= nil then p else (cfg :: any)[name]
	end
	local maxBadges, maxRings, fireworkSparks = limit("MaxBadges"), limit("MaxRings"), limit("FireworkSparks")
	local w, h = cs.width, cs.height
	local lastState: CameraState? = nil
	local lastNow = os.clock()

	-- Вся захватываемая суша карты — для доли «Сверхдержавы» (как Grid.capturableCount на сервере).
	local land = 0
	for i = 0, w * h - 1 do
		local stats = Config.Terrain[MapDataModule.getTerrain(map, i)]
		if stats ~= nil and stats.borderPassable then
			land += 1
		end
	end

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
		if n == nil then
			return "?"
		end
		return if lang == "en" then n.nameEn else n.name
	end
	local function visible(cell: number): boolean
		return cs.fog.all or Fog.isVisible(cs.fog, cell)
	end
	local bandColor: { [string]: Color3 } = {
		stall = Theme.Colors.Alert,
		crawl = Theme.color("Orange"),
		full = Theme.color("Lime"),
		breakthrough = Theme.Colors.Gold,
	}

	local function textOn(parent: Instance, size: number, z: number): TextLabel
		local l = Instance.new("TextLabel")
		l.AnchorPoint = Vector2.new(0.5, 1)
		l.BackgroundTransparency = 1
		l.FontFace = Theme.FontBold
		l.TextSize = size
		l.TextStrokeColor3 = Theme.Colors.Backdrop
		l.TextStrokeTransparency = 0.2
		l.Size = UDim2.fromOffset(0, size + 4)
		l.AutomaticSize = Enum.AutomaticSize.X
		l.ZIndex = z
		l.Parent = parent
		return l
	end

	-- Всплывающая надпись на карте (клетки x, y): поднимается и тает.
	local floaters: { Floater } = {}
	local function float(x: number, y: number, text: string, color: Color3, size: number, life: number)
		local l = textOn(canvas, size, 18)
		l.Text = text
		l.TextColor3 = color
		table.insert(floaters, { label = l, x = x, y = y, born = os.clock(), life = life, rise = 22 })
	end

	-- 1. Плашки перевеса.
	local badges: { [number]: Badge } = {}
	local badgeCount = 0
	local lastScan = -math.huge
	local function makeBadge(key: number, x: number, y: number, ratio: number, againstMe: boolean): Badge
		local f = Instance.new("Frame")
		f.Name = "RatioBadge"
		f.AnchorPoint = Vector2.new(0.5, 1)
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BackgroundTransparency = 0.15
		f.BorderSizePixel = 0
		f.Size = UDim2.fromOffset(0, 0)
		f.AutomaticSize = Enum.AutomaticSize.XY
		f.ZIndex = 17
		f.Parent = canvas
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = f
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingRight = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 2)
		pad.Parent = f
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = f
		local function line(order: number, size: number, bold: boolean, color: Color3): TextLabel
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.FontFace = if bold then Theme.FontBold else Theme.Font
			t.TextSize = size
			t.TextColor3 = color
			t.Size = UDim2.fromOffset(0, size + 4)
			t.AutomaticSize = Enum.AutomaticSize.X
			t.LayoutOrder = order
			t.ZIndex = 18
			t.Visible = order == 1
			t.Parent = f
			return t
		end
		local l = line(1, 15, true, Theme.Colors.Text)
		local fc = Config.Forecast
		local status = line(2, fc.StatusTextPx, true, Theme.Colors.Text)
		local detail = line(3, fc.DetailTextPx, false, Theme.Colors.Muted)
		local advice = line(4, fc.DetailTextPx, true, Theme.Colors.Alert)
		badgeCount += 1
		return {
			key = key,
			frame = f,
			stroke = stroke,
			label = l,
			status = status,
			detail = detail,
			advice = advice,
			history = {},
			x = x,
			y = y,
			tx = x,
			ty = y,
			shown = math.min(ratio, cfg.BadgeMaxShown),
			ratio = ratio,
			againstMe = againstMe,
			seen = os.clock(),
			band = nil,
		}
	end
	local function dropBadge(key: number)
		local b = badges[key]
		if b ~= nil then
			b.frame:Destroy()
			badges[key] = nil
			badgeCount -= 1
		end
	end

	-- Прогноз фронта (§15н): тренд по истории перевеса, остальное — от сервера (только сторонам фронта).
	local function forecast(b: Badge, a: any, now: number)
		local fc = Config.Forecast
		local hist = b.history
		if #hist == 0 or now - hist[#hist].t >= fc.HistoryStepSec then
			table.insert(hist, { t = now, r = a.ratio })
		end
		while #hist > 1 and hist[2].t <= now - fc.TrendSec do
			table.remove(hist, 1)
		end
		local old = if hist[1].t <= now - fc.TrendSec + fc.HistoryStepSec then hist[1].r else nil
		local lasts = if b.againstMe then nil else FrontForecast.lastsSec(a.power, a.burn or 0, ClientState.simRate(cs))
		local lines = FrontForecast.lines({
			ratio = a.ratio,
			fighting = a.fighting,
			againstMe = b.againstMe,
			why = a.why or 0,
			need = a.need or 0,
			lasts = lasts,
			trend = FrontForecast.trend(old, a.ratio),
		}, lang)
		b.status.Text = lines.status
		b.status.Visible = true
		local detail = lines.detail
		b.detail.Text = detail or ""
		b.detail.Visible = detail ~= nil and not phone
		local advice = lines.advice
		b.advice.Text = advice or ""
		b.advice.Visible = advice ~= nil
	end

	local function scanBadges(state: CameraState)
		local stats = cs.stats
		local me = cs.myNation
		local now = os.clock()
		if stats ~= nil and me ~= nil and cs.phase == "Play" then
			local x0, y0, x1, y1 = CameraMath.visibleRect(state)
			-- Встречные фронты пары — одна плашка: своя атака важнее вражеской на той же границе.
			local mine: { [number]: boolean } = {}
			for _, a in stats.attacks do
				if a.attacker == me and a.target ~= 0 then
					mine[a.target] = true
				end
			end
			for _, a in stats.attacks do
				local counter = a.target == me and mine[a.attacker] == true
				if a.target ~= 0 and (a.attacker == me or a.target == me) and not counter then
					local key = a.attacker * 65536 + a.target
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
						Config.Render.WarFx.ArrowStride,
						3,
						Config.Render.WarFx.ArrowMinCells
					)
					local mid = list[math.max(1, (#list + 1) // 2)]
					if mid ~= nil and visible(math.floor(mid.y) * w + math.floor(mid.x)) then
						local b = badges[key]
						if b == nil and badgeCount < maxBadges then
							b = makeBadge(key, mid.x, mid.y - 1.5, a.ratio, a.target == me)
							badges[key] = b
						end
						if b ~= nil then
							b.tx, b.ty = mid.x, mid.y - 1.5
							b.ratio = a.ratio
							b.seen = now
							forecast(b, a, now)
						end
					end
				end
			end
		end
		-- Фронт закрылся или ушёл из кадра — плашка исчезает.
		for key, b in badges do
			if b.seen < now then
				dropBadge(key)
			end
		end
	end

	-- 2. Кольца захвата городов.
	local rings: { Ring } = {}
	local function ring(cell: number, color: Color3)
		if #rings >= maxRings then
			return
		end
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundTransparency = 1
		f.ZIndex = 16
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 3
		stroke.Parent = f
		f.Parent = canvas
		table.insert(rings, { frame = f, stroke = stroke, x = cell % w + 0.5, y = cell // w + 0.5, born = os.clock() })
	end

	-- Владельцы городов — чтобы узнать, что город сменил хозяина.
	local cityOwner: { [number]: number } = {}
	local citySet: { [number]: boolean } = {}
	local cityCount = -1
	local function syncCities()
		if #cs.cities == cityCount then
			return
		end
		cityCount = #cs.cities
		table.clear(citySet)
		for _, c in cs.cities do
			citySet[c] = true
			if cityOwner[c] == nil then
				cityOwner[c] = ownerAt(c)
			end
		end
	end

	-- 3. Салют и баннер выбывания.
	local sparks: { Spark } = {}
	local function firework(cell: number, color: Color3)
		local x, y = cell % w + 0.5, cell // w + 0.5
		local now = os.clock()
		local gold, white = Theme.Colors.Gold, Theme.color("White")
		for k = 1, fireworkSparks do
			local angle = k / fireworkSparks * math.pi * 2 + (k % 3) * 0.21
			local speed = cfg.FireworkCells * (0.6 + 0.4 * ((k * 7) % 5) / 4)
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.BorderSizePixel = 0
			f.BackgroundColor3 = if k % 4 == 0 then gold elseif k % 4 == 1 then white else color
			f.ZIndex = 17
			f.Parent = canvas
			table.insert(sparks, {
				frame = f,
				x = x,
				y = y,
				vx = math.cos(angle) * speed,
				vy = math.sin(angle) * speed - cfg.FireworkCells * 0.4,
				born = now,
			})
		end
	end

	local elim = Instance.new("Frame")
	elim.Name = "EliminatedBanner"
	elim.AnchorPoint = Vector2.new(0.5, 0.5)
	elim.Position = UDim2.fromScale(0.5, 0.4)
	elim.Size = UDim2.fromOffset(0, 46)
	elim.AutomaticSize = Enum.AutomaticSize.X
	elim.BackgroundColor3 = Theme.Colors.PanelBg
	elim.BorderSizePixel = 0
	elim.Visible = false
	elim.ZIndex = 48
	elim.Parent = hud
	local elimStroke = Instance.new("UIStroke")
	elimStroke.Thickness = 3
	elimStroke.Parent = elim
	local elimPad = Instance.new("UIPadding")
	elimPad.PaddingLeft = UDim.new(0, 18)
	elimPad.PaddingRight = UDim.new(0, 18)
	elimPad.Parent = elim
	local elimText = Instance.new("TextLabel")
	elimText.BackgroundTransparency = 1
	elimText.FontFace = Theme.FontBold
	elimText.TextSize = 22
	elimText.TextColor3 = Theme.Colors.Text
	elimText.TextStrokeTransparency = 0.4
	elimText.Size = UDim2.fromScale(0, 1)
	elimText.AutomaticSize = Enum.AutomaticSize.X
	elimText.ZIndex = 49
	elimText.Parent = elim
	local elimFrom = -math.huge

	-- 4. Корона и плашка «Сверхдержава».
	local crowns: { [number]: Crown } = {}
	local function makeCrown(owner: number): Crown
		local root = Instance.new("Frame")
		root.Name = "GiantCrown"
		root.AnchorPoint = Vector2.new(0.5, 1)
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromOffset(7 * cfg.CrownPx, 5 * cfg.CrownPx)
		root.ZIndex = 6
		root.Parent = canvas
		for row, line in CROWN do
			for col = 1, #line do
				local ch = string.sub(line, col, col)
				if ch ~= "." then
					local p = Instance.new("Frame")
					p.BorderSizePixel = 0
					p.BackgroundColor3 = if ch == "r" then Theme.color("Red") else Theme.Colors.Gold
					p.Position = UDim2.fromOffset((col - 1) * cfg.CrownPx, (row - 1) * cfg.CrownPx)
					p.Size = UDim2.fromOffset(cfg.CrownPx, cfg.CrownPx)
					p.ZIndex = 6
					p.Parent = root
				end
			end
		end
		local shadow = Instance.new("UIStroke")
		shadow.Color = Theme.Colors.Backdrop
		shadow.Thickness = 1
		shadow.Transparency = 0.3
		shadow.Parent = root
		return { root = root, owner = owner }
	end

	local chip = Instance.new("Frame")
	chip.Name = "GiantChip"
	chip.Size = UDim2.fromOffset(0, 30)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.BackgroundColor3 = Theme.Colors.PanelBg
	chip.BorderSizePixel = 0
	chip.Visible = false
	chip.Parent = hud
	local chipStroke = Instance.new("UIStroke")
	chipStroke.Color = Theme.Colors.Gold
	chipStroke.Thickness = 2
	chipStroke.Parent = chip
	local chipPad = Instance.new("UIPadding")
	chipPad.PaddingLeft = UDim.new(0, 10)
	chipPad.PaddingRight = UDim.new(0, 10)
	chipPad.Parent = chip
	local chipText = Instance.new("TextLabel")
	chipText.BackgroundTransparency = 1
	chipText.FontFace = Theme.FontBold
	chipText.TextSize = 14
	chipText.TextColor3 = Theme.Colors.Gold
	chipText.RichText = true
	chipText.Size = UDim2.fromScale(0, 1)
	chipText.AutomaticSize = Enum.AutomaticSize.X
	chipText.Parent = chip

	local function giantOf(id: number): number
		local stats = cs.stats
		if stats == nil or land <= 0 then
			return 0
		end
		for _, n in stats.nations do
			if n.id == id then
				return Fronts.giant(n.cells / land)
			end
		end
		return 0
	end

	local function cityScale(zoom: number): number
		local scale = 1
		for _, step in Config.Render.CityScales do
			if zoom >= step.zoom then
				scale = step.scale
			end
		end
		return scale
	end

	local function refreshGiants()
		local alive: { [number]: boolean } = {}
		for _, n in cs.nations do
			if n.alive and n.capital ~= nil and giantOf(n.id) >= cfg.CrownFromGiant then
				alive[n.id] = true
				if crowns[n.id] == nil then
					crowns[n.id] = makeCrown(n.id)
				end
			end
		end
		for id, c in crowns do
			if not alive[id] then
				c.root:Destroy()
				crowns[id] = nil
			end
		end
		local me = cs.myNation
		local mine = if me ~= nil then giantOf(me) else 0
		chip.Visible = mine > 0 and cs.phase == "Play"
		if chip.Visible then
			local g = Config.Combat.Giant
			chipText.Text = string.format(
				Strings.get("fx.giant", lang),
				math.round((g.AttackerSpeedMax - 1) * mine * 100),
				math.round((1 - g.AttackerLossMin) * mine * 100)
			)
		end
	end

	-- 5. Тряска экрана.
	local shakeFrom, shakeAmp = -math.huge, 0
	local basePos = viewport.Position
	local function shake(px: number)
		local now = os.clock()
		local mul = if phone then Config.Render.Shake.PhoneMul else 1
		local left = math.max(0, 1 - (now - shakeFrom) / Config.Render.Shake.Sec)
		-- Новая тряска не слабее остатка прежней.
		shakeAmp = math.max(px * mul, shakeAmp * left)
		shakeFrom = now
	end

	local function onEvents(events: { any })
		local me = cs.myNation
		for _, e in events do
			if type(e) ~= "table" then
				continue
			end
			if e.kind == "nukeHit" and type(e.cell) == "number" then
				local state = lastState
				if state ~= nil then
					local x0, y0, x1, y1 = CameraMath.visibleRect(state)
					local cx, cy = e.cell % w, e.cell // w
					local r = tonumber(e.radius) or 10
					if cx >= x0 - r and cx <= x1 + r and cy >= y0 - r and cy <= y1 + r then
						shake(Config.Render.Shake.NukePx)
					end
				end
			elseif e.kind == "capitalLost" and me ~= nil and e.nation == me then
				shake(Config.Render.Shake.CapitalPx)
			elseif e.kind == "eliminated" and type(e.nation) == "number" then
				local by = if type(e.by) == "number" then e.by else 0
				local n = cs.nations[e.nation]
				local cell = if n ~= nil then n.capital else nil
				if cell ~= nil and visible(cell) then
					firework(cell, if by ~= 0 then colorOf(by) else Theme.Colors.Gold)
				end
				elimText.Text = string.format(Strings.get("fx.eliminated", lang), nameOf(e.nation))
				elimStroke.Color = if by ~= 0 then colorOf(by) else colorOf(e.nation)
				elimFrom = os.clock()
				elim.Visible = true
			end
		end
	end

	local function onSnapshot()
		table.clear(cityOwner)
		cityCount = -1
		syncCities()
		for c in citySet do
			cityOwner[c] = ownerAt(c)
		end
	end

	local function onDelta(cells: { number })
		syncCities()
		local me = cs.myNation
		for _, c in cells do
			if citySet[c] then
				local before = cityOwner[c] or 0
				local after = ownerAt(c)
				if before ~= after then
					cityOwner[c] = after
					if after ~= 0 and visible(c) then
						ring(c, colorOf(after))
						local x, y = c % w + 0.5, c // w
						if me ~= nil and after == me then
							float(x, y, Strings.get("fx.cityTaken", lang), Theme.Colors.Gold, 18, cfg.CityTextSec)
						elseif me ~= nil and before == me then
							float(x, y, Strings.get("fx.cityLost", lang), Theme.Colors.Alert, 18, cfg.CityTextSec)
						end
					end
				end
			end
		end
	end

	local giantAt = -math.huge
	local function update(now: number, state: CameraState)
		lastState = state
		local dt = math.clamp(now - lastNow, 0, 0.1)
		lastNow = now
		local zoom = state.zoom
		if now - lastScan >= cfg.BadgeScanSec then
			lastScan = now
			scanBadges(state)
		end
		-- Плашки: число и место догоняют, полоса — цвет; переход в прорыв своего фронта — «ПРОРЫВ!».
		local ease = math.min(1, dt * cfg.BadgeEasePerSec)
		local move = math.min(1, dt * cfg.BadgeMoveEasePerSec)
		local me = cs.myNation
		for _, b in badges do
			local target = math.min(b.ratio, cfg.BadgeMaxShown)
			b.shown += (target - b.shown) * ease
			b.x += (b.tx - b.x) * move
			b.y += (b.ty - b.y) * move
			local band: WarFx.RatioBand =
				WarFx.ratioBand(b.ratio, Config.Combat.FullSpeedRatio, Config.Combat.BreakthroughRatio)
			if band ~= b.band then
				if band == "breakthrough" and b.band ~= nil and not b.againstMe and me ~= nil then
					float(
						b.x,
						b.y - 1,
						Strings.get("fx.breakthroughPop", lang),
						Theme.Colors.Gold,
						22,
						cfg.BreakthroughSec
					)
				end
				b.band = band
			end
			local value = if b.ratio >= cfg.BadgeMaxShown
				then string.format("%d+", cfg.BadgeMaxShown)
				else string.format("%.1f", math.max(0.1, b.shown))
			local text = if band == "breakthrough"
				then string.format(Strings.get("fx.breakthrough", lang), value)
				else "×" .. value
			b.label.Text = (if b.againstMe then "⚠ " else "") .. text
			b.label.TextColor3 = bandColor[band]
			b.status.TextColor3 = bandColor[band]
			b.stroke.Color = if b.againstMe then Theme.Colors.Alert else bandColor[band]
			-- Прорыв — плашка пульсирует.
			local pulse = if band == "breakthrough" then 1 + 0.08 * math.sin(now * 8) else 1
			b.label.TextSize = 15 * pulse
			b.frame.Position = UDim2.fromOffset(b.x * zoom, b.y * zoom)
		end
		-- Кольца захвата.
		local k = 1
		while k <= #rings do
			local r = rings[k]
			local t = (now - r.born) / cfg.CityRingSec
			if t >= 1 then
				r.frame:Destroy()
				rings[k] = rings[#rings]
				rings[#rings] = nil
			else
				local ease2 = 1 - (1 - t) * (1 - t)
				local size = math.max(6, cfg.CityRingCells * 2 * zoom * ease2)
				r.frame.Position = UDim2.fromOffset(r.x * zoom, r.y * zoom)
				r.frame.Size = UDim2.fromOffset(size, size)
				r.stroke.Transparency = t
				r.stroke.Thickness = 1 + 4 * (1 - t)
				k += 1
			end
		end
		-- Всплывающие надписи: выскакивают, поднимаются, тают.
		k = 1
		while k <= #floaters do
			local f = floaters[k]
			local t = (now - f.born) / f.life
			if t >= 1 then
				f.label:Destroy()
				floaters[k] = floaters[#floaters]
				floaters[#floaters] = nil
			else
				local pop = math.min(1, t * 8)
				f.label.Position = UDim2.fromOffset(f.x * zoom, f.y * zoom - f.rise * t)
				f.label.TextTransparency = math.max(0, (t - 0.6) / 0.4)
				f.label.TextStrokeTransparency = 0.2 + 0.8 * t
				f.label.Rotation = (1 - pop) * -8
				k += 1
			end
		end
		-- Салют: искры разлетаются, падают и гаснут.
		k = 1
		while k <= #sparks do
			local s = sparks[k]
			local t = (now - s.born) / cfg.FireworkSec
			if t >= 1 then
				s.frame:Destroy()
				sparks[k] = sparks[#sparks]
				sparks[#sparks] = nil
			else
				local life = t * cfg.FireworkSec
				local x = s.x + s.vx * t * (1 - t * 0.5)
				local y = s.y + s.vy * t + cfg.FireworkCells * 1.2 * t * t
				local size = math.max(2, zoom * 0.9)
				s.frame.Position = UDim2.fromOffset(x * zoom, y * zoom)
				s.frame.Size = UDim2.fromOffset(size, size)
				s.frame.BackgroundTransparency = t * t
				s.frame.Rotation = life * 180
				k += 1
			end
		end
		-- Баннер выбывания: въезжает, держится, тает.
		if elim.Visible then
			local t = (now - elimFrom) / cfg.ElimSec
			if t >= 1 then
				elim.Visible = false
			else
				local alpha = math.min(t / 0.12, (1 - t) / 0.2, 1)
				elim.BackgroundTransparency = 1 - 0.9 * alpha
				elimText.TextTransparency = 1 - alpha
				elimStroke.Transparency = 1 - alpha
				elim.Position = UDim2.new(0.5, 0, 0.4, -(1 - math.min(1, t / 0.12)) * 20)
			end
		end
		-- Короны — раз в полсекунды (доля суши меняется медленно), место — каждый кадр.
		if now - giantAt >= cfg.BadgeScanSec then
			giantAt = now
			refreshGiants()
		end
		for id, c in crowns do
			local n = cs.nations[id]
			local cell = if n ~= nil then n.capital else nil
			if cell == nil then
				c.root.Visible = false
			else
				local cx, cy = cell % w, cell // w
				local left, top = CameraMath.cellEdge(zoom, cx), CameraMath.cellEdge(zoom, cy)
				local cellW = CameraMath.cellEdge(zoom, cx + 1) - left
				local side = CitySprites.size(ClientState.cityLevel(cs, cell)) * cityScale(zoom)
				local centerY = top + cellW / 2
				local labelTop = centerY - side / 2 - 2 - (Config.Render.NationLabelSize + 4)
				c.root.Visible = visible(cell)
				c.root.Position = UDim2.fromOffset(left + cellW / 2, labelTop - 2 + math.sin(now * 2 + id) * 1.5)
			end
		end
		-- Тряска экрана.
		local t = (now - shakeFrom) / Config.Render.Shake.Sec
		if t < 1 then
			local dx, dy = WarFx.shake(t, shakeAmp, Config.Render.Shake.Hz, Config.Render.Shake.Sec)
			viewport.Position = basePos + UDim2.fromOffset(math.round(dx), math.round(dy))
		elseif viewport.Position ~= basePos then
			viewport.Position = basePos
		end
	end

	return {
		onEvents = onEvents,
		onSnapshot = onSnapshot,
		onDelta = onDelta,
		update = update,
		giantChip = chip,
	}
end

return table.freeze(BattleFxLayer)
