--!strict
--[[
	NameGen — выдуманные названия держав для ботов (GDD §4, §9): слоги на русском и английском
	собираются параллельно, поэтому у имени есть обе версии («Валдория» / «Valdoria»).
	Реальные страны исключены: слоги подобраны так, чтобы их не складывать, а на всякий случай
	есть стоп-список (тест прогоняет тысячи имён).
]]

local Rng = require("./Rng")

type Rng = Rng.Rng

export type GeneratedName = { ru: string, en: string }

type Part = { string }

local STARTS: { Part } = {
	{ "Вал", "Val" },
	{ "Бер", "Ber" },
	{ "Дар", "Dar" },
	{ "Зар", "Zar" },
	{ "Кел", "Kel" },
	{ "Лор", "Lor" },
	{ "Мир", "Mir" },
	{ "Нор", "Nor" },
	{ "Ост", "Ost" },
	{ "Рав", "Rav" },
	{ "Сел", "Sel" },
	{ "Тор", "Tor" },
	{ "Фен", "Fen" },
	{ "Хал", "Khal" },
	{ "Вес", "Ves" },
	{ "Гед", "Ged" },
	{ "Иль", "Il" },
	{ "Ямр", "Yamr" },
	{ "Эст", "Est" },
	{ "Ульм", "Ulm" },
}

local MIDDLES: { Part } = {
	{ "", "" },
	{ "а", "a" },
	{ "е", "e" },
	{ "о", "o" },
	{ "ен", "en" },
	{ "ир", "ir" },
	{ "ол", "ol" },
	{ "ад", "ad" },
}

local ENDS: { Part } = {
	{ "ия", "ia" },
	{ "ория", "oria" },
	{ "ана", "ana" },
	{ "ор", "or" },
	{ "ен", "en" },
	{ "ада", "ada" },
	{ "ис", "is" },
	{ "ея", "ea" },
	{ "ум", "um" },
	{ "град", "grad" },
	{ "мар", "mar" },
	{ "ск", "sk" },
}

-- Стоп-список реальных государств (на случай неудачной комбинации слогов). Сравнение точное:
-- string.lower в Luau не меняет регистр кириллицы, поэтому имена записаны с заглавной, как генерируются.
local DENY: { [string]: boolean } = {}
for _, name in
	{
		"Армения",
		"Сербия",
		"Корея",
		"Индия",
		"Нигерия",
		"Ливия",
		"Сирия",
		"Кения",
		"Гана",
		"Оман",
		"Мали",
		"Чад",
		"Перу",
		"Куба",
		"Иран",
		"Ирак",
		"Дания",
		"Латвия",
		"Эстония",
		"Румыния",
		"Болгария",
		"Норвегия",
		"Швеция",
		"Турция",
		"Греция",
		"Тунис",
		"Гамбия",
		"Замбия",
		"Намибия",
		"Боливия",
		"Колумбия",
		"Словения",
		"Хорватия",
		"Мавритания",
		"Монголия",
		"Молдавия",
		"Валахия",
	}
do
	DENY[name] = true
end

local NameGen = {}

local function pick(rng: Rng, list: { Part }): Part
	return list[Rng.range(rng, 1, #list)]
end

-- Похоже ли имя на реальное государство из стоп-списка.
function NameGen.isDenied(ru: string): boolean
	return DENY[ru] == true
end

-- Одно имя. Повторяет попытку, если вышло имя из стоп-списка или уже занятое (taken[ru]).
function NameGen.generate(rng: Rng, taken: { [string]: boolean }?): GeneratedName
	for _ = 1, 64 do
		local a, b, c = pick(rng, STARTS), pick(rng, MIDDLES), pick(rng, ENDS)
		local ru = a[1] .. b[1] .. c[1]
		local en = a[2] .. b[2] .. c[2]
		if not NameGen.isDenied(ru) and not (taken and taken[ru]) then
			return { ru = ru, en = en }
		end
	end
	-- Почти невозможный случай: все попытки заняты — добавляем номер.
	local a = pick(rng, STARTS)
	local n = Rng.range(rng, 2, 99)
	return { ru = a[1] .. "ия-" .. n, en = a[2] .. "ia-" .. n }
end

return table.freeze(NameGen)
