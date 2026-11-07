--!strict
-- Арсенал (§15л ч.6): покупка за медали от уровня, одно в бой, раз за матч, в потолке силы, без «Дуэли».
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Arsenal = require("../src/shared/Arsenal")
local Commanders = require("../src/shared/Commanders")
local Config = require("../src/shared/Config")
local Forces = require("../src/shared/Forces")
local MatchSim = require("../src/shared/MatchSim")
local Profile = require("../src/shared/Profile")

local DT = 1 / Config.Sim.TickRate

local function played(): MatchSim.Match
	local m = MatchSim.new(Fixtures.pangea, 61)
	m.targetNations = 3
	MatchSim.addPlayer(m, 1, "A")
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, DT)
	end
	m.victory = false
	return m
end

T.describe("Арсенал (§15л ч.6)", function()
	T.it(
		"все предметы — в списке, в потолке MaxEdge, цена и уровень растут",
		function()
			local items = Config.Arsenal.Items
			local count = 0
			for _ in items do
				count += 1
			end
			T.expect(#Config.Arsenal.Order).toBe(count)
			local maxEdge = Config.Shop.MaxEdge
			T.expect(items.Reinforce.powerShare <= maxEdge).toBe(true)
			T.expect(items.Barrage.frontLoss <= maxEdge).toBe(true)
			T.expect(items.Convoy.money <= Config.Shop.Boosts.Loan.money * 1.5).toBe(true)
			local prevPrice, prevLevel = 0, 0
			for _, key in Config.Arsenal.Order do
				local it = items[key]
				T.expect(it.price > prevPrice and it.level > prevLevel).toBe(true)
				prevPrice, prevLevel = it.price, it.level
			end
		end
	)

	T.it(
		"покупка: уровень, медали, навсегда; первое берётся в бой; брать — только открытое",
		function()
			local d = Profile.new()
			T.expect(select(2, Arsenal.buy(d, "Reinforce", 1))).toBe("level")
			T.expect(select(2, Arsenal.buy(d, "Reinforce", 5))).toBe("medals")
			d.medals = 5000
			T.expect((Arsenal.buy(d, "Reinforce", 5))).toBe(true)
			T.expect(d.medals).toBe(3500)
			T.expect(d.loadout).toBe("Reinforce")
			T.expect(select(2, Arsenal.buy(d, "Reinforce", 5))).toBe("owned")
			T.expect(select(2, Arsenal.equip(d, "Convoy"))).toBe("target")
			T.expect((Arsenal.buy(d, "Convoy", 6))).toBe(true)
			T.expect(d.loadout).toBe("Reinforce") -- второе не меняет выбранное
			T.expect((Arsenal.equip(d, "Convoy"))).toBe(true)
			T.expect(d.loadout).toBe("Convoy")
			T.expect(select(2, Arsenal.buy(d, "Nuke", 99))).toBe("target")
			-- Сохранение и загрузка: открытое и выбранное живут; мусор отбрасывается.
			local back = Profile.migrate({ arsenal = { Convoy = true, Nuke = true }, loadout = "Reinforce" })
			T.expect(back.arsenal.Convoy).toBe(true)
			T.expect(back.arsenal.Nuke).toBe(nil)
			T.expect(back.loadout).toBe(nil) -- Reinforce не открыт
		end
	)

	T.it(
		"в матче: раз за матч, только взятое; подкрепление, конвой, резерв штаба",
		function()
			local m = played()
			local n = m.nations[1]
			T.expect(select(2, MatchSim.useArsenal(m, 1))).toBe("noArsenal")
			MatchSim.setArsenal(m, 1, "Reinforce")
			local inf = Forces.kindIndex("Infantry") :: number
			local before = n.home[inf].strength
			T.expect((MatchSim.useArsenal(m, 1))).toBe(true)
			T.expect(n.home[inf].strength - before >= Config.Arsenal.Items.Reinforce.minStrength - 1e-6).toBe(true)
			T.expect(select(2, MatchSim.useArsenal(m, 1))).toBe("arsenalUsed")

			local m2 = played()
			MatchSim.setArsenal(m2, 1, "Convoy")
			local money = m2.nations[1].money
			T.expect((MatchSim.useArsenal(m2, 1))).toBe(true)
			T.expect(m2.nations[1].money - money).toBe(Config.Arsenal.Items.Convoy.money)

			local m3 = played()
			MatchSim.setArsenal(m3, 1, "HqReserve")
			T.expect((MatchSim.useArsenal(m3, 1))).toBe(true)
			T.expect(Commanders.of(m3.commanders, 1) ~= nil).toBe(true)

			-- По клетке: врага рядом нет — не тратится.
			local m4 = played()
			MatchSim.setArsenal(m4, 1, "Barrage")
			T.expect((MatchSim.useArsenal(m4, 1, m4.nations[1].capital))).toBe(false)
			T.expect(m4.arsenalUsed[1]).toBe(nil)
			MatchSim.setArsenal(m4, 1, "Jammer")
			T.expect(select(2, MatchSim.useArsenal(m4, 1, m4.nations[1].capital))).toBe("noTarget")
			T.expect(select(2, MatchSim.useArsenal(m4, 1, -5))).toBe("focus")
		end
	)

	T.it(
		"без бустов (Дуэль, Обучение) — нельзя; неизвестный предмет не ставится",
		function()
			local m = played()
			local rules = table.clone(m.rules)
			rules.boosts = false
			m.rules = rules
			MatchSim.setArsenal(m, 1, "Convoy")
			T.expect(select(2, MatchSim.useArsenal(m, 1))).toBe("noBoosts")
			MatchSim.setArsenal(m, 1, "Nuke")
			T.expect(m.arsenal[1]).toBe(nil)
		end
	)
end)
