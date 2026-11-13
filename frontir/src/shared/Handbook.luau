--!strict
--[[
	Handbook — справочник механик (§15х ч.5): вкладки и строки-карточки «Что это · Как запустить · Чем защититься».
	§15ц Ц4б: вкладки — три группы ВОЙНА · ДЕРЖАВА · МИР, внутри — разделы (Handbook.Sections).
	Чистые данные: ключ механики (тексты — Strings «handbook.<ключ>.name / what / how / defense»), вкладка и картинка
	(ItemArt: свой ключ или динамический «building.<вид>»). hinder = true — третья строка «Как помешать»
	(ключ «handbook.<ключ>.hinder»): механика своя, от неё не защищаются, а мешают врагу. Окно — UI/HandbookPanel
	(кнопка в «Как играть»).
	Тест Handbook.spec: у каждой строки есть RU/EN и картинка.
]]

local Handbook = {}

-- §15ц Ц4б: tab — группа ВОЙНА · ДЕРЖАВА · МИР (вкладка окна), section — раздел внутри неё (заголовок).
export type Entry = { key: string, tab: string, section: string, art: string, hinder: boolean? }

Handbook.Tabs = table.freeze({ "war", "nation", "peace" })

-- Разделы вкладки по порядку (тексты — Strings «handbook.section.<раздел>»).
Handbook.Sections = table.freeze({
	war = { "army", "strikes", "air" },
	nation = { "build", "order" },
	peace = { "diplo", "world" },
} :: { [string]: { string } })

Handbook.Entries = table.freeze({
	-- ВОЙНА · Войска и фронт
	{ key = "hire", tab = "war", section = "army", art = "shop.Recruit", hinder = true },
	{ key = "front", tab = "war", section = "army", art = "war.declare" },
	{ key = "supply", tab = "war", section = "army", art = "building.City", hinder = true },
	{ key = "pocket", tab = "war", section = "army", art = "arsenal.Convoy" },
	{ key = "giant", tab = "war", section = "army", art = "results.peak" },
	-- ВОЙНА · Удары и защита
	{ key = "missile", tab = "war", section = "strikes", art = "strike.missile" },
	{ key = "nukes", tab = "war", section = "strikes", art = "council.superweaponBan" },
	{ key = "raid", tab = "war", section = "strikes", art = "strike.raid" },
	{ key = "ability", tab = "war", section = "strikes", art = "strike.Airstrike" },
	{ key = "defense", tab = "war", section = "strikes", art = "building.AirDefense", hinder = true },
	{ key = "threat", tab = "war", section = "strikes", art = "shop.Intel" },
	-- ВОЙНА · Флот и авиация
	{ key = "landing", tab = "war", section = "air", art = "naval.land" },
	{ key = "destroyer", tab = "war", section = "air", art = "naval.Destroyer" },
	{ key = "fighter", tab = "war", section = "air", art = "air.Fighter", hinder = true },
	-- ДЕРЖАВА · Стройка и экономика
	{ key = "buildings", tab = "nation", section = "build", art = "building.Factory" },
	{ key = "district", tab = "nation", section = "build", art = "building.Housing", hinder = true },
	{ key = "oil", tab = "nation", section = "build", art = "building.OilRig" },
	{ key = "tech", tab = "nation", section = "build", art = "shop.Research", hinder = true },
	-- ДЕРЖАВА · Стабильность и победа
	{ key = "stability", tab = "nation", section = "order", art = "quest.cities" },
	{ key = "doomsday", tab = "nation", section = "order", art = "results.time" },
	-- МИР · Дипломатия
	{ key = "war", tab = "peace", section = "diplo", art = "peace.offer" },
	{ key = "alliance", tab = "peace", section = "diplo", art = "council.aid" },
	{ key = "passage", tab = "peace", section = "diplo", art = "council.truce" },
	{ key = "council", tab = "peace", section = "diplo", art = "council.sanctions" },
	-- МИР · Торговля и события
	{ key = "trade", tab = "peace", section = "world", art = "naval.port" },
	{ key = "events", tab = "peace", section = "world", art = "shop.Weekly" },
} :: { Entry })

-- Третья строка карточки: «defense» (Чем защититься) или «hinder» (Как помешать).
function Handbook.counter(e: Entry): string
	return if e.hinder then "hinder" else "defense"
end

-- Ключи Strings карточки: название, «что это», «как запустить», третья строка (Handbook.counter).
function Handbook.textKeys(e: Entry): { name: string, what: string, how: string, counter: string }
	local base = "handbook." .. e.key .. "."
	return { name = base .. "name", what = base .. "what", how = base .. "how", counter = base .. Handbook.counter(e) }
end

-- Строки вкладки tab по порядку (разделы — по Handbook.Sections, внутри — как в Entries).
function Handbook.of(tab: string): { Entry }
	local out: { Entry } = {}
	local sections: { string } = Handbook.Sections[tab] or {}
	for _, section in sections do
		for _, e in Handbook.inSection(tab, section) do
			table.insert(out, e)
		end
	end
	return out
end

-- Строки раздела section вкладки tab по порядку.
function Handbook.inSection(tab: string, section: string): { Entry }
	local out: { Entry } = {}
	for _, e in Handbook.Entries do
		if e.tab == tab and e.section == section then
			table.insert(out, e)
		end
	end
	return out
end

return table.freeze(Handbook)
