--!strict
--[[
	Spectate — «Следить за лидером» (GDD §15й Й5), без Roblox API: куда смотреть (главный удар лидера — фронт против
	державы важнее ничьей земли, сильнее важнее слабее; нет фронтов — столица) и плавный шаг камеры к цели.
]]

local Config = require("./Config")

export type AttackLike = { attacker: number, target: number, focus: number?, power: number }

local Spectate = {}

-- Клетка, куда смотреть: главный удар лидера или его столица (nil — некуда).
function Spectate.target(attacks: { AttackLike }, leader: number, capital: number?): number?
	local best: AttackLike? = nil
	for _, a in attacks do
		if a.attacker == leader and a.focus ~= nil then
			local better = best == nil
				or (a.target ~= 0 and best.target == 0)
				or ((a.target ~= 0) == (best.target ~= 0) and a.power > best.power)
			if better then
				best = a
			end
		end
	end
	if best ~= nil then
		return best.focus
	end
	return capital
end

-- Шаг камеры от (x, y) к (tx, ty) за dt секунд: доля пути — как у пружины (Render.Spectate.Follow в секунду).
function Spectate.step(x: number, y: number, tx: number, ty: number, dt: number): (number, number)
	local k = 1 - math.exp(-Config.Render.Spectate.Follow * math.max(0, dt))
	return x + (tx - x) * k, y + (ty - y) * k
end

return table.freeze(Spectate)
