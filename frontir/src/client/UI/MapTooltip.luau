--!strict
--[[
	MapTooltip — подсказка при наведении на карту (§15е ч.1, только мышь): чья земля, местность, провинция и
	ЧТО СДЕЛАЕТ КЛИК — «расширение с N людьми», «атака», «объявить войну», «десант на корабле», «ваша земля».
	Правила те же, что у MatchHud.tapCell и сервера (десант — суша на другом массиве, как MatchSim.overSea:
	берём массивы суши, где у нас есть центр провинции). Над окнами интерфейса и в режиме стройки — не видна.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local Naval = require(Shared:WaitForChild("Naval"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState

export type MapTooltip = {
	show: (cell: number?, x: number, y: number, percent: number) -> (), -- cell nil — спрятать
}

local MapTooltip = {}

local terrainNames: { [number]: string } = {}
for name, id in Types.Terrain :: { [string]: number } do
	terrainNames[id] = name
end

local function short(n: number): string
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.round(n))
end

function MapTooltip.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	map: MapDataModule.MapData,
	provinces: Provinces.ProvinceSet
): MapTooltip
	local box = Instance.new("Frame")
	box.Name = "MapTooltip"
	box.BackgroundColor3 = Theme.Colors.PanelBg
	box.BackgroundTransparency = 0.08
	box.BorderSizePixel = 0
	box.Size = UDim2.fromOffset(0, 0)
	box.AutomaticSize = Enum.AutomaticSize.XY
	box.ZIndex = 60
	box.Visible = false
	box.Parent = gui
	Theme.decorate(box)
	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
		(pad :: any)[side] = UDim.new(0, 7)
	end
	pad.Parent = box
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromOffset(0, 0)
	text.AutomaticSize = Enum.AutomaticSize.XY
	text.RichText = true
	text.FontFace = Theme.Font
	text.TextSize = 13
	text.TextColor3 = Theme.Colors.Text
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.ZIndex = 61
	text.Parent = box

	local function hex(c: Color3): string
		return string.format("#%02x%02x%02x", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
	end
	local gold, sky, alert, muted =
		hex(Theme.Colors.Gold), hex(Theme.Colors.Sky), hex(Theme.Colors.Alert), hex(Theme.Colors.Muted)

	-- Массивы суши, где у нас есть центр провинции (пересчёт раз в секунду): нажатие на другой — десант.
	local sea: Naval.SeaMap? = nil
	local myLands: { [number]: boolean } = {}
	local landsAt = -math.huge
	local function overSea(cell: number): boolean
		if sea == nil then
			sea = Naval.buildSea(map, provinces)
		end
		local s = sea :: Naval.SeaMap
		local now = os.clock()
		if now - landsAt > 1 then
			landsAt = now
			table.clear(myLands)
			for _, p in provinces.list do
				if ClientState.ownerAt(cs, p.center) == cs.myNation then
					myLands[Naval.landAt(s, p.center)] = true
				end
			end
		end
		local island = Naval.landAt(s, cell)
		return island ~= 0 and not myLands[island]
	end

	local function nationName(id: number): string
		local n = cs.nations[id]
		return if n == nil then "?" elseif lang == "en" then n.nameEn else n.name
	end

	local function describe(cell: number, percent: number): string
		local t = MapDataModule.getTerrain(map, cell)
		local terrain = Strings.get("terrain." .. (terrainNames[t] or "?"), lang)
		local owner = ClientState.ownerAt(cs, cell)
		local who = if owner == 0 then Strings.get("tip.neutral", lang) else nationName(owner)
		local p = provinces.list[MapDataModule.getProvince(map, cell)]
		local where = if p ~= nil then (if lang == "en" then p.nameEn else p.name) else ""
		local head = string.format("<b>%s</b> · %s", who, terrain)
		if where ~= "" then
			head ..= string.format(' <font color="%s">· %s</font>', muted, where)
		end
		-- Что сделает клик (как MatchHud.tapCell).
		local action: string? = nil
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		local mine = if me ~= nil then ClientState.statsOf(cs, me.id) else nil
		if cs.phase ~= "Play" or me == nil or not me.alive or mine == nil or not Config.Terrain[t].borderPassable then
			action = nil
		elseif owner == me.id then
			action = string.format('<font color="%s">%s</font>', muted, Strings.get("tip.yours", lang))
		elseif owner ~= 0 and ClientState.warBetween(cs, me.id, owner) == nil then
			action = string.format('<font color="%s">%s</font>', alert, Strings.get("tip.declare", lang))
		elseif owner ~= 0 and not (ClientState.warBetween(cs, me.id, owner) :: any).active then
			action = string.format('<font color="%s">%s</font>', muted, Strings.get("tip.mobilizing", lang))
		elseif overSea(cell) then
			action = string.format('<font color="%s">%s</font>', sky, Strings.get("tip.boat", lang))
		elseif owner == 0 then
			action = string.format(
				'<font color="%s">%s</font>',
				gold,
				string.format(Strings.get("tip.expand", lang), short(mine.people * percent))
			)
		else
			action = string.format('<font color="%s">%s</font>', alert, Strings.get("tip.attack", lang))
		end
		return if action ~= nil then head .. "\n" .. action else head
	end

	local lastCell = -1
	local function show(cell: number?, x: number, y: number, percent: number)
		if cell == nil then
			box.Visible = false
			lastCell = -1
			return
		end
		if cell ~= lastCell then
			lastCell = cell
			text.Text = describe(cell, percent)
		end
		box.Position = UDim2.fromOffset(x + 18, y + 18)
		box.Visible = true
	end

	return { show = show }
end

return table.freeze(MapTooltip)
