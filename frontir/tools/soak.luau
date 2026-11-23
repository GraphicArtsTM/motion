--!strict
--[[
	Прогон на выносливость (перед закрытым тестом): полные матчи ботов на каждой карте пула и в каждом режиме —
	ловит редкие ошибки в тике (в игре они заморозили бы матч, см. TickErrorLimit) и медленные тики. Сеть тоже
	проверяется: каждый тик собираются сообщения STATS/forces для первой державы, как их шлёт сервер.
	Запуск из frontir/:  lune run tools/soak [секунд матча = 900] [сид = 1] [карта | all] [режим | all]
	Итог: строка на пару «карта · режим» (фаза в конце, держав живы, худший тик) и все ошибки с трассировкой.
]]

local process = require("@lune/process")

local Config = require("../src/shared/Config")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")
local Types = require("../src/shared/Types")

local seconds = tonumber(process.args[1]) or 900
local seed = tonumber(process.args[2]) or 1
local mapArg = process.args[3] or "all"
local modeArg = process.args[4] or "all"

local maps: { string } = if mapArg == "all" then Config.MapVote.Pool else { mapArg }
local modes: { string } = if modeArg == "all" then Types.ModeIds :: any else { modeArg }

local dt = 1 / Config.Sim.TickRate
local failures = 0
for _, mapName in maps do
	local map = MapFormat.fromModule((require :: any)("../maps/" .. mapName) :: MapFormat.MapModule)
	for _, mode in modes do
		if mode == "Tutorial" then
			continue -- обучение — только для человека (без него шаги стоят)
		end
		local m = MatchSim.new(map, seed)
		m.forcedMode = mode :: any
		local worst, steps, phase = 0, 0, "?"
		local ok, err = xpcall(function()
			MatchSim.startPick(m)
			local guard = 0
			while m.phase ~= "Play" and guard < 5000 do
				MatchSim.step(m, dt)
				guard += 1
			end
			for _ = 1, math.floor(seconds / dt) do
				local t0 = os.clock()
				MatchSim.step(m, dt)
				local spent = os.clock() - t0
				if spent > worst then
					worst = spent
				end
				steps += 1
				if steps % 50 == 0 then
					-- То, что сервер шлёт игрокам: статистика (как видит держава 1) и события.
					local known = MatchSim.knownSet(m, 1)
					local vision = MatchStats.vision(m, 1)
					MatchStats.forViewer(m, MatchStats.build(m, 0, 0, 1), 1, vision, known)
					MatchStats.forcesOf(m, 1)
					MatchStats.ships(m, 1, vision)
					MatchStats.air(m, 1, vision)
					MatchStats.world(m, 1)
					MatchStats.stability(m, 1)
					MatchStats.tech(m, 1)
					MatchStats.commander(m, 1)
					MatchStats.task(m, 1)
					MatchStats.pockets(m, 1)
					MatchStats.wars(m, known)
					MatchStats.diplo(m)
					MatchSim.railsMessage(m, false)
					MatchSim.takeEvents(m)
				end
				if m.phase == "Over" then
					break
				end
			end
			phase = m.phase
		end, debug.traceback)
		local alive = 0
		for _, n in m.nations do
			if n.alive then
				alive += 1
			end
		end
		if ok then
			print(
				string.format(
					"  ok  %-13s %-12s фаза %-5s держав %2d/%2d  тиков %5d  худший тик %.1f мс",
					mapName,
					mode,
					phase,
					alive,
					#m.nations,
					steps,
					worst * 1000
				)
			)
		else
			failures += 1
			print(string.format("  !!  %s %s после %d тиков:\n%s", mapName, mode, steps, tostring(err)))
		end
	end
end
print(string.format("итог: ошибок %d", failures))
if failures > 0 then
	process.exit(1)
end
