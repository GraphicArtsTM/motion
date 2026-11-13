--!strict
-- Экран матча: подписи и цвета клеток полосы (§15ц Ц3).
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Palette = require("../src/shared/Palette")
local Strings = require("../src/shared/Strings")
local Types = require("../src/shared/Types")

T.describe("Нижняя полоса (§15ц Ц3)", function()
	local cfg = Config.Render.CommandBar
	local langs: { Strings.Lang } = { "ru", "en" }

	T.it(
		"у каждого здания полосы и каждого юнита — свой цвет из палитры и короткое название",
		function()
			local kindColors = cfg.KindColors :: { [string]: string }
			local unitColors = cfg.UnitColors :: { [string]: string }
			local seen: { [string]: string } = {}
			for _, kind in Config.Buildable do
				local c = kindColors[kind]
				T.expect(c ~= nil).toBe(true)
				T.expect(Palette.ByName[c] ~= nil).toBe(true)
				-- Цвет вида не повторяется у другого здания: клетки различаются с первого взгляда.
				T.expect(seen[c] == nil).toBe(true)
				seen[c] = kind
				for _, lang in langs do
					T.expect((Strings.Table["building." .. kind .. ".short"] or {} :: any)[lang] ~= nil).toBe(true)
				end
			end
			for _, unit in Types.LandUnits do
				local c = unitColors[unit]
				T.expect(c ~= nil).toBe(true)
				T.expect(Palette.ByName[c] ~= nil).toBe(true)
				for _, lang in langs do
					T.expect((Strings.Table["unit." .. unit .. ".short"] or {} :: any)[lang] ~= nil).toBe(true)
				end
			end
		end
	)

	T.it(
		"клетка с подписью помещается в полосу: заголовок группы + клетка не выше полосы",
		function()
			local pad = 10
			T.expect(14 + 3 + cfg.SlotH <= cfg.HeightPx - 2 * pad).toBe(true)
			-- Строка «клавиша · цена», значок 12×12 ×3 ×0.75 и строка названия.
			T.expect(cfg.SlotH >= 14 + 27 + 12).toBe(true)
			T.expect(cfg.SlotW >= 36 + 8).toBe(true)
		end
	)
end)
