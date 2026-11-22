--!strict
--[[
	PhoneLayout — раскладка телефона (GDD §15ц Ц5в, §15ё). Чистые правила, клиент только применяет.
	- narrow(width, force): условная ширина слоя меньше Render.NarrowScreenPx (или Dev.PhoneLayout в Studio);
	- phone(width, height, force): §15ё телефонный экран — узкий или низкий (высота меньше Phone.Hud.ShortScreenPx);
	- bar(...): нижняя полоса на компьютере — в одну строку (ужимается до MinScale) или, если не влезает, в две:
	  ширина — по нижней строке, масштаб — до ширины экрана, не мельче MinScale;
	- phoneBar(natural, avail): §15ё полоса телефона — одна строка, ужимается до ширины экрана (не мельче MinScale);
	- hud(w, h, counts): §15ё где что стоит на экране матча телефона (прямоугольники в условных px, от левого верха).
]]

local Config = require("./Config")

export type Bar = {
	rows: number, -- 1 или 2
	width: number, -- ширина полосы до масштаба (условные px)
	scale: number,
}

export type Rect = { x: number, y: number, w: number, h: number }

export type HudCounts = {
	strikes: number, -- плиток ударов
	windows: number, -- кнопок окон в верхней строке
	tools: number, -- квадратов у мини-карты (Угрозы, Метки, Логистика)
	minimapW: number, -- мини-карта до масштаба
	minimapH: number,
	-- §15ё полоса Roblox сверху (над слоем HUD): левый край свободной части и высота; 0 — нет. Верхний ряд встаёт в
	-- неё, если помещается: так у HUD на телефоне на ~58 условных px больше высоты.
	bandX: number?,
	bandH: number?,
}

export type Hud = {
	-- В полосе Roblox (координаты от верха экрана, не HUD): menu, windows и top; удары — тогда в HUD справа сверху.
	inBand: boolean,
	menu: Rect, -- «меню»
	strikes: Rect, -- «УДАРЫ» квадратами (HUD)
	windows: Rect, -- кнопки окон механик
	top: Rect?, -- §15ё Ё6: время и «Контроль суши» в полосе Roblox (nil — не влезает: остаются сверху по центру)
	centerX: number, -- середина столбика сверху (HUD)
	topY: number, -- под верхней строкой: столбики по центру и справа
	side: Rect, -- колонка справа («#N · M%», «АТАКИ» свёрнутые)
	centerMaxW: number, -- ширина столбика по центру (между колонками)
	bar: Rect, -- полоса (верх — самое высокое место полосы)
	minimap: Rect,
	minimapScale: number, -- масштаб мини-карты (не выше колонки справа)
	tools: Rect,
	chips: Rect, -- фишки своих атак (столбиком, правый край — у квадратов)
	feed: Rect, -- подсказка и лента (растут снизу вверх до topY)
}

local PhoneLayout = {}

function PhoneLayout.narrow(width: number, force: boolean?): boolean
	return force == true or width < Config.Render.NarrowScreenPx
end

function PhoneLayout.phone(width: number, height: number, force: boolean?): boolean
	return PhoneLayout.narrow(width, force) or height < Config.Render.Phone.Hud.ShortScreenPx
end

-- natural — ширина в одну строку, second — ширина нижней строки (войска, стройка, арсенал, магазин),
-- avail — сколько места по ширине, narrow — узкий экран.
function PhoneLayout.bar(natural: number, second: number, avail: number, narrow: boolean): Bar
	local minScale = Config.Render.CommandBar.MinScale
	if not narrow then
		local s = math.min(1, avail / natural)
		if s >= minScale then
			return { rows = 1, width = natural, scale = s }
		end
	end
	local width = math.min(natural, second)
	return { rows = 2, width = width, scale = math.clamp(avail / width, minScale, 1) }
end

function PhoneLayout.phoneBar(natural: number, avail: number): Bar
	local minScale = Config.Render.CommandBar.MinScale
	return { rows = 1, width = natural, scale = math.clamp(avail / natural, minScale, 1) }
end

-- Ширина ряда из n квадратов по px с промежутками.
local function row(n: number, px: number, gap: number): number
	return if n <= 0 then 0 else n * px + (n - 1) * gap
end

function PhoneLayout.hud(w: number, h: number, c: HudCounts): Hud
	local cfg = Config.Render.Phone.Hud
	local touch = Config.Render.MinTouchTargetPx
	local e, g = cfg.Edge, cfg.Gap

	local strikesW = row(c.strikes, cfg.StrikePx, g)
	local winW = row(c.windows, cfg.WindowPx, g)
	local rowH = math.max(touch, cfg.WindowPx)
	-- Полоса Roblox: по высоте влезает ряд и справа от кнопок Roblox хватает места на «меню» и кнопки окон.
	local bandX, bandH = c.bandX or 0, c.bandH or 0
	local inBand = bandH >= rowH + 2 and bandX + g + touch + 2 * g + winW + e <= w
	local menu: Rect
	local windows: Rect
	local strikes: Rect
	local top: Rect? = nil
	local topY: number
	local side: Rect
	local centerX: number, centerMaxW: number
	if inBand then
		-- §15ё Ё6: в полосе — «меню», время и «Контроль суши» (если влезает), справа — кнопки окон; удары — столбиком
		-- сверху вниз у левого края под полосой (решение геймдизайнера), справа сверху — «#N · M%» и «АТАКИ».
		-- Лента и «Обучение» — правее столбика ударов.
		local y = math.floor((bandH - rowH) / 2)
		-- §15ё Ё8: «меню» — того же размера, что кнопки окон рядом.
		menu = { x = bandX + g, y = y, w = rowH, h = rowH }
		windows = { x = w - e - winW, y = y + (rowH - cfg.WindowPx) / 2, w = winW, h = cfg.WindowPx }
		local topH = math.min(cfg.BandTopH, bandH - 4)
		local candidate: Rect =
			{ x = menu.x + menu.w + g, y = math.floor((bandH - topH) / 2), w = cfg.BandTopW, h = topH }
		if candidate.x + candidate.w + 2 * g <= windows.x then
			top = candidate
		end
		topY = cfg.TopY
		strikes = { x = e, y = cfg.TopY, w = cfg.StrikePx, h = row(c.strikes, cfg.StrikePx, g) }
		side = { x = w - e - cfg.SideW, y = cfg.TopY, w = cfg.SideW, h = cfg.SideH }
		-- Столбик сверху (тревоги, война, сирена): по центру экрана, между ударами и колонкой справа.
		local left, right = strikes.x + strikes.w + g, side.x - g
		centerX = w / 2
		centerMaxW = 2 * math.min(centerX - left, right - centerX)
		if centerMaxW < cfg.CenterMinW then
			centerX = (left + right) / 2
			centerMaxW = right - left
		end
	else
		local y = cfg.TopY
		local rowAll = math.max(rowH, cfg.StrikePx)
		menu = { x = e, y = y + (rowAll - touch) / 2, w = touch, h = touch }
		strikes = { x = menu.x + menu.w + g, y = y + (rowAll - cfg.StrikePx) / 2, w = strikesW, h = cfg.StrikePx }
		windows = { x = w - e - winW, y = y + (rowAll - cfg.WindowPx) / 2, w = winW, h = cfg.WindowPx }
		topY = cfg.TopY + rowAll + g
		side = { x = w - e - cfg.SideW, y = topY, w = cfg.SideW, h = cfg.SideH }
		centerX = w / 2
		centerMaxW = math.max(0, w - 2 * (e + cfg.SideW + g))
	end

	local barY = h - cfg.BarBottom - cfg.BarH
	local bar: Rect = { x = e, y = barY, w = w - 2 * e, h = cfg.BarH }
	local room = barY - g - (side.y + side.h + g)
	local mmScale = math.max(0, math.min(cfg.MinimapScale, room / math.max(1, c.minimapH)))
	local mmW, mmH = c.minimapW * mmScale, c.minimapH * mmScale
	local minimap: Rect = { x = w - e - mmW, y = barY - g - mmH, w = mmW, h = mmH }
	local toolsW = row(c.tools, cfg.ToolPx, g)
	local tools: Rect = {
		x = minimap.x - (if toolsW > 0 then g + toolsW else 0),
		y = barY - g - cfg.ToolPx,
		w = toolsW,
		h = if toolsW > 0 then cfg.ToolPx else 0,
	}
	local chipsH = row(cfg.ChipsMax, cfg.ChipPx, g)
	local chips: Rect
	local feedRight: number
	if inBand and toolsW > 0 then
		-- §15ё Ё7: справа сверху пусто (кнопки окон — в полосе) — фишки атак над квадратами у мини-карты, лента шире.
		chips = { x = tools.x + tools.w - cfg.ChipW, y = tools.y - g - chipsH, w = cfg.ChipW, h = chipsH }
		feedRight = tools.x
	else
		local chipsRight = (if toolsW > 0 then tools.x else minimap.x) - g
		chips = { x = chipsRight - cfg.ChipW, y = barY - g - chipsH, w = cfg.ChipW, h = chipsH }
		feedRight = chips.x
	end
	-- Лента и «Обучение» слева — правее столбика ударов, если удары у левого края.
	local feedX = if inBand then strikes.x + strikes.w + g else e
	local feedW = math.max(0, math.min(cfg.FeedW * cfg.FeedScale, feedRight - g - feedX))
	local feed: Rect = { x = feedX, y = topY, w = feedW, h = math.max(0, barY - g - topY) }

	return {
		inBand = inBand,
		menu = menu,
		strikes = strikes,
		windows = windows,
		top = top,
		topY = topY,
		side = side,
		centerX = centerX,
		centerMaxW = math.max(0, centerMaxW),
		bar = bar,
		minimap = minimap,
		minimapScale = mmScale,
		tools = tools,
		chips = chips,
		feed = feed,
	}
end

-- Пересекаются ли два прямоугольника (пустые — нет).
function PhoneLayout.overlap(a: Rect, b: Rect): boolean
	if a.w <= 0 or a.h <= 0 or b.w <= 0 or b.h <= 0 then
		return false
	end
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Целиком внутри экрана w×h.
function PhoneLayout.inside(r: Rect, w: number, h: number): boolean
	return r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h
end

return table.freeze(PhoneLayout)
