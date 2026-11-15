--!strict
--[[
	CardData — гладкие карточки (§15ш Ш8, §15я). Сделано tools/card_pack из assets/cards — руками не править.
	palette — цвета подряд по 6 hex-знаков; data — base64 индексов (байт на пиксель, строки сверху вниз).
	Карточки лежат частями (CardData1…N), здесь — сборка.
]]

local CardData = {}

CardData.W = 144
CardData.H = 96

local cards: { [string]: { palette: string, data: string } } = {}
for _, part in
	{
		require("./CardData1"),
		require("./CardData2"),
		require("./CardData3"),
		require("./CardData4"),
		require("./CardData5"),
		require("./CardData6"),
		require("./CardData7"),
	} :: { { [string]: { palette: string, data: string } } }
do
	for name, card in part do
		cards[name] = card
	end
end
CardData.Cards = table.freeze(cards)

return table.freeze(CardData)
