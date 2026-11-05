--!strict
--[[
	Cosmetics — косметика и флаг державы (GDD §11.4, этап 9в). Чистый модуль: каталог (Config.Cosmetics), что у игрока
	открыто (медали, уровень, премиум-пропуск), покупка за медали, надеть / снять, проверка флага из готовых частей,
	узор территории по клетке, публичный вид державы для info (его видят все). Преимуществ в бою не даёт.
]]

local Config = require("./Config")
local Profile = require("./Profile")

export type Kind = "pattern" | "capture" | "title" | "layout" | "emblem"
export type Flag = { bg: string, layout: string, layoutColor: string, emblem: string, emblemColor: string }
-- Что видят все (в info у державы).
export type Public = { pattern: string?, capture: string?, title: string?, flag: Flag, vip: boolean }

local Cosmetics = {}

Cosmetics.Kinds = table.freeze({ "pattern", "capture", "title", "layout", "emblem" } :: { Kind })

function Cosmetics.defaultFlag(): Flag
	return { bg = "Sky", layout = "Plain", layoutColor = "White", emblem = "Circle", emblemColor = "Gold" }
end

-- Список предметов вида kind: { id, price?, level?, seasonTier? }.
function Cosmetics.list(kind: Kind): { { id: string, price: number?, level: number?, seasonTier: number? } }
	local c = Config.Cosmetics :: any
	if kind == "pattern" then
		return c.Patterns
	elseif kind == "capture" then
		return c.Captures
	elseif kind == "title" then
		return c.Titles
	end
	local parts = if kind == "layout" then c.Flag.Layouts else c.Flag.Emblems
	local out = {}
	for k, id in parts do
		table.insert(out, { id = id, price = if k <= c.Flag.FreeParts then nil else c.Flag.PartPrice })
	end
	return out
end

function Cosmetics.item(kind: Kind, id: string): { id: string, price: number?, level: number?, seasonTier: number? }?
	for _, it in Cosmetics.list(kind) do
		if it.id == id then
			return it
		end
	end
	return nil
end

function Cosmetics.key(kind: Kind, id: string): string
	return kind .. ":" .. id
end

-- Открыт ли предмет: бесплатная часть флага, куплен, уровень или 30-я ступень премиум-пропуска.
function Cosmetics.owns(d: Profile.Data, kind: Kind, id: string): boolean
	local it = Cosmetics.item(kind, id)
	if it == nil then
		return false
	end
	if (kind == "layout" or kind == "emblem") and it.price == nil then
		return true
	end
	if d.cosmetics[Cosmetics.key(kind, id)] then
		return true
	end
	if it.level ~= nil and (Profile.levelOf(d.xp)) >= it.level then
		return true
	end
	if it.seasonTier ~= nil and d.seasonPremium and Profile.seasonTier(d) >= it.seasonTier then
		return true
	end
	return false
end

-- Купить за медали (§11.4).
function Cosmetics.buy(d: Profile.Data, kind: Kind, id: string): (boolean, string?)
	local it = Cosmetics.item(kind, id)
	if it == nil or it.price == nil then
		return false, "target"
	end
	if Cosmetics.owns(d, kind, id) then
		return false, "already"
	end
	if d.medals < it.price then
		return false, "noMedals"
	end
	d.medals -= it.price
	d.cosmetics[Cosmetics.key(kind, id)] = true
	return true, nil
end

-- Надеть (id nil — снять) узор, вспышку или титул.
function Cosmetics.equip(d: Profile.Data, kind: Kind, id: string?): (boolean, string?)
	if kind ~= "pattern" and kind ~= "capture" and kind ~= "title" then
		return false, "target"
	end
	if id ~= nil and not Cosmetics.owns(d, kind, id) then
		return false, "locked"
	end
	(d.equipped :: any)[kind] = id -- nil — снять
	return true, nil
end

-- Флаг из готовых частей: цвета — из списка, раскладка и эмблема — открытые.
function Cosmetics.setFlag(d: Profile.Data, flag: any): (boolean, string?)
	if type(flag) ~= "table" then
		return false, "target"
	end
	local colors = Config.Cosmetics.Flag.Colors
	for _, field in { "bg", "layoutColor", "emblemColor" } do
		if table.find(colors, flag[field]) == nil then
			return false, "target"
		end
	end
	if type(flag.layout) ~= "string" or type(flag.emblem) ~= "string" then
		return false, "target"
	end
	if not Cosmetics.owns(d, "layout", flag.layout) or not Cosmetics.owns(d, "emblem", flag.emblem) then
		return false, "locked"
	end
	d.flag = {
		bg = flag.bg,
		layout = flag.layout,
		layoutColor = flag.layoutColor,
		emblem = flag.emblem,
		emblemColor = flag.emblemColor,
	}
	return true, nil
end

-- Публичный вид (надетое, но только если всё ещё открыто).
function Cosmetics.public(d: Profile.Data, vip: boolean): Public
	local function worn(kind: Kind): string?
		local id = d.equipped[kind]
		return if id ~= nil and Cosmetics.owns(d, kind, id) then id else nil
	end
	local flag = d.flag or Cosmetics.defaultFlag()
	return { pattern = worn("pattern"), capture = worn("capture"), title = worn("title"), flag = flag, vip = vip }
end

-- Узор территории: попадает ли клетка (x, y) в рисунок.
function Cosmetics.patternHit(pattern: string, x: number, y: number): boolean
	if pattern == "Stripes" then
		return (x + y) % 6 < 2
	elseif pattern == "Checker" then
		return (x // 4 + y // 4) % 2 == 0
	elseif pattern == "Dots" then
		return x % 5 == 2 and y % 5 == 2
	elseif pattern == "Grid" then
		return x % 8 == 0 or y % 8 == 0
	elseif pattern == "Waves" then
		return (x + (y // 3) % 4) % 7 < 2
	end
	return false
end

return table.freeze(Cosmetics)
