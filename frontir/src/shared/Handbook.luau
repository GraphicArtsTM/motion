--!strict
--[[
	Handbook — справочник механик (§15х ч.5): вкладки и строки-карточки «Что это · Как запустить · Чем защититься».
	Чистые данные: ключ механики (тексты — Strings «handbook.<ключ>.name / what / how / defense»), вкладка и картинка
	(ItemArt: свой ключ или динамический «building.<вид>»). Окно — UI/HandbookPanel (кнопка в «Как играть»).
	Тест Handbook.spec: у каждой строки есть RU/EN и картинка.
]]

local Handbook = {}

export type Entry = { key: string, tab: string, art: string }

Handbook.Tabs = table.freeze({ "strikes", "army", "build", "air", "diplo", "world" })

Handbook.Entries = table.freeze({
	-- Удары и защита
	{ key = "missile", tab = "strikes", art = "strike.missile" },
	{ key = "nukes", tab = "strikes", art = "council.superweaponBan" },
	{ key = "raid", tab = "strikes", art = "strike.raid" },
	{ key = "ability", tab = "strikes", art = "strike.Airstrike" },
	{ key = "defense", tab = "strikes", art = "building.AirDefense" },
	{ key = "threat", tab = "strikes", art = "shop.Intel" },
	-- Войска и фронт
	{ key = "hire", tab = "army", art = "shop.Recruit" },
	{ key = "front", tab = "army", art = "war.declare" },
	{ key = "supply", tab = "army", art = "building.City" },
	{ key = "pocket", tab = "army", art = "arsenal.Convoy" },
	{ key = "giant", tab = "army", art = "results.peak" },
	-- Стройка и экономика
	{ key = "buildings", tab = "build", art = "building.Factory" },
	{ key = "district", tab = "build", art = "building.Housing" },
	{ key = "oil", tab = "build", art = "building.OilRig" },
	{ key = "tech", tab = "build", art = "shop.Research" },
	-- Флот и авиация
	{ key = "landing", tab = "air", art = "naval.land" },
	{ key = "destroyer", tab = "air", art = "naval.Destroyer" },
	{ key = "fighter", tab = "air", art = "air.Fighter" },
	{ key = "trade", tab = "air", art = "naval.port" },
	-- Дипломатия
	{ key = "war", tab = "diplo", art = "peace.offer" },
	{ key = "alliance", tab = "diplo", art = "council.aid" },
	{ key = "passage", tab = "diplo", art = "council.truce" },
	{ key = "council", tab = "diplo", art = "council.sanctions" },
	-- Мир и события
	{ key = "stability", tab = "world", art = "quest.cities" },
	{ key = "events", tab = "world", art = "shop.Weekly" },
	{ key = "doomsday", tab = "world", art = "results.time" },
} :: { Entry })

-- Строки вкладки tab по порядку.
function Handbook.of(tab: string): { Entry }
	local out: { Entry } = {}
	for _, e in Handbook.Entries do
		if e.tab == tab then
			table.insert(out, e)
		end
	end
	return out
end

return table.freeze(Handbook)
