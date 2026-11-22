--!strict
--[[
	Logistics — сводка режима карты «Логистика» (§15ч Ч5б). Чистый модуль: что видит игрок о своей сети.
	- Станции — свои города, заводы, порты, вышки (работающие: выведенные из строя и стройки не считаются).
	- В сети — станции главной сети (дорога до столицы); без дороги — остальные (по порядку клеток, для кнопки
	  «Показать станцию без дороги»).
	- Водные пути, стыки с союзниками, свои разрушенные мосты, свои поезда в пути — числа для плашки.
]]

local Logistics = {}

export type Station = { cell: number, kind: string }
export type Input = {
	stations: { Station },
	connected: { [number]: boolean }, -- станции главной сети
	waterways: number,
	sealines: number?, -- §15ч Ч6: морские линии
	junctions: number,
	broken: number,
	trains: number,
}
export type Summary = {
	total: number,
	connected: number,
	offline: { number }, -- станции без дороги к столице, по порядку клеток
	waterways: number,
	sealines: number,
	junctions: number,
	broken: number,
	trains: number,
}

function Logistics.summary(input: Input): Summary
	local offline: { number } = {}
	local on = 0
	for _, s in input.stations do
		if input.connected[s.cell] then
			on += 1
		else
			table.insert(offline, s.cell)
		end
	end
	table.sort(offline)
	return {
		total = #input.stations,
		connected = on,
		offline = offline,
		waterways = input.waterways,
		sealines = input.sealines or 0,
		junctions = input.junctions,
		broken = input.broken,
		trains = input.trains,
	}
end

return table.freeze(Logistics)
