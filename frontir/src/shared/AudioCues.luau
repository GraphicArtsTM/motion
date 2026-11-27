--!strict
--[[
	AudioCues — когда что звучит (GDD §13, этап 10б). Чистый модуль: события матча → имена звуков (Config.Sounds),
	какая мелодия сейчас (Config.Music), ограничение частоты одинаковых звуков. Проигрывает клиентский Audio.
]]

local Config = require("./Config")
local Finale = require("./Finale")

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

AudioCues.MusicNames = table.freeze({ "Menu", "Match", "War" } :: { string })

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
		((kind == "researched" or kind == "shipBuilt" or kind == "taskNew") and mine)
		or kind == "worldEvent"
		or kind == "councilOpened"
	then
		return "Notify"
	elseif kind == "tutorialDone" and mine then
		return "Victory" -- §15ь Л4: обучение пройдено
	elseif kind == "tutorial" and mine then
		return "Coin" -- §15ь Л4: шаг обучения пройден
	elseif (kind == "underdog" or (kind == "trophy" and e.capital == true)) and mine then
		return "Victory" -- §15й Й2: фанфары — «Триумф» и «Давид и Голиаф»
	elseif
		(kind == "mercs" or kind == "taskDone" or kind == "trophy") and mine
		or (kind == "tradeDelivered" and (mine or onMe))
	then
		return "Coin"
	-- Правка звука (18.11.2026): ещё события, которые игрок должен услышать.
	elseif kind == "warStarted" and (mine or onMe) then
		return "Battle" -- мобилизация кончилась — война пошла
	elseif (kind == "capitalLost" or kind == "doomWarning") and mine then
		return "Siren" -- пала ваша столица / «часы судного дня» против вас
	elseif kind == "eliminated" and me ~= nil and e.by == me then
		return "Victory" -- вы добили державу
	elseif kind == "peace" and (mine or onMe) then
		return "Notify"
	elseif kind == "offerAccepted" and onMe then
		return "Notify" -- ваше предложение приняли
	elseif (kind == "built" or kind == "cityFounded") and mine then
		return "Build" -- стройка закончена
	elseif kind == "taskFailed" and mine then
		return "Error"
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
	menu: boolean?, -- открыто главное меню (или хаб / показательный бой за меню)
	atWar: boolean?, -- у игрока война или мобилизация (с задержкой Audio.WarHoldSec — AudioCues.warHold)
	leaderShare: number, -- доля суши лидера (0..1)
	victoryShare: number, -- доля для победы (0..1)
	timeLeft: number?, -- секунд матча до лимита (nil — без лимита)
	nearAllowed: boolean?, -- §15й Й3: бывает ли финал «лидер близко» (nil — да)
}

-- Какая мелодия сейчас (правка звука): меню — главное меню, хаб, ожидание игроков и итоги; матч — выбор старта и
-- игра без войны; война — у вас война или финал матча.
function AudioCues.music(s: MusicState): string
	if s.menu or s.phase == "Waiting" or s.phase == "Lobby" or s.phase == "Over" then
		return "Menu"
	end
	if s.phase ~= "Play" then
		return "Match"
	end
	if s.atWar then
		return "War"
	end
	-- §15й Й3: финал — то же правило, что баннер и «Все против лидера» (Finale.state).
	local f = Finale.state({
		victoryShare = s.victoryShare,
		leaderShare = s.leaderShare,
		timeLeft = s.timeLeft,
		nearAllowed = s.nearAllowed ~= false,
	}, false)
	if f.on then
		return "War"
	end
	return "Match"
end

-- Военная музыка ещё держится: последняя война была меньше Audio.WarHoldSec назад (nil — войны не было).
function AudioCues.warHold(lastWarAt: number?, now: number): boolean
	return lastWarAt ~= nil and now - lastWarAt < Config.Audio.WarHoldSec
end

-- Приглушать ли музыку на время этого звука.
function AudioCues.ducks(name: string): boolean
	return table.find(Config.Audio.Duck.Names, name) ~= nil
end

-- Скорость (высота) звука: частые звуки чуть разные; r — случайное 0..1.
function AudioCues.pitch(name: string, r: number): number
	local jitter = (Config.Audio.Pitch :: any)[name]
	if type(jitter) ~= "number" then
		return 1
	end
	return 1 + (r * 2 - 1) * jitter
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
