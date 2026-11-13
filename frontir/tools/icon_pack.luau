--!strict
--[[
	Иконки зданий, юнитов (§15ш Ш5) и значки интерфейса (Ш7) без загрузки в Roblox: PNG из
	assets/icons/{buildings,units,ui}/*.png →
	Size×Size пикселей палитры (docs/palette.md) → src/shared/IconData.luau (данные; рисует игра через EditableImage,
	как миниатюры карт). Уменьшение — по квадратам: самый частый цвет палитры среди непрозрачных пикселей квадрата;
	прозрачно, если непрозрачных меньше половины.
	Запуск из frontir/:  lune run tools/icon_pack [размер=64] [превью=build/icons_pack.png]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Palette = require("../src/shared/Palette")
local Png = require("./lib/Png")

local SIZE = tonumber(process.args[1]) or 64
local PREVIEW = process.args[2] or "build/icons_pack.png"
local KEYS = "abcdefghijklmnopqrstuvwxyzABCDEF" -- знак = индекс в Palette.Swatches; «.» — прозрачно

local swatches: { Palette.Rgb } = {}
for k, sw in Palette.Swatches do
	swatches[k] = Palette.rgb(sw.name)
end
-- Ближайший цвет палитры («redmean» — ближе к глазу, чем простое расстояние RGB); кеш по 6 бит на канал.
local cache: { [number]: number } = {}
local function nearest(r: number, g: number, b: number): number
	local key = (r // 4) * 4096 + (g // 4) * 64 + b // 4
	local hit = cache[key]
	if hit then
		return hit
	end
	local best, bestD = 1, math.huge
	for k, c in swatches do
		local rm = (r + c.r) / 2
		local dr, dg, db = r - c.r, g - c.g, b - c.b
		local d = (2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db
		if d < bestD then
			best, bestD = k, d
		end
	end
	cache[key] = best
	return best
end

local function pack(img: Png.Image): { string }
	local rows: { string } = {}
	local bx, by = img.width / SIZE, img.height / SIZE
	for ty = 0, SIZE - 1 do
		local row = table.create(SIZE, ".")
		for tx = 0, SIZE - 1 do
			local x0, x1 = math.floor(tx * bx), math.floor((tx + 1) * bx) - 1
			local y0, y1 = math.floor(ty * by), math.floor((ty + 1) * by) - 1
			local votes: { [number]: number } = {}
			local opaque, total = 0, 0
			for y = y0, y1 do
				for x = x0, x1 do
					local o = (y * img.width + x) * 4
					total += 1
					if buffer.readu8(img.rgba, o + 3) >= 128 then
						opaque += 1
						local k = nearest(
							buffer.readu8(img.rgba, o),
							buffer.readu8(img.rgba, o + 1),
							buffer.readu8(img.rgba, o + 2)
						)
						votes[k] = (votes[k] or 0) + 1
					end
				end
			end
			if opaque * 2 >= total then
				local best, n = 1, -1
				for k, c in votes do
					if c > n or (c == n and k < best) then
						best, n = k, c
					end
				end
				row[tx + 1] = string.sub(KEYS, best, best)
			end
		end
		rows[ty + 1] = table.concat(row)
	end
	return rows
end

local groups = { "buildings", "units", "ui" } -- ui — значки окон, ресурсов, ударов, Арсенала (§15ш Ш7)
local names: { string } = {}
local packed: { [string]: { string } } = {}
for _, group in groups do
	local dir = "assets/icons/" .. group
	local files = fs.readDir(dir)
	table.sort(files)
	for _, file in files do
		local name = string.match(file, "^(.+)%.png$")
		if name ~= nil then
			packed[name] = pack(Png.decode(fs.readFile(dir .. "/" .. file)))
			table.insert(names, name)
			print(group, name)
		end
	end
end

local lines: { string } = {
	"--!strict",
	"--[[",
	"\tIconData — иконки зданий и юнитов (§15ш Ш5). Сделано tools/icon_pack из assets/icons — руками не править.",
	'\tСтрока — ряд сверху вниз, знак — номер цвета в Palette.Swatches (Keys: "a" — 1-й, …), «.» — прозрачно.',
	"]]",
	"",
	"local IconData = {}",
	"",
	string.format("IconData.Size = %d", SIZE),
	string.format('IconData.Keys = "%s"', KEYS),
	"",
	"-- stylua: ignore",
	"IconData.Icons = table.freeze({",
}
for _, name in names do
	table.insert(lines, string.format("\t%s = table.freeze({", name))
	for _, row in packed[name] do
		table.insert(lines, string.format('\t\t"%s",', row))
	end
	table.insert(lines, "\t}),")
end
table.insert(lines, "})")
table.insert(lines, "")
table.insert(lines, "return table.freeze(IconData)")
table.insert(lines, "")
fs.writeFile("src/shared/IconData.luau", table.concat(lines, "\n"))

-- Превью: все иконки ×3 на фоне панели игры (Night).
local cols, scale, pad = 6, 3, 8
local cell = SIZE * scale + pad
local rowsN = math.ceil(#names / cols)
local W, H = cols * cell + pad, rowsN * cell + pad
local pix = buffer.create(W * H * 3)
local bg = Palette.rgb("Night")
for i = 0, W * H - 1 do
	buffer.writeu8(pix, i * 3, bg.r)
	buffer.writeu8(pix, i * 3 + 1, bg.g)
	buffer.writeu8(pix, i * 3 + 2, bg.b)
end
for n, name in names do
	local ox = pad + ((n - 1) % cols) * cell
	local oy = pad + ((n - 1) // cols) * cell
	for y, row in packed[name] do
		for x = 1, SIZE do
			local ch = string.sub(row, x, x)
			if ch ~= "." then
				local c = swatches[string.find(KEYS, ch, 1, true) :: number]
				for sy = 0, scale - 1 do
					for sx = 0, scale - 1 do
						local i = ((oy + (y - 1) * scale + sy) * W + ox + (x - 1) * scale + sx) * 3
						buffer.writeu8(pix, i, c.r)
						buffer.writeu8(pix, i + 1, c.g)
						buffer.writeu8(pix, i + 2, c.b)
					end
				end
			end
		end
	end
end
fs.writeFile(PREVIEW, Png.encodeRgb(W, H, pix))
print(
	string.format("иконок %d, %d×%d → src/shared/IconData.luau, превью %s", #names, SIZE, SIZE, PREVIEW)
)
