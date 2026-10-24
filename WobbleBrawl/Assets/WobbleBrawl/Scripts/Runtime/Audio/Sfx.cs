using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>
    /// Every sound in the game is synthesised at start-up (no audio assets): thumps, smacks,
    /// whooshes, cartoon grunts, a knockout bell, crowd cheers and two procedural music loops.
    /// Playback goes through a small pool of 2D sources panned by screen position.
    /// </summary>
    public sealed class Sfx : MonoBehaviour
    {
        public static AudioClip Punch, Smack, Thud, Whoosh, Jump, Grab, KO, Splash, Cheer, Whistle, Tick, Select, Fanfare, Boing;
        public static AudioClip[] Grunts;
        public static AudioClip MenuMusic, BattleMusic;
        public static float MasterVolume = 0.9f;
        public static float MusicVolume = 0.35f;

        static Sfx instance;
        AudioSource[] pool;
        int next;
        AudioSource music;
        const int Rate = 22050;

        public static void Init(Transform parent)
        {
            if (instance != null) return;
            var go = new GameObject("Sfx");
            go.transform.SetParent(parent, false);
            instance = go.AddComponent<Sfx>();
            instance.Build();
        }

        void Build()
        {
            pool = new AudioSource[24];
            for (int i = 0; i < pool.Length; i++)
            {
                pool[i] = gameObject.AddComponent<AudioSource>();
                pool[i].playOnAwake = false;
                pool[i].spatialBlend = 0f;
            }
            music = gameObject.AddComponent<AudioSource>();
            music.loop = true;
            music.playOnAwake = false;
            music.spatialBlend = 0f;

            var rng = new System.Random(1234);
            Punch = Make("punch", 0.2f, (t, i) => Thump(t, 150f, 45f, 18f) * 0.9f + Noise(rng) * Env(t, 0.002f, 0.03f) * 0.6f);
            Smack = Make("smack", 0.22f, (t, i) => Thump(t, 120f, 40f, 14f) + Noise(rng) * Env(t, 0.001f, 0.06f) * 0.8f);
            Thud = Make("thud", 0.25f, LowNoise(rng, 0.25f, 0.9f));
            Whoosh = Make("whoosh", 0.28f, BandNoise(rng, 0.28f));
            Jump = Make("jump", 0.16f, (t, i) => Mathf.Sin(2f * Mathf.PI * Sweep(t, 220f, 560f, 0.16f)) * Env(t, 0.005f, 0.12f) * 0.5f);
            Boing = Make("boing", 0.5f, Tone(t => 170f + 90f * Mathf.Sin(t * 45f) * Mathf.Exp(-t * 4f), 0.002f, 0.4f, 0.6f));
            Grab = Make("grab", 0.06f, (t, i) => Noise(rng) * Env(t, 0.001f, 0.02f) * 0.5f + Mathf.Sin(t * 2f * Mathf.PI * 900f) * Env(t, 0.001f, 0.02f) * 0.3f);
            KO = Make("ko", 1.3f, (t, i) => Bell(t, 660f) * 0.5f + Bell(t, 990f) * 0.25f);
            Splash = Make("splash", 0.8f, LowNoise(rng, 0.8f, 0.35f));
            Cheer = Make("cheer", 2.4f, CrowdNoise(rng, 2.4f));
            Whistle = Make("whistle", 0.6f, Tone(t => 2300f + 140f * Mathf.Sin(t * 2f * Mathf.PI * 28f), 0.02f, 0.5f, 0.35f));
            Tick = Make("tick", 0.05f, (t, i) => Mathf.Sin(2f * Mathf.PI * 1100f * t) * Env(t, 0.001f, 0.04f) * 0.4f);
            Select = Make("select", 0.16f, (t, i) => Mathf.Sin(2f * Mathf.PI * (t < 0.07f ? 660f : 990f) * t) * Env(t, 0.002f, 0.14f) * 0.45f);
            Fanfare = Make("fanfare", 1.6f, FanfareGen());

            Grunts = new AudioClip[5];
            for (int g = 0; g < Grunts.Length; g++)
            {
                float f0 = 150f + g * 28f;
                float f1 = 500f + g * 90f, f2 = 1200f + g * 150f;
                float len = 0.16f + g * 0.02f;
                Grunts[g] = Make("grunt" + g, len, Voice(f0, f1, f2, len));
            }

            MenuMusic = MakeMusic("menu_music", 104f, 7);
            BattleMusic = MakeMusic("battle_music", 128f, 3);
        }

        // ------------------------------------------------------------------ playback

        public static AudioClip RandomGrunt() => Grunts != null && Grunts.Length > 0 ? Grunts[Random.Range(0, Grunts.Length)] : null;

        public static void Play(AudioClip clip, Vector3 worldPos, float volume = 1f, float pitch = 1f)
        {
            if (instance == null || clip == null) return;
            var src = instance.pool[instance.next];
            instance.next = (instance.next + 1) % instance.pool.Length;

            float pan = 0f, att = 1f;
            var cam = GameManager.I != null ? GameManager.I.MainCamera : null;
            if (cam != null)
            {
                Vector3 vp = cam.WorldToViewportPoint(worldPos);
                pan = Mathf.Clamp((vp.x - 0.5f) * 1.4f, -0.8f, 0.8f);
                float dist = Vector3.Distance(cam.transform.position, worldPos);
                att = Mathf.Clamp01(1.4f - dist / 45f);
            }
            src.panStereo = pan;
            src.pitch = pitch;
            src.volume = Mathf.Clamp01(volume * att) * MasterVolume;
            src.clip = clip;
            src.Play();
        }

        public static void PlayUI(AudioClip clip, float volume = 0.6f, float pitch = 1f)
        {
            if (instance == null || clip == null) return;
            var src = instance.pool[instance.next];
            instance.next = (instance.next + 1) % instance.pool.Length;
            src.panStereo = 0f;
            src.pitch = pitch;
            src.volume = volume * MasterVolume;
            src.clip = clip;
            src.Play();
        }

        public static void PlayMusic(AudioClip clip)
        {
            if (instance == null) return;
            var m = instance.music;
            if (m.clip == clip && m.isPlaying) return;
            m.clip = clip;
            m.volume = MusicVolume * MasterVolume;
            m.Play();
        }

        public static void SetMusicDuck(float k)
        {
            if (instance == null) return;
            instance.music.volume = MusicVolume * MasterVolume * k;
        }

        // ------------------------------------------------------------------ synthesis helpers

        delegate float Gen(float t, int i);

        static AudioClip Make(string name, float seconds, Gen gen)
        {
            int n = Mathf.CeilToInt(seconds * Rate);
            var data = new float[n];
            float peak = 0.0001f;
            for (int i = 0; i < n; i++)
            {
                data[i] = gen(i / (float)Rate, i);
                peak = Mathf.Max(peak, Mathf.Abs(data[i]));
            }
            if (peak > 1f) for (int i = 0; i < n; i++) data[i] /= peak;
            // tiny fade-out to avoid clicks
            int fade = Mathf.Min(n, 64);
            for (int i = 0; i < fade; i++) data[n - 1 - i] *= i / (float)fade;
            var clip = AudioClip.Create(name, n, 1, Rate, false);
            clip.SetData(data, 0);
            return clip;
        }

        static float Noise(System.Random r) => (float)(r.NextDouble() * 2.0 - 1.0);

        static float Env(float t, float attack, float decay)
        {
            if (t < attack) return t / attack;
            return Mathf.Exp(-(t - attack) / Mathf.Max(0.0001f, decay));
        }

        static float Sweep(float t, float f0, float f1, float len)
        {
            // integrated phase of a linear frequency sweep
            float k = (f1 - f0) / len;
            return f0 * t + 0.5f * k * t * t;
        }

        /// <summary>Sine whose pitch falls exponentially from f0 to f1 (integrated phase).</summary>
        static float Thump(float t, float f0, float f1, float rate)
        {
            float phase = 2f * Mathf.PI * (f1 * t + (f0 - f1) * (1f - Mathf.Exp(-t * rate)) / rate);
            return Mathf.Sin(phase) * Env(t, 0.002f, 0.08f);
        }

        /// <summary>Sine with an arbitrary frequency curve, using a phase accumulator.</summary>
        static Gen Tone(System.Func<float, float> freq, float attack, float decay, float gain)
        {
            float phase = 0f;
            return (t, i) =>
            {
                phase += freq(t) / Rate;
                return Mathf.Sin(2f * Mathf.PI * phase) * Env(t, attack, decay) * gain;
            };
        }

        static float Bell(float t, float f)
        {
            return (Mathf.Sin(2f * Mathf.PI * f * t) + 0.5f * Mathf.Sin(2f * Mathf.PI * f * 2.76f * t) * Mathf.Exp(-t * 6f)) * Env(t, 0.002f, 0.5f);
        }

        static Gen LowNoise(System.Random r, float len, float cutoff)
        {
            float y = 0f;
            return (t, i) =>
            {
                float a = Mathf.Lerp(0.02f, cutoff, Mathf.Exp(-t * 8f));
                y += (Noise(r) - y) * a;
                return y * 2.2f * Env(t, 0.003f, len * 0.35f);
            };
        }

        static Gen BandNoise(System.Random r, float len)
        {
            float lp = 0f, lp2 = 0f;
            return (t, i) =>
            {
                float x = t / len;
                float a = Mathf.Lerp(0.05f, 0.4f, Mathf.Sin(x * Mathf.PI));
                lp += (Noise(r) - lp) * a;
                lp2 += (lp - lp2) * a;
                return (lp - lp2) * 2.5f * Mathf.Sin(x * Mathf.PI);
            };
        }

        static Gen CrowdNoise(System.Random r, float len)
        {
            float lp = 0f, lp2 = 0f;
            var voices = new float[8];
            var phases = new float[8];
            for (int v = 0; v < voices.Length; v++) voices[v] = 180f + (float)r.NextDouble() * 260f;
            return (t, i) =>
            {
                lp += (Noise(r) - lp) * 0.25f;
                lp2 += (lp - lp2) * 0.25f;
                float s = (lp - lp2) * 1.8f;
                for (int v = 0; v < voices.Length; v++)
                {
                    phases[v] += voices[v] * (1f + 0.03f * Mathf.Sin(t * (3f + v))) / Rate;
                    s += (Mathf.Repeat(phases[v], 1f) * 2f - 1f) * 0.04f;
                }
                float env = Mathf.Clamp01(t / 0.3f) * Mathf.Clamp01((len - t) / 1.2f);
                return s * env;
            };
        }

        static Gen Voice(float f0, float f1, float f2, float len)
        {
            float phase = 0f;
            float b1 = 0, b1b = 0, b2 = 0, b2b = 0;
            return (t, i) =>
            {
                float f = f0 * (1.15f - 0.35f * t / len);
                phase += f / Rate;
                float saw = Mathf.Repeat(phase, 1f) * 2f - 1f;
                // two crude resonators acting as vowel formants
                float w1 = 2f * Mathf.PI * f1 / Rate, w2 = 2f * Mathf.PI * f2 / Rate;
                float r1 = 0.97f, r2 = 0.96f;
                float y1 = saw + 2f * r1 * Mathf.Cos(w1) * b1 - r1 * r1 * b1b; b1b = b1; b1 = y1;
                float y2 = saw + 2f * r2 * Mathf.Cos(w2) * b2 - r2 * r2 * b2b; b2b = b2; b2 = y2;
                float env = Env(t, 0.015f, len * 0.5f);
                return (y1 * 0.03f + y2 * 0.02f) * env;
            };
        }

        static Gen FanfareGen()
        {
            float[] notes = { 523.25f, 659.25f, 783.99f, 1046.5f };
            return (t, i) =>
            {
                int k = Mathf.Min(3, (int)(t / 0.18f));
                float nt = t - k * 0.18f;
                float f = notes[k];
                float len = k == 3 ? 1.0f : 0.16f;
                float s = 0f;
                for (int h = 1; h <= 4; h++) s += Mathf.Sin(2f * Mathf.PI * f * h * t) / h;
                return s * 0.3f * Env(nt, 0.01f, len);
            };
        }

        /// <summary>A short chiptune-ish loop: kick/snare/hat, bass and a plucky pentatonic lead.</summary>
        static AudioClip MakeMusic(string name, float bpm, int seed)
        {
            var r = new System.Random(seed);
            float beat = 60f / bpm;
            int bars = 8;
            float len = bars * 4 * beat;
            int n = Mathf.CeilToInt(len * Rate);
            var data = new float[n];
            float[] scale = { 0, 3, 5, 7, 10, 12, 15 };
            int[] chordRoots = { 0, 5, 3, 7, 0, 5, 10, 7 };
            float root = 110f; // A2

            // pre-pick a melody: one note per eighth
            int steps = bars * 8;
            var melody = new int[steps];
            int cur = 3;
            for (int s = 0; s < steps; s++)
            {
                cur = Mathf.Clamp(cur + r.Next(-2, 3), 0, scale.Length - 1);
                melody[s] = r.NextDouble() < 0.22 ? -1 : cur;
            }

            var noise = new System.Random(seed * 31);
            for (int i = 0; i < n; i++)
            {
                float t = i / (float)Rate;
                float bt = t / beat;
                int bar = Mathf.Min(bars - 1, (int)(bt / 4f));
                float inBeat = bt - Mathf.Floor(bt);
                float inEighth = bt * 2f - Mathf.Floor(bt * 2f);
                int beatInBar = (int)bt % 4;
                float s = 0f;

                // kick on 1 and 3 (plus a pickup)
                if (beatInBar == 0 || beatInBar == 2 || (beatInBar == 3 && inBeat > 0.5f && bar % 2 == 1))
                {
                    float kt = beatInBar == 3 ? (inBeat - 0.5f) * beat : inBeat * beat;
                    s += Mathf.Sin(2f * Mathf.PI * (50f * kt + 90f * (1f - Mathf.Exp(-kt * 30f)) / 30f)) * Mathf.Exp(-kt * 9f) * 0.55f;
                }
                // snare on 2 and 4
                if (beatInBar == 1 || beatInBar == 3)
                {
                    float st = inBeat * beat;
                    s += Noise(noise) * Mathf.Exp(-st * 18f) * 0.22f + Mathf.Sin(2f * Mathf.PI * 190f * st) * Mathf.Exp(-st * 25f) * 0.15f;
                }
                // closed hats on eighths
                float ht = inEighth * beat * 0.5f;
                s += Noise(noise) * Mathf.Exp(-ht * 70f) * 0.06f;

                // bass: root of the bar's chord, bouncing octaves on eighths
                float bassF = root * Mathf.Pow(2f, chordRoots[bar] / 12f) * (((int)(bt * 2f)) % 2 == 1 ? 2f : 1f);
                float bassPhase = bassF * t;
                float bass = (Mathf.Repeat(bassPhase, 1f) < 0.5f ? 1f : -1f) * 0.12f + Mathf.Sin(2f * Mathf.PI * bassPhase) * 0.12f;
                s += bass * Mathf.Exp(-ht * 6f);

                // lead pluck
                int step = Mathf.Min(steps - 1, (int)(bt * 2f));
                if (melody[step] >= 0)
                {
                    float f = root * 4f * Mathf.Pow(2f, scale[melody[step]] / 12f);
                    float ph = f * t;
                    float tri = Mathf.Abs(Mathf.Repeat(ph, 1f) * 4f - 2f) - 1f;
                    s += tri * Mathf.Exp(-ht * 7f) * 0.13f;
                }
                data[i] = Mathf.Clamp(s, -1f, 1f) * 0.8f;
            }
            var clip = AudioClip.Create(name, n, 1, Rate, false);
            clip.SetData(data, 0);
            return clip;
        }
    }
}
