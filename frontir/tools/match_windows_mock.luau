--!strict
--[[
	Макет окон матча (§15л ч.11): меню порта, окно здания, условия мира, объявление войны, итоги — по размерам
	UI/CardKit, BuildingInfo, WarPanel, ResultsPanel. Текст — пиксельным шрифтом превью (в игре — шрифт интерфейса).
	Запуск: lune run tools/match_windows_mock docs/previews/ui-match-windows.png
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local ItemArt = require("../src/shared/ItemArt")
local Palette = require("../src/shared/Palette")
local PixelSkin = require("../src/shared/PixelSkin")
local Strings = require("../src/shared/Strings")
local PixelFont = require("./lib/PixelFont")
local Png = require("./lib/Png")

local W, H = 1120, 700
local px = buffer.create(W * H * 3)

local function fill(x: number, y: number, w: number, h: number, color: string)
	local c = Palette.rgb(color)
	for yy = math.max(0, y), math.min(H - 1, y + h - 1) do
		for xx = math.max(0, x), math.min(W - 1, x + w - 1) do
			local i = (yy * W + xx) * 3
			buffer.writeu8(px, i, c.r)
			buffer.writeu8(px, i + 1, c.g)
			buffer.writeu8(px, i + 2, c.b)
		end
	end
end
local function blit(src: buffer, sw: number, sh: number, x: number, y: number, w: number, h: number)
	for yy = 0, h - 1 do
		for xx = 0, w - 1 do
			local si = ((yy * sh // h) * sw + (xx * sw // w)) * 4
			local di = ((y + yy) * W + x + xx) * 3
			buffer.writeu8(px, di, buffer.readu8(src, si))
			buffer.writeu8(px, di + 1, buffer.readu8(src, si + 1))
			buffer.writeu8(px, di + 2, buffer.readu8(src, si + 2))
		end
	end
end
local function text(s: string, x: number, y: number, color: string, scale: number, maxW: number?)
	local k = 0
	for _, code in utf8.codes(s) do
		local cx = x + k * (PixelFont.W + 1) * scale
		if maxW ~= nil and cx + PixelFont.W * scale > x + maxW then
			break
		end
		local g = PixelFont.glyph(utf8.char(code))
		for gy = 1, PixelFont.H do
			for gx = 1, PixelFont.W do
				if string.sub(g[gy], gx, gx) == "#" then
					fill(cx + (gx - 1) * scale, y + (gy - 1) * scale, scale, scale, color)
				end
			end
		end
		k += 1
	end
end
local function frame(x: number, y: number, w: number, h: number, face: string, edge: string)
	fill(x - 2, y - 2, w + 4, h + 4, edge)
	fill(x, y, w, h, face)
end
local function button(label: string, x: number, y: number, w: number, h: number, face: string, ink: string)
	for _, r in PixelSkin.button(w, h, face, "normal") do
		fill(x + r.x, y + r.y, r.w, r.h, r.color)
	end
	text(label, x + 6, y + (h - 14) // 2, ink, 2, w - 10)
end

local function t(key: string): string
	return Strings.get(key, "ru")
end
local function art(key: string, x: number, y: number, w: number, h: number)
	fill(x - 2, y - 2, w + 4, h + 4, "Ink")
	blit(ItemArt.paint(key), ItemArt.W, ItemArt.H, x, y, w, h)
end

fill(0, 0, W, H, "Abyss")

-- Меню порта (CardKit.dock).
do
	local x, y, w = 20, 20, 460
	frame(x, y, w, 200, "Night", "Steel")
	art("naval.port", x + 10, y + 10, 96, 64)
	text(t("naval.title"), x + 118, y + 12, "Gold", 2)
	text("ТРАНСПОРТОВ 2, ЭСМИНЦЕВ 1", x + 118, y + 40, "Mist", 1, w - 180)
	button("x", x + w - 54, y + 10, 44, 44, "Slate", "White")
	for k, kind in { "Transport", "Destroyer" } do
		local tx = x + 10 + (k - 1) * 224
		frame(tx, y + 84, 216, 84, "Ink", "Steel")
		art("naval." .. kind, tx + 6, y + 90, 84, 56)
		text(t("ship." .. kind), tx + 98, y + 92, "White", 2, 112)
		text("$1 200 · НЕФТЬ 40", tx + 98, y + 114, "Gold", 1, 112)
		fill(tx + 140, y + 150, 70, 14, "Gold")
		text("+ НАНЯТЬ", tx + 144, y + 153, "Ink", 1)
	end
	button(string.format(t("naval.land"), 2), x + 10, y + 178 - 6, w - 20, 26, "Gold", "Ink")
end

-- Окно здания (BuildingInfo).
do
	local x, y, w = 520, 20, 420
	frame(x, y, w, 170, "Night", "Steel")
	art("building.Factory", x + 10, y + 10, 120, 80)
	text(t("building.Factory"), x + 142, y + 12, "Gold", 2)
	for k = 1, 5 do
		fill(x + 142 + (k - 1) * 18, y + 38, 14, 14, "Ink")
		fill(x + 144 + (k - 1) * 18, y + 40, 10, 10, if k <= 2 then "Gold" else "Night")
	end
	text(string.format(t("info.level"), 2, 5), x + 236, y + 40, "Mist", 1)
	text("+1 ЗАВОД К НАЙМУ", x + 142, y + 62, "White", 1, w - 150)
	text("РАЙОН ГОРОДА: +20%", x + 10, y + 100, "Sky", 1)
	text("СОДЕРЖАНИЕ: $1.5/С", x + 180, y + 100, "Mist", 1)
	button("УЛУЧШИТЬ ($900)", x + 10, y + 118, 230, 44, "Gold", "Ink")
	button("СНЕСТИ (+$300)", x + 248, y + 118, 162, 44, "Red", "White")
end

-- Условия мира (WarPanel → PeaceTerms).
do
	local x, y = 20, 250
	local w = 3 * 184 + 2 * 10 + 24
	frame(x, y, w, 370, "Night", "Sky")
	art("peace.offer", x + 12, y + 10, 72, 48)
	text("МИР С АВРОРИЕЙ", x + 96, y + 12, "White", 2)
	text(t("peace.pick"), x + 96, y + 40, "Mist", 1)
	button("x", x + w - 56, y + 10, 44, 44, "Slate", "White")
	for k, key in { "white", "keep", "capitulate" } do
		local cx, cy = x + 12 + (k - 1) * 194, y + 72
		frame(cx, cy, 184, 280, "Ink", "Steel")
		local aw = 172
		local ah = aw * ItemArt.H // ItemArt.W
		art("peace." .. key, cx + 6, cy + 6, aw, ah)
		text(t("peace." .. key), cx + 8, cy + ah + 14, "White", 2, 168)
		text(t("peace." .. key .. ".hint"), cx + 8, cy + ah + 40, "Mist", 1, 168)
		button(t("peace.propose"), cx + 8, cy + 228, 168, 44, if key == "capitulate" then "Red" else "Forest", "White")
	end
end

-- Объявление войны (WarPanel → DeclareWar).
do
	local x, y, w = 640, 250, 460
	frame(x, y, w, 250, "Night", "Red")
	text(t("war.declare"), x + w // 2 - 90, y + 12, "Red", 2)
	for k, ci in { 4, 2 } do
		local sx = if k == 1 then x + 35 else x + w - 155
		art("nation." .. ci, sx, y + 44, 120, 80)
		text(if k == 1 then "НОРДЕЯ" else "АВРОРИЯ", sx + 20, y + 132, "White", 2, 120)
		text("СИЛА ≈ 4.2K", sx + 20, y + 156, "Mist", 1)
	end
	text(t("war.vs"), x + w // 2 - 18, y + 74, "Red", 3)
	button(t("war.declare"), x + 12, y + 196, 214, 44, "Red", "White")
	button(t("war.cancel"), x + 234, y + 196, 214, 44, "Slate", "White")
end

-- Итоги: плитки и места.
do
	local x, y = 640, 520
	for k, key in { "results.place", "results.peak", "results.time", "results.out" } do
		local tx = x + (k - 1) * 116
		frame(tx, y, 108, 60, "Ink", "Steel")
		art(key, tx + 4, y + 8, 54, 36)
		text(({ "1 ИЗ 8", "41%", "12:30", "5" })[k], tx + 62, y + 24, "White", 1)
	end
	for place = 1, 3 do
		local py = y + 70 + (place - 1) * 36
		frame(x, py, 456, 32, "Ink", if place == 1 then "Gold" else "Steel")
		art("results.medal" .. place, x + 4, py + 2, 42, 28)
		fill(x + 56, py + 8, 16, 16, "Ink")
		text(({ "НОРДЕЯ", "АВРОРИЯ", "КАЛИСТА" })[place], x + 82, py + 9, "White", 2, 250)
		text(({ "41%", "22%", "13%" })[place], x + 400, py + 9, "Sky", 2)
	end
end

local out = process.args[1] or "build/ui-match-windows.png"
fs.writeFile(out, Png.encodeRgb(W, H, px))
print("→ " .. out)
