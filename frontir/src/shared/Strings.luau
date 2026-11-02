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
	["map.Pangea"] = { ru = "Пангея", en = "Pangaea" },

	["terrain.Water"] = { ru = "вода", en = "water" },
	["terrain.Plains"] = { ru = "равнина", en = "plains" },
	["terrain.Forest"] = { ru = "лес", en = "forest" },
	["terrain.Hills"] = { ru = "холмы", en = "hills" },
	["terrain.Mountains"] = { ru = "горы", en = "mountains" },
	["terrain.Desert"] = { ru = "пустыня", en = "desert" },
	["terrain.Tundra"] = { ru = "тундра", en = "tundra" },
	["terrain.River"] = { ru = "река", en = "river" },

	["debug.title"] = { ru = "Отладка (F3)", en = "Debug (F3)" },
	["debug.fps"] = { ru = "FPS: %d", en = "FPS: %d" },
	["debug.map"] = { ru = "Карта: %s %d×%d, сид %d", en = "Map: %s %d×%d, seed %d" },
	["debug.zoom"] = { ru = "Зум: ×%d", en = "Zoom: ×%d" },
	["debug.camera"] = { ru = "Камера: %.1f, %.1f", en = "Camera: %.1f, %.1f" },
	["debug.cell"] = { ru = "Клетка: %d, %d — %s", en = "Cell: %d, %d — %s" },
	["debug.cell.none"] = { ru = "Клетка: —", en = "Cell: —" },
	["debug.memory"] = { ru = "EditableImage: чанков %d, %.2f МБ", en = "EditableImage: %d chunks, %.2f MB" },

	["error.editable.disabled"] = {
		ru = "Не удалось создать EditableImage. В опубликованной игре включите Allow Mesh / Image APIs (Experience Settings → Security).",
		en = "Could not create EditableImage. For a published game enable Allow Mesh / Image APIs (Experience Settings → Security).",
	},
	["error.editable.budget"] = {
		ru = "Не хватает памяти устройства, чтобы показать карту (лимит EditableImage).",
		en = "Not enough device memory to show the map (EditableImage budget).",
	},
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
