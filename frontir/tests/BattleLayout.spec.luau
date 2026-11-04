--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local BattleLayout = require("../src/shared/BattleLayout")
local Config = require("../src/shared/Config")
local MapData = require("../src/shared/MapData")
local Types = require("../src/shared/Types")

-- Карта: слева страна 1, справа 2 (граница между x = 14 и x = 15), по желанию — река посередине.
local function field(river: boolean): (MapData.MapData, (i: number) -> number, (i: number) -> boolean)
	local rows: { string } = {}
	for _ = 1, 20 do
		table.insert(rows, if river then string.rep(".", 15) .. "r" .. string.rep(".", 14) else string.rep(".", 30))
	end
	local map = TinyMap.fromRows(rows)
	local function ownerAt(i: number): number
		local x = i % 30
		if river and x == 15 then
			return 0
		end
		return if x < 15 then 1 else 2
	end
	local function isRiver(i: number): boolean
		return MapData.getTerrain(map, i) == Types.Terrain.River
	end
	return map, ownerAt, isRiver
end

local RECT = { x0 = 0, y0 = 0, x1 = 29, y1 = 19 }
local PAIRS = { [1 * 65536 + 2] = 1 }

T.describe("BattleLayout", function()
	T.it("линия фронта видна с обеих сторон, и через реку тоже", function()
		for _, river in { false, true } do
			local _, ownerAt, isRiver = field(river)
			local lineA, lineD = BattleLayout.scan(ownerAt, isRiver, 30, 20, RECT, 1, PAIRS, 1)
			T.expect(#lineA[1]).toBe(20)
			T.expect(#lineD[1]).toBe(20)
			for _, p in lineA[1] do
				T.expect(p.cell % 30).toBe(14)
				T.expect(p.dx).toBe(1)
			end
			for _, p in lineD[1] do
				T.expect(p.cell % 30).toBe(if river then 16 else 15)
				T.expect(p.dx).toBe(-1)
			end
		end
	end)

	T.it(
		"стороны стоят на своей земле, между ними ничейная полоса, артиллерия в тылу",
		function()
			local _, ownerAt, isRiver = field(false)
			local lineA, lineD = BattleLayout.scan(ownerAt, isRiver, 30, 20, RECT, 1, PAIRS, 1)
			local mix = { 0.5, 0.25, 0.25, 0 }
			local a = BattleLayout.place(lineA[1], 20, mix, nil, ownerAt, 1, 30, 20)
			local d = BattleLayout.place(lineD[1], 20, mix, nil, ownerAt, 2, 30, 20)
			T.expect(#a).toBe(20)
			local cfg = Config.Render.Battle
			local frontA, frontD = -math.huge, math.huge
			local art = 0
			for _, s in a do
				T.expect(ownerAt(math.floor(s.y) * 30 + math.floor(s.x))).toBe(1)
				if s.kind == "Artillery" then
					art += 1
					T.expect(15 - s.x >= cfg.ArtilleryBack).toBe(true)
				elseif s.kind == "Infantry" then
					frontA = math.max(frontA, s.x)
				end
			end
			for _, s in d do
				T.expect(ownerAt(math.floor(s.y) * 30 + math.floor(s.x))).toBe(2)
				if s.kind == "Infantry" then
					frontD = math.min(frontD, s.x)
				end
			end
			T.expect(art >= 4 and art <= 6).toBe(true) -- около четверти из 20
			T.expect(frontD - frontA >= cfg.NoMansLand).toBe(true)
		end
	)

	T.it("у точки главного удара юнитов больше", function()
		local _, ownerAt, isRiver = field(false)
		local lineA = BattleLayout.scan(ownerAt, isRiver, 30, 20, RECT, 1, PAIRS, 1)
		local focus = 2 * 30 + 20 -- против верхнего края линии
		local slots = BattleLayout.place(lineA[1], 20, { 1, 0, 0, 0 }, focus, ownerAt, 1, 30, 20)
		local top, bottom = 0, 0
		for _, s in slots do
			if s.y < 10 then
				top += 1
			else
				bottom += 1
			end
		end
		T.expect(top > bottom).toBe(true)
		T.expect(bottom > 0).toBe(true) -- остальная линия тоже держится
	end)

	T.it(
		"типы юнитов перемешаны в пропорциях состава, число — по силе",
		function()
			local counts: { [string]: number } = {}
			for k = 1, 100 do
				local kind = BattleLayout.kindAt({ 0.6, 0.3, 0.1, 0 }, k)
				counts[kind] = (counts[kind] or 0) + 1
			end
			T.expect(math.abs((counts.Infantry or 0) - 60) <= 3).toBe(true)
			T.expect(math.abs((counts.Tanks or 0) - 30) <= 3).toBe(true)
			T.expect(counts.AntiAir).toBe(nil)
			-- Соседи на линии — разные типы, а не блоки.
			T.expect(BattleLayout.kindAt({ 0.5, 0.5, 0, 0 }, 1) ~= BattleLayout.kindAt({ 0.5, 0.5, 0, 0 }, 2))
				.toBe(true)
			T.expect(BattleLayout.unitsFor(0)).toBe(0)
			T.expect(BattleLayout.unitsFor(1)).toBe(1)
			T.expect(BattleLayout.unitsFor(1e9)).toBe(Config.Render.Battle.MaxUnitsPerFront)
		end
	)
end)
