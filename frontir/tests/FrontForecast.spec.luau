--!strict
local T = require("./lib/TestKit")
local AttackPreview = require("../src/shared/AttackPreview")
local TinyMap = require("./lib/TinyMap")
local Config = require("../src/shared/Config")
local Forces = require("../src/shared/Forces")
local FrontForecast = require("../src/shared/FrontForecast")
local Fronts = require("../src/shared/Fronts")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local MatchStats = require("../src/shared/Net/MatchStats")
local Protocol = require("../src/shared/Net/Protocol")
local Rng = require("../src/shared/Rng")
local Strings = require("../src/shared/Strings")
local Types = require("../src/shared/Types")
local Wars = require("../src/shared/Wars")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number
local FULL = Config.Combat.FullSpeedRatio
local W = 40

local function whyOf(name: string): number
	return table.find(FrontForecast.Whys, name) :: number
end

local function factors(): FrontForecast.Factors
	return { supply = 1, fortLine = 1, forts = 1, river = 1, terrain = 1, ability = 1 }
end

-- Две державы на равнине 40×12 (1 — слева, 2 — справа), война активна; третья — далеко, без войны.
-- Город 1 у x=4: фронт (x≈20) без снабжения (дальность 60 × 40/512 ≈ 4.7 клетки).
local function duel(defense: number?): MatchSim.Match
	local m = MatchSim.new(TinyMap.plains(W, 12), 5)
	m.victory = false
	MatchSim.addPlayer(m, 1, "A")
	MatchSim.addPlayer(m, 2, "B")
	MatchSim.addPlayer(m, 3, "C")
	m.phase = "Play"
	for x = 1, 38 do
		for y = 1, 9 do
			Grid.setOwner(m.grid, y * W + x, if x <= 19 then 1 else 2)
		end
	end
	Grid.setOwner(m.grid, 10 * W + 1, 3)
	local cities = { 6 * W + 4, 6 * W + 35, 10 * W + 1 }
	for k, c in cities do
		Grid.setCity(m.grid, c, true)
		m.cityOf[-k] = c
		m.nations[k].capital = c
	end
	for _, n in m.nations do
		n.colorIndex = n.id
		n.people = 5000
	end
	local war = Wars.declare(m.wars, 1, 2, m.simTime)
	war.state = "active"
	war.activeAt = m.simTime
	Forces.add(m.nations[1].home, INF, 3000)
	Forces.add(m.nations[2].home, INF, defense or 5000)
	return m
end

local function attackOf(m: MatchSim.Match): Types.Attack
	T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 1 }))).toBe(true)
	MatchSim.step(m, DT)
	return m.attacks[1]
end

T.describe("Прогноз фронта (§15н)", function()
	T.it("состояние по перевесу; без обороны — «свободно»", function()
		T.expect(FrontForecast.state(0.8, true)).toBe("stalled")
		T.expect(FrontForecast.state(1, true)).toBe("stalled")
		T.expect(FrontForecast.state((1 + FULL) / 2, true)).toBe("slow")
		T.expect(FrontForecast.state(FULL, true)).toBe("advance")
		T.expect(FrontForecast.state(Config.Combat.BreakthroughRatio, true)).toBe("breakthrough")
		T.expect(FrontForecast.state(math.huge, false)).toBe("free")
	end)

	T.it(
		"причина — самый большой множитель обороны; ни одного заметного — «мало войск»; на полной скорости — нет",
		function()
			local f = factors()
			T.expect(FrontForecast.why(f, 0.8, true)).toBe(FrontForecast.Garrison)
			f.river = Config.Combat.RiverBankDefense
			f.supply = 1 / Config.Combat.UnsuppliedPowerMul
			T.expect(FrontForecast.why(f, 0.8, true)).toBe(whyOf("river")) -- 1.5 > 1.43
			f.terrain = 1.8
			T.expect(FrontForecast.why(f, 0.8, true)).toBe(whyOf("terrain"))
			-- Даже без гор фронт стоял бы (0.3 × 1.8 < 1) — причина в числе войск.
			T.expect(FrontForecast.why(f, 0.3, true)).toBe(FrontForecast.Garrison)
			T.expect(FrontForecast.why(f, FULL, true)).toBe(0)
			T.expect(FrontForecast.why(f, math.huge, false)).toBe(0)
			local small = factors()
			small.forts = Config.Forecast.ReasonMinMul - 0.01
			T.expect(FrontForecast.why(small, 0.95, true)).toBe(FrontForecast.Garrison)
		end
	)

	T.it(
		"сколько нужно: атаке — до полной скорости, обороне — до ×1; на сколько хватит войск — с темпом матча",
		function()
			T.expect(FrontForecast.needAttack(1000, 1)).toBeNear(1000 * (FULL - 1), 1e-6)
			T.expect(FrontForecast.needAttack(1000, FULL)).toBe(0)
			T.expect(FrontForecast.needAttack(0, 0)).toBe(0)
			T.expect(FrontForecast.needDefense(800, 1.5)).toBeNear(400, 1e-6)
			T.expect(FrontForecast.needDefense(800, 0.9)).toBe(0)
			T.expect(FrontForecast.needDefense(800, math.huge)).toBe(0)
			T.expect(FrontForecast.lastsSec(1000, 10, 1) :: number).toBeNear(100, 1e-6)
			T.expect(FrontForecast.lastsSec(1000, 10, 2) :: number).toBeNear(50, 1e-6) -- матч ×2 — вдвое меньше
			T.expect(FrontForecast.lastsSec(1000, 0, 1)).toBe(nil)
		end
	)

	T.it("тренд — с мёртвой зоной", function()
		local d = Config.Forecast.TrendDeadband
		T.expect(FrontForecast.trend(nil, 2)).toBe(0)
		T.expect(FrontForecast.trend(2, 2 * (1 + d / 2))).toBe(0)
		T.expect(FrontForecast.trend(2, 2 * (1 + d * 2))).toBe(1)
		T.expect(FrontForecast.trend(2, 2 * (1 - d * 2))).toBe(-1)
		T.expect(FrontForecast.trend(math.huge, 3)).toBe(-1)
		T.expect(FrontForecast.trend(3, math.huge)).toBe(1)
	end)

	T.it(
		"строки плашки: своя атака и фронт против вас; совет отступить — только когда войска тают без толку",
		function()
			local own = FrontForecast.lines({
				ratio = 0.8,
				fighting = true,
				againstMe = false,
				why = whyOf("river"),
				need = 1500,
				lasts = 20,
				trend = -1,
			}, "ru")
			T.expect(own.status).toBe("Стоит ↓ · река")
			T.expect(own.detail).toBe("+1.5K до ×2 · войск на ~20 с")
			T.expect(own.advice).toBe("Лучше отступить")
			-- Перевес растёт — не отступать; войск надолго — без «на ~N с».
			local rising = FrontForecast.lines({
				ratio = 1.5,
				fighting = true,
				againstMe = false,
				why = FrontForecast.Garrison,
				need = 400,
				lasts = Config.Forecast.LastsShowSec + 1,
				trend = 1,
			}, "en")
			T.expect(rising.status).toBe("Slow ↑ · outnumbered")
			T.expect(rising.detail).toBe("+400 for ×2")
			T.expect(rising.advice).toBe(nil)
			local enemy = FrontForecast.lines({
				ratio = 1.5,
				fighting = true,
				againstMe = true,
				why = 0,
				need = 1200,
				lasts = nil,
				trend = 0,
			}, "ru")
			T.expect(enemy.status).toBe("Враг ползёт")
			T.expect(enemy.detail).toBe("+1.2K обороны остановят")
			T.expect(enemy.advice).toBe(nil)
			-- Все ключи состояний и причин есть в Strings.
			for _, state in { "free", "stalled", "slow", "advance", "breakthrough" } do
				for _, side in { "state", "enemy" } do
					T.expect(Strings.Table["forecast." .. side .. "." .. state] ~= nil).toBe(true)
				end
			end
			for _, why in FrontForecast.Whys do
				T.expect(Strings.Table["forecast.why." .. why] ~= nil).toBe(true)
			end
		end
	)

	T.it("Fronts.battle: потери в секунду и сила обороны на линии", function()
		local a: Types.Attack = {
			attacker = 1,
			target = 2,
			troops = 0,
			focus = nil,
			forces = Forces.new(),
			supplied = false,
			ratio = math.huge,
			fighting = false,
			lastAdvance = 0,
		}
		Forces.add(a.forces, INF, 1000)
		local home = Forces.new()
		Forces.add(home, INF, 2000)
		local r = Fronts.battle(a, { home = home, share = 0.5 }, 1, Rng.new(1), DT, false)
		T.expect(r.defStrength).toBeNear(1000, 1e-6)
		local defensePower = Forces.power(home, a.forces, "defense") * 0.5 * Config.Combat.DefenderHomeBonus
		local expected = defensePower * Config.Combat.LossRate + 1000 * Config.Combat.OutOfSupplyLossPerSec
		T.expect(r.burn).toBeNear(expected, 1e-6)
	end)

	T.it(
		"в матче: причина — то, без чего фронт пошёл бы (снабжение, горы); при большом отставании — «мало войск»",
		function()
			-- Матч с гарнизоном защитника под нужный перевес: перевес обратно пропорционален гарнизону.
			local function front(target: number, supplied: boolean, mountains: boolean): Types.Attack
				local function build(defense: number): Types.Attack
					local m = duel(defense)
					if supplied then
						local near = 5 * W + 18
						Grid.setCity(m.grid, near, true)
						m.cityOf[-4] = near
					end
					if mountains then
						for y = 0, 11 do
							for x = 20, 23 do
								MapData.setTerrain(m.map, y * W + x, Types.Terrain.Mountains)
							end
						end
					end
					return attackOf(m)
				end
				local probe = build(5000)
				local a = build(5000 * probe.ratio / target)
				T.expect(a.supplied).toBe(supplied)
				T.expect(a.ratio).toBeNear(target, 0.05)
				return a
			end
			local a = front(0.9, false, false)
			T.expect(a.why).toBe(whyOf("supply")) -- со снабжением было бы ×1.3
			T.expect((a.needAtk :: number) > 0).toBe(true)
			T.expect((a.burn :: number) > 0).toBe(true)
			T.expect(a.needDef).toBe(0) -- фронт стоит — обороне добавлять нечего
			T.expect(front(1.2, true, false).why).toBe(FrontForecast.Garrison) -- ничего не мешает, просто мало
			T.expect(front(0.8, true, true).why).toBe(whyOf("terrain")) -- без гор было бы ×1.4
			T.expect(front(0.3, true, true).why).toBe(FrontForecast.Garrison) -- и без гор стоял бы
			T.expect(front(0.3, false, false).why).toBe(FrontForecast.Garrison)
		end
	)

	T.it(
		"сеть: прогноз — только сторонам фронта; третьей державе — нули (скрытая мощь)",
		function()
			local m = duel()
			-- Сильная атака: обороне есть что добавить.
			Forces.add(m.nations[1].home, INF, 30000)
			local a = attackOf(m)
			T.expect(a.ratio > 1).toBe(true)
			T.expect((a.needDef :: number) > 0).toBe(true)
			local full = MatchStats.build(m, 0, 0)
			local function seen(viewer: number?): Protocol.AttackStats
				local s = Protocol.decodeStats(Protocol.encodeStats(MatchStats.forViewer(m, full, viewer)))
				return s.attacks[1]
			end
			local mine = seen(1)
			T.expect(mine.why).toBe(a.why)
			T.expect(mine.need :: number).toBeNear(a.needAtk :: number, 10)
			T.expect(mine.burn :: number).toBeNear(a.burn :: number, 0.1)
			local theirs = seen(2)
			T.expect(theirs.why).toBe(0)
			T.expect(theirs.burn).toBe(0)
			T.expect(theirs.need :: number).toBeNear(a.needDef :: number, 10)
			local other = seen(3)
			T.expect(other.why).toBe(0)
			T.expect(other.need).toBe(0)
			T.expect(other.burn).toBe(0)
		end
	)
	T.it(
		"§15н ч.2: прогноз до атаки совпадает с перевесом сервера после удара (равнина и горы); подкрепление",
		function()
			-- Что знает клиент — из сообщений сервера: свои войска, статистика, сетка, города, здания.
			local function source(m: MatchSim.Match): AttackPreview.Source
				local stats = MatchStats.build(m, 0, 0)
				return {
					width = m.grid.width,
					height = m.grid.height,
					map = m.map,
					ownerAt = function(i: number): number
						return Grid.getOwner(m.grid, i)
					end,
					me = 1,
					myKinds = MatchStats.forcesOf(m, 1).kinds,
					nations = stats.nations,
					attacks = stats.attacks,
					cities = MatchSim.cities(m),
					friends = {},
					buildings = m.buildings.byCell,
				}
			end
			for _, mountains in { false, true } do
				local m = duel(2000)
				if mountains then
					for y = 0, 11 do
						for x = 20, 23 do
							MapData.setTerrain(m.map, y * W + x, Types.Terrain.Mountains)
						end
					end
				end
				local cell = 5 * W + 20 -- его клетка у нашей границы
				local preview = AttackPreview.compute(source(m), 2, cell, 0.5) :: AttackPreview.Result
				T.expect(preview ~= nil).toBe(true)
				T.expect(preview.known).toBe(true)
				T.expect(preview.existing).toBe(nil)
				T.expect((MatchSim.applyIntent(m, 1, { kind = "attack", target = 2, percent = 0.5 }))).toBe(true)
				MatchSim.step(m, DT)
				local a = m.attacks[1]
				T.expect(preview.ratio).toBeNear(a.ratio, a.ratio * 1e-3)
				T.expect(preview.why).toBe(a.why)
				-- «Сколько нужно» сервер считает уже после потерь первого тика — разница меньше процента.
				T.expect(preview.need).toBeNear(a.needAtk :: number, (a.needAtk :: number) * 0.02 + 1)
				-- Подкрепление: фронт уже идёт — прогноз выше нынешнего перевеса.
				local more = AttackPreview.compute(source(m), 2, cell, 0.5) :: AttackPreview.Result
				T.expect(more.existing).toBeNear(a.ratio, 0.05)
				T.expect(more.ratio > (more.existing :: number)).toBe(true)
			end
			-- Далеко от общей границы — прогноза нет (там десант или ничего).
			local m = duel(2000)
			T.expect(AttackPreview.compute(source(m), 2, 5 * W + 37, 0.5)).toBe(nil)
		end
	)
	T.it(
		"§15н ч.2: строки прогноза до атаки — война, подкрепление, «если начать войну», скрытые силы",
		function()
			local v = {
				ratio = 1.6,
				state = "slow" :: FrontForecast.State,
				why = whyOf("terrain"),
				need = 1200,
				known = true,
			}
			local head, detail = FrontForecast.previewLines(v, true, "ru")
			T.expect(head).toBe("Атака сейчас: ×1.6 · Медленно · местность")
			T.expect(detail).toBe("+1.2K до ×2")
			local reinforce = table.clone(v) :: any
			reinforce.existing = 1.2
			T.expect((FrontForecast.previewLines(reinforce, true, "ru")))
				.toBe("Подкрепление: ×1.2 → ×1.6 · Медленно · местность")
			local hidden = table.clone(v)
			hidden.known = false
			local h2, d2 = FrontForecast.previewLines(hidden, false, "en")
			T.expect(h2).toBe("If you go to war: ≈×1.6 · Slow · terrain")
			T.expect(d2).toBe("+1.2K for ×2 · estimate: enemy strength hidden")
			T.expect(FrontForecast.ratioText(math.huge)).toBe("×8+")
		end
	)
end)
