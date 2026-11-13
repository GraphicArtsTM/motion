--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Buildings = require("../src/shared/Buildings")
local Config = require("../src/shared/Config")
local Forces = require("../src/shared/Forces")
local MatchSim = require("../src/shared/MatchSim")
local Profile = require("../src/shared/Profile")
local Shop = require("../src/shared/Shop")

local DT = 1 / Config.Sim.TickRate
local NOW = 1800000000 -- любое время: сезон без срока

local function played(): MatchSim.Match
	local m = MatchSim.new(Fixtures.pangea, 51)
	m.targetNations = 3
	MatchSim.addPlayer(m, 1, "A")
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, DT)
	end
	m.victory = false
	return m
end

T.describe("Платные части (§11.3)", function()
	T.it("в потолке: гвардия ≤ MaxEdge силы, авиаудар ≤ MaxEdge фронта", function()
		local b = Config.Shop.Boosts
		T.expect(b.Guards.powerShare <= Config.Shop.MaxEdge).toBe(true)
		T.expect(b.Airstrike.frontLoss <= Config.Shop.MaxEdge).toBe(true)
		for _, key in Shop.UnitKeys do
			T.expect(Shop.isBoost(key)).toBe(true)
		end
	end)

	T.it(
		"гвардия — танки 2★; эскадра — нужен порт; авиакрыло — нужен аэродром; авиаудар — нужен враг",
		function()
			local m = played()
			local n = m.nations[1]
			local tanks = Forces.kindIndex("Tanks") :: number
			local before = n.home[tanks].strength
			T.expect((MatchSim.useBoost(m, 1, "Guards"))).toBe(true)
			T.expect(n.home[tanks].strength - before >= Config.Shop.Boosts.Guards.minStrength - 1e-6).toBe(true)
			T.expect(Forces.stars(n.home[tanks]) >= 1).toBe(true)
			T.expect(select(2, MatchSim.useBoost(m, 1, "Squadron"))).toBe("noPort")
			T.expect(select(2, MatchSim.useBoost(m, 1, "AirWing"))).toBe("noAirfield")
			T.expect(select(2, MatchSim.useBoost(m, 1, "Airstrike", n.capital))).toBe("noEnemy")
			-- Аэродром у столицы — авиакрыло: два самолёта.
			local cap = n.capital :: number
			local province = require("../src/shared/MapData").getProvince(m.map, cap)
			Buildings.place(m.buildings, "Airfield", cap, province)
			MatchSim.refreshOwned(m)
			local planes = #m.air.planes
			T.expect((MatchSim.useBoost(m, 1, "AirWing"))).toBe(true)
			T.expect(#m.air.planes).toBe(planes + 2)
		end
	)
end)

T.describe("Ящики снабжения (§11.3)", function()
	T.it(
		"шансы в сумме 100%; гарантия джекпота не позже Pity-го ящика; часть — в запас",
		function()
			local sum = 0
			for _, o in Profile.crateOdds() do
				sum += o.percent
			end
			T.expect(sum).toBeNear(100)
			local d = Profile.new()
			d.crates = Config.Crates.Pity
			local lastKey: string? = nil
			for _ = 1, Config.Crates.Pity do
				lastKey = Profile.openCrate(d, function(_n: number): number
					return 1 -- всегда самая частая награда
				end)
			end
			T.expect(lastKey).toBe("jackpot")
			T.expect(d.pity).toBe(0)
			T.expect((Profile.openCrate(d, function(n: number): number
				return n
			end))).toBe(nil) -- ящиков нет
			d.crates = 1
			local unitRow = 0
			local acc = 0
			for k, row in Config.Crates.Table do
				if row.key == "unit" then
					unitRow = acc + 1
					break
				end
				acc += row.weight
				unitRow = k
			end
			local key, unit = Profile.openCrate(d, function(n: number): number
				return if n == #Shop.UnitKeys then 1 else unitRow
			end)
			T.expect(key).toBe("unit")
			T.expect(unit).toBe(Shop.UnitKeys[1])
			T.expect(d.stock[Shop.UnitKeys[1]]).toBe(1)
		end
	)
end)

T.describe(
	"Ежедневная награда, первая победа дня, предложение недели (§11.3)",
	function()
		T.it(
			"серия до 7, пропуск дня — заново, повтор в тот же день — ничего; 7-й день — ящик",
			function()
				local d = Profile.new()
				local day = 20000
				for k = 1, 7 do
					local streak = Profile.claimDaily(d, day + k - 1)
					T.expect(streak).toBe(k)
				end
				T.expect(d.crates).toBe(1)
				T.expect((Profile.claimDaily(d, day + 6))).toBe(nil)
				T.expect((Profile.claimDaily(d, day + 7))).toBe(1) -- по кругу
				T.expect((Profile.claimDaily(d, day + 9))).toBe(1) -- пропуск
			end
		)

		T.it(
			"первая победа дня — ×2 опыта, вторая — обычно; предложение недели — раз в неделю",
			function()
				local d = Profile.new()
				local first = Profile.applyMatch(d, 1, 0, true, 1, NOW)
				local second = Profile.applyMatch(d, 1, 0, true, 1, NOW)
				T.expect(first).toBe(second * Config.Daily.FirstWinMul)
				T.expect(d.xp).toBe(first + second)
				T.expect(Profile.packAvailable(d, "Weekly", NOW)).toBe(true)
				T.expect(Profile.grantProduct(d, "pack", "Weekly", "w1", NOW)).toBe(true)
				local offer = Shop.weeklyOffer(NOW)
				for key, n in offer.stock do
					T.expect(d.stock[key]).toBe(n)
				end
				T.expect(Profile.packAvailable(d, "Weekly", NOW)).toBe(false)
				T.expect(Profile.packAvailable(d, "Weekly", NOW + 7 * 86400)).toBe(true)
				T.expect(Shop.weekLeft(NOW) > 0 and Shop.weekLeft(NOW) <= 7 * 86400).toBe(true)
			end
		)
	end
)

T.describe(
	"Платные случайные награды (PolicyService, сводная правка ч.4)",
	function()
		T.it(
			"где запрещены: наборы ящиков не продаются, ящики за Robux — фиксированная награда",
			function()
				local c = Config.Crates.Restricted
				local d = Profile.new()
				d.noPaidRandom = true
				T.expect(Profile.packAvailable(d, "Crate1", NOW)).toBe(false)
				T.expect(Profile.packAvailable(d, "Crate5", NOW)).toBe(false)
				T.expect(Profile.packAvailable(d, "Weekly", NOW)).toBe(true)
				-- Куплен всё же (Robux списаны) — замена вместо ящиков.
				T.expect(Profile.grantProduct(d, "pack", "Crate5", "c5", NOW)).toBe(true)
				T.expect(d.crates).toBe(0)
				T.expect(d.medals).toBe(5 * c.medals)
				T.expect(d.tokens).toBe(5 * c.tokens)
				-- Премиум-дорога: ящиков нет ни на одном уровне (вместо них медали); бесплатные ящики пути остаются.
				T.expect(Profile.grantProduct(d, "pack", "PathPremium", "sp", NOW)).toBe(true)
				local paid, free = 0, 0
				for lv = 2, Config.Profile.MaxLevel do
					paid += Profile.premiumReward(lv).crates
					free += Profile.pathReward(lv).crates
				end
				Profile.addXp(d, Profile.xpToMax())
				Profile.pathClaim(d)
				T.expect(paid > 0).toBe(true)
				T.expect(d.crates).toBe(free)
			end
		)
		T.it("где разрешены — всё как было", function()
			local d = Profile.new()
			T.expect(Profile.packAvailable(d, "Crate1", NOW)).toBe(true)
			T.expect(Profile.grantProduct(d, "pack", "Crate5", "c5", NOW)).toBe(true)
			T.expect(d.crates).toBe(5)
			local r = { medals = 0, tokens = 0, crates = 2, stock = {} }
			T.expect(Profile.paidReward(r, false)).toBe(r)
		end)
	end
)
