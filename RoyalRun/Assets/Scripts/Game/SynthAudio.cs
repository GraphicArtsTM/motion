using UnityEngine;

// Sounds and background music synthesized in code (no audio files in the project).
// Everything is generated once at start-up and takes a few milliseconds.
public static class SynthAudio
{
    const int Rate = 22050;

    public static AudioClip Coin, Gem, PowerUp, Hit, Thud, Checkpoint, Beep, Go, Click, Jump, Land, Shield, Combo, Music;

    public static void Init()
    {
        if (Coin != null && Music != null) return;

        Coin = Make("Coin", Concat(Tone(988f, 988f, 0.07f, 1, 0.5f), Tone(1319f, 1319f, 0.16f, 1, 0.5f)));
        Gem = Make("Gem", Concat(Concat(Tone(1319f, 1319f, 0.06f, 2, 0.5f), Tone(1568f, 1568f, 0.06f, 2, 0.5f)),
                                 Concat(Tone(1976f, 1976f, 0.06f, 2, 0.5f), Tone(2637f, 2637f, 0.25f, 2, 0.45f))));
        PowerUp = Make("PowerUp", Tone(380f, 1100f, 0.32f, 1, 0.45f));
        Jump = Make("Jump", Tone(300f, 720f, 0.16f, 2, 0.45f));
        Land = Make("Land", Mix(Noise(0.08f, 0.25f, 0.7f), Tone(110f, 70f, 0.08f, 0, 0.5f)));
        Shield = Make("Shield", Mix(Tone(1200f, 300f, 0.35f, 2, 0.4f), Noise(0.2f, 0.25f, 0.2f)));
        Combo = Make("Combo", Concat(Tone(784f, 784f, 0.07f, 1, 0.35f), Tone(1175f, 1175f, 0.14f, 1, 0.35f)));
        Hit = Make("Hit", Mix(Noise(0.25f, 0.7f, 0.35f), Tone(140f, 60f, 0.3f, 0, 0.8f)));
        Thud = Make("Thud", Mix(Noise(0.18f, 0.5f, 0.6f), Tone(90f, 45f, 0.22f, 0, 0.9f)));
        Checkpoint = Make("Checkpoint", Concat(Concat(Tone(523f, 523f, 0.09f, 2, 0.5f), Tone(659f, 659f, 0.09f, 2, 0.5f)),
                                               Concat(Tone(784f, 784f, 0.09f, 2, 0.5f), Tone(1047f, 1047f, 0.3f, 2, 0.5f))));
        Beep = Make("Beep", Tone(660f, 660f, 0.16f, 2, 0.5f));
        Go = Make("Go", Tone(990f, 990f, 0.4f, 2, 0.55f));
        Click = Make("Click", Tone(1200f, 900f, 0.04f, 2, 0.35f));
        Music = Make("Music", BuildMusic());
    }

    static AudioClip Make(string name, float[] data)
    {
        AudioClip clip = AudioClip.Create("RR " + name, data.Length, 1, Rate, false);
        clip.SetData(data, 0);
        return clip;
    }

    // wave: 0 sine, 1 square, 2 triangle
    static float Osc(int wave, float ph)
    {
        float x = ph - Mathf.Floor(ph);
        switch (wave)
        {
            case 1: return x < 0.5f ? 0.6f : -0.6f;
            case 2: return 4f * Mathf.Abs(x - 0.5f) - 1f;
            default: return Mathf.Sin(x * Mathf.PI * 2f);
        }
    }

    static float[] Tone(float f0, float f1, float dur, int wave, float vol)
    {
        int n = Mathf.CeilToInt(dur * Rate);
        float[] d = new float[n];
        float ph = 0f;
        for (int i = 0; i < n; i++)
        {
            float t = i / (float)n;
            float f = Mathf.Lerp(f0, f1, t);
            ph += f / Rate;
            float env = Mathf.Min(1f, i / (Rate * 0.005f)) * (1f - t) * (1f - t);
            d[i] = Osc(wave, ph) * env * vol;
        }
        return d;
    }

    static float[] Noise(float dur, float vol, float smooth)
    {
        int n = Mathf.CeilToInt(dur * Rate);
        float[] d = new float[n];
        System.Random r = new System.Random(7);
        float last = 0f;
        for (int i = 0; i < n; i++)
        {
            float t = i / (float)n;
            float v = (float)(r.NextDouble() * 2.0 - 1.0);
            last = Mathf.Lerp(v, last, smooth);
            d[i] = last * vol * (1f - t) * (1f - t);
        }
        return d;
    }

    static float[] Concat(float[] a, float[] b)
    {
        float[] d = new float[a.Length + b.Length];
        a.CopyTo(d, 0);
        b.CopyTo(d, a.Length);
        return d;
    }

    static float[] Mix(float[] a, float[] b)
    {
        float[] d = new float[Mathf.Max(a.Length, b.Length)];
        for (int i = 0; i < d.Length; i++)
            d[i] = (i < a.Length ? a[i] : 0f) + (i < b.Length ? b[i] : 0f);
        return d;
    }

    // ------------------------------------------------------------------
    //  Background music: an 8-bar loop at 128 BPM, A minor (Am - F - C - G)
    // ------------------------------------------------------------------

    static float[] BuildMusic()
    {
        const float bpm = 128f;
        float beat = 60f / bpm;
        float step = beat / 4f;                 // a sixteenth note
        const int bars = 8;
        int total = Mathf.CeilToInt(bars * 4 * beat * Rate);
        float[] d = new float[total];

        // chords as MIDI notes
        int[][] chords =
        {
            new[] { 57, 60, 64 },   // Am
            new[] { 53, 57, 60 },   // F
            new[] { 48, 52, 55 },   // C
            new[] { 55, 59, 62 },   // G
        };
        int[] arpOrder = { 0, 1, 2, 1, 0, 2, 1, 2 };
        int[] melody = { 76, -1, 74, 72, 74, -1, 72, 69, 72, -1, 71, 67, 71, 72, 74, -1 };   // quarter notes, bars 5-8

        System.Random rnd = new System.Random(3);

        for (int bar = 0; bar < bars; bar++)
        {
            int[] chord = chords[bar % 4];
            float barStart = bar * 4 * beat;

            for (int s = 0; s < 16; s++)
            {
                float t0 = barStart + s * step;

                // bass: eighth notes (root, root, octave...)
                if (s % 2 == 0)
                {
                    int note = chord[0] - 12 + ((s % 8 == 4) ? 12 : 0);
                    AddNote(d, t0, step * 1.8f, Midi(note), 2, 0.22f);
                }

                // arpeggio: sixteenth notes, an octave up
                int an = chord[arpOrder[s % 8]] + 12;
                AddNote(d, t0, step * 0.9f, Midi(an), 1, bar < 4 ? 0.035f : 0.028f);

                // drums
                if (s % 4 == 0) AddKick(d, t0);
                if (s % 8 == 4) AddSnare(d, t0, rnd);
                if (s % 2 == 1) AddHat(d, t0, rnd);
            }

            // melody in the second half
            if (bar >= 4)
            {
                for (int q = 0; q < 4; q++)
                {
                    int m = melody[((bar - 4) * 4 + q) % melody.Length];
                    if (m < 0) continue;
                    AddNote(d, barStart + q * beat, beat * 0.9f, Midi(m), 2, 0.12f);
                }
            }
        }

        // normalize
        float peak = 0.0001f;
        foreach (float v in d) peak = Mathf.Max(peak, Mathf.Abs(v));
        float g = 0.8f / peak;
        for (int i = 0; i < d.Length; i++) d[i] *= g;
        return d;
    }

    static float Midi(int note)
    {
        return 440f * Mathf.Pow(2f, (note - 69) / 12f);
    }

    static void AddNote(float[] d, float start, float dur, float freq, int wave, float vol)
    {
        int s0 = (int)(start * Rate);
        int n = (int)(dur * Rate);
        float ph = 0f;
        for (int i = 0; i < n && s0 + i < d.Length; i++)
        {
            float t = i / (float)n;
            ph += freq / Rate;
            float env = Mathf.Min(1f, i / (Rate * 0.004f)) * Mathf.Pow(1f - t, 1.5f);
            d[s0 + i] += Osc(wave, ph) * env * vol;
        }
    }

    static void AddKick(float[] d, float start)
    {
        int s0 = (int)(start * Rate);
        int n = (int)(0.16f * Rate);
        float ph = 0f;
        for (int i = 0; i < n && s0 + i < d.Length; i++)
        {
            float t = i / (float)n;
            ph += Mathf.Lerp(120f, 45f, t) / Rate;
            d[s0 + i] += Mathf.Sin(ph * Mathf.PI * 2f) * (1f - t) * (1f - t) * 0.5f;
        }
    }

    static void AddSnare(float[] d, float start, System.Random r)
    {
        int s0 = (int)(start * Rate);
        int n = (int)(0.14f * Rate);
        for (int i = 0; i < n && s0 + i < d.Length; i++)
        {
            float t = i / (float)n;
            float v = (float)(r.NextDouble() * 2.0 - 1.0);
            d[s0 + i] += v * (1f - t) * (1f - t) * 0.2f + Mathf.Sin(i * 200f * Mathf.PI * 2f / Rate) * (1f - t) * 0.08f;
        }
    }

    static void AddHat(float[] d, float start, System.Random r)
    {
        int s0 = (int)(start * Rate);
        int n = (int)(0.035f * Rate);
        float last = 0f;
        for (int i = 0; i < n && s0 + i < d.Length; i++)
        {
            float t = i / (float)n;
            float v = (float)(r.NextDouble() * 2.0 - 1.0);
            float hp = v - last;    // a rough high-pass filter
            last = v;
            d[s0 + i] += hp * (1f - t) * 0.05f;
        }
    }
}

// Plays short sound effects (coin, hit, checkpoint, button clicks).
public static class Sfx
{
    static AudioSource source;

    public static float Volume = 0.8f;

    public static void Init(GameObject host)
    {
        source = host.AddComponent<AudioSource>();
        source.playOnAwake = false;
        source.spatialBlend = 0f;
    }

    public static void Play(AudioClip clip, float volume = 1f)
    {
        if (source == null || clip == null) return;
        source.PlayOneShot(clip, volume * Volume);
    }
}
