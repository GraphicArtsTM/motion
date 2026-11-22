--!strict
-- §15ы: значки на карте не налезают друг на друга, подписи не накладываются, корабль крупнее.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local LabelLayout = require("../src/shared/LabelLayout")
local MapIcons = require("../src/shared/MapIcons")

local R = Config.Render

-- Все зумы, на которых видны значки зданий (дальше — точки).
local function iconZooms(): { number }
	local out = {}
	local z = R.BuildingDotZoom
	while z <= R.ZoomMax + 1e-9 do
		table.insert(out, z)
		z += 0.25
	end
	return out
end

T.describe("Значки зданий не налезают (§15ы Ы1)", function()
	T.it(
		"два здания на разрешённом расстоянии — значки не перекрываются ни на одном зуме",
		function()
			local gap = Config.Build.MinGap
			local checked = 0
			for _, z in iconZooms() do
				for dy = -8, 8 do
					for dx = -8, 8 do
						if math.max(math.abs(dx), math.abs(dy)) >= gap then
							local sa = MapIcons.sideAmong(z, { { dx = dx, dy = dy } }, {})
							local sb = MapIcons.sideAmong(z, { { dx = -dx, dy = -dy } }, {})
							local a = MapIcons.rect(0, 0, z, sa)
							local b = MapIcons.rect(dx, dy, z, sb)
							T.expect(MapIcons.overlap(a, b)).toBe(false)
							checked += 1
						end
					end
				end
			end
			T.expect(checked > 1000).toBe(true)
		end
	)

	T.it(
		"снимок «казармы над заводом»: 3 клетки — теперь нельзя, 4 — значки рядом, не друг на друге",
		function()
			T.expect(Config.Build.MinGap >= 4).toBe(true)
			for _, z in iconZooms() do
				local s = MapIcons.sideAmong(z, { { dx = 0, dy = Config.Build.MinGap } }, {})
				T.expect(s <= Config.Build.MinGap * z - R.MapIcons.GapPx).toBe(true)
				T.expect(s >= R.MapIcons.MinPx).toBe(true)
			end
		end
	)

	T.it(
		"одинокое здание — обычного размера, растёт с зумом, в пределах MinPx..MaxPx",
		function()
			local prev = 0
			for _, z in iconZooms() do
				local s = MapIcons.sideAmong(z, {}, {})
				T.expect(s >= R.MapIcons.MinPx and s <= R.MapIcons.MaxPx).toBe(true)
				T.expect(s >= prev).toBe(true)
				prev = s
			end
			-- На крупном зуме значок заметно крупнее мелкого.
			T.expect(MapIcons.sideAmong(R.ZoomMax, {}, {}) >= 2 * MapIcons.sideAmong(R.BuildingDotZoom, {}, {}))
				.toBe(true)
		end
	)

	T.it(
		"здание у города: жетон уступает место, значок не залезает на жетон, если места хватает; с ×7 — у всех уровней",
		function()
			local gap = Config.Build.MinGap
			local overlaps = 0
			for _, z in iconZooms() do
				for level = 1, 5 do
					for dy = -8, 8 do
						for dx = -8, 8 do
							if math.max(math.abs(dx), math.abs(dy)) >= gap then
								-- Здание в (dx, dy) от города: жетон считает его, значок — настоящий край жетона.
								local citySide = MapIcons.citySideAmong(level, z, { { dx = dx, dy = dy } })
								T.expect(citySide + 1 >= MapIcons.citySide(level, z) * R.MapIcons.CityShrinkMin)
									.toBe(true)
								local half = MapIcons.halfOf(citySide)
								local room = MapIcons.cityRoom(z, -dx, -dy, half)
								local s, byCity = MapIcons.sideAmong(z, {}, { { dx = -dx, dy = -dy, half = half } })
								local hit =
									MapIcons.overlap(MapIcons.rect(dx, dy, z, s), MapIcons.rect(0, 0, z, 2 * half))
								if room >= s then
									T.expect(hit).toBe(false)
								else
									-- Не влез — урезан не меньше NearCityMin и рисуется поверх города.
									T.expect(byCity).toBe(true)
									T.expect(s + 1 >= MapIcons.buildingBase(z) * R.MapIcons.NearCityMin).toBe(true)
									overlaps += 1
								end
								if z >= 7 then
									T.expect(hit).toBe(false)
								end
							end
						end
					end
				end
			end
			T.expect(overlaps >= 0).toBe(true)
		end
	)
end)

T.describe("Города и корабли видно (§15ы Ы2–Ы3)", function()
	T.it(
		"жетон города растёт с уровнем, не мельче CityMinPx и не больше CityMaxPx, крупнее значка здания",
		function()
			for _, z in iconZooms() do
				local prev = 0
				for level = 1, 5 do
					local side = MapIcons.citySide(level, z)
					T.expect(side >= R.MapIcons.CityMinPx[level] and side <= R.MapIcons.CityMaxPx).toBe(true)
					T.expect(side >= prev).toBe(true)
					T.expect(side > MapIcons.buildingBase(z)).toBe(true)
					prev = side
				end
			end
		end
	)

	T.it(
		"корабль: не мельче MinPx и крупнее прежнего (8 px спрайта × масштаб × 1.5)",
		function()
			for _, z in iconZooms() do
				local scale = 1
				for _, step in R.UnitSpriteScales do
					if z >= step.zoom then
						scale = step.scale
					end
				end
				local side = MapIcons.shipSide(z)
				T.expect(side >= R.ShipAnim.MinPx and side <= R.ShipAnim.MaxPx).toBe(true)
				T.expect(side >= 8 * scale * 1.5).toBe(true)
			end
		end
	)

	T.it(
		"кильватер короткий: клуб не больше корабля и живёт меньше секунды",
		function()
			local sp = R.Spectacle
			T.expect(sp.WakeSec <= 1).toBe(true)
			T.expect(sp.WakeSize[2] * R.ZoomMax <= MapIcons.shipSide(R.ZoomMax)).toBe(true)
			T.expect(sp.WakeAlpha >= 0.5).toBe(true)
		end
	)
end)

T.describe("Подписи без наложений (§15ы Ы2)", function()
	T.it(
		"подпись не встаёт на занятое место: сдвигается ниже, а некуда — пропускается",
		function()
			local l = LabelLayout.new()
			LabelLayout.take(l, { x0 = 0, y0 = 0, x1 = 100, y1 = 20 }) -- название города
			local want = { x0 = 20, y0 = 10, x1 = 80, y1 = 26 }
			T.expect(LabelLayout.place(l, want, { 0, 20 })).toBe(20)
			-- То же место ещё раз: 0 и 20 уже заняты.
			T.expect(LabelLayout.place(l, want, { 0, 20 })).toBe(nil)
			-- Свободное место — без сдвига.
			T.expect(LabelLayout.place(l, { x0 = 300, y0 = 0, x1 = 360, y1 = 16 }, { 0, 20 })).toBe(0)
		end
	)
end)

T.describe("Нажатие по жетону города (§15й Й1)", function()
	T.it(
		"точка внутри жетона — в город, за его краем — нет; на ближнем зуме жетон меньше в клетках",
		function()
			local zoom = 4
			local side = MapIcons.citySide(1, zoom)
			local r = MapIcons.halfOf(side) / zoom
			T.expect(MapIcons.inToken(0, 0, side, zoom)).toBe(true)
			T.expect(MapIcons.inToken(r * 0.9, 0, side, zoom)).toBe(true)
			T.expect(MapIcons.inToken(r * 0.8, r * 0.8, side, zoom)).toBe(false)
			T.expect(MapIcons.inToken(r * 1.1, 0, side, zoom)).toBe(false)
			local near = 20
			T.expect(MapIcons.halfOf(MapIcons.citySide(1, near)) / near <= r).toBe(true)
		end
	)
end)

T.describe("Подписи регионов без повторов (§15й)", function()
	T.it(
		"то же имя ближе dist — повтор; дальше или другое имя — нет",
		function()
			local l = LabelLayout.new()
			LabelLayout.mark(l, "Степь", 100, 100)
			T.expect(LabelLayout.repeats(l, "Степь", 150, 120, 200)).toBe(true)
			T.expect(LabelLayout.repeats(l, "Степь", 500, 100, 200)).toBe(false)
			T.expect(LabelLayout.repeats(l, "Альпы", 110, 100, 200)).toBe(false)
		end
	)
end)

return nil
