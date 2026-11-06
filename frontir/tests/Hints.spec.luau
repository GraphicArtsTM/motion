--!strict
-- Подсказки «что делать дальше» (§15д ч.5).
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Hints = require("../src/shared/Hints")
local Strings = require("../src/shared/Strings")

local function facts(): Hints.Facts
	return {
		time = 30,
		tutorial = false,
		attacks = 0,
		people = 900,
		maxPeople = 1500,
		money = 0,
		barracks = 0,
		factories = 0,
		cityLevels = 1,
		cities = 1,
		troops = 0,
		atWar = false,
		bombed = false,
		batteries = 0,
		lowStability = false,
	}
end

T.describe("Подсказки (§15д ч.5)", function()
	T.it(
		"по порядку: расширение → казармы → завод → найм; сделано — подсказка уходит; закрытая — не показывается",
		function()
			local f = facts()
			T.expect(Hints.pick(f, {})).toBe("expand")
			f.attacks = 1
			T.expect(Hints.pick(f, {})).toBe(nil) -- денег нет — строить нечего
			f.money = Config.Buildings.Factory.cost
			T.expect(Hints.pick(f, {})).toBe("barracks")
			f.barracks = 1
			T.expect(Hints.pick(f, {})).toBe("factory")
			T.expect(Hints.pick(f, { factory = true })).toBe("hire")
			f.factories, f.troops = 1, Config.Hints.FewTroops
			T.expect(Hints.pick(f, {})).toBe("city")
			f.cityLevels = 2
			f.atWar = true
			T.expect(Hints.pick(f, {})).toBe("tanks")
			f.bombed = true
			T.expect(Hints.pick(f, { tanks = true })).toBe("defense")
			f.tutorial = true
			T.expect(Hints.pick(f, {})).toBe(nil) -- в обучении — свой ведущий
		end
	)

	T.it("у каждой подсказки есть текст на двух языках", function()
		for _, key in Hints.Order do
			T.expect(Strings.get("hint." .. key, "ru") ~= "hint." .. key).toBe(true)
			T.expect(Strings.get("hint." .. key, "en") ~= "hint." .. key).toBe(true)
		end
	end)
end)
