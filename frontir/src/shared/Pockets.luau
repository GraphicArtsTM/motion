--!strict
--[[
	Pockets — котлы (GDD §6.7): куски земли державы, не связанные своей землёй со столицей.
	Чистый модуль. Связность считается заливкой от столицы по своим клеткам (4 соседа); всё остальное
	своё — котлы, сгруппированные по связности. Держава без столицы котлов не имеет (не от чего считать).
]]

local Grid = require("./Grid")

type Grid = Grid.Grid

export type Pocket = {
	cells: { number },
	hasCity: boolean,
	since: number, -- simTime, с которого кусок в котле (переносится между пересчётами)
}

export type NationPockets = {
	pockets: { Pocket },
	inPocket: { [number]: number }, -- клетка → номер котла
	cells: number, -- клеток в котлах
}

local Pockets = {}

function Pockets.empty(): NationPockets
	return { pockets = {}, inPocket = {}, cells = 0 }
end

-- Котлы державы nation. isCity(cell) — город ли клетка; previous — прошлый результат (сохраняет since).
function Pockets.compute(
	g: Grid,
	nation: number,
	capital: number?,
	isCity: (cell: number) -> boolean,
	now: number,
	previous: NationPockets?
): NationPockets
	if capital == nil or Grid.getOwner(g, capital) ~= nation then
		return Pockets.empty()
	end
	-- Все клетки державы: заливка от её границы (у каждого куска есть пограничная клетка).
	local all: { number } = {}
	local seen: { [number]: boolean } = {}
	local function flood(starts: { number }, mark: { [number]: boolean }, out: { number })
		local head = #out + 1
		for _, s in starts do
			if not mark[s] then
				mark[s] = true
				table.insert(out, s)
			end
		end
		while head <= #out do
			Grid.forNeighbours(g, out[head], function(j)
				if not mark[j] and Grid.getOwner(g, j) == nation then
					mark[j] = true
					table.insert(out, j)
				end
			end)
			head += 1
		end
	end
	local starts: { number } = {}
	for i in Grid.borderCells(g, nation) do
		table.insert(starts, i)
	end
	table.insert(starts, capital)
	flood(starts, seen, all)
	-- Связанные со столицей.
	local connected: { [number]: boolean } = {}
	flood({ capital }, connected, {})
	if #all == 0 then
		return Pockets.empty()
	end
	local result: NationPockets = { pockets = {}, inPocket = {}, cells = 0 }
	local grouped: { [number]: boolean } = {}
	for _, i in all do
		if not connected[i] and not grouped[i] then
			local cells: { number } = {}
			local mark: { [number]: boolean } = {}
			-- Заливка внутри котла: только свои клетки, не связанные со столицей.
			mark[i] = true
			table.insert(cells, i)
			local head = 1
			while head <= #cells do
				Grid.forNeighbours(g, cells[head], function(j)
					if not mark[j] and not connected[j] and Grid.getOwner(g, j) == nation then
						mark[j] = true
						table.insert(cells, j)
					end
				end)
				head += 1
			end
			local index = #result.pockets + 1
			local hasCity = false
			local since = now
			for _, c in cells do
				grouped[c] = true
				result.inPocket[c] = index
				if isCity(c) then
					hasCity = true
				end
				-- Кусок уже был в котле — время отсчитываем от того раза.
				if previous ~= nil then
					local old = previous.inPocket[c]
					if old ~= nil then
						since = math.min(since, previous.pockets[old].since)
					end
				end
			end
			result.cells += #cells
			table.insert(result.pockets, { cells = cells, hasCity = hasCity, since = since })
		end
	end
	return result
end

-- Кому сдаётся котёл: сосед, с которым идёт война (atWar), с самой длинной общей границей; 0 — некому.
function Pockets.captor(g: Grid, nation: number, pocket: Pocket, atWar: (other: number) -> boolean): number
	local border: { [number]: number } = {}
	for _, i in pocket.cells do
		Grid.forNeighbours(g, i, function(j)
			local o = Grid.getOwner(g, j)
			if o ~= 0 and o ~= nation and atWar(o) then
				border[o] = (border[o] or 0) + 1
			end
		end)
	end
	local best, bestLen = 0, 0
	for o, len in border do
		if len > bestLen or (len == bestLen and o < best) then
			best, bestLen = o, len
		end
	end
	return best
end

return table.freeze(Pockets)
