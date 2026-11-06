--!strict
--[[
	Buildings — здания (GDD §6.9, этап 4б). Чистый модуль: где можно строить, что стоит, кому что принадлежит.

	- Здание стоит в клетке: обычное — на любой своей клетке суши (§15г; не ближе Build.MinGap к другим зданиям
	  и городам), «Город» — улучшение города в его клетке. Проверка общая для сервера и «призрака» на клиенте.
	- Владелец здания — владелец его клетки по сетке: провинция сменила хозяина — здание тоже.
	- Экономика 2.0 (§15д): ограничения числа зданий нет; каждое следующее здание того же типа дороже на
	  Build.CostStep (уровни считаются, по тому, что у державы есть сейчас); уровни до maxLevel (нажатие своим
	  зданием того же типа на него — улучшение); содержание; район города (Build.DistrictRadius) усиливает здание.
	- Нефтяная вышка — только в провинции с нефтяным полем; порт — у воды.
	- Город ур. 1 — любой город на карте (столица тоже); улучшения до Economy.MaxCityLevel.
]]

local Config = require("./Config")
local Grid = require("./Grid")
local MapData = require("./MapData")
local Provinces = require("./Provinces")
local Types = require("./Types")

type Grid = Grid.Grid
type Building = Types.Building

export type BuildingSet = {
	byCell: { [number]: Building },
	byProvince: { [number]: number }, -- провинция → клетка последнего обычного здания в ней (есть ли здание)
	forts: { [number]: { number } }, -- провинция → клетки укреплений в ней
	changed: { Building }, -- изменения с прошлой рассылки
}

-- Что у державы есть: для дохода, найма и ботов. Счётчики — число зданий; «сила» — с уровнями и районами.
export type Owned = {
	factories: number,
	markets: number,
	rigs: number,
	forts: number,
	ports: number, -- §6.12
	airfields: number, -- §6.13
	silos: number, -- ракетные шахты (§6.9, этап 7г)
	sams: number, -- ЗРК (§15з)
	cityLevels: number, -- сумма уровней своих городов
	-- Экономика 2.0 (§15д)
	barracks: number, -- число казарм
	barracksLevel: number, -- лучший уровень казарм (открывает танки и ПВО)
	recruitLines: number, -- линий найма от казарм (сумма уровней)
	housing: number, -- число жилых кварталов
	housingPeople: number, -- + к максимуму людей (с районами)
	factoryIncome: number, -- денег в секунду от заводов (с районами)
	marketBonus: number, -- доля к доходу от рынков (с районами), складывается
	rigOil: number, -- множитель нефти вышек (сумма по уровням)
	upkeep: number, -- содержание зданий, денег в секунду
}

local Buildings = {}

function Buildings.new(): BuildingSet
	return { byCell = {}, byProvince = {}, forts = {}, changed = {} }
end

function Buildings.emptyOwned(): Owned
	return {
		factories = 0,
		markets = 0,
		rigs = 0,
		forts = 0,
		ports = 0,
		airfields = 0,
		silos = 0,
		sams = 0, -- §15з
		cityLevels = 0,
		barracks = 0,
		barracksLevel = 0,
		recruitLines = 0,
		housing = 0,
		housingPeople = 0,
		factoryIncome = 0,
		marketBonus = 0,
		rigOil = 0,
		upkeep = 0,
	}
end

-- До какого уровня улучшается здание kind (§15д).
function Buildings.maxLevel(kind: string): number
	if kind == "City" then
		return Config.Economy.MaxCityLevel
	end
	local stats = (Config.Buildings :: any)[kind]
	return if stats ~= nil and stats.maxLevel ~= nil then stats.maxLevel else 1
end

-- Сумма уровней зданий kind державы nation (для роста цены, §15д).
function Buildings.levelsOf(set: BuildingSet, ownerAt: (cell: number) -> number, nation: number, kind: string): number
	local n = 0
	for cell, b in set.byCell do
		if b.kind == kind and ownerAt(cell) == nation then
			n += b.level
		end
	end
	return n
end

-- Цена нового своего города (§15д ч.4): founded — сколько основанных городов у державы сейчас.
function Buildings.foundPrice(founded: number): number
	return Config.Cities.FoundCost * (1 + Config.Cities.FoundStep * founded)
end

-- Цена здания kind (нового или следующего уровня), когда у державы уже levels уровней этого типа (§15д).
function Buildings.priceFor(kind: string, nextLevel: number, levels: number): number
	local stats = (Config.Buildings :: any)[kind]
	local mul = Config.Build.UpgradeMul[nextLevel] or Config.Build.UpgradeMul[#Config.Build.UpgradeMul]
	return stats.cost * mul * (1 + Config.Build.CostStep * levels)
end

-- Уровень города в клетке (1, если не улучшали).
function Buildings.cityLevel(set: BuildingSet, cell: number): number
	local b = set.byCell[cell]
	return if b ~= nil and b.kind == "City" then b.level else 1
end

-- Цена постройки: деньги и нефть. Для «Города» — цена следующего уровня (nil — дальше некуда). Обычное здание:
-- новое или улучшение стоящего в cell (§15д); levels — сумма уровней этого типа у державы (рост цены).
function Buildings.cost(set: BuildingSet, kind: Types.BuildingKind, cell: number, levels: number?): (number?, number)
	local stats = (Config.Buildings :: any)[kind]
	if kind == "City" then
		local level = Buildings.cityLevel(set, cell)
		if level >= Config.Economy.MaxCityLevel then
			return nil, 0
		end
		return if level == 1 then stats.cost else stats.upgradeCosts[level - 1], 0
	end
	local b = set.byCell[cell]
	local nextLevel = if b ~= nil and b.kind == kind then b.level + 1 else 1
	if nextLevel > Buildings.maxLevel(kind) then
		return nil, 0
	end
	return Buildings.priceFor(kind, nextLevel, levels or 0), if nextLevel == 1 then stats.oil or 0 else 0
end

-- Множество зданий из списка (клиент: «призрак» стройки проверяет тем же Buildings.check).
function Buildings.fromList(list: { [any]: Building }, map: MapData.MapData): BuildingSet
	local set = Buildings.new()
	for _, b in list do
		set.byCell[b.cell] = b
		if b.kind ~= "City" then
			local p = MapData.getProvince(map, b.cell)
			if p ~= 0 then
				set.byProvince[p] = b.cell
				if b.kind == "Fort" then
					local list2 = set.forts[p] or {}
					table.insert(list2, b.cell)
					set.forts[p] = list2
				end
			end
		end
	end
	return set
end

-- Радиус действия здания в клетках для круга у «призрака» стройки (§15г); nil — круга нет.
function Buildings.rangeOf(kind: string, mapWidth: number): number?
	if kind == "Radar" then
		return Config.Fog.RadarVision
	elseif kind == "AirDefense" then
		return Config.Buildings.AirDefense.radius
	elseif kind == "Sam" then
		return Config.Buildings.Sam.radius * mapWidth / Config.UnitsReferenceMapWidth
	elseif kind == "Airfield" then
		return Config.Air.Range * mapWidth / Config.UnitsReferenceMapWidth
	end
	return nil
end

-- Клетка у воды (порт ставят на берег, §15г).
function Buildings.coastal(map: MapData.MapData, cell: number): boolean
	local w, h = map.width, map.height
	local x, y = cell % w, cell // w
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local nx, ny = x + d[1], y + d[2]
		if
			nx >= 0
			and ny >= 0
			and nx < w
			and ny < h
			and MapData.getTerrain(map, ny * w + nx) == Types.Terrain.Water
		then
			return true
		end
	end
	return false
end

-- Можно ли державе nation построить kind по нажатию на клетку cell. Возвращает клетку здания или причину.
-- ownerAt — владелец клетки (сервер — сетка, клиент — его копия).
function Buildings.check(
	set: BuildingSet,
	ownerAt: (cell: number) -> number,
	map: MapData.MapData,
	provinces: Provinces.ProvinceSet,
	isCity: (cell: number) -> boolean,
	nation: number,
	kind: Types.BuildingKind,
	cell: number,
	hasDock: ((province: number) -> boolean)?, -- есть ли у провинции выход к морю (порт, §6.12)
	allowed: ((kind: Types.BuildingKind) -> boolean)? -- открыто ли здание технологией (§6.14)
): (number?, string?)
	if cell < 0 or cell >= map.width * map.height then
		return nil, "focus"
	end
	if table.find(Config.Buildable, kind) == nil then
		return nil, "notYet"
	end
	if allowed ~= nil and not allowed(kind) then
		return nil, "needTech"
	end
	if kind == "City" then
		-- Свой город (±1 клетка) — улучшение; своя земля без города рядом — основать новый (§15д ч.4).
		local w0, h0 = map.width, map.height
		local x0, y0 = cell % w0, cell // w0
		for dy = -1, 1 do
			for dx = -1, 1 do
				local nx, ny = x0 + dx, y0 + dy
				if nx >= 0 and ny >= 0 and nx < w0 and ny < h0 and isCity(ny * w0 + nx) then
					local c = ny * w0 + nx
					if ownerAt(c) ~= nation then
						return nil, "needCity"
					end
					if Buildings.cityLevel(set, c) >= Config.Economy.MaxCityLevel then
						return nil, "maxLevel"
					end
					return c, nil
				end
			end
		end
		local terrain = MapData.getTerrain(map, cell)
		if
			terrain == Types.Terrain.Water
			or terrain == Types.Terrain.River
			or MapData.getProvince(map, cell) == 0
			or ownerAt(cell) ~= nation
		then
			return nil, "notOwner"
		end
		local far = Config.Cities.FoundMinDistance
		for dy = -far, far do
			for dx = -far, far do
				local nx, ny = x0 + dx, y0 + dy
				if nx >= 0 and ny >= 0 and nx < w0 and ny < h0 and dx * dx + dy * dy < far * far then
					if isCity(ny * w0 + nx) then
						return nil, "cityTooClose"
					end
				end
			end
		end
		local gap = Config.Build.MinGap - 1
		for dy = -gap, gap do
			for dx = -gap, gap do
				local nx, ny = x0 + dx, y0 + dy
				if nx >= 0 and ny >= 0 and nx < w0 and ny < h0 and set.byCell[ny * w0 + nx] ~= nil then
					return nil, "tooClose"
				end
			end
		end
		return cell, nil
	end
	-- Своё здание того же типа рядом с нажатием (±1 клетка) — улучшение (§15д).
	local w, h = map.width, map.height
	local x, y = cell % w, cell // w
	for dy = -1, 1 do
		for dx = -1, 1 do
			local nx, ny = x + dx, y + dy
			if nx >= 0 and ny >= 0 and nx < w and ny < h then
				local j = ny * w + nx
				local b = set.byCell[j]
				if b ~= nil and b.kind == kind and ownerAt(j) == nation then
					if b.level >= Buildings.maxLevel(kind) then
						return nil, "maxLevel"
					end
					return j, nil
				end
			end
		end
	end
	local id = MapData.getProvince(map, cell)
	local province = if id ~= 0 then provinces.list[id] else nil
	if province == nil or MapData.getTerrain(map, cell) == Types.Terrain.Water or ownerAt(cell) ~= nation then
		return nil, "notOwner"
	end
	if kind == "OilRig" and not province.oil then
		return nil, "needOil"
	end
	if kind == "Port" and (hasDock == nil or not hasDock(id) or not Buildings.coastal(map, cell)) then
		return nil, "needCoast"
	end
	-- Не ближе MinGap к другим зданиям и городам (значки не налезают).
	local gap = Config.Build.MinGap - 1
	for dy = -gap, gap do
		local ny = y + dy
		if ny >= 0 and ny < h then
			for dx = -gap, gap do
				local nx = x + dx
				if nx >= 0 and nx < w then
					local j = ny * w + nx
					if set.byCell[j] ~= nil or isCity(j) then
						return nil, "tooClose"
					end
				end
			end
		end
	end
	return cell, nil
end

-- Ставит здание в клетке spot провинции province; своё того же типа там уже стоит — следующий уровень (§15д),
-- «Город» — улучшение города.
function Buildings.place(set: BuildingSet, kind: Types.BuildingKind, spot: number, province: number)
	local b: Building
	local old = set.byCell[spot]
	if kind == "City" then
		b = { kind = "City", cell = spot, level = Buildings.cityLevel(set, spot) + 1 }
	elseif old ~= nil and old.kind == kind then
		b = { kind = kind, cell = spot, level = old.level + 1 }
	else
		b = { kind = kind, cell = spot, level = 1 }
		set.byProvince[province] = spot
		if kind == "Fort" then
			local list = set.forts[province] or {}
			table.insert(list, spot)
			set.forts[province] = list
		end
	end
	set.byCell[spot] = b
	table.insert(set.changed, b)
end

-- Уровень здания в клетке сменился (удар, захват — §15д ч.3); 0 — снести.
function Buildings.setLevel(set: BuildingSet, cell: number, level: number, province: number)
	local b = set.byCell[cell]
	if b == nil then
		return
	end
	if level <= 0 then
		Buildings.remove(set, cell, province)
		return
	end
	local nb: Building = { kind = b.kind, cell = cell, level = level }
	set.byCell[cell] = nb
	table.insert(set.changed, nb)
end

-- Здание исчезло (снос, §15д; клетка ушла под воду — «Потоп», §5.3).
function Buildings.remove(set: BuildingSet, cell: number, province: number)
	local b = set.byCell[cell]
	if b == nil then
		return
	end
	set.byCell[cell] = nil
	if set.byProvince[province] == cell then
		set.byProvince[province] = nil
	end
	local forts = set.forts[province]
	if forts ~= nil then
		local k = table.find(forts, cell)
		if k ~= nil then
			table.remove(forts, k)
		end
	end
	-- Клиентам: уровень 0 — здание снесено.
	table.insert(set.changed, { kind = b.kind, cell = cell, level = 0 })
end

-- Забирает изменения для рассылки.
function Buildings.takeChanges(set: BuildingSet): { Building }
	local out = set.changed
	set.changed = {}
	return out
end

-- Все здания списком (для новых игроков).
function Buildings.list(set: BuildingSet): { Building }
	local out: { Building } = {}
	for _, b in set.byCell do
		table.insert(out, b)
	end
	table.sort(out, function(a: Building, b: Building): boolean
		return a.cell < b.cell
	end)
	return out
end

-- Что у каждой державы: здания по владельцу клетки и уровни городов (cities — клетки всех городов).
-- off(cell) — здание выведено из строя (налёт, §6.13): не работает, но содержание платится.
-- Район (§15д): здание не дальше Build.DistrictRadius от своего города — эффект × (1 + DistrictPerCityLevel × ур.).
function Buildings.owned(
	set: BuildingSet,
	g: Grid,
	cities: { number },
	off: ((cell: number) -> boolean)?
): { [number]: Owned }
	local cfg = Config.Build
	local out: { [number]: Owned } = {}
	local function of(owner: number): Owned
		local o = out[owner]
		if o == nil then
			o = Buildings.emptyOwned()
			out[owner] = o
		end
		return o
	end
	-- Города по корзинам R×R: район ищется в 3×3 соседних корзинах.
	local r = cfg.DistrictRadius
	local w = g.width
	local buckets: { [number]: { number } } = {}
	local bw = w // r + 1
	for _, cell in cities do
		local owner = Grid.getOwner(g, cell)
		if owner ~= 0 then
			local o = of(owner)
			o.cityLevels += Buildings.cityLevel(set, cell)
			local key = (cell // w) // r * bw + (cell % w) // r
			local list = buckets[key] or {}
			table.insert(list, cell)
			buckets[key] = list
		end
	end
	local function district(cell: number, owner: number): number
		local x, y = cell % w, cell // w
		local bx, by = x // r, y // r
		local best = 0
		for dy = -1, 1 do
			for dx = -1, 1 do
				local list = buckets[(by + dy) * bw + bx + dx]
				if list ~= nil then
					for _, c in list do
						local cx, cy = c % w, c // w
						if math.abs(cx - x) <= r and math.abs(cy - y) <= r and Grid.getOwner(g, c) == owner then
							best = math.max(best, Buildings.cityLevel(set, c))
						end
					end
				end
			end
		end
		return 1 + cfg.DistrictPerCityLevel * best
	end
	local stats = Config.Buildings :: any
	for cell, b in set.byCell do
		local owner = Grid.getOwner(g, cell)
		if owner == 0 or b.kind == "City" then
			continue
		end
		local o = of(owner)
		o.upkeep += stats[b.kind].cost * cfg.UpkeepShare * b.level
		if off ~= nil and off(cell) then
			continue
		end
		if b.kind == "Factory" then
			o.factories += 1
			o.factoryIncome += stats.Factory.income * b.level * district(cell, owner)
		elseif b.kind == "Market" then
			o.markets += 1
			o.marketBonus += stats.Market.incomeBonus * district(cell, owner)
		elseif b.kind == "Housing" then
			o.housing += 1
			o.housingPeople += stats.Housing.people * b.level * district(cell, owner)
		elseif b.kind == "Barracks" then
			o.barracks += 1
			o.barracksLevel = math.max(o.barracksLevel, b.level)
			o.recruitLines += b.level
		elseif b.kind == "OilRig" then
			o.rigs += 1
			o.rigOil += stats.OilRig.oilByLevel[b.level] or 1
		elseif b.kind == "Fort" then
			o.forts += 1
		elseif b.kind == "Port" then
			o.ports += 1
		elseif b.kind == "Airfield" then
			o.airfields += 1
		elseif b.kind == "MissileSilo" then
			o.silos += 1
		elseif b.kind == "Sam" then
			o.sams += 1
		end
	end
	return out
end

-- Оборона укрепления в провинции клетки cell, принадлежащего её владельцу (§6.9; ур. 2 — сильнее, §15д).
-- 1 — укрепления нет. off(cell) — укрепление выведено из строя.
function Buildings.fortMul(
	set: BuildingSet,
	g: Grid,
	map: MapData.MapData,
	cell: number,
	off: ((cell: number) -> boolean)?
): number
	local forts = set.forts[MapData.getProvince(map, cell)]
	if forts == nil then
		return 1
	end
	local owner = Grid.getOwner(g, cell)
	local best = 1
	for _, spot in forts do
		local b = set.byCell[spot]
		if b ~= nil and b.kind == "Fort" and Grid.getOwner(g, spot) == owner and not (off ~= nil and off(spot)) then
			best =
				math.max(best, Config.Buildings.Fort.defenseByLevel[b.level] or Config.Buildings.Fort.defenseMultiplier)
		end
	end
	return best
end

-- Есть ли укрепление в провинции клетки cell, принадлежащее её владельцу (оборона ×1.5, §6.9).
function Buildings.fortified(set: BuildingSet, g: Grid, map: MapData.MapData, cell: number): boolean
	return Buildings.fortMul(set, g, map, cell) > 1
end

-- Содержание здания kind ур. level в секунду (§15д).
function Buildings.upkeepOf(kind: string, level: number): number
	local stats = (Config.Buildings :: any)[kind]
	return if stats ~= nil then stats.cost * Config.Build.UpkeepShare * level else 0
end

-- Сколько вернёт снос здания (§15д): доля цены всех его уровней без роста цены.
function Buildings.refundOf(b: Building): number
	if b.kind == "City" then
		return 0
	end
	local total = 0
	for level = 1, b.level do
		total += Buildings.priceFor(b.kind, level, 0)
	end
	return total * Config.Build.DemolishRefund
end

return table.freeze(Buildings)
