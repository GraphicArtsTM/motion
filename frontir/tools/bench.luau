--!strict
--[[
	Нагрузка сервера: партия ботов на карте, время тика и трафик на клиента (GDD §12: тик не дольше 25 мс
	при 60 игроках на «Мире»). Запуск из frontir/:  lune run tools/bench [карта=World] [держав=60] [секунд=180]
	Время тика — в Lune на этой машине; на сервере Roblox оно другое, это ориентир.
]]

local process = require("@lune/process")

local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")
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
		second += buffer.len(Protocol.encodeStats(MatchStats.build(m, 0, #changes))) + OVERHEAD
		second += buffer.len(Protocol.encodeWars(MatchStats.wars(m))) + OVERHEAD
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
