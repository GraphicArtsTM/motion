--!strict
--[[
	AudioCues — когда что звучит (GDD §13, этап 10б). Чистый модуль: события матча → имена звуков (Config.Sounds),
	какая мелодия сейчас (Config.Music), ограничение частоты одинаковых звуков. Проигрывает клиентский Audio.
]]

local Config = require("./Config")

local AudioCues = {}

AudioCues.SoundNames = table.freeze({
	"Click",
	"Error",
	"Capture",
	"Province",
	"Battle",
	"Explosion",
	"Plane",
	"Parachute",
	"Siren",
	"Offer",
	"Betrayal",
	"Victory",
	"Defeat",
	"Notify",
	"Coin",
	"Hire",
	"Build",
} :: { string })

AudioCues.MusicNames = table.freeze({ "Lobby", "Calm", "Finale" } :: { string })

-- Звук одного события глазами державы me (nil — без звука).
function AudioCues.cueOf(e: { [string]: any }, me: number?): string?
	local kind = e.kind
	local mine = me ~= nil and e.nation == me
	local onMe = me ~= nil and e.target == me
	local landing = (kind == "ability" and (e.ability == "Airdrop" or e.ability == "SeaLanding")) or kind == "landed"
	if (kind == "warDeclared" or kind == "missileLaunched") and onMe then
		return "Siren"
	elseif
		kind == "missileHit"
		or kind == "nukeHit"
		or (kind == "raid" and onMe)
		or (kind == "ability" and e.ability == "Airstrike" and (mine or onMe))
	then
		return "Explosion"
	elseif (kind == "raid" or kind == "planeBuilt") and mine then
		return "Plane"
	elseif kind == "betrayal" and onMe then
		return "Betrayal"
	elseif (kind == "offerMade" or kind == "peaceProposed") and onMe then
		return "Offer"
	elseif landing and (mine or onMe) then
		return "Parachute"
	elseif
		((kind == "researched" or kind == "shipBuilt") and mine)
		or kind == "worldEvent"
		or kind == "councilOpened"
	then
		return "Notify"
	elseif (kind == "mercs" and mine) or (kind == "tradeDelivered" and (mine or onMe)) then
		return "Coin"
	end
	return nil
end

-- Звуки для пачки событий глазами державы me (каждый звук — не больше раза за пачку, в порядке событий).
-- Победа и поражение — по итогу матча (AudioCues.result), захват клеток и городов — по дельтам сетки.
function AudioCues.fromEvents(events: { any }, me: number?): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(name: string)
		if not seen[name] then
			seen[name] = true
			table.insert(out, name)
		end
	end
	for _, e in events do
		if type(e) ~= "table" then
			continue
		end
		local name = AudioCues.cueOf(e, me)
		if name ~= nil then
			add(name)
		end
	end
	return out
end

-- Итог матча для державы me: "Victory" (победитель или его союзник), "Defeat" — иначе, nil — зритель.
function AudioCues.result(winner: number, coWinners: { number }?, me: number?): string?
	if me == nil then
		return nil
	end
	if winner == me or (coWinners ~= nil and table.find(coWinners, me) ~= nil) then
		return "Victory"
	end
	return "Defeat"
end

export type MusicState = {
	phase: string, -- фаза матча
	leaderShare: number, -- доля суши лидера (0..1)
	victoryShare: number, -- доля для победы (0..1)
	timeLeft: number?, -- секунд матча до лимита (nil — без лимита)
}

-- Какая мелодия сейчас: лобби, игра или финал.
function AudioCues.music(s: MusicState): string
	if s.phase ~= "Play" then
		return "Lobby"
	end
	local cfg = Config.Audio
	if s.victoryShare > 0 and s.leaderShare >= s.victoryShare - cfg.FinaleMargin then
		return "Finale"
	end
	if s.timeLeft ~= nil and s.timeLeft <= cfg.FinaleTimeSec then
		return "Finale"
	end
	return "Calm"
end

export type Throttle = { last: { [string]: number } }

function AudioCues.newThrottle(): Throttle
	return { last = {} }
end

-- Можно ли сыграть звук name сейчас (не чаще Config.Audio.Gaps[name]); если да — запоминает время.
function AudioCues.allow(t: Throttle, name: string, now: number): boolean
	local gap = (Config.Audio.Gaps :: any)[name] or 0
	local last = t.last[name]
	if last ~= nil and now - last < gap then
		return false
	end
	t.last[name] = now
	return true
end

-- Громкость по шагам VolumeStep в пределах 0..1.
function AudioCues.stepVolume(v: number, dir: number): number
	local step = Config.Audio.VolumeStep
	return math.clamp(math.round((v + dir * step) / step) * step, 0, 1)
end

return table.freeze(AudioCues)
