--!strict
--[[
	Strings — все тексты интерфейса по ключам (RU/EN), §10 «Локализация».
	Пока это чистая таблица; позже из неё будет собираться LocalizationTable.
	Никаких строк интерфейса хардкодом в UI — только Strings.get(key, lang).
]]

export type Lang = "ru" | "en"

-- Каждая запись обязана иметь оба языка: пропуск перевода — ошибка типов.
export type Entry = { ru: string, en: string }

local DEFAULT_LANG: Lang = "ru"
local LANGS: { Lang } = { "ru", "en" }

local TABLE: { [string]: Entry } = {
	["game.title"] = { ru = "Фронтир", en = "Frontir" },
	["boot.stage"] = { ru = "Каркас готов (этап 0)", en = "Skeleton ready (stage 0)" },
	["boot.hint"] = { ru = "Карта появится на этапе 1", en = "The map arrives in stage 1" },
}

-- Перевод записи на язык.
local function pick(entry: Entry, lang: Lang): string
	if lang == "en" then
		return entry.en
	end
	return entry.ru
end

-- Приводит код локали Roblox ("ru-ru", "en-us") к поддерживаемому языку.
local function langFromLocale(localeId: string): Lang
	local prefix = string.lower(string.sub(localeId, 1, 2))
	if prefix == "ru" then
		return "ru"
	end
	return "en"
end

-- Возвращает строку по ключу; пустой перевод заменяется русским; нет ключа — сам ключ.
local function get(key: string, lang: Lang?): string
	local entry = TABLE[key]
	if entry == nil then
		return key
	end
	local text = pick(entry, lang or DEFAULT_LANG)
	if text == "" then
		return pick(entry, DEFAULT_LANG)
	end
	return text
end

for _, entry in TABLE do
	table.freeze(entry)
end

export type StringsModule = {
	DefaultLang: Lang,
	Langs: { Lang },
	Table: { [string]: Entry },
	pick: (entry: Entry, lang: Lang) -> string,
	langFromLocale: (localeId: string) -> Lang,
	get: (key: string, lang: Lang?) -> string,
}

local Strings: StringsModule = {
	DefaultLang = DEFAULT_LANG,
	Langs = table.freeze(LANGS),
	Table = table.freeze(TABLE),
	pick = pick,
	langFromLocale = langFromLocale,
	get = get,
}

return table.freeze(Strings)
