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
		-- Игра из одного места (оба 0): любой сервер — «всё в одном» (меню и матч вместе), F4 только в Studio.
		if hub == 0 and match == 0 then
			T.expect(Places.role(110452094639889, false, 0, "")).toBe("combined")
			T.expect(Places.role(0, false, 0, "")).toBe("combined")
			T.expect(Places.role(123, false, 42, "")).toBe("combined")
			T.expect(Places.role(0, true, 0, "hub")).toBe("hub")
			T.expect(Config.Dev.Role).toBe("")
			return
		end
		-- Одно место (Match = 0): обычный сервер — хаб, резервный (поднял хаб) — матч, частный — как раньше.
		if match == 0 then
			T.expect(Places.role(hub, false, 0, "", false)).toBe("hub")
			T.expect(Places.role(hub, false, 0, "", true)).toBe("match")
			T.expect(Places.role(hub, false, 42, "", true)).toBe("combined")
			T.expect(Places.role(123, false, 0, "", true)).toBe("combined")
			T.expect(Places.role(hub, true, 0, "", true)).toBe("combined") -- Studio
			T.expect(Places.matchPlace()).toBe(hub)
			T.expect(Config.Dev.Role).toBe("")
			return
		end
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

	T.it(
		"свой матч: код из 6 знаков без похожих букв, ввод игрока, запись кода",
		function()
			local n = 0
			local code = Places.newCode(function(max: number): number
				n += 1
				return (n * 7) % max + 1
			end)
			T.expect(#code).toBe(Config.Places.CodeLength)
			T.expect((string.find(code, "[01OI]"))).toBe(nil)
			T.expect(Places.normalizeCode(code)).toBe(code)
			T.expect(Places.normalizeCode(" k7q-2md ")).toBe("K7Q2MD")
			T.expect(Places.normalizeCode("K7Q2M")).toBe(nil) -- коротко
			T.expect(Places.normalizeCode("K7Q2M0")).toBe(nil) -- ноля нет в алфавите
			T.expect(Places.normalizeCode(123456)).toBe(nil)
			T.expect(Places.normalizeCode(string.rep("A", 40))).toBe(nil)
			local rec = Places.privateRecord({ access = "code", psid = "ps", owner = 42 })
			T.expect(rec ~= nil and rec.owner == 42).toBe(true)
			T.expect(Places.privateRecord({ access = "code", psid = "", owner = 42 })).toBe(nil)
			T.expect(Places.privateRecord({ access = "code", psid = "ps", owner = 0 })).toBe(nil)
			T.expect(Places.privateRecord("x")).toBe(nil)
		end
	)

	T.it(
		"хаб: карты показательного матча — настоящие карты игры",
		function()
			for _, id in Config.Hub.DemoMaps do
				T.expect((Config.RealMaps :: any)[id] ~= nil).toBe(true)
			end
			T.expect(Config.Hub.DemoNations >= 2).toBe(true)
		end
	)
end)

T.describe("Лобби в общем списке и приглашения (§15ъ)", function()
	local MatchSim = require("../src/shared/MatchSim")
	local TinyMap = require("./lib/TinyMap")

	T.it(
		"запись лобби (Waiting / Lobby) проходит проверку хаба: режим — не nil",
		function()
			local m = MatchSim.new(TinyMap.plains(64, 32), 3)
			for _, phase in { "Waiting", "Lobby" } do
				m.phase = phase :: any
				local raw = {
					id = "job-1",
					psid = "ps-1",
					map = "Europe",
					mode = MatchSim.lobbyMode(m), -- так пишет сервер матча (раньше — Modes.tally по пустым вариантам = nil)
					phase = phase,
					players = 1,
					max = 50,
					left = 30,
					at = NOW,
					users = { 111 },
				}
				local entry = Places.entry(raw, NOW)
				T.expect(entry ~= nil).toBe(true)
				T.expect(Places.action(entry :: Places.Entry)).toBe("join")
			end
		end
	)

	T.it(
		"сервер друга по UserId; список игроков проверяется, мусор отбрасывается",
		function()
			local raw = {
				id = "job-2",
				psid = "ps-2",
				map = "World",
				mode = "Ffa",
				phase = "Lobby",
				players = 3,
				max = 50,
				left = 20,
				at = NOW,
				users = { 5, "x", 7.5, 9 },
			}
			local entry = Places.entry(raw, NOW) :: Places.Entry
			T.expect(entry.users).toEqual({ 5, 9 })
			local other = e("job-3", "Lobby", 1)
			T.expect(Places.serverOf({ other, entry }, 9)).toBe(entry)
			T.expect(Places.serverOf({ other, entry }, 42)).toBe(nil)
		end
	)

	T.it(
		"данные приглашения: сервер или код своего матча; мусор — nil",
		function()
			local a = Places.invite({ psid = "abc" }) :: any
			T.expect(a.psid).toBe("abc")
			T.expect(a.code).toBe(nil)
			T.expect(Places.invite({ psid = "" })).toBe(nil)
			T.expect(Places.invite("nope")).toBe(nil)
			T.expect(Places.invite({ psid = 5 })).toBe(nil)
			local code = Places.newCode(function(_n: number): number
				return 1
			end)
			local b = Places.invite({ psid = "abc", code = code }) :: any
			T.expect(b.code).toBe(code)
		end
	)
end)
