using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Shatranj.Chess;

namespace Shatranj.Visual
{
    /// <summary>
    /// Эффекты боя: искры от сабли, щепки, пыль, разлёт деревянной фигуры на части (физика),
    /// вспышка удара, замедление времени, салют победы, сияние «Пахлавона».
    /// </summary>
    public class Fx : MonoBehaviour
    {
        static Fx inst;
        public static Material HeroRingMaterial;

        ParticleSystem sparks, dust, fireworks, gold;
        ParticleSystem chipsWhite, chipsBlack;
        Transform debrisRoot;
        Light flash;
        float flashTime;
        Coroutine slowCo;
        readonly List<Transform> debris = new List<Transform>();

        public static System.Action OnFireworkPop;

        public static void Init(Transform parent)
        {
            if (inst != null) return;
            var go = new GameObject("Fx");
            go.transform.SetParent(parent, false);
            inst = go.AddComponent<Fx>();
            inst.Build();
        }

        void Build()
        {
            debrisRoot = new GameObject("Debris").transform;
            debrisRoot.SetParent(transform, false);

            var glowMat = MaterialLib.Unlit(Color.white, TextureFactory.Glow());
            HeroRingMaterial = MaterialLib.Unlit(new Color(1f, 0.82f, 0.35f, 0.9f), TextureFactory.Ring(128, 0.12f));

            sparks = MakeSystem("Sparks", glowMat, ParticleSystemRenderMode.Stretch, null);
            {
                var m = sparks.main;
                m.startLifetime = new ParticleSystem.MinMaxCurve(0.18f, 0.45f);
                m.startSpeed = new ParticleSystem.MinMaxCurve(2.5f, 6.5f);
                m.startSize = new ParticleSystem.MinMaxCurve(0.03f, 0.07f);
                m.startColor = new ParticleSystem.MinMaxGradient(new Color(1f, 0.95f, 0.7f), new Color(1f, 0.6f, 0.2f));
                m.gravityModifier = 0.8f;
                var r = sparks.GetComponent<ParticleSystemRenderer>();
                r.lengthScale = 2.5f;
                r.velocityScale = 0.04f;
                FadeOut(sparks);
            }

            dust = MakeSystem("Dust", MaterialLib.Unlit(Color.white, TextureFactory.Glow()), ParticleSystemRenderMode.Billboard, null);
            {
                var m = dust.main;
                m.startLifetime = new ParticleSystem.MinMaxCurve(0.6f, 1.1f);
                m.startSpeed = new ParticleSystem.MinMaxCurve(0.3f, 1.2f);
                m.startSize = new ParticleSystem.MinMaxCurve(0.25f, 0.55f);
                m.startColor = new ParticleSystem.MinMaxGradient(new Color(0.85f, 0.75f, 0.6f, 0.45f), new Color(0.7f, 0.6f, 0.45f, 0.3f));
                m.gravityModifier = -0.05f;
                var sol = dust.sizeOverLifetime;
                sol.enabled = true;
                sol.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 0.6f, 1, 1.4f));
                FadeOut(dust);
            }

            chipsWhite = MakeChips("ChipsWhite", MaterialLib.White.Wood);
            chipsBlack = MakeChips("ChipsBlack", MaterialLib.Black.Wood);

            gold = MakeSystem("Gold", glowMat, ParticleSystemRenderMode.Billboard, null);
            {
                var m = gold.main;
                m.startLifetime = new ParticleSystem.MinMaxCurve(0.8f, 1.6f);
                m.startSpeed = new ParticleSystem.MinMaxCurve(0.5f, 2.5f);
                m.startSize = new ParticleSystem.MinMaxCurve(0.05f, 0.12f);
                m.startColor = new ParticleSystem.MinMaxGradient(new Color(1f, 0.85f, 0.4f), new Color(1f, 0.95f, 0.75f));
                m.gravityModifier = -0.15f;
                FadeOut(gold);
            }

            fireworks = MakeSystem("Fireworks", glowMat, ParticleSystemRenderMode.Billboard, null);
            {
                var m = fireworks.main;
                m.startLifetime = new ParticleSystem.MinMaxCurve(1.0f, 1.8f);
                m.startSpeed = new ParticleSystem.MinMaxCurve(2.5f, 5.5f);
                m.startSize = new ParticleSystem.MinMaxCurve(0.08f, 0.16f);
                m.gravityModifier = 0.35f;
                m.maxParticles = 3000;
                var sh = fireworks.shape;
                sh.radius = 0.05f;
                FadeOut(fireworks);
            }

            var lgo = new GameObject("ImpactFlash");
            lgo.transform.SetParent(transform, false);
            flash = lgo.AddComponent<Light>();
            flash.type = LightType.Point;
            flash.range = 3.5f;
            flash.intensity = 0f;
            flash.color = new Color(1f, 0.85f, 0.6f);
            flash.shadows = LightShadows.None;
            flash.enabled = false;
        }

        static ParticleSystem MakeSystem(string name, Material mat, ParticleSystemRenderMode mode, Mesh mesh)
        {
            var go = new GameObject(name);
            go.transform.SetParent(inst.transform, false);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main;
            main.loop = true;
            main.playOnAwake = false;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.maxParticles = 1500;
            main.scalingMode = ParticleSystemScalingMode.Hierarchy;
            var em = ps.emission;
            em.rateOverTime = 0f;
            var shape = ps.shape;
            shape.enabled = true;
            shape.shapeType = ParticleSystemShapeType.Sphere;
            shape.radius = 0.12f;
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.renderMode = mode;
            r.sharedMaterial = mat;
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            if (mesh != null) r.mesh = mesh;
            ps.Play();
            return ps;
        }

        static ParticleSystem MakeChips(string name, Material wood)
        {
            var ps = MakeSystem(name, wood, ParticleSystemRenderMode.Mesh, MeshBuilder.Cube);
            var m = ps.main;
            m.startLifetime = new ParticleSystem.MinMaxCurve(1.2f, 2.0f);
            m.startSpeed = new ParticleSystem.MinMaxCurve(1.5f, 4.5f);
            m.startSize3D = true;
            m.startSizeX = new ParticleSystem.MinMaxCurve(0.02f, 0.06f);
            m.startSizeY = new ParticleSystem.MinMaxCurve(0.01f, 0.025f);
            m.startSizeZ = new ParticleSystem.MinMaxCurve(0.03f, 0.1f);
            m.startRotation3D = true;
            m.startRotationX = new ParticleSystem.MinMaxCurve(0f, Mathf.PI * 2f);
            m.startRotationY = new ParticleSystem.MinMaxCurve(0f, Mathf.PI * 2f);
            m.startRotationZ = new ParticleSystem.MinMaxCurve(0f, Mathf.PI * 2f);
            m.gravityModifier = 1.4f;
            var rol = ps.rotationOverLifetime;
            rol.enabled = true;
            rol.separateAxes = true;
            rol.x = new ParticleSystem.MinMaxCurve(-8f, 8f);
            rol.y = new ParticleSystem.MinMaxCurve(-8f, 8f);
            rol.z = new ParticleSystem.MinMaxCurve(-8f, 8f);
            var col = ps.collision;
            col.enabled = true;
            col.type = ParticleSystemCollisionType.World;
            col.mode = ParticleSystemCollisionMode.Collision3D;
            col.bounce = new ParticleSystem.MinMaxCurve(0.25f);
            col.dampen = new ParticleSystem.MinMaxCurve(0.45f);
            col.quality = ParticleSystemCollisionQuality.Low;
            var sol = ps.sizeOverLifetime;
            sol.enabled = true;
            sol.size = new ParticleSystem.MinMaxCurve(1f, new AnimationCurve(new Keyframe(0, 1), new Keyframe(0.75f, 1), new Keyframe(1, 0)));
            return ps;
        }

        static void FadeOut(ParticleSystem ps)
        {
            var col = ps.colorOverLifetime;
            col.enabled = true;
            var g = new Gradient();
            g.SetKeys(new[] { new GradientColorKey(Color.white, 0), new GradientColorKey(Color.white, 1) },
                      new[] { new GradientAlphaKey(1f, 0), new GradientAlphaKey(0.8f, 0.6f), new GradientAlphaKey(0f, 1) });
            col.color = new ParticleSystem.MinMaxGradient(g);
        }

        static void Emit(ParticleSystem ps, Vector3 pos, int count, Color? color = null)
        {
            if (ps == null) return;
            var ep = new ParticleSystem.EmitParams { position = pos, applyShapeToPosition = true };
            if (color.HasValue) ep.startColor = color.Value;
            ps.Emit(ep, count);
        }

        // ------------------------------------------------------------------ Публичный API

        public static void SwordClash(Vector3 pos)
        {
            if (inst == null) return;
            Emit(inst.sparks, pos, 36);
            inst.Flash(pos, new Color(1f, 0.85f, 0.55f), 5f);
        }

        public static void WoodBurst(Vector3 pos, Side woodSide, int count = 40)
        {
            if (inst == null) return;
            Emit(woodSide == Side.White ? inst.chipsWhite : inst.chipsBlack, pos, count);
            Emit(inst.dust, pos + Vector3.down * 0.2f, 10);
        }

        public static void Dust(Vector3 pos, int count = 6)
        {
            if (inst == null) return;
            Emit(inst.dust, pos, count);
        }

        public static void GoldBurst(Vector3 pos, int count = 60)
        {
            if (inst == null) return;
            Emit(inst.gold, pos, count);
            inst.Flash(pos + Vector3.up * 0.5f, new Color(1f, 0.85f, 0.4f), 4f);
        }

        void Flash(Vector3 pos, Color c, float intensity)
        {
            flash.transform.position = pos + Vector3.up * 0.3f;
            flash.color = c;
            flash.intensity = intensity;
            flash.enabled = true;
            flashTime = 0.28f;
        }

        void Update()
        {
            if (flash != null && flash.enabled)
            {
                flashTime -= Time.deltaTime;
                flash.intensity = Mathf.Max(0f, flash.intensity - Time.deltaTime * 20f);
                if (flashTime <= 0f) flash.enabled = false;
            }
        }

        /// <summary>Разрубленная фигура разлетается на резные детали, которые падают и исчезают.</summary>
        public static void Shatter(PieceView v, Vector3 hitPoint, Vector3 dir, float power = 1f)
        {
            if (v == null) return;
            ShatterObject(v.gameObject, hitPoint, dir, power);
        }

        public static void ShatterObject(GameObject v, Vector3 hitPoint, Vector3 dir, float power = 1f)
        {
            if (inst == null || v == null) return;
            var col = v.GetComponent<Collider>();
            if (col != null) col.enabled = false;
            dir.y = 0;
            dir = dir.sqrMagnitude > 1e-4f ? dir.normalized : Vector3.forward;

            var parts = new List<Transform>();
            foreach (var r in v.GetComponentsInChildren<MeshRenderer>())
            {
                if (r.GetComponent<MeshFilter>() == null || r.name == "HeroAura" || r.name == "Contact") continue;
                var t = r.transform;
                t.SetParent(inst.debrisRoot, true);
                var go = t.gameObject;
                if (go.layer != IconRenderer.Layer) go.layer = 2; // Ignore Raycast
                go.AddComponent<BoxCollider>();
                var rb = go.AddComponent<Rigidbody>();
                rb.mass = 0.12f;
                rb.drag = 0.35f;
                rb.angularDrag = 0.4f;
                rb.interpolation = RigidbodyInterpolation.Interpolate;
                Vector3 away = t.position - hitPoint;
                away.y = Mathf.Abs(away.y) + 0.2f;
                rb.AddForce((dir * Random.Range(1.5f, 3.2f) + away.normalized * Random.Range(1f, 2.6f) + Vector3.up * Random.Range(1.8f, 3.8f)) * power, ForceMode.VelocityChange);
                rb.AddTorque(Random.insideUnitSphere * 14f, ForceMode.VelocityChange);
                parts.Add(t);
            }
            Destroy(v.gameObject);
            inst.debris.AddRange(parts);
            inst.StartCoroutine(inst.FadeParts(parts, 2.4f));
            // ограничиваем количество обломков на сцене
            while (inst.debris.Count > 240)
            {
                var old = inst.debris[0];
                inst.debris.RemoveAt(0);
                if (old != null) Destroy(old.gameObject);
            }
        }

        IEnumerator FadeParts(List<Transform> parts, float delay)
        {
            for (float t = 0; t < delay; t += Time.deltaTime) yield return null;
            var scales = new Vector3[parts.Count];
            for (int i = 0; i < parts.Count; i++) if (parts[i] != null) scales[i] = parts[i].localScale;
            for (float t = 0; t < 1f; t += Time.deltaTime / 0.6f)
            {
                for (int i = 0; i < parts.Count; i++)
                    if (parts[i] != null) parts[i].localScale = scales[i] * (1f - Ease.In(t));
                yield return null;
            }
            foreach (var p in parts)
            {
                if (p == null) continue;
                debris.Remove(p);
                Destroy(p.gameObject);
            }
        }

        public static void ClearDebris()
        {
            if (inst == null) return;
            foreach (var d in inst.debris) if (d != null) Destroy(d.gameObject);
            inst.debris.Clear();
        }

        public static void Fireworks(Vector3 center, int bursts)
        {
            if (inst == null) return;
            inst.StartCoroutine(inst.FireworksRoutine(center, bursts));
        }

        IEnumerator FireworksRoutine(Vector3 center, int bursts)
        {
            Color[] palette =
            {
                new Color(1f, 0.82f, 0.3f), new Color(0.2f, 0.8f, 0.85f), new Color(0.95f, 0.25f, 0.3f),
                new Color(0.3f, 0.5f, 1f), new Color(1f, 1f, 0.9f), new Color(0.3f, 0.9f, 0.45f)
            };
            for (int i = 0; i < bursts; i++)
            {
                Vector3 p = center + new Vector3(Random.Range(-4f, 4f), Random.Range(3.5f, 6.5f), Random.Range(-3f, 4f));
                Color c = palette[Random.Range(0, palette.Length)];
                Emit(fireworks, p, 110, c);
                Emit(fireworks, p, 30, Color.white);
                Flash(p, c, 3f);
                if (OnFireworkPop != null) OnFireworkPop();
                float wait = Random.Range(0.25f, 0.6f);
                for (float t = 0; t < wait; t += Time.unscaledDeltaTime) yield return null;
            }
        }

        public static ParticleSystem CreateHeroSparks(Transform parent, float height)
        {
            var go = new GameObject("HeroSparks");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = new Vector3(0, 0.05f, 0);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var m = ps.main;
            m.loop = true;
            m.startLifetime = new ParticleSystem.MinMaxCurve(0.8f, 1.4f);
            m.startSpeed = new ParticleSystem.MinMaxCurve(0.15f, 0.45f);
            m.startSize = new ParticleSystem.MinMaxCurve(0.03f, 0.07f);
            m.startColor = new ParticleSystem.MinMaxGradient(new Color(1f, 0.85f, 0.35f), new Color(1f, 0.95f, 0.7f));
            m.gravityModifier = -0.2f;
            m.simulationSpace = ParticleSystemSimulationSpace.World;
            var em = ps.emission;
            em.rateOverTime = 10f;
            var sh = ps.shape;
            sh.shapeType = ParticleSystemShapeType.Circle;
            sh.radius = 0.32f;
            sh.rotation = new Vector3(-90, 0, 0);
            FadeOut(ps);
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.sharedMaterial = MaterialLib.Unlit(Color.white, TextureFactory.Glow());
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            go.layer = parent.gameObject.layer;
            ps.Play();
            return ps;
        }

        /// <summary>Кинематографичное замедление времени.</summary>
        public static void SlowMo(float scale, float realSeconds)
        {
            if (inst == null) return;
            if (inst.slowCo != null) inst.StopCoroutine(inst.slowCo);
            inst.slowCo = inst.StartCoroutine(inst.SlowMoRoutine(scale, realSeconds));
        }

        IEnumerator SlowMoRoutine(float scale, float realSeconds)
        {
            Time.timeScale = scale;
            Time.fixedDeltaTime = 0.02f * scale;
            for (float t = 0; t < realSeconds; t += Time.unscaledDeltaTime) yield return null;
            for (float t = 0; t < 1f; t += Time.unscaledDeltaTime / 0.2f)
            {
                Time.timeScale = Mathf.Lerp(scale, 1f, t);
                Time.fixedDeltaTime = 0.02f * Time.timeScale;
                yield return null;
            }
            Time.timeScale = 1f;
            Time.fixedDeltaTime = 0.02f;
        }

        public static void ResetTime()
        {
            if (inst != null && inst.slowCo != null) { inst.StopCoroutine(inst.slowCo); inst.slowCo = null; }
            Time.timeScale = 1f;
            Time.fixedDeltaTime = 0.02f;
        }
    }
}
