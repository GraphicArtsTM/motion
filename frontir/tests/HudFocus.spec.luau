--!strict
-- §15ъ «Экран не мешает играть»: в столбике сверху — одна карточка по порядку важности, остальные ждут.
local T = require("./lib/TestKit")
local HudFocus = require("../src/shared/HudFocus")

local function count(t: { [string]: boolean }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

T.describe("Одна карточка в центре (§15ъ)", function()
	T.it(
		"худший случай со скриншота: на экране одно предложение мира, остальное ждёт",
		function()
			local wanted = {
				PeaceOffer = true,
				DiplomacyOffer = true,
				TaskCard = true,
				DoomBar = true,
				WarStatus = true,
			}
			local shown, waiting = HudFocus.pick(wanted, {})
			T.expect(count(shown)).toBe(1)
			T.expect(shown.PeaceOffer).toBe(true)
			T.expect(#waiting).toBe(4)
			T.expect(waiting[1]).toBe("DiplomacyOffer")
			T.expect(waiting[#waiting]).toBe("TaskCard")
		end
	)

	T.it("тревога и пауза — всегда и вне счёта", function()
		local shown, waiting = HudFocus.pick({ Alarm = true, Solo = true, TaskCard = true, Siren = true }, {})
		T.expect(shown.Alarm).toBe(true)
		T.expect(shown.Solo).toBe(true)
		T.expect(shown.Siren).toBe(true)
		T.expect(shown.TaskCard).toBe(nil)
		T.expect(#waiting).toBe(1)
	end)

	T.it("колокольчик: вызванная карточка — первой, по кругу", function()
		local wanted = { WarStatus = true, TaskCard = true, DoomBar = true }
		local _, waiting = HudFocus.pick(wanted, {})
		local hold = HudFocus.nextHold(waiting, nil)
		T.expect(hold).toBe("DoomBar")
		local shown = HudFocus.pick(wanted, { hold = hold })
		T.expect(shown.DoomBar).toBe(true)
		T.expect(shown.WarStatus).toBe(nil)
		T.expect(HudFocus.nextHold({ "WarStatus", "TaskCard" }, "DoomBar")).toBe("TaskCard")
		T.expect(HudFocus.nextHold({ "WarStatus", "DoomBar" }, "TaskCard")).toBe("WarStatus")
		T.expect(HudFocus.nextHold({}, nil)).toBe(nil)
	end)

	T.it(
		"плотность: «всё» — до трёх, «минимум» — только предложения и сирена",
		function()
			local wanted = { WarStatus = true, TaskCard = true, DoomBar = true, FinaleStrip = true }
			local full = HudFocus.pick(wanted, { density = "full" })
			T.expect(count(full)).toBe(3)
			local min, waiting = HudFocus.pick(wanted, { density = "min" })
			T.expect(count(min)).toBe(0)
			T.expect(#waiting).toBe(4)
			local minOffer = HudFocus.pick({ DiplomacyOffer = true, TaskCard = true }, { density = "min" })
			T.expect(minOffer.DiplomacyOffer).toBe(true)
			-- По колокольчику и в «минимуме» видно то, что вызвали.
			local held = HudFocus.pick(wanted, { density = "min", hold = "TaskCard" })
			T.expect(held.TaskCard).toBe(true)
		end
	)

	T.it("чистая карта: пока двигают карту — только «всегда»", function()
		local shown, waiting = HudFocus.pick({ Alarm = true, PeaceOffer = true, TaskCard = true }, { clean = true })
		T.expect(count(shown)).toBe(1)
		T.expect(shown.Alarm).toBe(true)
		T.expect(#waiting).toBe(2)
	end)

	T.it("незнакомая карточка — в конце очереди, не теряется", function()
		local shown, waiting = HudFocus.pick({ Mystery = true, TaskCard = true }, {})
		T.expect(shown.TaskCard).toBe(true)
		T.expect(waiting[1]).toBe("Mystery")
	end)
end)
