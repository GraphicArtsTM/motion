--!strict
-- Защита сервера (правка перед закрытым тестом): намерения с «плохими» данными, которые прошли Intents.parse
-- (клетки за краем карты, несуществующие державы, корабли, самолёты, провинции), не роняют ни applyIntent, ни
-- следующие тики симуляции. Ошибка в тике повторялась бы каждый кадр — матч замер бы для всех.
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local Intents = require("../src/shared/Intents")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Types = require("../src/shared/Types")

local DT = 1 / Config.Sim.TickRate
local W, H = 128, 24

local function match(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 7)
	m.victory = false
	MatchSim.addPlayer(m, 1, "N1")
	MatchSim.addPlayer(m, 2, "N2")
	m.phase = "Play"
	for y = 1, H - 2 do
		for x = 1, 100 do
			Grid.setOwner(m.grid, y * W + x, if x <= 50 then 1 else 2)
		end
	end
	local caps = { 12 * W + 10, 12 * W + 90 }
	for _, n in m.nations do
		n.colorIndex = n.id
		n.people = 5000
		n.money = 100000
		n.oil = 5000
		n.capital = caps[n.id]
		Grid.setCity(m.grid, caps[n.id], true)
		m.cityOf[-n.id] = caps[n.id]
	end
	return m
end

-- Все виды намерений и значения полей: «плохие» числа (за краем карты, огромные, чужие id) и все допустимые строки.
local KINDS = {
	"pick",
	"attack",
	"hire",
	"cancel",
	"declare",
	"peace",
	"peaceReply",
	"build",
	"demolish",
	"offer",
	"offerReply",
	"breakTreaty",
	"distrust",
	"rebel",
	"taskSkip",
	"endSolo",
	"transfer",
	"embargo",
	"vote",
	"ping",
	"ship",
	"land",
	"patrol",
	"plane",
	"raid",
	"cover",
	"research",
	"bid",
	"missile",
	"emoji",
	"intel",
	"mapVote",
	"modeVote",
	"difficulty",
	"solo",
	"commander",
	"ability",
}
local CELLS = { 0, W * H - 1, W * H, W * H + 77, 2 ^ 30, 12 * W + 90 }
local IDS = { 1, 2, 3, 99, 2 ^ 30, 0 }

local function choices(): { [string]: { any } }
	return {
		unit = Types.LandUnits,
		building = Config.Buildable,
		offer = { "pact3", "pact5", "alliance", "demand", "trade", "trust" },
		terms = { "white", "keep", "capitulate" },
		ship = { "Transport", "Destroyer", 1, 99, 2 ^ 30 },
		plane = { "Fighter", "Bomber", 1, 99, 2 ^ 30 },
		branch = { "Army", "Economy", "Fleet" },
		warhead = { "missile", "atom", "hydrogen" },
		phrase = Config.Pings.Phrases,
		map = Config.MapVote.Pool,
		mode = { "FFA", "Teams", "Tutorial" },
		level = Types.BotLevels,
		commander = Types.CommanderIds,
		accept = { true, false },
		on = { true, false },
		pause = { false, true },
		fast = { false, true },
		slot = { 1, 2 },
		percent = { 0, 0.5, 1 },
		emoji = { 1 },
		option = { 1, Config.Council.Options },
		amount = { 0, 100, 2 ^ 30 },
		money = { 0, 10, 2 ^ 30 },
		oil = { 0, 10, 2 ^ 30 },
		people = { 0, 10, 2 ^ 30 },
	}
end

local CELL_FIELDS = { "cell", "focus", "port", "airfield" }
local ID_FIELDS = { "target", "province" }

T.describe("Защита сервера: плохие намерения не роняют матч", function()
	T.it("ни applyIntent, ни 200 тиков после него не падают", function()
		local m = match()
		local errors: { string } = {}
		local applied = 0
		local pick = choices()
		for _, kind in KINDS do
			for v = 1, #CELLS do
				local payload: { [string]: any } = {}
				for _, f in CELL_FIELDS do
					payload[f] = CELLS[v]
				end
				for _, f in ID_FIELDS do
					payload[f] = IDS[v]
				end
				for field, list in pick do
					payload[field] = list[(v - 1) % #list + 1]
				end
				local intent = Intents.parse(kind, payload)
				if intent ~= nil then
					for _, nation in { 1, 2 } do
						local ok, err = pcall(function()
							MatchSim.applyIntent(m, nation, intent)
						end)
						applied += 1
						if not ok then
							table.insert(errors, kind .. " #" .. v .. ": " .. tostring(err))
						end
					end
					local okStep, errStep = pcall(function()
						for _ = 1, 5 do
							MatchSim.step(m, DT)
						end
					end)
					if not okStep then
						table.insert(errors, "тик после " .. kind .. " #" .. v .. ": " .. tostring(errStep))
						m = match() -- матч сломан — дальше на новом, чтобы найти все случаи
					end
				end
			end
		end
		local okRun, errRun = pcall(function()
			for _ = 1, 200 do
				MatchSim.step(m, DT)
			end
		end)
		if not okRun then
			table.insert(errors, "200 тиков: " .. tostring(errRun))
		end
		for _, e in errors do
			print("  ! " .. e)
		end
		T.expect(applied > 100).toBe(true)
		T.expect(#errors).toBe(0)
	end)
end)
