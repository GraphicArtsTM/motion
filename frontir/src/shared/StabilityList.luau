--!strict
--[[
	StabilityList — §15ц Ц4а: что показать в окне «Стабильность». Свои провинции от худшей к лучшей и метка у
	каждой: «revolt» — ниже Stability.RevoltBelow (провинция восстанет, если не поднять), «low» — ниже LowBelow
	(доход ×LowIncomeMul), «ok» — всё хорошо. Чистый модуль: берёт то, что пришло в cs.stability (ids, values).
]]

local Config = require("./Config")

export type Level = "revolt" | "low" | "ok"
export type Row = { province: number, value: number, level: Level }
export type Counts = { revolt: number, low: number, ok: number }

local StabilityList = {}

function StabilityList.level(value: number): Level
	local cfg = Config.Stability
	if value < cfg.RevoltBelow then
		return "revolt"
	elseif value < cfg.LowBelow then
		return "low"
	end
	return "ok"
end

-- Строки от худшей стабильности к лучшей; при равенстве — по номеру провинции (порядок не прыгает).
function StabilityList.rows(ids: { number }, values: { number }): { Row }
	local rows: { Row } = {}
	for k, p in ids do
		local v = values[k] or 0
		table.insert(rows, { province = p, value = v, level = StabilityList.level(v) })
	end
	table.sort(rows, function(a: Row, b: Row): boolean
		if a.value ~= b.value then
			return a.value < b.value
		end
		return a.province < b.province
	end)
	return rows
end

function StabilityList.counts(rows: { Row }): Counts
	local c: Counts = { revolt = 0, low = 0, ok = 0 }
	for _, r in rows do
		c[r.level] += 1
	end
	return c
end

-- Самая слабая провинция (для главной кнопки «К самой слабой»); nil — своих провинций нет.
function StabilityList.worst(rows: { Row }): number?
	local first = rows[1]
	return if first ~= nil then first.province else nil
end

return table.freeze(StabilityList)
