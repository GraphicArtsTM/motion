using UnityEngine;
using UnityEngine.SceneManagement;

namespace PushPals.Audio
{
    /// <summary>
    /// Музыка (Этап 17): тёплые петли, сыгранные кодом — укулеле (щипки Карплуса — Стронга), ксилофон и мягкий бас.
    /// Три петли: главное меню на столе — тихий вальс шкатулки при свече, коробок (лобби) — укулеле, на уровнях —
    /// бодрее. Переход плавный: из меню в коробок, из коробка на уровень и обратно. Временно, пока нет настоящей музыки.
    /// </summary>
    public class MusicPlayer : MonoBehaviour
    {
        [SerializeField] private float fadeTime = 1.5f;
        [SerializeField, Range(0f, 1f)] private float loudness = 0.45f;

        private const int Rate = 32000;
        private AudioSource a, b;
        private AudioClip menu, lobby, level;
        private bool lobbyScene;
        private bool usingA = true;
        private float fade = 1f;

        public static void Create(GameObject host) => host.AddComponent<MusicPlayer>();

        private void Awake()
        {
            a = NewSource();
            b = NewSource();
            // Лобби: C – Am – F – G, 92 удара в минуту; уровень: F – C – G – Am, 112, мелодия гуще; меню — свой вальс
            menu = ComposeMenu();
            lobby = Compose("Music Lobby", 92f, new[] { 0, 9, 5, 7 }, 0.45f, 11);
            level = Compose("Music Level", 112f, new[] { 5, 0, 7, 9 }, 0.7f, 23);
            SceneManager.sceneLoaded += OnScene;
            OnScene(SceneManager.GetActiveScene(), LoadSceneMode.Single);
        }

        private void OnDestroy() => SceneManager.sceneLoaded -= OnScene;

        private AudioSource NewSource()
        {
            var s = gameObject.AddComponent<AudioSource>();
            s.loop = true;
            s.playOnAwake = false;
            s.spatialBlend = 0f;
            s.volume = 0f;
            return s;
        }

        private void OnScene(Scene scene, LoadSceneMode mode)
        {
            lobbyScene = scene.name == PushPals.Level.LevelLoader.LobbyScene;
            Play(Wanted());
        }

        // Главное меню стоит на столе над коробком (та же сцена) — у него своя музыка, пока оно открыто
        private AudioClip Wanted() => PushPals.UI.MainMenuScreen.Showing ? menu : lobbyScene ? lobby : level;

        private void Play(AudioClip clip)
        {
            var current = usingA ? a : b;
            if (current.clip == clip && current.isPlaying) return;
            usingA = !usingA;
            var incoming = usingA ? a : b;
            incoming.clip = clip;
            incoming.time = 0f;
            incoming.Play();
            fade = 0f;
        }

        private void Update()
        {
            var want = Wanted();
            if ((usingA ? a : b).clip != want) Play(want);
            fade = Mathf.MoveTowards(fade, 1f, Time.unscaledDeltaTime / Mathf.Max(0.1f, fadeTime));
            float v = SoundSettings.MusicVolume * loudness;
            (usingA ? a : b).volume = v * fade;
            var old = usingA ? b : a;
            old.volume = v * (1f - fade);
            if (fade >= 1f && old.isPlaying) old.Stop();
        }

        // ---------- Сочинить петлю ----------

        // Меню: ночная кухня при свече — медленный вальс (3/4, 76 ударов), Dm – G – C – Am. Музыкальная шкатулка
        // ведёт колыбельную фразу, тихая гитара — «раз — два-три», под ними тёплый тянущийся аккорд.
        // Хвосты последних нот переносятся в начало — петля без щелчка на стыке
        private static AudioClip ComposeMenu()
        {
            const float bpm = 76f;
            int[] chords = { 2, 7, 0, 9 };
            // Фраза шкатулки на 4 такта: восьмые (6 на такт), полутона от C5, −1 — пауза
            int[][] phrase =
            {
                new[] { 9, -1, 5, -1, 2, 5 },
                new[] { 7, -1, 11, -1, 14, -1 },
                new[] { 12, -1, 7, -1, 4, 7 },
                new[] { 9, -1, -1, 12, 11, 9 },
            };
            // Второй круг — с проходящими нотами, третий — реже (передышка), четвёртый — как первый, в конце — «ля»
            int[][] fill =
            {
                new[] { 9, 10, 9, 5, 2, 5 },
                new[] { 7, 9, 11, 12, 14, -1 },
                new[] { 12, 11, 12, 7, 4, 7 },
                new[] { 9, -1, 12, 11, 9, 7 },
            };
            var rng = new System.Random(37);
            float beat = 60f / bpm;
            int bars = chords.Length * 4;
            float length = bars * 3 * beat;
            int n = Mathf.CeilToInt(length * Rate);
            var d = new float[n + Rate * 3]; // с запасом под хвосты
            for (int bar = 0; bar < bars; bar++)
            {
                int root = chords[bar % chords.Length];
                int third = Minor(root) ? 3 : 4;
                int cycle = bar / chords.Length;
                float t0 = bar * 3 * beat;
                // Тянущийся аккорд на весь такт
                foreach (int note in new[] { root, root + third, root + 7 })
                    AddPad(d, t0, 3 * beat, Note(note, 3), 0.045f);
                // Гитара: бас на «раз», аккорд на «два» и «три»
                SynthClips.Pluck(d, t0, Note(root, 2), 0.2f, 0.996f, Rate, rng);
                for (int k = 1; k <= 2; k++)
                {
                    int[] chord = { root + third, root + 7, root + 12 };
                    for (int c = 0; c < chord.Length; c++)
                        SynthClips.Pluck(d, t0 + k * beat + c * 0.018f, Note(chord[c], 3), 0.07f, 0.995f, Rate, rng);
                }
                // Шкатулка: колыбельная, на третьем круге — только сильные доли
                var line = cycle == 1 ? fill[bar % 4] : phrase[bar % 4];
                for (int e = 0; e < 6; e++)
                {
                    int note = line[e];
                    if (note < 0 || (cycle == 2 && e % 2 == 1)) continue;
                    if (cycle == 3 && bar % 4 == 3 && e > 0) continue; // в конце — одна долгая «ля»
                    float at = t0 + e * beat * 0.5f;
                    float f = Note(note, 5);
                    SynthClips.AddBell(d, at, f, 0.16f, Rate, 3.2f);
                    SynthClips.AddBell(d, at, f * 2f, 0.035f, Rate, 7f); // звонкий «зубчик» гребёнки
                }
            }
            // Хвосты за концом петли — в её начало
            var loop = new float[n];
            for (int i = 0; i < d.Length; i++) loop[i % n] += d[i];
            float peak = 0.0001f;
            foreach (var x in loop) peak = Mathf.Max(peak, Mathf.Abs(x));
            for (int i = 0; i < n; i++) loop[i] *= 0.7f / peak; // тише остальных — меню спокойное
            var clip = AudioClip.Create("Music Menu", n, 1, Rate, false);
            clip.SetData(loop, 0);
            return clip;
        }

        // Тёплый тянущийся звук (как фисгармония): мягкое нарастание и затухание, чуть «дышит»
        private static void AddPad(float[] d, float start, float duration, float freq, float amp)
        {
            int s0 = Mathf.RoundToInt(start * Rate);
            int len = Mathf.Min(d.Length - s0, Mathf.RoundToInt((duration + 0.6f) * Rate));
            for (int i = 0; i < len; i++)
            {
                float t = i / (float)Rate;
                float env = Mathf.Min(1f, t / 0.35f) * (t < duration ? 1f : Mathf.Exp(-(t - duration) * 6f));
                float wobble = 1f + 0.15f * Mathf.Sin(2f * Mathf.PI * 0.8f * t);
                float w = 2f * Mathf.PI * freq * t;
                d[s0 + i] += amp * env * wobble * (Mathf.Sin(w) + 0.3f * Mathf.Sin(2f * w) + 0.1f * Mathf.Sin(3f * w));
            }
        }

        // Полутона от C: аккорд мажор/минор по ступени (0 — C, 9 — Am …)
        private static float Note(int semitone, int octave) => 261.63f * Mathf.Pow(2f, (semitone + 12 * (octave - 4)) / 12f);
        private static bool Minor(int root) => root == 9 || root == 2 || root == 4;

        private static AudioClip Compose(string name, float bpm, int[] chords, float melodyDensity, int seed)
        {
            var rng = new System.Random(seed);
            float beat = 60f / bpm;
            int bars = chords.Length * 4; // 4 круга аккордов
            float length = bars * 4 * beat;
            var d = new float[Mathf.CeilToInt(length * Rate)];
            int[] scale = { 0, 2, 4, 7, 9 }; // пентатоника — всегда в тон
            int lastNote = 2;
            for (int bar = 0; bar < bars; bar++)
            {
                int root = chords[bar % chords.Length];
                int third = Minor(root) ? 3 : 4;
                float t0 = bar * 4 * beat;
                // Бас: корень на 1 и 3
                SynthClips.AddBell(d, t0, Note(root, 2), 0.35f, Rate, 3f);
                SynthClips.AddBell(d, t0 + 2 * beat, Note(root, 2), 0.25f, Rate, 3f);
                // Укулеле: «бой» вниз-вверх (1, 2+, 3, 4)
                float[] strums = { 0f, 1.5f, 2f, 3f };
                foreach (var s in strums)
                {
                    int[] chord = { root, root + third, root + 7, root + 12 };
                    for (int k = 0; k < chord.Length; k++)
                        SynthClips.Pluck(d, t0 + s * beat + k * 0.012f, Note(chord[k], 4), s == 0f ? 0.16f : 0.11f, 0.994f, Rate, rng);
                }
                // Ксилофон: мелодия по пентатонике восьмыми, ходит плавно
                for (int e = 0; e < 8; e++)
                {
                    if (rng.NextDouble() > melodyDensity) continue;
                    lastNote = Mathf.Clamp(lastNote + rng.Next(-2, 3), 0, scale.Length * 2 - 1);
                    int semitone = scale[lastNote % scale.Length] + 12 * (lastNote / scale.Length);
                    SynthClips.AddBell(d, t0 + e * beat * 0.5f, Note(semitone, 5), 0.22f, Rate, 7f);
                }
            }
            // Нормировка
            float peak = 0.0001f;
            foreach (var x in d) peak = Mathf.Max(peak, Mathf.Abs(x));
            for (int i = 0; i < d.Length; i++) d[i] *= 0.8f / peak;
            var clip = AudioClip.Create(name, d.Length, 1, Rate, false);
            clip.SetData(d, 0);
            return clip;
        }
    }
}
