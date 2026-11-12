--!strict
--[[
	SpectacleLayer — зрелищность на карте (GDD §15х ч.9). Что показать — чистый SpectacleFx, частицы рисует общий
	движок StrikeFxLayer.spawn; здесь — когда и где:
	- флот: кильватер за идущими кораблями (ShipLayer.visible), залпы эсминцев в бою (SpectacleFx.duels — правило
	  сервера), гибель корабля (события shipSunk / merchantSunk с x, y);
	- взятый город: флаг и волны цвета захватчика (cityTaken — из BattleFxLayer, там же кольцо и надпись);
	- заражение и шторм (cs.world.fallout / storm): огоньки и дождь с тучами, только в кадре;
	- день и ночь (ПК, Render.DayNight): затемнение карты по времени матча, огни городов ночью;
	- выбор старта: «дышащие» кольца у своей столицы и союзников, круг соседства у чужих;
	- приказ (order — из send в Main.client): шевроны сходятся к точке;
	- победа: салют цветом победителя над его столицей, камера — onVictory (Main.client).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Fog = require(Shared:WaitForChild("Fog"))
local RenderBudget = require(Shared:WaitForChild("RenderBudget"))
local SpectacleFx = require(Shared:WaitForChild("SpectacleFx"))
local StrikeFx = require(Shared:WaitForChild("StrikeFx"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local ShipLayer = require(script.Parent:WaitForChild("ShipLayer"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type Spawner = (parts: { StrikeFx.Part }, owner: number, delay: number, low: boolean) -> ()

export type SpectacleLayer = {
	onEvents: (events: { any }) -> (),
	cityTaken: (cell: number, owner: number) -> (),
	order: (cell: number) -> (),
	update: (now: number, state: CameraState) -> (),
}

local SpectacleLayer = {}

function SpectacleLayer.new(
	canvas: Frame,
	cs: ClientState,
	spawn: Spawner,
	ships: () -> { ShipLayer.VisibleShip },
	onVictory: (cell: number) -> ()
): SpectacleLayer
	local cfg = Config.Render.Spectacle
	local dn = Config.Render.DayNight
	local phone = RenderBudget.isPhone(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)
	local nightOn = dn.Enabled and (dn.Phone or not phone)
	local w = cs.width
	local lastState: CameraState? = nil
	local seed = 0
	local function nextSeed(): number
		seed += 1
		return seed
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

	-- Ночь: затемнение над картой (над территорией, под подсветками и значками) и огни городов.
	local night = Instance.new("Frame")
	night.Name = "Night"
	night.BorderSizePixel = 0
	night.BackgroundColor3 = Theme.Colors.Backdrop
	night.BackgroundTransparency = 1
	night.ZIndex = 2
	night.Visible = false
	night.Parent = canvas
	type Light = { core: Frame, halo: Frame }
	local lights: { Light } = {}
	local function light(k: number): Light
		local l = lights[k]
		if l ~= nil then
			return l
		end
		local function round(color: Color3, z: number): Frame
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.BorderSizePixel = 0
			f.BackgroundColor3 = color
			f.ZIndex = z
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = f
			f.Parent = canvas
			return f
		end
		local made = { core = round(Theme.Colors.Gold, 3), halo = round(Theme.color("Orange"), 3) }
		lights[k] = made
		return made
	end

	-- Выбор старта: кольца (рамка без заливки).
	local rings: { Frame } = {}
	local function ring(k: number): Frame
		local f: Frame? = rings[k]
		if f ~= nil then
			return f
		end
		local made = Instance.new("Frame")
		made.AnchorPoint = Vector2.new(0.5, 0.5)
		made.BorderSizePixel = 0
		made.ZIndex = 4
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = made
		local st = Instance.new("UIStroke")
		st.Thickness = 2
		st.Parent = made
		made.Parent = canvas
		rings[k] = made
		return made
	end

	local nextWake, nextSalvo, nextFallout, nextRain, nextCloud = 0, 0, 0, 0, 0
	local lastShips: { ShipLayer.VisibleShip } = {}

	local function onEvents(events: { any })
		for _, e in events do
			if type(e) ~= "table" then
				continue
			end
			if
				(e.kind == "shipSunk" or e.kind == "merchantSunk")
				and type(e.x) == "number"
				and type(e.y) == "number"
			then
				local cell = math.floor(e.y) * w + math.floor(e.x)
				if visible(cell) and onScreen(e.x, e.y, 6) then
					spawn(SpectacleFx.sinking(e.x, e.y, nextSeed()), tonumber(e.nation) or 0, 0, false)
				end
			elseif e.kind == "victory" and type(e.nation) == "number" then
				local n = cs.nations[e.nation]
				local cap = if n ~= nil then n.capital else nil
				if cap ~= nil then
					onVictory(cap)
					local x, y = cap % w + 0.5, cap // w + 0.5
					spawn(
						SpectacleFx.fireworks(x, y, nextSeed(), cfg.VictoryVolleys, cfg.VictorySparks),
						e.nation,
						0.6, -- камера успевает долететь
						false
					)
				end
			end
		end
	end

	local function warActive(a: number, b: number): boolean
		local war = ClientState.warBetween(cs, a, b)
		return war ~= nil and (war :: any).active == true
	end

	local function update(now: number, state: CameraState)
		lastState = state
		local zoom = state.zoom
		local playing = cs.phase == "Play"
		-- Флот: кильватер и залпы.
		if playing and now >= nextWake then
			nextWake = now + cfg.WakeEverySec
			lastShips = ships()
			local made = 0
			for _, s in lastShips do
				if made >= cfg.MaxWakeShips then
					break
				end
				if (math.abs(s.dx) > 0.05 or math.abs(s.dy) > 0.05) and onScreen(s.x, s.y, 2) then
					made += 1
					spawn(SpectacleFx.wake(s.x, s.y, s.dx, s.dy, nextSeed()), s.owner, 0, true)
				end
			end
		end
		if playing and now >= nextSalvo then
			nextSalvo = now + cfg.SalvoEverySec
			local list: { SpectacleFx.ShipLike } = {}
			for _, s in lastShips do
				table.insert(list, { id = s.id, owner = s.owner, kind = s.kind, x = s.x, y = s.y })
			end
			for _, d in SpectacleFx.duels(list, w, warActive) do
				if onScreen(d.from.x, d.from.y, 4) then
					spawn(SpectacleFx.salvo(d.from.x, d.from.y, d.to.x, d.to.y, nextSeed()), d.from.owner, 0, false)
				end
			end
		end
		-- Заражение и шторм — только в кадре.
		if playing and now >= nextFallout then
			nextFallout = now + cfg.FalloutEverySec
			local fallout: { { cell: number, radius: number, left: number } } = cs.world.fallout or {}
			for _, f in fallout do
				local x, y = f.cell % w + 0.5, f.cell // w + 0.5
				if onScreen(x, y, f.radius) then
					spawn(SpectacleFx.fallout(x, y, f.radius, nextSeed(), cfg.FalloutPerTick), 0, 0, true)
				end
			end
		end
		local storm = cs.world.storm
		if playing and storm ~= nil and now >= nextRain then
			nextRain = now + cfg.StormEverySec
			local x, y = storm.cell % w + 0.5, storm.cell // w + 0.5
			if onScreen(x, y, storm.radius) then
				local clouds = 0
				if now >= nextCloud then
					nextCloud = now + cfg.StormCloudEverySec
					clouds = 2
				end
				spawn(SpectacleFx.storm(x, y, storm.radius, nextSeed(), cfg.StormPerTick, clouds), 0, 0, true)
			end
		end
		-- День и ночь.
		local dark = if nightOn and playing then SpectacleFx.darkness(ClientState.matchTime(cs, now)) else 0
		night.Visible = dark > 0.005
		local litCount = 0
		if night.Visible then
			night.Position = UDim2.fromOffset(0, 0)
			night.Size = UDim2.fromOffset(w * zoom, cs.height * zoom)
			night.BackgroundTransparency = 1 - dark
			local glow = dark / dn.MaxDark
			for cell, b in cs.buildings do
				if b.kind == "City" and litCount < cfg.MaxCityLights and visible(cell) then
					local x, y = cell % w + 0.5, cell // w + 0.5
					if onScreen(x, y, 2) then
						litCount += 1
						local l = light(litCount)
						local px = dn.LightPx + 2 * (b.level - 1)
						local flicker = 0.9 + 0.1 * math.sin(now * 5 + cell)
						l.core.Visible, l.halo.Visible = true, true
						l.core.Position = UDim2.fromOffset(x * zoom, y * zoom)
						l.halo.Position = l.core.Position
						l.core.Size = UDim2.fromOffset(px * flicker, px * flicker)
						l.halo.Size = UDim2.fromOffset(px * 2.6, px * 2.6)
						l.core.BackgroundTransparency = 1 - 0.9 * glow
						l.halo.BackgroundTransparency = 1 - 0.35 * glow
					end
				end
			end
		end
		for k = litCount + 1, #lights do
			lights[k].core.Visible = false
			lights[k].halo.Visible = false
		end
		-- Выбор старта: кольца у своих, круг соседства у чужих.
		local ringCount = 0
		if cs.phase == "Pick" then
			local me = cs.myNation
			local friends = if me ~= nil then ClientState.friendsOf(cs, me) else {}
			local breathe = 0.5 + 0.5 * math.sin(now * math.pi * 2 / cfg.PickRingSec)
			local zone = Config.Start.NeighbourCells * w / Config.UnitsReferenceMapWidth
			for id, n in cs.nations do
				local cap = n.capital
				if cap ~= nil then
					local x, y = cap % w + 0.5, cap // w + 0.5
					local mine = me ~= nil and (id == me or friends[id] == true)
					local r = if mine then (2.5 + 1.5 * breathe) else zone
					if onScreen(x, y, r) then
						ringCount += 1
						local f = ring(ringCount)
						f.Visible = true
						f.Position = UDim2.fromOffset(x * zoom, y * zoom)
						f.Size = UDim2.fromOffset(math.max(10, r * 2 * zoom), math.max(10, r * 2 * zoom))
						local st = f:FindFirstChildOfClass("UIStroke")
						if mine then
							f.BackgroundTransparency = 1
							if st ~= nil then
								st.Color = if id == me then Theme.Colors.Gold else Theme.color("Lime")
								st.Transparency = 0.1 + 0.5 * (1 - breathe)
							end
						else
							f.BackgroundColor3 = Theme.Colors.Alert
							f.BackgroundTransparency = 0.88
							if st ~= nil then
								st.Color = Theme.Colors.Alert
								st.Transparency = 0.45
							end
						end
					end
				end
			end
		end
		for k = ringCount + 1, #rings do
			rings[k].Visible = false
		end
	end

	return {
		onEvents = onEvents,
		cityTaken = function(cell: number, owner: number)
			local x, y = cell % w + 0.5, cell // w + 0.5
			if onScreen(x, y, 8) then
				spawn(SpectacleFx.capture(x, y, nextSeed()), owner, 0, false)
			end
		end,
		order = function(cell: number)
			local x, y = cell % w + 0.5, cell // w + 0.5
			if onScreen(x, y, 4) then
				-- На дальнем плане шевроны идут издалека — не меньше OrderMinPx на экране.
				local zoom = if lastState ~= nil then lastState.zoom else 4
				spawn(SpectacleFx.order(x, y, cfg.OrderMinPx / zoom), cs.myNation or 0, 0, false)
			end
		end,
		update = update,
	}
end

return table.freeze(SpectacleLayer)
