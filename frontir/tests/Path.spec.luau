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
			T.expect(Profile.pathClaimable(d)).toBe(0)
			T.expect(#Profile.pathClaim(d)).toBe(0)
			Profile.addXp(d, totalTo(8))
			T.expect(Profile.pathClaimable(d)).toBe(7) -- уровни 2…8
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
