--!strict
--[[
	MarkerLayer — круги на карте (этап 7г): шторм на море (§6.16, голубой) и ракеты в полёте (§6.9, красный круг
	удара с обратным отсчётом). Рамки на canvas карты; положение — по камере (CameraMath.cellEdge), данные — из
	ClientState.world (раз в секунду) и события missileLaunched (сразу).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local StrikeForecast = require(Shared:WaitForChild("StrikeForecast"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type MarkerLayer = {
	refresh: () -> (), -- пришло сообщение world
	onEvents: (events: { any }) -> (),
	update: (now: number, state: CameraState) -> (),
	-- §15х: круги защиты врага у цели прицеливания (ПВО — оранжевый, ЗРК — голубой, без зарядов — серый);
	-- звать каждый кадр, пока целимся: перестали — круги гаснут сами.
	defenses: (covers: { StrikeForecast.Cover }) -> (),
	-- §15х ч.2: круг действия здания под курсором (звать каждый кадр, пока наведено).
	range: (cell: number, radius: number, color: Color3) -> (),
	-- §15х ч.4б: круг «Карты угроз» под ключом key (цвет — при создании, в ключе должен быть вид); звать каждый кадр.
	zone: (key: string, cell: number, radius: number, color: Color3) -> (),
}

type Marker = { frame: Frame, label: TextLabel?, cell: number, radius: number, endsAt: number }

local MarkerLayer = {}

function MarkerLayer.new(canvas: Frame, cs: ClientState): MarkerLayer
	local markers: { [string]: Marker } = {}
	local width = cs.width

	local function make(key: string, color: Color3, withLabel: boolean): Marker
		local f = Instance.new("Frame")
		f.Name = "Marker_" .. key
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 0.8
		f.BorderSizePixel = 0
		f.ZIndex = 9
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 2
		stroke.Parent = f
		local label: TextLabel? = nil
		if withLabel then
			local l = Instance.new("TextLabel")
			l.AnchorPoint = Vector2.new(0.5, 0.5)
			l.Position = UDim2.fromScale(0.5, 0.5)
			l.Size = UDim2.fromOffset(40, 20)
			l.BackgroundTransparency = 1
			l.FontFace = Theme.FontBold
			l.TextSize = 16
			l.TextColor3 = Theme.Colors.Text
			l.TextStrokeTransparency = 0.3
			l.ZIndex = 10
			l.Parent = f
			label = l
		end
		f.Parent = canvas
		local m: Marker = { frame = f, label = label, cell = 0, radius = 1, endsAt = 0 }
		markers[key] = m
		return m
	end

	local function set(key: string, color: Color3, cell: number, radius: number, endsAt: number, withLabel: boolean)
		local m = markers[key] or make(key, color, withLabel)
		m.cell, m.radius, m.endsAt = cell, radius, endsAt
	end

	-- §15х ч.3: свой удар — голубой, союзника — зелёный, чужой — красный.
	local function strikeColor(owner: number): Color3
		local me = cs.myNation
		if me ~= nil and owner == me then
			return Theme.Colors.Sky
		elseif me ~= nil and ClientState.friendsOf(cs, me)[owner] then
			return Theme.color("Lime")
		end
		return Theme.Colors.Alert
	end

	local function refresh()
		local now = os.clock()
		local speed = math.max(ClientState.simRate(cs), 1e-3) -- на паузе отсчёт стоит
		local live: { [string]: boolean } = {}
		local storm = cs.world.storm
		if storm ~= nil then
			set("storm", Theme.Colors.Sky, storm.cell, storm.radius, now + storm.left / speed, false)
			live.storm = true
		end
		-- Заражённые зоны (§15ж): зелёный круг с отсчётом.
		local fallout: { { cell: number, radius: number, left: number } } = cs.world.fallout or {}
		for _, f in fallout do
			local key = "fallout_" .. f.cell
			set(key, Theme.color("Lime"), f.cell, f.radius, now + f.left / speed, true)
			live[key] = true
		end
		for _, mi in cs.world.missiles do
			local key = "missile_" .. mi.cell
			set(
				key,
				strikeColor(mi.owner),
				mi.cell,
				mi.radius or Config.Buildings.MissileSilo.strikeRadius,
				now + mi.left / speed,
				true
			)
			live[key] = true
		end
		for key, m in markers do
			if not live[key] and os.clock() >= m.endsAt then
				m.frame:Destroy()
				markers[key] = nil
			end
		end
	end

	local function onEvents(events: { any })
		local now = os.clock()
		for _, e in events do
			if type(e) == "table" and e.kind == "missileLaunched" and type(e.cell) == "number" then
				local left = (tonumber(e.impactIn) or 0) / math.max(ClientState.simRate(cs), 1e-3)
				set(
					"missile_" .. e.cell,
					strikeColor(tonumber(e.nation) or 0),
					e.cell,
					if type(e.radius) == "number" then e.radius else Config.Buildings.MissileSilo.strikeRadius,
					now + left,
					true
				)
			elseif
				type(e) == "table"
				and (e.kind == "missileHit" or e.kind == "missileShot" or e.kind == "nukeHit")
				and type(e.cell) == "number"
			then
				local m = markers["missile_" .. e.cell]
				if m ~= nil then
					m.frame:Destroy()
					markers["missile_" .. e.cell] = nil
				end
			end
		end
	end

	local function update(now: number, state: CameraState)
		local zoom = state.zoom
		for key, m in markers do
			if now >= m.endsAt + 1 then
				m.frame:Destroy()
				markers[key] = nil
				continue
			end
			local cx, cy = m.cell % width, m.cell // width
			local x0 = CameraMath.cellEdge(zoom, cx - m.radius)
			local x1 = CameraMath.cellEdge(zoom, cx + m.radius + 1)
			local y0 = CameraMath.cellEdge(zoom, cy - m.radius)
			local y1 = CameraMath.cellEdge(zoom, cy + m.radius + 1)
			m.frame.Position = UDim2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2)
			m.frame.Size = UDim2.fromOffset(x1 - x0, y1 - y0)
			local label = m.label
			if label ~= nil then
				label.Text =
					tostring(math.max(0, math.ceil((m.endsAt - now) * math.max(ClientState.simRate(cs), 1e-3))))
			end
		end
	end

	local function defenses(covers: { StrikeForecast.Cover })
		local now = os.clock()
		for _, c in covers do
			local color = if c.ready <= 0
				then Theme.Colors.Muted
				elseif c.long then Theme.Colors.Sky
				else Theme.color("Orange")
			-- §15х ч.6: накрывает дальним кругом — круг дальний (голубой), иначе ближний (оранжевый).
			local near = Config.Buildings.AirDefense.radius
			local radius = math.round(if c.long then StrikeForecast.radius(99, width, true) else near)
			-- Ключ — с состоянием заряда: цвет круга задаётся при создании.
			local key = "def_" .. c.cell .. (if c.ready > 0 then "_on" else "_off")
			set(key, color, c.cell, radius, now - 0.6, false) -- без обновления гаснет через ~0.4 с
		end
	end

	local function range(cell: number, radius: number, color: Color3)
		set("range_" .. cell, color, cell, math.max(1, math.round(radius)), os.clock() - 0.6, false)
	end

	local function zone(key: string, cell: number, radius: number, color: Color3)
		set(key, color, cell, math.max(1, math.round(radius)), os.clock() - 0.6, false)
	end

	return {
		refresh = refresh,
		onEvents = onEvents,
		update = update,
		defenses = defenses,
		range = range,
		zone = zone,
	}
end

return table.freeze(MarkerLayer)
