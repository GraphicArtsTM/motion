--!strict
-- Пиксельный вид кнопок и окон (§15л ч.4): цвета только из палитры, фаска светлее и темнее кнопки.
local T = require("./lib/TestKit")
local Palette = require("../src/shared/Palette")
local PixelSkin = require("../src/shared/PixelSkin")

local function luma(name: string): number
	local c = Palette.rgb(name)
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
end

T.describe("Пиксельный вид (§15л ч.4)", function()
	T.it(
		"фаска: имена палитры, светлая — светлее кнопки, тёмная — не светлее",
		function()
			for face, shade in PixelSkin.Shades do
				T.expect(Palette.ByName[face] ~= nil).toBe(true)
				T.expect(Palette.ByName[shade.hi] ~= nil).toBe(true)
				T.expect(Palette.ByName[shade.lo] ~= nil).toBe(true)
				T.expect(luma(shade.hi) > luma(face)).toBe(true)
				T.expect(luma(shade.lo) <= luma(face)).toBe(true)
			end
			for _, name in { PixelSkin.Outline, PixelSkin.PanelOutline, PixelSkin.Hover, PixelSkin.Lip } do
				T.expect(Palette.ByName[name] ~= nil).toBe(true)
			end
		end
	)

	T.it(
		"цвет → имя палитры; кнопка: нажатие — фаска наоборот и без полки",
		function()
			local gold = Palette.rgb("Gold")
			T.expect(PixelSkin.nameOf(gold.r, gold.g, gold.b)).toBe("Gold")
			T.expect(PixelSkin.nameOf(1, 2, 3)).toBe(nil)
			local normal = PixelSkin.button(100, 40, "Gold", "normal")
			local pressed = PixelSkin.button(100, 40, "Gold", "pressed")
			local hover = PixelSkin.button(100, 40, "Gold", "hover")
			T.expect(#pressed).toBe(#normal - 1)
			T.expect(normal[2].color).toBe("White")
			T.expect(pressed[2].color).toBe("Orange")
			T.expect(hover[6].color).toBe(PixelSkin.Hover)
			for _, r in PixelSkin.panel(200, 100, "Night") do
				T.expect(Palette.ByName[r.color] ~= nil).toBe(true)
			end
		end
	)
end)
