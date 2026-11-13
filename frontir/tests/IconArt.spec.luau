--!strict
-- Иконки зданий и юнитов без загрузки в Roblox (§15ш Ш5): данные из tools/icon_pack.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local IconArt = require("../src/shared/IconArt")
local IconData = require("../src/shared/IconData")
local Palette = require("../src/shared/Palette")
local PixelIcons = require("../src/shared/PixelIcons")
local Types = require("../src/shared/Types")

T.describe("Иконки зданий и юнитов (§15ш Ш5)", function()
	T.it(
		"у каждого здания полосы, юнита, корабля и самолёта есть иконка",
		function()
			for _, kind in Config.Buildable do
				T.expect(IconArt.forKey("building." .. kind)).toBe(kind)
			end
			for _, unit in Types.LandUnits do
				T.expect(IconArt.forKey("unit." .. unit)).toBe(unit)
			end
			T.expect(IconArt.forKey("naval.Transport")).toBe("Transport")
			T.expect(IconArt.forKey("naval.Destroyer")).toBe("Destroyer")
			T.expect(IconArt.forKey("air.Fighter")).toBe("Fighter")
			T.expect(IconArt.forKey("air.Bomber")).toBe("Bomber")
			-- §15ш Ш7: удары, Арсенал и все значки PixelIcons — тоже картинками.
			for _, k in
				{
					"missile",
					"raid",
					"Airstrike",
					"Surge",
					"SeaLanding",
					"Blockade",
					"Reveal",
					"Propaganda",
					"Fortify",
					"Airdrop",
				}
			do
				T.expect(IconArt.forKey("strike." .. k) ~= nil).toBe(true)
			end
			for _, k in { "Reinforce", "Convoy", "Barrage", "Jammer" } do
				T.expect(IconArt.forKey("arsenal." .. k) ~= nil).toBe(true)
			end
			for key in PixelIcons.Icons do
				-- «Резерв штаба» картинки пока не получил — остаётся пиксельным значком.
				T.expect(IconArt.has(key) or key == "hqReserve").toBe(true)
			end
			T.expect(IconArt.has("menu") and IconArt.has("home")).toBe(true)
			T.expect(IconArt.forKey("naval.port")).toBe(nil) -- сцены остаются картинками ItemArt
			T.expect(IconArt.forKey("building.Radar")).toBe(nil)
		end
	)

	T.it(
		"данные целые: квадрат Size×Size, только знаки палитры и «.»",
		function()
			local n = IconData.Size
			T.expect(#IconData.Keys).toBe(#Palette.Swatches)
			for name, rows in IconData.Icons :: { [string]: { string } } do
				T.expect(#rows).toBe(n)
				local opaque = 0
				for _, row in rows do
					T.expect(#row).toBe(n)
					for x = 1, n do
						local ch = string.sub(row, x, x)
						T.expect(ch == "." or string.find(IconData.Keys, ch, 1, true) ~= nil).toBe(true)
						if ch ~= "." then
							opaque += 1
						end
					end
				end
				-- Предмет занимает заметную часть квадрата, но не весь (фон вырезан).
				T.expect(opaque > n * n * 0.15 and opaque < n * n * 0.95).toBe(true)
				local px = IconArt.paint(name) :: buffer
				T.expect(buffer.len(px)).toBe(n * n * 4)
			end
			T.expect(IconArt.paint("Nope")).toBe(nil)
		end
	)
end)
