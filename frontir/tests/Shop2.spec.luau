--!strict
-- §15я Магазин 2.0: товары не противоречат друг другу, новые товары, выгода наборов.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Cosmetics = require("../src/shared/Cosmetics")
local Profile = require("../src/shared/Profile")
local Shop = require("../src/shared/Shop")

local NOW = 1800000000

local function totalTo(level: number): number
	local xp = 0
	for lv = 1, level - 1 do
		xp += Profile.xpNeeded(lv)
	end
	return xp
end

T.describe("Магазин 2.0: без противоречий (§15я Я1)", function()
	T.it(
		"премиум-дорога и «Премиум + 10 уровней» взаимоисключающие; есть премиум — оба скрыты",
		function()
			local d = Profile.new()
			T.expect(Profile.packAvailable(d, "PathPremium", NOW)).toBe(true)
			T.expect(Profile.packAvailable(d, "PathPremiumPlus", NOW)).toBe(true)
			T.expect(Profile.grantProduct(d, "pack", "PathPremiumPlus", "pp", NOW)).toBe(true)
			T.expect(d.pathPremium).toBe(true)
			T.expect((Profile.levelOf(d.xp))).toBe(11)
			T.expect(Profile.packAvailable(d, "PathPremium", NOW)).toBe(false)
			T.expect(Profile.packAvailable(d, "PathPremiumPlus", NOW)).toBe(false)
			T.expect(Profile.packAvailable(d, "Levels5", NOW)).toBe(true)
		end
	)

	T.it(
		"улучшение куплено в магазине — на премиум-дороге вместо него медали",
		function()
			local d = Profile.new()
			d.pathPremium = true
			d.xp = totalTo(30)
			local medals = 0
			for _, item in Profile.pathClaim(d, { AllCommanders = true }) do
				if item.premium and item.level == 30 then
					T.expect(item.reward.pass).toBe(nil)
					medals = item.reward.medals
				end
			end
			T.expect(medals).toBe(Profile.premiumReward(30).medals + Config.Path.Premium.PassRefund)
			-- Без покупки — улучшение на месте.
			local e = Profile.new()
			e.pathPremium = true
			e.xp = totalTo(30)
			local got = Profile.pathClaim(e)
			local seen = false
			for _, item in got do
				seen = seen or item.reward.pass == "AllCommanders"
			end
			T.expect(seen).toBe(true)
		end
	)

	T.it(
		"техника уже открыта (куплена / премиумом раньше) — на дороге медали, а не повтор",
		function()
			local d = Profile.new()
			d.pathPremium = true
			local tanks = Config.Unlocks.Items.Tanks
			d.xp = totalTo(tanks.level)
			local free, paid = nil :: any, nil :: any
			for _, item in Profile.pathClaim(d) do
				if item.level == tanks.level and not item.premium then
					free = item.reward
				end
				if item.level == tanks.premiumLevel and item.premium then
					paid = item.reward
				end
			end
			T.expect(paid.unit).toBe("Tanks") -- премиум открыл на своём уровне
			T.expect(free.unit).toBe(nil) -- бесплатная дорога позже — уже открыто
			local e = Profile.new()
			T.expect(Profile.grantProduct(e, "unlock", "Tanks", "u1", NOW)).toBe(true)
			e.xp = totalTo(tanks.level)
			for _, item in Profile.pathClaim(e) do
				if item.level == tanks.level then
					T.expect(item.reward.unit).toBe(nil)
					T.expect(item.reward.medals >= Config.Path.Premium.UnitRefund).toBe(true)
				end
			end
		end
	)

	T.it("уровни после 100-го идут в бонусы, а не пропадают", function()
		local d = Profile.new()
		d.xp = Profile.xpToMax()
		T.expect((Profile.bonusEarned(d))).toBe(0)
		T.expect(Profile.grantProduct(d, "pack", "Levels5", "l5", NOW)).toBe(true)
		T.expect((Profile.bonusEarned(d))).toBe(5)
	end)

	T.it(
		"ускоритель опыта: ×XpBoostMul за матчи, повторная покупка продлевает срок",
		function()
			local d = Profile.new()
			local plain = Profile.matchReward(1, 3, true, 1)
			T.expect(Profile.grantProduct(d, "pack", "XpBoost1", "x1", NOW)).toBe(true)
			local h = Config.Shop.Packs.XpBoost1.xpBoostHours * 3600
			T.expect(Profile.xpBoostLeft(d, NOW)).toBe(h)
			T.expect(Profile.grantProduct(d, "pack", "XpBoost1", "x2", NOW + 100)).toBe(true)
			T.expect(Profile.xpBoostLeft(d, NOW + 100)).toBe(2 * h - 100)
			d.firstWinDay = Profile.dayOf(NOW) -- без «первой победы дня»
			local xp = Profile.applyMatch(d, 1, 3, true, 1, NOW)
			T.expect(xp).toBe(math.floor(plain * Config.Shop.XpBoostMul))
			T.expect(Profile.xpBoostLeft(d, NOW + 3 * h)).toBe(0)
			T.expect(Profile.migrate(d :: any).xpBoostUntil).toBe(d.xpBoostUntil)
		end
	)

	T.it(
		"«Парадный набор»: эксклюзив магазина, разово; повторная покупка не ломает",
		function()
			local d = Profile.new()
			T.expect(Profile.grantProduct(d, "pack", "ParadeSet", "ps", NOW)).toBe(true)
			T.expect(Cosmetics.owns(d, "pattern", "Stars")).toBe(true)
			T.expect(Cosmetics.owns(d, "capture", "Snow")).toBe(true)
			T.expect(Cosmetics.owns(d, "title", "Generalissimo")).toBe(true)
			T.expect(Profile.packAvailable(d, "ParadeSet", NOW)).toBe(false)
			T.expect(Cosmetics.packSource("title", "Generalissimo")).toBe("ParadeSet")
			T.expect((Cosmetics.pathSource("title", "Generalissimo"))).toBe(nil)
			T.expect(select(2, Cosmetics.buy(d, "pattern", "Stars"))).toBe("target") -- за медали не продаётся
		end
	)

	T.it(
		"выгода наборов честная: набор дешевле частей; у каждого товара — цена и картинка",
		function()
			local ItemArt = require("../src/shared/ItemArt")
			for _, key in { "Crate5", "XpBoost7", "PathPremiumPlus", "Weekly" } do
				local cfg = (Config.Shop.Packs :: any)[key]
				local parts = Shop.partsPrice(key, NOW) :: number
				T.expect(parts > cfg.price).toBe(true)
				T.expect(Shop.saving(cfg.price, parts) > 0).toBe(true)
			end
			-- Предложение недели дешевле частей в КАЖДУЮ неделю круга.
		for w = 0, #Config.Shop.WeeklyOffers - 1 do
			local at = Config.Modes.WeekStartUnix + w * 7 * 86400 + 3600
			T.expect((Shop.partsPrice("Weekly", at) :: number) > Config.Shop.Packs.Weekly.price).toBe(true)
		end
		T.expect(Shop.saving(100, 90)).toBe(0)
			T.expect(Shop.saving(50, 100)).toBe(50)
			T.expect(Config.Unlocks.All.price < (Shop.partsPrice("UnlockAll", NOW) :: number)).toBe(true)
			for _, key in Shop.PackKeys do
				local cfg = (Config.Shop.Packs :: any)[key]
				T.expect(cfg.price > 0).toBe(true)
				T.expect(ItemArt.has("shop." .. key)).toBe(true)
			end
			for tagKey, tag in Config.Shop.Tags do
				T.expect(tag == "hit" or tag == "new").toBe(true)
				T.expect((Config.Shop.Packs :: any)[tagKey] ~= nil).toBe(true)
			end
		end
	)
end)
