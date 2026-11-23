--!strict
-- §15ъ Выжженная земля: авиаудар делает землю врага во внутреннем круге ничьей; занять её до срока может только
-- ударивший — враг ни ростом, ни заливкой анклавов. Города, столицы и здания не выжигаются.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
local cfg = Config.Commanders
-- Как Commanders.spec: 160×32, держава 1 — x 1..60, держава 2 — x 61..120, дальше ничья земля.
local W, H = 160, 32

local function duo(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 9)
	m.victory = false
	MatchSim.addPlayer(m, 1, "N1")
	MatchSim.addPlayer(m, 2, "N2")
	m.phase = "Play"
	for y = 1, H - 2 do
		for x = 1, 120 do
			Grid.setOwner(m.grid, y * W + x, if x <= 60 then 1 else 2)
		end
	end
	local caps = { 16 * W + 5, 16 * W + 115 }
	for _, n in m.nations do
		n.colorIndex = n.id
		n.people = 50000
		n.money = 100000
		n.oil = 5000
		n.capital = caps[n.id]
		Grid.setCity(m.grid, caps[n.id], true)
		m.cityOf[-n.id] = caps[n.id]
		Forces.add(n.home, INF, 3000)
	end
	return m
end

local function runFor(m: MatchSim.Match, seconds: number)
	for _ = 1, math.floor(seconds * Config.Sim.TickRate + 0.5) do
		MatchSim.step(m, DT)
	end
end

local function circle(at: number, r: number): { number }
	local out = {}
	for dy = -r, r do
		for dx = -r, r do
			if dx * dx + dy * dy <= r * r then
				table.insert(out, (at // W + dy) * W + at % W + dx)
			end
		end
	end
	return out
end

local function ownersIn(m: MatchSim.Match, cells: { number }, owner: number): number
	local k = 0
	for _, c in cells do
		if Grid.getOwner(m.grid, c) == owner then
			k += 1
		end
	end
	return k
end

local function strike(m: MatchSim.Match, at: number): (boolean, string?)
	return MatchSim.applyIntent(m, 1, { kind = "ability", slot = 1, cell = at }) -- Маршал: слот 1 — Авиаудар
end

T.describe("Выжженная земля (§15ъ)", function()
	T.it(
		"авиаудар у границы: земля врага во внутреннем круге — ничья, своя цела; событие с числом клеток",
		function()
			local m = duo()
			DevTools.warNow(m, 1, 2)
			local at = 16 * W + 63 -- круг r=3: x 60..66 — своя полоса x=60 и вражеские 61..66
			local zone = circle(at, cfg.StrikeScorchRadius)
			local enemyBefore = ownersIn(m, zone, 2)
			local mineBefore = ownersIn(m, zone, 1)
			MatchSim.takeEvents(m)
			T.expect((strike(m, at))).toBe(true)
			T.expect(ownersIn(m, zone, 2)).toBe(0)
			T.expect(ownersIn(m, zone, 0)).toBe(enemyBefore)
			T.expect(ownersIn(m, zone, 1)).toBe(mineBefore)
			local found = nil
			for _, e in MatchSim.takeEvents(m) do
				if e.kind == "scorched" then
					found = e
				end
			end
			T.expect(found ~= nil).toBe(true)
			T.expect((found :: any).cells).toBe(enemyBefore)
			T.expect((found :: any).target).toBe(2)
			T.expect((found :: any).nation).toBe(1)
		end
	)

	T.it(
		"без войны — удара нет и земля цела; город, столица и здание в круге не выжигаются",
		function()
			local m = duo()
			local at = 16 * W + 63
			T.expect(select(2, strike(m, at))).toBe("noEnemy")
			T.expect(ownersIn(m, circle(at, cfg.StrikeScorchRadius), 0)).toBe(0)
			DevTools.warNow(m, 1, 2)
			local city, building = 16 * W + 64, 15 * W + 63
			Grid.setCity(m.grid, city, true)
			Buildings.place(m.buildings, "Factory", building, MapData.getProvince(m.map, building))
			MatchSim.refreshOwned(m)
			m.nations[2].capital = 17 * W + 63
			T.expect((strike(m, at))).toBe(true)
			T.expect(Grid.getOwner(m.grid, city)).toBe(2)
			T.expect(Grid.getOwner(m.grid, building)).toBe(2)
			T.expect(Grid.getOwner(m.grid, 17 * W + 63)).toBe(2)
			T.expect(Grid.getOwner(m.grid, at)).toBe(0)
		end
	)

	T.it(
		"враг не возвращает выжженную землю до срока, ударивший занимает; после срока — может и враг",
		function()
			local m = duo()
			DevTools.warNow(m, 1, 2)
			local at = 16 * W + 90 -- в глубине врага: дыра, окружённая его землёй
			local zone = circle(at, cfg.StrikeScorchRadius)
			T.expect((strike(m, at))).toBe(true)
			local burnt = ownersIn(m, zone, 0)
			T.expect(burnt > 0).toBe(true)
			-- Враг растёт людьми (к ничьей земле x > 120): дыру не заливает ни ростом, ни анклавом.
			T.expect((MatchSim.applyIntent(m, 2, { kind = "attack", target = 0, percent = 1 }))).toBe(true)
			runFor(m, 10)
			T.expect(ownersIn(m, zone, 0)).toBe(burnt)
			-- Срок вышел — враг может взять её снова.
			m.simTime += cfg.StrikeScorchSec + 1
			m.nations[2].people = 50000
			T.expect((MatchSim.applyIntent(m, 2, { kind = "attack", target = 0, percent = 1 }))).toBe(true)
			runFor(m, 10)
			T.expect(ownersIn(m, zone, 0) < burnt).toBe(true)
		end
	)

	T.it(
		"ударивший занимает выжженную землю у своей границы людьми",
		function()
			local m = duo()
			DevTools.warNow(m, 1, 2)
			local at = 16 * W + 63
			local zone = circle(at, cfg.StrikeScorchRadius)
			T.expect((strike(m, at))).toBe(true)
			local mineBefore = ownersIn(m, zone, 1)
			T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 0, percent = 1 }))).toBe(true)
			runFor(m, 10)
			T.expect(ownersIn(m, zone, 1) > mineBefore).toBe(true)
		end
	)

	T.it(
		"клиент: зона гари из события — кто и сколько ещё может занять; своя клетка и вне круга — не выжжены",
		function()
			local cs = ClientState.new(W, H)
			local at = 16 * W + 63
			ClientState.noteScorched(cs, { kind = "scorched", nation = 1, cell = at, radius = 3, sec = 30 }, 100)
			local by, left = ClientState.scorchedAt(cs, at + 1, 105)
			T.expect(by).toBe(1)
			T.expect(left > 0 and left <= 30).toBe(true)
			T.expect((ClientState.scorchedAt(cs, at + 10, 105))).toBe(nil) -- вне круга
			buffer.writeu16(cs.owners, (at + 1) * 2, 2)
			T.expect((ClientState.scorchedAt(cs, at + 1, 105))).toBe(nil) -- уже занята
			T.expect((ClientState.scorchedAt(cs, at, 100 + 31 / math.max(ClientState.simRate(cs), 1e-3)))).toBe(nil)
		end
	)
end)
