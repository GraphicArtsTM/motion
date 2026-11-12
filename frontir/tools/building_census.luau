--!strict
--[[
	Перепись зданий (вопрос геймдизайнера §15х ч.5: «зачем столько построек, какие не нужны»). Только замер.

	lune run tools/building_census [партий=6] [карта=Europe] [держав=12] [база сидов=21000]
	Полные партии ботов. На 5, 10, 15, 20 минуте и в конце — сколько зданий каждого вида (с уровнями) стоит на карте
	у живых держав и у скольких держав есть хотя бы одно. Итог — таблица в консоли и build/building_census.json.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")

local games = tonumber(process.args[1]) or 6
local mapName = process.args[2] or "Europe"
local nations = tonumber(process.args[3]) or 12
local seedBase = tonumber(process.args[4]) or 21000
local map = MapFormat.fromModule((require :: any)("../maps/" .. mapName) :: MapFormat.MapModule)
local dt = 1 / Config.Sim.TickRate

local KINDS = {
	"Factory",
	"Barracks",
	"Housing",
	"OilRig",
	"Fort",
	"Port",
	"Airfield",
	"AirDefense",
	"MissileSilo",
}
local MARKS = { 300, 600, 900, 1200, math.huge }
local LABELS = { "5 мин", "10 мин", "15 мин", "20 мин", "конец" }

-- sums[mark][kind] = { buildings, levels, nationsWith, alive }
type Cell = { buildings: number, levels: number, has: number, alive: number, samples: number }
local sums: { { [string]: Cell } } = {}
for k = 1, #MARKS do
	sums[k] = {}
	for _, kind in KINDS do
		sums[k][kind] = { buildings = 0, levels = 0, has = 0, alive = 0, samples = 0 }
	end
end

local function sample(m: MatchSim.Match, k: number)
	local alive = 0
	for _, n in m.nations do
		if n.alive then
			alive += 1
		end
	end
	for _, kind in KINDS do
		local c = sums[k][kind]
		local owners: { [number]: boolean } = {}
		for cell, b in m.buildings.byCell do
			if b.kind == kind then
				local owner = Grid.getOwner(m.grid, cell)
				if owner ~= 0 then
					c.buildings += 1
					c.levels += b.level or 1
					owners[owner] = true
				end
			end
		end
		for _ in owners do
			c.has += 1
		end
		c.alive += alive
		c.samples += 1
	end
end

local t0 = os.clock()
for g = 1, games do
	local m = MatchSim.new(map, seedBase + g * 37)
	m.targetNations = nations
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, dt)
	end
	local start = m.simTime
	local k = 1
	local limit = m.rules.timeLimitSec + 5
	while m.phase == "Play" and m.time < limit do
		MatchSim.step(m, dt)
		while k < #MARKS and m.simTime - start >= MARKS[k] do
			sample(m, k)
			k += 1
		end
	end
	sample(m, #MARKS)
	print(
		string.format(
			"партия %d/%d: %.0f с игры, %.1f с счёта",
			g,
			games,
			m.simTime - start,
			os.clock() - t0
		)
	)
end

print("\nВид            " .. table.concat(LABELS, " | "))
local out: { [string]: any } = {}
for _, kind in KINDS do
	local cols: { string } = {}
	out[kind] = {}
	for k = 1, #MARKS do
		local c = sums[k][kind]
		local per = if c.alive > 0 then c.buildings / c.alive else 0
		local share = if c.alive > 0 then c.has / c.alive else 0
		table.insert(cols, string.format("%4.1f/%3d%%", per, math.round(share * 100)))
		out[kind][LABELS[k]] = { perNation = per, share = share, avgLevel = c.levels / math.max(1, c.buildings) }
	end
	print(string.format("%-14s %s", kind, table.concat(cols, " | ")))
end
print(
	"\n(зданий на живую державу / доля живых держав, у которых есть хотя бы одно)"
)
fs.writeDir("build")
fs.writeFile("build/building_census.json", serde.encode("json", out, true))
