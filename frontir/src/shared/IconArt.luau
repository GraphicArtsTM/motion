--!strict
--[[
	IconArt — иконки зданий и юнитов (§15ш Ш5) и значки интерфейса (Ш7: имена как у PixelIcons), чистый модуль: какой картинке интерфейса (ключ CardKit / ItemArt)
	соответствует иконка и её пиксели RGBA. Данные — IconData (делает tools/icon_pack из assets/icons; цвета —
	палитра docs/palette.md). Клиент рисует через EditableImage (UI/IconImage) — загрузка в Roblox не нужна.
]]

local IconData = require("./IconData")
local Palette = require("./Palette")

local IconArt = {}

IconArt.Size = IconData.Size

-- Ключи картинок интерфейса (ItemArt / CardKit.art) → имя иконки.
local BY_KEY: { [string]: string } = {
	["naval.Transport"] = "Transport",
	["naval.Destroyer"] = "Destroyer",
	["air.Fighter"] = "Fighter",
	["air.Bomber"] = "Bomber",
	-- §15ш Ш7: плитки «УДАРОВ» и карточки Арсенала.
	["strike.missile"] = "missile",
	["strike.raid"] = "raid",
	["strike.Airstrike"] = "ability_airstrike",
	["strike.Surge"] = "ability_surge",
	["strike.SeaLanding"] = "ability_sealanding",
	["strike.Blockade"] = "ability_blockade",
	["strike.Reveal"] = "ability_reveal",
	["strike.Propaganda"] = "ability_propaganda",
	["strike.Fortify"] = "ability_fortify",
	["strike.Airdrop"] = "ability_airdrop",
	["arsenal.Reinforce"] = "reinforce",
	["arsenal.Convoy"] = "convoy",
	["arsenal.Barrage"] = "barrage",
	["arsenal.Jammer"] = "jammer",
}

function IconArt.has(name: string): boolean
	return (IconData.Icons :: { [string]: { string } })[name] ~= nil
end

-- «building.<вид>», «unit.<юнит>», «naval.<корабль>», «air.<самолёт>» → имя иконки (nil — иконки нет).
function IconArt.forKey(key: string): string?
	local name = BY_KEY[key] or string.match(key, "^building%.(%a+)$") or string.match(key, "^unit%.(%a+)$")
	return if name ~= nil and IconArt.has(name) then name else nil
end

-- Пиксели RGBA (Size × Size, строки сверху вниз); nil — иконки нет.
function IconArt.paint(name: string): buffer?
	local rows = (IconData.Icons :: { [string]: { string } })[name]
	if rows == nil then
		return nil
	end
	local n = IconData.Size
	local out = buffer.create(n * n * 4)
	for y, row in rows do
		for x = 1, n do
			local ch = string.sub(row, x, x)
			local k = if ch == "." then nil else string.find(IconData.Keys, ch, 1, true)
			if k ~= nil then
				local c = Palette.rgb(Palette.Swatches[k].name)
				local i = ((y - 1) * n + (x - 1)) * 4
				buffer.writeu8(out, i, c.r)
				buffer.writeu8(out, i + 1, c.g)
				buffer.writeu8(out, i + 2, c.b)
				buffer.writeu8(out, i + 3, 255)
			end
		end
	end
	return out
end

return table.freeze(IconArt)
