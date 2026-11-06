--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Config = require("../src/shared/Config")
local MatchSim = require("../src/shared/MatchSim")
local Modes = require("../src/shared/Modes")
local ServerSettings = require("../src/shared/ServerSettings")

local DT = 1 / Config.Sim.TickRate

local function valid(): { [string]: any }
	return {
		map = "Europe",
		mode = "Blitz",
		nations = 6,
		botLevel = "General",
		speed = 2,
		startMoney = 16000,
		fog = true,
		diplomacy = false,
	}
end

T.describe("Частный сервер (§5.4)", function()
	T.it(
		"разбор настроек: только значения из списков; держав — не больше максимума карты",
		function()
			local s = ServerSettings.parse(valid(), "World")
			T.expect(s ~= nil).toBe(true)
			local d = ServerSettings.defaults("Europe")
			T.expect(d.map).toBe(nil)
			T.expect(d.mode).toBe(nil)
			T.expect(d.nations).toBe(Config.RealMaps.Europe.Nations)
			T.expect(d.diplomacy).toBe(true)
			local function bad(field: string, value: any): boolean
				local p = valid()
				p[field] = value
				return (ServerSettings.parse(p, "World")) == nil
			end
			T.expect(bad("map", "Atlantis")).toBe(true)
			T.expect(bad("mode", "Duel")).toBe(true)
			T.expect(bad("mode", "Royale")).toBe(true)
			T.expect(bad("nations", 1)).toBe(true)
			T.expect(bad("nations", Config.RealMaps.Europe.MaxPlayers + 1)).toBe(true)
			T.expect(bad("nations", 6.5)).toBe(true)
			T.expect(bad("botLevel", "Boss")).toBe(true)
			T.expect(bad("speed", 3)).toBe(true)
			T.expect(bad("startMoney", 1)).toBe(true)
			T.expect(bad("fog", "yes")).toBe(true)
			T.expect((ServerSettings.parse("x", "World"))).toBe(nil)
			-- Без карты предел — по текущей карте.
			local p = valid()
			p.map = nil
			p.nations = Config.RealMaps.World.MaxPlayers
			T.expect(ServerSettings.parse(p, "World") ~= nil).toBe(true)
			T.expect((ServerSettings.parse(p, "Scandinavia"))).toBe(nil)
		end
	)

	T.it(
		"правила с настройками: скорость поверх режима, туман, дипломатия",
		function()
			local s = ServerSettings.parse(valid(), "World") :: ServerSettings.Settings
			local r = ServerSettings.applyRules(Modes.rules("Blitz"), s)
			T.expect(r.speed).toBeNear(Config.Modes.BlitzSpeed * 2)
			T.expect(r.fog).toBe(true)
			T.expect(r.hideTerritory).toBe(false)
			T.expect(r.diplomacy).toBe(false)
		end
	)

	T.it(
		"в матче: режим без голосования, боты и деньги из настроек, без дипломатии, карта без голосования",
		function()
			local s = ServerSettings.parse(valid(), "World") :: ServerSettings.Settings
			local m = MatchSim.new(Fixtures.pangea, 3)
			m.settings = s
			m.forcedMode = s.mode
			m.targetNations = s.nations
			MatchSim.openVote(m, 0)
			T.expect(#m.modeOptions).toBe(0) -- режим задан — голосования нет
			MatchSim.addPlayer(m, 1, "Владелец")
			T.expect(#m.modeOptions).toBe(0)
			MatchSim.startPick(m)
			while m.phase ~= "Play" do
				MatchSim.step(m, DT)
			end
			T.expect(m.mode).toBe("Blitz")
			T.expect(m.speed).toBeNear(Config.Match.Speed * Config.Modes.BlitzSpeed * 2)
			T.expect(m.rules.fog).toBe(true)
			T.expect(#m.nations).toBe(6)
			for _, n in m.nations do
				T.expect(n.money).toBe(16000)
				if n.isBot then
					T.expect(n.botLevel).toBe("General")
				end
			end
			T.expect(select(2, MatchSim.offer(m, 1, 2, "alliance"))).toBe("diplomacyOff")
			T.expect(select(2, MatchSim.offer(m, 1, 2, "trade"))).toBe("diplomacyOff")
			-- Война и мир — можно.
			T.expect((MatchSim.applyIntent(m, 1, { kind = "declare", target = 2 }))).toBe(true)
			-- Карта выбрана владельцем — голосования за карту в лобби нет (§15к).
			MatchSim.openMapVote(m)
			T.expect(#m.mapOptions).toBe(0)
			T.expect(MatchSim.mapWinner(m)).toBe(m.map.name)
		end
	)
end)
