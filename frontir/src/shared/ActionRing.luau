--!strict
--[[
	ActionRing — «что можно сделать здесь» для кольца действий (GDD §15е, идея жанра из OpenFront). Чистый модуль:
	по фактам о нажатой клетке — список действий (не больше MaxActions, без лишних). Клиент рисует кнопки
	(UI/ActionRing) и вызывает уже существующие действия (атака, объявление войны, предложения, разведка, метки).
]]

local ActionRing = {}

export type Action =
	"expand"
	| "attack"
	| "declare"
	| "alliance"
	| "trade"
	| "intel"
	| "target"
	| "help"
	| "build"
	| "mark"

export type Facts = {
	playing: boolean, -- идёт матч и у игрока есть держава
	me: number,
	owner: number, -- владелец клетки (0 — ничья)
	land: boolean, -- суша
	war: "none" | "mobilizing" | "active", -- война с владельцем
	allied: boolean, -- союзник
	trade: boolean, -- уже есть торговое соглашение
}

ActionRing.MaxActions = 6

function ActionRing.actions(f: Facts): { Action }
	local out: { Action } = {}
	if not f.playing then
		return out
	end
	if not f.land then
		table.insert(out, "mark")
	elseif f.owner == 0 then
		table.insert(out, "expand")
		table.insert(out, "mark")
	elseif f.owner == f.me then
		table.insert(out, "build")
		table.insert(out, "help")
	elseif f.allied then
		if not f.trade then
			table.insert(out, "trade")
		end
		table.insert(out, "help")
	elseif f.war ~= "none" then
		-- Мобилизация: атаковать ещё нельзя, но разведка и метка для союзников уже нужны.
		if f.war == "active" then
			table.insert(out, "attack")
		end
		table.insert(out, "intel")
		table.insert(out, "target")
	else
		table.insert(out, "declare")
		table.insert(out, "alliance")
		if not f.trade then
			table.insert(out, "trade")
		end
		table.insert(out, "intel")
	end
	while #out > ActionRing.MaxActions do
		table.remove(out)
	end
	return out
end

return table.freeze(ActionRing)
