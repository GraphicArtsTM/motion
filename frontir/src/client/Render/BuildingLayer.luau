--!strict
--[[
	BuildingLayer — здания и нефтяные поля на карте (GDD §6.8–6.9).
	Значки 12×12 (Shared.BuildingSprites, §15д ч.4) в клетке здания (§15г — любая своя клетка), цветом владельца клетки;
	улучшенный город — золотые точки-уровни рядом с городом; нефтяное поле без вышки — тёмная капля в центре
	провинции. С приближением значки крупнее (Render.BuildingIconScales). Владельцы меняются вместе с клетками —
	recolor() перекрашивает. §15х ч.8: издалека (меньше Render.BuildingDotZoom px на клетку) — точка цвета державы,
	без точек уровня, зарядов и нефтяных полей (иначе значки рябят по всей карте).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildingSprites = require(Shared:WaitForChild("BuildingSprites"))
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Fog = require(Shared:WaitForChild("Fog"))
local MapData = require(Shared:WaitForChild("MapData"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Provinces = require(Shared:WaitForChild("Provinces"))

local IconArt = require(Shared:WaitForChild("IconArt"))
local IconImage = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("IconImage"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type BuildingLayer = {
	refresh: () -> (), -- здания поменялись
	recolor: () -> (), -- владельцы клеток поменялись
	charges: () -> (), -- заряды батарей ПВО поменялись (cs.world.batteries, §15д ч.3)
	onCamera: (state: CameraState) -> (),
}

-- §15я: plate / image — здание картинкой (assets/icons/buildings) на подложке цвета хозяина; без них — пиксели.
type Icon = {
	root: Frame,
	parts: { Frame },
	kind: string,
	cell: number,
	owner: number,
	pips: number,
	dot: Frame?,
	plate: Frame?,
	image: ImageLabel?,
}

local BuildingLayer = {}

function BuildingLayer.new(
	canvas: Frame,
	cs: ClientState,
	provinces: Provinces.ProvinceSet,
	map: MapData.MapData
): BuildingLayer
	local icons: { Icon } = {}
	local zoom = 1
	local size = BuildingSprites.Size
	local far = false -- §15х ч.8: дальний план — точки вместо значков

	local function ownerColor(owner: number): Color3
		local ci = ClientState.colorIndexOf(cs, owner)
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Muted
	end

	local NONE: { BuildingSprites.Part } = {}
	local function shapeOf(kind: string): { BuildingSprites.Part }
		return BuildingSprites.Shapes[kind] or NONE
	end
	-- §15я: картинка здания есть — пиксельные детали не нужны (только точки уровня).
	local function pictured(kind: string): boolean
		return kind ~= "City" and kind ~= "OilField" and IconArt.has(kind) and IconImage.content(kind) ~= nil
	end
	local function partsShape(icon: Icon): { BuildingSprites.Part }
		return if icon.image ~= nil then NONE else shapeOf(icon.kind)
	end

	local function paint(icon: Icon)
		local color = ownerColor(icon.owner)
		local d = icon.dot
		if d ~= nil then
			d.BackgroundColor3 = color
		end
		local plate = icon.plate
		if plate ~= nil then
			plate.BackgroundColor3 = color
		end
		local r, g, b = math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255)
		for k, p in partsShape(icon) do
			icon.parts[k].BackgroundColor3 = Color3.fromRGB(BuildingSprites.rgb(p, r, g, b))
		end
	end

	local function place(icon: Icon)
		local w = cs.width
		-- Дальний план (§15х ч.8): у зданий — точка цвета державы, точки уровня города и нефть не видны.
		local showDot = far and icon.kind ~= "City" and icon.kind ~= "OilField"
		icon.root.Visible = not far or showDot
		for _, f in icon.parts do
			f.Visible = not far
		end
		local d = icon.dot
		if d ~= nil then
			d.Visible = showDot
		end
		local plate = icon.plate
		if plate ~= nil then
			plate.Visible = not far
		end
		if far then
			if showDot and d ~= nil then
				local px = Config.Render.BuildingDotPx
				local cx, cy = icon.cell % w, icon.cell // w
				icon.root.Size = UDim2.fromOffset(px, px)
				icon.root.Position =
					UDim2.fromOffset(math.round((cx + 0.5) * zoom - px / 2), math.round((cy + 0.5) * zoom - px / 2))
				d.Size = UDim2.fromOffset(px, px)
				d.Position = UDim2.fromOffset(0, 0)
			end
			return
		end
		local scale = 1
		for _, step in Config.Render.BuildingIconScales do
			if zoom >= step.zoom then
				scale = step.scale
			end
		end
		local cx, cy = icon.cell % w, icon.cell // w
		local left = CameraMath.cellEdge(zoom, cx)
		local x = left + (CameraMath.cellEdge(zoom, cx + 1) - left) / 2
		local y = CameraMath.cellEdge(zoom, cy)
		if icon.kind == "City" then
			-- Точки уровня справа от городского квадрата.
			icon.root.Size = UDim2.fromOffset(3 * scale * icon.pips, 2 * scale)
			icon.root.Position = UDim2.fromOffset(x + 4 * scale, y - 2 * scale)
			for k, f in icon.parts do
				f.Position = UDim2.fromOffset((k - 1) * 3 * scale, 0)
				f.Size = UDim2.fromOffset(2 * scale, 2 * scale)
			end
			return
		end
		icon.root.Size = UDim2.fromOffset(size * scale, size * scale)
		-- Значок стоит над своей клеткой.
		icon.root.Position = UDim2.fromOffset(math.round(x - size * scale / 2), y - size * scale)
		-- §15я: картинка — чуть крупнее пиксельного значка, на скруглённой подложке цвета хозяина.
		local pic = icon.plate
		if pic ~= nil then
			local side = math.round(size * scale * 1.35)
			pic.Size = UDim2.fromOffset(side, side)
			pic.Position = UDim2.fromOffset(math.round((size * scale - side) / 2), size * scale - side)
		end
		local shape = partsShape(icon)
		for k, p in shape do
			icon.parts[k].Position = UDim2.fromOffset(p.x * scale, p.y * scale)
			icon.parts[k].Size = UDim2.fromOffset(p.w * scale, p.h * scale)
		end
		-- Уровень здания (§15д): золотые точки под значком.
		for k = #shape + 1, #icon.parts do
			local i = k - #shape - 1
			icon.parts[k].Position = UDim2.fromOffset(i * 3 * scale, (size + 1) * scale)
			icon.parts[k].Size = UDim2.fromOffset(2 * scale, 2 * scale)
		end
	end

	local function add(kind: string, cell: number, pips: number)
		local root = Instance.new("Frame")
		root.Name = kind .. "_" .. cell
		root.BackgroundTransparency = 1
		root.ZIndex = 5
		local plate: Frame? = nil
		local image: ImageLabel? = nil
		local withImage = pictured(kind)
		if withImage then
			local pf = Instance.new("Frame")
			pf.Name = "Plate"
			pf.BorderSizePixel = 0
			pf.BackgroundTransparency = 0.15
			pf.ZIndex = 5
			pf.Parent = root
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.25, 0)
			corner.Parent = pf
			local st = Instance.new("UIStroke")
			st.Color = Theme.Colors.Backdrop
			st.Thickness = 1.5
			st.Parent = pf
			local img = Instance.new("ImageLabel")
			img.Name = "Picture"
			img.BackgroundTransparency = 1
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.fromScale(0.5, 0.5)
			img.Size = UDim2.fromScale(0.92, 0.92)
			img.ScaleType = Enum.ScaleType.Fit
			img.ResampleMode = Enum.ResamplerMode.Pixelated
			img.ImageContent = IconImage.content(kind) :: Content
			img.ZIndex = 5
			img.Parent = pf
			plate, image = pf, img
		end
		local parts: { Frame } = {}
		local shapeCount = if withImage then 0 else #shapeOf(kind)
		local count = if kind == "City" then pips else shapeCount + pips
		for k = 1, count do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.ZIndex = 6
			if kind == "City" or k > shapeCount then
				f.BackgroundColor3 = Theme.Colors.Gold
				local stroke = Instance.new("UIStroke")
				stroke.Color = Theme.Colors.Backdrop
				stroke.Parent = f
			end
			f.Parent = root
			table.insert(parts, f)
		end
		local dot: Frame? = nil
		if kind ~= "City" and kind ~= "OilField" then
			local d = Instance.new("Frame")
			d.Name = "Dot"
			d.BorderSizePixel = 0
			d.ZIndex = 5
			d.Visible = false
			local stroke = Instance.new("UIStroke")
			stroke.Color = Theme.Colors.Backdrop
			stroke.Parent = d
			d.Parent = root
			dot = d
		end
		root.Parent = canvas
		local icon: Icon = {
			root = root,
			parts = parts,
			kind = kind,
			cell = cell,
			owner = ClientState.knownOwnerAt(cs, cell),
			pips = pips,
			dot = dot,
			plate = plate,
			image = image,
		}
		if kind ~= "City" then
			paint(icon)
		end
		place(icon)
		table.insert(icons, icon)
	end

	-- §15я Я4: метка нефтяного поля — не на клетке города (иначе картинка города её закрывает, а она — город):
	-- клетка провинции на расстоянии около Render.OilMarkerOffset клеток от города. Провинции не меняются — кеш.
	local oilSpots: { [number]: number } = {}
	local function oilSpot(p: Provinces.Province): number
		local cached = oilSpots[p.id]
		if cached ~= nil then
			return cached
		end
		local w = map.width
		local city = p.city or p.center
		local cx, cy = city % w, city // w
		local want = Config.Render.OilMarkerOffset
		local best, bestErr = p.center, math.huge
		if p.city ~= nil or p.center == city then
			for _, cell in p.cells do
				local dx, dy = cell % w - cx, cell // w - cy
				-- Ближе всего к нужному расстоянию; при равенстве — правее и ниже (одинаково у всех игроков).
				local err = math.abs(math.sqrt(dx * dx + dy * dy) - want) - (dx + dy) * 0.01
				if err < bestErr then
					best, bestErr = cell, err
				end
			end
		end
		oilSpots[p.id] = best
		return best
	end

	local function refresh()
		for _, icon in icons do
			icon.root:Destroy()
		end
		table.clear(icons)
		for cell, b in cs.buildings do
			-- Туман (§6.11): здание видно, если клетку хоть раз видели; города — везде, когда границы видны всем.
			local cityShown = b.kind == "City" and not cs.fog.hideTerritory
			if not cityShown and not Fog.wasSeen(cs.fog, cell) then
				continue
			end
			if b.kind == "City" then
				if b.level > 1 then
					add("City", cell, b.level - 1)
				end
			else
				add(b.kind, cell, b.level - 1)
			end
		end
		-- Нефтяные поля без вышки (вышка — в любой клетке провинции, §15г).
		local rigged: { [number]: boolean } = {}
		for cell, b in cs.buildings do
			if b.kind == "OilRig" then
				rigged[MapData.getProvince(map, cell)] = true
			end
		end
		for _, p in provinces.list do
			if p.oil and not rigged[p.id] then
				add("OilField", oilSpot(p), 0)
			end
		end
	end

	-- Заряды батарей ПВО (§15д ч.3): голубые точки над значком — готов, тёмные — восстанавливается.
	local chargeDots: { [number]: { Frame } } = {}
	local function charges()
		for _, dots in chargeDots do
			for _, f in dots do
				f:Destroy()
			end
		end
		table.clear(chargeDots)
		local list = cs.world.batteries
		if list == nil or far then
			return -- дальний план (§15х ч.8): заряды не рисуем
		end
		local byCell: { [number]: Icon } = {}
		for _, icon in icons do
			byCell[icon.cell] = icon
		end
		for _, b in list do
			local icon = byCell[b.cell]
			if icon ~= nil and icon.kind == "AirDefense" then
				local dots: { Frame } = {}
				for k = 1, b.max do
					local f = Instance.new("Frame")
					f.BorderSizePixel = 0
					f.ZIndex = 6
					f.Size = UDim2.fromOffset(4, 4)
					f.Position = UDim2.fromOffset((k - 1) * 6, -7)
					f.BackgroundColor3 = if k <= b.ready then Theme.Colors.Sky else Theme.Colors.Slate
					local stroke = Instance.new("UIStroke")
					stroke.Color = Theme.Colors.Backdrop
					stroke.Parent = f
					f.Parent = icon.root
					table.insert(dots, f)
				end
				chargeDots[b.cell] = dots
			end
		end
	end

	local function recolor()
		for _, icon in icons do
			if icon.kind ~= "City" and icon.kind ~= "OilField" then
				local owner = ClientState.knownOwnerAt(cs, icon.cell)
				if owner ~= icon.owner then
					icon.owner = owner
					paint(icon)
				end
			end
		end
	end

	return {
		refresh = function()
			refresh()
			charges()
		end,
		recolor = recolor,
		charges = charges,
		onCamera = function(state: CameraState)
			if state.zoom ~= zoom then
				zoom = state.zoom
				local wasFar = far
				far = zoom < Config.Render.BuildingDotZoom
				for _, icon in icons do
					place(icon)
				end
				if far ~= wasFar then
					charges()
				end
			end
		end,
	}
end

return table.freeze(BuildingLayer)
