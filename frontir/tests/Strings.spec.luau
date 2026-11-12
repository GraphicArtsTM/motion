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
				"noCapital",
				"noUnits",
				"queueFull",
				"notAtWar",
				"mobilizing",
				"alreadyAtWar",
				"peaceCooldown",
				"peacePending",
				"noProposal",
				"notYet",
				"needFactory",
				"noMoney",
				"noOil",
				"needCity",
				"maxLevel",
				"occupied",
				"needOil",
				"notOwner",
				"researching",
				"techMaxed",
				"techLocked",
				-- Этапы 8–9 (режимы, магазин, косметика)
				"team",
				"mode",
				"solo",
				"diplomacyOff",
				"locked",
				"noStock",
				"noTokens",
				"boostUsed",
				"noBoosts",
				"noCrates",
				"noPort",
				"noAirfield",
				"noMedals",
				"needTech",
				"noResearch",
				"cooldown",
				"noEnemy",
				"needSilo",
				"banned",
				"noAuction",
				"lowBid",
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

	T.it(
		'каждый ключ, который код берёт строкой Strings.get("..."), есть в таблице (§11.5)',
		function()
			local fs = require("@lune/fs")
			local missing: { string } = {}
			local function scan(dir: string)
				for _, name in fs.readDir(dir) do
					local path = dir .. "/" .. name
					if fs.isDir(path) then
						scan(path)
					elseif string.sub(name, -5) == ".luau" then
						local text = fs.readFile(path)
						for key in string.gmatch(text, 'Strings%.get%(%s*"([^"]+)"%s*[,)]') do
							if Strings.Table[key] == nil then
								table.insert(missing, path .. ": " .. key)
							end
						end
					end
				end
			end
			scan("src")
			if #missing > 0 then
				error("нет строк: " .. table.concat(missing, "; "))
			end
		end
	)

	T.it(
		"в шаблонах знак процента — только «%%»: «+5% income» ронял string.format (окно торговли, Studio)",
		function()
			local bad: { string } = {}
			for key, entry in Strings.Table do
				for _, lang: Strings.Lang in Strings.Langs do
					local s = Strings.pick(entry, lang)
					-- Только шаблоны (есть %s / %d …): простой текст с «5%» выводится как есть и не ломается.
					local template = string.find(s, "%%[%-%+#0]*%d*%.?%d*[sdifgxXqc]") ~= nil
					local i = if template then 1 else #s + 1
					while true do
						local p = string.find(s, "%", i, true)
						if p == nil then
							break
						end
						if string.sub(s, p + 1, p + 1) == "%" then
							i = p + 2
						else
							local spec = string.match(s, "^%%[%-%+#0]*%d*%.?%d*[sdifgxXqc]", p)
							if spec == nil or string.match(string.sub(s, p - 1, p - 1), "%d") ~= nil then
								table.insert(bad, key .. "/" .. lang .. ": " .. s)
							end
							i = p + 1
						end
					end
				end
			end
			table.sort(bad)
			if #bad > 0 then
				error("одиночный %: " .. table.concat(bad, "; "))
			end
		end
	)
end)
