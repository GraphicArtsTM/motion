--!strict
--[[
	Arsenal — особое оружие игрока (GDD §15л ч.6), чистые правила профиля: что открыто навсегда (`owned`), что взято
	в бой (`loadout`, одно), покупка за медали от уровня. Эффект в матче — MatchSim.useArsenal.
]]

local Config = require("./Config")

export type Data = { arsenal: { [string]: boolean }, loadout: string?, medals: number }

local Arsenal = {}

function Arsenal.isItem(key: any): boolean
	return type(key) == "string" and Config.Arsenal.Items[key] ~= nil
end

function Arsenal.item(key: string): { [string]: any }?
	return Config.Arsenal.Items[key]
end

-- Можно ли купить: предмет есть, ещё не открыт, уровень и медали хватает.
function Arsenal.canBuy(d: Data, key: any, level: number): (boolean, string?)
	if not Arsenal.isItem(key) then
		return false, "target"
	end
	local it = Config.Arsenal.Items[key]
	if d.arsenal[key] then
		return false, "owned"
	end
	if level < it.level then
		return false, "level"
	end
	if d.medals < it.price then
		return false, "medals"
	end
	return true, nil
end

-- Купить: медали списываются, предмет открыт навсегда; первый купленный сразу берётся в бой.
function Arsenal.buy(d: Data, key: any, level: number): (boolean, string?)
	local ok, why = Arsenal.canBuy(d, key, level)
	if not ok then
		return false, why
	end
	local it = Config.Arsenal.Items[key]
	d.medals -= it.price
	d.arsenal[key] = true
	if d.loadout == nil then
		d.loadout = key
	end
	return true, nil
end

-- Взять в бой (nil — ничего не брать). Только открытое.
function Arsenal.equip(d: Data, key: any): (boolean, string?)
	if key == nil then
		d.loadout = nil
		return true, nil
	end
	if not Arsenal.isItem(key) or not d.arsenal[key] then
		return false, "target"
	end
	d.loadout = key
	return true, nil
end

-- Из сырой записи DataStore: только известные предметы; взятое в бой — только открытое.
function Arsenal.migrate(rawOwned: any, rawLoadout: any): ({ [string]: boolean }, string?)
	local owned: { [string]: boolean } = {}
	if type(rawOwned) == "table" then
		for _, key in Config.Arsenal.Order do
			if rawOwned[key] == true then
				owned[key] = true
			end
		end
	end
	local loadout = if type(rawLoadout) == "string" and owned[rawLoadout] then rawLoadout else nil
	return owned, loadout
end

return table.freeze(Arsenal)
