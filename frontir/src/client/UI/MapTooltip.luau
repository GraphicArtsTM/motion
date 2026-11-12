--!strict
--[[
	MapTooltip — подсказка при наведении на карту (§15е ч.1, только мышь): чья земля, местность, провинция и
	ЧТО СДЕЛАЕТ КЛИК — «расширение с N людьми», «атака», «объявить войну», «десант на корабле», «ваша земля».
	Над соседом — прогноз до атаки (§15н ч.2, AttackPreview): перевес с ползунком, состояние, причина, сколько нужно.
	Правила те же, что у MatchHud.tapCell и сервера (десант — суша на другом массиве, как MatchSim.overSea:
	берём массивы суши, где у нас есть центр провинции). Над окнами интерфейса и в режиме стройки — не видна.
	§15у: враг за союзником с полным доверием (общей границы у курсора нет) — «Удар через союзника X (~N с)» (Passage).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AttackPreview = require(Shared:WaitForChild("AttackPreview"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local FrontForecast = require(Shared:WaitForChild("FrontForecast"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local Naval = require(Shared:WaitForChild("Naval"))
local Passage = require(Shared:WaitForChild("Passage"))
local Buildings = require(Shared:WaitForChild("Buildings"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local StrikeForecast = require(Shared:WaitForChild("StrikeForecast"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState

export type MapTooltip = {
	show: (cell: number?, x: number, y: number, percent: number) -> (), -- cell nil — спрятать
	-- §15х: чем целимся сейчас (nil — ничем): подсказка показывает прогноз «собьют / дойдёт».
	setAiming: (aiming: () -> StrikeForecast.Kind?) -> (),
	-- §15х: прогноз удара по клетке (nil — не целимся или нечего показать) — для кругов защиты на карте.
	forecast: (cell: number) -> StrikeForecast.Result?,
	-- §15х ч.2: здание или город под курсором с кругом действия: радиус и цвет (nil — нет).
	rangeAt: (cell: number) -> (number?, Color3?),
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
		-- Ни одного своего центра провинции (начало матча, малая держава) — не знаем, где мы: не обещаем десант.
		if next(myLands) == nil then
			return false
		end
		local island = Naval.landAt(s, cell)
		return island ~= 0 and not myLands[island]
	end

	local function nationName(id: number): string
		local n = cs.nations[id]
		return if n == nil then "?" elseif lang == "en" then n.nameEn else n.name
	end

	local stateColor: { [string]: string } = {
		free = hex(Theme.color("Lime")),
		stalled = alert,
		slow = hex(Theme.color("Orange")),
		advance = hex(Theme.color("Lime")),
		breakthrough = gold,
	}
	-- §15н ч.2: прогноз удара по соседу owner у клетки cell (nil — у курсора нет общей границы или нет данных).
	local function preview(me: number, owner: number, cell: number, percent: number, atWar: boolean): string?
		local stats, forces = cs.stats, cs.myForces
		if stats == nil or forces == nil then
			return nil
		end
		local result = AttackPreview.compute({
			width = cs.width,
			height = cs.height,
			map = map,
			ownerAt = function(i: number): number
				return ClientState.ownerAt(cs, i)
			end,
			me = me,
			myKinds = forces.kinds,
			nations = stats.nations,
			attacks = stats.attacks,
			cities = cs.cities,
			friends = ClientState.trustFriendsOf(cs, me), -- §15у ч.2: снабжают города полного доверия
			buildings = cs.buildings,
		}, owner, cell, percent)
		if result == nil then
			return nil
		end
		local head, detail = FrontForecast.previewLines(result, atWar, lang)
		local out = string.format('<font color="%s">%s</font>', stateColor[result.state] or muted, head)
		if detail ~= nil then
			out ..= string.format('\n<font color="%s">%s</font>', muted, detail)
		end
		return out
	end

	-- §15у: путь через союзника с полным доверием к врагу owner у клетки cell (строка подсказки или nil).
	local cityCells: { [number]: boolean } = {}
	local cityList: { number }? = nil
	local function passageLine(me: number, owner: number, cell: number): string?
		local allies: { [number]: boolean } = {}
		for _, t in cs.diplo.treaties do
			if t.kind == "alliance" and t.trust then
				local other = if t.a == me then t.b elseif t.b == me then t.a else 0
				if other ~= 0 then
					allies[other] = true
				end
			end
		end
		if next(allies) == nil then
			return nil
		end
		if cityList ~= cs.cities then
			cityList = cs.cities
			table.clear(cityCells)
			for _, c in cs.cities do
				cityCells[c] = true
			end
		end
		local route = Passage.route({
			width = cs.width,
			height = cs.height,
			ownerAt = function(i: number): number
				return ClientState.ownerAt(cs, i)
			end,
			capturable = function(i: number): boolean
				local stats = Config.Terrain[MapDataModule.getTerrain(map, i)]
				return stats ~= nil and stats.borderPassable
			end,
			isCity = function(i: number): boolean
				return cityCells[i] == true
			end,
		}, me, owner, allies, cell)
		if route == nil then
			return nil
		end
		return string.format(
			'<font color="%s">%s</font>',
			sky,
			string.format(
				Strings.get("tooltip.passage", lang),
				nationName(route.ally),
				math.ceil(route.sec / math.max(cs.speed, 0.01))
			)
		)
	end

	-- §15х: прогноз удара по клетке тем, чем сейчас целимся.
	local aimingFn: () -> StrikeForecast.Kind? = function(): StrikeForecast.Kind?
		return nil
	end
	local function strikeForecast(cell: number): StrikeForecast.Result?
		local kind: StrikeForecast.Kind? = aimingFn()
		local me = cs.myNation
		if kind == nil or me == nil then
			return nil
		end
		local victim = ClientState.ownerAt(cs, cell)
		local defs: { StrikeForecast.Defense } = {}
		local batteries: { { cell: number, ready: number, max: number } } = cs.world.batteries or {}
		for _, b in batteries do
			local building = cs.buildings[b.cell]
			if building ~= nil then
				local kindName: string = building.kind
				local d: StrikeForecast.Defense =
					{ cell = b.cell, kind = kindName, ready = b.ready, max = b.max, level = building.level }
				table.insert(defs, d)
			end
		end
		local fighters: { StrikeForecast.Fighter } = {}
		for _, p in cs.air.planes do
			if p.kind == "Fighter" and p.owner ~= me and p.state ~= "based" then
				table.insert(fighters, { x = p.x, y = p.y })
			end
		end
		return StrikeForecast.compute({
			width = cs.width,
			cell = cell,
			kind = kind,
			victim = victim,
			ownerAt = function(i: number): number
				return ClientState.ownerAt(cs, i)
			end,
			friends = (if victim ~= 0 then ClientState.trustFriendsOf(cs, victim) else {}) :: { [number]: boolean },
			defenses = defs,
			fighters = fighters,
		})
	end
	local function strikeLine(cell: number): string?
		local f = strikeForecast(cell)
		if f == nil then
			return nil
		end
		local lines: { string } = {}
		if #f.covers == 0 then
			table.insert(
				lines,
				string.format('<font color="%s">%s</font>', hex(Theme.color("Lime")), Strings.get("strike.open", lang))
			)
		else
			local sams, aas = 0, 0
			for _, c in f.covers do
				if c.long then -- §15х ч.6: дальняя ПВО ур. 3
					sams += 1
				else
					aas += 1
				end
			end
			local what = string.format(Strings.get("strike.covered", lang), aas, sams, f.ready, f.need)
			table.insert(
				lines,
				string.format(
					'<font color="%s">%s</font>',
					if f.stopped then alert else gold,
					what .. "  " .. Strings.get(if f.stopped then "strike.stopped" else "strike.through", lang)
				)
			)
		end
		if f.fighters > 0 then
			table.insert(
				lines,
				string.format(
					'<font color="%s">%s</font>',
					gold,
					string.format(Strings.get("strike.fighters", lang), f.fighters)
				)
			)
		end
		return table.concat(lines, "\n")
	end

	-- §15х ч.2: что под курсором — здание (или город) и что оно делает; у защиты — заряды.
	local RANGE_COLORS: { [string]: string } = {
		AirDefense = "Orange",
		Airfield = "Gold",
		Port = "Sky",
		City = "Gold",
	}
	local function buildingAt(cell: number): string?
		local b = cs.buildings[cell]
		if b ~= nil then
			return b.kind
		end
		for _, c in cs.cities do
			if c == cell then
				return "City"
			end
		end
		return nil
	end
	local function rangeAt(cell: number): (number?, Color3?)
		local kind = buildingAt(cell)
		if kind == nil then
			return nil, nil
		end
		local b = cs.buildings[cell]
		local level = if b ~= nil then b.level else 1
		local r = Buildings.rangeOf(kind, cs.width, level)
		if r == nil then
			return nil, nil
		end
		-- §15х ч.6: дальняя ПВО (ур. 3) — голубой круг, ближняя — оранжевый.
		local long = kind == "AirDefense" and level >= Config.Buildings.AirDefense.longRangeLevel
		return r, Theme.color(if long then "Sky" else RANGE_COLORS[kind] or "Mist")
	end
	local function buildingLine(cell: number): string?
		local kind = buildingAt(cell)
		if kind == nil then
			return nil
		end
		local b = cs.buildings[cell]
		local name = Strings.get("building." .. kind, lang)
		if b ~= nil and b.level > 1 then
			name ..= string.format(" · " .. Strings.get("range.level", lang), b.level)
		end
		local line = string.format(
			'<font color="%s"><b>%s</b></font>  %s',
			gold,
			name,
			Strings.get(
				if kind == "AirDefense"
						and b ~= nil
						and b.level >= Config.Buildings.AirDefense.longRangeLevel
					then "range.AirDefenseLong"
					else "range." .. kind,
				lang
			)
		)
		local batteries: { { cell: number, ready: number, max: number } } = cs.world.batteries or {}
		for _, bt in batteries do
			if bt.cell == cell then
				line ..= string.format(
					'\n<font color="%s">%s</font>',
					if bt.ready > 0 then sky else alert,
					string.format(Strings.get("range.charges", lang), bt.ready, bt.max)
				)
			end
		end
		return line
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
		-- §15ф Ф1: выбор старта — соседей рядом (чужие столицы в радиусе) и какое начало.
		if cs.phase == "Pick" and Config.Terrain[t].borderPassable then
			if owner ~= 0 then
				return head .. string.format('\n<font color="%s">%s</font>', muted, Strings.get("tip.pickTaken", lang))
			end
			local w = cs.width
			local r = Config.Start.NeighbourCells * w / Config.UnitsReferenceMapWidth
			local cx, cy = cell % w, cell // w
			local near = 0
			for id, n in cs.nations do
				local cap = n.capital
				if cap ~= nil and id ~= cs.myNation and (cap % w - cx) ^ 2 + (cap // w - cy) ^ 2 <= r * r then
					near += 1
				end
			end
			local calm = near <= Config.Start.CalmNeighbours
			return head
				.. string.format(
					'\n<font color="%s">%s</font>',
					if calm then hex(Theme.color("Lime")) else hex(Theme.color("Orange")),
					string.format(Strings.get(if calm then "tip.pickCalm" else "tip.pickCrowded", lang), near)
				)
				.. string.format('\n<font color="%s">%s</font>', gold, Strings.get("tip.pickHere", lang))
		end
		-- §15х: целимся ракетой, бомбой или налётом — вместо «что сделает клик» прогноз удара.
		local strike = if cs.phase == "Play" then strikeLine(cell) else nil
		if strike ~= nil then
			return head .. "\n" .. strike
		end
		-- §15х ч.2: здание или город — что делает (круг его действия рисует Main.client).
		local building = if cs.phase == "Play" then buildingLine(cell) else nil
		if building ~= nil then
			head ..= "\n" .. building
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
		-- Прогноз до атаки: сосед (не ничья земля, не за морем) — в войне, мобилизации и в мире.
		if action ~= nil and me ~= nil and owner ~= 0 and owner ~= me.id and not overSea(cell) then
			local war = ClientState.warBetween(cs, me.id, owner)
			local active = war ~= nil and (war :: any).active
			local line = preview(me.id, owner, cell, percent, active)
			if line ~= nil then
				action ..= "\n" .. line
			elseif active then
				-- Общей границы у курсора нет — может, через союзника с полным доверием (§15у).
				local via = passageLine(me.id, owner, cell)
				if via ~= nil then
					action ..= "\n" .. via
				end
			end
		end
		return if action ~= nil then head .. "\n" .. action else head
	end

	local lastCell, lastPercent, lastAt = -1, -1, 0
	local function show(cell: number?, x: number, y: number, percent: number)
		if cell == nil then
			box.Visible = false
			lastCell = -1
			return
		end
		-- Перерисовка: другая клетка, другой ползунок или раз в Forecast.PreviewRefreshSec (силы меняются).
		local now = os.clock()
		if cell ~= lastCell or percent ~= lastPercent or now - lastAt >= Config.Forecast.PreviewRefreshSec then
			lastCell, lastPercent, lastAt = cell, percent, now
			text.Text = describe(cell, percent)
		end
		box.Position = UDim2.fromOffset(x + 18, y + 18)
		box.Visible = true
	end

	return {
		show = show,
		setAiming = function(fn: () -> StrikeForecast.Kind?)
			aimingFn = fn
		end,
		forecast = strikeForecast,
		rangeAt = rangeAt,
	}
end

return table.freeze(MapTooltip)
