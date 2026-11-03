--!strict
--[[
	Heap — двоичная мин-куча пар (ключ, значение) для Dijkstra и A*.
	При равных ключах первым выходит меньшее значение — порядок детерминирован (одинаков в Roblox и Lune).
]]

export type Heap = {
	keys: { number },
	values: { number },
	size: number,
}

local Heap = {}

function Heap.new(capacity: number?): Heap
	local c = capacity or 64
	return { keys = table.create(c), values = table.create(c), size = 0 }
end

local function less(h: Heap, a: number, b: number): boolean
	local ka, kb = h.keys[a], h.keys[b]
	if ka ~= kb then
		return ka < kb
	end
	return h.values[a] < h.values[b]
end

local function swap(h: Heap, a: number, b: number)
	h.keys[a], h.keys[b] = h.keys[b], h.keys[a]
	h.values[a], h.values[b] = h.values[b], h.values[a]
end

function Heap.push(h: Heap, key: number, value: number)
	local i = h.size + 1
	h.size = i
	h.keys[i] = key
	h.values[i] = value
	while i > 1 do
		local parent = i // 2
		if less(h, i, parent) then
			swap(h, i, parent)
			i = parent
		else
			break
		end
	end
end

-- Достаёт пару с наименьшим ключом: значение и ключ. Пустая куча — ошибка.
function Heap.pop(h: Heap): (number, number)
	assert(h.size > 0, "Heap.pop: куча пуста")
	local value, key = h.values[1], h.keys[1]
	local last = h.size
	h.keys[1], h.values[1] = h.keys[last], h.values[last]
	h.keys[last], h.values[last] = nil :: any, nil :: any
	h.size = last - 1
	local i = 1
	local n = h.size
	while true do
		local l, r = i * 2, i * 2 + 1
		local smallest = i
		if l <= n and less(h, l, smallest) then
			smallest = l
		end
		if r <= n and less(h, r, smallest) then
			smallest = r
		end
		if smallest == i then
			break
		end
		swap(h, i, smallest)
		i = smallest
	end
	return value, key
end

function Heap.isEmpty(h: Heap): boolean
	return h.size == 0
end

return table.freeze(Heap)
