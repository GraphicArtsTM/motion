--!strict
--[[
	LabelLayout — подписи на карте без наложений (GDD §15ы), без Roblox API. Занятые места (города, их названия,
	уже поставленные подписи) — прямоугольники в пикселях холста; новая подпись пробует своё место и сдвиги по
	вертикали, первое свободное (с зазором Render.MapIcons.LabelGapPx) занимает, не нашлось — подписи нет.
]]

local Config = require("./Config")
local MapIcons = require("./MapIcons")

type Rect = MapIcons.Rect

export type Layout = { taken: { Rect }, names: { [string]: { { x: number, y: number } } } }

local LabelLayout = {}

function LabelLayout.new(): Layout
	return { taken = {}, names = {} }
end

-- Занять место (город, его название).
function LabelLayout.take(l: Layout, r: Rect)
	table.insert(l.taken, r)
end

local function free(l: Layout, r: Rect): boolean
	local g = Config.Render.MapIcons.LabelGapPx
	local wide = { x0 = r.x0 - g, y0 = r.y0 - g, x1 = r.x1 + g, y1 = r.y1 + g }
	for _, t in l.taken do
		if MapIcons.overlap(wide, t) then
			return false
		end
	end
	return true
end

-- Поставить подпись: want — желаемое место, shifts — сдвиги по вертикали (px) по порядку (первый обычно 0).
-- Возвращает сдвиг, который подошёл (место занято), или nil — подпись не влезает.
function LabelLayout.place(l: Layout, want: Rect, shifts: { number }): number?
	for _, dy in shifts do
		local r = { x0 = want.x0, y0 = want.y0 + dy, x1 = want.x1, y1 = want.y1 + dy }
		if free(l, r) then
			table.insert(l.taken, r)
			return dy
		end
	end
	return nil
end

-- §15й: одно и то же имя региона («Понтийская степь») на десяти соседних провинциях — каша. Есть ли уже подпись text
-- ближе dist px к (x, y); mark — запомнить поставленную.
function LabelLayout.repeats(l: Layout, text: string, x: number, y: number, dist: number): boolean
	local placed: { { x: number, y: number } } = l.names[text] or {}
	for _, p in placed do
		local dx, dy = p.x - x, p.y - y
		if dx * dx + dy * dy < dist * dist then
			return true
		end
	end
	return false
end

function LabelLayout.mark(l: Layout, text: string, x: number, y: number)
	local list = l.names[text]
	if list == nil then
		list = {}
		l.names[text] = list
	end
	table.insert(list, { x = x, y = y })
end

return table.freeze(LabelLayout)
