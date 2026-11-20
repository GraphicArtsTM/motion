using System.Collections.Generic;
using UnityEngine;

// Every sound of the game and both music tracks are synthesized in code at start-up (no audio files).
//
// The building blocks: oscillators with pitch glides and vibrato, FM bells (coins, gems, chimes), a
// state-variable filter on noise (whooshes, wind, crunches, crashes), low-passed saw "brass" (fanfares,
// bass, the lead), Karplus-Strong plucked strings (lute and harp), synthesized drums and a small
// Schroeder reverb. The music reverb "wraps around", so the loops have no seam.
public static class SynthAudio
{
    public const int Rate = 22050;
    const float TwoPi = Mathf.PI * 2f;
    // each thread has its own generator (the music is synthesized on a background thread)
    [System.ThreadStatic] static System.Random rngT;
    static System.Random rng { get { return rngT ?? (rngT = new System.Random(20261120)); } }

    static float[] menuData, gameData;
    static volatile bool musicDone;
    static string musicError;

    // the original set (names kept: the rest of the game and the guide's scripts use them)
    public static AudioClip Coin, Gem, PowerUp, Hit, Thud, Checkpoint, Beep, Go, Click, Jump, Land, Shield, Combo, Music;

    // the full set
    public static AudioClip MenuMusic, Apple, Magnet, ShieldBreak, Slide, Whoosh, Turn, Crash, Stumble,
                            GolemRoar, GolemStep, SpeedUp, Select, Back, GameOver, Victory, Record, Wind;
    public static AudioClip[] Steps, Birds;

    public static void Init()
    {
        if (Coin != null) return;
        float started = Time.realtimeSinceStartup;

        Coin = Make("Coin", Finish(BuildCoin(), 0.85f));
        Gem = Make("Gem", Finish(BuildGem(), 0.85f));
        Combo = Make("Combo", Finish(BuildCombo(), 0.8f));
        PowerUp = Make("PowerUp", Finish(BuildPowerUp(), 0.85f));
        Apple = Make("Apple", Finish(BuildApple(), 0.85f));
        Magnet = Make("Magnet", Finish(BuildMagnet(), 0.8f));
        Shield = Make("Shield", Finish(BuildShield(), 0.85f));
        ShieldBreak = Make("ShieldBreak", Finish(BuildShieldBreak(), 0.9f));

        Jump = Make("Jump", Finish(BuildJump(), 0.75f));
        Land = Make("Land", Finish(BuildLand(), 0.8f));
        Slide = Make("Slide", Finish(BuildSlide(), 0.75f));
        Whoosh = Make("Whoosh", Finish(BuildWhoosh(0.17f, 600f, 1700f), 0.7f));
        Turn = Make("Turn", Finish(BuildTurn(), 0.8f));
        Steps = new AudioClip[4];
        for (int i = 0; i < Steps.Length; i++) Steps[i] = Make("Step" + i, Finish(BuildStep(i), 0.7f));

        Hit = Make("Hit", Finish(BuildHit(), 0.95f));
        Thud = Make("Thud", Finish(BuildThud(), 0.9f));
        Crash = Make("Crash", Finish(BuildCrash(), 0.95f));
        Stumble = Make("Stumble", Finish(BuildStumble(), 0.8f));
        GolemRoar = Make("GolemRoar", Finish(BuildGolemRoar(), 0.9f));
        GolemStep = Make("GolemStep", Finish(BuildGolemStep(), 0.9f));
        SpeedUp = Make("SpeedUp", Finish(BuildSpeedUp(), 0.75f));
        Checkpoint = Make("Checkpoint", Finish(BuildCheckpoint(), 0.85f));

        Beep = Make("Beep", Finish(BuildBeep(), 0.75f));
        Go = Make("Go", Finish(BuildGo(), 0.85f));
        Click = Make("Click", Finish(BuildClick(), 0.6f));
        Select = Make("Select", Finish(BuildSelect(), 0.7f));
        Back = Make("Back", Finish(BuildBack(), 0.7f));
        GameOver = Make("GameOver", Finish(BuildGameOver(), 0.85f));
        Victory = Make("Victory", Finish(BuildVictory(), 0.85f));
        Record = Make("Record", Finish(BuildRecord(), 0.85f));

        Wind = Make("Wind", Normalize(BuildWind(), 0.8f));
        Birds = new AudioClip[3];
        for (int i = 0; i < Birds.Length; i++) Birds[i] = Make("Bird" + i, Finish(BuildBird(i), 0.7f));

        // the music takes longer: it is made on a background thread, so the game starts at once
        System.Threading.Thread worker = new System.Threading.Thread(() =>
        {
            try
            {
                menuData = BuildMenuMusic();
                gameData = BuildGameMusic();
            }
            catch (System.Exception e) { musicError = e.ToString(); }
            musicDone = true;
        });
        worker.IsBackground = true;
        worker.Start();

        Debug.Log("Royal Run: sounds synthesized in " + Mathf.RoundToInt((Time.realtimeSinceStartup - started) * 1000f) + " ms");
    }

    // Called every frame from the main thread: turns the finished music into clips. True when done.
    public static bool PollMusic()
    {
        if (!musicDone) return false;
        if (menuData != null) { MenuMusic = Make("MenuMusic", menuData); menuData = null; }
        if (gameData != null) { Music = Make("Music", gameData); gameData = null; }
        if (musicError != null) { Debug.LogWarning("Royal Run: music synthesis failed: " + musicError); musicError = null; }
        return true;
    }

    static AudioClip Make(string name, float[] data)
    {
        AudioClip clip = AudioClip.Create("RR " + name, data.Length, 1, Rate, false);
        clip.SetData(data, 0);
        return clip;
    }

    // ==================================================================
    //  Building blocks
    // ==================================================================

    static float[] Buf(float seconds)
    {
        return new float[Mathf.Max(1, Mathf.CeilToInt(seconds * Rate))];
    }

    static float Rnd()
    {
        return (float)(rng.NextDouble() * 2.0 - 1.0);
    }

    static float Rnd(float a, float b)
    {
        return a + (float)rng.NextDouble() * (b - a);
    }

    static float Midi(int note)
    {
        return 440f * Mathf.Pow(2f, (note - 69) / 12f);
    }

    // wave: 0 sine, 1 square, 2 triangle, 3 saw, 4 narrow pulse
    static float Osc(int wave, float ph)
    {
        float x = ph - Mathf.Floor(ph);
        switch (wave)
        {
            case 1: return x < 0.5f ? 0.7f : -0.7f;
            case 2: return 4f * Mathf.Abs(x - 0.5f) - 1f;
            case 3: return 2f * x - 1f;
            case 4: return x < 0.25f ? 0.75f : -0.25f;
            default: return Mathf.Sin(x * TwoPi);
        }
    }

    static float Fall(float t, float k)
    {
        float u = 1f - t;
        if (k == 1f) return u;
        if (k == 2f) return u * u;
        if (k == 3f) return u * u * u;
        return Mathf.Pow(u, k);
    }

    // A tone gliding from f0 to f1, with a quick attack and a decay of the given steepness.
    static void Tone(float[] d, float start, float dur, float f0, float f1, int wave, float vol,
                     float attack = 0.004f, float decay = 2f, float vibHz = 0f, float vibDepth = 0f)
    {
        int s0 = (int)(start * Rate), n = (int)(dur * Rate);
        float ph = 0f, atk = Mathf.Max(1f, attack * Rate);
        for (int i = 0; i < n && s0 + i < d.Length; i++)
        {
            if (s0 + i < 0) continue;
            float t = i / (float)n;
            float f = f0 + (f1 - f0) * t;
            if (vibHz > 0f) f *= 1f + vibDepth * Mathf.Sin(TwoPi * vibHz * i / Rate);
            ph += f / Rate;
            d[s0 + i] += Osc(wave, ph) * Mathf.Min(1f, i / atk) * Fall(t, decay) * vol;
        }
    }

    // An FM bell: bright at the strike, mellowing as it rings (coins, gems, chimes).
    static void Bell(float[] d, float start, float dur, float freq, float vol, float ratio = 3.5f, float index = 2f, float decay = 6f)
    {
        int s0 = (int)(start * Rate), n = (int)(dur * Rate);
        float pc = 0f, pm = 0f, e = 1f, k = Mathf.Exp(-decay / Rate);
        for (int i = 0; i < n && s0 + i < d.Length; i++)
        {
            float tail = i > n - 200 ? (n - i) / 200f : 1f;
            pc += freq / Rate;
            pm += freq * ratio / Rate;
            float v = Mathf.Sin(TwoPi * pc + index * e * Mathf.Sin(TwoPi * pm));
            d[s0 + i] += v * e * vol * Mathf.Min(1f, i / 30f) * tail;
            e *= k;
        }
    }

    // Noise through a state-variable filter (mode 0 low-pass, 1 band-pass, 2 high-pass).
    // The cutoff glides from f0 to f1; the envelope rises during "attack" (0..1 of the length), then falls.
    static void Noise(float[] d, float start, float dur, float vol, int mode, float f0, float f1,
                      float q = 1f, float attack = 0.01f, float decay = 2f)
    {
        int s0 = (int)(start * Rate), n = (int)(dur * Rate);
        float low = 0f, band = 0f, damp = 1f / Mathf.Max(0.7f, q);
        for (int i = 0; i < n && s0 + i < d.Length; i++)
        {
            float t = i / (float)n;
            float fc = Mathf.Clamp(f0 + (f1 - f0) * t, 30f, 6000f);
            float f = 2f * Mathf.Sin(Mathf.PI * fc / (Rate * 2f));       // the filter runs twice per sample
            float input = Rnd(), high = 0f;
            for (int k = 0; k < 2; k++)
            {
                low += f * band;
                high = input - low - damp * band;
                band += f * high;
            }
            float o = mode == 0 ? low : mode == 1 ? band : high;
            float env = t < attack ? t / attack : Fall((t - attack) / (1f - attack + 1e-5f), decay);
            d[s0 + i] += o * env * vol;
        }
    }

    // A low-passed saw: brass for fanfares and the lead, or a round bass.
    static void Brass(float[] d, float start, float dur, float freq, float vol, float bright = 2200f,
                      float attack = 0.025f, float vib = 0.006f, int voices = 2)
    {
        int s0 = (int)(start * Rate), n = (int)(dur * Rate);
        float[] ph = new float[voices];
        for (int v = 0; v < voices; v++) ph[v] = (float)rng.NextDouble();
        float l1 = 0f, l2 = 0f, a = 0f;
        int atk = Mathf.Max(1, (int)(attack * Rate)), rel = Mathf.Min(n / 3, (int)(0.08f * Rate));
        for (int i = 0; i < n && s0 + i < d.Length; i++)
        {
            float time = i / (float)Rate;
            float amp = i < atk ? i / (float)atk : (i > n - rel ? (n - i) / (float)rel : 1f - 0.2f * Mathf.Clamp01((i - atk) / (0.3f * Rate)));
            float vibr = vib > 0f ? 1f + vib * Mathf.Sin(TwoPi * 5.5f * time) * Mathf.Clamp01(time * 4f - 0.6f) : 1f;
            float s = 0f;
            for (int v = 0; v < voices; v++)
            {
                ph[v] += freq * vibr * (1f + (v - (voices - 1) * 0.5f) * 0.004f) / Rate;
                s += Osc(3, ph[v]);
            }
            s /= voices;
            if ((i & 15) == 0)
            {
                float fc = Mathf.Min(5000f, freq + bright * (i < atk * 2 ? 1f : 0.55f + 0.45f * Mathf.Exp(-(i - atk * 2) / (0.25f * Rate))));
                a = 1f - Mathf.Exp(-TwoPi * fc / Rate);
            }
            l1 += (s - l1) * a;
            l2 += (l1 - l2) * a;
            d[s0 + i] += l2 * amp * vol;
        }
    }

    // A plucked string (Karplus-Strong): lute and harp.
    static void Pluck(float[] d, float start, float dur, float freq, float vol, float bright = 0.6f, float sustain = 0.996f)
    {
        int s0 = (int)(start * Rate), n = (int)(dur * Rate);
        int len = Mathf.Max(2, Mathf.RoundToInt(Rate / freq));
        float[] line = new float[len];
        float last = 0f;
        for (int k = 0; k < len; k++)
        {
            last += (Rnd() - last) * bright;
            line[k] = last;
        }
        int idx = 0;
        for (int i = 0; i < n && s0 + i < d.Length; i++)
        {
            int nx = idx + 1 == len ? 0 : idx + 1;
            float v = line[idx];
            line[idx] = sustain * 0.5f * (v + line[nx]);
            idx = nx;
            float tail = i > n - 300 ? (n - i) / 300f : 1f;
            d[s0 + i] += v * vol * tail;
        }
    }

    // A soft breathy flute: sine with vibrato and a little air.
    static void Flute(float[] d, float start, float dur, float freq, float vol)
    {
        int s0 = (int)(start * Rate), n = (int)(dur * Rate);
        float ph = 0f, air = 0f;
        int atk = (int)(0.06f * Rate), rel = Mathf.Min(n / 3, (int)(0.1f * Rate));
        for (int i = 0; i < n && s0 + i < d.Length; i++)
        {
            float time = i / (float)Rate;
            float amp = i < atk ? i / (float)atk : (i > n - rel ? (n - i) / (float)rel : 1f);
            ph += freq * (1f + 0.007f * Mathf.Sin(TwoPi * 5f * time) * Mathf.Clamp01(time * 3f)) / Rate;
            air += (Rnd() - air) * 0.3f;
            float x = ph - Mathf.Floor(ph);
            float s = Mathf.Sin(x * TwoPi) + 0.18f * Mathf.Sin(x * TwoPi * 2f) + air * 0.12f;
            d[s0 + i] += s * amp * vol;
        }
    }

    // ---------- drums ----------

    static void Kick(float[] d, float start, float vol = 0.55f)
    {
        int s0 = (int)(start * Rate), n = (int)(0.22f * Rate);
        float ph = 0f;
        for (int i = 0; i < n && s0 + i < d.Length; i++)
        {
            float time = i / (float)Rate;
            ph += (45f + 110f * Mathf.Exp(-time * 28f)) / Rate;
            float env = Mathf.Exp(-time * 13f);
            d[s0 + i] += (Mathf.Sin(TwoPi * ph) * env + (i < 60 ? Rnd() * 0.3f * (1f - i / 60f) : 0f)) * vol;
        }
    }

    static void Snare(float[] d, float start, float vol = 0.32f)
    {
        Noise(d, start, 0.19f, vol, 1, 2600f, 1800f, 0.8f, 0.01f, 2.5f);
        Noise(d, start, 0.12f, vol * 0.5f, 2, 4000f, 4000f, 1f, 0.01f, 2f);
        Tone(d, start, 0.09f, 200f, 170f, 2, vol * 0.6f, 0.001f, 2f);
    }

    static void Hat(float[] d, float start, float vol = 0.12f, float len = 0.045f)
    {
        Noise(d, start, len, vol, 2, 5500f, 5500f, 1.2f, 0.02f, 2.5f);
    }

    static void Tom(float[] d, float start, float pitch, float vol = 0.4f)
    {
        int s0 = (int)(start * Rate), n = (int)(0.4f * Rate);
        float ph = 0f;
        for (int i = 0; i < n && s0 + i < d.Length; i++)
        {
            float time = i / (float)Rate;
            ph += pitch * (1f + 0.5f * Mathf.Exp(-time * 20f)) / Rate;
            d[s0 + i] += Mathf.Sin(TwoPi * ph) * Mathf.Exp(-time * 8f) * vol;
        }
        Noise(d, start, 0.08f, vol * 0.4f, 0, 900f, 400f, 1f, 0.02f, 2f);
    }

    static void Tambourine(float[] d, float start, float vol = 0.08f)
    {
        Noise(d, start, 0.12f, vol, 2, 5000f, 5800f, 2f, 0.03f, 2.5f);
        Bell(d, start, 0.1f, 5200f, vol * 0.3f, 1.41f, 1f, 30f);
    }

    // ---------- reverb and finishing ----------

    // A small Schroeder reverb. wrap = true: the tail of the end flows into the start (a seamless loop).
    static float[] Reverb(float[] d, float mix, float room = 0.8f, float tail = 1f, bool wrap = false)
    {
        int[] combLen = { 558, 594, 638, 678 };
        int[] apLen = { 278, 220 };
        float[][] comb = new float[4][];
        int[] ci = new int[4];
        float[] cf = new float[4];
        for (int k = 0; k < 4; k++) comb[k] = new float[combLen[k]];
        float[][] ap = { new float[apLen[0]], new float[apLen[1]] };
        int[] ai = new int[2];

        int len = d.Length;
        int outLen = wrap ? len : len + (int)(tail * Rate);
        float[] o = new float[outLen];
        int total = wrap ? len * 2 : outLen;
        for (int i = 0; i < total; i++)
        {
            float x = wrap ? d[i % len] : (i < len ? d[i] : 0f);
            float s = 0f;
            for (int k = 0; k < 4; k++)
            {
                float y = comb[k][ci[k]];
                cf[k] = y * 0.75f + cf[k] * 0.25f;         // damping: the echoes get darker
                comb[k][ci[k]] = x * 0.25f + cf[k] * room;
                ci[k] = (ci[k] + 1) % combLen[k];
                s += y;
            }
            for (int k = 0; k < 2; k++)
            {
                float b = ap[k][ai[k]];
                float y = -s + b;
                ap[k][ai[k]] = s + b * 0.5f;
                ai[k] = (ai[k] + 1) % apLen[k];
                s = y;
            }
            if (wrap)
            {
                if (i >= len) o[i - len] = x + s * mix;
            }
            else o[i] = x + s * mix;
        }
        return o;
    }

    static float[] Normalize(float[] d, float peak)
    {
        float m = 0.0001f;
        for (int i = 0; i < d.Length; i++) m = Mathf.Max(m, Mathf.Abs(d[i]));
        float g = peak / m;
        for (int i = 0; i < d.Length; i++) d[i] *= g;
        return d;
    }

    // Normalizes and trims the silent end.
    static float[] Finish(float[] d, float peak)
    {
        Normalize(d, peak);
        int end = d.Length;
        while (end > 1 && Mathf.Abs(d[end - 1]) < 0.002f) end--;
        end = Mathf.Min(d.Length, end + 64);
        if (end < d.Length) System.Array.Resize(ref d, end);
        int fade = Mathf.Min(64, d.Length);
        for (int i = 0; i < fade; i++) d[d.Length - 1 - i] *= i / (float)fade;
        return d;
    }

    // ==================================================================
    //  Pick-ups
    // ==================================================================

    static float[] BuildCoin()
    {
        float[] d = Buf(0.5f);
        Bell(d, 0f, 0.09f, 1318.5f, 0.5f, 2f, 1.2f, 18f);
        Bell(d, 0.065f, 0.42f, 1975.5f, 0.55f, 2f, 1.5f, 7f);
        Bell(d, 0.065f, 0.3f, 3951f, 0.08f, 1f, 0f, 12f);
        return Reverb(d, 0.12f, 0.7f, 0.3f);
    }

    static float[] BuildGem()
    {
        float[] d = Buf(0.9f);
        int[] notes = { 88, 92, 95, 100 };
        for (int i = 0; i < notes.Length; i++)
            Bell(d, i * 0.055f, 0.6f, Midi(notes[i]), 0.35f, 3.01f, 1.8f, 6f);
        Noise(d, 0f, 0.5f, 0.05f, 2, 5000f, 6000f, 2f, 0.1f, 2f);
        return Reverb(d, 0.3f, 0.8f, 0.6f);
    }

    static float[] BuildCombo()
    {
        float[] d = Buf(0.5f);
        Bell(d, 0f, 0.3f, Midi(91), 0.45f, 2f, 1.3f, 9f);
        Bell(d, 0.07f, 0.4f, Midi(98), 0.45f, 2f, 1.3f, 7f);
        Bell(d, 0.07f, 0.4f, Midi(103), 0.12f, 1f, 0f, 9f);
        return Reverb(d, 0.2f, 0.75f, 0.4f);
    }

    // the hourglass / generic bonus: a rising sweep, then sparkles
    static float[] BuildPowerUp()
    {
        float[] d = Buf(0.8f);
        Tone(d, 0f, 0.35f, 330f, 1320f, 4, 0.22f, 0.01f, 0.6f, 9f, 0.03f);
        Tone(d, 0f, 0.35f, 165f, 660f, 2, 0.25f, 0.01f, 0.8f);
        int[] notes = { 84, 88, 91, 96 };
        for (int i = 0; i < notes.Length; i++) Bell(d, 0.3f + i * 0.045f, 0.4f, Midi(notes[i]), 0.3f, 2f, 1f, 8f);
        return Reverb(d, 0.25f, 0.78f, 0.5f);
    }

    // a crunchy bite and a happy blip
    static float[] BuildApple()
    {
        float[] d = Buf(0.45f);
        for (int i = 0; i < 4; i++)
            Noise(d, i * 0.035f, 0.05f, 0.6f - i * 0.1f, 1, 2600f - i * 300f, 1200f, 1.5f, 0.05f, 2f);
        Tone(d, 0f, 0.07f, 190f, 90f, 0, 0.5f, 0.002f, 2f);
        Tone(d, 0.16f, 0.13f, 880f, 1320f, 2, 0.28f, 0.005f, 1.5f);
        Tone(d, 0.24f, 0.15f, 1320f, 1760f, 2, 0.22f, 0.005f, 2f);
        return d;
    }

    // the magnet: a wobbling electric hum that rises
    static float[] BuildMagnet()
    {
        float[] d = Buf(0.7f);
        int n = (int)(0.6f * Rate);
        float ph = 0f, ph2 = 0f;
        for (int i = 0; i < n; i++)
        {
            float t = i / (float)n;
            float wob = Mathf.Sin(TwoPi * Mathf.Lerp(8f, 18f, t) * i / Rate);
            float f = Mathf.Lerp(200f, 520f, t) * (1f + 0.12f * wob);
            ph += f / Rate;
            ph2 += f * 2.01f / Rate;
            float env = Mathf.Min(1f, t * 12f) * Fall(t, 1.5f);
            d[i] += (Osc(1, ph) * 0.25f + Mathf.Sin(TwoPi * ph2) * 0.3f) * env;
        }
        Bell(d, 0.45f, 0.25f, 1568f, 0.25f, 2f, 1f, 10f);
        return Reverb(d, 0.15f, 0.7f, 0.3f);
    }

    // the shield: a shimmering chord rising into place
    static float[] BuildShield()
    {
        float[] d = Buf(1f);
        int[] notes = { 72, 76, 79, 84, 88 };
        for (int i = 0; i < notes.Length; i++)
            Bell(d, i * 0.04f, 0.8f, Midi(notes[i]), 0.22f, 1.5f, 1.2f, 4f);
        Tone(d, 0f, 0.4f, 300f, 900f, 2, 0.18f, 0.02f, 1f);
        Noise(d, 0f, 0.6f, 0.12f, 1, 2500f, 5000f, 3f, 0.3f, 1.5f);
        return Reverb(d, 0.35f, 0.82f, 0.6f);
    }

    // the shield breaks: glass shatter
    static float[] BuildShieldBreak()
    {
        float[] d = Buf(0.8f);
        Noise(d, 0f, 0.45f, 0.6f, 2, 4500f, 3000f, 1f, 0.005f, 3f);
        for (int i = 0; i < 9; i++)
            Bell(d, Rnd(0f, 0.25f), 0.3f, Rnd(2200f, 4800f), Rnd(0.08f, 0.18f), 2.7f, 1f, Rnd(10f, 20f));
        Tone(d, 0f, 0.15f, 160f, 70f, 0, 0.5f, 0.002f, 2f);
        return Reverb(d, 0.25f, 0.75f, 0.4f);
    }

    // ==================================================================
    //  Running
    // ==================================================================

    static float[] BuildJump()
    {
        float[] d = Buf(0.3f);
        Noise(d, 0f, 0.24f, 0.7f, 1, 400f, 1700f, 1.6f, 0.35f, 1.5f);
        Tone(d, 0f, 0.09f, 200f, 330f, 2, 0.25f, 0.005f, 2f);
        return d;
    }

    static float[] BuildLand()
    {
        float[] d = Buf(0.2f);
        Noise(d, 0f, 0.12f, 0.8f, 0, 900f, 250f, 1f, 0.02f, 2.5f);
        Tone(d, 0f, 0.1f, 120f, 55f, 0, 0.6f, 0.002f, 2f);
        return d;
    }

    static float[] BuildSlide()
    {
        float[] d = Buf(0.55f);
        Noise(d, 0f, 0.5f, 0.6f, 1, 1100f, 450f, 1.2f, 0.08f, 1.3f);
        Noise(d, 0f, 0.45f, 0.35f, 0, 500f, 200f, 1f, 0.05f, 1.5f);
        // grit: little ticks of gravel
        for (int i = 0; i < 12; i++) Noise(d, Rnd(0.02f, 0.4f), 0.012f, Rnd(0.1f, 0.25f), 2, 3500f, 3500f, 1f, 0.1f, 2f);
        return d;
    }

    // a swish past the ear (lane change)
    static float[] BuildWhoosh(float dur, float f0, float f1)
    {
        float[] d = Buf(dur + 0.02f);
        Noise(d, 0f, dur, 0.8f, 1, f0, f1, 1.8f, 0.45f, 1.6f);
        return d;
    }

    static float[] BuildTurn()
    {
        float[] d = Buf(0.5f);
        Noise(d, 0f, 0.42f, 0.8f, 1, 300f, 1500f, 1.5f, 0.4f, 1.4f);
        Noise(d, 0.05f, 0.35f, 0.3f, 0, 400f, 200f, 1f, 0.3f, 1.5f);
        Tone(d, 0.08f, 0.15f, 90f, 60f, 0, 0.3f, 0.01f, 2f);
        return d;
    }

    // footsteps on cobbles and earth: four slightly different ones
    static float[] BuildStep(int v)
    {
        float[] d = Buf(0.1f);
        Noise(d, 0f, 0.06f, 0.7f, 0, 1300f + v * 180f, 300f, 1f, 0.03f, 2.5f);
        Tone(d, 0f, 0.05f, 105f + v * 9f, 60f, 0, 0.5f, 0.001f, 2f);
        Noise(d, 0.006f, 0.02f, 0.15f, 2, 3000f, 3000f, 1f, 0.1f, 2f);
        return d;
    }

    // ==================================================================
    //  Hits
    // ==================================================================

    // running into something: a wooden crack and a body thump
    static float[] BuildHit()
    {
        float[] d = Buf(0.5f);
        Noise(d, 0f, 0.07f, 0.9f, 2, 3000f, 2000f, 1f, 0.01f, 2.5f);
        Bell(d, 0f, 0.18f, 420f, 0.35f, 1.62f, 1.4f, 25f);
        Bell(d, 0f, 0.14f, 780f, 0.2f, 1.41f, 1f, 30f);
        Tone(d, 0f, 0.25f, 140f, 50f, 0, 0.8f, 0.002f, 2f);
        Noise(d, 0f, 0.25f, 0.4f, 0, 700f, 150f, 1f, 0.02f, 2f);
        return d;
    }

    // something heavy hits the road
    static float[] BuildThud()
    {
        float[] d = Buf(0.45f);
        Tone(d, 0f, 0.35f, 85f, 38f, 0, 0.9f, 0.002f, 1.8f);
        Noise(d, 0f, 0.3f, 0.5f, 0, 500f, 120f, 1f, 0.02f, 2f);
        return d;
    }

    // the end of a run: a smash, a boom and rattling debris
    static float[] BuildCrash()
    {
        float[] d = Buf(1.1f);
        Noise(d, 0f, 0.12f, 1f, 2, 3500f, 1500f, 0.9f, 0.01f, 2f);
        Noise(d, 0f, 0.5f, 0.6f, 0, 1500f, 200f, 1f, 0.01f, 2f);
        Tone(d, 0f, 0.5f, 110f, 35f, 0, 1f, 0.002f, 1.6f);
        Bell(d, 0f, 0.25f, 380f, 0.3f, 1.62f, 1.5f, 18f);
        for (int i = 0; i < 12; i++)
        {
            float t = 0.08f + Rnd(0f, 0.6f);
            Bell(d, t, 0.1f, Rnd(300f, 1100f), Rnd(0.08f, 0.2f), Rnd(1.3f, 2.4f), 1.2f, 35f);
            Noise(d, t, 0.02f, Rnd(0.1f, 0.3f), 1, 2000f, 1500f, 1f, 0.1f, 2f);
        }
        return Reverb(d, 0.2f, 0.7f, 0.4f);
    }

    // a stumble: a scuff and a grunt-like low "oof"
    static float[] BuildStumble()
    {
        float[] d = Buf(0.45f);
        Noise(d, 0f, 0.3f, 0.6f, 1, 900f, 300f, 1.3f, 0.1f, 1.8f);
        Brass(d, 0.02f, 0.18f, 150f, 0.5f, 500f, 0.02f, 0f, 1);
        Tone(d, 0.02f, 0.18f, 150f, 105f, 2, 0.25f, 0.01f, 2f);
        return d;
    }

    // ==================================================================
    //  The golem
    // ==================================================================

    static float[] BuildGolemRoar()
    {
        float[] d = Buf(1.5f);
        int n = (int)(1.3f * Rate);
        float ph = 0f, ph2 = 0f, l1 = 0f, l2 = 0f;
        for (int i = 0; i < n; i++)
        {
            float t = i / (float)n, time = i / (float)Rate;
            float f = Mathf.Lerp(78f, 52f, t) * (1f + 0.04f * Mathf.Sin(TwoPi * 6f * time));
            ph += f / Rate;
            ph2 += f * 1.5f / Rate;
            float growl = 0.6f + 0.4f * Mathf.Sin(TwoPi * 31f * time);
            float s = (Osc(3, ph) + 0.5f * Osc(3, ph2)) * growl + Rnd() * 0.5f;
            float fc = Mathf.Lerp(900f, 350f, t);
            float a = 1f - Mathf.Exp(-TwoPi * fc / Rate);
            l1 += (s - l1) * a;
            l2 += (l1 - l2) * a;
            float env = Mathf.Min(1f, t * 7f) * Fall(t, 1.2f);
            d[i] += l2 * env * 0.8f;
        }
        Noise(d, 0f, 0.6f, 0.3f, 0, 250f, 120f, 1f, 0.05f, 1.5f);
        return Reverb(d, 0.3f, 0.8f, 0.6f);
    }

    static float[] BuildGolemStep()
    {
        float[] d = Buf(0.45f);
        Tone(d, 0f, 0.35f, 60f, 32f, 0, 1f, 0.002f, 1.6f);
        Noise(d, 0f, 0.25f, 0.6f, 0, 300f, 90f, 1f, 0.02f, 2f);
        for (int i = 0; i < 4; i++) Noise(d, Rnd(0.02f, 0.2f), 0.03f, 0.2f, 1, 1200f, 900f, 1f, 0.1f, 2f);  // pebbles
        return d;
    }

    // ==================================================================
    //  Progress
    // ==================================================================

    static float[] BuildSpeedUp()
    {
        float[] d = Buf(0.8f);
        Noise(d, 0f, 0.55f, 0.5f, 1, 400f, 3500f, 2f, 0.85f, 3f);
        Tone(d, 0f, 0.5f, 220f, 880f, 3, 0.12f, 0.3f, 0.5f);
        Tone(d, 0.48f, 0.25f, 1760f, 1760f, 2, 0.25f, 0.005f, 2f);
        return Reverb(d, 0.2f, 0.75f, 0.4f);
    }

    // the checkpoint arch: a short brass fanfare with a bell on top
    static float[] BuildCheckpoint()
    {
        float[] d = Buf(1.3f);
        Brass(d, 0f, 0.1f, Midi(72), 0.35f);
        Brass(d, 0.1f, 0.1f, Midi(76), 0.35f);
        Brass(d, 0.2f, 0.1f, Midi(79), 0.35f);
        foreach (int m in new[] { 72, 76, 79, 84 }) Brass(d, 0.3f, 0.6f, Midi(m), 0.22f);
        Kick(d, 0.3f, 0.35f);
        Bell(d, 0.3f, 0.7f, Midi(96), 0.18f, 3.5f, 1.5f, 5f);
        return Reverb(d, 0.3f, 0.82f, 0.6f);
    }

    // ==================================================================
    //  Countdown, menus, endings
    // ==================================================================

    static float[] BuildBeep()
    {
        float[] d = Buf(0.3f);
        Tone(d, 0f, 0.22f, 880f, 880f, 0, 0.5f, 0.005f, 1.5f);
        Tone(d, 0f, 0.22f, 1760f, 1760f, 2, 0.12f, 0.005f, 2f);
        return Reverb(d, 0.15f, 0.7f, 0.2f);
    }

    static float[] BuildGo()
    {
        float[] d = Buf(0.9f);
        foreach (int m in new[] { 84, 88, 91 }) Brass(d, 0f, 0.5f, Midi(m), 0.25f, 3000f, 0.01f);
        Bell(d, 0f, 0.6f, Midi(96), 0.2f, 2f, 1.2f, 5f);
        Kick(d, 0f, 0.45f);
        Noise(d, 0f, 0.35f, 0.25f, 1, 600f, 2500f, 1.5f, 0.3f, 1.5f);
        return Reverb(d, 0.25f, 0.78f, 0.5f);
    }

    static float[] BuildClick()
    {
        float[] d = Buf(0.05f);
        Tone(d, 0f, 0.03f, 2100f, 1500f, 0, 0.6f, 0.0005f, 2f);
        Noise(d, 0f, 0.008f, 0.3f, 2, 4000f, 4000f, 1f, 0.1f, 2f);
        return d;
    }

    static float[] BuildSelect()
    {
        float[] d = Buf(0.3f);
        Tone(d, 0f, 0.07f, 988f, 988f, 2, 0.4f, 0.003f, 1.5f);
        Tone(d, 0.06f, 0.14f, 1480f, 1480f, 2, 0.4f, 0.003f, 2f);
        return Reverb(d, 0.15f, 0.7f, 0.2f);
    }

    static float[] BuildBack()
    {
        float[] d = Buf(0.3f);
        Tone(d, 0f, 0.07f, 1480f, 1480f, 2, 0.35f, 0.003f, 1.5f);
        Tone(d, 0.06f, 0.14f, 988f, 988f, 2, 0.35f, 0.003f, 2f);
        return Reverb(d, 0.15f, 0.7f, 0.2f);
    }

    // the run is over: a sad descending "wah-wah"
    static float[] BuildGameOver()
    {
        float[] d = Buf(2f);
        int[] notes = { 67, 66, 65 };
        for (int i = 0; i < notes.Length; i++) Brass(d, i * 0.28f, 0.26f, Midi(notes[i] - 12), 0.4f, 900f, 0.03f, 0.01f);
        Brass(d, 0.84f, 0.75f, Midi(64 - 12), 0.4f, 900f, 0.03f, 0.025f);
        Tone(d, 0.84f, 0.75f, Midi(40), Midi(40), 2, 0.25f, 0.03f, 1.2f);
        return Reverb(d, 0.3f, 0.8f, 0.6f);
    }

    // the race is won / the timed run is complete
    static float[] BuildVictory()
    {
        float[] d = Buf(2f);
        int[] run = { 72, 76, 79, 84 };
        for (int i = 0; i < run.Length; i++) Brass(d, i * 0.12f, 0.12f, Midi(run[i]), 0.35f);
        foreach (int m in new[] { 72, 76, 79, 84, 88 }) Brass(d, 0.48f, 0.9f, Midi(m), 0.18f);
        Kick(d, 0.48f, 0.4f);
        Snare(d, 0.48f, 0.2f);
        for (int i = 0; i < 6; i++) Bell(d, 0.5f + i * 0.06f, 0.6f, Midi(96 + (i % 3) * 4), 0.12f, 3.5f, 1.2f, 6f);
        return Reverb(d, 0.32f, 0.84f, 0.8f);
    }

    // a new record: a fanfare and a cascade of sparkles
    static float[] BuildRecord()
    {
        float[] d = Buf(2.4f);
        int[] run = { 67, 72, 76, 79, 84 };
        for (int i = 0; i < run.Length; i++) Brass(d, i * 0.09f, 0.1f, Midi(run[i]), 0.35f, 2800f);
        foreach (int m in new[] { 72, 79, 84, 88, 91 }) Brass(d, 0.45f, 1.1f, Midi(m), 0.16f, 2800f);
        Kick(d, 0.45f, 0.45f);
        Tom(d, 0.45f, 90f, 0.35f);
        for (int i = 0; i < 14; i++) Bell(d, 0.45f + i * 0.05f, 0.5f, Midi(108 - (i % 7) * 3), 0.1f, 3.5f, 1.5f, 6f);
        Noise(d, 0.45f, 1f, 0.06f, 2, 5000f, 6000f, 2f, 0.1f, 1.5f);
        return Reverb(d, 0.35f, 0.85f, 0.9f);
    }

    // ==================================================================
    //  Ambience
    // ==================================================================

    // 6 s of wind; every modulation completes whole cycles, so the loop has no seam
    static float[] BuildWind()
    {
        const float len = 6f;
        float[] d = Buf(len);
        float low = 0f, band = 0f, low2 = 0f, band2 = 0f;
        for (int i = 0; i < d.Length; i++)
        {
            float time = i / (float)Rate;
            float gust = 0.55f + 0.25f * Mathf.Sin(TwoPi * time * 1f / len) + 0.2f * Mathf.Sin(TwoPi * time * 3f / len + 1f);
            float fc = 380f + 320f * gust;
            float f = 2f * Mathf.Sin(Mathf.PI * fc / (Rate * 2f));
            float f2 = 2f * Mathf.Sin(Mathf.PI * (fc * 2.6f) / (Rate * 2f));
            float x = Rnd();
            for (int k = 0; k < 2; k++)
            {
                low += f * band; float h = x - low - 0.35f * band; band += f * h;
                low2 += f2 * band2; float h2 = x - low2 - 0.5f * band2; band2 += f2 * h2;
            }
            d[i] = (band * 0.6f + band2 * 0.25f) * gust;
        }
        // a short crossfade of the end into the start
        int fade = (int)(0.25f * Rate);
        for (int i = 0; i < fade; i++)
        {
            float k = i / (float)fade;
            d[i] = d[i] * k + d[d.Length - fade + i] * (1f - k);
        }
        System.Array.Resize(ref d, d.Length - fade);
        return d;
    }

    static float[] BuildBird(int v)
    {
        float[] d = Buf(1f);
        int chirps = 2 + v * 2;
        float t = 0f;
        for (int i = 0; i < chirps; i++)
        {
            float f0 = 2600f + v * 300f + Rnd(-200f, 200f);
            float dur = v == 1 ? 0.05f : 0.08f;
            Tone(d, t, dur, f0, f0 * (v == 2 ? 0.75f : 1.35f), 0, 0.5f, 0.004f, 1.2f, 45f, 0.04f);
            t += dur + (v == 1 ? 0.03f : 0.06f);
        }
        return Reverb(d, 0.25f, 0.75f, 0.4f);
    }

    // ==================================================================
    //  Music
    // ==================================================================

    // The run: 128 BPM in A minor, 16 bars. Four-on-the-floor drums with taiko fills, a pulsing bass,
    // a plucked arpeggio, a soft pad and a heroic brass melody from bar 5.
    static float[] BuildGameMusic()
    {
        const float bpm = 128f;
        float beat = 60f / bpm, eighth = beat / 2f, six = beat / 4f;
        const int bars = 16;
        float[] d = Buf(bars * 4 * beat);

        int[][] chords =
        {
            new[] { 57, 60, 64 }, new[] { 53, 57, 60 }, new[] { 48, 52, 55 }, new[] { 55, 59, 62 },   // Am F C G
            new[] { 57, 60, 64 }, new[] { 53, 57, 60 }, new[] { 55, 59, 62 }, new[] { 52, 56, 59 },   // Am F G E
        };
        // the melody: (note, length in eighths) - each bar adds up to 8
        int[][] melody =
        {
            new[] { 69, 2, 72, 1, 76, 1, 81, 3, 79, 1 },
            new[] { 77, 2, 76, 1, 74, 1, 72, 2, 69, 2 },
            new[] { 67, 2, 72, 1, 76, 1, 79, 3, 76, 1 },
            new[] { 74, 2, 71, 1, 74, 1, 79, 4 },
            new[] { 81, 2, 79, 1, 76, 1, 72, 2, 76, 2 },
            new[] { 77, 2, 81, 2, 79, 2, 77, 2 },
            new[] { 76, 2, 74, 1, 71, 1, 74, 2, 79, 2 },
            new[] { 80, 3, 76, 1, 71, 2, 68, 2 },
        };
        int[] arp = { 0, 1, 2, 1, 0, 2, 1, 2 };

        for (int bar = 0; bar < bars; bar++)
        {
            int[] ch = chords[bar % 8];
            float b0 = bar * 4 * beat;

            // pad: the chord held through the bar
            foreach (int m in ch) Brass(d, b0, 4 * beat, Midi(m), 0.035f, 500f, 0.25f, 0.003f, 2);

            for (int s = 0; s < 16; s++)
            {
                float t = b0 + s * six;
                if (s % 2 == 0)
                {
                    int bn = ch[0] - 24 + (s % 8 == 6 ? 12 : 0);
                    Brass(d, t, eighth * 0.9f, Midi(bn), 0.2f, 350f, 0.005f, 0f, 1);
                }
                Pluck(d, t, six * 2.5f, Midi(ch[arp[s % 8]] + 12), bar < 4 ? 0.13f : 0.1f, 0.7f, 0.994f);

                if (s % 4 == 0) Kick(d, t, 0.5f);
                if (s % 8 == 4) Snare(d, t, 0.28f);
                if (s % 2 == 1) Hat(d, t, 0.07f, s % 4 == 3 ? 0.09f : 0.04f);
            }
            // a taiko fill closes every four bars
            if (bar % 4 == 3)
            {
                Tom(d, b0 + 3 * beat, 110f, 0.35f);
                Tom(d, b0 + 3 * beat + six * 2f, 90f, 0.35f);
                Tom(d, b0 + 3 * beat + six * 3f, 75f, 0.4f);
            }

            if (bar >= 4)
            {
                int[] mel = melody[bar % 8];
                float t = b0;
                for (int k = 0; k < mel.Length; k += 2)
                {
                    float len = mel[k + 1] * eighth;
                    Brass(d, t, len * 0.95f, Midi(mel[k]), bar >= 12 ? 0.15f : 0.13f, 2600f, 0.02f, 0.008f, 2);
                    if (bar >= 12) Pluck(d, t, len, Midi(mel[k] + 12), 0.05f, 0.5f, 0.996f);
                    t += len;
                }
            }
        }
        d = Reverb(d, 0.18f, 0.78f, 0f, true);
        return Normalize(d, 0.85f);
    }

    // The menu: 92 BPM in D dorian, 8 bars. A lute, a soft pad, a frame drum and a tambourine, and a flute.
    static float[] BuildMenuMusic()
    {
        const float bpm = 92f;
        float beat = 60f / bpm, eighth = beat / 2f;
        const int bars = 8;
        float[] d = Buf(bars * 4 * beat);

        int[][] chords =
        {
            new[] { 50, 57, 62, 65 }, new[] { 48, 55, 60, 64 }, new[] { 46, 53, 58, 62 }, new[] { 48, 55, 60, 64 },  // Dm C Bb C
        };
        int[] lute = { 0, 2, 1, 3, 2, 1, 3, 2 };
        int[][] melody =
        {
            new[] { 74, 2, 77, 1, 76, 1, 74, 2, 69, 2 },
            new[] { 72, 2, 76, 1, 74, 1, 72, 2, 67, 2 },
            new[] { 70, 2, 74, 1, 77, 1, 81, 3, 79, 1 },
            new[] { 79, 2, 76, 2, 72, 2, 76, 2 },
        };

        for (int bar = 0; bar < bars; bar++)
        {
            int[] ch = chords[bar % 4];
            float b0 = bar * 4 * beat;
            foreach (int m in new[] { ch[1], ch[2], ch[3] }) Brass(d, b0, 4 * beat, Midi(m), 0.03f, 400f, 0.4f, 0.003f, 2);
            Pluck(d, b0, 4 * beat, Midi(ch[0] - 12), 0.22f, 0.5f, 0.998f);
            for (int e = 0; e < 8; e++)
                Pluck(d, b0 + e * eighth, eighth * 3f, Midi(ch[lute[e]] + 12), 0.14f, 0.55f, 0.996f);
            Tom(d, b0, 80f, 0.3f);
            Tom(d, b0 + 2.5f * beat, 80f, 0.18f);
            Tambourine(d, b0 + beat, 0.07f);
            Tambourine(d, b0 + 3f * beat, 0.07f);

            if (bar >= 4)
            {
                int[] mel = melody[bar % 4];
                float t = b0;
                for (int k = 0; k < mel.Length; k += 2)
                {
                    float len = mel[k + 1] * eighth;
                    Flute(d, t, len * 0.95f, Midi(mel[k]), 0.12f);
                    t += len;
                }
            }
        }
        d = Reverb(d, 0.28f, 0.84f, 0f, true);
        return Normalize(d, 0.8f);
    }
}

// Plays the sounds: a pool of sources (so many sounds overlap, each with its own pitch and stereo position),
// two music sources for cross-fades, a looping wind that follows the running speed, and birdsong.
public static class Sfx
{
    const string MuteKey = "rr.muted";

    static AudioSource[] pool;
    static int next;
    static AudioSource musicA, musicB, wind;
    static SfxDriver driver;

    public static float Volume = 0.8f;          // effects
    public static float MusicVolume = 0.42f;
    public static bool Muted { get; private set; }

    public static void Init(GameObject host)
    {
        SynthAudio.Init();
        pool = new AudioSource[14];
        for (int i = 0; i < pool.Length; i++) pool[i] = NewSource(host, false);
        musicA = NewSource(host, true);
        musicB = NewSource(host, true);
        wind = NewSource(host, true);
        wind.clip = SynthAudio.Wind;
        wind.volume = 0f;
        wind.Play();
        driver = host.AddComponent<SfxDriver>();
        driver.Setup(musicA, musicB, wind);

        Muted = PlayerPrefs.GetInt(MuteKey, 0) == 1;
        AudioListener.volume = Muted ? 0f : 1f;
    }

    static AudioSource NewSource(GameObject host, bool loop)
    {
        AudioSource s = host.AddComponent<AudioSource>();
        s.playOnAwake = false;
        s.spatialBlend = 0f;
        s.loop = loop;
        s.ignoreListenerPause = true;
        return s;
    }

    public static void ToggleMute()
    {
        Muted = !Muted;
        PlayerPrefs.SetInt(MuteKey, Muted ? 1 : 0);
        PlayerPrefs.Save();
        AudioListener.volume = Muted ? 0f : 1f;
    }

    public static void Play(AudioClip clip, float volume = 1f)
    {
        Play(clip, volume, 1f, 0f);
    }

    public static void Play(AudioClip clip, float volume, float pitch, float pan = 0f)
    {
        if (pool == null || clip == null) return;
        // a free source if there is one, otherwise the oldest
        AudioSource src = pool[next];
        for (int i = 0; i < pool.Length; i++)
        {
            AudioSource s = pool[(next + i) % pool.Length];
            if (!s.isPlaying) { src = s; next = (next + i) % pool.Length; break; }
        }
        next = (next + 1) % pool.Length;
        src.pitch = pitch;
        src.panStereo = pan;
        src.PlayOneShot(clip, volume * Volume);
    }

    // The same sound a little higher or lower every time (footsteps, whooshes, hits do not sound mechanical).
    public static void PlayVar(AudioClip clip, float volume, float variation = 0.07f)
    {
        Play(clip, volume, 1f + Random.Range(-variation, variation), 0f);
    }

    public static void PlayDelayed(AudioClip clip, float volume, float delay)
    {
        if (driver != null) driver.Schedule(clip, volume, delay);
    }

    public static void PlayStep(float volume)
    {
        AudioClip[] s = SynthAudio.Steps;
        if (s == null || s.Length == 0) return;
        Play(s[Random.Range(0, s.Length)], volume, 1f + Random.Range(-0.08f, 0.08f), Random.Range(-0.1f, 0.1f));
    }

    // The track that should play now (the same one again changes nothing); null = silence.
    public static void Music(AudioClip clip)
    {
        if (driver != null) driver.WantMusic(clip);
    }

    // Quieter music (pause, results).
    public static void DuckMusic(float level)
    {
        if (driver != null) driver.duck = level;
    }

    // Called every frame by a running world: how fast (0..1) and whether birds sing here.
    public static void ReportRun(float speed01, bool birds)
    {
        if (driver != null) driver.Report(speed01, birds);
    }
}
