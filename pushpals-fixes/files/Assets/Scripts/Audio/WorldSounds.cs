using System.Collections.Generic;
using PushPals.Fire;
using PushPals.Level;
using PushPals.Players;
using PushPals.Ragdoll;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace PushPals.Audio
{
    /// <summary>
    /// Звуки мира (Этап 17) без правок в каждом элементе: раз в кадр смотрит на состояния (кнопка нажата, дверь открылась,
    /// золотая спичка взята, шарик лопнул, желе подбросило, огонь вспыхнул) — так звучит одинаково у хоста и у сетевого клиента
    /// (у клиента состояния приходят снимком). Спички: удары деревом, шаги, приземление, хват, шлепок, «боднуть», огонь;
    /// у сетевого клиента события физики не приходят — там по переходам состояний (приземлился, загорелся).
    /// </summary>
    public class WorldSounds : MonoBehaviour
    {
        [Tooltip("Удар частью тела быстрее этого (м/с) — стук дерева")]
        [SerializeField] private float knockSpeed = 2.5f;

        public static void Create(GameObject host) => host.AddComponent<WorldSounds>();

        // ---------- Элементы уровня ----------

        private class Tracked<T> where T : Component
        {
            public T Item;
            public bool State;
            public int Count;
        }

        private readonly List<Tracked<PressurePlate>> plates = new List<Tracked<PressurePlate>>();
        private readonly List<Tracked<Door>> doors = new List<Tracked<Door>>();
        private readonly List<Tracked<GoldenMatch>> stars = new List<Tracked<GoldenMatch>>();
        private readonly List<Tracked<MatchboxCheckpoint>> boxes = new List<Tracked<MatchboxCheckpoint>>();
        private readonly List<Tracked<Balloon>> balloons = new List<Tracked<Balloon>>();
        private readonly List<Tracked<Jelly>> jellies = new List<Tracked<Jelly>>();
        private readonly List<Tracked<Candle>> candles = new List<Tracked<Candle>>();
        private readonly List<Tracked<RibbonGate>> gifts = new List<Tracked<RibbonGate>>();
        private readonly List<Tracked<CandleGoal>> cakes = new List<Tracked<CandleGoal>>();
        private bool finished;

        private void Awake()
        {
            SceneManager.sceneLoaded += (s, m) => Collect();
            Collect();
        }

        private void Collect()
        {
            Fill(plates, p => p.IsPressed, null);
            Fill(doors, d => d.IsOpen, null);
            Fill(stars, s => s.Collected, null);
            Fill(boxes, b => b.IsOpen, null);
            Fill(balloons, b => b.IsAlive, null);
            Fill(jellies, null, j => j.Bounces);
            Fill(candles, c => c.IsLit, null);
            Fill(gifts, g => g.IsOpen, null);
            Fill(cakes, c => c.IsDone, null);
            finished = false;
            foreach (var m in matches.Values) if (m.Crackle != null) Destroy(m.Crackle); // треск прошлой сцены
            matches.Clear();
        }

        private static void Fill<T>(List<Tracked<T>> list, System.Func<T, bool> state, System.Func<T, int> count) where T : Component
        {
            list.Clear();
            foreach (var item in FindObjectsByType<T>(FindObjectsSortMode.None))
                list.Add(new Tracked<T> { Item = item, State = state != null && state(item), Count = count != null ? count(item) : 0 });
        }

        // Переход состояния → звук
        private static void Watch<T>(List<Tracked<T>> list, System.Func<T, bool> state, System.Action<T, bool> changed) where T : Component
        {
            foreach (var t in list)
            {
                if (t.Item == null) continue;
                bool now = state(t.Item);
                if (now != t.State) { t.State = now; changed(t.Item, now); }
            }
        }

        private void Update()
        {
            Watch(plates, p => p.IsPressed, (p, on) => Sfx.Play(on ? "toggle" : "click", p.transform.position, 0.7f));
            Watch(doors, d => d.IsOpen, (d, on) => Sfx.Play(on ? "impactPlank_medium" : "impactWood_medium", d.transform.position, 0.8f));
            Watch(stars, s => s.Collected, (s, on) => { if (on) Sfx.Play("chime", s.transform.position, 0.9f, 0f); });
            Watch(boxes, b => b.IsOpen, (b, on) => { if (on) Sfx.Play("bong", b.transform.position, 0.6f); });
            Watch(balloons, b => b.IsAlive, (b, alive) => Sfx.Play(alive ? "pluck" : "pop", b.Body != null ? b.Body.position : (Vector2)b.transform.position, alive ? 0.3f : 1f));
            Watch(candles, c => c.IsLit, (c, lit) => Sfx.Play(lit ? "ignite" : "fizz", c.transform.position, 0.6f));
            Watch(gifts, g => g.IsOpen, (g, on) => { if (on) Sfx.Play("confirmation", g.transform.position, 0.8f, 0f); });
            Watch(cakes, c => c.IsDone, (c, on) => { if (on) Sfx.Ui("fanfare", 0.9f); });
            foreach (var j in jellies)
            {
                if (j.Item == null) continue;
                int n = j.Item.Bounces;
                if (n != j.Count) { j.Count = n; Sfx.Play("boing", j.Item.transform.position, 0.7f, 0.12f); }
            }
            var run = LevelRun.Instance;
            if (run != null && run.Finished && !finished) { finished = true; Sfx.Ui("fanfare", 0.9f); }

            Matches();
        }

        // ---------- Спички ----------

        private class MatchState
        {
            public RagdollController Controller;
            public MatchFire Fire;
            public bool Grounded, Burning, Stunned, Ghost;
            public float StepPhase, LastStep = -10f;
            public AudioSource Crackle;
        }

        private readonly Dictionary<RagdollController, MatchState> matches = new Dictionary<RagdollController, MatchState>();
        private float scanTimer;

        [Header("Шаги")]
        [Tooltip("Один шаг одной спички не чаще, с (раньше — на каждый полушаг, дробью)")]
        [SerializeField] private float stepInterval = 0.27f;
        [Tooltip("Шаги всех спичек вместе не чаще, с — вчетвером не сливаются в стук")]
        [SerializeField] private float anyStepInterval = 0.08f;
        [Tooltip("Медленнее этого (м/с) — не шаг (упёрся в стену, топчется на месте)")]
        [SerializeField] private float stepMinSpeed = 0.6f;
        [Tooltip("Громкость шага: медленно — быстро")]
        [SerializeField] private Vector2 stepVolume = new Vector2(0.07f, 0.15f);
        private float lastAnyStep = -10f;

        private void Matches()
        {
            if ((scanTimer -= Time.deltaTime) <= 0f)
            {
                scanTimer = 1f;
                foreach (var c in FindObjectsByType<RagdollController>(FindObjectsSortMode.None))
                    if (!matches.ContainsKey(c)) Hook(c);
            }
            foreach (var kv in matches)
            {
                var m = kv.Value;
                var c = m.Controller;
                if (c == null || !c.Body.IsBuilt) continue;
                Vector2 at = c.Body.Torso.Body.position;

                // Приземлился (и у клиента — по снимку)
                bool grounded = c.IsGrounded;
                if (grounded && !m.Grounded && c.IsRemoteView) Sfx.Play("impactSoft_medium", at, 0.5f);
                m.Grounded = grounded;

                // Шаги — мягкое «топ» (синтез): только когда правда идёт, не чаще stepInterval, тише медленно;
                // Тяжёлый — ниже и громче, Маленький — выше и тише
                if (grounded && !c.IsRemoteView && !c.IsGhost && c.WalkAmount > 0.3f)
                {
                    float phase = Mathf.Repeat(c.WalkPhase, Mathf.PI);
                    float speed = Mathf.Abs(c.Body.Velocity.x);
                    float now = Time.time;
                    if (phase < m.StepPhase && speed > stepMinSpeed && now - m.LastStep >= stepInterval && now - lastAnyStep >= anyStepInterval)
                    {
                        m.LastStep = lastAnyStep = now;
                        float size = Mathf.InverseLerp(0.5f, 0.86f, c.Profile.LegLength); // ноги: Маленький 0,52 … Тяжёлый 0,84
                        float volume = Mathf.Lerp(stepVolume.x, stepVolume.y, Mathf.InverseLerp(stepMinSpeed, 3f, speed)) * Mathf.Lerp(0.75f, 1.25f, size);
                        Sfx.Play("step_soft", c.Body.HipPoint, volume, 0.06f, Mathf.Lerp(1.25f, 0.8f, size));
                    }
                    m.StepPhase = phase;
                }

                // Огонь: вспыхнул / погас (у клиента тоже)
                bool burning = m.Fire != null && m.Fire.IsBurning;
                if (burning != m.Burning && c.IsRemoteView) Sfx.Play(burning ? "ignite" : "fizz", at, 0.6f);
                m.Burning = burning;
                UpdateCrackle(m, burning, at);

                bool ghost = c.IsGhost;
                if (ghost && !m.Ghost) Sfx.Play("maximize", at, 0.5f, 0f);
                m.Ghost = ghost;
                if (c.IsRemoteView && c.IsStunned && !m.Stunned) Sfx.Play("impactWood_heavy", at, 0.8f);
                m.Stunned = c.IsStunned;
            }
        }

        private void Hook(RagdollController c)
        {
            var m = new MatchState { Controller = c, Fire = c.GetComponent<MatchFire>() };
            matches[c] = m;
            // События физики — у хоста и за одним ПК
            c.Body.Impact += (part, speed) =>
            {
                if (speed < knockSpeed || c.IsRemoteView) return;
                string kind = speed > 9f ? "impactWood_heavy" : speed > 5f ? "impactWood_medium" : "impactWood_light";
                Sfx.Play(kind, part.Body.position, Mathf.Clamp01(speed / 10f));
                if (speed > 9f) CameraShake.Shake(0.15f);
            };
            c.Landed += impact => Sfx.Play("impactSoft_medium", c.Body.Torso.Body.position, Mathf.Clamp01(0.3f + impact * 0.05f));
            c.Jumped += () => Sfx.Play("impactSoft_medium", c.Body.Torso.Body.position, 0.2f, 0.15f);
            c.Stunned += () => Sfx.Play("impactWood_heavy", c.Body.Head.Body.position, 0.9f);
            var grab = c.GetComponent<RagdollGrab>();
            if (grab != null)
            {
                grab.Grabbed += left => Sfx.Play("impactGeneric_light", c.Body.Torso.Body.position, 0.4f);
                grab.Slapped += left => Sfx.Play("impactPunch_medium", c.Body.Torso.Body.position, 0.7f);
            }
            var butt = c.GetComponent<RagdollHeadbutt>();
            if (butt != null) butt.Headbutted += hit => { if (hit != null) Sfx.Play("impactWood_medium", c.Body.Head.Body.position, 0.7f); };
            if (m.Fire != null)
            {
                m.Fire.Ignited += () => { Sfx.Play("strike", c.Body.Head.Body.position, 0.8f); Sfx.Play("ignite", c.Body.Head.Body.position, 0.7f); };
                m.Fire.Extinguished += wet => Sfx.Play(wet ? "fizz" : "back", c.Body.Head.Body.position, 0.7f);
                m.Fire.BurntOut += () => Sfx.Play("fizz", c.Body.Head.Body.position, 0.4f);
            }
        }

        // Треск горящей головки — петля, тише вдали
        private void UpdateCrackle(MatchState m, bool burning, Vector2 at)
        {
            if (!burning)
            {
                if (m.Crackle != null) m.Crackle.Stop();
                return;
            }
            if (m.Crackle == null)
            {
                m.Crackle = gameObject.AddComponent<AudioSource>();
                m.Crackle.clip = Sfx.Clip("crackle");
                m.Crackle.loop = true;
                m.Crackle.spatialBlend = 0f;
            }
            var cam = Camera.main;
            float near = cam != null ? 1f - Mathf.Clamp01((Vector2.Distance(cam.transform.position, at) - 6f) / 14f) : 1f;
            m.Crackle.volume = 0.18f * near * SoundSettings.EffectsVolume;
            if (!m.Crackle.isPlaying) m.Crackle.Play();
        }
    }
}
