--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local Diplomacy = require("../src/shared/Diplomacy")
local Economy = require("../src/shared/Economy")
local Expansion = require("../src/shared/Expansion")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")
local Stability = require("../src/shared/Stability")
local Types = require("../src/shared/Types")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
local W, H, STRIP = 45, 12, 5 -- карта 45×12, провинции — полосы по 5 клеток
local cfg = Config.Stability

-- Три державы на полосах-провинциях: 1 — провинции 1–3, 2 — 4–6, 3 — 7–9. Столицы — в первой провинции трети.
local function trio(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for y = 1, H - 2 do
		for x = 1, W - 2 do
			MapData.setProvince(map, y * W + x, x // STRIP + 1)
		end
	end
	local m = MatchSim.new(map, 3)
	m.victory = false
	for k = 1, 3 do
		MatchSim.addPlayer(m, k, "N" .. k)
	end
	m.phase = "Play"
	for y = 1, H - 2 do
		for x = 1, W - 2 do
			Grid.setOwner(m.grid, y * W + x, math.min(3, x // (STRIP * 3) + 1))
		end
	end
	for _, n in m.nations do
		n.colorIndex = n.id
		n.people = 5000
		n.capital = 6 * W + (n.id - 1) * STRIP * 3 + 2
		Grid.setCity(m.grid, n.capital :: number, true)
		m.cityOf[-n.id] = n.capital :: number -- город в списке городов (иначе держава выбывает)
	end
	return m
end

local function runFor(m: MatchSim.Match, seconds: number)
	for _ = 1, math.floor(seconds * Config.Sim.TickRate + 0.5) do
		MatchSim.step(m, DT)
	end
end

-- Целевая стабильность провинции p у хозяина.
local function targetOf(m: MatchSim.Match, p: number): number
	local ctx = MatchSim.stabilityContext(m)
	return Stability.target(ctx, p, Stability.ownerOf(ctx, p), m.stability.provinces[p].capturedAt)
end

-- Поправка за город в провинции p (на карте есть ничейные города, Cities.ProvinceShare).
local function cityBonus(m: MatchSim.Match, p: number, id: number): number
	local city = m.cityOf[p]
	if city == nil or Grid.getOwner(m.grid, city) ~= id then
		return 0
	end
	return cfg.CityPerLevel * Buildings.cityLevel(m.buildings, city)
end

-- Ожидаемая поправка за удалённость центра провинции p от столицы державы id.
local function distancePenalty(m: MatchSim.Match, p: number, id: number): number
	local capital = m.nations[id].capital :: number
	local center = m.provinces.list[p].center
	local dx, dy = capital % W - center % W, capital // W - center // W
	local d = math.sqrt(dx * dx + dy * dy) * cfg.DistanceRefWidth / W
	return math.min(cfg.DistanceMax, cfg.DistancePenalty * d / cfg.DistanceCells)
end

T.describe("Стабильность", function()
	T.it(
		"сетка считает клетки провинций по владельцам; хозяин — город или больше половины клеток",
		function()
			local m = trio()
			local p3 = m.provinces.list[3]
			T.expect(Grid.provinceCells(m.grid, 3, 1)).toBe(p3.capturable)
			local ctx = MatchSim.stabilityContext(m)
			T.expect(Stability.ownerOf(ctx, 3)).toBe(1)
			-- Половина клеток — уже не хозяин; город делает хозяином даже с одной клеткой.
			local moved = 0
			for _, cell in p3.cells do
				if moved * 2 < p3.capturable then
					Grid.setOwner(m.grid, cell, 2)
					moved += 1
				end
			end
			T.expect(Grid.provinceCells(m.grid, 3, 1) + Grid.provinceCells(m.grid, 3, 2)).toBe(p3.capturable)
			T.expect(Stability.ownerOf(ctx, 3)).toBe(2)
			local city = p3.cells[#p3.cells]
			Grid.setCity(m.grid, city, true)
			m.cityOf[3] = city
			T.expect(Grid.getOwner(m.grid, city)).toBe(1)
			T.expect(Stability.ownerOf(ctx, 3)).toBe(1)
		end
	)

	T.it(
		"целевая: столица, удалённость, мир и война, «Предатель», город и укрепление",
		function()
			local m = trio()
			runFor(m, 1.1)
			T.expect(targetOf(m, 1)).toBeNear(math.min(100, cfg.Base + cfg.Capital + cfg.Peace), 1e-6)
			local far = cfg.Base + cfg.Peace - distancePenalty(m, 3, 1) + cityBonus(m, 3, 1)
			local hadCity = cityBonus(m, 3, 1) > 0
			T.expect(targetOf(m, 3)).toBeNear(far, 1e-6)
			T.expect(distancePenalty(m, 3, 1) > distancePenalty(m, 2, 1)).toBeTruthy() -- дальше от столицы — ниже
			-- Война: −10 вместо +10 за мир.
			T.expect((MatchSim.applyIntent(m, 1, { kind = "declare", target = 2 }))).toBe(true)
			runFor(m, Config.War.MobilizationSec + 1)
			T.expect(targetOf(m, 3)).toBeNear(far - cfg.Peace + cfg.War, 1e-6)
			-- «Предатель»: −20.
			Diplomacy.markTraitor(m.diplo, 1, m.simTime)
			T.expect(targetOf(m, 3)).toBeNear(far - cfg.Peace + cfg.War + cfg.Traitor, 1e-6)
			-- Укрепление +10, город +8 за уровень.
			local p3 = m.provinces.list[3]
			Buildings.place(m.buildings, "Fort", p3.center, 3)
			if not hadCity then
				local city = p3.cells[1]
				Grid.setCity(m.grid, city, true)
				m.cityOf[3] = city
			end
			local withCity = far + (if hadCity then 0 else cfg.CityPerLevel)
			T.expect(targetOf(m, 3)).toBeNear(withCity - cfg.Peace + cfg.War + cfg.Traitor + cfg.Fort, 1e-6)
		end
	)

	T.it(
		"текущая идёт к целевой на 1 в секунду; захват у державы — сразу не выше 30 и −25, тает",
		function()
			local m = trio()
			runFor(m, 0.1)
			T.expect(Stability.valueOf(m.stability, 3)).toBeNear(cfg.SettleStart, 1e-6)
			runFor(m, 10)
			T.expect(Stability.valueOf(m.stability, 3)).toBeNear(cfg.SettleStart + 10 * cfg.ChangePerSec, 0.5)
			runFor(m, 60)
			T.expect(Stability.valueOf(m.stability, 3)).toBeNear(targetOf(m, 3), 1e-6)
			-- Держава 2 забирает провинцию 3.
			for _, cell in m.provinces.list[3].cells do
				Grid.setOwner(m.grid, cell, 2)
			end
			runFor(m, cfg.UpdateSec + 0.05)
			local s = m.stability.provinces[3]
			T.expect(s.owner).toBe(2)
			T.expect(s.value <= cfg.CaptureStart).toBeTruthy()
			T.expect(s.capturedAt ~= nil).toBeTruthy()
			local fresh = targetOf(m, 3)
			runFor(m, cfg.RecentCaptureSec)
			T.expect(targetOf(m, 3) - fresh).toBeNear(-cfg.RecentCapture, 0.5) -- поправка растаяла
		end
	)

	T.it(
		"ниже 30 — доход провинции вдвое меньше; средняя стабильность по клеткам",
		function()
			local m = trio()
			runFor(m, 1.1)
			local high = m.economy[1].income
			T.expect((DevTools.setStability(m, 1, false))).toBe(true)
			runFor(m, cfg.UpdateSec + 0.05)
			local sum = Stability.summaryOf(m.stability, 1)
			T.expect(sum.average < cfg.LowBelow).toBeTruthy()
			local cells = Grid.cellsOf(m.grid, 1)
			T.expect(sum.lowCells).toBe(cells)
			local levels = MatchSim.ownedOf(m, 1).cityLevels - sum.lowCityLevels * (1 - cfg.LowIncomeMul)
			T.expect(m.economy[1].income).toBeNear(Economy.income(cells * cfg.LowIncomeMul, levels, 0), 1e-6)
			T.expect(m.economy[1].income < high).toBeTruthy()
			-- «Стабильность 100» — доход снова полный.
			DevTools.setStability(m, 1, true)
			runFor(m, cfg.UpdateSec + 0.05)
			T.expect(Stability.summaryOf(m.stability, 1).lowCells).toBe(0)
			T.expect(m.economy[1].income).toBeNear(high, 1e-6)
		end
	)

	T.it("ниже 15 — восстания, но не в провинции столицы", function()
		local m = trio()
		runFor(m, 1.1)
		local st = m.stability
		local ctx = MatchSim.stabilityContext(m)
		local found: { [number]: boolean } = {}
		for _ = 1, 200 do
			Stability.setAll(st, 1, 0)
			st.nextUpdateAt, st.nextRevoltAt = 0, 0
			for _, r in Stability.update(st, ctx) do
				T.expect(r.owner).toBe(1)
				found[r.province] = true
			end
		end
		T.expect(found[1]).toBe(nil) -- столица
		T.expect(found[2] and found[3]).toBeTruthy()
		-- Выше RevoltBelow — не восстаёт никогда.
		local none = true
		for _ = 1, 200 do
			Stability.setAll(st, 1, cfg.RevoltBelow)
			st.nextUpdateAt, st.nextRevoltAt = 0, 0
			if #Stability.update(st, ctx) > 0 then
				none = false
			end
		end
		T.expect(none).toBe(true)
	end)

	T.it(
		"восстание: земля ничья, город повстанцев с гарнизоном 600, срок RebelSec",
		function()
			local m = trio()
			local p3 = m.provinces.list[3]
			local city = p3.center
			Grid.setCity(m.grid, city, true)
			m.cityOf[3] = city
			runFor(m, 1.1)
			MatchSim.takeEvents(m)
			T.expect((DevTools.revoltNow(m, 1))).toBe(true)
			local events = MatchSim.takeEvents(m)
			T.expect(events[1].kind).toBe("revolt")
			local revolted = (events[1] :: any).province :: number
			T.expect(revolted ~= 1).toBeTruthy() -- не столица
			-- Провинция 3 восстаёт сама: проверяем её.
			MatchSim.revolt(m, 3, 1)
			T.expect(Grid.provinceCells(m.grid, 3, 1)).toBe(0)
			T.expect(Grid.getOwner(m.grid, city)).toBe(0)
			T.expect(Stability.isRebel(m.stability, 3)).toBe(true)
			local msg = MatchStats.stability(m, 1)
			T.expect(table.find(msg.rebels, 3) ~= nil).toBeTruthy()
			-- Гарнизон повстанцев: 500 силы города не берут, 700 — берут.
			local function attackCity(strength: number): boolean
				local a: Types.Attack = {
					attacker = 1,
					target = 0,
					troops = 3000,
					focus = city,
					forces = Forces.new(),
					supplied = true,
					ratio = 0,
					fighting = false,
					lastAdvance = 0,
				}
				Forces.add(a.forces, INF, strength)
				table.insert(m.attacks, a)
				runFor(m, 20)
				return Grid.getOwner(m.grid, city) == 1
			end
			T.expect(attackCity(500)).toBe(false)
			T.expect(attackCity(cfg.RebelGarrison + 100)).toBe(true)
			-- Срок повстанцев кончается.
			runFor(m, cfg.RebelSec)
			T.expect(Stability.isRebel(m.stability, 3)).toBe(false)
		end
	)

	T.it(
		"ничью землю повстанцев граница людей берёт втрое дороже (Expansion, costMul)",
		function()
			local function captured(mul: number): number
				-- Ничья земля больше EnclaveMaxCells — окружённым куском её не забрать даром.
				local rows = { string.rep("~", 122) }
				for _ = 1, 4 do
					table.insert(rows, "~" .. string.rep(".", 120) .. "~")
				end
				table.insert(rows, string.rep("~", 122))
				local map = TinyMap.fromRows(rows)
				local g = Grid.new(map)
				Grid.setOwner(g, 122 + 1, 1)
				local n: Types.Nation = {
					id = 1,
					name = "N",
					nameEn = "N",
					isBot = false,
					colorIndex = 1,
					capital = 123,
					people = 0,
					alive = true,
					home = Forces.new(),
					queue = {},
					money = 0,
					oil = 0,
				}
				local a: Types.Attack = {
					attacker = 1,
					target = 0,
					troops = 100,
					forces = Forces.new(),
					supplied = true,
					ratio = 0,
					fighting = false,
					lastAdvance = 0,
				}
				for tick = 1, 4000 do
					local done = Expansion.advance(map, g, { n }, a, tick, 1, DT, {
						costMul = function(_cell: number): number
							return mul
						end,
					})
					if done then
						break
					end
				end
				return Grid.cellsOf(g, 1) - 1
			end
			local normal, rebel = captured(1), captured(cfg.RebelCellCostMul)
			T.expect(rebel > 0).toBeTruthy()
			T.expect(normal / rebel).toBeNear(cfg.RebelCellCostMul, 0.2)
		end
	)

	T.it("бот (Обычный) гасит нестабильность укреплением", function()
		local m = trio()
		MatchSim.setBot(m, 1, "Normal", "Trader")
		local n = m.nations[1]
		n.money = 100000
		Buildings.place(m.buildings, "Factory", m.provinces.list[1].center, 1)
		runFor(m, 1.1)
		DevTools.setStability(m, 1, false)
		local calmed = false
		for _ = 1, 60 do
			runFor(m, 0.5)
			Stability.setAll(m.stability, 1, 5) -- держим низкой, пока бот думает
			local spot2, spot3 = m.buildings.byProvince[2], m.buildings.byProvince[3]
			if spot2 ~= nil or spot3 ~= nil then
				local b = m.buildings.byCell[(spot2 or spot3) :: number]
				calmed = b.kind == "Fort"
				break
			end
		end
		T.expect(calmed).toBe(true)
	end)
end)
