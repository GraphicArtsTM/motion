--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local BotBrain = require("../src/shared/BotBrain")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Grid = require("../src/shared/Grid")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")
local Rng = require("../src/shared/Rng")
local StartPositions = require("../src/shared/StartPositions")
local Types = require("../src/shared/Types")

local DT = 1 / Config.Sim.TickRate

-- Профиль без ошибок уровня (пропуск хода мешал бы проверкам).
local function profile(level: Types.BotLevel, personality: Types.BotPersonality?): BotBrain.Profile
	local p = BotBrain.profile(level, personality or "Admiral")
	p.level = table.clone(p.level)
	p.level.mistake = 0
	p.level.buildChance = 0 -- стройку проверяем отдельно
	return p
end

local function view(): BotBrain.BotView
	return {
		people = 900,
		maxPeople = 1000,
		attacks = 0,
		queue = Config.Forces.MaxQueue, -- очередь полна — найм не мешает
		power = 2000,
		totalPower = 2000,
		hasCapital = true,
		hasNeutral = false,
		neighbours = {},
		wars = {},
		fronts = {},
		mix = { 0.5, 0.5, 0, 0 },
		money = 1e6,
		oil = 1e4,
		economy = { income = 1000, oilIncome = 0, upkeep = 0 },
		owned = { factories = 1, markets = 2, rigs = 3, forts = 0, cityLevels = 1 },
		spots = {},
	}
end

local function neighbour(id: number, power: number, extra: { [string]: any }?): BotBrain.Neighbour
	local n: BotBrain.Neighbour = {
		id = id,
		people = 1,
		power = power,
		frontPower = 0,
		atWar = false,
		canDeclare = true,
		border = 50,
		share = 0.1,
		distracted = false,
		mix = { 1, 0, 0, 0 },
		cities = 1,
	}
	if extra ~= nil then
		for k, v in extra do
			(n :: any)[k] = v
		end
	end
	return n
end

T.describe("Боты v2: решения", function()
	local rng = Rng.new(5)

	T.it("уровни по весам Bots.LevelMix, личности — все пять", function()
		local r = Rng.new(11)
		local counts: { [string]: number } = {}
		local personalities: { [string]: boolean } = {}
		for _ = 1, 2000 do
			local level = BotBrain.rollLevel(r)
			counts[level] = (counts[level] or 0) + 1
			personalities[BotBrain.rollPersonality(r)] = true
		end
		local mix = Config.Bots.LevelMix :: { [string]: number }
		local total = mix.Novice + mix.Normal + mix.General
		for _, level in Types.BotLevels do
			T.expect((counts[level] or 0) / 2000).toBeNear(mix[level] / total, 0.04)
		end
		for _, p in Types.BotPersonalities do
			T.expect(personalities[p]).toBe(true)
		end
	end)

	T.it(
		"слабый фронт: Генерал отменяет быстро, Обычный — только совсем проигранный, Новичок — никогда",
		function()
			local v = view()
			v.neighbours = { neighbour(4, 3000, { atWar = true, canDeclare = false }) }
			v.attacks = 1
			v.fronts = {
				{ target = 4, ratio = 0.7, supplied = true, fighting = true, stalledSec = 15, power = 800 },
			}
			local g = BotBrain.decide(v, rng, profile("General"))
			T.expect(g ~= nil and g.kind == "cancel" and g.target == 4).toBe(true)
			local n = BotBrain.decide(v, rng, profile("Normal"))
			T.expect(n == nil or n.kind ~= "cancel").toBe(true)
			local fronts = v.fronts :: { BotBrain.FrontView }
			fronts[1].ratio, fronts[1].stalledSec = 0.3, 25
			local n2 = BotBrain.decide(v, rng, profile("Normal"))
			T.expect(n2 ~= nil and n2.kind == "cancel").toBe(true)
			local nv = BotBrain.decide(v, rng, profile("Novice"))
			T.expect(nv == nil or nv.kind ~= "cancel").toBe(true)
			-- Без снабжения и стоит — Генерал уводит войска даже при хорошем перевесе.
			fronts[1].ratio, fronts[1].supplied, fronts[1].stalledSec = 1.5, false, 12
			local g2 = BotBrain.decide(v, rng, profile("General"))
			T.expect(g2 ~= nil and g2.kind == "cancel").toBe(true)
		end
	)

	T.it(
		"состав войск: Генерал нанимает против состава врага и держит пехоту",
		function()
			local v = view()
			v.queue = 0
			v.people = 1000
			v.owned.barracksLevel = 3 -- §15д: вся техника открыта казармами ур. 3
			local general = profile("General")
			general.level = table.clone(general.level)
			general.level.hireChance = 1
			-- Враг — одни танки: лучший ответ — артиллерия.
			v.neighbours = { neighbour(4, 99999, { atWar = true, canDeclare = false, mix = { 0, 1, 0, 0 } }) }
			local h = BotBrain.decide(v, rng, general)
			T.expect(h ~= nil and h.kind == "hire" and h.unit == "Artillery").toBe(true)
			-- Враг — одна пехота: танки.
			v.neighbours = { neighbour(4, 99999, { atWar = true, canDeclare = false, mix = { 1, 0, 0, 0 } }) }
			local h2 = BotBrain.decide(v, rng, general)
			T.expect(h2 ~= nil and h2.kind == "hire" and h2.unit == "Tanks").toBe(true)
			-- Своей пехоты мало — сначала пехота.
			v.mix = { 0.1, 0.9, 0, 0 }
			local h3 = BotBrain.decide(v, rng, general)
			T.expect(h3 ~= nil and h3.kind == "hire" and h3.unit == "Infantry").toBe(true)
			-- Без завода — только пехота у всех.
			v.mix = { 0.5, 0.5, 0, 0 }
			v.owned = { factories = 0, markets = 0, rigs = 0, forts = 0, cityLevels = 1 }
			local h4 = BotBrain.decide(v, rng, general)
			T.expect(h4 ~= nil and h4.kind == "hire" and h4.unit == "Infantry").toBe(true)
			-- Оценка контр-типов сама по себе.
			T.expect(BotBrain.unitValue(3, { 0, 1, 0, 0 }) > BotBrain.unitValue(2, { 0, 1, 0, 0 })).toBe(true)
		end
	)

	T.it(
		"цель войны: Генерал выбирает лидера и отвлечённого, Обычный — слабейшего",
		function()
			local v = view()
			v.power = 6000
			v.neighbours = {
				neighbour(3, 600), -- самый слабый
				neighbour(4, 900, { share = 0.45 }), -- лидер к победе
			}
			local n = BotBrain.decide(v, rng, profile("Normal"))
			T.expect(n ~= nil and n.kind == "declare" and n.target == 3).toBe(true)
			local g = BotBrain.decide(v, rng, profile("General"))
			T.expect(g ~= nil and g.kind == "declare" and g.target == 4).toBe(true)
			v.neighbours = {
				neighbour(3, 600),
				neighbour(5, 800, { distracted = true }), -- уже воюет с другим
			}
			local c = BotBrain.decide(v, rng, profile("General", "Cunning"))
			T.expect(c ~= nil and c.kind == "declare" and c.target == 5).toBe(true)
		end
	)

	T.it(
		"решимость: Новичок лезет на почти равного, Генерал ждёт перевеса; Миролюбивый осторожнее",
		function()
			local v = view()
			v.power = 1000 -- отправят 400 / 600 / 700
			v.neighbours = { neighbour(3, 500) }
			local nv = BotBrain.decide(v, rng, profile("Novice"))
			T.expect(nv ~= nil and nv.kind == "declare").toBe(true)
			local g0 = BotBrain.decide(v, rng, profile("General"))
			T.expect(g0 == nil or g0.kind ~= "declare").toBe(true) -- может предложить торговлю, но не войну
			v.power = 2000
			local g = BotBrain.decide(v, rng, profile("General"))
			T.expect(g ~= nil and g.kind == "declare").toBe(true)
			v.power = 1200 -- Обычный отправит 720 ≥ 500, Миролюбивый — нет (нужно 750, отправит 648)
			local plain = BotBrain.decide(v, rng, profile("Normal"))
			T.expect(plain ~= nil and plain.kind == "declare").toBe(true)
			local p0 = BotBrain.decide(v, rng, profile("Normal", "Peaceful"))
			T.expect(p0 == nil or p0.kind ~= "declare").toBe(true)
		end
	)

	T.it(
		"фронт: Генерал бьёт в ближайший город и подкрепляет только до прорыва",
		function()
			local v = view()
			v.neighbours = { neighbour(4, 500, { atWar = true, canDeclare = false, city = 1234 }) }
			local g = BotBrain.decide(v, rng, profile("General"))
			T.expect(g ~= nil and g.kind == "attack" and g.target == 4 and g.focus == 1234).toBe(true)
			v.attacks = 1
			v.fronts = { { target = 4, ratio = 5, supplied = true, fighting = true, stalledSec = 0, power = 900 } }
			local g2 = BotBrain.decide(v, rng, profile("General"))
			T.expect(g2 == nil or g2.kind ~= "attack").toBe(true) -- прорыв и так идёт — войска держит дома
			local fronts = v.fronts :: { BotBrain.FrontView }
			fronts[1].ratio = 1.4
			local g3 = BotBrain.decide(v, rng, profile("General"))
			T.expect(g3 ~= nil and g3.kind == "attack" and g3.target == 4).toBe(true)
		end
	)

	T.it(
		"мир: Миролюбивый соглашается на белый мир охотнее Агрессора",
		function()
			local offer =
				{ terms = "white" :: Types.PeaceTerms, myGain = 10, theirGain = 0, myPower = 1200, theirPower = 1000 }
			T.expect(BotBrain.answerPeace(offer, BotBrain.profile("Normal", "Peaceful"))).toBe(true)
			T.expect(BotBrain.answerPeace(offer, BotBrain.profile("Normal", "Aggressor"))).toBe(false)
		end
	)
end)

T.describe("Боты v2 в матче", function()
	local function playing(seed: number, nations: number): MatchSim.Match
		local m = MatchSim.new(Fixtures.pangea, seed)
		m.targetNations = nations
		MatchSim.startPick(m)
		while m.phase ~= "Play" do
			MatchSim.step(m, DT)
		end
		m.victory = false
		return m
	end

	T.it(
		"у каждого бота уровень и личность; бюджет раздумий за тик",
		function()
			local m = playing(3, 40)
			for _, n in m.nations do
				T.expect(n.isBot).toBe(true)
				T.expect(table.find(Types.BotLevels, n.botLevel :: any) ~= nil).toBe(true)
				T.expect(table.find(Types.BotPersonalities, n.personality :: any) ~= nil).toBe(true)
			end
			-- Все думают сразу — за тик не больше бюджета.
			for id in m.botNextThink do
				m.botNextThink[id] = 0
			end
			MatchSim.step(m, DT)
			T.expect(m.botThinks).toBe(Config.Bots.MaxThinksPerTick)
			MatchSim.step(m, DT)
			T.expect(m.botThinks <= Config.Bots.MaxThinksPerTick).toBe(true)
		end
	)

	T.it("Генералу +10% дохода, остальным — нет", function()
		local m = playing(4, 4)
		MatchSim.setBot(m, 1, "General", "Admiral")
		MatchSim.setBot(m, 2, "Normal", "Admiral")
		MatchSim.step(m, DT)
		for id, mul in { [1] = 1 + Config.BotLevels.General.incomeBonus, [2] = 1 } do
			local owned = MatchSim.ownedOf(m, id)
			local base = Economy.income(Grid.cellsOf(m.grid, id), owned.cityLevels, owned.markets)
			T.expect(m.economy[id].income).toBeNear(base * mul, 1e-6)
		end
		T.expect(Config.BotLevels.General.incomeBonus).toBe(0.10)
	end)

	T.it("игрок ушёл — держава под Обычным ботом", function()
		local m = MatchSim.new(Fixtures.pangea, 6)
		MatchSim.addPlayer(m, 1, "A")
		m.targetNations = 3
		MatchSim.startPick(m)
		while m.phase ~= "Play" do
			MatchSim.step(m, DT)
		end
		T.expect(m.nations[1].isBot).toBe(false)
		T.expect(m.nations[1].botLevel).toBe(nil)
		MatchSim.removePlayer(m, 1)
		T.expect(m.nations[1].isBot).toBe(true)
		T.expect(m.nations[1].botLevel).toBe("Normal")
	end)
end)

T.describe("Автостарт на крупной суше", function()
	T.it("«Европа», 4 державы: никто не стартует на острове", function()
		local map = MapFormat.fromModule((require :: any)("../maps/Europe") :: MapFormat.MapModule)
		local g = Grid.new(map)
		local land = StartPositions.landmasses(map, g)
		local taken: { number } = {}
		local rng = Rng.new(1154)
		for _ = 1, 4 do
			local cell = StartPositions.autoPick(g, taken, rng, land) :: number
			T.expect(cell ~= nil).toBe(true)
			T.expect(buffer.readu32(land, cell * 4) >= g.capturableCount * Config.Start.MinLandmassShare).toBe(true)
			table.insert(taken, cell)
		end
	end)
end)

T.describe("Потоки случайных чисел", function()
	T.it(
		"решения одного бота не сдвигают случайные числа остальных (§12)",
		function()
			local function run(navy: number, air: number): { [number]: number }
				local m = MatchSim.new(Fixtures.pangea, 31)
				m.targetNations = 8
				MatchSim.startPick(m)
				while m.phase ~= "Play" do
					MatchSim.step(m, DT)
				end
				m.victory = false
				local profile = m.botProfiles[1]
				local personality = table.clone(profile.personality)
				personality.navy, personality.air = navy, air
				m.botProfiles[1] = { level = profile.level, personality = personality }
				-- Сколько раз подумал каждый бот к 60 с: зависит только от его потока «раздумий».
				local thinks: { [number]: number } = {}
				local last: { [number]: number } = {}
				for _ = 1, 60 * Config.Sim.TickRate do
					MatchSim.step(m, DT)
					for id, due in m.botNextThink do
						if last[id] ~= due then
							thinks[id] = (thinks[id] or 0) + 1
							last[id] = due
						end
					end
				end
				return thinks
			end
			local a, b = run(0, 0), run(1, 1)
			for id = 2, 8 do
				T.expect(a[id]).toBe(b[id])
			end
		end
	)
end)
