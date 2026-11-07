--!strict
-- Хаб и матч — разные места (§15л ч.3): роль сервера, записи списка матчей, быстрый вход.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Places = require("../src/shared/Places")

local NOW = 1_800_000_000

local function e(id: string, phase: string, players: number, max: number?): Places.Entry
	return {
		id = id,
		psid = "",
		map = "Europe",
		mode = "Ffa",
		phase = phase,
		players = players,
		max = max or 12,
		left = 30,
		at = NOW,
	}
end

T.describe("Хаб и матч (§15л ч.3)", function()
	T.it("роль сервера: id места, Studio и частный сервер", function()
		local hub, match = Config.Places.Hub, Config.Places.Match
		T.expect(Places.role(hub, false, 0, "")).toBe("hub")
		T.expect(Places.role(match, false, 0, "")).toBe("match")
		T.expect(Places.role(123, false, 0, "")).toBe("combined")
		-- Частный сервер — меню поверх своего матча, как раньше.
		T.expect(Places.role(hub, false, 42, "")).toBe("combined")
		-- Studio: как раньше, роль для проверки вида — Dev.Role; вне Studio Dev.Role не действует.
		T.expect(Places.role(hub, true, 0, "")).toBe("combined")
		T.expect(Places.role(0, true, 0, "hub")).toBe("hub")
		T.expect(Places.role(0, true, 0, "match")).toBe("match")
		T.expect(Places.role(0, true, 0, "boss")).toBe("combined")
		T.expect(Places.role(match, false, 0, "hub")).toBe("match")
		-- Оба места заданы и разные; в сборке по умолчанию Studio — как раньше.
		T.expect(hub ~= match and hub > 0 and match > 0).toBe(true)
		T.expect(Config.Dev.Role).toBe("")
	end)

	T.it("запись о сервере: проверка полей и срок", function()
		local good = e("job-1", "Lobby", 3)
		local got = Places.entry(good, NOW + 5)
		T.expect(got ~= nil).toBe(true)
		T.expect((got :: Places.Entry).psid).toBe("")
		T.expect(Places.entry(good, NOW + Config.Places.ExpireSec + 1)).toBe(nil)
		T.expect(Places.entry(nil, NOW)).toBe(nil)
		T.expect(Places.entry("x", NOW)).toBe(nil)
		local bad = table.clone(good) :: any
		bad.phase = "Party"
		T.expect(Places.entry(bad, NOW)).toBe(nil)
		bad = table.clone(good) :: any
		bad.players = -1
		T.expect(Places.entry(bad, NOW)).toBe(nil)
		bad = table.clone(good) :: any
		bad.max = 0
		T.expect(Places.entry(bad, NOW)).toBe(nil)
		bad = table.clone(good) :: any
		bad.players = 2.5
		T.expect(Places.entry(bad, NOW)).toBe(nil)
		bad = table.clone(good) :: any
		bad.id = ""
		T.expect(Places.entry(bad, NOW)).toBe(nil)
		local reserved = table.clone(good) :: any
		reserved.psid = "ps-9"
		T.expect((Places.entry(reserved, NOW) :: Places.Entry).psid).toBe("ps-9")
	end)

	T.it("что можно: войти, смотреть, полон", function()
		T.expect(Places.action(e("a", "Lobby", 3))).toBe("join")
		T.expect(Places.action(e("a", "Over", 3))).toBe("join")
		T.expect(Places.action(e("a", "Play", 3))).toBe("watch")
		T.expect(Places.action(e("a", "Lobby", 12, 12))).toBe("full")
	end)

	T.it(
		"быстрый вход: лобби с игроками, потом выбор старта, итоги; в идущую игру — нет",
		function()
			local list = {
				e("play", "Play", 5),
				e("over", "Over", 6),
				e("pick", "Pick", 7),
				e("lobbyFull", "Lobby", 12, 12),
				e("lobby2", "Lobby", 2),
				e("lobby4", "Lobby", 4),
			}
			T.expect((Places.pick(list) :: Places.Entry).id).toBe("lobby4")
			T.expect((Places.pick({ e("over", "Over", 6), e("pick", "Pick", 1) }) :: Places.Entry).id).toBe("pick")
			T.expect((Places.pick({ e("over", "Over", 6) }) :: Places.Entry).id).toBe("over")
			T.expect(Places.pick({ e("play", "Play", 1), e("full", "Lobby", 12, 12) })).toBe(nil)
			T.expect(Places.pick({})).toBe(nil)
			-- Строки меню: куда войти — сверху, «смотреть» — ниже, полные — в конце.
			local order = {}
			for _, x in Places.sorted(list) do
				table.insert(order, x.id)
			end
			T.expect(table.concat(order, ",")).toBe("lobby4,lobby2,pick,over,play,lobbyFull")
		end
	)
end)
