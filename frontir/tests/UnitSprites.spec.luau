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

	T.it("на крупном зуме спрайты крупнее", function()
		T.expect(UnitSprites.scaleFor(1)).toBe(1)
		local steps = Config.Render.UnitSpriteScales
		local last = steps[#steps]
		T.expect(UnitSprites.scaleFor(last.zoom)).toBe(last.scale)
		T.expect(UnitSprites.scaleFor(last.zoom * 4)).toBe(last.scale)
	end)
end)
