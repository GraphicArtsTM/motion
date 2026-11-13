--!strict
--[[
	CardArt — карточки ударов (§15ш Ш8), чистый модуль: какой картинке интерфейса («strike.<удар>») соответствует
	карточка и её пиксели RGBA. Данные — CardData (делает tools/card_pack из assets/cards; полный цвет, у каждой
	карточки своя палитра — исключение из «только палитра», решение геймдизайнера). Клиент — UI/IconImage.card.
]]

local Base64 = require("./Base64")
local CardData = require("./CardData")

local CardArt = {}

CardArt.W = CardData.W
CardArt.H = CardData.H

local BY_KEY: { [string]: string } = {
	["strike.missile"] = "strike_missile",
	["strike.raid"] = "strike_raid",
	["strike.Airstrike"] = "ability_airstrike",
	["strike.Surge"] = "ability_surge",
	["strike.SeaLanding"] = "ability_sealanding",
	["strike.Blockade"] = "ability_blockade",
	["strike.Reveal"] = "ability_reveal",
	["strike.Propaganda"] = "ability_propaganda",
	["strike.Fortify"] = "ability_fortify",
	["strike.Airdrop"] = "ability_airdrop",
}

type Card = { palette: string, data: string }

-- Ключ картинки интерфейса → имя карточки (nil — карточки нет).
function CardArt.forKey(key: string): string?
	local name = BY_KEY[key]
	return if name ~= nil and (CardData.Cards :: { [string]: Card })[name] ~= nil then name else nil
end

-- Пиксели RGBA (W × H, строки сверху вниз, непрозрачные); nil — карточки нет.
function CardArt.paint(name: string): buffer?
	local card = (CardData.Cards :: { [string]: Card })[name]
	if card == nil then
		return nil
	end
	local colors: { { number } } = {}
	for i = 1, #card.palette, 6 do
		local hex = string.sub(card.palette, i, i + 5)
		table.insert(colors, {
			tonumber(string.sub(hex, 1, 2), 16) :: number,
			tonumber(string.sub(hex, 3, 4), 16) :: number,
			tonumber(string.sub(hex, 5, 6), 16) :: number,
		})
	end
	local indices = Base64.decode(card.data)
	local n = CardData.W * CardData.H
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

return table.freeze(CardArt)
