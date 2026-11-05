--!strict
--[[
	Нагрузка сервера: партия ботов на карте, время тика и трафик на клиента (GDD §12: тик не дольше 25 мс
	при 60 игроках на «Мире»). Запуск из frontir/:  lune run tools/bench [карта=World] [держав=60] [секунд=180]
	Время тика — в Lune на этой машине; на сервере Roblox оно другое, это ориентир.
]]

local process = require("@lune/process")

local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Diplomacy")
local Fog = require("../src/shared/Fog")
local Grid = require("../src/shared/Grid")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")
local Naval = require("../src/shared/Naval")
local Protocol = require("../src/shared/Net/Protocol")

local OVERHEAD = 16 -- байт на сообщение RemoteEvent (оценка, как в тесте трафика)

local name = process.args[1] or "World"
local nations = tonumber(process.args[2]) or 60
local seconds = tonumber(process.args[3]) or 180

local map = MapFormat.fromModule((require :: any)("../maps/" .. name) :: MapFormat.MapModule)
local m = MatchSim.new(map, 60)
m.targetNations = nations
MatchSim.startPick(m)
local dt = 1 / Config.Sim.TickRate
while m.phase ~= "Play" do
	MatchSim.step(m, dt)
end
Grid.takeChanges(m.grid)

local ticks, total, worst, slow = 0, 0, 0, 0
local bytes, peak, second = 0, 0, 0
local statsEvery = Config.Sim.TickRate // Config.Net.StatsHz
for t = 1, seconds * Config.Sim.TickRate do
	local t0 = os.clock()
	MatchSim.step(m, dt)
	local ms = (os.clock() - t0) * 1000
	total += ms
	worst = math.max(worst, ms)
	ticks += 1
	if ms > 25 then
		slow += 1
	end
	local changes = Grid.takeChanges(m.grid)
	if #changes > 0 then
		second += buffer.len(Protocol.encodeDelta(m.tick, changes, m.grid.owner)) + OVERHEAD
	end
	if t % statsEvery == 0 then
		-- STATS — каждому свой (туман, §6.11): меряем глазами первой державы.
		second += buffer.len(Protocol.encodeStats(MatchStats.forViewer(m, MatchStats.build(m, 0, #changes), 1))) + OVERHEAD
		second += buffer.len(Protocol.encodeWars(MatchStats.wars(m))) + OVERHEAD
		second += buffer.len(Protocol.encodeShips(MatchStats.ships(m, 1))) + OVERHEAD -- корабли (§6.12)
		second += buffer.len(Protocol.encodeAir(MatchStats.air(m, 1))) + OVERHEAD -- самолёты (§6.13)
	end
	if t % Config.Sim.TickRate == 0 then
		peak = math.max(peak, second)
		bytes += second
		second = 0
	end
	MatchSim.takeEvents(m)
end

print(
	string.format(
		"%s, держав %d, %d с: тик средний %.2f мс, худший %.1f мс, дольше 25 мс — %d из %d; "
			.. "трафик средний %.1f КБ/с, пик %.1f КБ/с",
		name,
		#m.nations,
		seconds,
		total / ticks,
		worst,
		slow,
		ticks,
		bytes / seconds / 1000,
		peak / 1000
	)
)

-- Туман (§6.11): пересчёт обзора клиентом у самой большой державы и STATS каждому игроку (сервер, раз в секунду).
local biggest = m.nations[1]
for _, n in m.nations do
	if n.alive and Grid.cellsOf(m.grid, n.id) > Grid.cellsOf(m.grid, biggest.id) then
		biggest = n
	end
end
local fs = Fog.new(m.grid.width, m.grid.height)
local friends = Diplomacy.friends(m.diplo, biggest.id)
local fronts: { { mine: number, other: number } } = {}
for _, a in m.attacks do
	if friends[a.attacker] and a.target ~= 0 then
		table.insert(fronts, { mine = a.attacker, other = a.target })
	elseif friends[a.target] then
		table.insert(fronts, { mine = a.target, other = a.attacker })
	end
end
local sources = { friends = friends, fronts = fronts, radars = MatchStats.radarsOf(m, friends) }
Fog.compute(fs, m.grid.owner, sources) -- первый раз — из «видно всё»
local runs, fogMs = 10, 0
for _ = 1, runs do
	local t0 = os.clock()
	Fog.compute(fs, m.grid.owner, sources)
	fogMs += (os.clock() - t0) * 1000
end
local t0 = os.clock()
local full = MatchStats.build(m, 0, 0)
local head = Protocol.encodeStatsHead(full)
for _, n in m.nations do
	Protocol.encodeStats(MatchStats.forViewer(m, full, n.id), head)
end
local statsMs = (os.clock() - t0) * 1000
print(
	string.format(
		"туман: обзор клиента у крупнейшей державы (%.0f%% суши) — %.1f мс; STATS для %d держав — %.1f мс",
		Grid.cellsOf(m.grid, biggest.id) / m.grid.capturableCount * 100,
		fogMs / runs,
		#m.nations,
		statsMs
	)
)

-- Флот (§6.12): поиск морского пути между причалами (сервер ищет не больше Naval.PathsPerTick путей за тик).
do
	local docks: { number } = {}
	for _, d in m.sea.docks do
		table.insert(docks, d)
	end
	table.sort(docks)
	local worstPath, sumPath, paths = 0, 0, 0
	for k = 1, 40 do
		local a = docks[(k * 37) % #docks + 1]
		local b = docks[(k * 91 + 13) % #docks + 1]
		if a ~= nil and b ~= nil and Naval.seaAt(m.sea, a) == Naval.seaAt(m.sea, b) then
			local t = os.clock()
			Naval.path(m.sea, a, b)
			local ms = (os.clock() - t) * 1000
			worstPath = math.max(worstPath, ms)
			sumPath += ms
			paths += 1
		end
	end
	print(
		string.format(
			"флот: морской путь между причалами (%d пар) — среднее %.1f мс, худшее %.1f мс; кораблей в матче %d",
			paths,
			sumPath / math.max(1, paths),
			worstPath,
			#m.fleet.ships
		)
	)
end
