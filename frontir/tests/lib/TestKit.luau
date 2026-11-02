--!strict
--[[
	TestKit — минимальный тестовый фреймворк для Lune (без внешних зависимостей).

	local T = require("./lib/TestKit")
	T.describe("Grid", function()
		T.it("индекс клетки", function()
			T.expect(1 + 1).toBe(2)
		end)
	end)
]]

export type Result = { name: string, ok: boolean, err: string? }

local TestKit = {}

local results: { Result } = {}
local prefix: { string } = {}

local function fullName(name: string): string
	if #prefix == 0 then
		return name
	end
	return table.concat(prefix, " › ") .. " › " .. name
end

function TestKit.describe(name: string, body: () -> ())
	table.insert(prefix, name)
	body()
	table.remove(prefix)
end

function TestKit.it(name: string, body: () -> ())
	local ok, err = pcall(body)
	table.insert(results, { name = fullName(name), ok = ok, err = if ok then nil else tostring(err) })
end

local function fmt(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

export type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeNear: (expected: number, eps: number?) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toThrow: () -> (),
}

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function TestKit.expect(actual: any): Expectation
	return {
		toBe = function(expected: any)
			if actual ~= expected then
				error(string.format("ожидалось %s, получено %s", fmt(expected), fmt(actual)), 2)
			end
		end,
		toEqual = function(expected: any)
			if not deepEqual(actual, expected) then
				error("таблицы не совпадают", 2)
			end
		end,
		toBeNear = function(expected: number, eps: number?)
			local e = eps or 1e-9
			if type(actual) ~= "number" or math.abs(actual - expected) > e then
				error(
					string.format(
						"ожидалось ≈%s (±%s), получено %s",
						fmt(expected),
						fmt(e),
						fmt(actual)
					),
					2
				)
			end
		end,
		toBeTruthy = function()
			if not actual then
				error(
					string.format(
						"ожидалось истинное значение, получено %s",
						fmt(actual)
					),
					2
				)
			end
		end,
		toBeFalsy = function()
			if actual then
				error(
					string.format("ожидалось ложное значение, получено %s", fmt(actual)),
					2
				)
			end
		end,
		toThrow = function()
			local ok = pcall(actual)
			if ok then
				error("ожидалась ошибка, но функция выполнилась", 2)
			end
		end,
	}
end

-- Забирает накопленные результаты и очищает буфер.
function TestKit.takeResults(): { Result }
	local out = results
	results = {}
	return out
end

return TestKit
