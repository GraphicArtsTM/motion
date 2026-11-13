--!strict
--[[
	RailLayer — железные дороги и поезда поверх карты (§15ч Ч2).
	- Линии дорог: вблизи рельсы видны пикселями в картинке территории (TerritoryLayer), а вдали, где клетка меньше
	  Render.Rail.LineBelowZoom px, — линии постоянной толщины поверх карты: путь сглаживается до кусков около
	  SegmentPx на экране, кусок через реку — цветом дерева.
	- Поезда: паровоз и Wagons вагонов едут по маршруту из события trainStarted (клиент двигает сам: копит игровое
	  время через ClientState.simRate — пауза и ×2 учитываются); trainGone — убрать. Вошедшему в матч поезда
	  приходят со снимком (rails full: trains, now).
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
}

type Segment = { frame: Frame, ax: number, ay: number, bx: number, by: number }
type Train = { cells: { number }, speed: number, t: number, cars: { Frame } }

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

	local segments: { Segment } = {}
	local builtStep = -1 -- шаг сглаживания (клеток), с которым построены куски
	local dirty = true
	local placedZoom = -1

	local function clearLines()
		for _, s in segments do
			s.frame:Destroy()
		end
		table.clear(segments)
	end

	-- Куски линий: по каждому пути — точки через step клеток (и последняя).
	local function buildLines(step: number)
		clearLines()
		builtStep = step
		local lineColor = Theme.color(cfg.LineColor)
		local bridgeColor = Theme.color(cfg.Bridge)
		for _, net in cs.rails.nets do
			for _, path in net.paths do
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
					f.BackgroundColor3 = if bridge then bridgeColor else lineColor
					f.BackgroundTransparency = if bridge then 0 else cfg.LineAlpha
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

	local function placeLines(zoom: number)
		placedZoom = zoom
		for _, s in segments do
			local dx, dy = (s.bx - s.ax) * zoom, (s.by - s.ay) * zoom
			local len = math.sqrt(dx * dx + dy * dy)
			s.frame.Position = UDim2.fromOffset((s.ax + s.bx) / 2 * zoom, (s.ay + s.by) / 2 * zoom)
			s.frame.Size = UDim2.fromOffset(len + cfg.LinePx, cfg.LinePx)
			s.frame.Rotation = math.deg(math.atan2(dy, dx))
		end
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
	local function addTrain(id: number, s: number, d: string, speed: number, elapsed: number)
		removeTrain(id)
		local cells = Rails.decode(s, d, width)
		if #cells < 2 then
			return
		end
		local cars: { Frame } = {}
		for k = 0, cfg.Wagons do
			local f = Instance.new("Frame")
			f.Name = if k == 0 then "Engine" else "Wagon"
			f.BorderSizePixel = 0
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.BackgroundColor3 = Theme.color(if k == 0 then cfg.Engine else cfg.Wagon)
			f.ZIndex = 6
			f.Parent = trainsRoot
			table.insert(cars, f)
		end
		trains[id] = { cells = cells, speed = speed, t = math.max(0, elapsed), cars = cars }
	end

	local function onEvents(events: { any })
		for _, e in events do
			if type(e) ~= "table" or type(e.id) ~= "number" then
				continue
			end
			if e.kind == "trainStarted" and type(e.s) == "number" and type(e.d) == "string" then
				addTrain(e.id, e.s, e.d, tonumber(e.speed) or 1, 0)
			elseif e.kind == "trainGone" then
				removeTrain(e.id)
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
					addTrain(tr.id, tr.s, tr.d, tonumber(tr.speed) or 1, now - (tonumber(tr.start) or now))
				end
			end
		end
	end

	local function update(_now: number, dt: number, state: CameraState)
		local zoom = state.zoom
		-- Линии — только вдали.
		local far = zoom < cfg.LineBelowZoom
		lines.Visible = far
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
		-- Поезда едут (игровое время — с паузой и ×2).
		local simDt = dt * ClientState.simRate(cs)
		local size = math.max(cfg.CarPx, zoom * cfg.CarCells)
		for _, tr in trains do
			tr.t += simDt
			for k, f in tr.cars do
				local x, y = Trains.at(tr.cells, width, tr.speed, tr.t, (k - 1) * cfg.CarGap)
				f.Position = UDim2.fromOffset(x * zoom, y * zoom)
				f.Size = UDim2.fromOffset(size, size)
			end
		end
	end

	return {
		railsChanged = function()
			dirty = true
		end,
		onRails = onRails,
		onEvents = onEvents,
		update = update,
	}
end

return table.freeze(RailLayer)
