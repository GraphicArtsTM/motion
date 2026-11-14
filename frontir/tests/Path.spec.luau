--!strict
-- «Путь командира» 2.0 (§15щ Щ1): кривая опыта и награда за каждый уровень.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Cosmetics = require("../src/shared/Cosmetics")
local Profile = require("../src/shared/Profile")

local function totalTo(level: number): number
	local xp = 0
	for lv = 1, level - 1 do
		xp += Profile.xpNeeded(lv)
	end
	return xp
end

T.describe("Путь командира: опыт (§15щ Щ1)", function()
	T.it(
		"кривая линейная: каждый уровень дороже на XpStep, высшие звания достижимы",
		function()
			local cfg = Config.Profile
			T.expect(Profile.xpNeeded(1)).toBe(cfg.XpBase)
			T.expect(Profile.xpNeeded(11) - Profile.xpNeeded(10)).toBe(cfg.XpStep)
			-- Не слишком легко: 2-й уровень — не за один средний матч; 10-й — десятки матчей.
			local avgMatch = cfg.XpPlay + cfg.XpPlace[3] + cfg.XpPerCity * 8
			T.expect(Profile.xpNeeded(1) > avgMatch * 2).toBe(true)
			T.expect(totalTo(10) / avgMatch > 25).toBe(true)
			-- Но достижимо: командующий фронтом (86) — меньше 300 тыс. опыта, а 100-й — меньше 400 тыс.
			T.expect(totalTo(Config.Ranks.Tiers[#Config.Ranks.Tiers]) < 300000).toBe(true)
			T.expect(totalTo(Config.Profile.MaxLevel) < 400000).toBe(true)
			T.expect((Profile.levelOf(totalTo(86)))).toBe(86)
		end
	)
end)

T.describe("Путь командира: награды (§15щ Щ1)", function()
	T.it(
		"у каждого уровня 2…MaxLevel есть награда; ступени званий — с узором или вспышкой",
		function()
			for lv = 2, Config.Profile.MaxLevel do
				local r = Profile.pathReward(lv)
				T.expect(r.medals + r.tokens + r.crates > 0 or r.cosmetic ~= nil).toBe(true)
			end
			local r1 = Profile.pathReward(1)
			T.expect(r1.medals + r1.tokens + r1.crates).toBe(0)
			for k = 2, #Config.Ranks.Tiers do
				local r = Profile.pathReward(Config.Ranks.Tiers[k])
				T.expect(r.cosmetic ~= nil).toBe(true)
				local kind, id = string.match(r.cosmetic :: string, "^(%a+):(%a+)$")
				T.expect(Cosmetics.item(kind :: any, id :: string) ~= nil).toBe(true)
			end
			T.expect(Profile.pathReward(Config.Path.TokenEvery).tokens).toBe(1)
			T.expect(Profile.pathReward(Config.Path.CrateEvery).crates).toBe(1)
		end
	)

	T.it(
		"забрать: только пройденные, по порядку, один раз; узор, который уже есть, — медалями",
		function()
			local d = Profile.new()
			T.expect((Profile.pathClaimable(d))).toBe(0)
			T.expect(#Profile.pathClaim(d)).toBe(0)
			Profile.addXp(d, totalTo(8))
			T.expect((Profile.pathClaimable(d))).toBe(7) -- уровни 2…8
			d.cosmetics["pattern:Dots"] = true -- уровень 8 даёт «Dots» — уже куплен
			local medals0 = d.medals
			local got = Profile.pathClaim(d)
			T.expect(#got).toBe(7)
			T.expect(got[1].level).toBe(2)
			T.expect(got[7].level).toBe(8)
			T.expect(got[7].reward.cosmetic).toBe(nil) -- вместо узора — медали
			T.expect(d.cosmetics["capture:Sky"]).toBe(true) -- ступень 4
			local expect = 0
			for lv = 2, 8 do
				expect += Profile.pathReward(lv).medals
			end
			T.expect(d.medals - medals0 > expect).toBe(true) -- + цена «Dots»
			T.expect(d.pathClaimed).toBe(8)
			T.expect(#Profile.pathClaim(d)).toBe(0) -- второй раз — ничего
			local migrated = Profile.migrate({ xp = d.xp, pathClaimed = 8 })
			T.expect(migrated.pathClaimed).toBe(8)
			T.expect(Profile.migrate({ xp = 10 }).pathClaimed).toBe(1)
		end
	)
end)

T.describe("Единый путь: премиум-дорога (§15ю)", function()
	local Shop = require("../src/shared/Shop")

	T.it(
		"на каждом уровне премиум есть медали; бусты, ящики и жетоны по правилу; премиум богаче бесплатной",
		function()
			local paidMedals, freeMedals, stock, passes, cosmetics = 0, 0, 0, 0, 0
			local boostsSeen: { [string]: boolean } = {}
			for lv = 2, Config.Profile.MaxLevel do
				local p = Profile.premiumReward(lv)
				local f = Profile.pathReward(lv)
				T.expect(p.medals > 0).toBe(true)
				paidMedals += p.medals
				freeMedals += f.medals
				for key, n in p.stock do
					T.expect(Shop.isBoost(key)).toBe(true)
					boostsSeen[key] = true
					stock += n
				end
				if p.pass ~= nil then
					T.expect((Config.Shop.Passes :: any)[p.pass] ~= nil).toBe(true)
					passes += 1
				end
				if p.cosmetic ~= nil then
					cosmetics += 1
				end
			end
			T.expect(paidMedals >= freeMedals * 3).toBe(true)
			T.expect(stock >= 40).toBe(true)
			for _, key in Shop.BoostKeys do
				T.expect(boostsSeen[key]).toBe(true) -- все товары-бусты магазина есть на дороге
			end
			T.expect(passes).toBe(4)
			T.expect(cosmetics).toBe(19)
			T.expect(Profile.premiumReward(Config.Profile.MaxLevel).cosmetic).toBe("title:Legend")
		end
	)

	T.it(
		"эксклюзивная косметика: у каждой есть картинка и место на дороге, за медали не продаётся",
		function()
			local Cosmetics = require("../src/shared/Cosmetics")
			local ItemArt = require("../src/shared/ItemArt")
			for _, kind in { "pattern", "capture", "title" } do
				for _, it in Cosmetics.list(kind :: any) do
					T.expect(ItemArt.has(kind .. "." .. it.id)).toBe(true)
					if it.price == nil and it.level == nil then
						-- Эксклюзив: на «Пути» или в наборе магазина — ровно в одном месте (§15я Я1).
						local lv = Cosmetics.pathSource(kind :: any, it.id)
						local pack = Cosmetics.packSource(kind :: any, it.id)
						T.expect((lv ~= nil) ~= (pack ~= nil)).toBe(true)
					end
				end
			end
		end
	)

	T.it(
		"техника: бесплатно позже, с премиумом раньше; улучшения навсегда — только с премиумом",
		function()
			local d = Profile.new()
			d.xp = totalTo(Config.Unlocks.Items.Tanks.premiumLevel)
			T.expect(Profile.unitUnlocked(d, "Tanks")).toBe(false)
			d.pathPremium = true
			T.expect(Profile.unitUnlocked(d, "Tanks")).toBe(true)
			for _, key in Config.Unlocks.Order do
				local item = Config.Unlocks.Items[key]
				T.expect(item.premiumLevel < item.level).toBe(true)
				T.expect(Profile.pathReward(item.level).unit).toBe(key)
				T.expect(Profile.premiumReward(item.premiumLevel).unit).toBe(key)
			end
			T.expect(Config.Unlocks.Items.Tanks.level >= 10).toBe(true) -- не так легко (§15ю Ю2)
			d.xp = totalTo(30)
			T.expect(Profile.pathPasses(d).AllCommanders).toBe(true)
			T.expect(Profile.pathPasses(d).HQ).toBe(nil)
			T.expect(Profile.passesWith(d, { Intel = true }).Intel).toBe(true)
			d.pathPremium = false
			T.expect((next(Profile.pathPasses(d)))).toBe(nil)
		end
	)

	T.it(
		"забор: обе дороги по порядку; премиум куплен позже — его награды ждут; повтор — ничего",
		function()
			local d = Profile.new()
			d.xp = totalTo(6)
			local got = Profile.pathClaim(d)
			T.expect(#got).toBe(5)
			local free, paid = Profile.pathClaimable(d)
			T.expect(free + paid).toBe(0)
			T.expect(Profile.grantProduct(d, "pack", "PathPremium", "pp", 0)).toBe(true)
			T.expect(Profile.packAvailable(d, "PathPremium", 0)).toBe(false)
			free, paid = Profile.pathClaimable(d)
			T.expect(paid).toBe(5)
			local medals = d.medals
			got = Profile.pathClaim(d)
			T.expect(#got).toBe(5)
			for _, item in got do
				T.expect(item.premium).toBe(true)
			end
			T.expect(d.medals > medals).toBe(true)
			T.expect(d.cosmetics["capture:Orange"]).toBe(true) -- ур. 6 премиум
			T.expect(#Profile.pathClaim(d)).toBe(0)
			d.xp = totalTo(8)
			got = Profile.pathClaim(d)
			T.expect(#got).toBe(4)
			T.expect(got[1].level).toBe(7)
			T.expect(got[1].premium).toBe(false)
			T.expect(got[2].level).toBe(7)
			T.expect(got[2].premium).toBe(true)
		end
	)

	T.it(
		"после 100-го — бонусы каждые BonusXp опыта; опыт не пропадает",
		function()
			local d = Profile.new()
			d.pathPremium = true
			d.xp = Profile.xpToMax() + Config.Path.BonusXp * 2 + 10
			local earned, into, per = Profile.bonusEarned(d)
			T.expect(earned).toBe(2)
			T.expect(into).toBe(10)
			T.expect(per).toBe(Config.Path.BonusXp)
			local _, _, bonus = Profile.pathClaimable(d)
			T.expect(bonus).toBe(4) -- 2 бесплатных + 2 премиум
			local crates = d.crates
			local got = Profile.pathClaim(d)
			local bonuses = 0
			for _, item in got do
				if item.bonus then
					bonuses += 1
					T.expect(item.level > Config.Profile.MaxLevel).toBe(true)
				end
			end
			T.expect(bonuses).toBe(4)
			T.expect(d.crates > crates).toBe(true)
			T.expect(select(3, Profile.pathClaimable(d))).toBe(0)
		end
	)

	T.it(
		"старое сохранение: купивший пропуск сезона — премиум-дорога; 30-я ступень — «Легенда»",
		function()
			local back = Profile.migrate({ xp = 0, seasonPremium = true, seasonXp = 30 * 400 })
			T.expect(back.pathPremium).toBe(true)
			T.expect(back.cosmetics["title:Legend"]).toBe(true)
			local plain = Profile.migrate({ xp = 0, seasonPremium = false, seasonXp = 99999 })
			T.expect(plain.pathPremium).toBe(false)
			T.expect(plain.pathPaid).toBe(1)
		end
	)
end)
