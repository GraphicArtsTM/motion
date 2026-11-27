--!strict
-- §15ё: подсказки без клавиш на телефоне.
local T = require("./lib/TestKit")
local Strings = require("../src/shared/Strings")
local TouchText = require("../src/shared/TouchText")

T.describe("Текст для касания (§15ё)", function()
	T.it("убирает клавиши, остальное — как было", function()
		T.expect(
			TouchText.strip("Постройте Казармы (клавиша 2): больше линий найма.")
		)
			.toBe("Постройте Казармы: больше линий найма.")
		T.expect(TouchText.strip("Build Barracks (key 2): more hiring lines."))
			.toBe("Build Barracks: more hiring lines.")
		T.expect(
			TouchText.strip(
				"Улучшите город (клавиша 1, нажмите на свой город): доход."
			)
		).toBe("Улучшите город (нажмите на свой город): доход.")
		T.expect(TouchText.strip("Upgrade a city (key 1, tap your city): income."))
			.toBe("Upgrade a city (tap your city): income.")
		T.expect(
			TouchText.strip(
				"Выберите здание в СТРОЙКЕ внизу (клавиши 1–9, 0) → нажмите свою землю."
			)
		).toBe("Выберите здание в СТРОЙКЕ внизу → нажмите свою землю.")
		T.expect(TouchText.strip("research «Missile silo» (tech Y → Army, lv 3), then build a silo (key 0)."))
			.toBe("research «Missile silo» (tech → Army, lv 3), then build a silo.")
		T.expect(TouchText.strip("Дипломатия у мини-карты (T) → сосед"))
			.toBe("Дипломатия у мини-карты → сосед")
		T.expect(TouchText.strip("<b>Пехота</b> [Z]\n$1000")).toBe("<b>Пехота</b>\n$1000")
		T.expect(TouchText.strip("Задания [J] и меню [Tab]")).toBe("Задания и меню")
		T.expect(
			TouchText.strip(
				"Нанимайте войска: Z — пехота. Без войск страну не взять."
			)
		).toBe("Нанимайте войска: пехота. Без войск страну не взять.")
		T.expect(TouchText.strip("Hire troops: Z — infantry.")).toBe("Hire troops: infantry.")
		-- Без клавиш — не трогает (проценты, скобки с текстом, «ур. 3»).
		local plain = "Атака 25% (ур. 3) — «Пехота» [готово]"
		T.expect(TouchText.strip(plain)).toBe(plain)
	end)

	T.it("подсказки hint.* и strikeHow.* на телефоне — без «клавиш»", function()
		for key, entry in Strings.Table do
			if string.sub(key, 1, 5) == "hint." or string.sub(key, 1, 10) == "strikeHow." then
				local ru = TouchText.strip(entry.ru)
				local en = TouchText.strip(entry.en)
				local keyDash = string.find(ru, "%f[%a]%u — ") ~= nil or string.find(en, "%f[%a]%u — ") ~= nil
				if string.find(ru, "клавиш") ~= nil or string.find(en, "%f[%a]key%f[%A]") ~= nil or keyDash then
					error(key .. ": осталась клавиша — " .. ru .. " / " .. en)
				end
			end
		end
	end)
end)
