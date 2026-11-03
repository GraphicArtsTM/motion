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
	["debug.net"] = { ru = "Сеть: %.1f КБ/с", en = "Net: %.1f KB/s" },
	["debug.fronts"] = { ru = "Фронтов: %d, в бою %d", en = "Fronts: %d, fighting %d" },

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
		ru = "Нажмите на ничью землю или страну",
		en = "Tap free land or a nation",
	},
	["hud.neutral"] = { ru = "ничья земля", en = "free land" },
	["hud.leaders"] = { ru = "Лидеры", en = "Leaders" },
	["hud.you"] = { ru = "вы", en = "you" },
	["event.eliminated"] = { ru = "Держава %s пала", en = "%s has fallen" },
	["event.capitalLost"] = { ru = "%s потеряла столицу", en = "%s lost its capital" },

	["unit.Infantry"] = { ru = "Пехота", en = "Infantry" },
	["unit.Tanks"] = { ru = "Танки", en = "Tanks" },
	["unit.Artillery"] = { ru = "Артиллерия", en = "Artillery" },
	["unit.AntiAir"] = { ru = "ПВО", en = "Anti-air" },
	["hire.cost"] = { ru = "%s людей · %d с", en = "%s people · %d s" },
	["forces.title"] = { ru = "Войска", en = "Troops" },
	["forces.total"] = { ru = "Дома %s · на фронтах %s", en = "Home %s · at fronts %s" },
	["forces.kind"] = { ru = "%s: %s · %s", en = "%s: %s · %s" },
	["forces.empty"] = { ru = "Войск нет — наймите (Z/X/C/V)", en = "No troops — recruit (Z/X/C/V)" },
	["forces.queue"] = { ru = "Найм: %s", en = "Recruiting: %s" },
	["forces.queueItem"] = { ru = "%s %d с", en = "%s %d s" },
	["forces.hint"] = { ru = "Z/X/C/V — найм", en = "Z/X/C/V — recruit" },
	["hud.front.power"] = { ru = "сила %s", en = "power %s" },
	["hud.front.people"] = { ru = "%s людей", en = "%s people" },
	["hud.front.ratio"] = { ru = "перевес ×%.1f", en = "odds ×%.1f" },
	["hud.front.open"] = { ru = "без обороны", en = "undefended" },
	["hud.front.stalled"] = { ru = "стоит", en = "stalled" },
	["hud.front.noSupply"] = { ru = "нет снабжения", en = "no supply" },

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
	["reject.noCapital"] = {
		ru = "Нет столицы — нанимать негде",
		en = "No capital to recruit in",
	},
	["reject.noUnits"] = {
		ru = "Нужны войска: наймите юниты (Z/X/C/V)",
		en = "You need troops: recruit units (Z/X/C/V)",
	},
	["reject.queueFull"] = { ru = "Очередь найма полна", en = "Recruitment queue is full" },
	["reject.notAtWar"] = {
		ru = "С этой страной мир — сначала объявите войну",
		en = "You are at peace — declare war first",
	},
	["reject.mobilizing"] = {
		ru = "Идёт мобилизация — бои ещё не начались",
		en = "Mobilization — the fighting has not started yet",
	},
	["reject.alreadyAtWar"] = { ru = "Война уже объявлена", en = "War is already declared" },
	["reject.peaceCooldown"] = {
		ru = "Мир заключён недавно — война пока нельзя",
		en = "Peace was just signed — no war yet",
	},
	["reject.peacePending"] = {
		ru = "Предложение мира уже ждёт ответа",
		en = "A peace offer is already waiting",
	},
	["reject.noProposal"] = { ru = "Предложения мира нет", en = "No peace offer" },
	["reject.needFactory"] = { ru = "Нужен свой завод", en = "You need a factory" },
	["reject.noMoney"] = { ru = "Не хватает денег", en = "Not enough money" },
	["reject.noOil"] = { ru = "Не хватает нефти", en = "Not enough oil" },
	["reject.needCity"] = { ru = "Нажмите на свой город", en = "Tap your own city" },
	["reject.maxLevel"] = {
		ru = "Это уже самый высокий уровень",
		en = "Already at the top level",
	},
	["reject.occupied"] = {
		ru = "В провинции уже есть здание",
		en = "This province already has a building",
	},
	["reject.needOil"] = {
		ru = "Вышку ставят только на нефтяное поле",
		en = "Oil rigs go only on oil fields",
	},
	["reject.notOwner"] = {
		ru = "Центр провинции должен быть вашим",
		en = "The province centre must be yours",
	},
	["reject.notYet"] = {
		ru = "Капитуляция появится вместе с дипломатией",
		en = "Capitulation comes with diplomacy",
	},

	["war.declare"] = { ru = "Объявить войну", en = "Declare war" },
	["war.declare.cooldown"] = { ru = "Мир: ещё %d с", en = "Peace: %d s left" },
	["war.cancel"] = { ru = "Отмена", en = "Cancel" },
	["war.banner"] = { ru = "ВОЙНА: %s — %s", en = "WAR: %s — %s" },
	["war.mobilizing"] = { ru = "МОБИЛИЗАЦИЯ: %s — %s · %d с", en = "MOBILIZATION: %s — %s · %d s" },
	["war.stats"] = { ru = "Земля: %s / %s · Потери: %s / %s", en = "Land: %s / %s · Losses: %s / %s" },
	["war.toFront"] = { ru = "К фронту", en = "To front" },
	["war.peace"] = { ru = "Мир", en = "Peace" },
	["peace.title"] = { ru = "Мир с %s", en = "Peace with %s" },
	["peace.white"] = { ru = "Белый мир", en = "White peace" },
	["peace.white.hint"] = {
		ru = "взятая в войне земля возвращается",
		en = "land taken in the war goes back",
	},
	["peace.keep"] = { ru = "Забрать захваченное", en = "Keep captured land" },
	["peace.keep.hint"] = {
		ru = "каждый оставляет то, что взял",
		en = "each side keeps what it took",
	},
	["peace.capitulate"] = { ru = "Капитуляция", en = "Capitulation" },
	["peace.capitulate.hint"] = { ru = "позже — с дипломатией", en = "later — with diplomacy" },
	["peace.offer"] = { ru = "%s предлагает мир: %s · %d с", en = "%s offers peace: %s · %d s" },
	["peace.accept"] = { ru = "Принять", en = "Accept" },
	["peace.decline"] = { ru = "Отклонить", en = "Decline" },
	["peace.sent"] = { ru = "Предложение мира отправлено", en = "Peace offer sent" },
	["peace.terms.white"] = { ru = "белый мир", en = "white peace" },
	["peace.terms.keep"] = { ru = "забрать захваченное", en = "keep captured land" },
	["peace.terms.capitulate"] = { ru = "капитуляция", en = "capitulation" },
	["event.warDeclared"] = { ru = "%s объявила войну: %s", en = "%s declared war on %s" },
	["event.attacked"] = {
		ru = "На вас напала %s! Мобилизация %d с",
		en = "%s declared war on you! Mobilization %d s",
	},
	["event.warStarted"] = { ru = "Война %s — %s началась", en = "War %s — %s has begun" },
	["event.peace"] = { ru = "Мир: %s — %s (%s)", en = "Peace: %s — %s (%s)" },
	["event.peaceRejected"] = { ru = "%s отклонила мир", en = "%s rejected peace" },
	["event.peaceExpired"] = { ru = "%s не ответила на мир", en = "%s did not answer the peace offer" },
	["hud.money"] = { ru = "Деньги: %s (%s/с)", en = "Money: %s (%s/s)" },
	["hud.oil"] = { ru = "Нефть: %s (%s/с)", en = "Oil: %s (%s/s)" },
	["hire.money"] = { ru = "$%s", en = "$%s" },
	["hire.oil"] = { ru = "%s нефти", en = "%s oil" },
	["hire.needFactory"] = { ru = "нужен завод", en = "needs a factory" },
	["build.button"] = { ru = "Построить (B)", en = "Build (B)" },
	["build.cancel"] = { ru = "Отмена (Esc): %s", en = "Cancel (Esc): %s" },
	["build.pick"] = { ru = "%s: нажмите на свою провинцию", en = "%s: tap your province" },
	["build.pickCity"] = { ru = "%s: нажмите на свой город", en = "%s: tap your city" },
	["building.City"] = { ru = "Город +1 уровень", en = "City +1 level" },
	["building.City.hint"] = { ru = "доход и максимум людей", en = "income and max people" },
	["building.OilRig"] = { ru = "Нефтяная вышка", en = "Oil rig" },
	["building.OilRig.hint"] = { ru = "только на нефтяном поле", en = "oil fields only" },
	["building.Factory"] = { ru = "Завод", en = "Factory" },
	["building.Factory.hint"] = {
		ru = "танки, пушки, ПВО; найм быстрее",
		en = "tanks, guns, AA; faster hiring",
	},
	["building.Fort"] = { ru = "Укрепление", en = "Fortification" },
	["building.Fort.hint"] = { ru = "защита провинции ×1.5", en = "province defence ×1.5" },
	["building.Market"] = { ru = "Рынок", en = "Market" },
	["building.Market.hint"] = { ru = "+5% дохода", en = "+5% income" },
	["event.pocketSurrendered"] = { ru = "Котёл сдался: %s → %s", en = "Pocket surrendered: %s → %s" },
	["hud.weariness"] = {
		ru = "Усталость от войны: −%d%% прироста",
		en = "War weariness: −%d%% growth",
	},

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
