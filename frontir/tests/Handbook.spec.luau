--!strict
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Handbook = require("../src/shared/Handbook")
local ItemArt = require("../src/shared/ItemArt")
local Strings = require("../src/shared/Strings")

-- Картинка есть: свой ключ ItemArt или «building.<вид>» существующего здания.
local function artExists(key: string): boolean
	if ItemArt.has(key) then
		return true
	end
	local kind = string.match(key, "^building%.(%a+)$")
	return kind ~= nil and (Config.Buildings :: any)[kind] ~= nil
end

local function filled(key: string): boolean
	local e = Strings.Table[key]
	return e ~= nil and e.ru ~= "" and e.en ~= ""
end

T.describe("Справочник механик (§15х ч.5)", function()
	T.it(
		"у каждой строки есть название и три строки на RU/EN и картинка",
		function()
			for _, e in Handbook.Entries do
				local keys = Handbook.textKeys(e)
				for _, k in { keys.name, keys.what, keys.how, keys.counter } do
					if not filled(k) then
						error("нет текста RU/EN: " .. k)
					end
				end
				if not artExists(e.art) then
					error("нет картинки: " .. e.art .. " у " .. e.key)
				end
			end
		end
	)

	T.it(
		"третья строка: «Чем защититься» или «Как помешать», лишнего ключа нет",
		function()
			for _, e in Handbook.Entries do
				local other = if e.hinder then "defense" else "hinder"
				T.expect(Strings.Table["handbook." .. e.key .. "." .. other]).toBe(nil)
			end
			T.expect(Handbook.counter({ key = "x", tab = "army", art = "a" })).toBe("defense")
			T.expect(Handbook.counter({ key = "x", tab = "army", art = "a", hinder = true })).toBe("hinder")
			T.expect(filled("handbook.defense")).toBeTruthy()
			T.expect(filled("handbook.hinder")).toBeTruthy()
			T.expect(filled("handbook.what")).toBeTruthy()
			T.expect(filled("handbook.how")).toBeTruthy()
		end
	)

	T.it(
		"вкладки: шесть, у каждой название и хотя бы одна механика; ключи не повторяются",
		function()
			T.expect(#Handbook.Tabs).toBe(6)
			for _, tab in Handbook.Tabs do
				T.expect(filled("handbook.tab." .. tab)).toBeTruthy()
				T.expect(#Handbook.of(tab) > 0).toBeTruthy()
			end
			local seen: { [string]: boolean } = {}
			local total = 0
			for _, e in Handbook.Entries do
				T.expect(seen[e.key]).toBe(nil)
				seen[e.key] = true
				T.expect(table.find(Handbook.Tabs, e.tab) ~= nil).toBeTruthy()
			end
			for _, tab in Handbook.Tabs do
				total += #Handbook.of(tab)
			end
			T.expect(total).toBe(#Handbook.Entries)
		end
	)

	T.it("удары из таблицы §15х есть в справочнике", function()
		local keys: { [string]: boolean } = {}
		for _, e in Handbook.of("strikes") do
			keys[e.key] = true
		end
		for _, k in { "missile", "nukes", "raid", "ability", "defense" } do
			T.expect(keys[k]).toBe(true)
		end
	end)
end)
