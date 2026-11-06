--!strict
--[[
	BuildingLayer — здания и нефтяные поля на карте (GDD §6.8–6.9).
	Значки 7×7 (Shared.BuildingSprites) в клетке здания (§15г — любая своя клетка), цветом владельца клетки;
	улучшенный город — золотые точки-уровни рядом с городом; нефтяное поле без вышки — тёмная капля в центре
	провинции. С приближением значки крупнее (Render.BuildingIconScales). Владельцы меняются вместе с клетками —
	recolor() перекрашивает.
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

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type BuildingLayer = {
	refresh: () -> (), -- здания поменялись
	recolor: () -> (), -- владельцы клеток поменялись
	charges: () -> (), -- заряды батарей ПВО поменялись (cs.world.batteries, §15д ч.3)
	onCamera: (state: CameraState) -> (),
}

type Icon = { root: Frame, parts: { Frame }, kind: string, cell: number, owner: number, pips: number }

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

	local function paint(icon: Icon)
		local color = ownerColor(icon.owner)
		for k, p in shapeOf(icon.kind) do
			icon.parts[k].BackgroundColor3 = if p.ink then Theme.Colors.Backdrop else color
		end
	end

	local function place(icon: Icon)
		local w = cs.width
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
		local shape = shapeOf(icon.kind)
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
		local parts: { Frame } = {}
		local count = if kind == "City" then pips else #shapeOf(kind) + pips
		for k = 1, count do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.ZIndex = 5
			if kind == "City" or k > #shapeOf(kind) then
				f.BackgroundColor3 = Theme.Colors.Gold
				local stroke = Instance.new("UIStroke")
				stroke.Color = Theme.Colors.Backdrop
				stroke.Parent = f
			end
			f.Parent = root
			table.insert(parts, f)
		end
		root.Parent = canvas
		local icon: Icon = {
			root = root,
			parts = parts,
			kind = kind,
			cell = cell,
			owner = ClientState.knownOwnerAt(cs, cell),
			pips = pips,
		}
		if kind ~= "City" then
			paint(icon)
		end
		place(icon)
		table.insert(icons, icon)
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
				add("OilField", p.center, 0)
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
		if list == nil then
			return
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
				for _, icon in icons do
					place(icon)
				end
			end
		end,
	}
end

return table.freeze(BuildingLayer)
