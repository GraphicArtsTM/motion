--!strict
--[[
	BannerData — гладкие картинки (§15ш Ш8, §15я). Сделано tools/card_pack из assets/banners — руками не править.
	palette — цвета подряд по 6 hex-знаков; data — base64 индексов (байт на пиксель, строки сверху вниз).
	Картинки лежат частями (BannerData1…N), здесь — сборка.
]]

local BannerData = {}

BannerData.W = 512
BannerData.H = 64

local cards: { [string]: { palette: string, data: string } } = {}
for _, part in
	{
		require("./BannerData1"),
		require("./BannerData2"),
		require("./BannerData3"),
		require("./BannerData4"),
		require("./BannerData5"),
	} :: { { [string]: { palette: string, data: string } } }
do
	for name, card in part do
		cards[name] = card
	end
end
BannerData.Cards = table.freeze(cards)

return table.freeze(BannerData)
