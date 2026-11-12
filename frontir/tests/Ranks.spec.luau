--!strict
-- Звания по уровню профиля (§15л).
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Palette = require("../src/shared/Palette")
local Profile = require("../src/shared/Profile")
local Ranks = require("../src/shared/Ranks")
local Strings = require("../src/shared/Strings")

T.describe("Звания (§15л)", function()
	T.it(
		"ступень по уровню: с уровней Ranks.Tiers, последняя — до MaxLevel",
		function()
			local per = Config.Ranks.Tiers[2] - 1 -- §15ф: последний уровень первой ступени
			T.expect(Ranks.of(1)).toBe(1)
			T.expect(Ranks.of(per)).toBe(1)
			T.expect(Ranks.of(per + 1)).toBe(2)
			T.expect(Ranks.of(0)).toBe(1)
			T.expect(Ranks.of(Config.Profile.MaxLevel)).toBe(Ranks.Count)
			T.expect(Ranks.of(Config.Profile.MaxLevel + 50)).toBe(Ranks.Count)
			-- Все звания достижимы: последнее начинается не позже высшего уровня профиля.
			T.expect(Ranks.firstLevel(Ranks.Count) <= Config.Profile.MaxLevel).toBe(true)
			for rank = 1, Ranks.Count do
				T.expect(Ranks.of(Ranks.firstLevel(rank))).toBe(rank)
			end
			T.expect(Ranks.nextAt(1)).toBe(per + 1)
			T.expect(Ranks.nextAt(Config.Profile.MaxLevel)).toBe(nil)
			-- Уровень из профиля даёт звание.
			local level = Profile.levelOf(0)
			T.expect(Ranks.of(level)).toBe(1)
		end
	)

	T.it(
		"у каждого звания есть название RU/EN и свой значок в рамке 16×16 из цветов палитры",
		function()
			local seen: { [string]: number } = {}
			for rank = 1, Ranks.Count do
				local entry = Strings.Table["rank." .. rank]
				T.expect(entry ~= nil).toBe(true)
				local parts = Ranks.icon(rank)
				T.expect(#parts > 0).toBe(true)
				local key: { string } = {}
				for _, p in parts do
					T.expect(p.x >= 0 and p.y >= 0 and p.w >= 1 and p.h >= 1).toBe(true)
					T.expect(p.x + p.w <= Ranks.IconSize and p.y + p.h <= Ranks.IconSize).toBe(true)
					Palette.rgb(p.color) -- неизвестное имя — ошибка
					table.insert(key, string.format("%d,%d,%d,%d,%s", p.x, p.y, p.w, p.h, p.color))
				end
				local id = table.concat(key, ";")
				if seen[id] ~= nil then
					error(string.format("значки званий %d и %d одинаковые", seen[id], rank))
				end
				seen[id] = rank
			end
		end
	)
end)
