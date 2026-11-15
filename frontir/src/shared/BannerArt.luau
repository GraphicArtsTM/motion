--!strict
--[[
	BannerArt — гладкие шапки окон (§15я, картинки геймдизайнера), чистый модуль: есть ли шапка сцены
	(SceneArt-ключ: shop, ranks, victory…) и её пиксели RGBA W × H. Данные — BannerData (tools/card_pack banners из
	assets/banners/banner_<ключ>.png). Клиент — UI/SceneBanner (без шапки — пиксельная сцена SceneArt).
]]

local Base64 = require("./Base64")
local BannerData = require("./BannerData")

local BannerArt = {}

BannerArt.W = BannerData.W
BannerArt.H = BannerData.H

type Banner = { palette: string, data: string }

local function find(key: string): Banner?
	return (BannerData.Cards :: { [string]: Banner })["banner_" .. key]
end

function BannerArt.has(key: string): boolean
	return find(key) ~= nil
end

-- Пиксели RGBA (непрозрачные, строки сверху вниз); nil — шапки нет.
function BannerArt.paint(key: string): buffer?
	local b = find(key)
	if b == nil then
		return nil
	end
	local colors: { { number } } = {}
	for i = 1, #b.palette, 6 do
		local hex = string.sub(b.palette, i, i + 5)
		table.insert(colors, {
			tonumber(string.sub(hex, 1, 2), 16) :: number,
			tonumber(string.sub(hex, 3, 4), 16) :: number,
			tonumber(string.sub(hex, 5, 6), 16) :: number,
		})
	end
	local indices = Base64.decode(b.data)
	local n = BannerArt.W * BannerArt.H
	local out = buffer.create(n * 4)
	for i = 0, n - 1 do
		local c = colors[buffer.readu8(indices, i) + 1] or colors[1]
		buffer.writeu8(out, i * 4, c[1])
		buffer.writeu8(out, i * 4 + 1, c[2])
		buffer.writeu8(out, i * 4 + 2, c[3])
		buffer.writeu8(out, i * 4 + 3, 255)
	end
	return out
end

return table.freeze(BannerArt)
