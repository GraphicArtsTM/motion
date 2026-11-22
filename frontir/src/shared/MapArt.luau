--!strict
--[[
	MapArt — гладкие картинки на карте (GDD §15ы Ы4): города и корабли, без Roblox API. Данные — MapArtData (делает
	tools/map_art_pack из assets/icons: обрезка пустых полей, плавное уменьшение, тёмный контур, своя палитра и
	прозрачность). Нет картинки — UI берёт прежнюю иконку IconArt (пиксели палитры). Клиент — UI/IconImage.mapArt.
]]

local Base64 = require("./Base64")
local MapArtData = require("./MapArtData")

type Art = MapArtData.Art

local MapArt = {}

function MapArt.has(name: string): boolean
	return MapArtData.Arts[name] ~= nil
end

-- Размер картинки (w, h); 0, 0 — нет картинки.
function MapArt.size(name: string): (number, number)
	local art = MapArtData.Arts[name]
	if art == nil then
		return 0, 0
	end
	return art.w, art.h
end

-- Пиксели RGBA (w × h, строки сверху вниз); mirror — отразить по горизонтали. nil — картинки нет.
function MapArt.paint(name: string, mirror: boolean?): buffer?
	local art = MapArtData.Arts[name]
	if art == nil then
		return nil
	end
	local colors: { number } = {}
	for i = 1, #art.palette, 6 do
		local hex = string.sub(art.palette, i, i + 5)
		local v = tonumber(hex, 16) :: number
		table.insert(colors, v)
	end
	local indices = Base64.decode(art.data)
	local alpha = Base64.decode(art.alpha)
	local w, h = art.w, art.h
	local out = buffer.create(w * h * 4)
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local src = y * w + (if mirror then w - 1 - x else x)
			local c = colors[buffer.readu8(indices, src) + 1] or 0
			local o = (y * w + x) * 4
			buffer.writeu8(out, o, bit32.rshift(c, 16))
			buffer.writeu8(out, o + 1, bit32.band(bit32.rshift(c, 8), 255))
			buffer.writeu8(out, o + 2, bit32.band(c, 255))
			buffer.writeu8(out, o + 3, buffer.readu8(alpha, src))
		end
	end
	return out
end

return table.freeze(MapArt)
