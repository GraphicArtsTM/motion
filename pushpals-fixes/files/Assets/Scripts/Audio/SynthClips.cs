using UnityEngine;

namespace PushPals.Audio
{
    /// <summary>
    /// Звуки, которых нет в наборах Kenney, — синтез при запуске: чирканье о тёрку, вспышка, «пшш» в воде,
    /// хлопок шарика, «боинг» желе, звон звезды, фанфары, взрыв петарды, треск огня (петля), мягкий шаг.
    /// </summary>
    public static class SynthClips
    {
        private const int Rate = 44100;
        private static System.Random random = new System.Random(7);

        private static float Noise() => (float)(random.NextDouble() * 2.0 - 1.0);

        private static AudioClip Make(string name, float[] data)
        {
            // Нормировать громкость (без щелчка в конце)
            float peak = 0.0001f;
            foreach (var s in data) peak = Mathf.Max(peak, Mathf.Abs(s));
            float k = 0.9f / peak;
            for (int i = 0; i < data.Length; i++) data[i] *= k;
            var clip = AudioClip.Create(name, data.Length, 1, Rate, false);
            clip.SetData(data, 0);
            return clip;
        }

        private static float[] Buffer(float seconds) => new float[Mathf.CeilToInt(seconds * Rate)];

        /// <summary>
        /// Шаг спички по столу: глухое короткое «топ» — низкий тук с лёгким шорохом, без звонкого щелчка
        /// (стук дерева Kenney на каждый шаг резал слух). variant — свой разброс, чтобы шаги не звучали одинаково.
        /// </summary>
        public static AudioClip Step(int variant)
        {
            var r = new System.Random(100 + variant);
            var d = Buffer(0.09f);
            float lp = 0f, freq = 140f + variant * 17f;
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)Rate;
                lp += 0.1f * ((float)(r.NextDouble() * 2.0 - 1.0) - lp);                 // глухой шорох — только низы
                float thump = Mathf.Sin(2f * Mathf.PI * freq * t * (1f - t * 3f)) * Mathf.Exp(-t * 60f); // тук, чуть «проседает»
                float env = Mathf.Min(1f, t / 0.004f) * Mathf.Exp(-t * 40f);
                d[i] = (thump * 0.8f + lp * 1.5f) * env;
            }
            return Make("step_soft", d);
        }

        /// <summary>Чирк о тёрку: короткий шершавый шум с «зубчиками».</summary>
        public static AudioClip Strike()
        {
            var d = Buffer(0.25f);
            float hp = 0f, prev = 0f;
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)Rate;
                float n = Noise();
                hp = 0.85f * (hp + n - prev); prev = n;           // убрать низ — шуршание
                float teeth = 0.6f + 0.4f * Mathf.Sin(t * 2f * Mathf.PI * 70f);
                float env = Mathf.Min(1f, t / 0.01f) * Mathf.Exp(-t * 14f);
                d[i] = hp * teeth * env;
            }
            return Make("strike", d);
        }

        /// <summary>Вспышка головки: шум, который «раскрывается» (фильтр открывается).</summary>
        public static AudioClip Ignite()
        {
            var d = Buffer(0.55f);
            float lp = 0f;
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)Rate;
                float a = Mathf.Lerp(0.02f, 0.3f, Mathf.Clamp01(t / 0.12f));
                lp += a * (Noise() - lp);
                d[i] = lp * Mathf.Min(1f, t / 0.03f) * Mathf.Exp(-t * 5f);
            }
            return Make("ignite", d);
        }

        /// <summary>«Пшш» — огонь в воде.</summary>
        public static AudioClip Fizz()
        {
            var d = Buffer(0.9f);
            float hp = 0f, prev = 0f;
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)Rate;
                float n = Noise();
                hp = 0.95f * (hp + n - prev); prev = n;
                d[i] = hp * Mathf.Min(1f, t / 0.02f) * Mathf.Exp(-t * 3.5f) * (0.8f + 0.2f * Noise());
            }
            return Make("fizz", d);
        }

        /// <summary>Хлопок шарика.</summary>
        public static AudioClip Pop()
        {
            var d = Buffer(0.18f);
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)Rate;
                float burst = Noise() * Mathf.Exp(-t * 90f);
                float thump = Mathf.Sin(t * 2f * Mathf.PI * 140f) * Mathf.Exp(-t * 35f) * 0.6f;
                d[i] = burst + thump;
            }
            return Make("pop", d);
        }

        /// <summary>«Боинг» желе: тон вверх с дрожью.</summary>
        public static AudioClip Boing()
        {
            var d = Buffer(0.5f);
            float phase = 0f;
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)Rate;
                float f = Mathf.Lerp(170f, 400f, Mathf.Clamp01(t / 0.25f)) * (1f + 0.06f * Mathf.Sin(t * 2f * Mathf.PI * 14f));
                phase += f / Rate;
                d[i] = Mathf.Sin(phase * 2f * Mathf.PI) * Mathf.Min(1f, t / 0.01f) * Mathf.Exp(-t * 6f);
            }
            return Make("boing", d);
        }

        /// <summary>Звон звезды: два колокольчика.</summary>
        public static AudioClip Chime()
        {
            var d = Buffer(1f);
            AddBell(d, 0f, 1318.5f, 0.6f);
            AddBell(d, 0.09f, 1760f, 0.5f);
            AddBell(d, 0.18f, 2637f, 0.3f);
            return Make("chime", d);
        }

        /// <summary>Фанфары «уровень пройден»: арпеджио щипками и аккорд.</summary>
        public static AudioClip Fanfare()
        {
            var d = Buffer(2f);
            float[] notes = { 523.25f, 659.25f, 783.99f, 1046.5f };
            for (int i = 0; i < notes.Length; i++) Pluck(d, 0.12f * i, notes[i], 0.7f, 0.996f);
            foreach (var n in notes) Pluck(d, 0.6f, n, 0.45f, 0.998f);
            AddBell(d, 0.6f, 2093f, 0.25f);
            return Make("fanfare", d);
        }

        /// <summary>Взрыв петарды.</summary>
        public static AudioClip Boom()
        {
            var d = Buffer(1f);
            float lp = 0f;
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)Rate;
                lp += 0.08f * (Noise() - lp);
                d[i] = (lp * 3f + Mathf.Sin(t * 2f * Mathf.PI * 55f) * 0.8f) * Mathf.Exp(-t * 5f) + Noise() * Mathf.Exp(-t * 60f) * 0.5f;
            }
            return Make("boom", d);
        }

        /// <summary>Треск огня — петля 2 с (редкие щелчки).</summary>
        public static AudioClip Crackle()
        {
            var d = Buffer(2f);
            float lp = 0f;
            for (int i = 0; i < d.Length; i++)
            {
                lp += 0.05f * (Noise() - lp);
                d[i] = lp * 0.4f; // тихое шипение
            }
            for (int c = 0; c < 70; c++)
            {
                int at = random.Next(d.Length - 600);
                float amp = 0.3f + (float)random.NextDouble() * 0.7f;
                for (int k = 0; k < 500; k++) d[at + k] += Noise() * amp * Mathf.Exp(-k / 60f);
            }
            return Make("crackle", d);
        }

        // ---------- Кирпичики (и для музыки) ----------

        /// <summary>Колокольчик / ксилофон: синус с обертоном и быстрым затуханием.</summary>
        public static void AddBell(float[] d, float start, float freq, float amp, int rate = Rate, float decay = 6f)
        {
            int s0 = Mathf.RoundToInt(start * rate);
            int len = Mathf.Min(d.Length - s0, rate);
            for (int i = 0; i < len; i++)
            {
                float t = i / (float)rate;
                float env = Mathf.Min(1f, t / 0.003f) * Mathf.Exp(-t * decay);
                d[s0 + i] += amp * env * (Mathf.Sin(2f * Mathf.PI * freq * t) + 0.25f * Mathf.Sin(2f * Mathf.PI * freq * 4f * t) * Mathf.Exp(-t * 20f));
            }
        }

        /// <summary>Щипок струны (Карплус — Стронг): укулеле, гитара.</summary>
        public static void Pluck(float[] d, float start, float freq, float amp, float damping, int rate = Rate, System.Random rng = null)
        {
            rng = rng ?? random;
            int period = Mathf.Max(2, Mathf.RoundToInt(rate / freq));
            var line = new float[period];
            for (int i = 0; i < period; i++) line[i] = (float)(rng.NextDouble() * 2.0 - 1.0);
            int s0 = Mathf.RoundToInt(start * rate);
            int len = Mathf.Min(d.Length - s0, rate * 2);
            int idx = 0;
            for (int i = 0; i < len; i++)
            {
                int next = (idx + 1) % period;
                float v = line[idx];
                line[idx] = damping * 0.5f * (line[idx] + line[next]);
                d[s0 + i] += v * amp;
                idx = next;
            }
        }
    }
}
