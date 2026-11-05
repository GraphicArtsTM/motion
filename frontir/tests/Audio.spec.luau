--!strict
local T = require("./lib/TestKit")
local AudioCues = require("../src/shared/AudioCues")
local Config = require("../src/shared/Config")
local Profile = require("../src/shared/Profile")
local SoundBank = require("../tools/lib/SoundBank")
local Synth = require("../tools/lib/Synth")

local function keys(t: { [string]: any }): { string }
	local out: { string } = {}
	for k in t do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

local function sorted(list: { string }): { string }
	local out = table.clone(list)
	table.sort(out)
	return out
end

T.describe("Звук и музыка (этап 10б)", function()
	T.it(
		"имена звуков и мелодий одинаковы в Config, AudioCues и генераторе; у каждого id и громкость",
		function()
			T.expect(table.concat(keys(Config.Sounds :: any), ","))
				.toBe(table.concat(sorted(AudioCues.SoundNames), ","))
			T.expect(table.concat(keys(SoundBank.Sounds :: any), ","))
				.toBe(table.concat(sorted(AudioCues.SoundNames), ","))
			T.expect(table.concat(keys(Config.Music :: any), ",")).toBe(table.concat(sorted(AudioCues.MusicNames), ","))
			T.expect(table.concat(keys(SoundBank.Songs :: any), ","))
				.toBe(table.concat(sorted(AudioCues.MusicNames), ","))
			for _, group in { Config.Sounds, Config.Music } :: { any } do
				for name, entry in group do
					T.expect(type(entry.id)).toBe("string")
					T.expect(entry.id == "" or string.match(entry.id, "^rbxassetid://%d+$") ~= nil).toBe(true)
					T.expect(entry.volume > 0 and entry.volume <= 1).toBe(true)
					local _ = name
				end
			end
		end
	)

	T.it(
		"события → звуки: сирена, взрыв, предложение, предательство, парашют, самолёт, событие",
		function()
			local me = 1
			local function cues(events: { any }): string
				return table.concat(AudioCues.fromEvents(events, me), ",")
			end
			T.expect(cues({ { kind = "warDeclared", nation = 2, target = 1 } })).toBe("Siren")
			T.expect(cues({ { kind = "warDeclared", nation = 2, target = 3 } })).toBe("")
			T.expect(cues({ { kind = "missileLaunched", nation = 2, target = 1, cell = 5, impactIn = 10 } }))
				.toBe("Siren")
			T.expect(cues({ { kind = "missileHit", nation = 2, cell = 5, cells = 40 } })).toBe("Explosion")
			T.expect(cues({ { kind = "raid", nation = 2, target = 1 }, { kind = "raid", nation = 1, target = 2 } }))
				.toBe("Explosion,Plane")
			T.expect(cues({ { kind = "offerMade", nation = 2, target = 1, offer = "alliance" } })).toBe("Offer")
			T.expect(cues({ { kind = "betrayal", nation = 2, target = 1 } })).toBe("Betrayal")
			T.expect(cues({ { kind = "ability", nation = 1, ability = "Airdrop", target = 2 } })).toBe("Parachute")
			T.expect(cues({ { kind = "ability", nation = 2, ability = "Airstrike", target = 1 } })).toBe("Explosion")
			T.expect(cues({ { kind = "researched", nation = 1 }, { kind = "worldEvent", event = "Storm" } }))
				.toBe("Notify")
			T.expect(cues({ { kind = "mercs", nation = 1, amount = 2000 } })).toBe("Coin")
			-- Один и тот же звук — один раз за пачку; мусор пропускается.
			T.expect(cues({ "junk" :: any, { kind = "missileHit" }, { kind = "missileHit" } })).toBe("Explosion")
			-- Зритель (me = nil) слышит только общие звуки.
			T.expect(table.concat(AudioCues.fromEvents({ { kind = "warDeclared", nation = 2, target = 1 } }, nil), ","))
				.toBe("")
		end
	)

	T.it(
		"итог: победа у победителя и союзников, иначе поражение; зритель — ничего",
		function()
			T.expect(AudioCues.result(1, nil, 1)).toBe("Victory")
			T.expect(AudioCues.result(2, { 1 }, 1)).toBe("Victory")
			T.expect(AudioCues.result(2, { 3 }, 1)).toBe("Defeat")
			T.expect(AudioCues.result(2, nil, nil)).toBe(nil)
		end
	)

	T.it(
		"музыка: лобби вне игры, игра, финал — лидер ближе 10% к победе или мало времени",
		function()
			local cfg = Config.Audio
			T.expect(AudioCues.music({ phase = "Lobby", leaderShare = 0, victoryShare = 0.6 })).toBe("Lobby")
			T.expect(AudioCues.music({ phase = "Over", leaderShare = 0.7, victoryShare = 0.6 })).toBe("Lobby")
			T.expect(AudioCues.music({ phase = "Play", leaderShare = 0.3, victoryShare = 0.6, timeLeft = 600 }))
				.toBe("Calm")
			T.expect(AudioCues.music({ phase = "Play", leaderShare = 0.6 - cfg.FinaleMargin, victoryShare = 0.6 }))
				.toBe("Finale")
			T.expect(AudioCues.music({
				phase = "Play",
				leaderShare = 0.2,
				victoryShare = 0.6,
				timeLeft = cfg.FinaleTimeSec - 1,
			})).toBe("Finale")
		end
	)

	T.it("частота: звук не чаще Audio.Gaps; громкость по шагам 0..1", function()
		local t = AudioCues.newThrottle()
		T.expect(AudioCues.allow(t, "Battle", 10)).toBe(true)
		T.expect(AudioCues.allow(t, "Battle", 10 + Config.Audio.Gaps.Battle - 0.1)).toBe(false)
		T.expect(AudioCues.allow(t, "Battle", 10 + Config.Audio.Gaps.Battle)).toBe(true)
		T.expect(AudioCues.allow(t, "Victory", 10)).toBe(true)
		T.expect(AudioCues.allow(t, "Victory", 10)).toBe(true) -- без ограничения
		T.expect(AudioCues.stepVolume(0.8, 1)).toBeNear(0.9, 1e-9)
		T.expect(AudioCues.stepVolume(1, 1)).toBe(1)
		T.expect(AudioCues.stepVolume(0, -1)).toBe(0)
	end)

	T.it(
		"генератор: каждый звук и мелодия — непустой WAV нужной длины, без перегруза",
		function()
			for _, name in AudioCues.SoundNames do
				local s = Synth.finish(SoundBank.Sounds[name](), 0.85)
				T.expect(#s > 100 and #s < Synth.Rate * 2).toBe(true)
				for i = 1, #s, 97 do
					T.expect(s[i] == s[i] and math.abs(s[i]) <= 0.85 + 1e-9).toBe(true)
				end
			end
			local song = SoundBank.Songs.Finale
			local samples = SoundBank.song(song)
			local expected = math.floor(SoundBank.Bars * 4 * 60 / song.bpm * SoundBank.MusicRate)
			T.expect(#samples).toBe(expected)
			local wav = Synth.wav({ 0, 0.5, -0.5 }, 22050)
			T.expect(buffer.readstring(wav, 0, 4)).toBe("RIFF")
			T.expect(buffer.readstring(wav, 8, 4)).toBe("WAVE")
			T.expect(buffer.readu32(wav, 24)).toBe(22050)
			T.expect(buffer.readu32(wav, 40)).toBe(6)
			T.expect(buffer.readi16(wav, 46)).toBe(math.round(0.5 * 32767))
		end
	)

	T.it(
		"громкости в профиле: по умолчанию, шаг, мусор отклоняется и не ломает старый профиль",
		function()
			local d = Profile.new()
			T.expect(d.sfx).toBe(Config.Audio.DefaultSfx)
			T.expect(d.music).toBe(Config.Audio.DefaultMusic)
			T.expect((Profile.setVolumes(d, 0.33, 1))).toBe(true)
			T.expect(d.sfx).toBeNear(0.3, 1e-9)
			T.expect(d.music).toBe(1)
			T.expect((Profile.setVolumes(d, 2, 0.5))).toBe(false)
			T.expect((Profile.setVolumes(d, "x", 0.5))).toBe(false)
			local old = Profile.migrate({ xp = 10 }) -- профиль до 10б
			T.expect(old.sfx).toBe(Config.Audio.DefaultSfx)
			local kept = Profile.migrate({ xp = 10, sfx = 0.2, music = 0 })
			T.expect(kept.sfx).toBeNear(0.2, 1e-9)
			T.expect(kept.music).toBe(0)
		end
	)
end)
