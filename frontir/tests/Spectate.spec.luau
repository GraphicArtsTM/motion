--!strict
-- «Следить за лидером» (§15й Й5): главный удар лидера, без фронтов — столица; камера плавно догоняет цель.
local T = require("./lib/TestKit")
local Spectate = require("../src/shared/Spectate")

T.describe("Следить за лидером (§15й Й5)", function()
	T.it(
		"фронт против державы важнее ничьей земли, сильный важнее слабого, чужие атаки не в счёт",
		function()
			local attacks: { Spectate.AttackLike } = {
				{ attacker = 1, target = 0, focus = 10, power = 900 },
				{ attacker = 1, target = 3, focus = 20, power = 100 },
				{ attacker = 1, target = 4, focus = 30, power = 300 },
				{ attacker = 2, target = 1, focus = 40, power = 5000 },
			}
			T.expect(Spectate.target(attacks, 1, 99)).toBe(30)
			T.expect(Spectate.target({ attacks[1] }, 1, 99)).toBe(10)
			T.expect(Spectate.target({ attacks[4] }, 1, 99)).toBe(99)
			T.expect(Spectate.target({}, 1, nil)).toBe(nil)
		end
	)

	T.it(
		"шаг камеры: ближе к цели, не перелетает, без времени — на месте",
		function()
			local x, y = Spectate.step(0, 0, 100, 50, 0.1)
			T.expect(x > 0 and x < 100 and y > 0 and y < 50).toBe(true)
			local fx = Spectate.step(0, 0, 100, 50, 100)
			T.expect(fx <= 100 and fx > 99).toBe(true)
			T.expect((Spectate.step(5, 5, 100, 50, 0))).toBe(5)
		end
	)
end)
