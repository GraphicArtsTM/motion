--!strict
-- Окно державы (§15й Й7): какие действия видны и почему нельзя.
local T = require("./lib/TestKit")
local NationCard = require("../src/shared/NationCard")

local function base(): NationCard.Facts
	return {
		atWar = false,
		mobilizing = false,
		treaty = nil,
		breaking = false,
		trust = false,
		trustWait = 0,
		trade = false,
		cooldown = 0,
		diplomacy = true,
		teammate = false,
		intelOpen = true,
		intelWait = 0,
		powerKnown = false,
		money = 5000,
		giftMoney = 1000,
	}
end

local function find(list: { NationCard.Action }, key: string): NationCard.Action?
	for _, a in list do
		if a.key == key then
			return a
		end
	end
	return nil
end

local function keys(list: { NationCard.Action }): { string }
	local out: { string } = {}
	for _, a in list do
		table.insert(out, a.key)
	end
	return out
end

T.describe("Окно державы (§15й Й7)", function()
	T.it(
		"мир без договора: война, требование, союз, пакт, торговля, подарок, разведка, столица, дипломатия",
		function()
			T.expect(keys(NationCard.actions(base()))).toEqual({
				"declare",
				"demand",
				"alliance",
				"pact",
				"trade",
				"gift",
				"intel",
				"capital",
				"diplomacy",
			})
			local declare = find(NationCard.actions(base()), "declare") :: NationCard.Action
			T.expect(declare.enabled).toBe(true)
			T.expect(declare.warn).toBe(nil)
		end
	)

	T.it(
		"после мира — «через N с»; при договоре — предупреждение «предательство»",
		function()
			local f = base()
			f.cooldown = 30
			local d = find(NationCard.actions(f), "declare") :: NationCard.Action
			T.expect(d.enabled).toBe(false)
			T.expect(d.why).toBe("cooldown")
			local g = base()
			g.treaty = "pact"
			T.expect((find(NationCard.actions(g), "declare") :: NationCard.Action).warn).toBe("betray")
			T.expect(find(NationCard.actions(g), "pact")).toBe(nil) -- пакт уже есть
		end
	)

	T.it(
		"союз: «Полное доверие» с отсчётом, без союза и пакта в списке",
		function()
			local f = base()
			f.treaty = "alliance"
			f.trustWait = 40
			local list = NationCard.actions(f)
			local trust = find(list, "trust") :: NationCard.Action
			T.expect(trust.enabled).toBe(false)
			T.expect(trust.why).toBe("trustWait")
			T.expect(find(list, "alliance")).toBe(nil)
			f.trust = true
			T.expect(find(NationCard.actions(f), "trust")).toBe(nil)
		end
	)

	T.it(
		"война: к фронту и мир (в мобилизации — мир нельзя), без договоров",
		function()
			local f = base()
			f.mobilizing = true
			local list = NationCard.actions(f)
			T.expect((find(list, "peace") :: NationCard.Action).enabled).toBe(false)
			T.expect(find(list, "front") ~= nil).toBe(true)
			T.expect(find(list, "alliance")).toBe(nil)
			T.expect(find(list, "declare")).toBe(nil)
			f.mobilizing, f.atWar = false, true
			T.expect((find(NationCard.actions(f), "peace") :: NationCard.Action).enabled).toBe(true)
		end
	)

	T.it(
		"разведка: в блоке, сила известна, перезарядка; подарок — не хватает денег",
		function()
			local f = base()
			f.intelOpen = false
			T.expect((find(NationCard.actions(f), "intel") :: NationCard.Action).why).toBe("locked")
			f.intelOpen, f.powerKnown = true, true
			T.expect((find(NationCard.actions(f), "intel") :: NationCard.Action).why).toBe("known")
			f.powerKnown, f.intelWait = false, 20
			T.expect((find(NationCard.actions(f), "intel") :: NationCard.Action).why).toBe("intelWait")
			f.money = 10
			T.expect((find(NationCard.actions(f), "gift") :: NationCard.Action).why).toBe("money")
		end
	)

	T.it(
		"без дипломатии — только война, разведка и столица; со своей командой — без войны",
		function()
			local f = base()
			f.diplomacy = false
			T.expect(keys(NationCard.actions(f))).toEqual({ "declare", "intel", "capital" })
			local g = base()
			g.teammate = true
			local list = NationCard.actions(g)
			T.expect(find(list, "declare")).toBe(nil)
			T.expect(find(list, "intel")).toBe(nil)
			T.expect(#NationCard.inGroup(list, "diplo") > 0).toBe(true)
		end
	)

	T.it(
		"полоса «кто сильнее»: доля своей силы, скрытая — нет полосы",
		function()
			T.expect(NationCard.balance(300, 100)).toBe(0.75)
			T.expect(NationCard.balance(0, 0)).toBe(0.5)
			T.expect(NationCard.balance(300, -1)).toBe(nil)
		end
	)
end)
