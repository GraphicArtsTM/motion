--!strict
--[[
	RankArt — гладкие погоны званий (§15ю, картинки геймдизайнера), чистый модуль: есть ли погон звания и его пиксели
	RGBA (W × H, прозрачный фон). Данные — RankData (делает tools/rank_pack из assets/ranks). Клиент —
	UI/IconImage.rank → MenuKit.rankIcon / setRank (без картинки — пиксельный погон Ranks.icon).
]]

local Base64 = require("./Base64")
local RankData = require("./RankData")

local RankArt = {}

RankArt.W = RankData.W
RankArt.H = RankData.H

type Rank = { palette: string, data: string }

function RankArt.has(rank: number): boolean
	return (RankData.Ranks :: { [number]: Rank })[rank] ~= nil
end

-- Пиксели RGBA (строки сверху вниз, индекс 0 — прозрачно); nil — картинки нет.
function RankArt.paint(rank: number): buffer?
	local r = (RankData.Ranks :: { [number]: Rank })[rank]
	if r == nil then
		return nil
	end
	local colors: { { number } } = {}
	for i = 1, #r.palette, 6 do
		local hex = string.sub(r.palette, i, i + 5)
		table.insert(colors, {
			tonumber(string.sub(hex, 1, 2), 16) :: number,
			tonumber(string.sub(hex, 3, 4), 16) :: number,
			tonumber(string.sub(hex, 5, 6), 16) :: number,
		})
	end
	local indices = Base64.decode(r.data)
	local n = RankArt.W * RankArt.H
	local out = buffer.create(n * 4) -- нули: прозрачно
	for i = 0, n - 1 do
		local k = buffer.readu8(indices, i)
		local c = if k > 0 then colors[k] else nil
		if c ~= nil then
			buffer.writeu8(out, i * 4, c[1])
			buffer.writeu8(out, i * 4 + 1, c[2])
			buffer.writeu8(out, i * 4 + 2, c[3])
			buffer.writeu8(out, i * 4 + 3, 255)
		end
	end
	return out
end

return table.freeze(RankArt)
