using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    /// <summary>
    /// Zarra effektlari: uchqunlar, chaqnash, halqa to'lqini, chang, yulduzlar, suv, oltin zarralar.
    /// Har bir tur uchun bitta dunyoviy ParticleSystem — Emit() orqali (samarali).
    /// </summary>
    public static class VFX
    {
        public enum Kind { Spark, Flash, Ring, Dust, Star, Water, Ember, Smoke, Shard, Glow }

        static readonly Dictionary<Kind, ParticleSystem> systems = new Dictionary<Kind, ParticleSystem>();
        static Transform root;

        public static void Init()
        {
            if (root != null) return;
            root = new GameObject("VFX").transform;
            Object.DontDestroyOnLoad(root.gameObject);
            Create(Kind.Spark, TextureFactory.SoftDot(), true, ParticleSystemRenderMode.Stretch, 0f, 2f);
            Create(Kind.Flash, TextureFactory.SoftDot(), true, ParticleSystemRenderMode.Billboard, 0f, 0f);
            Create(Kind.Ring, TextureFactory.Ring(), true, ParticleSystemRenderMode.Billboard, 0f, 0f);
            Create(Kind.Dust, TextureFactory.Smoke(), false, ParticleSystemRenderMode.Billboard, -0.02f, 0f);
            Create(Kind.Star, TextureFactory.Star(), true, ParticleSystemRenderMode.Billboard, 0.2f, 0f);
            Create(Kind.Water, TextureFactory.HardDot(), false, ParticleSystemRenderMode.Stretch, 1.2f, 1f);
            Create(Kind.Ember, TextureFactory.SoftDot(), true, ParticleSystemRenderMode.Billboard, -0.05f, 0f);
            Create(Kind.Smoke, TextureFactory.Smoke(), false, ParticleSystemRenderMode.Billboard, -0.05f, 0f);
            Create(Kind.Shard, TextureFactory.HardDot(), true, ParticleSystemRenderMode.Stretch, 1f, 1f);
            Create(Kind.Glow, TextureFactory.SoftDot(), true, ParticleSystemRenderMode.Billboard, 0f, 0f);
        }

        static void Create(Kind k, Texture2D tex, bool additive, ParticleSystemRenderMode mode, float gravity, float stretch)
        {
            var go = new GameObject("PS_" + k);
            go.transform.SetParent(root, false);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main;
            main.loop = true;
            main.duration = 1f;
            main.playOnAwake = false;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.maxParticles = 3000;
            main.gravityModifier = gravity;
            main.startSpeed = 0;
            main.scalingMode = ParticleSystemScalingMode.Hierarchy;
            var em = ps.emission;
            em.enabled = false;
            var sh = ps.shape;
            sh.enabled = false;

            var col = ps.colorOverLifetime;
            col.enabled = true;
            var g = new Gradient();
            g.SetKeys(new[] { new GradientColorKey(Color.white, 0), new GradientColorKey(Color.white, 1) },
                new[] { new GradientAlphaKey(1, 0), new GradientAlphaKey(k == Kind.Dust || k == Kind.Smoke ? 0.6f : 0.9f, 0.4f), new GradientAlphaKey(0, 1) });
            col.color = g;

            var size = ps.sizeOverLifetime;
            size.enabled = true;
            AnimationCurve curve;
            switch (k)
            {
                case Kind.Ring: curve = AnimationCurve.EaseInOut(0, 0.2f, 1, 1.6f); break;
                case Kind.Flash: curve = new AnimationCurve(new Keyframe(0, 0.6f), new Keyframe(0.15f, 1f), new Keyframe(1, 0.2f)); break;
                case Kind.Dust:
                case Kind.Smoke: curve = AnimationCurve.EaseInOut(0, 0.4f, 1, 1.5f); break;
                case Kind.Star: curve = new AnimationCurve(new Keyframe(0, 0.2f), new Keyframe(0.2f, 1f), new Keyframe(1, 0f)); break;
                default: curve = AnimationCurve.Linear(0, 1, 1, 0); break;
            }
            size.size = new ParticleSystem.MinMaxCurve(1f, curve);

            if (k == Kind.Dust || k == Kind.Smoke || k == Kind.Spark || k == Kind.Ember)
            {
                var lv = ps.limitVelocityOverLifetime;
                lv.enabled = true;
                lv.dampen = k == Kind.Spark ? 0.12f : 0.08f;
                lv.limit = 0.5f;
            }
            if (k == Kind.Star || k == Kind.Shard)
            {
                var rot = ps.rotationOverLifetime;
                rot.enabled = true;
                rot.z = new ParticleSystem.MinMaxCurve(-4f, 4f);
            }

            var r = go.GetComponent<ParticleSystemRenderer>();
            r.renderMode = mode;
            if (mode == ParticleSystemRenderMode.Stretch)
            {
                r.velocityScale = 0.04f * stretch;
                r.lengthScale = 1.2f;
            }
            r.sharedMaterial = additive ? Mat.Additive(tex, Color.white) : Mat.Alpha(tex, Color.white);
            r.sortingFudge = additive ? -10 : 0;
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            ps.Play();
            systems[k] = ps;
        }

        public static void Emit(Kind k, Vector3 pos, Color color, int count, float speed, float size, float life, Vector3 dirBias = default, float spread = 1f)
        {
            if (!systems.TryGetValue(k, out var ps) || ps == null) return;
            var ep = new ParticleSystem.EmitParams();
            for (int i = 0; i < count; i++)
            {
                Vector3 rnd = Random.insideUnitSphere;
                rnd.z *= 0.4f;
                Vector3 v = (dirBias + rnd * spread).normalized * speed * Random.Range(0.5f, 1.2f);
                if (dirBias == default && spread <= 0) v = Vector3.zero;
                ep.position = pos + Random.insideUnitSphere * 0.03f;
                ep.velocity = v;
                ep.startColor = color;
                ep.startSize = size * Random.Range(0.7f, 1.3f);
                ep.startLifetime = life * Random.Range(0.7f, 1.2f);
                ep.rotation = Random.Range(0, 360f);
                ps.Emit(ep, 1);
            }
        }

        // ---------------- Tayyor kompozitsiyalar ----------------
        public static void HitSpark(Vector3 pos, HitFx type, bool blocked, float power, float dir)
        {
            Color main, core = Color.white;
            switch (type)
            {
                case HitFx.Slash: main = new Color(1f, 0.55f, 0.25f); break;
                case HitFx.Magic: main = new Color(0.65f, 0.45f, 1f); break;
                case HitFx.Star: main = new Color(0.55f, 0.75f, 1f); core = new Color(1, 0.95f, 0.7f); break;
                case HitFx.Water: main = new Color(0.4f, 0.8f, 1f); break;
                case HitFx.Arrow: main = new Color(1f, 0.8f, 0.4f); break;
                case HitFx.Gold: main = new Color(1f, 0.78f, 0.25f); break;
                case HitFx.Wind: main = new Color(0.7f, 1f, 0.9f); break;
                case HitFx.Earth: main = new Color(0.9f, 0.6f, 0.3f); break;
                default: main = new Color(1f, 0.75f, 0.45f); break;
            }
            if (blocked) { main = new Color(0.55f, 0.8f, 1f); core = new Color(0.85f, 0.95f, 1f); }
            Vector3 bias = new Vector3(dir, 0.25f, 0);
            Emit(Kind.Flash, pos, core * 1.2f, 1, 0, 0.9f * power, 0.12f, default, 0);
            Emit(Kind.Flash, pos, main, 1, 0, 1.6f * power, 0.18f, default, 0);
            Emit(Kind.Spark, pos, main, Mathf.RoundToInt(14 * power), 9f * power, 0.07f, 0.25f, bias, 0.9f);
            Emit(Kind.Spark, pos, core, Mathf.RoundToInt(6 * power), 13f * power, 0.05f, 0.18f, bias, 0.6f);
            Emit(Kind.Ring, pos, main.WithA(0.8f), 1, 0, 1.1f * power, 0.22f, default, 0);
            if (type == HitFx.Star || type == HitFx.Magic) Emit(Kind.Star, pos, main, Mathf.RoundToInt(8 * power), 3f, 0.25f, 0.6f, bias, 1f);
            if (type == HitFx.Water) Emit(Kind.Water, pos, main, 18, 5f, 0.08f, 0.6f, new Vector3(dir, 1, 0), 0.8f);
            if (type == HitFx.Gold) Emit(Kind.Ember, pos, main, 12, 2.5f, 0.12f, 0.8f, Vector3.up, 1f);
            if (type == HitFx.Earth) Emit(Kind.Dust, pos, new Color(0.6f, 0.45f, 0.3f, 0.7f), 5, 1.5f, 0.6f, 0.7f, Vector3.up, 1f);
        }

        public static void Dust(Vector3 pos, float amount)
        {
            int n = Mathf.RoundToInt(6 * amount);
            Emit(Kind.Dust, pos + Vector3.up * 0.05f, new Color(0.72f, 0.58f, 0.42f, 0.55f), n, 1.6f * amount, 0.55f * Mathf.Sqrt(amount), 0.8f, new Vector3(0, 0.25f, 0), 1f);
        }

        public static void Burst(Vector3 pos, Color c, float power)
        {
            Emit(Kind.Flash, pos, Color.white, 1, 0, 3f * power, 0.25f, default, 0);
            Emit(Kind.Ring, pos, c, 2, 0, 3.5f * power, 0.45f, default, 0);
            Emit(Kind.Spark, pos, c, Mathf.RoundToInt(40 * power), 14f, 0.09f, 0.45f, Vector3.zero, 1f);
            Emit(Kind.Ember, pos, c, Mathf.RoundToInt(30 * power), 4f, 0.15f, 1.2f, Vector3.up * 0.3f, 1f);
        }

        /// <summary>Raqib "yo'q bo'lishi" (yakuniy zarba): oltin/yulduz changga aylanish.</summary>
        public static void Disintegrate(Rig rig, Color c, Kind kind = Kind.Ember)
        {
            foreach (var b in rig.bones)
            {
                Emit(kind, b.position, c, 10, 2.5f, kind == Kind.Star ? 0.3f : 0.14f, 1.6f, Vector3.up * 0.6f, 1f);
                Emit(Kind.Glow, b.position, c.WithA(0.6f), 1, 0.3f, 0.6f, 0.6f, Vector3.up, 0.5f);
            }
        }
    }

    /// <summary>
    /// Qurol izi: tig' asosi va uchi orasida lenta (ribbon) mesh — professional "swoosh" effekti.
    /// </summary>
    public class SwordTrail : MonoBehaviour
    {
        public Transform baseT, tipT;
        public float lifetime = 0.14f;
        public bool emitting;
        public Color color = new Color(1f, 0.85f, 0.6f, 1f);

        struct Sample { public Vector3 a, b; public float t; }
        readonly List<Sample> samples = new List<Sample>();
        Mesh mesh;
        MeshRenderer mr;
        Material mat;
        readonly List<Vector3> v = new List<Vector3>();
        readonly List<Vector2> uv = new List<Vector2>();
        readonly List<Color> cols = new List<Color>();
        readonly List<int> tris = new List<int>();

        public static SwordTrail Create(Transform baseT, Transform tipT, Color c)
        {
            var go = new GameObject("Trail");
            var tr = go.AddComponent<SwordTrail>();
            tr.baseT = baseT; tr.tipT = tipT; tr.color = c;
            tr.mesh = new Mesh { name = "trail" };
            tr.mesh.MarkDynamic();
            go.AddComponent<MeshFilter>().sharedMesh = tr.mesh;
            tr.mr = go.AddComponent<MeshRenderer>();
            tr.mat = new Material(Mat.AddShader);
            tr.mat.SetTexture("_MainTex", TextureFactory.TrailGradient());
            if (tr.mat.HasProperty("_TintColor")) tr.mat.SetColor("_TintColor", Color.white);
            tr.mr.sharedMaterial = tr.mat;
            tr.mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            tr.mr.receiveShadows = false;
            return tr;
        }

        void LateUpdate()
        {
            float now = Time.time;
            if (emitting && baseT && tipT)
            {
                var s = new Sample { a = baseT.position, b = tipT.position, t = now };
                // oraliq interpolyatsiya — silliqroq yoy
                if (samples.Count > 0)
                {
                    var last = samples[samples.Count - 1];
                    for (int k = 1; k <= 2; k++)
                    {
                        float f = k / 3f;
                        samples.Add(new Sample { a = Vector3.Lerp(last.a, s.a, f), b = Vector3.Lerp(last.b, s.b, f), t = Mathf.Lerp(last.t, now, f) });
                    }
                }
                samples.Add(s);
            }
            samples.RemoveAll(x => now - x.t > lifetime);
            Rebuild(now);
        }

        void Rebuild(float now)
        {
            v.Clear(); uv.Clear(); cols.Clear(); tris.Clear();
            int n = samples.Count;
            if (n >= 2)
            {
                for (int i = 0; i < n; i++)
                {
                    var s = samples[n - 1 - i];
                    float age = Mathf.Clamp01((now - s.t) / lifetime);
                    v.Add(s.a); v.Add(s.b);
                    uv.Add(new Vector2(age, 0)); uv.Add(new Vector2(age, 1));
                    cols.Add(color); cols.Add(color);
                }
                for (int i = 0; i < n - 1; i++)
                {
                    int a = i * 2;
                    tris.Add(a); tris.Add(a + 1); tris.Add(a + 3);
                    tris.Add(a); tris.Add(a + 3); tris.Add(a + 2);
                }
            }
            mesh.Clear();
            mesh.SetVertices(v);
            mesh.SetUVs(0, uv);
            mesh.SetColors(cols);
            mesh.SetTriangles(tris, 0);
            mesh.RecalculateBounds();
        }

        public void Clear() { samples.Clear(); }
    }

    /// <summary>Jangchining vizual effektlari: qurol izlari, zarbada oq chaqnash, aura.</summary>
    public class FighterVisualFx : MonoBehaviour
    {
        Fighter f;
        readonly Dictionary<int, SwordTrail> trails = new Dictionary<int, SwordTrail>();
        Renderer[] renderers;
        MaterialPropertyBlock mpb;
        public Color auraColor;
        public float aura;
        static readonly int EmissionId = Shader.PropertyToID("_EmissionColor");

        public void Init(Fighter fighter)
        {
            f = fighter;
            var rig = f.rig;
            Color tc = f.def.energyColor;
            if (rig.weaponBaseR && rig.weaponTipR) trails[Trail.WeaponR] = SwordTrail.Create(rig.weaponBaseR, rig.weaponTipR, tc);
            if (rig.weaponBaseL && rig.weaponTipL) trails[Trail.WeaponL] = SwordTrail.Create(rig.weaponBaseL, rig.weaponTipL, tc);
            trails[Trail.FootL] = SwordTrail.Create(rig[Bone.ShinL], MakeTip(rig[Bone.FootL], new Vector3(0, -0.05f, 0.1f)), new Color(1, 1, 1, 0.7f));
            trails[Trail.FootR] = SwordTrail.Create(rig[Bone.ShinR], MakeTip(rig[Bone.FootR], new Vector3(0, -0.05f, 0.1f)), new Color(1, 1, 1, 0.7f));
            trails[Trail.HandR] = SwordTrail.Create(rig[Bone.ForeArmR], MakeTip(rig[Bone.HandR], new Vector3(0, -0.08f, 0)), new Color(1, 1, 1, 0.6f));
            trails[Trail.HandL] = SwordTrail.Create(rig[Bone.ForeArmL], MakeTip(rig[Bone.HandL], new Vector3(0, -0.08f, 0)), new Color(1, 1, 1, 0.6f));
            foreach (var t in trails.Values) t.transform.SetParent(transform.parent, false);
            var all = rig.GetComponentsInChildren<Renderer>(true);
            var list = new List<Renderer>();
            foreach (var r in all) if (!r.name.StartsWith("glow_") && !(r is ParticleSystemRenderer)) list.Add(r);
            renderers = list.ToArray();
            mpb = new MaterialPropertyBlock();
        }

        static Transform MakeTip(Transform parent, Vector3 p)
        {
            var t = new GameObject("TrailTip").transform;
            t.SetParent(parent, false);
            t.localPosition = p;
            return t;
        }

        public void StartTrails(MoveData m)
        {
            foreach (var kv in trails)
            {
                bool on = (m.trails & kv.Key) != 0;
                kv.Value.emitting = on;
                if (on && (kv.Key == Trail.WeaponR || kv.Key == Trail.WeaponL)) kv.Value.color = m.trailColor;
            }
        }

        public void StopTrails()
        {
            foreach (var t in trails.Values) if (t) t.emitting = false;
        }

        float lastFlash = -1;
        public void Tick()
        {
            float flash = Mathf.Clamp01(f.flashTimer / 0.12f);
            float a = aura > 0 ? aura * (0.6f + 0.4f * Mathf.Sin(Time.time * 12f)) : 0;
            float total = flash + a;
            if (Mathf.Abs(total - lastFlash) < 0.01f) return;
            lastFlash = total;
            Color c = f.flashColor * flash * 0.9f + auraColor * a * 0.6f;
            foreach (var r in renderers)
            {
                if (r == null || r is ParticleSystemRenderer) continue;
                r.GetPropertyBlock(mpb);
                mpb.SetColor(EmissionId, c);
                r.SetPropertyBlock(mpb);
            }
        }

        public void Dust(float amount, float? x = null)
        {
            VFX.Dust(new Vector3(x ?? f.pos.x, 0.02f, 0), amount);
        }

        public void Spark(Vector3 p, HitFx type, bool blocked, float power)
        {
            VFX.HitSpark(p, type, blocked, power, f.facing);
        }

        void OnDestroy()
        {
            foreach (var t in trails.Values) if (t) Destroy(t.gameObject);
        }
    }
}
