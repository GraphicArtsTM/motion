--!strict
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Cosmetics = require("../src/shared/Cosmetics")
local Profile = require("../src/shared/Profile")

T.describe("Косметика и флаг (§11.4)", function()
	T.it(
		"покупка за медали; не хватает — отказ; повторно — уже есть; надеть только открытое",
		function()
			local d = Profile.new()
			T.expect(select(2, Cosmetics.buy(d, "pattern", "Stripes"))).toBe("noMedals")
			d.medals = 1000
			T.expect((Cosmetics.buy(d, "pattern", "Stripes"))).toBe(true)
			T.expect(d.medals).toBe(1000 - (Config.Cosmetics.Patterns[1].price :: number))
			T.expect(select(2, Cosmetics.buy(d, "pattern", "Stripes"))).toBe("already")
			T.expect(select(2, Cosmetics.buy(d, "pattern", "Lasers"))).toBe("target")
			T.expect((Cosmetics.equip(d, "pattern", "Stripes"))).toBe(true)
			T.expect(select(2, Cosmetics.equip(d, "pattern", "Grid"))).toBe("locked")
			T.expect(select(2, Cosmetics.equip(d, "layout", "Plain"))).toBe("target") -- части флага — через setFlag
			T.expect((Cosmetics.equip(d, "pattern", nil))).toBe(true)
			T.expect(d.equipped.pattern).toBe(nil)
		end
	)

	T.it(
		"титулы за уровень и с премиум-дороги «Пути»; не продаются за медали",
		function()
			local d = Profile.new()
			d.medals = 99999
			T.expect(select(2, Cosmetics.buy(d, "title", "Veteran"))).toBe("target")
			T.expect(Cosmetics.owns(d, "title", "Veteran")).toBe(false)
			Profile.addXp(d, 10 ^ 6)
			T.expect(Cosmetics.owns(d, "title", "Veteran")).toBe(true)
			T.expect(Cosmetics.owns(d, "title", "Legend")).toBe(false)
			T.expect(select(2, Cosmetics.buy(d, "title", "Legend"))).toBe("target") -- эксклюзив (§15ю Ю4)
			d.pathPremium = true
			Profile.pathClaim(d)
			T.expect(Cosmetics.owns(d, "title", "Legend")).toBe(true)
			T.expect(Cosmetics.owns(d, "pattern", "Diamonds")).toBe(true)
			-- Узоры премиум-дороги рисуются, где их ждёт гардероб.
			for _, id in { "Diamonds", "Chevron", "Camo", "Cross", "Bricks" } do
				local hits = 0
				for y = 0, 15 do
					for x = 0, 15 do
						if Cosmetics.patternHit(id, x, y) then
							hits += 1
						end
					end
				end
				T.expect(hits > 0 and hits < 256).toBe(true)
				local lv, premium = Cosmetics.pathSource("pattern", id)
				T.expect(lv ~= nil and premium).toBe(true)
			end
		end
	)

	T.it(
		"флаг: цвета из списка, базовые части бесплатно, остальные — после покупки; публичный вид",
		function()
			local d = Profile.new()
			local flag =
				{ bg = "Red", layout = "HStripe", layoutColor = "White", emblem = "Circle", emblemColor = "Gold" }
			T.expect((Cosmetics.setFlag(d, flag))).toBe(true)
			T.expect(
				select(
					2,
					Cosmetics.setFlag(
						d,
						{ bg = "Neon", layout = "Plain", layoutColor = "White", emblem = "None", emblemColor = "Gold" }
					)
				)
			).toBe("target")
			local fancy =
				{ bg = "Ink", layout = "Cross", layoutColor = "Gold", emblem = "Diamond", emblemColor = "Red" }
			T.expect(select(2, Cosmetics.setFlag(d, fancy))).toBe("locked")
			d.medals = 10000
			T.expect((Cosmetics.buy(d, "layout", "Cross"))).toBe(true)
			T.expect((Cosmetics.buy(d, "emblem", "Diamond"))).toBe(true)
			T.expect((Cosmetics.setFlag(d, fancy))).toBe(true)
			T.expect((Cosmetics.buy(d, "capture", "Gold"))).toBe(true)
			Cosmetics.equip(d, "capture", "Gold")
			local pub = Cosmetics.public(d, true)
			T.expect(pub.flag.layout).toBe("Cross")
			T.expect(pub.capture).toBe("Gold")
			T.expect(pub.vip).toBe(true)
			-- Сохранение и загрузка: косметика и флаг переживают миграцию.
			local back = Profile.migrate(d)
			T.expect(back.cosmetics["layout:Cross"]).toBe(true)
			T.expect(back.equipped.capture).toBe("Gold")
			T.expect((back.flag :: any).emblem).toBe("Diamond")
		end
	)

	T.it("узоры попадают в часть клеток, но не во все", function()
		for _, p in Config.Cosmetics.Patterns do
			local hits = 0
			for y = 0, 23 do
				for x = 0, 23 do
					if Cosmetics.patternHit(p.id, x, y) then
						hits += 1
					end
				end
			end
			T.expect(hits > 0 and hits < 24 * 24).toBe(true)
		end
	end)
end)
