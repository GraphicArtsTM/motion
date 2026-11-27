--!strict
--[[
	HudFocus — §15ъ «экран не мешает играть», без Roblox API: какие карточки столбика сверху по центру показать.
	wanted — карточка хочет показаться (её окно само решило, что ему есть что сказать); показываем по порядку
	Config.Hud.Priority не больше MaxCards[density], «Always» — всегда и вне счёта. hold — карточка, вызванная
	колокольчиком (первой, если хочет показаться). clean — карту двигают: только «Always» (тревога, пауза…).
	Возвращает, что показать, и сколько хотящих ждёт (число на колокольчике), по порядку важности.
]]

local Config = require("./Config")

export type Density = "min" | "normal" | "full"
export type Options = { density: Density?, hold: string?, clean: boolean? }

local HudFocus = {}

-- Карточка в столбике, но не в списках Config.Hud — тоже ждёт, после всех из Priority.
local function rank(name: string): number
	return table.find(Config.Hud.Priority, name) or (#Config.Hud.Priority + 1)
end

function HudFocus.isAlways(name: string): boolean
	return table.find(Config.Hud.Always, name) ~= nil
end

function HudFocus.pick(wanted: { [string]: boolean }, opts: Options): ({ [string]: boolean }, { string })
	local density: Density = opts.density or "normal"
	local max = (Config.Hud.MaxCards :: any)[density] or 1
	local shown: { [string]: boolean } = {}
	local queue: { string } = {}
	for name, want in wanted do
		if want then
			if HudFocus.isAlways(name) then
				shown[name] = true
			else
				table.insert(queue, name)
			end
		end
	end
	table.sort(queue, function(a: string, b: string): boolean
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	local hold = opts.hold
	if hold ~= nil then
		local at = table.find(queue, hold)
		if at ~= nil then
			table.remove(queue, at)
			table.insert(queue, 1, hold)
		end
	end
	local waiting: { string } = {}
	local count = 0
	for _, name in queue do
		local allowed = density ~= "min" or table.find(Config.Hud.MinOnly, name) ~= nil or name == hold
		if not opts.clean and allowed and count < max then
			shown[name] = true
			count += 1
		else
			table.insert(waiting, name)
		end
	end
	return shown, waiting
end

-- Колокольчик: какую карточку показать по нажатию — следующую после той, что держится сейчас (по кругу).
function HudFocus.nextHold(waiting: { string }, current: string?): string?
	if #waiting == 0 then
		return nil
	end
	if current == nil then
		return waiting[1]
	end
	for k, name in waiting do
		if rank(name) > rank(current) then
			return waiting[k]
		end
	end
	return waiting[1]
end

return table.freeze(HudFocus)
