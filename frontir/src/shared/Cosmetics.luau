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

-- Список предметов вида kind: { id, price?, level? } (без цены и уровня — премиум-дорога «Пути», §15ю).
function Cosmetics.list(kind: Kind): { { id: string, price: number?, level: number? } }
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

function Cosmetics.item(kind: Kind, id: string): { id: string, price: number?, level: number? }?
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

-- Открыт ли предмет: бесплатная часть флага, куплен / забран с «Пути командира» или по уровню.
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
	return false
end

-- §15ю Ю4: где на «Пути командира» лежит предмет: уровень и дорога (премиум ли); нет — nil.
function Cosmetics.pathSource(kind: Kind, id: string): (number?, boolean)
	local key = Cosmetics.key(kind, id)
	for lv, sp in Config.Path.Premium.Specials do
		if sp.cosmetic == key then
			return lv, true
		end
	end
	for lv, ms in Config.Path.Milestones do
		if ms.cosmetic == key then
			return lv, false
		end
	end
	return nil, false
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
	-- §15ю Ю4: эксклюзив премиум-дороги «Пути командира».
	elseif pattern == "Diamonds" then
		return (math.abs(x % 8 - 4) + math.abs(y % 8 - 4)) == 3
	elseif pattern == "Chevron" then
		return (y + math.abs(x % 8 - 4)) % 6 < 2
	elseif pattern == "Camo" then
		return ((x * 7 + (y // 2) * 13) % 11 < 4) and ((x // 3 + y // 3) % 3 ~= 0)
	elseif pattern == "Cross" then
		return (x % 8 == 4 and y % 8 >= 2 and y % 8 <= 6) or (y % 8 == 4 and x % 8 >= 2 and x % 8 <= 6)
	elseif pattern == "Bricks" then
		return y % 4 == 0 or (x + (if (y // 4) % 2 == 0 then 0 else 4)) % 8 == 0
	end
	return false
end

return table.freeze(Cosmetics)
