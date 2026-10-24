using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>Pooled particle bursts built entirely in code: hit sparks, dust, splashes, stars, confetti.</summary>
    public sealed class Fx : MonoBehaviour
    {
        static Fx instance;
        ParticleSystem sparks, dust, splash, stars, confetti;

        static readonly Color[] ConfettiColors =
        {
            new Color(1f, 0.3f, 0.3f), new Color(1f, 0.85f, 0.2f), new Color(0.3f, 0.8f, 1f),
            new Color(0.4f, 1f, 0.4f), new Color(1f, 0.5f, 0.9f), Color.white,
        };

        public static void Init(Transform parent)
        {
            if (instance != null) return;
            var go = new GameObject("Fx");
            go.transform.SetParent(parent, false);
            instance = go.AddComponent<Fx>();
            instance.sparks = instance.Make("Sparks", PrimitiveType.Sphere, 0.35f, 0f, 400);
            instance.dust = instance.Make("Dust", PrimitiveType.Sphere, 0.9f, -0.05f, 400);
            instance.splash = instance.Make("Splash", PrimitiveType.Sphere, 1.1f, 1f, 400);
            instance.stars = instance.Make("Stars", PrimitiveType.Cube, 0.8f, 0.2f, 200);
            instance.confetti = instance.Make("Confetti", PrimitiveType.Cube, 3.5f, 0.35f, 900);
        }

        ParticleSystem Make(string name, PrimitiveType mesh, float lifetime, float gravity, int max)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);

            var main = ps.main;
            main.playOnAwake = false;
            main.loop = false;
            main.duration = 1f;
            main.startLifetime = lifetime;
            main.gravityModifier = gravity;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.maxParticles = max;
            main.startRotation3D = false;

            var emission = ps.emission;
            emission.enabled = false;
            var shape = ps.shape;
            shape.enabled = false;

            var size = ps.sizeOverLifetime;
            size.enabled = true;
            size.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.EaseInOut(0f, 1f, 1f, 0f));

            var rot = ps.rotationOverLifetime;
            rot.enabled = mesh == PrimitiveType.Cube;
            rot.z = new ParticleSystem.MinMaxCurve(-6f, 6f);

            var renderer = go.GetComponent<ParticleSystemRenderer>();
            renderer.renderMode = ParticleSystemRenderMode.Mesh;
            renderer.mesh = MatFactory.Mesh(mesh);
            renderer.sharedMaterial = MatFactory.Unlit();
            renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            renderer.receiveShadows = false;
            return ps;
        }

        static void Emit(ParticleSystem ps, Vector3 pos, int count, float speedMin, float speedMax, float sizeMin, float sizeMax,
            Color color, Vector3 bias = default, float lifeJitter = 0.3f)
        {
            if (ps == null) return;
            var main = ps.main;
            float life = main.startLifetime.constant;
            var ep = new ParticleSystem.EmitParams();
            for (int i = 0; i < count; i++)
            {
                ep.position = pos;
                ep.velocity = Random.onUnitSphere * Random.Range(speedMin, speedMax) + bias;
                ep.startSize = Random.Range(sizeMin, sizeMax);
                ep.startColor = color;
                ep.startLifetime = life * Random.Range(1f - lifeJitter, 1f + lifeJitter);
                ep.rotation3D = Random.insideUnitSphere * 180f;
                ps.Emit(ep, 1);
            }
        }

        public static void Hit(Vector3 pos, float power)
        {
            if (instance == null) return;
            int n = Mathf.Clamp(Mathf.RoundToInt(power * 0.8f), 4, 26);
            Emit(instance.sparks, pos, n, 2f, 4f + power * 0.15f, 0.05f, 0.13f, new Color(1f, 0.95f, 0.6f));
            Emit(instance.sparks, pos, n / 2, 1f, 3f, 0.08f, 0.16f, Color.white);
        }

        public static void Dust(Vector3 pos, int count)
        {
            if (instance == null || count <= 0) return;
            Emit(instance.dust, pos, Mathf.Min(count, 20), 0.4f, 1.6f, 0.12f, 0.3f, new Color(0.85f, 0.8f, 0.72f, 0.8f), Vector3.up * 0.6f);
        }

        public static void Splash(Vector3 pos)
        {
            if (instance == null) return;
            Emit(instance.splash, pos, 40, 1.5f, 4.5f, 0.12f, 0.28f, new Color(0.65f, 0.85f, 1f), Vector3.up * 5f);
            Emit(instance.splash, pos, 20, 0.5f, 2f, 0.2f, 0.35f, Color.white, Vector3.up * 3f);
        }

        public static void Stars(Vector3 pos, int count)
        {
            if (instance == null) return;
            Emit(instance.stars, pos, count, 1.5f, 3.5f, 0.08f, 0.16f, new Color(1f, 0.9f, 0.25f), Vector3.up * 1.5f);
        }

        public static void Confetti(Vector3 pos, int count)
        {
            if (instance == null) return;
            for (int i = 0; i < ConfettiColors.Length; i++)
                Emit(instance.confetti, pos, Mathf.Max(1, count / ConfettiColors.Length), 2f, 6f, 0.07f, 0.14f, ConfettiColors[i], Vector3.up * 4f, 0.4f);
        }
    }
}
