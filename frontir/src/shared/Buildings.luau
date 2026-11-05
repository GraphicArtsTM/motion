--!strict
--[[
	Buildings — здания (GDD §6.9, этап 4б). Чистый модуль: где можно строить, что стоит, кому что принадлежит.

	- Здание стоит в клетке: обычное — в центре провинции, «Город» — улучшение города в его клетке.
	- Владелец здания — владелец его клетки по сетке: провинция сменила хозяина — здание тоже.
	- В провинции одно здание (плюс город). Нефтяная вышка — только в провинции с нефтяным полем.
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
	byProvince: { [number]: number }, -- провинция → клетка обычного здания
	changed: { Building }, -- изменения с прошлой рассылки
}

-- Что у державы есть: для дохода, найма и ботов.
export type Owned = {
	factories: number,
	markets: number,
	rigs: number,
	forts: number,
	ports: number, -- §6.12
	airfields: number, -- §6.13
	silos: number, -- ракетные шахты (§6.9, этап 7г)
	cityLevels: number, -- сумма уровней своих городов
}

local Buildings = {}

function Buildings.new(): BuildingSet
	return { byCell = {}, byProvince = {}, changed = {} }
end

-- Уровень города в клетке (1, если не улучшали).
function Buildings.cityLevel(set: BuildingSet, cell: number): number
	local b = set.byCell[cell]
	return if b ~= nil and b.kind == "City" then b.level else 1
end

-- Цена постройки: деньги и нефть. Для «Города» — цена следующего уровня (nil — дальше некуда).
function Buildings.cost(set: BuildingSet, kind: Types.BuildingKind, cell: number): (number?, number)
	local stats = (Config.Buildings :: any)[kind]
	if kind == "City" then
		local level = Buildings.cityLevel(set, cell)
		if level >= Config.Economy.MaxCityLevel then
			return nil, 0
		end
		return if level == 1 then stats.cost else stats.upgradeCosts[level - 1], 0
	end
	return stats.cost, stats.oil or 0
end

-- Можно ли державе nation построить kind по нажатию на клетку cell. Возвращает клетку здания или причину.
function Buildings.check(
	set: BuildingSet,
	g: Grid,
	map: MapData.MapData,
	provinces: Provinces.ProvinceSet,
	isCity: (cell: number) -> boolean,
	nation: number,
	kind: Types.BuildingKind,
	cell: number,
	hasDock: ((province: number) -> boolean)?, -- есть ли у провинции выход к морю (порт, §6.12)
	allowed: ((kind: Types.BuildingKind) -> boolean)? -- открыто ли здание технологией (§6.14)
): (number?, string?)
	if cell < 0 or cell >= g.size then
		return nil, "focus"
	end
	if table.find(Config.Buildable, kind) == nil then
		return nil, "notYet"
	end
	if allowed ~= nil and not allowed(kind) then
		return nil, "needTech"
	end
	if kind == "City" then
		if not isCity(cell) or Grid.getOwner(g, cell) ~= nation then
			return nil, "needCity"
		end
		if Buildings.cityLevel(set, cell) >= Config.Economy.MaxCityLevel then
			return nil, "maxLevel"
		end
		return cell, nil
	end
	local id = MapData.getProvince(map, cell)
	local province = if id ~= 0 then provinces.list[id] else nil
	if province == nil then
		return nil, "notOwner"
	end
	local spot = province.center
	if Grid.getOwner(g, spot) ~= nation then
		return nil, "notOwner"
	end
	if set.byProvince[id] ~= nil then
		return nil, "occupied"
	end
	if kind == "OilRig" and not province.oil then
		return nil, "needOil"
	end
	if kind == "Port" and (hasDock == nil or not hasDock(id)) then
		return nil, "needCoast"
	end
	return spot, nil
end

-- Ставит здание (или поднимает уровень города) в клетке spot провинции id.
function Buildings.place(set: BuildingSet, kind: Types.BuildingKind, spot: number, province: number)
	local b: Building
	if kind == "City" then
		b = { kind = "City", cell = spot, level = Buildings.cityLevel(set, spot) + 1 }
	else
		b = { kind = kind, cell = spot, level = 1 }
		set.byProvince[province] = spot
	end
	set.byCell[spot] = b
	table.insert(set.changed, b)
end

-- Здание исчезло (клетка ушла под воду — «Потоп», §5.3). Клиенты узнают из полного списка в info.
function Buildings.remove(set: BuildingSet, cell: number, province: number)
	local b = set.byCell[cell]
	if b == nil then
		return
	end
	set.byCell[cell] = nil
	if set.byProvince[province] == cell then
		set.byProvince[province] = nil
	end
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
-- off(cell) — здание выведено из строя (налёт, §6.13): не считается.
function Buildings.owned(
	set: BuildingSet,
	g: Grid,
	cities: { number },
	off: ((cell: number) -> boolean)?
): { [number]: Owned }
	local out: { [number]: Owned } = {}
	local function of(owner: number): Owned
		local o = out[owner]
		if o == nil then
			o = { factories = 0, markets = 0, rigs = 0, forts = 0, ports = 0, airfields = 0, silos = 0, cityLevels = 0 }
			out[owner] = o
		end
		return o
	end
	for _, cell in cities do
		local owner = Grid.getOwner(g, cell)
		if owner ~= 0 then
			local o = of(owner)
			o.cityLevels += Buildings.cityLevel(set, cell)
		end
	end
	for cell, b in set.byCell do
		local owner = Grid.getOwner(g, cell)
		if owner ~= 0 and b.kind ~= "City" and off ~= nil and off(cell) then
			continue
		end
		if owner ~= 0 then
			local o = of(owner)
			if b.kind == "Factory" then
				o.factories += 1
			elseif b.kind == "Market" then
				o.markets += 1
			elseif b.kind == "OilRig" then
				o.rigs += 1
			elseif b.kind == "Fort" then
				o.forts += 1
			elseif b.kind == "Port" then
				o.ports += 1
			elseif b.kind == "Airfield" then
				o.airfields += 1
			elseif b.kind == "MissileSilo" then
				o.silos += 1
			end
		end
	end
	return out
end

-- Есть ли укрепление в провинции клетки cell, принадлежащее её владельцу (оборона ×1.5, §6.9).
function Buildings.fortified(set: BuildingSet, g: Grid, map: MapData.MapData, cell: number): boolean
	local spot = set.byProvince[MapData.getProvince(map, cell)]
	if spot == nil then
		return false
	end
	local b = set.byCell[spot]
	return b ~= nil and b.kind == "Fort" and Grid.getOwner(g, spot) == Grid.getOwner(g, cell)
end

return table.freeze(Buildings)
