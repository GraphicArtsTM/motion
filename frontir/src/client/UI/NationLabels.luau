--!strict
--[[
	NationLabels — города, столицы и названия держав на карте (GDD §6.5).
	- Город (§15д ч.4): пиксельный город по уровню (Shared.CitySprites) — от домиков до небоскрёбов, цветом
	  владельца (ничей — серый); столица — с флагом, своя — с золотой рамкой; над столицей — название державы.
	До раздачи цветов (выбор старта) выбранные точки — белые квадраты с именем.
	Метки живут на холсте карты и едут вместе с камерой; при смене зума пересчитываются позиции,
	при смене владельца клеток (recolor) — цвета городов. Спрайты города и столицы — docs/ART_LIST.md.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local CitySprites = require(Shared:WaitForChild("CitySprites"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Strings = require(Shared:WaitForChild("Strings"))
local UnitSprites = require(Shared:WaitForChild("UnitSprites"))

local FlagView = require(script.Parent:WaitForChild("FlagView"))
local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

type Marker = {
	cell: number,
	frame: Frame,
	dot: Frame?,
	text: TextLabel?,
	owner: number,
	level: number,
	parts: { Frame },
	shapes: { CitySprites.Part },
}

export type NationLabels = {
	refresh: () -> (),
	recolor: () -> (),
	onCamera: (state: CameraState) -> (),
}

local NationLabels = {}

function NationLabels.new(canvas: Frame, cs: ClientState, lang: Strings.Lang, mapWidth: number): NationLabels
	local markers: { Marker } = {}
	local zoom = 1

	local function ownerColor(owner: number): Color3
		local ci = ClientState.colorIndexOf(cs, owner)
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return if owner == 0 then Theme.Colors.Muted else Theme.color("White")
	end

	-- Масштаб пиксель-арта города от зума (Render.CityScales).
	local function cityScale(): number
		local scale = 1
		for _, step in Config.Render.CityScales do
			if zoom >= step.zoom then
				scale = step.scale
			end
		end
		return scale
	end

	-- Цвета деталей города (тон → цвет хозяина с оттенком или свой цвет).
	local function paintParts(m: Marker)
		local body = ownerColor(m.owner)
		local r, g, b = math.round(body.R * 255), math.round(body.G * 255), math.round(body.B * 255)
		for k, p in m.shapes do
			local shade = CitySprites.Shade[p.tone]
			local f = m.parts[k]
			if shade ~= nil then
				f.BackgroundColor3 = Color3.fromRGB(UnitSprites.shade(r, g, b, shade))
			elseif p.tone == "road" then
				f.BackgroundColor3 = Theme.Colors.Slate
			elseif p.tone == "window" then
				f.BackgroundColor3 = Theme.Colors.Gold
			elseif p.tone == "glass" then
				f.BackgroundColor3 = Theme.Colors.Sky
			else
				f.BackgroundColor3 = Theme.Colors.Backdrop
			end
		end
	end

	local function place(m: Marker)
		local cx, cy = m.cell % mapWidth, m.cell // mapWidth
		local left, top = CameraMath.cellEdge(zoom, cx), CameraMath.cellEdge(zoom, cy)
		local cellW = CameraMath.cellEdge(zoom, cx + 1) - left
		local scale = cityScale()
		local side = CitySprites.size(m.level) * scale
		local centerX, centerY = left + cellW / 2, top + (CameraMath.cellEdge(zoom, cy + 1) - top) / 2
		m.frame.Size = UDim2.fromOffset(side, side)
		m.frame.Position = UDim2.fromOffset(centerX, centerY)
		for k, p in m.shapes do
			m.parts[k].Position = UDim2.fromOffset(p.x * scale, p.y * scale)
			m.parts[k].Size = UDim2.fromOffset(p.w * scale, p.h * scale)
		end
		local text = m.text
		if text ~= nil then
			text.Position = UDim2.fromOffset(centerX, centerY - side / 2 - 2)
		end
	end

	local function clear()
		for _, m in markers do
			m.frame:Destroy()
			if m.text ~= nil then
				m.text:Destroy()
			end
		end
		table.clear(markers)
	end

	local function addMarker(cell: number, capitalOf: ClientState.NationInfo?)
		local owner = if capitalOf ~= nil then capitalOf.id else ClientState.knownOwnerAt(cs, cell)
		local frame = Instance.new("Frame")
		frame.Name = if capitalOf ~= nil then "Capital_" .. capitalOf.id else "City_" .. cell
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		-- Тёмная «подложка» квартала: город читается на любой земле.
		frame.BackgroundColor3 = Theme.Colors.Backdrop
		frame.BackgroundTransparency = 0.45
		frame.BorderSizePixel = 0
		frame.ZIndex = 4
		local isMe = capitalOf ~= nil and capitalOf.id == cs.myNation
		local stroke = Instance.new("UIStroke")
		stroke.Color = if isMe then Theme.Colors.Gold else Theme.Colors.Backdrop
		stroke.Thickness = if isMe then 2 else 1
		stroke.Transparency = if isMe then 0 else 0.4
		stroke.Parent = frame
		local level = ClientState.cityLevel(cs, cell)
		local shapes = CitySprites.parts(level, capitalOf ~= nil)
		local parts: { Frame } = {}
		for _ in shapes do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.ZIndex = 5
			f.Parent = frame
			table.insert(parts, f)
		end
		local dot: Frame? = nil
		frame.Parent = canvas

		local text: TextLabel? = nil
		if capitalOf ~= nil then
			local t = Instance.new("TextLabel")
			t.Name = "Name_" .. capitalOf.id
			t.AnchorPoint = Vector2.new(0.5, 1)
			t.Size = UDim2.fromOffset(0, Config.Render.NationLabelSize + 4)
			t.AutomaticSize = Enum.AutomaticSize.X
			t.BackgroundTransparency = 1
			t.FontFace = Theme.FontBold
			t.TextSize = Config.Render.NationLabelSize
			-- «Предатель» (§8.1) виден всем: красное имя со знаком.
			local traitor = ClientState.isTraitor(cs, capitalOf.id, os.clock(), ClientState.simRate(cs))
			local cosmetic = capitalOf.cosmetic
			t.TextColor3 = if traitor
				then Theme.Colors.Alert
				elseif isMe then Theme.Colors.Gold
				elseif cosmetic ~= nil and cosmetic.vip then Theme.color(Config.Cosmetics.VipNameColor) -- VIP (§11.4)
				else Theme.Colors.Text
			t.TextStrokeColor3 = Theme.Colors.Backdrop
			t.TextStrokeTransparency = 0.2
			-- Команда (§5.1) — номером перед именем.
			local team = if capitalOf.team ~= nil then "[" .. capitalOf.team .. "] " else ""
			t.Text = (if traitor then "⚠ " else "")
				.. team
				.. (if lang == "en" then capitalOf.nameEn else capitalOf.name)
			t.ZIndex = 5
			-- Косметика (§11.4): флаг слева от имени, титул под ним.
			if cosmetic ~= nil then
				local size = Config.Render.NationLabelSize
				local flag = FlagView.new(t, math.floor(size * 1.5), size, 6)
				flag.frame.AnchorPoint = Vector2.new(1, 0.5)
				flag.frame.Position = UDim2.new(0, -4, 0.5, 0)
				flag.set(cosmetic.flag)
				if cosmetic.title ~= nil then
					local title = Instance.new("TextLabel")
					title.AnchorPoint = Vector2.new(0.5, 0)
					title.Position = UDim2.fromScale(0.5, 1)
					title.Size = UDim2.fromOffset(0, size)
					title.AutomaticSize = Enum.AutomaticSize.X
					title.BackgroundTransparency = 1
					title.FontFace = Theme.Font
					title.TextSize = math.max(10, size - 4)
					title.TextColor3 = Theme.Colors.Muted
					title.TextStrokeColor3 = Theme.Colors.Backdrop
					title.TextStrokeTransparency = 0.3
					title.Text = Strings.get("title." .. cosmetic.title, lang)
					title.ZIndex = 5
					title.Parent = t
				end
			end
			t.Parent = canvas
			text = t
		end
		local m: Marker = {
			cell = cell,
			frame = frame,
			dot = dot,
			text = text,
			owner = owner,
			level = level,
			parts = parts,
			shapes = shapes,
		}
		paintParts(m)
		place(m)
		table.insert(markers, m)
	end

	local function refresh()
		clear()
		local capitals: { [number]: ClientState.NationInfo } = {}
		for _, n in cs.nations do
			if n.capital ~= nil and n.alive then
				capitals[n.capital] = n
			end
		end
		for cell, n in capitals do
			addMarker(cell, n)
		end
		for _, cell in cs.cities do
			if capitals[cell] == nil then
				addMarker(cell, nil)
			end
		end
	end

	-- Владельцы городов меняются вместе с клетками: перекрашиваем только изменившиеся.
	local function recolor()
		for _, m in markers do
			if m.text == nil then
				local owner = ClientState.knownOwnerAt(cs, m.cell)
				if owner ~= m.owner then
					m.owner = owner
					paintParts(m)
				end
			end
		end
	end

	return {
		refresh = refresh,
		recolor = recolor,
		onCamera = function(state: CameraState)
			if state.zoom ~= zoom then
				zoom = state.zoom
				for _, m in markers do
					place(m)
				end
			end
		end,
	}
end

return table.freeze(NationLabels)
