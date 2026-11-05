--!strict
--[[
	Shop — каталог магазина (GDD §11.1, этап 9а). Чистый модуль: ключи товаров, поиск по id продукта Roblox,
	перки геймпассов для матча. Цены и эффекты — Config.Shop; начисление — сервер (ProcessReceipt), эффекты в
	матче — MatchSim.useBoost / setPerks.
]]

local Config = require("./Config")

export type PassKey = "HQ" | "Intel" | "Vip" | "AllCommanders"
export type BoostKey = "Mobilize" | "Loan" | "Research" | "Reserve"
export type PackKey = "Recruit" | "Medals" | "Tokens"

-- Перки геймпассов в матче (§11.1).
export type Perks = {
	recruitLines: number, -- + линий найма
	incomeMul: number,
	intelCostMul: number,
	intelDurationSec: number?,
	xpMul: number, -- опыт и медали после матча
}

local Shop = {}

Shop.PassKeys = table.freeze({ "HQ", "Intel", "Vip", "AllCommanders" } :: { PassKey })
Shop.BoostKeys = table.freeze({ "Mobilize", "Loan", "Research", "Reserve" } :: { BoostKey })
Shop.PackKeys = table.freeze({ "Recruit", "Medals", "Tokens" } :: { PackKey })

function Shop.isBoost(key: any): boolean
	return table.find(Shop.BoostKeys, key) ~= nil
end

function Shop.isPass(key: any): boolean
	return table.find(Shop.PassKeys, key) ~= nil
end

-- Продукт разработчика по id Roblox: ("boost" | "pack", ключ) или nil.
function Shop.productById(id: number): (string?, string?)
	if id == 0 then
		return nil, nil
	end
	for key, b in (Config.Shop.Boosts :: any) :: { [string]: { id: number } } do
		if b.id == id then
			return "boost", key
		end
	end
	for key, p in (Config.Shop.Packs :: any) :: { [string]: { id: number } } do
		if p.id == id then
			return "pack", key
		end
	end
	return nil, nil
end

function Shop.noPerks(): Perks
	return { recruitLines = 0, incomeMul = 1, intelCostMul = 1, intelDurationSec = nil, xpMul = 1 }
end

-- Перки по купленным геймпассам.
function Shop.perks(owned: { [string]: boolean }): Perks
	local p = Shop.noPerks()
	local cfg = Config.Shop.Passes
	if owned.HQ then
		p.recruitLines = cfg.HQ.recruitLines
		p.incomeMul = cfg.HQ.incomeMul
	end
	if owned.Intel then
		p.intelCostMul = cfg.Intel.intelCostMul
		p.intelDurationSec = cfg.Intel.intelDurationSec
	end
	if owned.Vip then
		p.xpMul = cfg.Vip.xpMul
	end
	return p
end

return table.freeze(Shop)
