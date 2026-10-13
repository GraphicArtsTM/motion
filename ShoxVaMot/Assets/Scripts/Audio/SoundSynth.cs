using System;

namespace Shatranj.Audio
{
    /// <summary>
    /// Процедурный синтез звуков: дутар (Карплус-Стронг), дойра (дум/так/зенги), най,
    /// карнай; удар сабли, треск дерева, щелчки интерфейса. Работает с float-массивами,
    /// поэтому музыку можно считать в фоновом потоке.
    /// </summary>
    public static class SoundSynth
    {
        public const int SR = 22050;
        const float TwoPi = (float)(Math.PI * 2.0);

        static float Sin(float x) { return (float)Math.Sin(x); }
        static float Exp(float x) { return (float)Math.Exp(x); }

        public static float[] Buffer(float seconds) { return new float[(int)(seconds * SR)]; }

        static void Add(float[] dst, float[] src, int offset, float gain, bool wrap = false)
        {
            for (int i = 0; i < src.Length; i++)
            {
                int j = offset + i;
                if (wrap) j %= dst.Length;
                else if (j >= dst.Length) break;
                if (j < 0) continue;
                dst[j] += src[i] * gain;
            }
        }

        public static float[] Normalize(float[] b, float peak)
        {
            float m = 1e-6f;
            for (int i = 0; i < b.Length; i++) m = Math.Max(m, Math.Abs(b[i]));
            float k = peak / m;
            for (int i = 0; i < b.Length; i++) b[i] *= k;
            return b;
        }

        static void FadeEdges(float[] b, float inSec, float outSec)
        {
            int fi = (int)(inSec * SR), fo = (int)(outSec * SR);
            for (int i = 0; i < fi && i < b.Length; i++) b[i] *= i / (float)fi;
            for (int i = 0; i < fo && i < b.Length; i++) b[b.Length - 1 - i] *= i / (float)fo;
        }

        // ------------------------------------------------------------------ Инструменты

        /// <summary>Щипок струны дутара (Карплус-Стронг).</summary>
        public static float[] Pluck(float freq, float seconds, Random rnd, float decay = 0.996f, float bright = 0.55f)
        {
            var o = Buffer(seconds);
            int n = Math.Max(2, (int)(SR / freq));
            var buf = new float[n];
            float lp = 0f;
            for (int i = 0; i < n; i++)
            {
                float w = (float)(rnd.NextDouble() * 2 - 1);
                lp = lp + bright * (w - lp);
                buf[i] = lp;
            }
            int idx = 0;
            for (int i = 0; i < o.Length; i++)
            {
                int nx = (idx + 1) % n;
                float v = buf[idx];
                o[i] = v;
                buf[idx] = decay * 0.5f * (v + buf[nx]);
                idx = nx;
            }
            // мягкая атака без щелчка
            for (int i = 0; i < 40 && i < o.Length; i++) o[i] *= i / 40f;
            return o;
        }

        /// <summary>Най (тростниковая флейта): тон + обертон + дыхание + вибрато.</summary>
        public static float[] Nay(float freq, float seconds, Random rnd)
        {
            var o = Buffer(seconds);
            float phase = 0f, noiseLp = 0f;
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                float vib = t > 0.15f ? 1f + 0.006f * Sin(TwoPi * 5.2f * t) : 1f;
                phase += TwoPi * freq * vib / SR;
                float env = Math.Min(1f, t / 0.07f) * Math.Min(1f, (seconds - t) / 0.12f);
                float noise = (float)(rnd.NextDouble() * 2 - 1);
                noiseLp += 0.08f * (noise - noiseLp);
                o[i] = env * (Sin(phase) * 0.8f + Sin(phase * 2f) * 0.22f + Sin(phase * 3f) * 0.06f + noiseLp * 0.35f);
            }
            return o;
        }

        /// <summary>Сурнай/карнай: «медный» пилообразный тон с фильтром.</summary>
        public static float[] Brass(float freq, float seconds, float attack, float vibrato)
        {
            var o = Buffer(seconds);
            float phase = 0f, lp = 0f;
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                float vib = 1f + vibrato * Sin(TwoPi * 5.5f * t) * Math.Min(1f, t / 0.3f);
                phase += freq * vib / SR;
                phase -= (float)Math.Floor(phase);
                float saw = phase * 2f - 1f;
                float env = Math.Min(1f, t / attack) * Math.Min(1f, (seconds - t) / 0.15f);
                float cutoff = 0.08f + 0.25f * env;
                lp += cutoff * (saw - lp);
                o[i] = lp * env;
            }
            return o;
        }

        public static float[] DoiraDum(Random rnd)
        {
            var o = Buffer(0.45f);
            float phase = 0f;
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                float f = 70f + 60f * Exp(-t * 18f);
                phase += TwoPi * f / SR;
                float noise = (float)(rnd.NextDouble() * 2 - 1);
                o[i] = Sin(phase) * Exp(-t * 8f) * 0.9f + noise * Exp(-t * 90f) * 0.25f;
            }
            return o;
        }

        public static float[] DoiraTak(Random rnd)
        {
            var o = Buffer(0.2f);
            float prev = 0f;
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                float noise = (float)(rnd.NextDouble() * 2 - 1);
                float hp = noise - prev;
                prev = noise;
                o[i] = hp * Exp(-t * 40f) * 0.45f + Sin(TwoPi * 880f * t) * Exp(-t * 55f) * 0.35f;
            }
            return o;
        }

        /// <summary>Металлические кольца-зенги на ободе дойры.</summary>
        public static float[] Zang(Random rnd)
        {
            var o = Buffer(0.25f);
            float a = 0f, b = 0f;
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                float noise = (float)(rnd.NextDouble() * 2 - 1);
                a = noise - b * 0.7f;
                b = a;
                o[i] = a * Exp(-t * 22f) * 0.12f * (1f + 0.5f * Sin(TwoPi * 37f * t));
            }
            return o;
        }

        // ------------------------------------------------------------------ Звуки игры

        public static float[] WoodTap(float pitch, Random rnd)
        {
            var o = Buffer(0.16f);
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                float noise = (float)(rnd.NextDouble() * 2 - 1);
                o[i] = Sin(TwoPi * 820f * pitch * t) * Exp(-t * 55f) * 0.5f
                     + Sin(TwoPi * 1530f * pitch * t) * Exp(-t * 80f) * 0.25f
                     + Sin(TwoPi * 190f * pitch * t) * Exp(-t * 28f) * 0.6f
                     + noise * Exp(-t * 220f) * 0.35f;
            }
            return Normalize(o, 0.9f);
        }

        public static float[] Step(Random rnd)
        {
            var o = Buffer(0.06f);
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                float noise = (float)(rnd.NextDouble() * 2 - 1);
                o[i] = (Sin(TwoPi * 1200f * t) * 0.4f + noise * 0.4f) * Exp(-t * 120f);
            }
            return Normalize(o, 0.5f);
        }

        public static float[] Whoosh(Random rnd)
        {
            const float dur = 0.34f;
            var o = Buffer(dur);
            float lp = 0f, lp2 = 0f;
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                float x = t / dur;
                float cutoff = 0.02f + 0.3f * (float)Math.Pow(Math.Sin(Math.PI * Math.Min(1.0, x * 1.15)), 2);
                float noise = (float)(rnd.NextDouble() * 2 - 1);
                lp += cutoff * (noise - lp);
                lp2 += cutoff * (lp - lp2);
                float env = (float)Math.Pow(Math.Sin(Math.PI * x), 2);
                o[i] = (lp - lp2 * 0.6f) * env;
            }
            return Normalize(o, 0.8f);
        }

        /// <summary>Удар клинка: металлический звон с неоднородными обертонами + хруст дерева.</summary>
        public static float[] Impact(Random rnd)
        {
            var o = Buffer(1.1f);
            float[] partials = { 1180f, 1747f, 2491f, 3311f, 4103f };
            float[] decays = { 5f, 7f, 9f, 12f, 15f };
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                float s = 0f;
                for (int k = 0; k < partials.Length; k++) s += Sin(TwoPi * partials[k] * t) * Exp(-t * decays[k]) / (k + 1.5f);
                float noise = (float)(rnd.NextDouble() * 2 - 1);
                o[i] = s * 0.7f + noise * Exp(-t * 60f) * 0.6f + Sin(TwoPi * 95f * t) * Exp(-t * 14f) * 0.7f;
            }
            Add(o, Crack(rnd), (int)(0.02f * SR), 0.9f);
            return Normalize(o, 0.95f);
        }

        public static float[] Crack(Random rnd)
        {
            var o = Buffer(0.6f);
            for (int b = 0; b < 9; b++)
            {
                int start = (int)(rnd.NextDouble() * 0.35 * SR);
                float len = 0.02f + (float)rnd.NextDouble() * 0.05f;
                float amp = 0.4f + (float)rnd.NextDouble() * 0.6f;
                float lp = 0f;
                float cut = 0.15f + (float)rnd.NextDouble() * 0.5f;
                int n = (int)(len * SR);
                for (int i = 0; i < n && start + i < o.Length; i++)
                {
                    float t = i / (float)SR;
                    float noise = (float)(rnd.NextDouble() * 2 - 1);
                    lp += cut * (noise - lp);
                    o[start + i] += lp * amp * Exp(-t * 70f);
                }
            }
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                o[i] += Sin(TwoPi * (110f - 40f * t) * t) * Exp(-t * 12f) * 0.5f;
            }
            return Normalize(o, 0.9f);
        }

        public static float[] Check(Random rnd)
        {
            var o = Buffer(0.9f);
            Add(o, DoiraDum(rnd), 0, 1f);
            Add(o, DoiraTak(rnd), (int)(0.16f * SR), 0.9f);
            Add(o, DoiraTak(rnd), (int)(0.27f * SR), 0.7f);
            Add(o, Zang(rnd), (int)(0.16f * SR), 1f);
            var bell = Buffer(0.8f);
            for (int i = 0; i < bell.Length; i++)
            {
                float t = i / (float)SR;
                bell[i] = (Sin(TwoPi * 1318f * t) + Sin(TwoPi * 1976f * t) * 0.5f + Sin(TwoPi * 3140f * t) * 0.2f) * Exp(-t * 6f) * 0.3f;
            }
            Add(o, bell, (int)(0.05f * SR), 0.6f);
            return Normalize(o, 0.9f);
        }

        /// <summary>Победа: протяжный карнай, затем сурнай и дробь дойры.</summary>
        public static float[] Victory(Random rnd)
        {
            var o = Buffer(4.2f);
            Add(o, Brass(116.54f, 1.6f, 0.35f, 0.004f), 0, 0.7f);
            Add(o, Brass(174.6f, 1.6f, 0.4f, 0.004f), 0, 0.35f);
            float[] melody = { 587.33f, 698.46f, 783.99f, 880f, 783.99f, 880f, 932.33f, 880f };
            float[] lens = { 0.18f, 0.18f, 0.18f, 0.36f, 0.18f, 0.18f, 0.36f, 0.9f };
            float pos = 1.25f;
            for (int i = 0; i < melody.Length; i++)
            {
                Add(o, Brass(melody[i], lens[i] + 0.05f, 0.03f, 0.012f), (int)(pos * SR), 0.45f);
                pos += lens[i];
            }
            for (int k = 0; k < 16; k++)
            {
                float t = 1.25f + k * 0.12f;
                Add(o, k % 4 == 0 ? DoiraDum(rnd) : DoiraTak(rnd), (int)(t * SR), k % 4 == 0 ? 0.6f : 0.35f);
                Add(o, Zang(rnd), (int)(t * SR), 0.6f);
            }
            FadeEdges(o, 0.005f, 0.4f);
            return Normalize(o, 0.9f);
        }

        public static float[] DrawChord(Random rnd)
        {
            var o = Buffer(2.2f);
            float[] f = { 146.83f, 220f, 293.66f, 349.23f };
            for (int i = 0; i < f.Length; i++) Add(o, Pluck(f[i], 2f, rnd, 0.997f), (int)(i * 0.06f * SR), 0.5f);
            return Normalize(o, 0.8f);
        }

        public static float[] Click()
        {
            var o = Buffer(0.06f);
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                o[i] = Sin(TwoPi * 1250f * t) * Math.Min(1f, t / 0.002f) * Exp(-t * 70f);
            }
            return Normalize(o, 0.5f);
        }

        public static float[] Open(Random rnd)
        {
            var o = Buffer(0.6f);
            Add(o, Pluck(587.33f, 0.5f, rnd, 0.993f), 0, 0.6f);
            Add(o, Pluck(880f, 0.45f, rnd, 0.993f), (int)(0.07f * SR), 0.5f);
            return Normalize(o, 0.6f);
        }

        public static float[] Promote(Random rnd)
        {
            var o = Buffer(1.6f);
            float[] arp = { 293.66f, 349.23f, 440f, 587.33f, 698.46f, 880f };
            for (int i = 0; i < arp.Length; i++) Add(o, Pluck(arp[i], 1.2f, rnd, 0.995f, 0.7f), (int)(i * 0.07f * SR), 0.5f);
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                o[i] += Sin(TwoPi * 2349f * t) * Sin(TwoPi * 7f * t) * Exp(-t * 3f) * 0.08f;
            }
            return Normalize(o, 0.85f);
        }

        /// <summary>«Пахлавон!» — гонг и восходящий карнай.</summary>
        public static float[] Hero(Random rnd)
        {
            var o = Buffer(2.4f);
            float[] p = { 196f, 293f, 371f, 523f, 659f };
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                float s = 0f;
                for (int k = 0; k < p.Length; k++) s += Sin(TwoPi * p[k] * t * (1f + 0.002f * Sin(TwoPi * 3f * t))) * Exp(-t * (1.6f + k * 0.8f)) / (k + 1);
                o[i] = s * 0.7f;
            }
            Add(o, Brass(233.08f, 0.8f, 0.08f, 0.006f), (int)(0.1f * SR), 0.4f);
            Add(o, Brass(349.23f, 1.0f, 0.08f, 0.008f), (int)(0.5f * SR), 0.35f);
            return Normalize(o, 0.85f);
        }

        public static float[] Illegal()
        {
            var o = Buffer(0.14f);
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                float sq = Sin(TwoPi * 140f * t) > 0 ? 1f : -1f;
                o[i] = sq * 0.3f * Math.Min(1f, t / 0.005f) * Exp(-t * 18f);
            }
            return o;
        }

        public static float[] Tick()
        {
            var o = Buffer(0.04f);
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                o[i] = Sin(TwoPi * 2200f * t) * Exp(-t * 150f) * 0.5f;
            }
            return o;
        }

        public static float[] Pop(Random rnd)
        {
            var o = Buffer(0.9f);
            for (int i = 0; i < o.Length; i++)
            {
                float t = i / (float)SR;
                float noise = (float)(rnd.NextDouble() * 2 - 1);
                float crackle = rnd.NextDouble() < 0.004 * Exp(-t * 3f) ? (float)(rnd.NextDouble() * 2 - 1) * 2f : 0f;
                o[i] = noise * Exp(-t * 25f) * 0.7f + Sin(TwoPi * 70f * t) * Exp(-t * 15f) * 0.6f + crackle * 0.3f;
            }
            return Normalize(o, 0.7f);
        }

        // ------------------------------------------------------------------ Музыка

        /// <summary>
        /// Петля ~38 с в ладу ре-фригийский: дутар ведёт мелодию, потом её подхватывает най,
        /// дойра держит усул «дум-так-так». Сэмплы, выходящие за конец, заворачиваются в начало —
        /// петля звучит бесшовно.
        /// </summary>
        public static float[] Music(int seed)
        {
            var rnd = new Random(seed);
            const float bpm = 100f;
            float eighth = 60f / bpm / 2f;
            const int bars = 16;
            float total = bars * 8 * eighth;
            var o = Buffer(total);

            float[] scale = { 293.66f, 311.13f, 349.23f, 392f, 440f, 466.16f, 523.25f, 587.33f, 622.25f, 698.46f };
            // -1 = тянуть предыдущую ноту
            int[][] phrases =
            {
                new[] { 4, 4, 3, 4, 5, 4, 3, 2,   3, 2, 1, 2, 0, -1, -1, -1 },
                new[] { 0, 1, 2, 3, 4, -1, 4, 5,  6, 5, 4, 3, 4, -1, -1, -1 },
                new[] { 7, 7, 6, 5, 6, 5, 4, 3,   4, 3, 2, 1, 2, -1, 1, 0 },
                new[] { 2, 3, 4, 2, 3, 1, 2, 0,   1, -1, 0, -1, 0, -1, -1, -1 },
            };
            int[] order = { 0, 1, 0, 2, 3, 1, 2, 3 };

            for (int p = 0; p < order.Length; p++)
            {
                var ph = phrases[order[p]];
                bool nay = p >= 4;
                for (int i = 0; i < ph.Length; i++)
                {
                    if (ph[i] < 0) continue;
                    int len = 1;
                    while (i + len < ph.Length && ph[i + len] < 0) len++;
                    float start = (p * 16 + i) * eighth;
                    float f = scale[ph[i]];
                    if (nay)
                        Add(o, Nay(f * 2f, len * eighth * 0.98f, rnd), (int)(start * SR), 0.16f, true);
                    else
                    {
                        Add(o, Pluck(f, Math.Max(0.6f, len * eighth + 0.4f), rnd, 0.995f), (int)(start * SR), 0.5f, true);
                        // характерное дутарное тремоло на долгих нотах
                        if (len >= 3)
                            for (int k = 1; k < len * 2; k++)
                                Add(o, Pluck(f, 0.35f, rnd, 0.99f, 0.35f), (int)((start + k * eighth * 0.5f) * SR), 0.18f, true);
                    }
                }
            }

            // бурдон второй струны: ре и ля
            for (int i = 0; i < bars * 8; i++)
            {
                float f = (i % 4 == 0) ? 146.83f : (i % 2 == 0 ? 220f : 146.83f);
                Add(o, Pluck(f, 0.9f, rnd, 0.993f, 0.3f), (int)(i * eighth * SR), i % 4 == 0 ? 0.28f : 0.14f, true);
            }

            // дойра: Д . т т Д т . т
            string pattern = "D.ttDt.t";
            for (int bar = 0; bar < bars; bar++)
            {
                for (int k = 0; k < 8; k++)
                {
                    char c = pattern[k];
                    if (c == '.') continue;
                    int at = (int)((bar * 8 + k) * eighth * SR);
                    if (c == 'D') Add(o, DoiraDum(rnd), at, 0.45f, true);
                    else Add(o, DoiraTak(rnd), at, 0.22f, true);
                    Add(o, Zang(rnd), at, 0.35f, true);
                }
                if (bar % 4 == 3)
                    for (int k = 0; k < 4; k++)
                        Add(o, DoiraTak(rnd), (int)((bar * 8 + 6 + k * 0.5f) * eighth * SR), 0.15f, true);
            }
            return Normalize(o, 0.75f);
        }
    }
}
