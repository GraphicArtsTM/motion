--!strict
-- Масштаб интерфейса под экран (§15ц Ц1).
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local UiFit = require("../src/shared/UiFit")

T.describe("Масштаб интерфейса (§15ц Ц1)", function()
	local cfg = Config.Render.UiScale

	T.it(
		"на опорном экране масштаб 1, на большом — растёт по высоте",
		function()
			T.expect(UiFit.scale(cfg.RefWidthPx, cfg.RefHeightPx)).toBe(1)
			T.expect(UiFit.scale(1920, 1080)).toBe(1.2)
			T.expect(UiFit.scale(2560, 1440)).toBe(1.6)
			-- Широкий монитор: решает высота, лишняя ширина остаётся карте.
			T.expect(UiFit.scale(3440, 1440)).toBe(1.6)
		end
	)

	T.it(
		"узкий или маленький экран не раздувается и не ужимается ниже Min",
		function()
			-- Телефон лёжа и стоя, маленький ноутбук.
			T.expect(UiFit.scale(844, 390)).toBe(cfg.Min)
			T.expect(UiFit.scale(390, 844)).toBe(cfg.Min)
			T.expect(UiFit.scale(1366, 768)).toBe(cfg.Min)
			-- Высокий, но узкий экран: ширина не даёт вырасти.
			T.expect(UiFit.scale(1500, 2000)).toBe(1)
			-- Пустой экран (ещё не разложен) — без деления на ноль.
			T.expect(UiFit.scale(0, 0)).toBe(cfg.Min)
			T.expect(UiFit.scale(100000, 100000)).toBe(cfg.Max)
		end
	)

	T.it("масштаб кратен шагу и не убывает с ростом экрана", function()
		local prev = 0
		for h = 300, 3000, 37 do
			local s = UiFit.scale(h * 16 / 9, h)
			T.expect(s >= prev).toBe(true)
			T.expect(math.abs(s * cfg.StepsPerUnit - math.floor(s * cfg.StepsPerUnit + 0.5)) < 1e-6).toBe(true)
			prev = s
		end
	end)

	T.it(
		"условные пиксели: экран в единицах не меньше опорного там, где масштаб вырос",
		function()
			local w, h = UiFit.unitsSize(3440, 1440)
			T.expect(math.abs(h - 900) < 1).toBe(true)
			T.expect(w > cfg.RefWidthPx).toBe(true)
			T.expect(UiFit.toUnits(160, 1.6)).toBe(100)
			-- Телефон: единицы равны пикселям — узкие раскладки включаются как раньше.
			local pw = UiFit.unitsSize(844, 390)
			T.expect(pw).toBe(844)
			T.expect(pw < Config.Render.NarrowScreenPx).toBe(true)
		end
	)
end)
