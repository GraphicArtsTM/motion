--!strict
--[[
	BuildingLayer — здания и нефтяные поля на карте (GDD §6.8–6.9).
	Значки 12×12 (Shared.BuildingSprites, §15д ч.4) в клетке здания (§15г — любая своя клетка), цветом владельца клетки;
	улучшенный город — золотые точки-уровни рядом с городом; нефтяное поле без вышки — тёмная капля в центре
	провинции. С приближением значки крупнее (Render.MapIcons, §15ы). Владельцы меняются вместе с клетками —
	recolor() перекрашивает. §15х ч.8: издалека (меньше Render.BuildingDotZoom px на клетку) — точка цвета державы,
	без точек уровня, зарядов и нефтяных полей (иначе значки рябят по всей карте).
	§15ч Ч5а: стройка — картинка бледнее, поверх леса (Render.Site.Color) и полоса готовности (sites(now) — каждый кадр).
	§15ы: значок — квадрат с центром в клетке здания, сторона — Shared.MapIcons (растёт с зумом, но не больше места до
	соседнего здания или города: значки не налезают). Точки уровня, заряды и полоса стройки — внутри значка.
	Значок, урезанный городом, рисуется поверх города.
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
local MapIcons = require(Shared:WaitForChild("MapIcons"))
local IconImage = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("IconImage"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type BuildingLayer = {
	refresh: () -> (), -- здания поменялись
	recolor: () -> (), -- владельцы клеток поменялись
	charges: () -> (), -- заряды батарей ПВО поменялись (cs.world.batteries, §15д ч.3)
	sites: (now: number) -> (), -- §15ч Ч5а: леса и полоса готовности строек (cs.world.sites)
	onCamera: (state: CameraState) -> (),
	boxes: () -> { MapIcons.Rect }, -- §15ы: значки зданий (пиксели холста) — подписи провинций их обходят
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
	site: Frame?, -- §15ч Ч5а: леса и полоса готовности
	fill: Frame?,
	-- §15ы: соседи (смещения в клетках) — сторона значка не больше места до них.
	nearB: { { dx: number, dy: number } },
	nearC: { CityNear },
	dotted: boolean, -- §15ы: сейчас точка (дальний план или не влез у города)
}

-- §15ы: город рядом со значком — смещение, уровень и здания вокруг самого города (жетон им уступает).
type CityNear = { dx: number, dy: number, level: number, around: { { dx: number, dy: number } } }

-- §15ы: соседей ищем не дальше стольких клеток (дальше место заведомо больше значка).
local NEAR = 10

-- Слои значка: поверх городов (NationLabels — до 8), под названиями городов (CityLabels — 12).
local Z_PLATE, Z_PART, Z_SITE = 9, 10, 11

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
		local building = icon.kind ~= "City" and icon.kind ~= "OilField"
		-- §15ы: сторона — обычная для зума, но не больше места до соседей; у города на мелком зуме даже наименьший
		-- значок налезает на жетон — тогда точка, как на дальнем плане.
		local side, fits = 0, true
		if building and not far then
			local cities: { { dx: number, dy: number, half: number } } = {}
			for _, c in icon.nearC do
				local half = MapIcons.halfOf(MapIcons.citySideAmong(c.level, zoom, c.around))
				table.insert(cities, { dx = c.dx, dy = c.dy, half = half })
			end
			local s, _, ok = MapIcons.sideAmong(zoom, icon.nearB, cities)
			side, fits = s, ok
		end
		local dotted = far or not fits
		icon.dotted = dotted
		-- Дальний план (§15х ч.8): у зданий — точка цвета державы, точки уровня города и нефть не видны.
		local showDot = dotted and building
		icon.root.Visible = not dotted or showDot
		for _, f in icon.parts do
			f.Visible = not dotted
		end
		for _, f in icon.root:GetChildren() do
			if f.Name == "Charge" and f:IsA("GuiObject") then
				f.Visible = not dotted
			end
		end
		local d = icon.dot
		if d ~= nil then
			d.Visible = showDot
		end
		local plate = icon.plate
		if plate ~= nil then
			plate.Visible = not dotted
		end
		if dotted then
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
		local cx, cy = icon.cell % w, icon.cell // w
		local left, top = CameraMath.cellEdge(zoom, cx), CameraMath.cellEdge(zoom, cy)
		local x = left + (CameraMath.cellEdge(zoom, cx + 1) - left) / 2
		local y = top + (CameraMath.cellEdge(zoom, cy + 1) - top) / 2
		if icon.kind == "City" then
			-- Точки уровня — на нижнем крае жетона города (MapIcons.citySide), по центру.
			local half = MapIcons.halfOf(MapIcons.citySideAmong(icon.pips + 1, zoom, icon.nearB))
			local pip = math.max(3, math.round(half * 0.14))
			local step = pip + 2
			local width = step * icon.pips - 2
			icon.root.Size = UDim2.fromOffset(width, pip)
			icon.root.Position = UDim2.fromOffset(math.round(x - width / 2), math.round(y + half - pip / 2))
			for k, f in icon.parts do
				f.Position = UDim2.fromOffset((k - 1) * step, 0)
				f.Size = UDim2.fromOffset(pip, pip)
			end
			return
		end
		-- Центр значка — в клетке здания.
		icon.root.Size = UDim2.fromOffset(side, side)
		icon.root.Position = UDim2.fromOffset(math.round(x - side / 2), math.round(y - side / 2))
		local pic = icon.plate
		if pic ~= nil then
			pic.Size = UDim2.fromScale(1, 1)
			pic.Position = UDim2.fromOffset(0, 0)
		end
		local shape = partsShape(icon)
		local scale = side / size
		for k, p in shape do
			icon.parts[k].Position = UDim2.fromOffset(math.floor(p.x * scale), math.floor(p.y * scale))
			icon.parts[k].Size = UDim2.fromOffset(math.ceil(p.w * scale), math.ceil(p.h * scale))
		end
		-- Уровень здания (§15д): золотые точки — внутри значка, у нижнего края слева.
		local pip = math.max(3, math.round(side * 0.13))
		for k = #shape + 1, #icon.parts do
			local i = k - #shape - 1
			icon.parts[k].Position = UDim2.fromOffset(2 + i * (pip + 2), side - pip - 2)
			icon.parts[k].Size = UDim2.fromOffset(pip, pip)
		end
	end

	local function add(kind: string, cell: number, pips: number)
		local root = Instance.new("Frame")
		root.Name = kind .. "_" .. cell
		root.BackgroundTransparency = 1
		root.ZIndex = Z_PLATE
		local plate: Frame? = nil
		local image: ImageLabel? = nil
		local withImage = pictured(kind)
		if withImage then
			local pf = Instance.new("Frame")
			pf.Name = "Plate"
			pf.BorderSizePixel = 0
			pf.BackgroundTransparency = 0.1
			pf.ZIndex = Z_PLATE
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
			img.ZIndex = Z_PLATE
			img.Parent = pf
			plate, image = pf, img
		end
		local parts: { Frame } = {}
		local shapeCount = if withImage then 0 else #shapeOf(kind)
		local count = if kind == "City" then pips else shapeCount + pips
		for k = 1, count do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.ZIndex = Z_PART
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
			d.ZIndex = Z_PLATE
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
			nearB = {},
			nearC = {},
			dotted = false,
		}
		if kind ~= "City" then
			paint(icon)
		end
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
		-- §15ы: соседи каждого значка здания — другие здания и города (уровень города — размер жетона).
		local w = cs.width
		local cityCells: { { x: number, y: number, level: number, around: { { dx: number, dy: number } } } } = {}
		for _, cell in cs.cities do
			table.insert(cityCells, {
				x = cell % w,
				y = cell // w,
				level = ClientState.cityLevel(cs, cell),
				around = MapIcons.buildingsNear(cs.buildings, cell, w, NEAR),
			})
		end
		for _, icon in icons do
			if icon.kind == "City" then
				-- Точки уровня — у края жетона, а он уступает место соседним значкам (как в NationLabels).
				icon.nearB = MapIcons.buildingsNear(cs.buildings, icon.cell, w, NEAR)
				continue
			elseif icon.kind == "OilField" then
				continue
			end
			local x, y = icon.cell % w, icon.cell // w
			for _, other in icons do
				if other ~= icon and other.kind ~= "City" and other.kind ~= "OilField" then
					local dx, dy = other.cell % w - x, other.cell // w - y
					if math.abs(dx) <= NEAR and math.abs(dy) <= NEAR then
						table.insert(icon.nearB, { dx = dx, dy = dy })
					end
				end
			end
			for _, c in cityCells do
				local dx, dy = c.x - x, c.y - y
				if math.abs(dx) <= NEAR and math.abs(dy) <= NEAR then
					table.insert(icon.nearC, { dx = dx, dy = dy, level = c.level, around = c.around })
				end
			end
		end
		for _, icon in icons do
			place(icon)
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
					f.Name = "Charge"
					f.BorderSizePixel = 0
					f.ZIndex = Z_PART
					f.Size = UDim2.fromOffset(4, 4)
					f.Position = UDim2.fromOffset(3 + (k - 1) * 6, 3) -- §15ы: внутри значка, у верхнего края
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

	-- §15ч Ч5а: леса поверх строящегося здания и полоса готовности под ним.
	local siteCfg = Config.Render.Site
	local function scaffold(icon: Icon): (Frame, Frame)
		local box = Instance.new("Frame")
		box.Name = "Site"
		box.BackgroundTransparency = 1
		box.Size = UDim2.fromScale(1, 1)
		box.ZIndex = Z_SITE
		box.Parent = icon.root
		local wood = Theme.color(siteCfg.Color)
		local function bar(x: number, y: number, w: number, h: number)
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = wood
			f.Position = UDim2.fromScale(x, y)
			f.Size = UDim2.fromScale(w, h)
			f.ZIndex = Z_SITE
			f.Parent = box
		end
		bar(0.06, 0, 0.08, 1) -- стойки
		bar(0.86, 0, 0.08, 1)
		bar(0.06, 0.3, 0.88, 0.07) -- настилы
		bar(0.06, 0.68, 0.88, 0.07)
		local back = Instance.new("Frame")
		back.Name = "Progress"
		back.BorderSizePixel = 0
		back.BackgroundColor3 = Theme.Colors.Backdrop
		-- §15ы: полоса — внутри значка, у нижнего края (не залезает на соседа ниже).
		back.Position = UDim2.fromScale(0.08, 0.84)
		back.Size = UDim2.fromScale(0.84, siteCfg.BarHeight)
		back.ZIndex = Z_SITE
		back.Parent = box
		local fill = Instance.new("Frame")
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = Theme.color(siteCfg.Fill)
		fill.Size = UDim2.fromScale(0, 1)
		fill.ZIndex = Z_SITE + 1
		fill.Parent = back
		return box, fill
	end
	local function sites(now: number)
		local list = cs.world.sites
		local progress: { [number]: number } = {}
		if list ~= nil then
			for _, s in list do
				local _, frac = ClientState.siteAt(cs, s.cell, now)
				progress[s.cell] = frac
			end
		end
		for _, icon in icons do
			local frac = progress[icon.cell]
			if frac ~= nil and icon.kind ~= "City" and icon.kind ~= "OilField" then
				if icon.site == nil or icon.fill == nil then
					icon.site, icon.fill = scaffold(icon)
				end
				(icon.site :: Frame).Visible = not icon.dotted;
				(icon.fill :: Frame).Size = UDim2.fromScale(frac, 1)
				local image = icon.image
				if image ~= nil then
					image.ImageTransparency = siteCfg.PictureAlpha
				end
			elseif icon.site ~= nil then
				(icon.site :: Frame):Destroy()
				icon.site, icon.fill = nil, nil
				local image = icon.image
				if image ~= nil then
					image.ImageTransparency = 0
				end
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
		boxes = function(): { MapIcons.Rect }
			local out: { MapIcons.Rect } = {}
			if far then
				return out
			end
			for _, icon in icons do
				if icon.kind ~= "City" and icon.root.Visible then
					local p, s = icon.root.Position, icon.root.Size
					local x, y = p.X.Offset, p.Y.Offset
					table.insert(out, { x0 = x, y0 = y, x1 = x + s.X.Offset, y1 = y + s.Y.Offset })
				end
			end
			return out
		end,
		sites = sites,
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
