--!strict
--[[
	Арена ботов (GDD §9.1, этап 5): держава-«игрок» (Обычный бот, личность Флотоводец без флота — без перекосов) против
	трёх ботов одного уровня на реальной карте. Матч до победы или лимита времени, несколько сидов.
	Печатает место и долю суши «игрока» против Новичков, Обычных и Генералов.
	Запуск из frontir/:  lune run tools/bot_arena [карта=Europe] [сидов=4] [уровни=Novice,Normal,General] [соперников=3]
]]

local process = require("@lune/process")

local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")
local Types = require("../src/shared/Types")

local mapName = process.args[1] or "Europe"
local seeds = tonumber(process.args[2]) or 4
local levelsArg = process.args[3] or "Novice,Normal,General"
local rivals = tonumber(process.args[4]) or 3

local map = MapFormat.fromModule((require :: any)("../maps/" .. mapName) :: MapFormat.MapModule)
local dt = 1 / Config.Sim.TickRate

export type Outcome = { place: number, share: number, winner: number, reason: string, time: number }

local function play(level: any, seed: number): Outcome
	local m = MatchSim.new(map, seed)
	MatchSim.addPlayer(m, 1, "Игрок")
	m.targetNations = rivals + 1
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, dt)
	end
	for _, n in m.nations do
		if n.id == 1 then
			MatchSim.setBot(m, 1, "Normal", "Admiral")
			-- С этапа 7б-1 Флотоводец строит флот; «игрок» арены — без флота, как раньше, чтобы замеры уровней
			-- оставались сравнимыми.
			local profile = m.botProfiles[1]
			local personality = table.clone(profile.personality)
			personality.navy = 0
			m.botProfiles[1] = { level = profile.level, personality = personality }
		else
			MatchSim.setBot(m, n.id, level)
		end
	end
	while m.phase == "Play" do
		MatchSim.step(m, dt)
		MatchSim.takeEvents(m)
	end
	local result = m.result :: Types.MatchResult
	local place = table.find(result.places, 1) or #result.places
	return {
		place = place,
		share = Grid.cellsOf(m.grid, 1) / m.grid.capturableCount,
		winner = result.winner,
		reason = result.reason,
		time = m.time,
	}
end

print(
	string.format(
		"Арена: «%s», «игрок» — Обычный бот против %d ботов уровня…",
		mapName,
		rivals
	)
)
for level in string.gmatch(levelsArg, "[^,]+") do
	local lvl = (level :: any) :: Types.BotLevel
	local places, shares, wins = 0, 0, 0
	local lines: { string } = {}
	for k = 1, seeds do
		local seed = 1000 + k * 77
		local t0 = os.clock()
		local o = play(lvl, seed)
		places += o.place
		shares += o.share
		if o.place == 1 then
			wins += 1
		end
		table.insert(
			lines,
			string.format(
				"    сид %d: место %d, суша %4.1f%%, победа %d (%s) на %d:%02d  [%.0f с]",
				seed,
				o.place,
				o.share * 100,
				o.winner,
				o.reason,
				o.time // 60,
				math.floor(o.time % 60),
				os.clock() - t0
			)
		)
	end
	print(
		string.format(
			"  против %-8s: «игрок» первый в %d из %d, среднее место %.2f, средняя суша %.1f%%",
			level,
			wins,
			seeds,
			places / seeds,
			shares / seeds * 100
		)
	)
	for _, line in lines do
		print(line)
	end
end
