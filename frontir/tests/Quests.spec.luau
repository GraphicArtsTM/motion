--!strict
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Profile = require("../src/shared/Profile")
local Quests = require("../src/shared/Quests")

local NOW = 1800000000
local DAY = Profile.dayOf(NOW)

local function outcome(place: number, won: boolean, cities: number, land: number): Quests.MatchOutcome
	return { place = place, won = won, cities = cities, landPercent = land }
end

T.describe("Ежедневные задания (§11.5)", function()
	T.it(
		"3 разных задания в день; у игрока весь день одни, на следующий день — новые",
		function()
			local a = Quests.forDay(DAY, 42)
			T.expect(#a).toBe(Config.Quests.PerDay)
			T.expect(a[1] ~= a[2] and a[2] ~= a[3] and a[1] ~= a[3]).toBe(true)
			T.expect(Quests.forDay(DAY, 42)).toEqual(a)
			local d = Profile.new()
			Quests.sync(d, DAY, 42)
			T.expect(#d.quests).toBe(3)
			d.quests[1].progress = 1
			Quests.sync(d, DAY, 42)
			T.expect(d.quests[1].progress).toBe(1) -- тот же день — прогресс остаётся
			Quests.sync(d, DAY + 1, 42)
			T.expect(d.quests[1].progress).toBe(0)
		end
	)

	T.it(
		"прогресс по итогам матчей, награды выполненных и жетон за все три",
		function()
			local d = Profile.new()
			Quests.sync(d, DAY, 42)
			-- Подменяем задания на известные: сыграть 2, победить 1, 15% суши.
			local function poolOf(kind: string, target: number): number
				for k, row in Config.Quests.Pool do
					if row.kind == kind and row.target == target then
						return k
					end
				end
				error("нет задания " .. kind)
			end
			d.quests = {
				{ pool = poolOf("play", 2), progress = 0, done = false },
				{ pool = poolOf("win", 1), progress = 0, done = false },
				{ pool = poolOf("land", 15), progress = 0, done = false },
			}
			local done, tokens = Quests.onMatch(d, outcome(4, false, 3, 10), DAY, 42, NOW)
			T.expect(#done).toBe(0)
			T.expect(tokens).toBe(0)
			local medals = d.medals
			done, tokens = Quests.onMatch(d, outcome(1, true, 9, 22), DAY, 42, NOW)
			T.expect(#done).toBe(3)
			T.expect(tokens).toBe(Config.Quests.AllDoneTokens)
			T.expect(d.medals > medals).toBe(true)
			T.expect(d.xp > 0).toBe(true) -- §15ю Ю1: опыт заданий — в «Путь командира»
			-- Повторно жетон не дают.
			done, tokens = Quests.onMatch(d, outcome(1, true, 9, 22), DAY, 42, NOW)
			T.expect(#done).toBe(0)
			T.expect(tokens).toBe(0)
			-- Сохранение: задания переживают миграцию.
			local back = Profile.migrate(d)
			T.expect(#back.quests).toBe(3)
			T.expect(back.questsBonus).toBe(true)
		end
	)
end)

T.describe("Рейтинг дуэлей (§11.5)", function()
	T.it(
		"равные: победа +K/2; сильный у слабого берёт меньше; сумма изменений — ноль",
		function()
			T.expect(Quests.eloExpected(1000, 1000)).toBeNear(0.5)
			T.expect(Quests.eloDelta(1000, 1000, 1)).toBe(Config.Elo.K / 2)
			local strong = Quests.eloDelta(1400, 1000, 1)
			local weak = Quests.eloDelta(1000, 1400, 1)
			T.expect(strong < weak).toBe(true)
			T.expect(Quests.eloDelta(1200, 1000, 1) + Quests.eloDelta(1000, 1200, 0)).toBe(0)
			T.expect(Profile.new().elo).toBe(Config.Elo.Start)
		end
	)
end)
