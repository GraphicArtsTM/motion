--!strict
local T = require("./lib/TestKit")
local Strings = require("../src/shared/Strings")
local Types = require("../src/shared/Types")

T.describe("Strings", function()
	T.it("у каждого ключа есть все языки", function()
		for key, entry in Strings.Table do
			for _, lang: Strings.Lang in Strings.Langs do
				if Strings.pick(entry, lang) == "" then
					error("нет перевода " .. lang .. " для " .. key)
				end
			end
		end
	end)

	T.it("get возвращает перевод и ключ при отсутствии", function()
		T.expect(Strings.get("game.title", "ru")).toBe("Фронтир")
		T.expect(Strings.get("game.title", "en")).toBe("Frontir")
		T.expect(Strings.get("no.such.key", "en")).toBe("no.such.key")
	end)

	T.it("у каждого типа местности есть название", function()
		for name in Types.Terrain :: { [string]: number } do
			T.expect(Strings.Table["terrain." .. name] ~= nil).toBe(true)
		end
	end)

	T.it("шаблоны с %-подстановками совпадают в RU и EN", function()
		for key, entry in Strings.Table do
			local function specs(text: string): string
				local out = {}
				for spec in string.gmatch(text, "%%[%d%.]*[dsf]") do
					table.insert(out, spec)
				end
				return table.concat(out, ",")
			end
			if specs(entry.ru) ~= specs(entry.en) then
				error("разные подстановки в " .. key)
			end
		end
	end)

	T.it("числа с разделителем тысяч", function()
		local sep = "\u{202F}"
		T.expect(Strings.formatInt(0)).toBe("0")
		T.expect(Strings.formatInt(999)).toBe("999")
		T.expect(Strings.formatInt(1000)).toBe("1" .. sep .. "000")
		T.expect(Strings.formatInt(1234567.4)).toBe("1" .. sep .. "234" .. sep .. "567")
		T.expect(Strings.formatInt(-12345)).toBe("-12" .. sep .. "345")
	end)

	T.it("у каждой причины отказа сервера есть текст", function()
		for _, reason in
			{
				"TooClose",
				"NotLand",
				"TooSmall",
				"OutOfMap",
				"notAdjacent",
				"tooMany",
				"noTroops",
				"phase",
				"dead",
				"self",
				"target",
				"focus",
				"noAttack",
				"noNation",
			}
		do
			T.expect(Strings.Table["reject." .. reason] ~= nil).toBe(true)
		end
	end)

	T.it("локаль Roblox сводится к языку", function()
		T.expect(Strings.langFromLocale("ru-ru")).toBe("ru")
		T.expect(Strings.langFromLocale("en-us")).toBe("en")
		T.expect(Strings.langFromLocale("de-de")).toBe("en")
	end)
end)
