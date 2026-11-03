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

-- Заливка своих клеток державы от start с меткой mark (Grid.stamp), не заходя в клетки с меткой skip.
-- Клетки дописываются в out. Без замыканий и таблиц-множеств: на «Европе» держава — до 60 тыс. клеток.
local function flood(g: Grid, nation: number, start: number, mark: number, skip: number, out: { number })
	local w, size = g.width, g.size
	local owner, stamp = g.owner, g.stamp
	buffer.writeu32(stamp, start * 4, mark)
	table.insert(out, start)
	local head = #out
	while head <= #out do
		local i = out[head]
		head += 1
		local x = i % w
		for d = 1, 4 do
			local j = if d == 1
				then (if x > 0 then i - 1 else -1)
				elseif d == 2 then (if x < w - 1 then i + 1 else -1)
				elseif d == 3 then i - w
				else i + w
			if j >= 0 and j < size and buffer.readu16(owner, j * 2) == nation then
				local s = buffer.readu32(stamp, j * 4)
				if s ~= mark and s ~= skip then
					buffer.writeu32(stamp, j * 4, mark)
					table.insert(out, j)
				end
			end
		end
	end
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
	-- Всё, что связано со столицей.
	local connectedMark = Grid.newStamp(g)
	local connected: { number } = table.create(Grid.cellsOf(g, nation))
	flood(g, nation, capital, connectedMark, -1, connected) -- -1: ничего не пропускать (метки ≥ 0)
	if #connected >= Grid.cellsOf(g, nation) then
		return Pockets.empty()
	end
	-- Котлы: у каждого есть пограничная клетка (рядом чужая земля, вода или край карты).
	local pocketMark = Grid.newStamp(g)
	local result: NationPockets = { pockets = {}, inPocket = {}, cells = 0 }
	for i in Grid.borderCells(g, nation) do
		local s = buffer.readu32(g.stamp, i * 4)
		if s ~= connectedMark and s ~= pocketMark then
			local cells: { number } = {}
			flood(g, nation, i, pocketMark, connectedMark, cells)
			local index = #result.pockets + 1
			local hasCity = false
			local since = now
			for _, c in cells do
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
