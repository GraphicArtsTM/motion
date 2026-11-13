--!strict
--[[
	DiploMain — §15ц Ц4б: главная кнопка окна «Дипломатия» — самое полезное действие с выбранной державой.
	- держава не выбрана (или это вы, или она выбыла) — «pick», кнопка блёклая;
	- идёт война — «war», кнопка блёклая (мир предлагают в окне войны сверху);
	- союз без полного доверия — «trust» (до Alliance.TrustAfterSec — блёклая, с отсчётом);
	- союз с доверием или союз рвётся — «none» (главной кнопки нет);
	- нет договора или пакт — «alliance».
	Чистый модуль: факты собирает DiplomacyPanel.
]]

export type Action = "pick" | "war" | "alliance" | "trust" | "none"
export type Facts = {
	valid: boolean, -- выбрана живая чужая держава
	atWar: boolean,
	treaty: string?, -- вид договора: nil, "pact", "alliance"
	breaking: boolean, -- договор разрывается
	trust: boolean, -- полное доверие уже есть
	trustWait: number, -- секунд до «Полного доверия» (≤ 0 — можно)
}
export type Pick = { action: Action, enabled: boolean }

local DiploMain = {}

function DiploMain.pick(f: Facts): Pick
	if not f.valid then
		return { action = "pick", enabled = false }
	elseif f.atWar then
		return { action = "war", enabled = false }
	elseif f.treaty == "alliance" then
		if f.breaking or f.trust then
			return { action = "none", enabled = false }
		end
		return { action = "trust", enabled = f.trustWait <= 0 }
	end
	return { action = "alliance", enabled = true }
end

return table.freeze(DiploMain)
