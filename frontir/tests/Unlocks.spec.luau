--!strict
-- §15э Э1: танки, артиллерия, ПВО и ракетная шахта закрыты в профиле — «Путь командира» или магазин.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Config = require("../src/shared/Config")
local MatchSim = require("../src/shared/MatchSim")
local Modes = require("../src/shared/Modes")
local Profile = require("../src/shared/Profile")
local Shop = require("../src/shared/Shop")

local function xpFor(level: number): number
	local xp = 0
	for lv = 1, level - 1 do
		xp += Profile.xpNeeded(lv)
	end
	return xp
end

T.describe("Закрытая техника: профиль (§15э Э1)", function()
	T.it(
		"новичку закрыта вся техника, уровень «Пути» открывает её по порядку",
		function()
			local d = Profile.new()
			for _, key in Config.Unlocks.Order do
				T.expect(Profile.unitUnlocked(d, key)).toBe(false)
			end
			T.expect(Profile.unitUnlocked(d, "Infantry")).toBe(true) -- не в списке — открыто всегда
			local prev = 1
			for _, key in Config.Unlocks.Order do
				local level = Config.Unlocks.Items[key].level
				T.expect(level > prev).toBe(true) -- ранние вехи: по возрастанию
				d.xp = xpFor(level) - 1
				T.expect(Profile.unitUnlocked(d, key)).toBe(false)
				d.xp = xpFor(level)
				T.expect(Profile.unitUnlocked(d, key)).toBe(true)
				T.expect(Profile.pathReward(level).unit).toBe(key)
				prev = level
			end
			T.expect(Profile.pathReward(2).unit).toBe(nil)
		end
	)

	T.it(
		"покупка открывает технику навсегда; «Вся техника» — всё сразу; повтор покупки не ломает",
		function()
			local d = Profile.new()
			T.expect(Profile.grantProduct(d, "unlock", "Artillery", "p1")).toBe(true)
			T.expect(Profile.unitUnlocked(d, "Artillery")).toBe(true)
			T.expect(Profile.unitUnlocked(d, "Tanks")).toBe(false)
			T.expect(Profile.grantProduct(d, "unlock", "Artillery", "p1")).toBe(true)
			T.expect(Profile.grantProduct(d, "unlock", "Nope", "p2")).toBe(false)
			T.expect(Profile.grantProduct(d, "unlock", "All", "p3")).toBe(true)
			local set = Profile.unlockedUnits(d)
			for _, key in Config.Unlocks.Order do
				T.expect(set[key]).toBe(true)
			end
			-- Сохранение переживает загрузку.
			local back = Profile.migrate(d :: any)
			T.expect(Profile.unitUnlocked(back, "Missile")).toBe(true)
		end
	)

	T.it(
		"набор «Вся техника» дешевле, чем всё по отдельности; цены — в Config",
		function()
			local sum = 0
			for _, key in Config.Unlocks.Order do
				T.expect(Config.Unlocks.Items[key].price > 0).toBe(true)
				sum += Config.Unlocks.Items[key].price
			end
			T.expect(Config.Unlocks.All.price < sum).toBe(true)
		end
	)

	T.it(
		"магазин узнаёт продукт техники по id (0 — ещё не заведён)",
		function()
			T.expect((Shop.productById(0))).toBe(nil)
			for _, key in Config.Unlocks.Order do
				local id = Config.Unlocks.Items[key].id
				if id ~= 0 then
					local kind, k = Shop.productById(id)
					T.expect(kind).toBe("unlock")
					T.expect(k).toBe(key)
				end
			end
		end
	)
end)

T.describe("Закрытая техника: матч (§15э Э1)", function()
	local function match(): MatchSim.Match
		local m = MatchSim.new(TinyMap.plains(64, 32), 5)
		m.victory = false
		MatchSim.addPlayer(m, 1, "A")
		MatchSim.addPlayer(m, 2, "B")
		m.phase = "Play"
		for _, n in m.nations do
			n.capital = n.id * 10 + 32 * 8 -- найм идёт в столицу
		end
		return m
	end

	T.it(
		"закрытую технику не нанять и шахту не построить — с понятной причиной",
		function()
			local m = match()
			MatchSim.setUnitUnlocks(m, 1, {})
			local ok, reason = MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Tanks" })
			T.expect(ok).toBe(false)
			T.expect(reason).toBe("unitLocked")
			ok, reason = MatchSim.applyIntent(m, 1, { kind = "build", building = "MissileSilo", cell = 0 })
			T.expect(ok).toBe(false)
			T.expect(reason).toBe("siloLocked")
			-- Пехота открыта всем: отказ, если есть, — не из-за блокировки.
			local _, why = MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Infantry" })
			T.expect(why ~= "unitLocked").toBe(true)
		end
	)

	T.it(
		"открытая техника — по обычным правилам; без профиля (бот) — открыто всё",
		function()
			local m = match()
			MatchSim.setUnitUnlocks(m, 1, { Tanks = true })
			local _, why = MatchSim.applyIntent(m, 1, { kind = "hire", unit = "Tanks" })
			T.expect(why ~= "unitLocked").toBe(true)
			T.expect(MatchSim.unitAllowed(m, 1, "Artillery")).toBe(false)
			T.expect(MatchSim.unitAllowed(m, 2, "Artillery")).toBe(true) -- без набора (бот)
			T.expect(MatchSim.unitAllowed(m, 2, "Missile")).toBe(true)
		end
	)

	T.it("в «Дуэли» блокировок нет — равные условия", function()
		local m = match()
		m.rules = Modes.rules("Duel")
		MatchSim.setUnitUnlocks(m, 1, {})
		T.expect(MatchSim.unitAllowed(m, 1, "Tanks")).toBe(true)
		T.expect(MatchSim.unitAllowed(m, 1, "Missile")).toBe(true)
	end)
end)

T.describe("Клиент: закрытая техника и метки наград (§15э Э1, Э3)", function()
	local ClientState = require("../src/shared/ClientState")

	local function withProfile(p: { [string]: any }): ClientState.ClientState
		local cs = ClientState.new(8, 8)
		cs.profile = p :: any
		return cs
	end

	T.it(
		"unitOpen: закрыто до уровня; профиль не пришёл — открыто; дуэль — открыто",
		function()
			local cs = ClientState.new(8, 8)
			T.expect((ClientState.unitOpen(cs, "Tanks"))).toBe(true)
			cs = withProfile({ unitUnlocks = { Tanks = true }, level = 1, season = { tier = 0 } })
			T.expect((ClientState.unitOpen(cs, "Tanks"))).toBe(true)
			local open, level = ClientState.unitOpen(cs, "Missile")
			T.expect(open).toBe(false)
			T.expect(level).toBe(Config.Unlocks.Items.Missile.level)
			T.expect((ClientState.unitOpen(cs, "Infantry"))).toBe(true)
			cs.mode.mode = "Duel" :: any
			T.expect((ClientState.unitOpen(cs, "Missile"))).toBe(true)
		end
	)

	T.it(
		"rewardsPending: путь, бесплатная и премиум-дорога; премиум без покупки не ждёт",
		function()
			local cs = withProfile({
				level = 9,
				path = { claimed = 6 },
				season = { tier = 5, xp = 0, per = 400, premium = false, free = 2, paid = 0 },
			})
			local path, free, paid = ClientState.rewardsPending(cs)
			T.expect(path).toBe(3)
			T.expect(free).toBe(3)
			T.expect(paid).toBe(0)
			local p = cs.profile :: any
			p.season.premium = true
			path, free, paid = ClientState.rewardsPending(cs)
			T.expect(paid).toBe(5)
			-- Старый сервер без счётчиков — ничего не ждёт.
			p.path = nil
			p.season = { tier = 5, xp = 0, per = 400, premium = true }
			path, free, paid = ClientState.rewardsPending(cs)
			T.expect(path + free + paid).toBe(0)
			path, free, paid = ClientState.rewardsPending(ClientState.new(8, 8))
			T.expect(path + free + paid).toBe(0)
		end
	)
end)
