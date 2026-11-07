--!strict
-- Картинки-шапки окон (§15л ч.8): каждая сцена рисуется целиком, без пустых пикселей, одинаково при повторе.
local T = require("./lib/TestKit")
local SceneArt = require("../src/shared/SceneArt")

T.describe("Сцены-шапки (§15л ч.8)", function()
	T.it(
		"каждая сцена: W×H, все пиксели непрозрачны, картинка повторяется",
		function()
			for _, key in SceneArt.Keys do
				local a = SceneArt.paint(key)
				T.expect(buffer.len(a)).toBe(SceneArt.W * SceneArt.H * 4)
				local empty = 0
				for i = 0, SceneArt.W * SceneArt.H - 1 do
					if buffer.readu8(a, i * 4 + 3) ~= 255 then
						empty += 1
					end
				end
				T.expect(empty).toBe(0)
				T.expect(buffer.tostring(SceneArt.paint(key))).toBe(buffer.tostring(a))
			end
			-- Неизвестный ключ — запасная сцена, не ошибка.
			T.expect(buffer.len(SceneArt.paint("nope"))).toBe(SceneArt.W * SceneArt.H * 4)
		end
	)
end)
