--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Config = require("../src/shared/Config")
local Forces = require("../src/shared/Forces")
local MatchSim = require("../src/shared/MatchSim")
local Profile = require("../src/shared/Profile")
local Shop = require("../src/shared/Shop")
local Types = require("../src/shared/Types")

local DT = 1 / Config.Sim.TickRate
local INF = Forces.kindIndex("Infantry") :: number

local function played(mode: Types.ModeId?, humans: number): MatchSim.Match
	local m = MatchSim.new(Fixtures.pangea, 41)
	m.targetNations = 4
	for k = 1, humans do
		MatchSim.addPlayer(m, 100 + k, "P" .. k)
	end
	m.forcedMode = mode
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, DT)
	end
	m.victory = false
	return m
end

T.describe("Магазин: потолок и честность (§11.1)", function()
	T.it(
		"каждый платный эффект — не больше потолка MaxEdge; заём — не больше половины стартовых денег",
		function()
			local cfg = Config.Shop
			T.expect(cfg.MaxEdge <= 0.15).toBe(true)
			T.expect(cfg.Boosts.Mobilize.garrisonShare <= cfg.MaxEdge).toBe(true)
			T.expect(cfg.Passes.HQ.incomeMul - 1 <= cfg.MaxEdge).toBe(true)
			T.expect(cfg.Passes.HQ.recruitLines <= 1).toBe(true)
			T.expect(cfg.Boosts.Loan.money <= Config.Economy.StartMoney * 0.5).toBe(true)
			-- У каждого буста есть бесплатный путь — жетон (продукт без id всё равно доступен за жетон).
			for _, key in Shop.BoostKeys do
				T.expect((Config.Shop.Boosts :: any)[key] ~= nil).toBe(true)
			end
			T.expect(Config.Profile.TokenEveryLevels > 0).toBe(true)
		end
	)

	T.it("перки пассов; продукт по id; без id — не найден", function()
		local none = Shop.perks({})
		T.expect(none.incomeMul).toBe(1)
		local all = Shop.perks({ HQ = true, Intel = true, Vip = true })
		T.expect(all.recruitLines).toBe(1)
		T.expect(all.incomeMul).toBeNear(Config.Shop.Passes.HQ.incomeMul)
		T.expect(all.intelCostMul).toBeNear(0.5)
		T.expect(all.xpMul).toBeNear(1.5)
		T.expect((Shop.productById(0))).toBe(nil)
	end)
end)

T.describe("Профиль (§11.2)", function()
	T.it(
		"уровни по опыту, награда за матч, жетоны каждые 2 уровня",
		function()
			local need1 = Profile.xpNeeded(1)
			T.expect(need1).toBe(Config.Profile.XpBase)
			T.expect(Profile.xpNeeded(2) > need1).toBe(true)
			T.expect((Profile.levelOf(0))).toBe(1)
			T.expect((Profile.levelOf(need1))).toBe(2)
			local xp1 = Profile.matchReward(1, 5, true, 1)
			local xp4 = Profile.matchReward(4, 0, false, 1)
			T.expect(xp1 > xp4).toBe(true)
			local vip = Profile.matchReward(4, 0, false, 1.5)
			T.expect(vip).toBe(math.floor(xp4 * 1.5))
			local d = Profile.new()
			local _, tokens = Profile.addXp(d, need1 + Profile.xpNeeded(2)) -- до 3-го уровня
			T.expect((Profile.levelOf(d.xp))).toBe(3)
			T.expect(tokens).toBe(1) -- уровень 2 — жетон
			local before = d.medals
			Profile.applyMatch(d, 1, 3, true, 1)
			T.expect(d.matches).toBe(1)
			T.expect(d.wins).toBe(1)
			T.expect(d.medals > before).toBe(true)
		end
	)

	T.it(
		"миграция мусора; покупка начисляется один раз; разовый набор — один раз и до 10-го уровня",
		function()
			local d = Profile.migrate({
				xp = -5,
				medals = "много",
				tokens = 2,
				stock = { Loan = 1, Hack = 9 },
				purchases = { "a", 3 :: any },
			})
			T.expect(d.xp).toBe(0)
			T.expect(d.medals).toBe(0)
			T.expect(d.tokens).toBe(2)
			T.expect(d.stock.Loan).toBe(1)
			T.expect(d.stock.Hack).toBe(nil)
			T.expect(#d.purchases).toBe(1)
			T.expect(Profile.grantProduct(d, "boost", "Mobilize", "p1")).toBe(true)
			T.expect(Profile.grantProduct(d, "boost", "Mobilize", "p1")).toBe(true) -- повтор — без второго начисления
			T.expect(d.stock.Mobilize).toBe(1)
			T.expect(Profile.packAvailable(d, "Recruit")).toBe(true)
			T.expect(Profile.grantProduct(d, "pack", "Recruit", "p2")).toBe(true)
			T.expect(d.tokens).toBe(2 + Config.Shop.Packs.Recruit.tokens)
			T.expect(Profile.packAvailable(d, "Recruit")).toBe(false)
			T.expect(Profile.grantProduct(d, "pack", "Recruit", "p3")).toBe(false)
			local veteran = Profile.new()
			veteran.xp = 1e7
			T.expect(Profile.packAvailable(veteran, "Recruit")).toBe(false)
			T.expect(Profile.grantProduct(d, "boost", "Nuke", "p4")).toBe(false)
		end
	)

	T.it(
		"генералы по уровню; пасс «Все генералы» открывает всех",
		function()
			local d = Profile.new()
			T.expect(Profile.commanderUnlocked(d, "Marshal", false)).toBe(true)
			T.expect(Profile.commanderUnlocked(d, "Scout", false)).toBe(false)
			T.expect(Profile.commanderUnlocked(d, "Scout", true)).toBe(true)
			local open = Profile.unlockedCommanders(d, false)
			T.expect(open.Marshal).toBe(true)
			T.expect(open.Engineer == true).toBe(false)
		end
	)
end)

T.describe("Бусты и перки в матче (§11.1)", function()
	T.it(
		"буст — один каждого вида за матч; эффекты; в дуэли — нельзя",
		function()
			local m = played(nil, 1)
			local n = m.nations[1]
			local money = n.money
			T.expect((MatchSim.useBoost(m, 1, "Loan"))).toBe(true)
			T.expect(n.money).toBeNear(money + Config.Shop.Boosts.Loan.money)
			T.expect(select(2, MatchSim.useBoost(m, 1, "Loan"))).toBe("boostUsed")
			Forces.add(n.home, INF, 1000)
			local before = Forces.total(n.home)
			T.expect((MatchSim.useBoost(m, 1, "Mobilize"))).toBe(true)
			T.expect(Forces.total(n.home)).toBeNear(before * (1 + Config.Shop.Boosts.Mobilize.garrisonShare))
			T.expect(select(2, MatchSim.useBoost(m, 1, "Research"))).toBe("noResearch")
			T.expect((MatchSim.useBoost(m, 1, "Reserve"))).toBe(true)
			T.expect(select(2, MatchSim.useBoost(m, 2, "Loan"))).toBe("dead") -- бот
			local duel = played("Duel", 2)
			T.expect(select(2, MatchSim.useBoost(duel, 1, "Loan"))).toBe("noBoosts")
		end
	)

	T.it(
		"перки «Штаба» и «Разведуправления» действуют, в дуэли — нет; закрытый генерал — отказ",
		function()
			local m = played(nil, 1)
			local base = MatchSim.recruitLines(m, 1)
			MatchSim.setPerks(m, 1, Shop.perks({ HQ = true, Intel = true }))
			T.expect(MatchSim.recruitLines(m, 1)).toBe(base + 1)
			m.nations[1].money = 10000
			T.expect((MatchSim.spy(m, m.nations[1], 2))).toBe(true)
			T.expect(m.nations[1].money).toBeNear(10000 - Config.Intel.Cost * 0.5)
			local duel = played("Duel", 2)
			MatchSim.setPerks(duel, 1, Shop.perks({ HQ = true }))
			T.expect(MatchSim.perksOf(duel, 1).recruitLines).toBe(0)
			-- Генералы по уровню: закрытый — отказ в лобби.
			local lobby = MatchSim.new(Fixtures.pangea, 3)
			local id = MatchSim.addPlayer(lobby, 1, "A") :: number
			MatchSim.setUnlocked(lobby, id, { Marshal = true })
			T.expect(select(2, MatchSim.applyIntent(lobby, id, { kind = "commander", commander = "Scout" })))
				.toBe("locked")
			T.expect((MatchSim.applyIntent(lobby, id, { kind = "commander", commander = "Marshal" }))).toBe(true)
		end
	)
end)
