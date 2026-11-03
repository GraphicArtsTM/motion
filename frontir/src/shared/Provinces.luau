--!strict
--[[
	Provinces — данные провинций, вычисляемые из карты (GDD §6.5): клетки, центр, соседи, острова,
	названия и нейтральные города. Считается одинаково на сервере и клиенте из MapData и сида карты,
	поэтому по сети не передаётся (в карте хранится только id провинции у каждой клетки).
]]

local Config = require("./Config")
local MapData = require("./MapData")
local NameGen = require("./NameGen")
local Rng = require("./Rng")
local Types = require("./Types")

type MapData = MapData.MapData

export type Province = {
	id: number,
	cells: { number }, -- все клетки суши провинции (вместе с реками)
	capturable: number, -- клеток, которые можно захватить (суша без рек)
	center: number, -- захватываемая клетка ближе всего к центру масс
	neighbours: { number }, -- соседние провинции по суше
	island: boolean, -- соседей по суше нет
	name: string,
	nameEn: string,
	city: number?, -- клетка нейтрального города на старте матча
}

export type ProvinceSet = {
	count: number,
	list: { Province },
}

local Provinces = {}

function Provinces.idAt(map: MapData, i: number): number
	return MapData.getProvince(map, i)
end

function Provinces.build(map: MapData): ProvinceSet
	local w, h = map.width, map.height
	local list: { Province } = {}
	local count = 0
	local neighbourSets: { [number]: { [number]: boolean } } = {}
	for i = 0, w * h - 1 do
		local id = MapData.getProvince(map, i)
		if id ~= 0 then
			count = math.max(count, id)
			local p = list[id]
			if p == nil then
				p = {
					id = id,
					cells = {},
					capturable = 0,
					center = i,
					neighbours = {},
					island = true,
					name = "",
					nameEn = "",
					city = nil,
				}
				list[id] = p
				neighbourSets[id] = {}
			end
			table.insert(p.cells, i)
			if Config.Terrain[MapData.getTerrain(map, i)].borderPassable then
				p.capturable += 1
			end
			local x = i % w
			local function look(j: number)
				local o = MapData.getProvince(map, j)
				if o ~= 0 and o ~= id then
					neighbourSets[id][o] = true
				end
			end
			if x < w - 1 then
				look(i + 1)
			end
			if x > 0 then
				look(i - 1)
			end
			if i >= w then
				look(i - w)
			end
			if i + w < w * h then
				look(i + w)
			end
		end
	end

	local rng = Rng.new(map.seed + 7777)
	local taken: { [string]: boolean } = {}
	for id = 1, count do
		local p = list[id]
		-- Центр: захватываемая клетка, ближайшая к центру масс.
		local sx, sy, k = 0, 0, 0
		for _, i in p.cells do
			sx += i % w
			sy += i // w
			k += 1
		end
		local cx, cy = sx / k, sy / k
		local best, bestD = p.cells[1], math.huge
		for _, i in p.cells do
			if Config.Terrain[MapData.getTerrain(map, i)].borderPassable then
				local d = (i % w - cx) ^ 2 + (i // w - cy) ^ 2
				if d < bestD then
					best, bestD = i, d
				end
			end
		end
		p.center = best
		for o in neighbourSets[id] do
			table.insert(p.neighbours, o)
		end
		table.sort(p.neighbours)
		p.island = #p.neighbours == 0
		local name = NameGen.generate(rng, taken)
		taken[name.ru] = true
		p.name, p.nameEn = name.ru, name.en
	end

	-- Нейтральные города: доля провинций, не в горах, не ближе MinDistance друг к другу.
	local order: { number } = {}
	for id = 1, count do
		table.insert(order, id)
	end
	for k = #order, 2, -1 do
		local j = Rng.range(rng, 1, k)
		order[k], order[j] = order[j], order[k]
	end
	local want = math.floor(count * Config.Cities.ProvinceShare + 0.5)
	local cities: { number } = {}
	local minD = Config.Cities.MinDistance
	for _, id in order do
		if #cities >= want then
			break
		end
		local c = list[id].center
		if MapData.getTerrain(map, c) ~= Types.Terrain.Mountains then
			local ok = true
			for _, other in cities do
				if (c % w - other % w) ^ 2 + (c // w - other // w) ^ 2 < minD * minD then
					ok = false
					break
				end
			end
			if ok then
				table.insert(cities, c)
				list[id].city = c
			end
		end
	end

	return { count = count, list = list }
end

return table.freeze(Provinces)
