--!strict
-- Предложения справа (§15й Й6) и «К фронту» в свободную часть экрана: OfferQueue, FreeArea, CameraMath.showAt.
local T = require("./lib/TestKit")
local CameraMath = require("../src/shared/CameraMath")
local FreeArea = require("../src/shared/FreeArea")
local OfferQueue = require("../src/shared/OfferQueue")

T.describe("Предложения по одному (§15й Й6)", function()
	T.it("мне, без ответа, со временем — самые срочные первыми", function()
		local offers: { OfferQueue.Offer } = {
			{ kind = "pact", from = 2, to = 1, left = 20 },
			{ kind = "trade", from = 3, to = 1, left = 8 },
			{ kind = "alliance", from = 4, to = 5, left = 3 }, -- не мне
			{ kind = "trade", from = 6, to = 1, left = 0 }, -- время вышло
			{ kind = "alliance", from = 7, to = 1, left = 15 },
		}
		local answered = { [OfferQueue.key(offers[5])] = true }
		local list = OfferQueue.pending(offers, 1, answered, function(o: OfferQueue.Offer): number
			return o.left
		end)
		T.expect(#list).toBe(2)
		T.expect(list[1].from).toBe(3)
		T.expect(list[2].from).toBe(2)
		T.expect(#OfferQueue.pending(offers, nil, {}, function(o: OfferQueue.Offer): number
			return o.left
		end)).toBe(0)
		T.expect(OfferQueue.share(5, 20)).toBe(0.25)
		T.expect(OfferQueue.share(30, 20)).toBe(1)
	end)
end)

T.describe("Свободная часть экрана (§15й Й6)", function()
	T.it(
		"панели у краёв сужают рамку, панель на весь экран — нет",
		function()
			local x0, y0, x1, y1 = FreeArea.rect(1000, 600, {
				{ x0 = 0, y0 = 50, x1 = 200, y1 = 200 }, -- слева
				{ x0 = 850, y0 = 100, x1 = 1000, y1 = 400 }, -- справа
				{ x0 = 400, y0 = 0, x1 = 600, y1 = 70 }, -- сверху
				{ x0 = 200, y0 = 540, x1 = 800, y1 = 600 }, -- снизу
				{ x0 = 0, y0 = 0, x1 = 1000, y1 = 600 }, -- на весь экран
			})
			T.expect({ x0, y0, x1, y1 }).toEqual({ 200, 70, 850, 540 })
			local cx, cy = FreeArea.center(1000, 600, {})
			T.expect({ cx, cy }).toEqual({ 500, 300 })
		end
	)

	T.it("почти ничего не осталось — весь экран по этой оси", function()
		local x0, _, x1 = FreeArea.rect(1000, 600, {
			{ x0 = 0, y0 = 0, x1 = 290, y1 = 100 },
			{ x0 = 700, y0 = 0, x1 = 1000, y1 = 100 },
		})
		T.expect(x1 - x0 >= 300).toBe(true)
		local a0, _, a1 = FreeArea.rect(1000, 600, {
			{ x0 = 0, y0 = 0, x1 = 299, y1 = 100 },
			{ x0 = 560, y0 = 0, x1 = 1000, y1 = 100 },
		})
		T.expect({ a0, a1 }).toEqual({ 0, 1000 })
	end)

	T.it(
		"CameraMath.showAt: клетка оказывается в заданной точке экрана",
		function()
			local s = CameraMath.new(1000, 1000, 800, 600)
			s.zoom = 4
			CameraMath.showAt(s, 500, 400, 300, 250)
			local sx, sy = CameraMath.worldToScreen(s, 500, 400)
			T.expect(sx).toBeNear(300, 1e-6)
			T.expect(sy).toBeNear(250, 1e-6)
		end
	)
end)
