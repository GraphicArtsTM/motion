--!strict
--[[
	CardArt — карточки ударов (§15ш Ш8) и товаров (§15я), чистый модуль: какой картинке интерфейса («strike.*», «shop.*», «unlock.*») соответствует
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
	-- §15я: магазин и «Путь командира» (промпты — docs/ART_PROMPTS_SHOP.md); нет картинки — пиксели ItemArt.
	["shop.PathPremium"] = "shop_pathpremium",
	["shop.PathPremiumPlus"] = "shop_pathpremiumplus",
	["unlock.Tanks"] = "unlock_tanks",
	["unlock.Intel"] = "pass_intel", -- §15э Э1б: пока картинка «Разведуправления»
	["unlock.Artillery"] = "unlock_artillery",
	["unlock.AntiAir"] = "unlock_antiair",
	["unlock.Missile"] = "unlock_missile",
	["unlock.All"] = "unlock_all",
	["shop.Weekly"] = "shop_weekly",
	["shop.XpBoost1"] = "shop_xpboost",
	["shop.XpBoost7"] = "shop_xpboost",
	["shop.ParadeSet"] = "shop_paradeset",
	["shop.Crates"] = "shop_crates",
	["shop.Crate1"] = "shop_crates",
	["shop.Crate5"] = "shop_crates",
	["shop.Recruit"] = "shop_recruit",
	["shop.Levels5"] = "shop_levels",
	["shop.Medals"] = "shop_medals",
	["shop.Tokens"] = "shop_tokens",
	["shop.HQ"] = "pass_hq",
	["shop.Intel"] = "pass_intel",
	["shop.Vip"] = "pass_vip",
	["shop.AllCommanders"] = "pass_allcommanders",
	["shop.Mobilize"] = "boost_mobilize",
	["shop.Loan"] = "boost_loan",
	["shop.Research"] = "boost_research",
	["shop.Reserve"] = "boost_reserve",
	["shop.Guards"] = "boost_guards",
	["shop.Airstrike"] = "ability_airstrike", -- уже есть
	["shop.Squadron"] = "boost_squadron",
	["shop.AirWing"] = "boost_airwing",
}

type Card = { palette: string, data: string }

-- Имя по умолчанию: ключ с «_» вместо точки, строчными («tech.Army1» → «tech_army1»; docs/ART_PROMPTS_UI.md).
local function defaultName(key: string): string
	return string.lower((string.gsub(key, "%.", "_")))
end

-- Ключ картинки интерфейса → имя карточки (nil — карточки нет).
function CardArt.forKey(key: string): string?
	local cards = CardData.Cards :: { [string]: Card }
	local name = BY_KEY[key]
	if name ~= nil then
		return if cards[name] ~= nil then name else nil
	end
	local fallback = defaultName(key)
	return if cards[fallback] ~= nil then fallback else nil
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
