--!strict
-- Панель «АТАКИ» и фишки над полосой (§15ф Ф2).
local T = require("./lib/TestKit")
local AttackList = require("../src/shared/AttackList")

local function atk(attacker: number, target: number, power: number, ratio: number): AttackList.Attack
	return { attacker = attacker, target = target, power = power, troops = 0, ratio = ratio, supplied = true }
end

T.describe("Список атак (§15ф Ф2)", function()
	T.it(
		"свои атаки — первыми, по силе; потом на вас; чужие между другими — не видны",
		function()
			local list = {
				atk(3, 1, 500, 2), -- на нас
				atk(1, 4, 100, 0.5),
				atk(1, 0, 900, math.huge), -- расширение в ничью землю
				atk(5, 6, 9999, 3), -- нас не касается
				atk(7, 1, -1, 1), -- сила скрыта — в конце своих «на вас»
			}
			local rows, counts = AttackList.rows(list, 1, 10)
			T.expect(#rows).toBe(4)
			T.expect(rows[1].kind).toBe("out")
			T.expect(rows[1].other).toBe(0)
			T.expect(rows[2].other).toBe(4)
			T.expect(rows[3].kind).toBe("in")
			T.expect(rows[3].other).toBe(3)
			T.expect(rows[4].other).toBe(7)
			T.expect(counts.out).toBe(2)
			T.expect(counts.inc).toBe(2)
			T.expect(counts.hidden).toBe(0)
		end
	)

	T.it(
		"полоса перевеса: ratio/(1+ratio), у атаки на нас — доля обороны",
		function()
			T.expect(AttackList.share(1)).toBe(0.5)
			T.expect(AttackList.share(3)).toBe(0.75)
			T.expect(AttackList.share(math.huge)).toBe(1)
			T.expect(AttackList.share(0)).toBe(0)
			T.expect(AttackList.share(0 / 0)).toBe(0)
			local rows = AttackList.rows({ atk(2, 1, 10, 3) }, 1, 5)
			T.expect(rows[1].share).toBe(0.25)
			T.expect(rows[1].advancing).toBe(true)
		end
	)

	T.it(
		"не влезло — «ещё N»; фишки — только свои и не больше предела; без державы — пусто",
		function()
			local list = {}
			for k = 1, 8 do
				table.insert(list, atk(1, 10 + k, k * 10, 1))
			end
			table.insert(list, atk(2, 1, 5, 1))
			local rows, counts = AttackList.rows(list, 1, 6)
			T.expect(#rows).toBe(6)
			T.expect(counts.hidden).toBe(3)
			T.expect(rows[1].other).toBe(18) -- самая сильная
			local chips = AttackList.chips(list, 1, 5)
			T.expect(#chips).toBe(5)
			for _, c in chips do
				T.expect(c.kind).toBe("out")
			end
			local none, c0 = AttackList.rows(list, nil, 6)
			T.expect(#none).toBe(0)
			T.expect(c0.out + c0.inc).toBe(0)
		end
	)
end)
