--!strict
local T = require("./lib/TestKit")
local ActionRing = require("../src/shared/ActionRing")
local Strings = require("../src/shared/Strings")

local function facts(over: { [string]: any }): ActionRing.Facts
	local f: any = {
		playing = true,
		me = 1,
		owner = 0,
		land = true,
		war = "none",
		allied = false,
		trade = false,
	}
	for k, v in over do
		f[k] = v
	end
	return f
end

local function has(list: { ActionRing.Action }, a: string): boolean
	return table.find(list :: { any }, a) ~= nil
end

T.describe("Кольцо действий (§15е)", function()
	T.it("по клетке — только то, что можно сделать", function()
		T.expect(#ActionRing.actions(facts({ playing = false }))).toBe(0)
		local water = ActionRing.actions(facts({ land = false }))
		T.expect(#water).toBe(1)
		T.expect(water[1]).toBe("mark")
		T.expect(has(ActionRing.actions(facts({})), "expand")).toBe(true)
		local own = ActionRing.actions(facts({ owner = 1 }))
		T.expect(has(own, "build") and has(own, "help")).toBe(true)
		T.expect(has(own, "attack")).toBe(false)
		local peace = ActionRing.actions(facts({ owner = 2 }))
		T.expect(has(peace, "declare") and has(peace, "alliance") and has(peace, "trade") and has(peace, "intel"))
			.toBe(true)
		T.expect(has(peace, "attack")).toBe(false)
		T.expect(has(ActionRing.actions(facts({ owner = 2, trade = true })), "trade")).toBe(false)
		local war = ActionRing.actions(facts({ owner = 2, war = "active" }))
		T.expect(has(war, "attack") and has(war, "target") and has(war, "intel")).toBe(true)
		T.expect(has(war, "declare") or has(war, "alliance")).toBe(false)
		-- Мобилизация: атаковать ещё нельзя.
		T.expect(has(ActionRing.actions(facts({ owner = 2, war = "mobilizing" })), "attack")).toBe(false)
		local ally = ActionRing.actions(facts({ owner = 3, allied = true }))
		T.expect(has(ally, "help") and has(ally, "trade")).toBe(true)
		T.expect(has(ally, "declare")).toBe(false)
	end)

	T.it("не больше MaxActions кнопок; у каждой есть строка RU/EN", function()
		local all = { "expand", "attack", "declare", "alliance", "trade", "intel", "target", "help", "build", "mark" }
		for _, a in all do
			T.expect(Strings.get("ring." .. a, "ru") ~= "ring." .. a).toBe(true)
			T.expect(Strings.get("ring." .. a, "en") ~= "ring." .. a).toBe(true)
		end
		for _, f in { facts({ owner = 2 }), facts({ owner = 2, war = "active" }), facts({ owner = 1 }) } do
			T.expect(#ActionRing.actions(f) <= ActionRing.MaxActions).toBe(true)
		end
	end)
end)
