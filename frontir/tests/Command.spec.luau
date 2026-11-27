--!strict
-- §15ь Л1 «Принять командование»: какую державу бота дают, место, когда можно; сервер передаёт державу человеку.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Command = require("../src/shared/Command")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")

local function facts(over: { [string]: any }): Command.Facts
	local f: Command.Facts = {
		phase = "Play",
		duel = false,
		tutorial = false,
		secLeft = math.huge,
		used = false,
		living = false,
	}
	for k, v in over do
		(f :: any)[k] = v
	end
	return f
end

T.describe("Принять командование (§15ь Л1)", function()
	T.it(
		"бот со срединной сушей среди живых ботов; люди и мёртвые — мимо",
		function()
			local rows: { Command.Row } = {
				{ id = 1, land = 900, bot = false, alive = true }, -- человек
				{ id = 2, land = 500, bot = true, alive = true },
				{ id = 3, land = 300, bot = true, alive = true },
				{ id = 4, land = 100, bot = true, alive = true },
				{ id = 5, land = 0, bot = true, alive = false },
			}
			T.expect(Command.candidate(rows)).toBe(3)
			T.expect(Command.candidate({ rows[1] })).toBe(nil)
			local place, total = Command.place(rows, 3)
			T.expect(place).toBe(3)
			T.expect(total).toBe(4)
			T.expect((Command.place(rows, 5))).toBe(nil)
		end
	)

	T.it(
		"нельзя: не в игре, дуэль, обучение, живая своя держава, второй раз, под конец матча",
		function()
			T.expect((Command.allowed(facts({})))).toBe(true)
			T.expect(select(2, Command.allowed(facts({ phase = "Lobby" })))).toBe("notYet")
			T.expect(select(2, Command.allowed(facts({ duel = true })))).toBe("commandMode")
			T.expect(select(2, Command.allowed(facts({ tutorial = true })))).toBe("commandMode")
			T.expect(select(2, Command.allowed(facts({ living = true })))).toBe("commandAlive")
			T.expect(select(2, Command.allowed(facts({ used = true })))).toBe("commandUsed")
			local late = facts({ secLeft = Config.Command.MinSecLeft - 1 })
			T.expect(select(2, Command.allowed(late))).toBe("commandLate")
		end
	)

	T.it(
		"сервер: выбывший берёт срединного бота — держава становится его, бот больше не думает; второй раз — нельзя",
		function()
			local W, H = 120, 20
			local map = TinyMap.plains(W, H)
			for i = 0, W * H - 1 do
				if MapData.getTerrain(map, i) ~= 0 then
					MapData.setProvince(map, i, (i % W) // 10 + 1)
				end
			end
			local m = MatchSim.new(map, 5)
			m.victory = false
			MatchSim.addPlayer(m, 77, "Игрок")
			for k = 1, 3 do
				MatchSim.addPlayer(m, 100 + k, "Бот" .. k)
			end
			m.phase = "Play"
			for id = 2, 4 do
				MatchSim.setBot(m, id, "Normal")
			end
			-- Суша: бот 2 — 30 столбцов, бот 3 — 20, бот 4 — 10; игрок 1 — выбыл.
			local spans = { [2] = { 1, 30 }, [3] = { 31, 50 }, [4] = { 51, 60 } }
			for id, span in spans do
				for y = 1, H - 2 do
					for x = span[1], span[2] do
						Grid.setOwner(m.grid, y * W + x, id)
					end
				end
			end
			m.nations[1].alive = false
			local id, why = MatchSim.takeCommand(m, 77)
			T.expect(why).toBe(nil)
			T.expect(id).toBe(3)
			local n = m.nations[3]
			T.expect(n.isBot).toBe(false)
			T.expect(n.userId).toBe(77)
			T.expect(n.botLevel).toBe(nil)
			T.expect(m.botProfiles[3]).toBe(nil)
			local again, why2 = MatchSim.takeCommand(m, 77)
			T.expect(again).toBe(nil)
			T.expect(why2).toBe("commandAlive")
			n.alive = false
			local third, why3 = MatchSim.takeCommand(m, 77)
			T.expect(third).toBe(nil)
			T.expect(why3).toBe("commandUsed")
			-- Тики после передачи не падают.
			for _ = 1, 20 do
				MatchSim.step(m, 1 / Config.Sim.TickRate)
			end
		end
	)
end)
