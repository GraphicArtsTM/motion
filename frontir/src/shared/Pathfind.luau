--!strict
--[[
	Pathfind — путь сухопутной армии по клеткам (A*). Чистый модуль.
	- 8 направлений; по диагонали нельзя «срезать угол» через воду (оба соседних шага должны быть сушей).
	- Стоимость шага = длина шага / множитель скорости армий на клетке назначения (Config.Terrain.armySpeed):
	  горы и реки дороже, поэтому путь их обходит, если обход не слишком длинный.
	- Вода (armySpeed = 0) непроходима: флот и десант — этап 7.
	- Поиск ограничен Config.Armies.PathMaxNodes клетками — дальше «пути нет».
]]

local Config = require("./Config")
local Heap = require("./Heap")
local MapData = require("./MapData")

type MapData = MapData.MapData

local Pathfind = {}

local SQRT2 = math.sqrt(2)

local function speedAt(map: MapData, i: number): number
	return Config.Terrain[MapData.getTerrain(map, i)].armySpeed
end

function Pathfind.passable(map: MapData, i: number): boolean
	return i >= 0 and i < map.width * map.height and speedAt(map, i) > 0
end

-- Путь от from до to: список клеток без from, с to в конце. nil — пути нет.
function Pathfind.find(map: MapData, from: number, to: number, maxNodes: number?): { number }?
	if from == to then
		return {}
	end
	if not Pathfind.passable(map, from) or not Pathfind.passable(map, to) then
		return nil
	end
	local limit = maxNodes or Config.Armies.PathMaxNodes
	local w = map.width
	local size = map.width * map.height
	local tx, ty = to % w, to // w
	local maxSpeed = 0
	for _, stats in Config.Terrain do
		maxSpeed = math.max(maxSpeed, stats.armySpeed)
	end
	local function heuristic(i: number): number
		local dx, dy = math.abs(i % w - tx), math.abs(i // w - ty)
		local diag = math.min(dx, dy)
		return ((dx + dy - 2 * diag) + diag * SQRT2) / maxSpeed
	end

	local gScore: { [number]: number } = { [from] = 0 }
	local cameFrom: { [number]: number } = {}
	local closed: { [number]: boolean } = {}
	local open = Heap.new(256)
	Heap.push(open, heuristic(from), from)
	local expanded = 0
	while not Heap.isEmpty(open) do
		local i = Heap.pop(open)
		if i == to then
			local path: { number } = {}
			local c = to
			while c ~= from do
				table.insert(path, c)
				c = cameFrom[c]
			end
			-- Разворачиваем: от первого шага к цели.
			local n = #path
			for k = 1, n // 2 do
				path[k], path[n - k + 1] = path[n - k + 1], path[k]
			end
			return path
		end
		if not closed[i] then
			closed[i] = true
			expanded += 1
			if expanded > limit then
				return nil
			end
			local x, y = i % w, i // w
			local gi = gScore[i]
			for dy = -1, 1 do
				for dx = -1, 1 do
					if dx ~= 0 or dy ~= 0 then
						local nx, ny = x + dx, y + dy
						if nx >= 0 and ny >= 0 and nx < w and ny < map.height then
							local j = ny * w + nx
							local diagonal = dx ~= 0 and dy ~= 0
							local ok = not closed[j] and speedAt(map, j) > 0
							if ok and diagonal then
								ok = speedAt(map, y * w + nx) > 0 and speedAt(map, ny * w + x) > 0
							end
							if ok and j < size then
								local step = (if diagonal then SQRT2 else 1) / speedAt(map, j)
								local ng = gi + step
								local old = gScore[j]
								if old == nil or ng < old then
									gScore[j] = ng
									cameFrom[j] = i
									Heap.push(open, ng + heuristic(j), j)
								end
							end
						end
					end
				end
			end
		end
	end
	return nil
end

return table.freeze(Pathfind)
