--!strict
--[[
	Strings — все тексты интерфейса по ключам (RU/EN), §10 «Локализация».
	Пока это чистая таблица; позже из неё будет собираться LocalizationTable.
	Никаких строк интерфейса хардкодом в UI — только Strings.get(key, lang).
]]

export type Lang = "ru" | "en"

local Strings = {}

Strings.DefaultLang = "ru" :: Lang
Strings.Langs = table.freeze({ "ru", "en" }) :: { Lang }

Strings.Table = table.freeze({
	["game.title"] = table.freeze({ ru = "Фронтир", en = "Frontir" }),
	["boot.stage"] = table.freeze({ ru = "Каркас готов (этап 0)", en = "Skeleton ready (stage 0)" }),
	["boot.hint"] = table.freeze({
		ru = "Карта появится на этапе 1",
		en = "The map arrives in stage 1",
	}),
}) :: { [string]: { [Lang]: string } }

-- Приводит код локали Roblox ("ru-ru", "en-us") к поддерживаемому языку.
function Strings.langFromLocale(localeId: string): Lang
	local prefix = string.lower(string.sub(localeId, 1, 2))
	if prefix == "ru" then
		return "ru"
	end
	return "en"
end

-- Возвращает строку по ключу; если перевода нет — русскую; если ключа нет — сам ключ.
function Strings.get(key: string, lang: Lang?): string
	local entry = Strings.Table[key]
	if entry == nil then
		return key
	end
	return entry[lang or Strings.DefaultLang] or entry[Strings.DefaultLang] or key
end

return table.freeze(Strings)
