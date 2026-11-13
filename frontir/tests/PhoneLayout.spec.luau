--!strict
-- Раскладка узкого экрана (§15ц Ц5в).
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local PhoneLayout = require("../src/shared/PhoneLayout")
local UiFit = require("../src/shared/UiFit")

T.describe("Телефон (§15ц Ц5в)", function()
	T.it(
		"узкий экран: телефон и планшет — да, компьютер 1366×768 и шире — нет; флаг Studio включает",
		function()
			local function units(w: number, h: number): number
				local uw = UiFit.unitsSize(w, h)
				return uw
			end
			T.expect(PhoneLayout.narrow(units(844, 390))).toBe(true)
			T.expect(PhoneLayout.narrow(units(1024, 768))).toBe(true)
			T.expect(PhoneLayout.narrow(units(1366, 768))).toBe(false)
			T.expect(PhoneLayout.narrow(units(1920, 1080))).toBe(false)
			T.expect(PhoneLayout.narrow(units(3440, 1440))).toBe(false)
			T.expect(PhoneLayout.narrow(units(1920, 1080), true)).toBe(true)
		end
	)

	T.it(
		"полоса: широкий экран — одна строка; узкий — две, по нижней строке и в ширину экрана",
		function()
			local natural, second = 1800, 1000
			local wide = PhoneLayout.bar(natural, second, 1600, false)
			T.expect(wide.rows).toBe(1)
			T.expect(wide.width).toBe(natural)
			T.expect(math.abs(wide.scale - 1600 / natural) < 1e-9).toBe(true)
			local phone = PhoneLayout.bar(natural, second, 820, true)
			T.expect(phone.rows).toBe(2)
			T.expect(phone.width).toBe(second)
			T.expect(math.abs(phone.scale - 0.82) < 1e-9).toBe(true)
			-- Совсем узко — не мельче MinScale; широкий экран, где одна строка не влезает даже ужатой, — тоже две.
			T.expect(PhoneLayout.bar(natural, second, 300, true).scale).toBe(Config.Render.CommandBar.MinScale)
			T.expect(PhoneLayout.bar(natural, second, 900, false).rows).toBe(2)
		end
	)
end)
