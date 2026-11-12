--!strict
--[[
	ThreatMap — «Карта угроз» (§15х ч.4б, своя идея): что видно, когда игрок включает подсветку угроз.
	- Зоны: своя ПВО и ПВО друзей по полному доверию (ближний круг и дальний у ур. 3), ПВО врага (так же), куда летают
	  самолёты врага (Air.Range вокруг его работающих аэродромов), шахты врага (метка: ракеты бьют по всей карте).
	- «Дыры»: свои города и здания, которых ракета достанет без перехвата — ни одна своя или дружеская ПВО против
	  ракет их не накрывает (то же правило, что у сервера: StrikeForecast.radius, только ПВО с готовым или
	  восстанавливающимся зарядом — заряды не важны, важна дальность).
	Чистый модуль: клиент даёт здания, города, кто враг и кто друг.
]]

local Air = require("./Air")
local Config = require("./Config")
local StrikeForecast = require("./StrikeForecast")

export type ZoneKind = "myAA" | "myAALong" | "enemyAA" | "enemyAALong" | "enemyAir" | "enemySilo"

export type Building = { cell: number, kind: string, level: number, owner: number, off: boolean? }

export type Input = {
	width: number,
	me: number,
	friends: { [number]: boolean }, -- друзья по полному доверию (их ПВО прикрывает и нас)
	enemies: { [number]: boolean }, -- чьи угрозы показывать
	buildings: { Building },
	cities: { { cell: number, owner: number } },
}

export type Zone = { cell: number, radius: number, kind: ZoneKind }

export type Result = {
	zones: { Zone },
	holes: { number }, -- свои города и здания без защиты от ракет (по возрастанию клетки)
	targets: number, -- сколько своих городов и зданий всего
	enemySilos: number,
	enemyAirfields: number,
	enemyAA: number,
}

local ThreatMap = {}

-- Радиус метки шахты врага (клеток): ракета бьёт по всей карте, круг лишь показывает, где шахта.
ThreatMap.SiloMarkRadius = 3

function ThreatMap.compute(input: Input): Result
	local w = input.width
	local me = input.me
	local near = Config.Buildings.AirDefense.radius
	local longFrom = Config.Buildings.AirDefense.longRangeLevel
	local airReach = Config.Air.Range * Air.scale(w)
	local zones: { Zone } = {}
	local shields: { { cell: number, r: number } } = {} -- своя и дружеская ПВО против ракет
	local out: Result = { zones = zones, holes = {}, targets = 0, enemySilos = 0, enemyAirfields = 0, enemyAA = 0 }
	for _, b in input.buildings do
		local mine = b.owner == me or input.friends[b.owner] == true
		local enemy = not mine and input.enemies[b.owner] == true
		if b.off then
			continue -- выведено из строя — не защищает и не угрожает
		end
		if b.kind == "AirDefense" then
			local long = b.level >= longFrom
			local far = StrikeForecast.radius(b.level, w, true)
			if mine then
				table.insert(zones, { cell = b.cell, radius = near, kind = "myAA" })
				if long then
					table.insert(zones, { cell = b.cell, radius = far, kind = "myAALong" })
				end
				table.insert(shields, { cell = b.cell, r = far })
			elseif enemy then
				out.enemyAA += 1
				table.insert(zones, { cell = b.cell, radius = near, kind = "enemyAA" })
				if long then
					table.insert(zones, { cell = b.cell, radius = far, kind = "enemyAALong" })
				end
			end
		elseif b.kind == "Airfield" and enemy then
			out.enemyAirfields += 1
			table.insert(zones, { cell = b.cell, radius = airReach, kind = "enemyAir" })
		elseif b.kind == "MissileSilo" and enemy then
			out.enemySilos += 1
			table.insert(zones, { cell = b.cell, radius = ThreatMap.SiloMarkRadius, kind = "enemySilo" })
		end
	end
	-- Свои цели: здания и города.
	local targets: { [number]: boolean } = {}
	for _, b in input.buildings do
		if b.owner == me then
			targets[b.cell] = true
		end
	end
	for _, c in input.cities do
		if c.owner == me then
			targets[c.cell] = true
		end
	end
	for cell in targets do
		out.targets += 1
		local cx, cy = cell % w, cell // w
		local covered = false
		for _, s in shields do
			local dx, dy = s.cell % w - cx, s.cell // w - cy
			if dx * dx + dy * dy <= s.r * s.r then
				covered = true
				break
			end
		end
		if not covered then
			table.insert(out.holes, cell)
		end
	end
	table.sort(out.holes)
	return out
end

return table.freeze(ThreatMap)
