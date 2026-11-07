--!strict
-- Логотип (§15л ч.5): размер, знаки — только палитра или прозрачность.
local T = require("./lib/TestKit")
local LogoArt = require("../src/shared/LogoArt")
local Palette = require("../src/shared/Palette")

T.describe("Логотип (§15л ч.5)", function()
	T.it(
		"строки одной длины, цвета — из палитры, есть золото и рамка",
		function()
			T.expect(#LogoArt.Rows).toBe(LogoArt.H)
			local seen: { [string]: number } = {}
			for _, row in LogoArt.Rows do
				T.expect(#row).toBe(LogoArt.W)
				for k = 1, #row do
					local ch = string.sub(row, k, k)
					seen[ch] = (seen[ch] or 0) + 1
					if ch ~= "." then
						local name = LogoArt.Keys[ch]
						T.expect(name ~= nil and Palette.ByName[name] ~= nil).toBe(true)
					end
				end
			end
			T.expect((seen.g or 0) > 500).toBe(true)
			T.expect((seen.k or 0) > 500).toBe(true)
			T.expect((seen["."] or 0) > 0).toBe(true)
		end
	)
end)
