--!strict
-- Главная кнопка «Дипломатии» (§15ц Ц4б).
local T = require("./lib/TestKit")
local DiploMain = require("../src/shared/DiploMain")

local function facts(over: { [string]: any }): DiploMain.Facts
	local f: { [string]: any } =
		{ valid = true, atWar = false, treaty = nil, breaking = false, trust = false, trustWait = 0 }
	for k, v in over do
		f[k] = v
	end
	return f :: any
end

T.describe("Главная кнопка Дипломатии (§15ц Ц4б)", function()
	T.it("не выбрана держава — «pick»; война — «war»; обе блёклые", function()
		local p = DiploMain.pick(facts({ valid = false }))
		T.expect(p.action).toBe("pick")
		T.expect(p.enabled).toBe(false)
		p = DiploMain.pick(facts({ atWar = true, treaty = "alliance" }))
		T.expect(p.action).toBe("war")
		T.expect(p.enabled).toBe(false)
	end)

	T.it("нет договора или пакт — «Предложить союз»", function()
		T.expect(DiploMain.pick(facts({})).action).toBe("alliance")
		local p = DiploMain.pick(facts({ treaty = "pact" }))
		T.expect(p.action).toBe("alliance")
		T.expect(p.enabled).toBe(true)
	end)

	T.it(
		"союз: доверие — после ожидания; с доверием или при разрыве — главной кнопки нет",
		function()
			local wait = DiploMain.pick(facts({ treaty = "alliance", trustWait = 20 }))
			T.expect(wait.action).toBe("trust")
			T.expect(wait.enabled).toBe(false)
			T.expect(DiploMain.pick(facts({ treaty = "alliance", trustWait = 0 })).enabled).toBe(true)
			T.expect(DiploMain.pick(facts({ treaty = "alliance", trust = true })).action).toBe("none")
			T.expect(DiploMain.pick(facts({ treaty = "alliance", breaking = true })).action).toBe("none")
		end
	)
end)
