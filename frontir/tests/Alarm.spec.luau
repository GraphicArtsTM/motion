--!strict
-- Тревога на экране матча (§15ш Ш2).
local T = require("./lib/TestKit")
local Alarm = require("../src/shared/Alarm")
local Config = require("../src/shared/Config")
local NationColors = require("../src/shared/NationColors")
local Palette = require("../src/shared/Palette")

T.describe("Тревога «нет войск» (§15ш Ш2)", function()
	T.it("«нет войск» — на вас атакуют, а войск меньше одного", function()
		T.expect(Alarm.state({}, 0)).toBe(nil)
		local s = Alarm.state({ 0.5, 3, math.huge }, 0) :: Alarm.State
		T.expect(s.kind).toBe("noTroops")
		T.expect(s.attacks).toBe(3)
		T.expect((Alarm.state({ 0.2 }, 0.5) :: Alarm.State).kind).toBe("noTroops") -- полсолдата — ещё не войска
	end)

	T.it(
		"«фронт проседает» — войска есть, но перевес врага на фронте не меньше LosingRatio",
		function()
			local edge = Config.Render.Alarm.LosingRatio
			T.expect(Alarm.state({ 0.8, edge - 0.01 }, 150)).toBe(nil) -- держимся
			local s = Alarm.state({ 0.8, edge, math.huge }, 150) :: Alarm.State
			T.expect(s.kind).toBe("losing")
			T.expect(s.attacks).toBe(2) -- только проседающие фронты
		end
	)

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
