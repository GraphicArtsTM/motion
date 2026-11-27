--!strict
-- §15ъ стройка пальцем: второе касание рядом с «призраком» (в пикселях экрана) строит, далеко — переставляет.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local TouchBuild = require("../src/shared/TouchBuild")

local W = 100

T.describe("Стройка пальцем (§15ъ)", function()
	T.it(
		"без призрака — не подтверждает; та же клетка — подтверждает",
		function()
			T.expect(TouchBuild.confirms(nil, 5, W, 4)).toBe(false)
			T.expect(TouchBuild.confirms(5, 5, W, 4)).toBe(true)
		end
	)

	T.it(
		"на мелком зуме палец промахивается на несколько клеток — всё равно рядом",
		function()
			local zoom = 3 -- 3 пикселя на клетку
			local cells = math.floor(Config.Render.TouchConfirmPx / zoom)
			local pending = 50 * W + 50
			T.expect(TouchBuild.confirms(pending, pending + cells, W, zoom)).toBe(true)
			T.expect(TouchBuild.confirms(pending, pending + W * cells, W, zoom)).toBe(true)
			T.expect(TouchBuild.confirms(pending, pending + cells + 2, W, zoom)).toBe(false)
		end
	)

	T.it(
		"на крупном зуме соседняя клетка уже далеко — призрак переставится",
		function()
			local zoom = Config.Render.TouchConfirmPx + 1
			T.expect(TouchBuild.confirms(10 * W + 10, 10 * W + 11, W, zoom)).toBe(false)
		end
	)

	T.it(
		"край строки — не «соседняя» клетка на другом конце карты",
		function()
			T.expect(TouchBuild.confirms(10 * W + (W - 1), 11 * W, W, 3)).toBe(false)
		end
	)
end)
