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
			T.expect(15 + 3 + cfg.SlotH <= cfg.HeightPx - 2 * pad).toBe(true)
			-- Строка «клавиша · цена», значок 12×12 ×3 ×0.75 и строка названия.
			T.expect(cfg.SlotH >= 14 + 27 + 13).toBe(true)
			T.expect(cfg.SlotW >= 36 + 8).toBe(true)
		end
	)

	-- §15ш Ш1: на снимке атака была 30%, а кнопки — 10/25/35/50/75, ни одна не горела.
	T.it("доля атаки по умолчанию — одна из кнопок полосы", function()
		local found = false
		for _, p in cfg.Percents do
			if math.abs(p - Config.Expansion.DefaultPercent) < 1e-6 then
				found = true
			end
		end
		T.expect(found).toBe(true)
	end)

	-- §15ш Ш1: подсказки называют клавишу клетки СТРОЙКИ («клавиша 2»), номер — место в Config.Buildable (10-я — 0).
	T.it(
		"номера клавиш в подсказках стройки совпадают с клетками полосы",
		function()
			local said: { { string } } = {
				{ "hint.barracks", "Barracks" },
				{ "hint.factory", "Factory" },
				{ "hint.city", "City" },
				{ "strikeHow.missile.needTech", "MissileSilo" },
				{ "strikeHow.missile.needSilo", "MissileSilo" },
				{ "strikeHow.raid.needAirfieldTech", "Airfield" },
				{ "strikeHow.raid.needAirfield", "Airfield" },
				{ "handbook.defense.how", "AirDefense" },
				{ "handbook.oil.how", "OilRig" },
			}
			for _, pair in said do
				local index = table.find(Config.Buildable, pair[2])
				T.expect(index ~= nil).toBe(true)
				local key = tostring((index :: number) % 10)
				local entry = Strings.Table[pair[1]]
				T.expect(entry ~= nil).toBe(true)
				T.expect(string.find(entry.ru, "клавиша " .. key, 1, true) ~= nil).toBe(true)
				T.expect(string.find(entry.en, "key " .. key, 1, true) ~= nil).toBe(true)
			end
		end
	)
end)
