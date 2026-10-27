using System.Collections.Generic;
using UnityEngine;

namespace PushPals.Audio
{
    /// <summary>
    /// Звуки игры (Этап 17): Sfx.Play("impactWood_medium", точка, громкость). Клипы — из Resources/Sfx (Kenney, CC0;
    /// «группа» — имя без номера: impactWood_medium_003 → impactWood_medium, из группы берётся случайный) плюс синтез (SynthClips).
    /// Игра двумерная: громкость тише вдали от камеры, звук слева/справа по положению. Частые одинаковые звуки прореживаются.
    /// </summary>
    public class Sfx : MonoBehaviour
    {
        [Tooltip("Сколько звуков может звучать одновременно")]
        [SerializeField] private int voices = 20;
        [Tooltip("Дальше этого от камеры (м) звук еле слышен")]
        [SerializeField] private float hearDistance = 22f;
        [Tooltip("Один и тот же звук не чаще, с")]
        [SerializeField] private float minRepeat = 0.04f;

        private static Sfx instance;
        private readonly Dictionary<string, List<AudioClip>> groups = new Dictionary<string, List<AudioClip>>();
        private readonly Dictionary<string, float> lastPlayed = new Dictionary<string, float>();
        private readonly List<AudioSource> pool = new List<AudioSource>();
        private int next;

        /// <summary>Звуки загружены.</summary>
        public static bool Ready => instance != null;

        public static void Create(GameObject host)
        {
            if (instance != null) return;
            instance = host.AddComponent<Sfx>();
        }

        private void Awake()
        {
            foreach (var clip in Resources.LoadAll<AudioClip>("Sfx")) AddClip(Group(clip.name), clip);
            AddClip("strike", SynthClips.Strike());
            AddClip("ignite", SynthClips.Ignite());
            AddClip("fizz", SynthClips.Fizz());
            AddClip("pop", SynthClips.Pop());
            AddClip("boing", SynthClips.Boing());
            AddClip("chime", SynthClips.Chime());
            AddClip("fanfare", SynthClips.Fanfare());
            AddClip("boom", SynthClips.Boom());
            AddClip("crackle", SynthClips.Crackle());
            for (int i = 0; i < 4; i++) AddClip("step_soft", SynthClips.Step(i));
            for (int i = 0; i < voices; i++)
            {
                var s = gameObject.AddComponent<AudioSource>();
                s.playOnAwake = false;
                s.spatialBlend = 0f;
                pool.Add(s);
            }
        }

        private void OnDestroy()
        {
            if (instance == this) instance = null;
        }

        // impactWood_heavy_002 → impactWood_heavy
        private static string Group(string name)
        {
            int u = name.LastIndexOf('_');
            if (u > 0 && u < name.Length - 1 && char.IsDigit(name[u + 1])) return name.Substring(0, u);
            return name;
        }

        private void AddClip(string group, AudioClip clip)
        {
            List<AudioClip> list;
            if (!groups.TryGetValue(group, out list)) groups[group] = list = new List<AudioClip>();
            list.Add(clip);
        }

        /// <summary>Клип по имени группы (для петель — треск огня).</summary>
        public static AudioClip Clip(string group)
        {
            List<AudioClip> list;
            if (instance == null || !instance.groups.TryGetValue(group, out list) || list.Count == 0) return null;
            return list[Random.Range(0, list.Count)];
        }

        /// <summary>Звук интерфейса (без места, по центру).</summary>
        public static void Ui(string group, float volume = 0.6f) => Play(group, null, volume, 0f);

        /// <summary>Звук в мире. pitchJitter — разброс высоты (0,08 — живее).</summary>
        public static void Play(string group, Vector2? at, float volume = 1f, float pitchJitter = 0.08f)
        {
            if (instance == null || volume <= 0.01f) return;
            instance.PlayInternal(group, at, volume, pitchJitter, 1f);
        }

        /// <summary>Звук в мире со своей высотой (шаг Тяжёлого ниже, Маленького выше).</summary>
        public static void Play(string group, Vector2? at, float volume, float pitchJitter, float pitch)
        {
            if (instance == null || volume <= 0.01f) return;
            instance.PlayInternal(group, at, volume, pitchJitter, pitch);
        }

        private void PlayInternal(string group, Vector2? at, float volume, float pitchJitter, float pitch)
        {
            var clip = Clip(group);
            if (clip == null) return;
            float now = Time.unscaledTime, last;
            if (lastPlayed.TryGetValue(group, out last) && now - last < minRepeat) return;
            lastPlayed[group] = now;

            float pan = 0f, distance = 1f;
            var cam = Camera.main;
            if (at.HasValue && cam != null)
            {
                Vector2 c = cam.transform.position;
                Vector2 d = at.Value - c;
                distance = 1f - Mathf.Clamp01((d.magnitude - hearDistance * 0.4f) / (hearDistance * 0.6f));
                pan = Mathf.Clamp(d.x / (hearDistance * 0.6f), -0.7f, 0.7f);
            }
            float v = volume * distance * SoundSettings.EffectsVolume;
            if (v <= 0.01f) return;

            // Свободный голос или самый старый
            AudioSource src = null;
            for (int i = 0; i < pool.Count; i++)
            {
                var s = pool[(next + i) % pool.Count];
                if (!s.isPlaying) { src = s; next = (next + i + 1) % pool.Count; break; }
            }
            if (src == null) { src = pool[next]; next = (next + 1) % pool.Count; }
            src.clip = clip;
            src.volume = Mathf.Clamp01(v);
            src.pitch = pitch * (1f + Random.Range(-pitchJitter, pitchJitter));
            src.panStereo = pan;
            src.Play();
        }
    }
}
