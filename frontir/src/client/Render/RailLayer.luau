--!strict
--[[
	RailLayer — железные дороги и поезда поверх карты (§15ч Ч2).
	- Линии дорог: вблизи рельсы видны пикселями в картинке территории (TerritoryLayer), а вдали, где клетка меньше
	  Render.Rail.LineBelowZoom px, — линии постоянной толщины поверх карты: путь сглаживается до кусков около
	  SegmentPx на экране, кусок через реку — цветом дерева.
	- Поезда: паровоз и Wagons вагонов едут по маршруту из события trainStarted (клиент двигает сам: копит игровое
	  время через ClientState.simRate — пауза и ×2 учитываются); trainGone — убрать. Вошедшему в матч поезда
	  приходят со снимком (rails full: trains, now).
	- §15ч Ч4: водные пути — голубая линия вдоль реки на любом зуме (Render.Rail.Water); поезд на клетке реки —
	  баржа (цвет Render.Rail.Barge, крупнее).
	- §15ч Ч5б режим «Логистика» (setLogistics): линии на любом зуме — своя главная сеть золотом, оторванные куски —
	  серым, чужие — бледно; точки станций (setStations) — зелёная в сети, красная без дороги.
	- §15ч Ч3в: разрушенные мосты (cs.rails.damaged) — тёмный квадрат с красным крестом, пока не починят; обрыв дороги
	  (railCut) и гибель поезда у фронта (trainGone war) — красный крест на Render.Rail.CutShowSec, гаснет.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Rails = require(Shared:WaitForChild("Rails"))
local Trains = require(Shared:WaitForChild("Trains"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type RailLayer = {
	railsChanged: () -> (), -- сети поменялись — перестроить линии
	onRails: (msg: any) -> (), -- сообщение rails (со снимком — поезда в пути)
	onEvents: (events: { any }) -> (),
	update: (now: number, dt: number, state: CameraState) -> (),
	setLogistics: (on: boolean, me: number?) -> (), -- §15ч Ч5б
	setStations: (list: { { cell: number, on: boolean } }) -> (),
	trainsOf: (owner: number) -> number, -- свои поезда в пути
}

type Segment = { frame: Frame, ax: number, ay: number, bx: number, by: number }
type Train = { cells: { number }, speed: number, t: number, cars: { Frame }, colors: { Color3 }, owner: number }
-- left — сколько ещё показывать (nil — пока мост разрушен).
type Mark = { frame: Frame, cell: number, left: number? }

local RailLayer = {}

function RailLayer.new(canvas: Frame, cs: ClientState, width: number, isRiver: (cell: number) -> boolean): RailLayer
	local cfg = Config.Render.Rail
	local lines = Instance.new("Frame")
	lines.Name = "RailLines"
	lines.BackgroundTransparency = 1
	lines.Size = UDim2.fromScale(1, 1)
	lines.ZIndex = 3
	lines.Visible = false
	lines.Parent = canvas
	local trainsRoot = Instance.new("Frame")
	trainsRoot.Name = "Trains"
	trainsRoot.BackgroundTransparency = 1
	trainsRoot.Size = UDim2.fromScale(1, 1)
	trainsRoot.ZIndex = 6
	trainsRoot.Parent = canvas

	-- §15ч Ч4: водные пути — свой слой, виден всегда.
	local waterRoot = Instance.new("Frame")
	waterRoot.Name = "Waterways"
	waterRoot.BackgroundTransparency = 1
	waterRoot.Size = UDim2.fromScale(1, 1)
	waterRoot.ZIndex = 3
	waterRoot.Parent = canvas

	local segments: { Segment } = {}
	local builtStep = -1 -- шаг сглаживания (клеток), с которым построены куски
	local dirty = true
	local placedZoom = -1
	local waterSegs: { Segment } = {}
	local waterStep = -1
	local waterDirty = true
	local waterZoom = -1

	local function clearLines()
		for _, s in segments do
			s.frame:Destroy()
		end
		table.clear(segments)
	end

	local function newSegment(list: { Segment }, root: Frame, a: number, b: number, color: Color3, alpha: number)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = alpha
		f.ZIndex = 3
		f.Parent = root
		table.insert(list, {
			frame = f,
			ax = a % width + 0.5,
			ay = a // width + 0.5,
			bx = b % width + 0.5,
			by = b // width + 0.5,
		})
	end

	-- Водные пути: куски через step клеток.
	local function buildWater(step: number)
		for _, s in waterSegs do
			s.frame:Destroy()
		end
		table.clear(waterSegs)
		waterStep = step
		waterZoom = -1
		local color = Theme.color(cfg.Water)
		local seaColor = Theme.color(cfg.Sea)
		for _, net in cs.rails.nets do
			for idx, path in net.paths do
				local sea = net.sea[idx] == true
				if net.water[idx] or sea then
					-- §15ч Ч6: морская линия — пунктир (кусок через кусок).
					local k = 1
					local on = true
					while k < #path do
						local nextK = math.min(#path, k + step)
						if on or not sea then
							newSegment(
								waterSegs,
								waterRoot,
								path[k],
								path[nextK],
								if sea then seaColor else color,
								if sea then cfg.SeaAlpha else cfg.WaterAlpha
							)
						end
						on = not on
						k = nextK
					end
				end
			end
		end
	end

	-- §15ч Ч5б: режим «Логистика» и чья сеть «своя».
	local logistics = false
	local logisticsMe: number? = nil

	-- Куски линий: по каждому пути — точки через step клеток (и последняя).
	local function buildLines(step: number)
		clearLines()
		builtStep = step
		local lineColor = Theme.color(cfg.LineColor)
		local bridgeColor = Theme.color(cfg.Bridge)
		local mainColor = Theme.color(cfg.MainColor)
		local otherColor = Theme.color(cfg.OtherColor)
		for owner, net in cs.rails.nets do
			for idx, path in net.paths do
				if net.water[idx] or net.sea[idx] then
					continue -- водный путь и морскую линию рисует buildWater
				end
				-- «Логистика»: своя главная сеть — золото, свои оторванные куски — серым, чужие — бледно.
				local color: Color3? = nil
				local alpha = cfg.LineAlpha
				if logistics then
					if owner == logisticsMe then
						local main = net.connected[path[1]] == true and net.connected[path[#path]] == true
						color = if main then mainColor else otherColor
						alpha = 0
					else
						alpha = cfg.ForeignAlpha
					end
				end
				local k = 1
				while k < #path do
					local nextK = math.min(#path, k + step)
					local a, b = path[k], path[nextK]
					local bridge = false
					for j = k, nextK do
						if isRiver(path[j]) then
							bridge = true
							break
						end
					end
					local f = Instance.new("Frame")
					f.BorderSizePixel = 0
					f.AnchorPoint = Vector2.new(0.5, 0.5)
					f.BackgroundColor3 = color or (if bridge then bridgeColor else lineColor)
					f.BackgroundTransparency = if bridge and color == nil then 0 else alpha
					f.ZIndex = 3
					f.Parent = lines
					table.insert(segments, {
						frame = f,
						ax = a % width + 0.5,
						ay = a // width + 0.5,
						bx = b % width + 0.5,
						by = b // width + 0.5,
					})
					k = nextK
				end
			end
		end
		placedZoom = -1
	end

	local function placeList(list: { Segment }, zoom: number, px: number)
		for _, s in list do
			local dx, dy = (s.bx - s.ax) * zoom, (s.by - s.ay) * zoom
			local len = math.sqrt(dx * dx + dy * dy)
			s.frame.Position = UDim2.fromOffset((s.ax + s.bx) / 2 * zoom, (s.ay + s.by) / 2 * zoom)
			s.frame.Size = UDim2.fromOffset(len + px, px)
			s.frame.Rotation = math.deg(math.atan2(dy, dx))
		end
	end

	local function placeLines(zoom: number)
		placedZoom = zoom
		placeList(segments, zoom, if logistics then cfg.LogisticsPx else cfg.LinePx)
	end

	-- §15ч Ч5б: точки станций в режиме «Логистика».
	local stationRoot = Instance.new("Frame")
	stationRoot.Name = "Stations"
	stationRoot.BackgroundTransparency = 1
	stationRoot.Size = UDim2.fromScale(1, 1)
	stationRoot.ZIndex = 7
	stationRoot.Visible = false
	stationRoot.Parent = canvas
	local stationDots: { [number]: Frame } = {}
	local stationZoom = -1
	local function setStations(list: { { cell: number, on: boolean } })
		local keep: { [number]: boolean } = {}
		for _, s in list do
			keep[s.cell] = true
			local f: Frame? = stationDots[s.cell]
			if f == nil then
				local dot = Instance.new("Frame")
				f = dot
				dot.Name = "Station"
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				dot.BorderSizePixel = 0
				dot.ZIndex = 7
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.5, 0)
				corner.Parent = dot
				local stroke = Instance.new("UIStroke")
				stroke.Color = Theme.Colors.Backdrop
				stroke.Parent = dot
				dot.Parent = stationRoot
				stationDots[s.cell] = dot
			end
			(f :: Frame).BackgroundColor3 = Theme.color(if s.on then cfg.StationOn else cfg.StationOff)
		end
		for cell, f in stationDots do
			if not keep[cell] then
				f:Destroy()
				stationDots[cell] = nil
			end
		end
		stationZoom = -1
	end

	-- §15ч Ч3в: кресты — разрушенные мосты и места обрывов.
	local marksRoot = Instance.new("Frame")
	marksRoot.Name = "RailMarks"
	marksRoot.BackgroundTransparency = 1
	marksRoot.Size = UDim2.fromScale(1, 1)
	marksRoot.ZIndex = 7
	marksRoot.Parent = canvas
	local marks: { [string]: Mark } = {}
	local function makeCross(broken: boolean): Frame
		local box = Instance.new("Frame")
		box.Name = if broken then "BrokenBridge" else "RailCut"
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.BorderSizePixel = 0
		box.BackgroundColor3 = Theme.color(cfg.Broken)
		box.BackgroundTransparency = if broken then 0.15 else 1
		box.ZIndex = 7
		box.Parent = marksRoot
		for _, angle in { 45, -45 } do
			local bar = Instance.new("Frame")
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = UDim2.fromScale(1.2, 0.22)
			bar.Rotation = angle
			bar.BorderSizePixel = 0
			bar.BackgroundColor3 = Theme.color(cfg.Cut)
			bar.ZIndex = 8
			bar.Parent = box
		end
		return box
	end
	local function removeMark(key: string)
		local mk = marks[key]
		if mk ~= nil then
			mk.frame:Destroy()
			marks[key] = nil
		end
	end
	-- Разрушенные мосты — по списку из сообщения rails.
	local function syncBroken()
		for key, mk in marks do
			if mk.left == nil and cs.rails.damaged[mk.cell] == nil then
				removeMark(key)
			end
		end
		for cell in cs.rails.damaged do
			local key = "b" .. cell
			if marks[key] == nil then
				marks[key] = { frame = makeCross(true), cell = cell, left = nil }
			end
		end
	end
	local function addCut(cell: number)
		local key = "c" .. cell
		removeMark(key)
		marks[key] = { frame = makeCross(false), cell = cell, left = cfg.CutShowSec }
	end

	-- Поезда.
	local trains: { [number]: Train } = {}
	local function removeTrain(id: number)
		local tr = trains[id]
		if tr ~= nil then
			for _, f in tr.cars do
				f:Destroy()
			end
			trains[id] = nil
		end
	end
	-- toAlly — §15ч Ч3б: поезд к союзнику (вагоны цвета Render.Rail.AllyWagon).
	local function addTrain(
		id: number,
		s: number,
		d: string,
		speed: number,
		elapsed: number,
		toAlly: boolean,
		owner: number
	)
		removeTrain(id)
		local cells = Rails.decode(s, d, width)
		if #cells < 2 then
			return
		end
		local cars: { Frame } = {}
		local colors: { Color3 } = {}
		for k = 0, cfg.Wagons do
			local f = Instance.new("Frame")
			f.Name = if k == 0 then "Engine" else "Wagon"
			f.BorderSizePixel = 0
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.BackgroundColor3 = Theme.color(if k == 0 then cfg.Engine elseif toAlly then cfg.AllyWagon else cfg.Wagon)
			f.ZIndex = 6
			f.Parent = trainsRoot
			table.insert(cars, f)
			table.insert(colors, f.BackgroundColor3)
		end
		trains[id] =
			{ cells = cells, speed = speed, t = math.max(0, elapsed), cars = cars, colors = colors, owner = owner }
	end

	local function onEvents(events: { any })
		for _, e in events do
			if type(e) == "table" and e.kind == "railCut" and type(e.cell) == "number" then
				addCut(e.cell) -- §15ч Ч3в: дорогу перерезали
				continue
			end
			if type(e) ~= "table" or type(e.id) ~= "number" then
				continue
			end
			if e.kind == "trainStarted" and type(e.s) == "number" and type(e.d) == "string" then
				addTrain(e.id, e.s, e.d, tonumber(e.speed) or 1, 0, type(e.ally) == "number", tonumber(e.nation) or 0)
			elseif e.kind == "trainGone" then
				removeTrain(e.id)
				if e.war == true and type(e.cell) == "number" then
					addCut(e.cell) -- §15ч Ч3в: поезд погиб у фронта
				end
			end
		end
	end

	local function onRails(msg: any)
		if type(msg) ~= "table" or msg.full ~= true then
			return
		end
		for id in trains do
			removeTrain(id)
		end
		local now = tonumber(msg.now) or 0
		if type(msg.trains) == "table" then
			for _, tr in msg.trains do
				if
					type(tr) == "table"
					and type(tr.id) == "number"
					and type(tr.s) == "number"
					and type(tr.d) == "string"
				then
					addTrain(
						tr.id,
						tr.s,
						tr.d,
						tonumber(tr.speed) or 1,
						now - (tonumber(tr.start) or now),
						type(tr.ally) == "number",
						tonumber(tr.nation) or 0
					)
				end
			end
		end
	end

	local function update(_now: number, dt: number, state: CameraState)
		local zoom = state.zoom
		-- Линии — только вдали.
		local far = zoom < cfg.LineBelowZoom or logistics -- «Логистика»: линии на любом зуме
		lines.Visible = far
		stationRoot.Visible = logistics
		if logistics and math.abs(zoom - stationZoom) > 1e-3 then
			stationZoom = zoom
			for cell, f in stationDots do
				f.Position = UDim2.fromOffset((cell % width + 0.5) * zoom, (cell // width + 0.5) * zoom)
				f.Size = UDim2.fromOffset(cfg.StationPx, cfg.StationPx)
			end
		end
		if far then
			local step = math.max(1, math.ceil(cfg.SegmentPx / zoom))
			if dirty or step ~= builtStep then
				dirty = false
				buildLines(step)
			end
			if math.abs(zoom - placedZoom) > 1e-3 then
				placeLines(zoom)
			end
		elseif dirty then
			-- Вблизи линии не нужны: перестроим, когда снова отдалятся.
			clearLines()
			builtStep = -1
		end
		-- §15ч Ч4: водные пути — на любом зуме.
		local wStep = math.max(1, math.ceil(cfg.SegmentPx / zoom))
		if waterDirty or wStep ~= waterStep then
			waterDirty = false
			buildWater(wStep)
		end
		if math.abs(zoom - waterZoom) > 1e-3 then
			waterZoom = zoom
			placeList(waterSegs, zoom, cfg.WaterPx)
		end
		-- Поезда едут (игровое время — с паузой и ×2); на реке — баржа.
		local simDt = dt * ClientState.simRate(cs)
		local size = math.max(cfg.CarPx, zoom * cfg.CarCells)
		local bargeColor = Theme.color(cfg.Barge)
		for _, tr in trains do
			tr.t += simDt
			for k, f in tr.cars do
				local x, y = Trains.at(tr.cells, width, tr.speed, tr.t, (k - 1) * cfg.CarGap)
				local here = math.floor(y) * width + math.floor(x)
				local onRiver = isRiver(here) or cs.rails.seaway[here] ~= nil -- §15ч Ч6: на море — тоже судно
				local s = if onRiver then size * cfg.BargeMul else size
				f.Position = UDim2.fromOffset(x * zoom, y * zoom)
				f.Size = UDim2.fromOffset(s, s)
				f.BackgroundColor3 = if onRiver then bargeColor else tr.colors[k]
			end
		end
		-- Кресты: на месте, обрывы гаснут (реальное время).
		local markSize = math.max(cfg.MarkPx, zoom * cfg.MarkCells)
		for key, mk in marks do
			local left = mk.left
			if left ~= nil then
				left -= dt
				mk.left = left
				if left <= 0 then
					removeMark(key)
					continue
				end
				local fade = 1 - math.clamp(left / 1, 0, 1) -- последняя секунда — гаснет
				for _, bar in mk.frame:GetChildren() do
					if bar:IsA("Frame") then
						bar.BackgroundTransparency = fade
					end
				end
			end
			mk.frame.Position = UDim2.fromOffset((mk.cell % width + 0.5) * zoom, (mk.cell // width + 0.5) * zoom)
			mk.frame.Size = UDim2.fromOffset(markSize, markSize)
		end
	end

	return {
		railsChanged = function()
			dirty = true
			waterDirty = true
			syncBroken()
		end,
		setLogistics = function(on: boolean, me: number?)
			if on ~= logistics or me ~= logisticsMe then
				logistics, logisticsMe = on, me
				dirty = true
				placedZoom = -1
			end
		end,
		setStations = setStations,
		trainsOf = function(owner: number): number
			local count = 0
			for _, tr in trains do
				if tr.owner == owner then
					count += 1
				end
			end
			return count
		end,
		onRails = onRails,
		onEvents = onEvents,
		update = update,
	}
end

return table.freeze(RailLayer)
