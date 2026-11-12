--!strict
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local EventFeed = require("../src/shared/EventFeed")

T.describe("Лента событий по важности (§15т)", function()
	T.it(
		"уровень: по вам — критично, вы и союзники и большие события — важно, чужое и рутина — фон",
		function()
			local me, ally, other = 1, 2, 7
			local friends = { [ally] = true }
			local function level(e: { [string]: any }): EventFeed.Level
				return EventFeed.level(e, me, friends)
			end
			T.expect(level({ kind = "missileLaunched", nation = other, target = me, warhead = "atom" }))
				.toBe("critical")
			T.expect(level({ kind = "warDeclared", nation = other, target = me })).toBe("critical")
			T.expect(level({ kind = "landed", nation = other, target = me })).toBe("critical")
			T.expect(level({ kind = "allyAttacked", nation = other, target = ally, ally = me })).toBe("critical")
			T.expect(level({ kind = "capitalLost", nation = me })).toBe("critical")
			T.expect(level({ kind = "blockade", nation = me, on = true })).toBe("critical")
			T.expect(level({ kind = "blockade", nation = me, on = false })).toBe("important")
			-- Касается нас или союзника — важно.
			T.expect(level({ kind = "peace", nation = me, target = other })).toBe("important")
			T.expect(level({ kind = "warDeclared", nation = ally, target = other })).toBe("important")
			T.expect(level({ kind = "shipSunk", nation = other, by = me })).toBe("important")
			-- Большие события мира — важно всем; ядерный пуск между другими — тоже.
			T.expect(level({ kind = "eliminated", nation = other })).toBe("important")
			T.expect(level({ kind = "missileLaunched", nation = other, target = 9, warhead = "hydrogen" }))
				.toBe("important")
			-- Чужое и рутина — фон.
			T.expect(level({ kind = "warDeclared", nation = other, target = 9 })).toBe("background")
			T.expect(level({ kind = "missileLaunched", nation = other, target = 9, warhead = "missile" }))
				.toBe("background")
			T.expect(level({ kind = "shipBuilt", nation = me })).toBe("background")
			T.expect(level({ kind = "boost", nation = other })).toBe("background")
			-- Зритель: ничего не критично.
			T.expect(EventFeed.level({ kind = "warDeclared", nation = other, target = me }, nil, nil))
				.toBe("background")
		end
	)

	T.it(
		"полная лента: фон не вытесняет важное, критичное вытесняет фон, повтор — ×N, сроки по уровню",
		function()
			local feed = EventFeed.new(4)
			for i = 1, 3 do
				EventFeed.push(feed, "важно " .. i, "important", i)
			end
			EventFeed.push(feed, "фон 1", "background", 4)
			T.expect(#feed.lines).toBe(4)
			-- Ещё фон — вытесняет только фон.
			local shown, evicted = EventFeed.push(feed, "фон 2", "background", 5)
			T.expect(shown ~= nil and (evicted :: EventFeed.Line).text == "фон 1").toBe(true)
			-- Вся лента важнее фона, кроме одной строки фона: ещё один фон снова меняет фон.
			EventFeed.push(feed, "критично 1", "critical", 6) -- вытесняет фон 2
			T.expect(#feed.lines).toBe(4)
			local none = EventFeed.push(feed, "фон 3", "background", 7)
			T.expect(none).toBe(nil) -- лента вся важнее фона — фон не показан
			-- Важное вытесняет самое старое важное, критичное остаётся.
			local _, gone = EventFeed.push(feed, "важно 4", "important", 8)
			T.expect((gone :: EventFeed.Line).text).toBe("важно 1")
			local hasCritical = false
			for _, line in feed.lines do
				hasCritical = hasCritical or line.level == "critical"
			end
			T.expect(hasCritical).toBe(true)
			-- Повтор — «×2», новой строки нет.
			local again = EventFeed.push(feed, "важно 4", "important", 9) :: EventFeed.Line
			T.expect(#feed.lines).toBe(4)
			T.expect(EventFeed.textOf(again)).toBe("важно 4 ×2")
			-- Сроки: фон и важное уходят раньше критичного.
			local f2 = EventFeed.new(4)
			EventFeed.push(f2, "к", "critical", 0)
			EventFeed.push(f2, "в", "important", 0)
			EventFeed.push(f2, "ф", "background", 0)
			T.expect(#EventFeed.expire(f2, Config.Feed.BackgroundSec)).toBe(1)
			T.expect(#EventFeed.expire(f2, Config.Feed.ImportantSec)).toBe(1)
			T.expect(#f2.lines).toBe(1)
			T.expect(f2.lines[1].level).toBe("critical")
			T.expect(Config.Feed.CriticalSec > Config.Feed.ImportantSec).toBe(true)
			T.expect(Config.Feed.ImportantSec > Config.Feed.BackgroundSec).toBe(true)
		end
	)
end)
