--!strict
--[[
	MapArtData — картинки на карте: города и корабли (GDD §15ы Ы4). Сделано tools/map_art_pack из assets/icons —
	руками не править. w × h — размер; palette — цвета по 6 hex-знаков; data — base64 индексов (байт на пиксель,
	строки сверху вниз); alpha — base64 прозрачности (байт на пиксель). Картинки лежат частями, здесь — сборка.
]]

export type Art = { w: number, h: number, palette: string, data: string, alpha: string }

local arts: { [string]: Art } = {}
for _, part in
	{
		require("./MapArtData1"),
		require("./MapArtData2"),
		require("./MapArtData3"),
	} :: { { [string]: Art } }
do
	for name, art in part do
		arts[name] = art
	end
end

return table.freeze({ Arts = table.freeze(arts) })
