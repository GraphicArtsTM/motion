--!strict
local T = require("./lib/TestKit")
local Strings = require("../src/shared/Strings")

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

	T.it("локаль Roblox сводится к языку", function()
		T.expect(Strings.langFromLocale("ru-ru")).toBe("ru")
		T.expect(Strings.langFromLocale("en-us")).toBe("en")
		T.expect(Strings.langFromLocale("de-de")).toBe("en")
	end)
end)
