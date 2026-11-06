--!strict
--[[
	Арена генералов (сводная правка): lune run tools/arena_commanders [партий=40] [карта=Europe] [уровень=Normal] [личность=Cunning]
	Четыре бота одного уровня и одной личности, у каждого свой генерал (Маршал, Адмирал, Разведчик, Инженер);
	от партии к партии генералы сдвигаются по местам старта (старт не решает). Печатает долю побед каждого генерала
	(ровно — около 25%) и среднее место; генерал дальше ±10% — помечен.
]]

local process = require("@lune/process")

local Commanders = require("../src/shared/Commanders")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")
local Types = require("../src/shared/Types")

local games = tonumber(process.args[1]) or 40
local mapName = process.args[2] or "Europe"
local level: Types.BotLevel = (process.args[3] or "Normal") :: any
local personality: Types.BotPersonality = (process.args[4] or "Cunning") :: any
local map = MapFormat.fromModule((require :: any)("../maps/" .. mapName) :: MapFormat.MapModule)
local dt = 1 / Config.Sim.TickRate
local ids = Types.CommanderIds

local wins: { [string]: number } = {}
local places: { [string]: number } = {}
local lengths = 0
local t0 = os.clock()
for k = 1, games do
	local seed = 9000 + k * 53
	local m = MatchSim.new(map, seed)
	m.targetNations = #ids
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, dt)
	end
	-- Генерал держав сдвигается на одно место каждую партию.
	local commanderOf: { [number]: Types.CommanderId } = {}
	for i, n in m.nations do
		MatchSim.setBot(m, n.id, level, personality)
		local c: Types.CommanderId = ids[(i + k) % #ids + 1] :: any
		Commanders.choose(m.commanders, n.id, c)
		commanderOf[n.id] = c
	end
	local limit = m.rules.timeLimitSec + 5
	while m.phase == "Play" and m.time < limit do
		MatchSim.step(m, dt)
		MatchSim.takeEvents(m)
	end
	lengths += m.time / 60
	local result = m.result :: Types.MatchResult?
	if result ~= nil then
		local winner = commanderOf[result.winner]
		if winner ~= nil then
			wins[winner] = (wins[winner] or 0) + 1
		end
		for place, id in result.places do
			local c = commanderOf[id]
			if c ~= nil then
				places[c] = (places[c] or 0) + place
			end
		end
	end
	print(
		string.format(
			"партия %2d (сид %d): победил %s, %.1f мин, суша победителя %.0f%%",
			k,
			seed,
			if result ~= nil then commanderOf[result.winner] or "?" else "—",
			m.time / 60,
			if result ~= nil then Grid.cellsOf(m.grid, result.winner) / m.grid.capturableCount * 100 else 0
		)
	)
end

print(
	string.format(
		"\nИТОГ: %d партий «%s», боты %s / %s, средний матч %.1f мин, %.0f с",
		games,
		mapName,
		level,
		personality,
		lengths / games,
		os.clock() - t0
	)
)
for _, c in ids do
	local share = (wins[c] or 0) / games
	local flag = if math.abs(share - 0.25) > 0.10 then "  ← дальше ±10% от 25%" else ""
	print(
		string.format(
			"  %-9s побед %2d (%4.1f%%), среднее место %.2f%s",
			c,
			wins[c] or 0,
			share * 100,
			(places[c] or 0) / games,
			flag
		)
	)
end
