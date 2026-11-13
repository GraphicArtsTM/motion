--!strict
-- Матчи как серверы: плейлист «карта · режим», строки списка, выбор карты и режима (§15ц Ц2).
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Lobbies = require("../src/shared/Lobbies")
local Modes = require("../src/shared/Modes")
local Places = require("../src/shared/Places")

local NOW = 1_800_000_000

local function e(id: string, map: string, mode: string, phase: string, players: number, max: number?): Places.Entry
	return {
		id = id,
		psid = "",
		map = map,
		mode = mode,
		phase = phase,
		players = players,
		max = max or 12,
		left = 30,
		at = NOW,
	}
end

T.describe("Матчи как серверы (§15ц Ц2)", function()
	local slots = Lobbies.slots(NOW)

	T.it(
		"плейлист: пары из Config, «Weekly» — режим недели, карты и режимы допустимы",
		function()
			T.expect(#slots).toBe(#Config.Lobbies.Slots)
			for k, s in slots do
				T.expect(Modes.isMode(s.mode)).toBe(true)
				T.expect(table.find(Config.MapVote.Pool, s.map) ~= nil).toBe(true)
				T.expect((Config.RealMaps :: any)[s.map] ~= nil).toBe(true)
				if Config.Lobbies.Slots[k].mode == "Weekly" then
					T.expect(s.mode).toBe(Modes.weekly(NOW))
				end
				-- Каждая пара проходит проверку запроса (иначе «Новое лобби» нельзя поднять).
				T.expect(Lobbies.request({ map = s.map, mode = s.mode }) ~= nil).toBe(true)
			end
		end
	)

	T.it(
		"пустой список серверов — у каждой пары строка «Новое лобби»",
		function()
			local rows = Lobbies.board({}, slots, Config.Lobbies.Rows)
			T.expect(#rows).toBe(#slots)
			for k, r in rows do
				T.expect(r.slot).toBe(k)
				T.expect(r.id).toBe("")
				T.expect(r.phase).toBe("New")
				T.expect(r.action).toBe(if slots[k].mode == "Teams" then "teams" else "new")
				T.expect(r.max > 0).toBe(true)
			end
		end
	)

	T.it(
		"сервер пары показывается в её строке; идущие и полные — ниже, не больше rows",
		function()
			local s1, s2 = slots[1], slots[2]
			local list = {
				e("live", s1.map, s1.mode, "Play", 8),
				e("open", s1.map, s1.mode, "Lobby", 3),
				e("team", s2.map, s2.mode, "Pick", 5),
				e("full", "Europe", "Ffa", "Lobby", 12, 12),
				e("other", "Oceania", "Blitz", "Lobby", 2),
			}
			local rows = Lobbies.board(list, slots, 7)
			T.expect(rows[1].id).toBe("open")
			T.expect(rows[1].action).toBe("join")
			T.expect(rows[2].id).toBe("team")
			T.expect(rows[2].action).toBe("teams")
			T.expect(rows[3].phase).toBe("New")
			-- Ниже плейлиста: сначала куда можно войти, потом «смотреть», полные — в конце.
			T.expect(rows[#slots + 1].id).toBe("other")
			T.expect(rows[#slots + 1].slot).toBe(0)
			T.expect(rows[#slots + 2].id).toBe("live")
			T.expect(rows[#slots + 2].action).toBe("watch")
			T.expect(#rows).toBe(7)
			-- Строк больше, чем места: плейлист остаётся целиком.
			local short = Lobbies.board(list, slots, 2)
			T.expect(#short).toBe(#slots)
		end
	)

	T.it(
		"запрос: карта из пула, режим из списка, «одному» — с силой ботов; всё кривое — nil",
		function()
			local ok = Lobbies.request({ map = "Europe", mode = "Teams", solo = true, level = "General" })
			T.expect(ok ~= nil).toBe(true)
			local r = ok :: Lobbies.Request
			T.expect(r.solo).toBe(true)
			T.expect(r.level).toBe("General")
			local public = Lobbies.request({ map = "World", mode = "Ffa", level = "General" }) :: Lobbies.Request
			T.expect(public.solo).toBe(false)
			T.expect(public.level).toBe(nil) -- сила ботов — только в игре одному
			T.expect(Lobbies.request({ map = "Narnia", mode = "Ffa" })).toBe(nil)
			T.expect(Lobbies.request({ map = "Europe", mode = "Duel" })).toBe(nil)
			T.expect(Lobbies.request({ map = "Europe", mode = "Tutorial" })).toBe(nil)
			T.expect(Lobbies.request({ map = "Europe", mode = "Ffa", solo = true, level = "God" })).toBe(nil)
			T.expect(Lobbies.request("Europe")).toBe(nil)
			T.expect(Lobbies.request(nil)).toBe(nil)
			for _, mode in Config.Lobbies.Modes do
				T.expect(Modes.isMode(mode)).toBe(true)
			end
		end
	)

	T.it(
		"«В БОЙ»: открытый матч, иначе — новое лобби первой пары",
		function()
			local found, req = Lobbies.quick({ e("a", "World", "Ffa", "Lobby", 4) }, slots)
			T.expect((found :: Places.Entry).id).toBe("a")
			T.expect(req).toBe(nil)
			local none, fresh = Lobbies.quick({ e("b", "World", "Ffa", "Play", 4) }, slots)
			T.expect(none).toBe(nil)
			T.expect((fresh :: Lobbies.Request).map).toBe(slots[1].map)
			T.expect((fresh :: Lobbies.Request).mode).toBe(slots[1].mode)
		end
	)
end)
