using System;
using UnityEngine;

namespace UzbekKombat
{
    public enum ProjVisual { SwordWave, Dagger, StarOrb, FallingStar, Arrow, Lasso, Shockwave, WolfSpirit, WaterWave }

    /// <summary>Snaryad tavsifi.</summary>
    public class ProjectileSpec
    {
        public float damage = 60;
        public float chip = 0.15f;
        public HitLevel level = HitLevel.Mid;
        public int hitstun = 20, blockstun = 14;
        public Vector2 knockback = new Vector2(2.5f, 0);
        public bool launch, knockdown;
        public Vector2 size = new Vector2(0.6f, 0.6f);
        public float lifetime = 2.5f;
        public float gravity;
        public HitFx fx = HitFx.Magic;
        public Sfx hitSfx = Sfx.HitHeavy;
        public ProjVisual visual = ProjVisual.StarOrb;
        public Color color = Color.white;
        public bool reflectable = true;
        public int hitstop = 8;
        public float meterGain = 8;
        public int activationDelay;          // kadrlar (masalan, yulduz yomg'iri)
        public bool groundHugging;
        public Action<Fighter, Fighter> onHit;
        public bool destroyOnHit = true;
    }

    /// <summary>Dunyodagi snaryad: 2.5D tekislikda harakat, vizual model va zarralar.</summary>
    public class Projectile : MonoBehaviour
    {
        public ProjectileSpec spec;
        public Fighter owner;
        public Vector2 pos, vel, prevPos;
        public int age;
        public bool dead;
        public int dir => vel.x >= 0 ? 1 : -1;
        Transform visual;
        float spinRate;
        LineRenderer rope;

        public Rect Box => new Rect(pos.x - spec.size.x / 2, pos.y - spec.size.y / 2, spec.size.x, spec.size.y);
        public bool Active => age >= spec.activationDelay && !dead;

        public static Projectile Spawn(ProjectileSpec spec, Fighter owner, Vector2 pos, Vector2 vel)
        {
            var go = new GameObject("Projectile_" + spec.visual);
            var p = go.AddComponent<Projectile>();
            p.spec = spec;
            p.owner = owner;
            p.pos = p.prevPos = pos;
            p.vel = vel;
            p.BuildVisual();
            go.transform.position = new Vector3(pos.x, pos.y, 0);
            return p;
        }

        void BuildVisual()
        {
            visual = new GameObject("vis").transform;
            visual.SetParent(transform, false);
            var mb = new MeshBuilder();
            Color c = spec.color;
            Material m = Mat.Toon(Color.white, null, 0.6f, c * 1.6f);
            switch (spec.visual)
            {
                case ProjVisual.SwordWave:
                    {
                        // Yarim oy shaklidagi oltin to'lqin
                        var path = new System.Collections.Generic.List<Vector3>();
                        for (int i = 0; i <= 14; i++)
                        {
                            float a = Mathf.Lerp(-70, 70, i / 14f) * Mathf.Deg2Rad;
                            path.Add(new Vector3(Mathf.Cos(a) * 0.45f, Mathf.Sin(a) * 0.75f, 0));
                        }
                        mb.SetColor(c).Sweep(path, new[] { new Vector2(-0.05f, 0), new Vector2(0, 0.08f), new Vector2(0.05f, 0), new Vector2(0, -0.08f) },
                            t => Vector2.one * Mathf.Sin(t * Mathf.PI) * 1.4f, Vector3.forward);
                        m = Mat.Additive(TextureFactory.SoftDot(), Color.white);
                        mb.Build("wave", visual, Mat.Toon(Color.white, null, 0.5f, c * 2f), false);
                        break;
                    }
                case ProjVisual.Dagger:
                    mb.SetColor(Pal.Steel).Lathe(new[] { new Vector2(0, -0.2f), new Vector2(0.03f, -0.12f), new Vector2(0.025f, 0.15f), new Vector2(0, 0.22f) }, 4, Vector3.zero, 1.6f, 0.3f, true);
                    mb.SetColor(Pal.Gold).Box(new Vector3(0, -0.12f, 0), new Vector3(0.12f, 0.02f, 0.03f));
                    mb.SetColor(Pal.LeatherDark).Cylinder(Vector3.zero, 0.015f, 0.015f, -0.22f, -0.12f, 6);
                    visual.localRotation = Quaternion.Euler(0, 0, -90);
                    mb.Build("dagger", visual, Mat.ToonVC, false);
                    spinRate = 0;
                    break;
                case ProjVisual.StarOrb:
                    mb.SetColor(c).Sphere(Vector3.zero, 0.22f, 8, 12);
                    mb.Build("orb", visual, m, false);
                    {
                        var ring = new MeshBuilder();
                        ring.SetColor(Pal.Gold).Torus(Vector3.zero, 0.36f, 0.018f, 24, 4);
                        var r1 = ring.Build("ring1", visual, Mat.Toon(Color.white, null, 0.4f, Pal.Gold * 1.2f), false);
                        var r2 = ring.Build("ring2", visual, Mat.Toon(Color.white, null, 0.4f, Pal.Gold * 1.2f), false);
                        r1.transform.localRotation = Quaternion.Euler(70, 0, 20);
                        r2.transform.localRotation = Quaternion.Euler(-30, 60, 0);
                    }
                    spinRate = 240;
                    break;
                case ProjVisual.FallingStar:
                    mb.SetColor(c).Lathe(new[] { new Vector2(0, -0.25f), new Vector2(0.14f, 0f), new Vector2(0, 0.25f) }, 5, Vector3.zero, 1, 0.5f, true);
                    mb.Build("star", visual, m, false);
                    spinRate = 400;
                    break;
                case ProjVisual.Arrow:
                    mb.SetColor(Pal.Leather).Cylinder(Vector3.zero, 0.012f, 0.012f, -0.45f, 0.35f, 5);
                    mb.SetColor(Pal.Steel).Lathe(new[] { new Vector2(0.035f, 0.35f), new Vector2(0, 0.48f) }, 4);
                    mb.SetColor(Pal.White).Box(new Vector3(0, -0.4f, 0), new Vector3(0.005f, 0.12f, 0.06f));
                    mb.SetColor(Pal.Crimson).Box(new Vector3(0, -0.4f, 0), new Vector3(0.06f, 0.12f, 0.005f));
                    visual.localRotation = Quaternion.Euler(0, 0, -90);
                    mb.Build("arrow", visual, Mat.ToonVC, false);
                    break;
                case ProjVisual.Lasso:
                    mb.SetColor(ColorUtil.Hex("#c8a060")).Torus(Vector3.zero, 0.25f, 0.025f, 16, 4);
                    mb.Build("loop", visual, Mat.ToonVC, false);
                    visual.localRotation = Quaternion.Euler(0, 90, 0);
                    rope = gameObject.AddComponent<LineRenderer>();
                    rope.positionCount = 2;
                    rope.widthMultiplier = 0.035f;
                    rope.material = Mat.Unlit(ColorUtil.Hex("#c8a060"));
                    rope.useWorldSpace = true;
                    spinRate = 0;
                    break;
                case ProjVisual.Shockwave:
                    mb.SetColor(c).Lathe(new[] { new Vector2(0.0f, 0f), new Vector2(0.35f, 0.02f), new Vector2(0.2f, 0.35f), new Vector2(0, 0.6f) }, 7, Vector3.zero, 1.2f, 0.6f, true);
                    mb.Build("rock", visual, Mat.Toon(Color.white, null, 0.4f, c * 0.6f), false);
                    visual.localPosition = new Vector3(0, -0.3f, 0);
                    break;
                case ProjVisual.WolfSpirit:
                    {
                        // Ko'k bo'ri ruhi — soddalashtirilgan siluet
                        Color wc = new Color(0.4f, 0.75f, 1f);
                        mb.SetColor(wc).Sphere(new Vector3(0, 0.55f, 0), new Vector3(0.22f, 0.2f, 0.45f), 6, 10);
                        mb.SetColor(wc).Sphere(new Vector3(0, 0.75f, 0.45f), new Vector3(0.12f, 0.12f, 0.16f), 5, 8);
                        mb.SetColor(wc).Lathe(new[] { new Vector2(0.05f, 0), new Vector2(0, 0.12f) }, 4, new Vector3(0.06f, 0.86f, 0.42f));
                        mb.SetColor(wc).Lathe(new[] { new Vector2(0.05f, 0), new Vector2(0, 0.12f) }, 4, new Vector3(-0.06f, 0.86f, 0.42f));
                        mb.SetColor(wc).Cylinder(new Vector3(0, 0, 0.6f), 0.05f, 0.08f, 0.62f, 0.72f, 5);
                        foreach (var lx in new[] { -0.12f, 0.12f })
                            foreach (var lz in new[] { -0.3f, 0.3f })
                                mb.SetColor(wc).Cylinder(new Vector3(lx, 0, lz), 0.04f, 0.05f, 0f, 0.45f, 5);
                        mb.SetColor(wc).Capsule(new Vector3(0, 0.6f, -0.4f), new Vector3(0, 0.75f, -0.75f), 0.06f, 0.03f, 5);
                        mb.Build("wolf", visual, Mat.Additive(TextureFactory.SoftDot(), new Color(0.4f, 0.7f, 1f, 0.9f)), false);
                        visual.localRotation = Quaternion.Euler(0, 90, 0);
                        visual.localPosition = new Vector3(0, -0.6f, 0);
                        break;
                    }
                case ProjVisual.WaterWave:
                    mb.SetColor(new Color(0.3f, 0.7f, 0.95f)).Lathe(new[] { new Vector2(0.0f, 0f), new Vector2(0.6f, 0.05f), new Vector2(0.4f, 0.9f), new Vector2(0.1f, 1.4f), new Vector2(0, 1.5f) }, 9, Vector3.zero, 0.6f, 1.2f, false);
                    mb.Build("water", visual, Mat.Toon(new Color(0.4f, 0.8f, 1f), TextureFactory.Water(), 0.8f, new Color(0.1f, 0.3f, 0.5f)), false);
                    visual.localPosition = new Vector3(0, -0.75f, 0);
                    break;
            }
            if (spec.visual == ProjVisual.Lasso || spec.visual == ProjVisual.Dagger || spec.visual == ProjVisual.Arrow) return;
            var light = new GameObject("light").AddComponent<Light>();
            light.transform.SetParent(transform, false);
            light.type = LightType.Point;
            light.color = c;
            light.range = 4f;
            light.intensity = 2.2f;
        }

        public void Tick()
        {
            prevPos = pos;
            age++;
            if (age < spec.activationDelay)
            {
                if (age % 3 == 0) VFX.Emit(VFX.Kind.Star, new Vector3(pos.x, pos.y, 0), spec.color, 1, 0.5f, 0.3f, 0.4f, Vector3.up, 1f);
                visual.gameObject.SetActive(false);
                return;
            }
            visual.gameObject.SetActive(true);
            vel.y -= spec.gravity / 60f;
            pos += vel / 60f;
            if (age / 60f > spec.lifetime || Mathf.Abs(pos.x) > FightConst.StageHalfWidth + 3f || pos.y < -0.5f) Kill(false);
            if (spec.visual == ProjVisual.FallingStar && pos.y <= 0.1f)
            {
                VFX.Burst(new Vector3(pos.x, 0.1f, 0), spec.color, 0.6f);
                SynthAudio.Play(Sfx.Boom, 0.4f, 1.6f);
                Kill(false);
            }
            // Iz zarralari
            Vector3 p3 = new Vector3(pos.x, pos.y, 0);
            switch (spec.visual)
            {
                case ProjVisual.SwordWave: VFX.Emit(VFX.Kind.Ember, p3, spec.color, 2, 1f, 0.12f, 0.5f, new Vector3(-dir, 0.4f, 0), 0.7f); break;
                case ProjVisual.StarOrb: VFX.Emit(VFX.Kind.Star, p3, spec.color, 1, 0.8f, 0.22f, 0.6f, new Vector3(-dir, 0, 0), 1f); break;
                case ProjVisual.FallingStar: VFX.Emit(VFX.Kind.Ember, p3, spec.color, 2, 1f, 0.15f, 0.5f, Vector3.up, 0.4f); break;
                case ProjVisual.Shockwave: if (age % 2 == 0) VFX.Dust(new Vector3(pos.x, 0, 0), 0.6f); VFX.Emit(VFX.Kind.Ember, p3, spec.color, 1, 3f, 0.1f, 0.4f, Vector3.up, 0.5f); break;
                case ProjVisual.WolfSpirit: VFX.Emit(VFX.Kind.Glow, p3 + Vector3.up * 0.0f, new Color(0.4f, 0.7f, 1f, 0.5f), 1, 0.5f, 0.6f, 0.4f, new Vector3(-dir, 0.2f, 0), 0.5f); break;
                case ProjVisual.WaterWave: VFX.Emit(VFX.Kind.Water, p3, new Color(0.6f, 0.9f, 1f), 3, 4f, 0.08f, 0.6f, new Vector3(dir, 1.2f, 0), 0.6f); break;
                case ProjVisual.Arrow: if (age % 2 == 0) VFX.Emit(VFX.Kind.Spark, p3, new Color(1, 0.9f, 0.7f, 0.5f), 1, 0.5f, 0.04f, 0.15f, new Vector3(-dir, 0, 0), 0.1f); break;
            }
        }

        void Update()
        {
            float alpha = Time.fixedDeltaTime > 0 ? Mathf.Clamp01((Time.time - Time.fixedTime) / Time.fixedDeltaTime) : 1;
            Vector2 p = Vector2.Lerp(prevPos, pos, alpha);
            transform.position = new Vector3(p.x, p.y, 0);
            if (visual)
            {
                if (spinRate != 0) visual.Rotate(0, 0, spinRate * Time.deltaTime * -dir, Space.Self);
                if (spec.visual == ProjVisual.SwordWave || spec.visual == ProjVisual.Shockwave || spec.visual == ProjVisual.WaterWave)
                    visual.localScale = new Vector3(dir, 1, 1);
                if (spec.visual == ProjVisual.WolfSpirit) visual.localRotation = Quaternion.Euler(0, 90 * dir, 0);
                if (spec.visual == ProjVisual.Dagger || spec.visual == ProjVisual.Arrow) visual.localRotation = Quaternion.Euler(0, 0, -90 * dir);
                if (spec.visual == ProjVisual.FallingStar) visual.localScale = Vector3.one * (1f + 0.1f * Mathf.Sin(Time.time * 30));
            }
            if (rope && owner)
            {
                rope.SetPosition(0, owner.rig.Pos(Bone.HandR));
                rope.SetPosition(1, transform.position);
            }
        }

        public void Reflect(Fighter newOwner)
        {
            owner = newOwner;
            vel.x = -vel.x * 1.1f;
            age = Mathf.Min(age, 10);
            VFX.HitSpark(new Vector3(pos.x, pos.y, -0.3f), HitFx.Star, false, 0.8f, dir);
            SynthAudio.Play(Sfx.Clang, 0.8f, 1.4f);
        }

        public void Kill(bool impact)
        {
            if (dead) return;
            dead = true;
            if (impact) VFX.Burst(new Vector3(pos.x, pos.y, -0.2f), spec.color, 0.5f);
            Destroy(gameObject, 0.02f);
        }
    }
}
