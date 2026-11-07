--!strict
-- Миниатюры карт (§15л ч.6): есть у каждой карты, размер и знаки — палитра.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local MapThumbs = require("../src/shared/MapThumbs")
local Palette = require("../src/shared/Palette")

T.describe("Миниатюры карт (§15л ч.6)", function()
	T.it(
		"у каждой карты, W×H, знак — номер цвета палитры; есть вода и суша",
		function()
			T.expect(#MapThumbs.Keys).toBe(#Palette.Swatches)
			for _, name in Config.RealMapOrder do
				local rows = (MapThumbs.Maps :: any)[name] :: { string }
				T.expect(rows ~= nil).toBe(true)
				T.expect(#rows).toBe(MapThumbs.H)
				local kinds: { [string]: boolean } = {}
				for _, row in rows do
					T.expect(#row).toBe(MapThumbs.W)
					for k = 1, #row do
						local ch = string.sub(row, k, k)
						T.expect(string.find(MapThumbs.Keys, ch, 1, true) ~= nil).toBe(true)
						kinds[ch] = true
					end
				end
				local n = 0
				for _ in kinds do
					n += 1
				end
				T.expect(n >= 3).toBe(true)
			end
		end
	)
end)
