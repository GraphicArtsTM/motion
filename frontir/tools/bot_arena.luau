--!strict
--[[
	Арена ботов (GDD §9.1): держава-«игрок» (Обычный бот, личность Флотоводец — с флотом и авиацией) против
	трёх ботов одного уровня на реальной карте. Матч до победы или лимита времени, по умолчанию 20 сидов.
	Печатает место и долю суши «игрока» и проверяет пороги Config.Bots.Arena*: против Новичков «игрок» первый
	не реже ArenaNoviceFirstShare партий, против Генералов его среднее место хуже ArenaGeneralBestPlace (сложно)
	и не хуже ArenaGeneralWorstPlace (не безнадёжно).
	У каждой системы и каждого бота свой поток случайных чисел (MatchSim), поэтому решения «игрока» не меняют
	ход боёв и решений остальных ботов.
	Запуск из frontir/:  lune run tools/bot_arena [карта=Europe] [сидов=20] [уровни=Novice,Normal,General] [соперников=3]
]]

local process = require("@lune/process")

local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")
local Types = require("../src/shared/Types")

local mapName = process.args[1] or "Europe"
local seeds = tonumber(process.args[2]) or 20
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
	-- Пороги (Config.Bots): Новички — лёгкие, Генералы — тяжёлые.
	local cfg = Config.Bots
	if lvl == "Novice" then
		local share = wins / seeds
		print(
			string.format(
				"  ПОРОГ Новички: первый в %.0f%% партий (нужно ≥ %.0f%%) — %s",
				share * 100,
				cfg.ArenaNoviceFirstShare * 100,
				if share >= cfg.ArenaNoviceFirstShare then "выполнен" else "НЕ ВЫПОЛНЕН"
			)
		)
	elseif lvl == "General" then
		local avg = places / seeds
		local ok = avg > cfg.ArenaGeneralBestPlace and avg <= cfg.ArenaGeneralWorstPlace
		print(
			string.format(
				"  ПОРОГ Генералы: среднее место %.2f (нужно хуже %.1f и не хуже %.1f) — %s",
				avg,
				cfg.ArenaGeneralBestPlace,
				cfg.ArenaGeneralWorstPlace,
				if ok then "выполнен" else "НЕ ВЫПОЛНЕН"
			)
		)
	end
end
