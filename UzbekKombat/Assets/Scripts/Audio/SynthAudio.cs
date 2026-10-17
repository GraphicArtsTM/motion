using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;

namespace UzbekKombat
{
    public enum Sfx
    {
        None, WhooshLight, WhooshHeavy, HitLight, HitHeavy, Slash, SlashHeavy, Block, Clang, Jump, Land, BodyFall,
        Projectile, Magic, Boom, Throw, Grab, Arrow, Water, Thunder, Wolf, Stars, Gong, DrumRoll, Crowd, CrowdBig,
        UIMove, UISelect, UIBack, Teleport, Whip, Shatter, Heartbeat
    }

    /// <summary>
    /// Barcha tovushlar protsedural sintez qilinadi: zarba, qilich, doira, karnay, surnay, dutar (Karplus-Strong).
    /// </summary>
    public class SynthAudio : MonoBehaviour
    {
        public static SynthAudio I { get; private set; }

        const int SR = 44100;
        const int MusicSR = 22050;

        readonly Dictionary<Sfx, List<AudioClip>> clips = new Dictionary<Sfx, List<AudioClip>>();
        readonly List<AudioSource> pool = new List<AudioSource>();
        AudioSource musicSource, musicSourceB;
        AudioClip battleMusic, menuMusic;
        Task<float[]> battleTask, menuTask;
        string wantMusic;
        float musicVolume = 0.5f;
        public float sfxVolume = 0.9f;
        public float MusicVolume { get => musicVolume; set { musicVolume = value; if (musicSource) musicSource.volume = value; } }

        static System.Random rng = new System.Random(1234);

        public static SynthAudio Create()
        {
            if (I) return I;
            var go = new GameObject("SynthAudio");
            DontDestroyOnLoad(go);
            I = go.AddComponent<SynthAudio>();
            I.Init();
            return I;
        }

        void Init()
        {
            for (int i = 0; i < 20; i++)
            {
                var s = gameObject.AddComponent<AudioSource>();
                s.playOnAwake = false;
                s.spatialBlend = 0;
                pool.Add(s);
            }
            musicSource = gameObject.AddComponent<AudioSource>();
            musicSource.loop = true;
            musicSource.volume = musicVolume;
            musicSource.playOnAwake = false;

            GenerateSfx();
            battleTask = Task.Run(() => MusicGen.Battle(MusicSR));
            menuTask = Task.Run(() => MusicGen.Menu(MusicSR));
        }

        void Update()
        {
            if (battleMusic == null && battleTask != null && battleTask.IsCompleted && battleTask.Exception == null)
            {
                battleMusic = MakeClip("music_battle", battleTask.Result, MusicSR);
                battleTask = null;
                if (wantMusic == "battle") PlayMusic("battle");
            }
            if (menuMusic == null && menuTask != null && menuTask.IsCompleted && menuTask.Exception == null)
            {
                menuMusic = MakeClip("music_menu", menuTask.Result, MusicSR);
                menuTask = null;
                if (wantMusic == "menu") PlayMusic("menu");
            }
        }

        public void PlayMusic(string which)
        {
            wantMusic = which;
            AudioClip c = which == "battle" ? battleMusic : which == "menu" ? menuMusic : null;
            if (c == null) { if (which == null) musicSource.Stop(); return; }
            if (musicSource.clip == c && musicSource.isPlaying) return;
            musicSource.clip = c;
            musicSource.volume = musicVolume;
            musicSource.Play();
        }

        public void SetMusicPitch(float p) { if (musicSource) musicSource.pitch = p; }

        public static void Play(Sfx s, float volume = 1f, float pitch = 1f, float pitchVar = 0.06f)
        {
            if (I == null || s == Sfx.None) return;
            I.PlayInternal(s, volume, pitch, pitchVar);
        }

        void PlayInternal(Sfx s, float volume, float pitch, float pitchVar)
        {
            if (!clips.TryGetValue(s, out var list) || list.Count == 0) return;
            AudioSource src = null;
            foreach (var p in pool) if (!p.isPlaying) { src = p; break; }
            if (src == null) src = pool[rng.Next(pool.Count)];
            src.clip = list[rng.Next(list.Count)];
            src.volume = volume * sfxVolume;
            src.pitch = pitch * (1f + ((float)rng.NextDouble() * 2 - 1) * pitchVar) * Mathf.Max(0.5f, Time.timeScale < 0.99f ? Mathf.Lerp(0.7f, 1f, Time.timeScale) : 1f);
            src.Play();
        }

        static AudioClip MakeClip(string name, float[] data, int sr)
        {
            var c = AudioClip.Create(name, data.Length, 1, sr, false);
            c.SetData(data, 0);
            return c;
        }

        void Add(Sfx s, string name, float[] data)
        {
            if (!clips.TryGetValue(s, out var l)) clips[s] = l = new List<AudioClip>();
            Normalize(data, 0.92f);
            l.Add(MakeClip(name, data, SR));
        }

        static void Normalize(float[] d, float peak)
        {
            float m = 0.0001f;
            for (int i = 0; i < d.Length; i++) m = Math.Max(m, Math.Abs(d[i]));
            float k = peak / m;
            for (int i = 0; i < d.Length; i++) d[i] *= k;
        }

        static float Rnd() => (float)rng.NextDouble() * 2f - 1f;

        // ======================= SFX generatsiyasi =======================
        void GenerateSfx()
        {
            for (int v = 0; v < 3; v++)
            {
                Add(Sfx.WhooshLight, "whoosh_l", Whoosh(0.18f, 1800 + v * 300, 0.6f));
                Add(Sfx.WhooshHeavy, "whoosh_h", Whoosh(0.32f, 900 + v * 200, 1f));
                Add(Sfx.HitLight, "hit_l", Punch(0.16f, 140 + v * 20, 0.6f));
                Add(Sfx.HitHeavy, "hit_h", Punch(0.3f, 90 + v * 12, 1f));
                Add(Sfx.Slash, "slash", SlashHit(0.25f, 0.6f, v));
                Add(Sfx.SlashHeavy, "slash_h", SlashHit(0.45f, 1f, v));
                Add(Sfx.Block, "block", BlockSound(v));
                Add(Sfx.Clang, "clang", Metal(0.5f, 520 + v * 60, 1f));
            }
            Add(Sfx.Jump, "jump", Whoosh(0.16f, 1200, 0.4f));
            Add(Sfx.Land, "land", Punch(0.18f, 70, 0.5f));
            Add(Sfx.BodyFall, "fall", BodyFall());
            Add(Sfx.Projectile, "proj", Sweep(0.4f, 300, 900, 0.5f, true));
            Add(Sfx.Magic, "magic", Shimmer(0.8f));
            Add(Sfx.Stars, "stars", Shimmer(1.2f, 1600));
            Add(Sfx.Boom, "boom", Boom(1.2f));
            Add(Sfx.Throw, "throw", Whoosh(0.4f, 700, 1f));
            Add(Sfx.Grab, "grab", Punch(0.12f, 200, 0.4f));
            Add(Sfx.Arrow, "arrow", ArrowSound());
            Add(Sfx.Water, "water", WaterSound());
            Add(Sfx.Thunder, "thunder", Thunder());
            Add(Sfx.Wolf, "wolf", WolfHowl());
            Add(Sfx.Gong, "gong", Gong());
            Add(Sfx.DrumRoll, "drumroll", DrumRoll());
            Add(Sfx.Crowd, "crowd", Crowd(1.2f, 0.6f));
            Add(Sfx.CrowdBig, "crowd_big", Crowd(3f, 1f));
            Add(Sfx.UIMove, "ui_move", Pluck(0.25f, 440f));
            Add(Sfx.UISelect, "ui_select", Chord(0.6f, new[] { 293.7f, 440f, 587.3f }));
            Add(Sfx.UIBack, "ui_back", Pluck(0.3f, 220f));
            Add(Sfx.Teleport, "teleport", Sweep(0.35f, 1600, 200, 0.6f, false));
            Add(Sfx.Whip, "whip", WhipCrack());
            Add(Sfx.Shatter, "shatter", Shatter());
            Add(Sfx.Heartbeat, "heart", Heartbeat());
        }

        static float[] Buf(float sec) => new float[(int)(sec * SR)];

        static float[] Whoosh(float dur, float cutoff, float amp)
        {
            var d = Buf(dur);
            float lp = 0, lp2 = 0;
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / d.Length;
                float env = Mathf.Sin(Mathf.PI * Mathf.Pow(t, 0.6f)) * amp;
                float fc = cutoff * (0.5f + t);
                float a = 1 - Mathf.Exp(-2 * Mathf.PI * fc / SR);
                lp += (Rnd() - lp) * a;
                lp2 += (lp - lp2) * a;
                d[i] = (lp - lp2 * 0.6f) * env * 2.5f;
            }
            return d;
        }

        static float[] Punch(float dur, float freq, float amp)
        {
            var d = Buf(dur);
            float phase = 0, lp = 0;
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR;
                float f = freq * (1 + 2.5f * Mathf.Exp(-t * 40));
                phase += 2 * Mathf.PI * f / SR;
                float body = Mathf.Sin(phase) * Mathf.Exp(-t * 18);
                lp += (Rnd() - lp) * 0.35f;
                float click = lp * Mathf.Exp(-t * 90) * 0.9f;
                float slap = Rnd() * Mathf.Exp(-t * 160) * 0.5f;
                d[i] = (body + click + slap) * amp;
            }
            return d;
        }

        static float[] SlashHit(float dur, float amp, int v)
        {
            var d = Buf(dur);
            var w = Whoosh(dur * 0.6f, 3000 + v * 400, 0.7f);
            var p = Punch(dur, 120 + v * 15, 0.8f);
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR;
                float ring = (Mathf.Sin(2 * Mathf.PI * (2400 + v * 200) * t) + 0.5f * Mathf.Sin(2 * Mathf.PI * 3710 * t)) * Mathf.Exp(-t * 30) * 0.25f;
                float ww = i < w.Length ? w[i] : 0;
                d[i] = (ww + p[i] * 0.8f + ring) * amp;
            }
            return d;
        }

        static float[] Metal(float dur, float f0, float amp)
        {
            var d = Buf(dur);
            float[] ratios = { 1f, 2.76f, 5.4f, 8.93f, 1.5f };
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR;
                float s = 0;
                for (int k = 0; k < ratios.Length; k++) s += Mathf.Sin(2 * Mathf.PI * f0 * ratios[k] * t) * Mathf.Exp(-t * (6 + k * 4)) / (k + 1);
                s += Rnd() * Mathf.Exp(-t * 120) * 0.6f;
                d[i] = s * amp;
            }
            return d;
        }

        static float[] BlockSound(int v)
        {
            var d = Buf(0.25f);
            var m = Metal(0.25f, 800 + v * 90, 0.5f);
            var p = Punch(0.25f, 160, 0.6f);
            for (int i = 0; i < d.Length; i++) d[i] = m[i] + p[i];
            return d;
        }

        static float[] BodyFall()
        {
            var d = Buf(0.6f);
            var a = Punch(0.6f, 60, 1f);
            float lp = 0;
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR;
                lp += (Rnd() - lp) * 0.08f;
                float dust = lp * Mathf.Exp(-t * 6) * 0.8f;
                d[i] = a[i] + dust;
            }
            // ikkinchi urilish (sakrash)
            int off = (int)(0.14f * SR);
            var b = Punch(0.3f, 75, 0.5f);
            for (int i = 0; i < b.Length && i + off < d.Length; i++) d[i + off] += b[i];
            return d;
        }

        static float[] Sweep(float dur, float f0, float f1, float amp, bool fizz)
        {
            var d = Buf(dur);
            float ph = 0;
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / d.Length;
                float f = Mathf.Lerp(f0, f1, t * t);
                ph += 2 * Mathf.PI * f / SR;
                float env = Mathf.Sin(Mathf.PI * Mathf.Min(1, t * 1.2f)) * (1 - t * 0.5f);
                float s = Mathf.Sin(ph) + 0.4f * Mathf.Sin(ph * 2.01f) + (fizz ? Rnd() * 0.3f : 0);
                d[i] = s * env * amp;
            }
            return d;
        }

        static float[] Shimmer(float dur, float baseF = 900)
        {
            var d = Buf(dur);
            var r = new System.Random(77);
            for (int n = 0; n < 24; n++)
            {
                int start = (int)(r.NextDouble() * d.Length * 0.6f);
                float f = baseF * (1 + (float)r.NextDouble() * 2.5f);
                for (int i = start; i < d.Length; i++)
                {
                    float t = (float)(i - start) / SR;
                    d[i] += Mathf.Sin(2 * Mathf.PI * f * t) * Mathf.Exp(-t * 7) * 0.2f;
                }
            }
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR;
                d[i] += Mathf.Sin(2 * Mathf.PI * (200 + 400 * t) * t) * Mathf.Exp(-t * 3) * 0.3f;
            }
            return d;
        }

        static float[] Boom(float dur)
        {
            var d = Buf(dur);
            float lp = 0, ph = 0;
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR;
                lp += (Rnd() - lp) * 0.04f;
                ph += 2 * Mathf.PI * (45 + 60 * Mathf.Exp(-t * 8)) / SR;
                d[i] = (Mathf.Sin(ph) * 1.2f + lp * 3f) * Mathf.Exp(-t * 3.2f) + Rnd() * Mathf.Exp(-t * 40) * 0.6f;
            }
            return d;
        }

        static float[] ArrowSound()
        {
            var d = Buf(0.45f);
            float ph = 0;
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR;
                ph += 2 * Mathf.PI * (2600 - 1800 * t) / SR;
                float whistle = Mathf.Sin(ph) * Mathf.Exp(-t * 6) * 0.35f;
                float twang = Mathf.Sin(2 * Mathf.PI * 110 * t) * Mathf.Exp(-t * 14) * (1 + 0.3f * Mathf.Sin(2 * Mathf.PI * 7 * t));
                d[i] = whistle + twang * 0.7f + Rnd() * Mathf.Exp(-t * 60) * 0.3f;
            }
            return d;
        }

        static float[] WaterSound()
        {
            var d = Buf(1.4f);
            float lp = 0;
            var r = new System.Random(5);
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR;
                lp += (Rnd() - lp) * 0.15f;
                d[i] = lp * Mathf.Exp(-t * 2.2f) * 1.2f;
            }
            for (int b = 0; b < 30; b++)
            {
                int st = (int)(r.NextDouble() * d.Length * 0.8f);
                float f = 400 + (float)r.NextDouble() * 900;
                for (int i = st; i < Mathf.Min(d.Length, st + SR / 20); i++)
                {
                    float t = (float)(i - st) / SR;
                    d[i] += Mathf.Sin(2 * Mathf.PI * f * (1 + t * 8) * t) * Mathf.Exp(-t * 60) * 0.25f;
                }
            }
            return d;
        }

        static float[] Thunder()
        {
            var d = Buf(2.2f);
            float lp = 0, lp2 = 0;
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR;
                lp += (Rnd() - lp) * 0.05f;
                lp2 += (lp - lp2) * 0.05f;
                float crack = Rnd() * Mathf.Exp(-t * 25);
                float rumble = lp2 * 6f * Mathf.Exp(-t * 1.6f) * (0.7f + 0.3f * Mathf.Sin(t * 13));
                d[i] = crack * 0.8f + rumble;
            }
            return d;
        }

        static float[] WolfHowl()
        {
            var d = Buf(1.8f);
            float ph = 0;
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / d.Length;
                float f = 380 + 260 * Mathf.Sin(Mathf.PI * Mathf.Min(1, t * 1.4f)) - 120 * t;
                f *= 1 + 0.015f * Mathf.Sin(2 * Mathf.PI * 5.5f * t * 1.8f);
                ph += 2 * Mathf.PI * f / SR;
                float env = Mathf.Sin(Mathf.PI * t) * Mathf.Min(1, t * 8);
                d[i] = (Mathf.Sin(ph) + 0.35f * Mathf.Sin(ph * 2) + 0.12f * Mathf.Sin(ph * 3) + Rnd() * 0.05f) * env;
            }
            return d;
        }

        static float[] Gong()
        {
            var d = Buf(2.5f);
            float[] ratios = { 1f, 1.52f, 2.31f, 2.9f, 3.7f, 4.95f };
            float f0 = 110;
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR;
                float s = 0;
                for (int k = 0; k < ratios.Length; k++)
                    s += Mathf.Sin(2 * Mathf.PI * f0 * ratios[k] * t + Mathf.Sin(t * 3 + k)) * Mathf.Exp(-t * (1.2f + k * 0.7f)) / (1 + k * 0.6f);
                s += Mathf.Sin(2 * Mathf.PI * 55 * t) * Mathf.Exp(-t * 4) * 0.8f;
                s += Rnd() * Mathf.Exp(-t * 50) * 0.4f;
                d[i] = s;
            }
            return d;
        }

        static float[] DrumRoll()
        {
            var d = Buf(1.2f);
            for (int n = 0; n < 16; n++)
            {
                int st = (int)(n * 0.06f * SR);
                var h = Punch(0.2f, 100 + n * 3, 0.4f + n * 0.04f);
                for (int i = 0; i < h.Length && st + i < d.Length; i++) d[st + i] += h[i];
            }
            var last = Punch(0.4f, 80, 1.3f);
            int s2 = (int)(0.96f * SR);
            for (int i = 0; i < last.Length && s2 + i < d.Length; i++) d[s2 + i] += last[i];
            return d;
        }

        static float[] Crowd(float dur, float amp)
        {
            var d = Buf(dur);
            float[] lps = new float[6];
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / d.Length;
                float env = Mathf.Sin(Mathf.PI * Mathf.Pow(t, 0.4f));
                float s = 0;
                for (int k = 0; k < lps.Length; k++)
                {
                    float a = 0.05f + k * 0.03f;
                    lps[k] += (Rnd() - lps[k]) * a;
                    float formant = Mathf.Sin(i * (0.0003f + k * 0.00011f) + k) * 0.5f + 0.5f;
                    s += lps[k] * formant;
                }
                d[i] = s * env * amp;
            }
            return d;
        }

        static float[] Pluck(float dur, float f) => MusicGen.KarplusStrong(SR, f, dur, 0.996f, 0.6f);

        static float[] Chord(float dur, float[] fs)
        {
            var d = Buf(dur);
            foreach (var f in fs)
            {
                var p = MusicGen.KarplusStrong(SR, f, dur, 0.997f, 0.5f);
                for (int i = 0; i < d.Length; i++) d[i] += p[i];
            }
            return d;
        }

        static float[] WhipCrack()
        {
            var d = Buf(0.3f);
            var w = Whoosh(0.2f, 2500, 0.6f);
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR;
                float crack = t > 0.17f ? Rnd() * Mathf.Exp(-(t - 0.17f) * 120) * 1.5f : 0;
                d[i] = (i < w.Length ? w[i] : 0) + crack;
            }
            return d;
        }

        static float[] Shatter()
        {
            var d = Buf(1.0f);
            var r = new System.Random(9);
            for (int n = 0; n < 40; n++)
            {
                int st = (int)(r.NextDouble() * d.Length * 0.5f);
                float f = 2000 + (float)r.NextDouble() * 5000;
                for (int i = st; i < Mathf.Min(d.Length, st + SR / 8); i++)
                {
                    float t = (float)(i - st) / SR;
                    d[i] += Mathf.Sin(2 * Mathf.PI * f * t) * Mathf.Exp(-t * 40) * 0.2f;
                }
            }
            var b = Boom(1f);
            for (int i = 0; i < d.Length; i++) d[i] += b[i] * 0.4f;
            return d;
        }

        static float[] Heartbeat()
        {
            var d = Buf(0.8f);
            var a = Punch(0.2f, 55, 1f);
            var b = Punch(0.2f, 50, 0.7f);
            for (int i = 0; i < a.Length; i++) d[i] += a[i];
            int off = (int)(0.22f * SR);
            for (int i = 0; i < b.Length && i + off < d.Length; i++) d[i + off] += b[i];
            return d;
        }
    }

    /// <summary>
    /// O'zbek xalq cholg'ulari ilhomidagi protsedural musiqa:
    /// doira (dum-tak), karnay (bas), surnay (kuy), dutar (Karplus-Strong).
    /// </summary>
    public static class MusicGen
    {
        // Hijoz ladi (D): D Eb F# G A Bb C D
        static readonly int[] Hijaz = { 0, 1, 4, 5, 7, 8, 10, 12, 13, 16, 17, 19 };
        // Dugoh/Bayot ilhomi (D dorian-ga yaqin)
        static readonly int[] Bayot = { 0, 2, 3, 5, 7, 9, 10, 12, 14, 15, 17, 19 };

        static float Midi(float m) => 440f * Mathf.Pow(2, (m - 69) / 12f);

        public static float[] KarplusStrong(int sr, float freq, float dur, float decay, float amp, int seed = 1)
        {
            int n = (int)(dur * sr);
            var outp = new float[n];
            int period = Mathf.Max(2, (int)(sr / freq));
            var buf = new float[period];
            var r = new System.Random(seed + (int)freq);
            for (int i = 0; i < period; i++) buf[i] = (float)(r.NextDouble() * 2 - 1) * amp;
            int idx = 0;
            float prev = 0;
            for (int i = 0; i < n; i++)
            {
                float v = buf[idx];
                float nv = (v + prev) * 0.5f * decay;
                prev = v;
                buf[idx] = nv;
                outp[i] = v;
                idx = (idx + 1) % period;
            }
            return outp;
        }

        static void Mix(float[] dst, float[] src, int at, float gain)
        {
            for (int i = 0; i < src.Length && at + i < dst.Length; i++)
                if (at + i >= 0) dst[at + i] += src[i] * gain;
        }

        static float[] Doum(int sr, float amp)
        {
            int n = (int)(0.35f * sr);
            var d = new float[n];
            float ph = 0;
            for (int i = 0; i < n; i++)
            {
                float t = (float)i / sr;
                ph += 2 * Mathf.PI * (75 + 70 * Mathf.Exp(-t * 30)) / sr;
                d[i] = Mathf.Sin(ph) * Mathf.Exp(-t * 9) * amp;
            }
            return d;
        }

        static float[] Tak(int sr, float amp, int seed)
        {
            int n = (int)(0.18f * sr);
            var d = new float[n];
            var r = new System.Random(seed);
            float hp = 0, prev = 0;
            for (int i = 0; i < n; i++)
            {
                float t = (float)i / sr;
                float noise = (float)(r.NextDouble() * 2 - 1);
                hp = 0.7f * (hp + noise - prev);
                prev = noise;
                float ring = Mathf.Sin(2 * Mathf.PI * 820 * t) * Mathf.Exp(-t * 45) * 0.6f;
                // doira halqalari (zang)
                float jingle = (float)(r.NextDouble() * 2 - 1) * Mathf.Exp(-t * 22) * 0.35f * (0.6f + 0.4f * Mathf.Sin(2 * Mathf.PI * 5200 * t));
                d[i] = (hp * Mathf.Exp(-t * 70) + ring + jingle) * amp;
            }
            return d;
        }

        /// <summary>Karnay — uzun mis cholg'u, arra to'lqin + vibrato + filtr.</summary>
        static float[] Karnay(int sr, float freq, float dur, float amp)
        {
            int n = (int)(dur * sr);
            var d = new float[n];
            float ph = 0, lp = 0;
            for (int i = 0; i < n; i++)
            {
                float t = (float)i / sr;
                float vib = 1 + 0.006f * Mathf.Sin(2 * Mathf.PI * 4.5f * t) * Mathf.Min(1, t);
                ph += freq * vib / sr;
                float saw = 2 * (ph - Mathf.Floor(ph + 0.5f));
                float env = Mathf.Min(1, t * 3f) * Mathf.Min(1, (dur - t) * 4f);
                float a = 0.08f + 0.12f * env;
                lp += (saw - lp) * a;
                d[i] = lp * env * amp;
            }
            return d;
        }

        /// <summary>Surnay — nayli, burunsimon ovoz.</summary>
        static float[] Surnay(int sr, float freq, float dur, float amp, float bendFrom = 0)
        {
            int n = (int)(dur * sr);
            var d = new float[n];
            float ph = 0, lp = 0;
            for (int i = 0; i < n; i++)
            {
                float t = (float)i / sr;
                float bend = bendFrom != 0 ? Mathf.Lerp(bendFrom, 1, Mathf.Min(1, t * 14)) : 1;
                float vib = 1 + 0.012f * Mathf.Sin(2 * Mathf.PI * 6f * t) * Mathf.Min(1, t * 3);
                ph += freq * bend * vib / sr;
                float x = ph - Mathf.Floor(ph);
                float pulse = x < 0.32f ? 1 : -0.45f;
                lp += (pulse - lp) * 0.3f;
                float env = Mathf.Min(1, t * 30) * Mathf.Min(1, (dur - t) * 25);
                d[i] = (lp + 0.3f * Mathf.Sin(ph * 2 * Mathf.PI * 3)) * env * amp;
            }
            return d;
        }

        public static float[] Battle(int sr)
        {
            float bpm = 132;
            float beat = 60f / bpm;
            int bars = 16;
            float len = bars * 4 * beat;
            var mix = new float[(int)(len * sr) + sr];
            var doum = Doum(sr, 0.9f);
            var tak = Tak(sr, 0.45f, 3);
            var takSoft = Tak(sr, 0.22f, 4);

            // Doira usuli (16-lik): D . t k D . t . D t . k D . t t
            string pattern = "D.tkD.t.Dt.kD.tt";
            for (int bar = 0; bar < bars; bar++)
            {
                for (int s = 0; s < 16; s++)
                {
                    int at = (int)((bar * 4 * beat + s * beat / 4) * sr);
                    char c = pattern[s];
                    if (bar % 4 == 3 && s >= 12) c = 't'; // o'tish (fill)
                    if (c == 'D') Mix(mix, doum, at, 1f);
                    else if (c == 't') Mix(mix, tak, at, 1f);
                    else if (c == 'k') Mix(mix, takSoft, at, 1f);
                }
            }

            // Karnay — har 4 taktda kuchli nidolar
            float root = Midi(38); // D2
            for (int bar = 0; bar < bars; bar += 4)
            {
                Mix(mix, Karnay(sr, root * 2, beat * 3.5f, 0.35f), (int)(bar * 4 * beat * sr), 1f);
                Mix(mix, Karnay(sr, root * 3, beat * 1.5f, 0.25f), (int)((bar * 4 + 6) * beat * sr), 1f);
                Mix(mix, Karnay(sr, root * 2, beat * 1.5f, 0.3f), (int)((bar * 4 + 8) * beat * sr), 1f);
            }

            // Dutar ostinato (8-lik)
            int[] ost = { 0, 7, 12, 7, 5, 7, 4, 7 };
            for (int bar = 0; bar < bars; bar++)
                for (int e = 0; e < 8; e++)
                {
                    int at = (int)((bar * 4 * beat + e * beat / 2) * sr);
                    int shift = (bar / 4) % 2 == 1 && e >= 4 ? -2 : 0;
                    var p = KarplusStrong(sr, Midi(50 + ost[e] + shift), beat * 0.9f, 0.994f, 0.5f, bar * 8 + e);
                    Mix(mix, p, at, 0.55f);
                }

            // Surnay kuyi (Hijoz)
            int[][] phrases =
            {
                new[] { 4, 4, 5, 4, 3, 2, 3, 4,   5, 6, 5, 4, 3, 2, 1, 0 },
                new[] { 7, 7, 8, 7, 6, 5, 6, 7,   8, 9, 8, 7, 5, 4, 3, 4 },
                new[] { 4, 5, 6, 7, 6, 5, 4, 3,   4, 3, 2, 1, 2, 1, 0, 0 },
                new[] { 7, 6, 5, 4, 5, 6, 7, 8,   7, 5, 4, 3, 2, 1, 0, -1 },
            };
            for (int bar = 4; bar < bars; bar += 2)
            {
                var ph = phrases[((bar - 4) / 2) % phrases.Length];
                for (int e = 0; e < 16; e++)
                {
                    if (ph[e] < 0) continue;
                    if (e > 0 && ph[e] == ph[e - 1] && e % 4 == 1) continue;
                    int deg = ph[e];
                    int semis = Hijaz[Mathf.Clamp(deg, 0, Hijaz.Length - 1)];
                    float f = Midi(62 + semis);
                    float dur = beat / 2 * (e % 4 == 3 ? 1.6f : 0.95f);
                    int at = (int)((bar * 4 * beat + e * beat / 2) * sr);
                    Mix(mix, Surnay(sr, f, dur, 0.22f, e % 4 == 0 ? 0.94f : 0), at, 1f);
                }
            }

            // Yakun: halqa uchun tozalash va kompressiya
            var outp = new float[(int)(len * sr)];
            for (int i = 0; i < outp.Length; i++) outp[i] = mix[i];
            // Halqani silliq ulash: oxirgi qism boshiga qo'shiladi
            int tail = mix.Length - outp.Length;
            for (int i = 0; i < tail && i < outp.Length; i++) outp[i] += mix[outp.Length + i];
            SoftClip(outp, 0.8f);
            return outp;
        }

        public static float[] Menu(int sr)
        {
            float bpm = 84;
            float beat = 60f / bpm;
            int bars = 12;
            float len = bars * 4 * beat;
            var mix = new float[(int)(len * sr) + sr * 2];
            var doum = Doum(sr, 0.5f);
            var tak = Tak(sr, 0.18f, 11);
            // 6/8 ga yaqin "lazgi" ritmi soddalashtirilgan
            for (int bar = 0; bar < bars; bar++)
            {
                Mix(mix, doum, (int)((bar * 4) * beat * sr), 1f);
                Mix(mix, tak, (int)((bar * 4 + 1.5f) * beat * sr), 1f);
                Mix(mix, doum, (int)((bar * 4 + 2) * beat * sr), 0.6f);
                Mix(mix, tak, (int)((bar * 4 + 3) * beat * sr), 1f);
                Mix(mix, tak, (int)((bar * 4 + 3.5f) * beat * sr), 0.6f);
            }
            // Dutar kuyi (Bayot)
            int[] melody = { 0, 2, 3, 4, 3, 2, 3, 1,   2, 3, 4, 5, 4, 3, 2, 0,   4, 5, 6, 7, 6, 5, 4, 3,   2, 3, 4, 3, 2, 1, 0, 0 };
            for (int bar = 0; bar < bars; bar++)
            {
                for (int e = 0; e < 8; e++)
                {
                    int idx = (bar % 4) * 8 + e;
                    int deg = melody[idx];
                    float f = Midi(62 + Bayot[deg]);
                    int at = (int)((bar * 4 + e * 0.5f) * beat * sr);
                    Mix(mix, KarplusStrong(sr, f, beat * 1.5f, 0.997f, 0.5f, idx), at, 0.6f);
                    if (e % 2 == 0) Mix(mix, KarplusStrong(sr, Midi(50), beat, 0.995f, 0.4f, idx + 100), at, 0.35f); // bo'g'in tori (drone)
                }
            }
            // Yumshoq karnay fon
            for (int bar = 0; bar < bars; bar += 4)
                Mix(mix, Karnay(sr, Midi(38), beat * 15f, 0.12f), (int)(bar * 4 * beat * sr), 1f);

            var outp = new float[(int)(len * sr)];
            for (int i = 0; i < outp.Length; i++) outp[i] = mix[i];
            int tail = mix.Length - outp.Length;
            for (int i = 0; i < tail && i < outp.Length; i++) outp[i] += mix[outp.Length + i];
            SoftClip(outp, 0.7f);
            return outp;
        }

        static void SoftClip(float[] d, float target)
        {
            float m = 0.0001f;
            for (int i = 0; i < d.Length; i++) m = Mathf.Max(m, Mathf.Abs(d[i]));
            float k = 1.6f / m;
            for (int i = 0; i < d.Length; i++) d[i] = (float)Math.Tanh(d[i] * k) * target;
        }
    }
}
