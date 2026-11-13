--!strict
-- Окно «Стабильность»: порядок провинций и метки (§15ц Ц4а).
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local StabilityList = require("../src/shared/StabilityList")

T.describe("Окно стабильности (§15ц Ц4а)", function()
	local cfg = Config.Stability

	T.it(
		"метка по порогам: ниже RevoltBelow — восстание, ниже LowBelow — доход ×0.5",
		function()
			T.expect(StabilityList.level(cfg.RevoltBelow - 1)).toBe("revolt")
			T.expect(StabilityList.level(cfg.RevoltBelow)).toBe("low")
			T.expect(StabilityList.level(cfg.LowBelow - 1)).toBe("low")
			T.expect(StabilityList.level(cfg.LowBelow)).toBe("ok")
			T.expect(StabilityList.level(100)).toBe("ok")
		end
	)

	T.it(
		"строки от худшей к лучшей, равные — по номеру; счётчики и самая слабая",
		function()
			local rows = StabilityList.rows({ 7, 3, 9, 5 }, { 80, cfg.RevoltBelow - 5, 80, cfg.LowBelow - 1 })
			T.expect(#rows).toBe(4)
			T.expect(rows[1].province).toBe(3)
			T.expect(rows[1].level).toBe("revolt")
			T.expect(rows[2].province).toBe(5)
			T.expect(rows[2].level).toBe("low")
			T.expect(rows[3].province).toBe(7)
			T.expect(rows[4].province).toBe(9)
			local c = StabilityList.counts(rows)
			T.expect(c.revolt).toBe(1)
			T.expect(c.low).toBe(1)
			T.expect(c.ok).toBe(2)
			T.expect(StabilityList.worst(rows)).toBe(3)
			T.expect(StabilityList.worst(StabilityList.rows({}, {}))).toBe(nil)
		end
	)
end)
