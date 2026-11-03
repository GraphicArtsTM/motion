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
	["debug.zoom"] = { ru = "Зум: ×%.2f (мин. ×%.2f)", en = "Zoom: ×%.2f (min ×%.2f)" },
	["debug.camera"] = { ru = "Камера: %.1f, %.1f", en = "Camera: %.1f, %.1f" },
	["debug.cell"] = { ru = "Клетка: %d, %d — %s", en = "Cell: %d, %d — %s" },
	["debug.cell.none"] = { ru = "Клетка: —", en = "Cell: —" },
	["debug.memory"] = { ru = "EditableImage: чанков %d, %.2f МБ", en = "EditableImage: %d chunks, %.2f MB" },

	["debug.server"] = {
		ru = "Сервер: тик %.2f мс, клеток за тик %d",
		en = "Server: tick %.2f ms, cells/tick %d",
	},
	["debug.ping"] = { ru = "Пинг: %d мс", en = "Ping: %d ms" },

	["hud.waiting"] = { ru = "Ожидание игроков…", en = "Waiting for players…" },
	["hud.pick"] = { ru = "Выберите точку старта: %d с", en = "Choose your start: %d s" },
	["hud.pick.hint"] = { ru = "Нажмите на свободную сушу", en = "Tap free land" },
	["hud.pick.done"] = {
		ru = "Точка выбрана — можно перевыбрать",
		en = "Start chosen — you can change it",
	},
	["hud.spectator"] = {
		ru = "Матч уже идёт — вы зритель",
		en = "Match in progress — you are spectating",
	},
	["hud.defeated"] = {
		ru = "Ваша держава пала — вы зритель",
		en = "Your nation has fallen — spectating",
	},
	["hud.time"] = { ru = "%d:%02d", en = "%d:%02d" },
	["hud.people"] = { ru = "Люди: %s / %s", en = "People: %s / %s" },
	["hud.growth"] = { ru = "Прирост: %s/с", en = "Growth: %s/s" },
	["hud.land"] = { ru = "Суша: %s%%", en = "Land: %s%%" },
	["hud.troops"] = { ru = "В атаках: %s", en = "Attacking: %s" },
	["hud.attack"] = { ru = "Атака %d%%", en = "Attack %d%%" },
	["hud.attack.hint"] = {
		ru = "Нажмите на соседа или ничью землю",
		en = "Tap a neighbour or free land",
	},
	["hud.neutral"] = { ru = "ничья земля", en = "free land" },
	["hud.leaders"] = { ru = "Лидеры", en = "Leaders" },
	["hud.you"] = { ru = "вы", en = "you" },
	["event.eliminated"] = { ru = "Держава %s пала", en = "%s has fallen" },
	["event.capitalLost"] = { ru = "%s потеряла столицу", en = "%s lost its capital" },

	["unit.Infantry"] = { ru = "Пехота", en = "Infantry" },
	["unit.Tanks"] = { ru = "Танки", en = "Tanks" },
	["unit.Artillery"] = { ru = "Артиллерия", en = "Artillery" },
	["hire.cost"] = { ru = "%s людей · %d с", en = "%s people · %d s" },
	["army.state.recruit"] = { ru = "Найм %d%%", en = "Recruiting %d%%" },
	["army.state.idle"] = { ru = "Стоит", en = "Holding" },
	["army.state.move"] = { ru = "Марш", en = "Marching" },
	["army.state.capture"] = { ru = "Захват %d%%", en = "Capturing %d%%" },
	["army.strength"] = { ru = "Сила: %s / %s", en = "Strength: %s / %s" },
	["army.auto.on"] = { ru = "Авто: вкл", en = "Auto: on" },
	["army.auto.off"] = { ru = "Авто: выкл", en = "Auto: off" },
	["army.selected"] = { ru = "Выбрано армий: %d", en = "Armies selected: %d" },
	["army.hint"] = {
		ru = "Нажмите на карту — армия пойдёт туда",
		en = "Tap the map to send the army",
	},
	["army.stop"] = { ru = "Стоп", en = "Stop" },
	["army.auto"] = { ru = "Авто", en = "Auto" },
	["army.deselect"] = { ru = "Снять", en = "Deselect" },
	["debug.armies"] = { ru = "Армий на карте: %d", en = "Armies on map: %d" },

	["reject.TooClose"] = {
		ru = "Слишком близко к другой державе",
		en = "Too close to another nation",
	},
	["reject.NotLand"] = {
		ru = "Здесь нельзя: нужна свободная суша",
		en = "Not here: pick free land",
	},
	["reject.TooSmall"] = { ru = "Слишком мало суши вокруг", en = "Not enough land around" },
	["reject.OutOfMap"] = { ru = "Вне карты", en = "Outside the map" },
	["reject.notAdjacent"] = {
		ru = "Нет общей границы с целью",
		en = "No shared border with the target",
	},
	["reject.tooMany"] = { ru = "Слишком много атак сразу", en = "Too many attacks at once" },
	["reject.noTroops"] = { ru = "Не хватает людей", en = "Not enough people" },
	["reject.phase"] = { ru = "Сейчас нельзя", en = "Not now" },
	["reject.dead"] = { ru = "Ваша держава пала", en = "Your nation has fallen" },
	["reject.self"] = { ru = "Это ваша земля", en = "This is your land" },
	["reject.target"] = { ru = "Такой державы нет", en = "No such nation" },
	["reject.focus"] = { ru = "Неверная точка", en = "Invalid point" },
	["reject.noAttack"] = { ru = "Такой атаки нет", en = "No such attack" },
	["reject.noNation"] = { ru = "У вас нет державы", en = "You have no nation" },
	["reject.tooManyArmies"] = { ru = "Слишком много армий", en = "Too many armies" },
	["reject.noCapital"] = {
		ru = "Нет столицы — нанимать негде",
		en = "No capital to recruit in",
	},
	["reject.noArmy"] = { ru = "Армия не выбрана", en = "No army selected" },
	["reject.noPath"] = { ru = "Туда не пройти", en = "No path there" },

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

-- Целое с разделителем тысяч (узкий неразрывный пробел): 1234567 → «1 234 567».
local function formatInt(n: number): string
	local negative = n < 0
	local digits = tostring(math.floor(math.abs(n) + 0.5))
	local groups: { string } = {}
	while #digits > 3 do
		table.insert(groups, 1, string.sub(digits, -3))
		digits = string.sub(digits, 1, -4)
	end
	table.insert(groups, 1, digits)
	return (if negative then "-" else "") .. table.concat(groups, "\u{202F}")
end

export type StringsModule = {
	DefaultLang: Lang,
	Langs: { Lang },
	Table: { [string]: Entry },
	pick: (entry: Entry, lang: Lang) -> string,
	langFromLocale: (localeId: string) -> Lang,
	get: (key: string, lang: Lang?) -> string,
	formatInt: (n: number) -> string,
}

local Strings: StringsModule = {
	DefaultLang = DEFAULT_LANG,
	Langs = table.freeze(LANGS),
	Table = table.freeze(TABLE),
	pick = pick,
	langFromLocale = langFromLocale,
	get = get,
	formatInt = formatInt,
}

return table.freeze(Strings)
