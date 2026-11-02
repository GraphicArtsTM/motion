--!strict
--[[
	MapData — статичная карта: местность (1 байт на клетку) и id провинции (2 байта на клетку).
	Клетка (x, y) имеет индекс i = y * width + x, x и y считаются от нуля.
	Владельцы клеток (динамика матча) живут отдельно, в Grid (этап 2).
]]

export type MapData = {
	name: string,
	seed: number,
	width: number,
	height: number,
	terrain: buffer, -- u8 на клетку, значения Types.Terrain
	province: buffer, -- u16 на клетку, 0 — нет провинции (провинции появятся на этапе 3)
}

local MapData = {}

function MapData.new(name: string, seed: number, width: number, height: number): MapData
	assert(
		width > 0 and height > 0 and width <= 65535 and height <= 65535,
		"недопустимый размер карты"
	)
	return {
		name = name,
		seed = seed,
		width = width,
		height = height,
		terrain = buffer.create(width * height),
		province = buffer.create(width * height * 2),
	}
end

function MapData.cellCount(map: MapData): number
	return map.width * map.height
end

function MapData.index(map: MapData, x: number, y: number): number
	return y * map.width + x
end

function MapData.inBounds(map: MapData, x: number, y: number): boolean
	return x >= 0 and y >= 0 and x < map.width and y < map.height
end

function MapData.getTerrain(map: MapData, i: number): number
	return buffer.readu8(map.terrain, i)
end

function MapData.setTerrain(map: MapData, i: number, terrain: number)
	buffer.writeu8(map.terrain, i, terrain)
end

function MapData.getProvince(map: MapData, i: number): number
	return buffer.readu16(map.province, i * 2)
end

function MapData.setProvince(map: MapData, i: number, province: number)
	buffer.writeu16(map.province, i * 2, province)
end

-- Совпадают ли две карты побайтно (размер, местность, провинции).
function MapData.equals(a: MapData, b: MapData): boolean
	return a.width == b.width
		and a.height == b.height
		and buffer.tostring(a.terrain) == buffer.tostring(b.terrain)
		and buffer.tostring(a.province) == buffer.tostring(b.province)
end

-- Сколько клеток каждого типа местности: { [terrainId] = count }.
function MapData.terrainCounts(map: MapData): { [number]: number }
	local counts: { [number]: number } = {}
	for i = 0, map.width * map.height - 1 do
		local t = buffer.readu8(map.terrain, i)
		counts[t] = (counts[t] or 0) + 1
	end
	return counts
end

return table.freeze(MapData)
