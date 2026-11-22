--!strict
-- Отклик на действия (§15й Й4): отсчёт старта, искры «Готово!», вспышки роста, путь монеты, «→ N».
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local FeedbackFx = require("../src/shared/FeedbackFx")

local cfg = Config.Render.Feedback

T.describe("Отклик на действия (§15й Й4)", function()
	T.it("отсчёт: «3 · 2 · 1» только в последние CountdownFrom секунд", function()
		T.expect(FeedbackFx.countdown(cfg.CountdownFrom + 0.5)).toBe(nil)
		T.expect(FeedbackFx.countdown(cfg.CountdownFrom)).toBe(tostring(cfg.CountdownFrom))
		T.expect(FeedbackFx.countdown(1.2)).toBe("2")
		T.expect(FeedbackFx.countdown(0.3)).toBe("1")
		T.expect(FeedbackFx.countdown(0)).toBe(nil)
	end)

	T.it(
		"искры «Готово!»: вспышка, кольцо и BuiltSparks искр вверх; один сид — одна картинка",
		function()
			local a = FeedbackFx.builtSparks(10, 20, 7)
			T.expect(#a).toBe(2 + cfg.BuiltSparks)
			local sparks = 0
			for _, p in a do
				if p.kind == "spark" then
					sparks += 1
					T.expect(p.dy <= 0).toBe(true) -- вверх
				end
			end
			T.expect(sparks).toBe(cfg.BuiltSparks)
			T.expect(FeedbackFx.builtSparks(10, 20, 7)).toEqual(a)
		end
	)

	T.it(
		"вспышки роста: не больше предела, равномерно, без повторов",
		function()
			T.expect(FeedbackFx.growFlashes(5, 24)).toEqual({ 1, 2, 3, 4, 5 })
			local many = FeedbackFx.growFlashes(1000, 24)
			T.expect(#many).toBe(24)
			for k = 2, #many do
				T.expect(many[k] > many[k - 1]).toBe(true)
			end
			T.expect(many[#many] <= 1000).toBe(true)
			T.expect(#FeedbackFx.growFlashes(0, 24)).toBe(0)
		end
	)

	T.it(
		"монета: на старте и финише — в своих точках, посередине — выше прямой",
		function()
			local x, y = FeedbackFx.coin(100, 500, 900, 800, 2, 5, 0)
			T.expect(x).toBe(100)
			T.expect(y).toBe(500)
			x, y = FeedbackFx.coin(100, 500, 900, 800, 2, 5, 1)
			T.expect(x).toBe(900)
			T.expect(y).toBe(800)
			local _, my = FeedbackFx.coin(100, 500, 900, 800, 3, 5, 0.5)
			T.expect(my < (500 + 800) / 2).toBe(true)
		end
	)

	T.it("«→ N»: люди × доля атаки, целое", function()
		T.expect(FeedbackFx.sent(1523, 0.25)).toBe(380)
		T.expect(FeedbackFx.sent(-5, 0.5)).toBe(0)
	end)
end)
