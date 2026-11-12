--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local Buildings = require("../src/shared/Buildings")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Diplomacy")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local StrikeForecast = require("../src/shared/StrikeForecast")

local W, H = 600, 40 -- широкая карта: дальний круг ПВО ур. 3 (40 на 512) больше ближнего (14)

-- Две державы: 1 — запад, 2 — восток (граница по x = 300).
local function duo(): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for y = 1, H - 2 do
		for x = 1, W - 2 do
			MapData.setProvince(map, y * W + x, x // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 3)
	m.victory = false
	MatchSim.addPlayer(m, 1, "A")
	MatchSim.addPlayer(m, 2, "B")
	m.phase = "Play"
	for y = 1, H - 2 do
		for x = 1, W - 2 do
			Grid.setOwner(m.grid, y * W + x, if x < 300 then 1 else 2)
		end
	end
	return m
end

-- Прогноз по данным, которые видит клиент: заряды и уровни всех батарей ПВО (как MatchStats.world и здания).
local function forecast(m: MatchSim.Match, cell: number, kind: StrikeForecast.Kind): StrikeForecast.Result
	local defs: { StrikeForecast.Defense } = {}
	for _, b in MatchSim.buildingsOf(m, "AirDefense") do
		local ready, max = MatchSim.batteryCharges(m, b.cell)
		local level = m.buildings.byCell[b.cell].level
		table.insert(defs, { cell = b.cell, kind = "AirDefense", ready = ready, max = max, level = level })
	end
	local victim = Grid.getOwner(m.grid, cell)
	return StrikeForecast.compute({
		width = W,
		cell = cell,
		kind = kind,
		victim = victim,
		ownerAt = function(c: number): number
			return Grid.getOwner(m.grid, c)
		end,
		friends = Diplomacy.trustFriends(m.diplo, victim),
		defenses = defs,
	})
end

T.describe("Прогноз удара (§15х)", function()
	T.it(
		"совпадает с сервером: ПВО сбивает ракету, бомбе нужно больше зарядов, ПВО ур. 3 далеко — только ракеты",
		function()
			local m = duo()
			local target = 20 * W + 450
			-- Без защиты — всё доходит.
			T.expect(forecast(m, target, "missile").stopped).toBe(false)
			-- Батарея ПВО рядом с целью: ракету и налёт сбивает, атомной (2 заряда) — не хватает.
			local near = 20 * W + 455
			Buildings.place(m.buildings, "AirDefense", near, MapData.getProvince(m.map, near))
			MatchSim.refreshOwned(m)
			local f = forecast(m, target, "missile")
			T.expect(f.stopped).toBe(true)
			T.expect(f.covers[1].kind).toBe("AirDefense")
			T.expect(f.covers[1].long).toBe(false)
			T.expect(forecast(m, target, "raid").stopped).toBe(true)
			local atom = forecast(m, target, "atom")
			T.expect(atom.need).toBe(Config.Nukes.Atom.charges)
			T.expect(atom.stopped).toBe(atom.ready >= atom.need)
			-- Сервер решает так же (и только тогда тратит заряды).
			local byAtom = MatchSim.interceptCharges(m, 2, target, atom.need)
			T.expect(byAtom ~= nil).toBe(atom.stopped)
			local again = forecast(m, target, "missile")
			local by = MatchSim.intercept(m, 2, target, true)
			T.expect(by ~= nil).toBe(again.stopped)
			-- §15х ч.6: батарея в 30 клетках от цели (за ближним кругом 14): ур. 1 не достаёт, ур. 3 — дальний круг
			-- (40 на ширину 512 ≈ 47 клеток) сбивает ракету, но не налёт.
			local far = 20 * W + 330
			local aa = 20 * W + 360
			Buildings.place(m.buildings, "AirDefense", aa, MapData.getProvince(m.map, aa))
			MatchSim.refreshOwned(m)
			T.expect(forecast(m, far, "missile").stopped).toBe(false)
			T.expect((MatchSim.intercept(m, 2, far, true))).toBe(nil)
			m.buildings.byCell[aa].level = 3
			MatchSim.refreshOwned(m)
			local fm = forecast(m, far, "missile")
			T.expect(fm.stopped).toBe(true)
			T.expect(fm.covers[1].long).toBe(true)
			T.expect(forecast(m, far, "raid").stopped).toBe(false)
			T.expect((MatchSim.intercept(m, 2, far, false))).toBe(nil)
			T.expect((MatchSim.intercept(m, 2, far, true))).toBe(2)
			-- Ничья земля и своя — не прикрыты чужой защитой.
			T.expect(#forecast(m, 20 * W + 30, "missile").covers).toBe(0)
		end
	)

	T.it(
		"истребители врага у цели — предупреждение для налёта, на ракету не влияют",
		function()
			local input: StrikeForecast.Input = {
				width = W,
				cell = 10 * W + 10,
				kind = "raid",
				victim = 2,
				ownerAt = function(_c: number): number
					return 2
				end,
				friends = {},
				defenses = {},
				fighters = { { x = 12, y = 11 }, { x = 110, y = 30 } },
			}
			local r = StrikeForecast.compute(input)
			T.expect(r.fighters).toBe(1)
			T.expect(r.stopped).toBe(false)
			input.kind = "missile"
			T.expect(StrikeForecast.compute(input).fighters).toBe(0)
		end
	)
end)

T.describe("Что делает здание (§15х ч.2)", function()
	T.it(
		"у каждого здания есть строка «что делает»; у ПВО, аэродрома, порта, города — радиус",
		function()
			local Strings = require("../src/shared/Strings")
			-- §15х ч.6: 10 видов зданий — ни ЗРК, ни радара, ни рынка.
			T.expect(#Config.Buildable).toBe(10)
			for _, kind in Config.Buildable do
				T.expect(Strings.Table["range." .. kind] ~= nil).toBe(true)
			end
			for _, kind in { "AirDefense", "Airfield", "Port", "City" } do
				T.expect((Buildings.rangeOf(kind, 512) or 0) > 0).toBe(true)
			end
			T.expect(Buildings.rangeOf("Factory", 512)).toBe(nil)
			-- Радиус защиты в прогнозе и в круге здания — один и тот же.
			T.expect(StrikeForecast.radius(3, 768, true)).toBe(Buildings.rangeOf("AirDefense", 768, 3))
			T.expect(StrikeForecast.radius(1, 768, true)).toBe(Buildings.rangeOf("AirDefense", 768))
			T.expect(StrikeForecast.radius(3, 768, false)).toBe(Buildings.rangeOf("AirDefense", 768))
		end
	)
end)
