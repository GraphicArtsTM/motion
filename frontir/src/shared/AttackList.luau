--!strict
--[[
	AttackList — что показать в панели «АТАКИ» и в фишках над полосой (GDD §15ф Ф2), без Roblox API.
	rows(attacks, me, maxRows) — строки: свои атаки (kind "out") первыми, потом атаки на вас ("in"); внутри — по силе
	(скрытая сила «?» — в конце), при равенстве — по номеру державы. Возвращает строки (не больше maxRows), сколько
	не влезло, и сколько всего своих и чужих.
	share(ratio) — полоса перевеса 0..1: ratio / (1 + ratio) (обороны нет — 1).
	chips(attacks, me, maxChips) — свои атаки для фишек (тот же порядок).
]]

export type Kind = "out" | "in"

-- Минимум полей атаки, которые нужны списку (Protocol.AttackStats подходит).
export type Attack = {
	attacker: number,
	target: number,
	power: number, -- < 0 — сила скрыта (§6.11а)
	troops: number,
	ratio: number,
	supplied: boolean,
	focus: number?,
}

export type Row = {
	kind: Kind,
	other: number, -- цель своей атаки или кто нападает
	power: number,
	share: number, -- 0..1: наша доля в перевесе (у атаки на нас — доля обороны)
	advancing: boolean, -- атакующий перевешивает (ratio > 1)
	supplied: boolean,
	focus: number?,
}

export type Counts = { out: number, inc: number, hidden: number }

local AttackList = {}

function AttackList.share(ratio: number): number
	if ratio ~= ratio or ratio <= 0 then
		return 0
	end
	if ratio == math.huge then
		return 1
	end
	return ratio / (1 + ratio)
end

local function rowOf(a: Attack, kind: Kind): Row
	local s = AttackList.share(a.ratio)
	return {
		kind = kind,
		other = if kind == "out" then a.target else a.attacker,
		power = a.power,
		share = if kind == "out" then s else 1 - s,
		advancing = a.ratio > 1,
		supplied = a.supplied,
		focus = a.focus,
	}
end

local function before(x: Row, y: Row): boolean
	if x.kind ~= y.kind then
		return x.kind == "out"
	end
	local px = if x.power < 0 then -1 else x.power
	local py = if y.power < 0 then -1 else y.power
	if px ~= py then
		return px > py
	end
	return x.other < y.other
end

local function collect(attacks: { Attack }, me: number?, wantIn: boolean): { Row }
	local out: { Row } = {}
	if me == nil then
		return out
	end
	for _, a in attacks do
		if a.attacker == me then
			table.insert(out, rowOf(a, "out"))
		elseif wantIn and a.target == me and a.attacker ~= me then
			table.insert(out, rowOf(a, "in"))
		end
	end
	table.sort(out, before)
	return out
end

function AttackList.rows(attacks: { Attack }, me: number?, maxRows: number): ({ Row }, Counts)
	local all = collect(attacks, me, true)
	local counts: Counts = { out = 0, inc = 0, hidden = 0 }
	for _, r in all do
		if r.kind == "out" then
			counts.out += 1
		else
			counts.inc += 1
		end
	end
	local shown: { Row } = {}
	for k = 1, math.min(#all, math.max(0, maxRows)) do
		shown[k] = all[k]
	end
	counts.hidden = #all - #shown
	return shown, counts
end

function AttackList.chips(attacks: { Attack }, me: number?, maxChips: number): { Row }
	local own = collect(attacks, me, false)
	local out: { Row } = {}
	for k = 1, math.min(#own, math.max(0, maxChips)) do
		out[k] = own[k]
	end
	return out
end

return table.freeze(AttackList)
