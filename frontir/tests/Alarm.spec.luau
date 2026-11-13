--!strict
-- Тревога на экране матча (§15ш Ш2).
local T = require("./lib/TestKit")
local Alarm = require("../src/shared/Alarm")
local Config = require("../src/shared/Config")
local NationColors = require("../src/shared/NationColors")
local Palette = require("../src/shared/Palette")

T.describe("Тревога «нет войск» (§15ш Ш2)", function()
	T.it("плашка — только когда на вас атакуют, а войск нет", function()
		T.expect(Alarm.state(0, 0)).toBe(nil)
		T.expect(Alarm.state(2, 150)).toBe(nil)
		local s = Alarm.state(3, 0)
		T.expect(s ~= nil).toBe(true)
		T.expect((s :: Alarm.State).attacks).toBe(3)
		T.expect(Alarm.state(1, 0.5) ~= nil).toBe(true) -- полсолдата — это ещё не войска
	end)

	T.it("цвет тревоги не сливается ни с одним цветом державы", function()
		local names = Config.Render.Alarm.AlertColors :: { string }
		for _, name in names do
			T.expect(Palette.ByName[name] ~= nil).toBe(true)
		end
		T.expect(Alarm.alertName(nil)).toBe(names[1])
		local switched = 0
		for _, c in NationColors.Colors do
			local name = Alarm.alertName(c)
			T.expect(Alarm.distance(Palette.ByName[name], c) >= Config.Render.Alarm.MinColorDist).toBe(true)
			if name ~= names[1] then
				switched += 1
			end
		end
		-- Красный остаётся для большинства держав — меняется только у близких к нему.
		T.expect(switched >= 1).toBe(true)
		T.expect(switched < #NationColors.Colors / 2).toBe(true)
	end)
end)
