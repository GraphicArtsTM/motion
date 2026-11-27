--!strict
-- §15ъ «Экран не мешает играть»: в худшем случае (война, два предложения, задача, «Судный день», подсказка) карта
-- свободна не меньше чем на Hud.FreeShare. Считаем по сетке 4×4 условных px объединение рамок HUD: раскладка
-- телефона — PhoneLayout.hud (удары и окна — веером, по одной кнопке), ПК — размеры из Config; столбик по центру —
-- одна карточка (HudFocus), колонка справа — одна плашка со значками.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local HudFocus = require("../src/shared/HudFocus")
local PhoneLayout = require("../src/shared/PhoneLayout")

type Rect = PhoneLayout.Rect

local CELL = 4

local function freeShare(w: number, h: number, rects: { Rect }): number
	local cols, rows = math.ceil(w / CELL), math.ceil(h / CELL)
	local taken = buffer.create(cols * rows)
	local count = 0
	for _, r in rects do
		local x0 = math.clamp(math.floor(r.x / CELL), 0, cols)
		local x1 = math.clamp(math.ceil((r.x + r.w) / CELL), 0, cols)
		local y0 = math.clamp(math.floor(r.y / CELL), 0, rows)
		local y1 = math.clamp(math.ceil((r.y + r.h) / CELL), 0, rows)
		for y = y0, y1 - 1 do
			for x = x0, x1 - 1 do
				local i = y * cols + x
				if buffer.readu8(taken, i) == 0 then
					buffer.writeu8(taken, i, 1)
					count += 1
				end
			end
		end
	end
	return 1 - count / (cols * rows)
end

-- Худший случай столбика по центру: сколько карточек на экране при «Обычно».
local function centerCards(): number
	local shown = HudFocus.pick({
		Alarm = true,
		PeaceOffer = true,
		DiplomacyOffer = true,
		WarStatus = true,
		DoomBar = true,
		TaskCard = true,
	}, {})
	local n = 0
	for name in shown do
		if not HudFocus.isAlways(name) then
			n += 1
		end
	end
	return n
end

T.describe("Карта главнее (§15ъ)", function()
	T.it(
		"в столбике по центру при «Обычно» — одна карточка (тревога — вне счёта)",
		function()
			T.expect(centerCards()).toBe(1)
		end
	)

	T.it(
		"телефон: худший случай — карта свободна ≥ Hud.FreeSharePhone (667×300 … 1024×700)",
		function()
			local hud = Config.Hud
			local lineH = 18 * Config.Render.Phone.Hud.FeedScale
			for _, size in { { 667, 300 }, { 740, 310 }, { 844, 332 }, { 932, 372 }, { 1024, 700 } } do
				local w, h = size[1], size[2]
				local lay =
					PhoneLayout.hud(w, h, { strikes = 1, windows = 1, tools = 1, minimapW = 200, minimapH = 150 })
				local feedH = math.min(lay.feed.h, Config.Render.Phone.Hud.FeedLines * lineH)
				local cardW = math.min(lay.centerMaxW, Config.Render.Offers.WidthPx)
				local cardH = hud.CardMaxH * math.min(1, lay.centerMaxW / Config.Render.Offers.WidthPx)
				local rects: { Rect } = {
					lay.strikes,
					lay.bar,
					lay.minimap,
					lay.tools,
					lay.chips,
					{ x = lay.side.x, y = lay.side.y, w = lay.side.w, h = math.min(lay.side.h, hud.SideColumnH) },
					{ x = lay.feed.x, y = lay.feed.y + lay.feed.h - feedH, w = lay.feed.w, h = feedH },
					{ x = lay.centerX - cardW / 2, y = lay.topY, w = cardW, h = cardH * centerCards() },
				}
				if not lay.inBand then
					table.insert(rects, lay.menu)
					table.insert(rects, lay.windows)
				end
				local free = freeShare(w, h, rects)
				print(string.format("  телефон %d×%d: свободно %.0f%%", w, h, free * 100))
				T.expect(free >= hud.FreeSharePhone).toBe(true)
			end
		end
	)

	T.it(
		"ПК: худший случай — карта свободна ≥ Hud.FreeShare (1280…1920 × 900)",
		function()
			local hud = Config.Hud
			local r = Config.Render
			for _, size in { { 1280, 900 }, { 1440, 900 }, { 1600, 900 }, { 1920, 900 } } do
				local w, h = size[1], size[2]
				local s = r.Strikes
				local strikesW = 2 * 10 + 4 * s.TileW + 3 * 6
				local strikesScale = math.clamp(w * s.MaxScreenShare / strikesW, 0.6, 1)
				local barH = r.CommandBar.HeightPx
				local barTop = h - r.CommandBar.BottomPx - barH
				local buttonsH = 4 * r.MapButtons.HeightPx + 3 * r.MapButtons.GapPx
				local rects: { Rect } = {
					{ x = (w - 560) / 2, y = 8, w = 560, h = 70 }, -- верхняя полоса: время, «Контроль суши», 🔔
					{ x = (w - 560) / 2, y = 84, w = 560, h = hud.CardMaxH * centerCards() }, -- одна карточка
					{ x = w - 12 - hud.SideColumnW, y = 8, w = hud.SideColumnW, h = hud.SideColumnH }, -- одна плашка
					{ x = 12, y = 64, w = strikesW * strikesScale, h = 196 * strikesScale }, -- «УДАРЫ»
					{
						x = w - 12 - r.MinimapSide,
						y = barTop - 10 - r.MinimapSide,
						w = r.MinimapSide,
						h = r.MinimapSide,
					},
					{
						x = w - 12 - r.MapButtons.WidthPx,
						y = barTop - 10 - r.MinimapSide - 8 - buttonsH,
						w = r.MapButtons.WidthPx,
						h = buttonsH,
					},
					{ x = 12, y = barTop - 10 - r.FeedLines * 18, w = 320, h = r.FeedLines * 18 }, -- лента
				}
				local free = freeShare(w, h, rects)
				print(string.format("  ПК %d×%d: свободно %.0f%%", w, h, free * 100))
				T.expect(free >= hud.FreeShare).toBe(true)
			end
		end
	)
end)
