--!strict
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Types = require("../src/shared/Types")
local UnitSprites = require("../src/shared/UnitSprites")

T.describe("UnitSprites", function()
	T.it("у каждого наземного юнита есть спрайт в пределах 8×6", function()
		for _, kind in Types.LandUnits do
			local shape = UnitSprites.Shapes[kind]
			T.expect(shape ~= nil).toBe(true)
			for _, p in shape do
				T.expect(p.x >= 0 and p.y >= 0).toBe(true)
				T.expect(p.x + p.w <= UnitSprites.Width and p.y + p.h <= UnitSprites.Height).toBe(true)
			end
		end
	end)

	T.it("юниты вдоль фронта идут по долям состава", function()
		-- 60% пехоты, 40% танков → из 10 юнитов 6 солдат и 4 танка.
		local counts: { [string]: number } = {}
		for k = 1, 10 do
			local kind = UnitSprites.kindAt({ 0.6, 0.4, 0, 0 }, k, 10)
			counts[kind] = (counts[kind] or 0) + 1
		end
		T.expect(counts.Infantry).toBe(6)
		T.expect(counts.Tanks).toBe(4)
		-- Пустой состав — пехота.
		T.expect(UnitSprites.kindAt({ 0, 0, 0, 0 }, 1, 1)).toBe("Infantry")
	end)

	T.it("spread выбирает равномерно и не больше нужного", function()
		local list: { number } = {}
		for i = 1, 100 do
			list[i] = i
		end
		local picked = UnitSprites.spread(list, 4)
		T.expect(#picked).toBe(4)
		T.expect(picked[1]).toBe(13)
		T.expect(picked[4]).toBe(88)
		T.expect(#UnitSprites.spread(list, 0)).toBe(0)
		T.expect(#UnitSprites.spread({ 1, 2 }, 5)).toBe(2)
	end)

	T.it("на крупном зуме спрайты крупнее", function()
		T.expect(UnitSprites.scaleFor(1)).toBe(1)
		local steps = Config.Render.UnitSpriteScales
		local last = steps[#steps]
		T.expect(UnitSprites.scaleFor(last.zoom)).toBe(last.scale)
		T.expect(UnitSprites.scaleFor(last.zoom * 4)).toBe(last.scale)
	end)
end)
