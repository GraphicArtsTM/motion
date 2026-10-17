using System;
using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    /// <summary>Personaj rekvizitlari (masalan, kamon: qo'lda / orqada) — usullar davomida almashtiriladi.</summary>
    public class CharacterProps : MonoBehaviour
    {
        public readonly Dictionary<string, GameObject> items = new Dictionary<string, GameObject>();
        public void Show(string key, bool on) { if (items.TryGetValue(key, out var g) && g) g.SetActive(on); }
    }

    /// <summary>
    /// Har bir suyak uchun alohida MeshBuilder yig'adi va oxirida vertex-rangli toon mesh + kontur yaratadi.
    /// </summary>
    public class BodyKit
    {
        public readonly Rig rig;
        readonly Dictionary<Transform, MeshBuilder> solid = new Dictionary<Transform, MeshBuilder>();
        readonly Dictionary<Transform, (MeshBuilder mb, Color glow)> glow = new Dictionary<Transform, (MeshBuilder, Color)>();
        public float outline = 0.011f;

        public BodyKit(Rig r) { rig = r; }

        public MeshBuilder this[Bone b] => On(rig[b]);

        public MeshBuilder On(Transform t)
        {
            if (!solid.TryGetValue(t, out var mb)) solid[t] = mb = new MeshBuilder();
            mb.ResetTransform();
            return mb;
        }

        public MeshBuilder Glow(Transform t, Color c)
        {
            if (!glow.TryGetValue(t, out var g)) { g = (new MeshBuilder(), c); glow[t] = g; }
            g.mb.ResetTransform();
            return g.mb;
        }

        public void Finish()
        {
            var outlineMat = Mat.Outline(outline);
            foreach (var kv in solid)
            {
                if (kv.Value.IsEmpty) continue;
                kv.Value.ResetTransform();
                kv.Value.Build("mesh_" + kv.Key.name, kv.Key, Mat.ToonVC, true, outlineMat);
            }
            foreach (var kv in glow)
            {
                if (kv.Value.mb.IsEmpty) continue;
                kv.Value.mb.ResetTransform();
                kv.Value.mb.Build("glow_" + kv.Key.name, kv.Key, Mat.Toon(Color.white, null, 0.2f, kv.Value.glow * 1.4f), false);
            }
        }
    }

    public static class Pal
    {
        public static readonly Color Skin = ColorUtil.Hex("#c48a5a");
        public static readonly Color SkinLight = ColorUtil.Hex("#d39d70");
        public static readonly Color SkinDark = ColorUtil.Hex("#a8714a");
        public static readonly Color Hair = ColorUtil.Hex("#1e1612");
        public static readonly Color HairGrey = ColorUtil.Hex("#4a4440");
        public static readonly Color Steel = ColorUtil.Hex("#b9bec8");
        public static readonly Color SteelDark = ColorUtil.Hex("#6c7280");
        public static readonly Color Gold = ColorUtil.Hex("#d9a441");
        public static readonly Color GoldDark = ColorUtil.Hex("#a57a2a");
        public static readonly Color Leather = ColorUtil.Hex("#5a3a22");
        public static readonly Color LeatherDark = ColorUtil.Hex("#3a2416");
        public static readonly Color White = ColorUtil.Hex("#f1ead9");
        public static readonly Color Black = ColorUtil.Hex("#141012");
        public static readonly Color Crimson = ColorUtil.Hex("#9e1b24");
        public static readonly Color CrimsonDark = ColorUtil.Hex("#5e0f16");
        public static readonly Color Teal = ColorUtil.Hex("#1f7f86");
        public static readonly Color Indigo = ColorUtil.Hex("#25306e");
        public static readonly Color Purple = ColorUtil.Hex("#4b2a73");
        public static readonly Color Fur = ColorUtil.Hex("#4a3426");
        public static readonly Color Burgundy = ColorUtil.Hex("#6a1f2b");
        public static readonly Color Mongol = ColorUtil.Hex("#7a4a2a");
        public static readonly Color Emerald = ColorUtil.Hex("#1fbf7a");
    }

    public static class CharacterVisuals
    {
        static float Frac(float x) => x - Mathf.Floor(x);

        static Func<float, float, Color> Stripes(params Color[] cs) => (u, v) => cs[Mathf.FloorToInt(u * 24) % cs.Length];

        /// <summary>Adras/ikat uslubidagi to'lqinsimon yo'llar.</summary>
        static Func<float, float, Color> Ikat(Color[] cs, float waves = 3f) => (u, v) =>
        {
            float x = u * 18 + Mathf.Sin(v * Mathf.PI * waves) * 0.6f;
            return cs[Mathf.Abs(Mathf.FloorToInt(x)) % cs.Length];
        };

        static Func<float, float, Color> Trim(Func<float, float, Color> inner, Color trim, float frontWidth, float bottom = 0.08f) => (u, v) =>
        {
            float du = Mathf.Min(u, 1 - u);
            if (du < frontWidth || v < bottom) return trim;
            return inner(u, v);
        };

        // ===================== Umumiy tana =====================
        public struct Outfit
        {
            public Color skin, shirt, sleeve, trousers, boots, belt, beltBuckle, robe, robeTrim, chest;
            public Func<float, float, Color> robeFn, chestFn, sleeveFn;
            public bool robeLong, bracers, bootsTall, armorChest;
            public Color bracerColor;
            public float robeFlare;
        }

        static void BuildBody(BodyKit k, BodyShape s, Outfit o)
        {
            float bw = s.bulk;
            // Chanoq
            k[Bone.Hips].SetColor(o.trousers).Lathe(new[] { new Vector2(0, -0.13f), new Vector2(0.12f * bw, -0.12f), new Vector2(0.165f * bw, -0.05f), new Vector2(0.16f * bw, 0.06f), new Vector2(0.15f * bw, 0.13f) }, 12, Vector3.zero, 1.05f, 0.75f);
            // Chopon etagi (chanoqqa biriktirilgan)
            float flare = o.robeFlare <= 0 ? 1f : o.robeFlare;
            var robeFn = o.robeFn ?? ((u, v) => o.robe);
            k[Bone.Hips].Lathe(new[] { new Vector2(0.175f * bw, 0.14f), new Vector2(0.19f * bw, 0.02f), new Vector2(0.23f * bw * flare, -0.2f), new Vector2(0.25f * bw * flare, -0.3f) }, 18, Vector3.zero, 1.05f, 0.85f, true, (u, v) => robeFn(u, 1 - v));
            // Qorin
            k[Bone.Spine].SetColor(o.shirt).Lathe(new[] { new Vector2(0.15f * bw, -0.03f), new Vector2(0.153f * bw, 0.1f), new Vector2(0.16f * bw, 0.23f) }, 12, Vector3.zero, 1.05f, 0.76f, false, o.chestFn != null ? (u, v) => o.chestFn(u, v * 0.4f) : (Func<float, float, Color>)null);
            // Kamar (belbog')
            k[Bone.Spine].SetColor(o.belt).Lathe(new[] { new Vector2(0, -0.02f), new Vector2(0.165f * bw, -0.02f), new Vector2(0.168f * bw, 0.06f), new Vector2(0, 0.06f) }, 14, Vector3.zero, 1.05f, 0.78f, true);
            k[Bone.Spine].SetColor(o.beltBuckle).Box(new Vector3(0, 0.02f, 0.13f * bw), new Vector3(0.07f, 0.06f, 0.03f));
            // Ko'krak
            float sx = 1.12f * s.shoulders, sz = 0.74f;
            var chestFn = o.chestFn ?? ((u, v) => o.chest);
            k[Bone.Chest].Lathe(new[] { new Vector2(0.158f * bw, -0.03f), new Vector2(0.18f * bw, 0.06f), new Vector2(0.2f * bw, 0.15f), new Vector2(0.19f * bw, 0.22f), new Vector2(0.14f * bw, 0.275f), new Vector2(0.06f, 0.295f), new Vector2(0, 0.3f) }, 16, Vector3.zero, sx, sz * bw, false, chestFn);
            // Yelka bo'g'imlari
            k[Bone.Chest].SetColor(o.sleeve).Sphere(new Vector3(-0.19f * s.shoulders, 0.2f, 0), new Vector3(0.075f, 0.07f, 0.075f) * bw, 6, 10);
            k[Bone.Chest].SetColor(o.sleeve).Sphere(new Vector3(0.19f * s.shoulders, 0.2f, 0), new Vector3(0.075f, 0.07f, 0.075f) * bw, 6, 10);
            // Bo'yin
            k[Bone.Neck].SetColor(o.skin).Cylinder(Vector3.zero, 0.055f, 0.05f, -0.02f, 0.12f, 10);
            // Bosh
            BuildHead(k, o.skin);

            // Qo'llar
            foreach (var side in new[] { -1, 1 })
            {
                Bone ua = side < 0 ? Bone.UpperArmL : Bone.UpperArmR;
                Bone fa = side < 0 ? Bone.ForeArmL : Bone.ForeArmR;
                Bone hd = side < 0 ? Bone.HandL : Bone.HandR;
                float al = s.armLength;
                k[ua].SetColor(o.sleeve).Lathe(new[] { new Vector2(0, 0.03f), new Vector2(0.06f * bw, 0.02f), new Vector2(0.068f * bw, -0.08f), new Vector2(0.06f * bw, -0.29f * al), new Vector2(0, -0.31f * al) }, 10, Vector3.zero, 1, 1, false, o.sleeveFn);
                k[fa].SetColor(o.sleeve).Lathe(new[] { new Vector2(0, 0.02f), new Vector2(0.056f * bw, 0.01f), new Vector2(0.058f * bw, -0.1f), new Vector2(0.05f * bw, -0.24f * al), new Vector2(0, -0.25f * al) }, 10, Vector3.zero, 1, 1, false, o.sleeveFn);
                if (o.bracers)
                    k[fa].SetColor(o.bracerColor).Cylinder(Vector3.zero, 0.066f * bw, 0.058f * bw, -0.24f * al, -0.08f, 10, true);
                // Musht
                var h = k[hd].SetColor(o.skin);
                h.Box(new Vector3(0, -0.06f, 0.005f), new Vector3(0.075f, 0.1f, 0.09f));
                h.Box(new Vector3(0, -0.035f, 0.05f), new Vector3(0.05f, 0.04f, 0.035f)); // bosh barmoq
            }

            // Oyoqlar
            foreach (var side in new[] { -1, 1 })
            {
                Bone th = side < 0 ? Bone.ThighL : Bone.ThighR;
                Bone sh = side < 0 ? Bone.ShinL : Bone.ShinR;
                Bone ft = side < 0 ? Bone.FootL : Bone.FootR;
                float ll = s.legLength;
                k[th].SetColor(o.trousers).Lathe(new[] { new Vector2(0, 0.04f), new Vector2(0.095f * bw, 0.03f), new Vector2(0.1f * bw, -0.1f), new Vector2(0.075f * bw, -0.45f * ll), new Vector2(0, -0.47f * ll) }, 10);
                // Chopon bo'laklari — tizzagacha (yoki to'piqqacha)
                float robeLen = o.robeLong ? 0.52f : 0.42f;
                k[th].Lathe(new[] { new Vector2(0.115f * bw, 0.02f), new Vector2(0.13f * bw * flare, -0.2f), new Vector2(0.15f * bw * flare, -robeLen * ll) }, 12, Vector3.zero, 1, 1, true,
                    (u, v) => robeFn(u, 0.5f - v * 0.5f));
                k[sh].SetColor(o.trousers).Lathe(new[] { new Vector2(0, 0.03f), new Vector2(0.07f * bw, 0.02f), new Vector2(0.065f * bw, -0.15f), new Vector2(0.05f, -0.43f * ll), new Vector2(0, -0.44f * ll) }, 10);
                if (o.robeLong)
                    k[sh].Lathe(new[] { new Vector2(0.14f * bw, 0.05f), new Vector2(0.155f * bw, -0.15f), new Vector2(0.17f * bw, -0.33f * ll) }, 12, Vector3.zero, 1, 1, true, (u, v) => robeFn(u, v * 0.1f));
                // Etik
                float bootTop = o.bootsTall ? -0.08f : -0.25f;
                k[sh].SetColor(o.boots).Lathe(new[] { new Vector2(0, bootTop + 0.01f), new Vector2(0.074f, bootTop), new Vector2(0.068f, -0.3f), new Vector2(0.062f, -0.44f * ll), new Vector2(0, -0.45f * ll) }, 10, Vector3.zero, 1, 1, true);
                var f = k[ft].SetColor(o.boots);
                f.Box(new Vector3(0, -0.04f, 0.04f), new Vector3(0.09f, 0.075f, 0.22f));
                f.SetTransform(new Vector3(0, -0.045f, 0.15f), Quaternion.Euler(-70, 0, 0));
                f.Lathe(new[] { new Vector2(0.04f, 0), new Vector2(0.02f, 0.06f), new Vector2(0, 0.09f) }, 6); // yuqoriga qayrilgan uchi
                f.ResetTransform();
            }
        }

        static void BuildHead(BodyKit k, Color skin)
        {
            var h = k[Bone.Head].SetColor(skin);
            h.Sphere(new Vector3(0, 0.125f, 0.0f), new Vector3(0.096f, 0.12f, 0.105f), 8, 14);
            h.Sphere(new Vector3(0, 0.07f, 0.03f), new Vector3(0.078f, 0.06f, 0.078f), 6, 12); // jag'
            // Quloqlar
            h.Sphere(new Vector3(-0.095f, 0.12f, -0.005f), new Vector3(0.018f, 0.03f, 0.022f), 4, 6);
            h.Sphere(new Vector3(0.095f, 0.12f, -0.005f), new Vector3(0.018f, 0.03f, 0.022f), 4, 6);
            // Burun
            h.SetTransform(new Vector3(0, 0.12f, 0.1f), Quaternion.Euler(-12, 0, 0));
            h.Lathe(new[] { new Vector2(0.018f, -0.035f), new Vector2(0.012f, 0.0f), new Vector2(0.006f, 0.03f), new Vector2(0, 0.032f) }, 6, Vector3.zero, 1.1f, 1.2f);
            h.ResetTransform();
            // Ko'zlar
            foreach (var sx in new[] { -1f, 1f })
            {
                h.SetColor(Pal.White).Sphere(new Vector3(sx * 0.036f, 0.138f, 0.088f), new Vector3(0.017f, 0.011f, 0.01f), 4, 8);
                h.SetColor(Pal.Black).Sphere(new Vector3(sx * 0.036f, 0.138f, 0.096f), new Vector3(0.008f, 0.009f, 0.006f), 4, 6);
            }
            h.SetColor(skin.Mul(0.7f)).Box(new Vector3(0, 0.078f, 0.1f), new Vector3(0.035f, 0.006f, 0.01f));
        }

        static void Brows(BodyKit k, Color c, float angry = 14f, float thick = 1f)
        {
            var h = k[Bone.Head].SetColor(c);
            foreach (var sx in new[] { -1f, 1f })
            {
                h.SetTransform(new Vector3(sx * 0.04f, 0.162f, 0.098f), Quaternion.Euler(0, 0, sx * angry));
                h.Box(Vector3.zero, new Vector3(0.05f, 0.013f * thick, 0.02f));
            }
            h.ResetTransform();
        }

        static void Beard(BodyKit k, Color c, float size, float length, bool mustache = true, bool droopy = false)
        {
            var h = k[Bone.Head].SetColor(c);
            h.Sphere(new Vector3(0, 0.035f - length * 0.035f, 0.042f), new Vector3(0.08f * size, 0.045f + length * 0.045f, 0.068f * size), 6, 12);
            if (mustache)
            {
                foreach (var sx in new[] { -1f, 1f })
                {
                    Vector3 a = new Vector3(0, 0.092f, 0.108f);
                    Vector3 b = droopy ? new Vector3(sx * 0.05f, 0.02f, 0.1f) : new Vector3(sx * 0.052f, 0.075f, 0.094f);
                    h.Capsule(a, b, 0.012f, droopy ? 0.006f : 0.009f, 6);
                }
            }
        }

        static void Goatee(BodyKit k, Color c)
        {
            var h = k[Bone.Head].SetColor(c);
            h.Capsule(new Vector3(0, 0.05f, 0.09f), new Vector3(0, -0.04f, 0.085f), 0.02f, 0.006f, 6);
        }

        // ===================== Qurollar =====================
        /// <summary>Egri qilich (qilich/saber). Mount lokal +Z bo'ylab.</summary>
        static void Saber(BodyKit k, Transform mount, float len, Color blade, Color guard, Color grip, out Transform baseT, out Transform tipT)
        {
            // Dasta, gard, pommel — Y bo'ylab quriladi, keyin Z ga buriladi
            var tmp = new MeshBuilder();
            tmp.SetColor(grip).Cylinder(Vector3.zero, 0.018f, 0.02f, -0.1f, 0.08f, 8);
            tmp.SetColor(guard).Sphere(new Vector3(0, -0.11f, 0), 0.028f, 4, 8); // pommel
            tmp.SetColor(guard).Box(new Vector3(0, 0.09f, 0), new Vector3(0.16f, 0.025f, 0.04f)); // gard (krestovina)
            tmp.SetColor(guard).Sphere(new Vector3(0.08f, 0.09f, 0), 0.018f, 4, 6);
            tmp.SetColor(guard).Sphere(new Vector3(-0.08f, 0.09f, 0), 0.018f, 4, 6);
            var w = k.On(mount);
            w.matrix = Matrix4x4.Rotate(Quaternion.Euler(90, 0, 0));
            w.Append(tmp);
            w.ResetTransform();
            // Tig' — egri yo'l bo'ylab sweep
            var path = new List<Vector3>();
            int n = 12;
            for (int i = 0; i <= n; i++)
            {
                float t = i / (float)n;
                float z = 0.1f + t * len;
                float y = 0.11f * t * t * len;   // yuqoriga egilish
                path.Add(new Vector3(0, y, z));
            }
            var section = new[] { new Vector2(0, -0.022f), new Vector2(0.004f, 0f), new Vector2(0, 0.014f), new Vector2(-0.004f, 0f) };
            w = k.On(mount).SetColor(blade);
            w.Sweep(path, section, t => new Vector2(1f, t > 0.85f ? Mathf.Lerp(1f, 0.15f, (t - 0.85f) / 0.15f) : 1f + t * 0.25f), Vector3.right);
            baseT = new GameObject("WeaponBase").transform;
            baseT.SetParent(mount, false);
            baseT.localPosition = new Vector3(0, 0, 0.18f);
            tipT = new GameObject("WeaponTip").transform;
            tipT.SetParent(mount, false);
            tipT.localPosition = path[n];
        }

        static Transform MountRot(Transform mount, float pitch)
        {
            var t = new GameObject("Grip").transform;
            t.SetParent(mount, false);
            t.localRotation = Quaternion.Euler(pitch, 0, 0);
            return t;
        }

        static void Staff(BodyKit k, Transform mount, Color wood, Color metal, Color glowC, out Transform baseT, out Transform tipT)
        {
            var tmp = new MeshBuilder();
            tmp.SetColor(wood).Cylinder(Vector3.zero, 0.022f, 0.018f, -0.75f, 0.85f, 8);
            tmp.SetColor(metal).Cylinder(Vector3.zero, 0.03f, 0.03f, -0.78f, -0.7f, 8);
            tmp.SetColor(metal).Cylinder(Vector3.zero, 0.028f, 0.028f, 0.0f, 0.06f, 8);
            tmp.SetColor(metal).Cylinder(Vector3.zero, 0.028f, 0.028f, 0.8f, 0.86f, 8);
            // Usturlob (astrolabiya) halqalari
            tmp.SetColor(metal).Torus(new Vector3(0, 1.0f, 0), 0.13f, 0.012f, 20, 5);
            var ring2 = new MeshBuilder();
            ring2.SetColor(metal).Torus(Vector3.zero, 0.11f, 0.01f, 20, 5);
            tmp.matrix = Matrix4x4.TRS(new Vector3(0, 1.0f, 0), Quaternion.Euler(90, 0, 0), Vector3.one);
            tmp.Append(ring2);
            tmp.matrix = Matrix4x4.TRS(new Vector3(0, 1.0f, 0), Quaternion.Euler(90, 60, 0), Vector3.one);
            tmp.Append(ring2);
            tmp.ResetTransform();
            tmp.SetColor(metal).Cylinder(Vector3.zero, 0.012f, 0.012f, 0.85f, 0.88f, 6);
            var w = k.On(mount);
            w.matrix = Matrix4x4.Rotate(Quaternion.Euler(90, 0, 0));
            w.Append(tmp);
            w.ResetTransform();
            var g = k.Glow(mount, glowC);
            g.SetColor(glowC).Sphere(new Vector3(0, 0, 1.0f), 0.06f, 6, 10);
            g.SetColor(glowC.Mul(1.2f)).Sphere(new Vector3(0, 0, 1.13f), new Vector3(0.012f, 0.012f, 0.03f), 3, 6);
            baseT = new GameObject("WeaponBase").transform;
            baseT.SetParent(mount, false);
            baseT.localPosition = new Vector3(0, 0, 0.55f);
            tipT = new GameObject("WeaponTip").transform;
            tipT.SetParent(mount, false);
            tipT.localPosition = new Vector3(0, 0, 1.08f);
        }

        static GameObject Bow(Transform parent, Vector3 pos, Quaternion rot, Color wood, Color tips)
        {
            var go = new GameObject("Bow");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = rot;
            var mb = new MeshBuilder();
            var path = new List<Vector3>();
            for (int i = 0; i <= 16; i++)
            {
                float t = i / 16f * 2 - 1; // -1..1
                float y = t * 0.55f;
                float z = -0.12f * (1 - t * t) + 0.06f * Mathf.Pow(Mathf.Abs(t), 6) ; // refleks kamon
                path.Add(new Vector3(0, y, z));
            }
            var sec = new[] { new Vector2(-0.014f, -0.01f), new Vector2(0.014f, -0.01f), new Vector2(0.014f, 0.01f), new Vector2(-0.014f, 0.01f) };
            mb.SetColor(wood).Sweep(path, sec, t => Vector2.one * (1.2f - Mathf.Abs(t - 0.5f) * 1.2f), Vector3.right);
            mb.SetColor(tips).Box(new Vector3(0, 0, -0.12f), new Vector3(0.035f, 0.1f, 0.035f));
            mb.SetColor(Pal.White).Capsule(path[0], path[16], 0.003f, 0.003f, 4); // ip
            mb.Build("bow_mesh", go.transform, Mat.ToonVC, true, Mat.Outline(0.008f));
            return go;
        }

        static void Quiver(MeshBuilder mb, Color c)
        {
            mb.SetTransform(new Vector3(0.1f, 0.0f, -0.05f), Quaternion.Euler(0, 0, 25));
            mb.SetColor(c).Cylinder(Vector3.zero, 0.05f, 0.06f, -0.3f, 0.12f, 8);
            mb.SetColor(Pal.Gold).Cylinder(Vector3.zero, 0.062f, 0.062f, 0.08f, 0.12f, 8);
            for (int i = 0; i < 5; i++)
            {
                float a = i * 1.2f;
                Vector3 p = new Vector3(Mathf.Sin(a) * 0.025f, 0.12f, Mathf.Cos(a) * 0.025f);
                mb.SetColor(Pal.Leather).Capsule(p, p + Vector3.up * 0.14f, 0.005f, 0.005f, 4);
                mb.SetColor(Pal.White).Box(p + Vector3.up * 0.16f, new Vector3(0.006f, 0.05f, 0.025f));
            }
            mb.ResetTransform();
        }

        // ===================== Amir Temur =====================
        public static Rig BuildTemur(Transform parent)
        {
            var shape = new BodyShape { height = 1.03f, shoulders = 1.1f, bulk = 1.12f };
            var rig = Rig.Create(parent, shape, "Temur");
            var k = new BodyKit(rig);
            Color[] chaponC = { Pal.Crimson, Pal.Crimson, Pal.CrimsonDark, Pal.Gold, Pal.Crimson, Pal.CrimsonDark };
            var robe = Trim(Ikat(chaponC, 2f), Pal.Gold, 0.035f, 0.07f);
            // Plastinka-zirh (lamellar)
            Func<float, float, Color> armor = (u, v) =>
            {
                if (v > 0.86f) return Pal.Gold;
                int row = Mathf.FloorToInt(v * 9);
                bool edge = Frac(v * 9) < 0.18f;
                bool slit = Frac(u * 28 + (row % 2) * 0.5f) < 0.12f;
                if (row == 4 && !edge) return Pal.Gold;
                if (edge) return Pal.SteelDark;
                return slit ? Pal.SteelDark : Pal.Steel;
            };
            var o = new Outfit
            {
                skin = Pal.Skin, shirt = Pal.Steel, sleeve = Pal.Crimson, trousers = ColorUtil.Hex("#2b2230"),
                boots = Pal.LeatherDark, belt = Pal.Gold, beltBuckle = Pal.Emerald, robe = Pal.Crimson,
                robeFn = robe, chestFn = armor, sleeveFn = (u, v) => v < 0.12f ? Pal.Gold : Pal.Crimson,
                bracers = true, bracerColor = Pal.Steel, bootsTall = true, robeFlare = 1.08f
            };
            BuildBody(k, shape, o);
            Brows(k, Pal.Hair, 16f, 1.3f);
            Beard(k, ColorUtil.Hex("#2a1d16"), 1.0f, 0.9f);
            // Dubulg'a (sharqona o'tkir uchli)
            var h = k[Bone.Head];
            h.SetColor(Pal.Steel).Lathe(new[] { new Vector2(0.113f, 0.180f), new Vector2(0.12f, 0.225f), new Vector2(0.112f, 0.270f), new Vector2(0.085f, 0.320f), new Vector2(0.045f, 0.360f), new Vector2(0.014f, 0.415f), new Vector2(0, 0.455f) }, 16, Vector3.zero, 1, 1.05f, false,
                (u, v) => v < 0.18f ? Pal.Gold : (Frac(u * 8) < 0.08f ? Pal.Gold : Pal.Steel));
            h.SetColor(Pal.Gold).Torus(new Vector3(0, 0.185f, 0), 0.118f, 0.012f, 18, 5, 1.05f);
            // Burun himoyasi
            h.SetColor(Pal.Steel).Box(new Vector3(0, 0.15f, 0.122f), new Vector3(0.018f, 0.135f, 0.012f));
            // Halqali to'r (aventail) — orqa va yonlar
            h.Lathe(new[] { new Vector2(0.116f, 0.185f), new Vector2(0.13f, 0.105f), new Vector2(0.15f, 0.015f), new Vector2(0.17f, -0.035f) }, 14, Vector3.zero, 1, 1.05f, true,
                (u, v) => Frac(u * 30 + v * 4) < 0.5f ? Pal.SteelDark : Pal.Steel, 55f, 250f);
            // Pat (qizil)
            h.SetColor(Pal.Crimson).Lathe(new[] { new Vector2(0.02f, 0.445f), new Vector2(0.03f, 0.515f), new Vector2(0.012f, 0.605f), new Vector2(0, 0.645f) }, 8);
            // Yelka zirhlari
            foreach (var b in new[] { Bone.UpperArmL, Bone.UpperArmR })
            {
                var m = k[b];
                m.SetColor(Pal.Steel).Lathe(new[] { new Vector2(0, 0.07f), new Vector2(0.06f, 0.065f), new Vector2(0.095f, 0.02f), new Vector2(0.105f, -0.05f), new Vector2(0.1f, -0.1f) }, 12, Vector3.zero, 1, 1, true,
                    (u, v) => Frac(v * 3) < 0.25f ? Pal.Gold : Pal.Steel);
            }
            // Plashch (orqada)
            k[Bone.Chest].Lathe(new[] { new Vector2(0.17f, 0.27f), new Vector2(0.24f, 0.05f), new Vector2(0.3f, -0.35f), new Vector2(0.34f, -0.72f) }, 12, new Vector3(0, 0, -0.02f), 1.15f, 0.7f, true,
                (u, v) => v < 0.05f ? Pal.Gold : Pal.CrimsonDark, 120f, 120f);
            // Qilich
            var grip = MountRot(rig.mountR, 50f);
            Saber(k, grip, 0.82f, ColorUtil.Hex("#dfe3ea"), Pal.Gold, Pal.LeatherDark, out rig.weaponBaseR, out rig.weaponTipR);
            // Kamarda qin
            var hb = k[Bone.Hips];
            hb.SetTransform(new Vector3(-0.17f, 0.02f, -0.05f), Quaternion.Euler(55, 0, -10));
            hb.SetColor(Pal.LeatherDark).Cylinder(Vector3.zero, 0.025f, 0.02f, -0.75f, 0.0f, 6);
            hb.ResetTransform();
            k.Finish();
            rig.gameObject.AddComponent<CharacterProps>();
            return rig;
        }

        // ===================== Jaloliddin Manguberdi =====================
        public static Rig BuildJaloliddin(Transform parent)
        {
            var shape = new BodyShape { height = 1.0f, shoulders = 1.02f, bulk = 0.98f, legLength = 1.03f };
            var rig = Rig.Create(parent, shape, "Jaloliddin");
            var k = new BodyKit(rig);
            Color[] cs = { Pal.Teal, Pal.White, Pal.Teal, Pal.Indigo, Pal.Teal, Pal.Gold };
            var robe = Trim(Stripes(cs), Pal.Indigo, 0.03f, 0.06f);
            Func<float, float, Color> vest = (u, v) =>
            {
                float du = Mathf.Min(u, 1 - u);
                if (du < 0.05f) return Pal.Teal;          // old ochiq qism
                if (v > 0.85f) return Pal.LeatherDark;
                bool rivet = Frac(u * 20) < 0.15f && Frac(v * 8) < 0.2f;
                return rivet ? Pal.Gold : Pal.Leather;
            };
            var o = new Outfit
            {
                skin = Pal.Skin, shirt = Pal.Leather, sleeve = Pal.Teal, trousers = ColorUtil.Hex("#26303a"),
                boots = Pal.Leather, belt = Pal.Indigo, beltBuckle = Pal.Gold, robe = Pal.Teal, robeFn = robe,
                chestFn = vest, sleeveFn = (u, v) => Stripes(cs)(u, v), bracers = true, bracerColor = Pal.Leather, bootsTall = true, robeFlare = 0.95f
            };
            BuildBody(k, shape, o);
            Brows(k, Pal.Hair, 10f, 1.1f);
            Beard(k, Pal.Hair, 0.95f, 0.4f);
            var h = k[Bone.Head];
            // Dubulg'a + salla o'rami
            h.SetColor(Pal.Steel).Lathe(new[] { new Vector2(0.11f, 0.190f), new Vector2(0.112f, 0.240f), new Vector2(0.09f, 0.300f), new Vector2(0.05f, 0.340f), new Vector2(0.015f, 0.380f), new Vector2(0, 0.400f) }, 14);
            h.SetColor(Pal.White).Torus(new Vector3(0, 0.195f, 0), 0.118f, 0.03f, 18, 6, 1.05f);
            h.SetColor(Pal.White).Torus(new Vector3(0, 0.230f, -0.005f), 0.108f, 0.026f, 18, 6, 1.05f);
            h.SetColor(Pal.Teal).Sphere(new Vector3(0, 0.215f, 0.125f), new Vector3(0.03f, 0.070f, 0.015f), 4, 8);
            h.SetColor(Pal.Gold).Sphere(new Vector3(0, 0.215f, 0.135f), 0.012f, 4, 6);
            // Salla dumi (orqada osilgan)
            h.SetColor(Pal.White).Capsule(new Vector3(0, 0.210f, -0.11f), new Vector3(0.02f, -0.040f, -0.16f), 0.03f, 0.022f, 6);
            // Qo'sh qilich
            var gripR = MountRot(rig.mountR, 50f);
            Saber(k, gripR, 0.72f, ColorUtil.Hex("#e8ecf2"), Pal.Gold, Pal.Indigo, out rig.weaponBaseR, out rig.weaponTipR);
            var gripL = MountRot(rig.mountL, 50f);
            Saber(k, gripL, 0.72f, ColorUtil.Hex("#e8ecf2"), Pal.Gold, Pal.Indigo, out rig.weaponBaseL, out rig.weaponTipL);
            k.Finish();
            rig.gameObject.AddComponent<CharacterProps>();
            return rig;
        }

        // ===================== Mirzo Ulug'bek =====================
        public static Rig BuildUlugbek(Transform parent)
        {
            var shape = new BodyShape { height = 0.99f, shoulders = 0.97f, bulk = 1.0f };
            var rig = Rig.Create(parent, shape, "Ulugbek");
            var k = new BodyKit(rig);
            // Yulduzli to'n
            Func<float, float, Color> starRobe = (u, v) =>
            {
                float du = Mathf.Min(u, 1 - u);
                if (du < 0.035f || v < 0.05f) return Pal.Gold;
                bool star = Frac(u * 14 + Mathf.Floor(v * 9) * 0.5f) < 0.14f && Frac(v * 9) < 0.18f;
                return star ? ColorUtil.Hex("#f2d27a") : Pal.Indigo;
            };
            var o = new Outfit
            {
                skin = Pal.SkinLight, shirt = Pal.White, sleeve = Pal.Indigo, trousers = Pal.Indigo,
                boots = ColorUtil.Hex("#2a1e14"), belt = Pal.Gold, beltBuckle = ColorUtil.Hex("#3fa0e0"), robe = Pal.Indigo, robeFn = starRobe,
                chestFn = (u, v) => { float du = Mathf.Min(u, 1 - u); return du < 0.04f ? Pal.Gold : du < 0.09f ? Pal.White : starRobe(u, v); },
                sleeveFn = (u, v) => v < 0.1f ? Pal.Gold : Pal.Indigo, robeLong = true, bootsTall = false, robeFlare = 1.12f
            };
            BuildBody(k, shape, o);
            Brows(k, Pal.HairGrey, 6f, 1f);
            Beard(k, Pal.HairGrey, 0.95f, 0.7f);
            var h = k[Bone.Head];
            // Katta oq salla
            h.SetColor(Pal.White).Sphere(new Vector3(0, 0.300f, -0.005f), new Vector3(0.13f, 0.150f, 0.13f), 6, 14);
            for (int i = 0; i < 3; i++)
                h.SetColor(i % 2 == 0 ? Pal.White : ColorUtil.Hex("#e2dac6")).Torus(new Vector3(0, 0.2f + i * 0.04f, 0), 0.13f - i * 0.008f, 0.036f, 20, 6, 1.02f);
            h.SetColor(Pal.Indigo).Lathe(new[] { new Vector2(0.06f, 0.370f), new Vector2(0.04f, 0.410f), new Vector2(0, 0.420f) }, 8);
            // Zumrad marjon va pat (jig'a)
            h.SetColor(Pal.Gold).Sphere(new Vector3(0, 0.260f, 0.15f), new Vector3(0.035f, 0.080f, 0.015f), 4, 8);
            var g = k.Glow(rig[Bone.Head], Pal.Emerald);
            g.SetColor(Pal.Emerald).Sphere(new Vector3(0, 0.260f, 0.163f), 0.018f, 4, 8);
            h.SetColor(Pal.White).Capsule(new Vector3(0, 0.290f, 0.15f), new Vector3(0.02f, 0.440f, 0.1f), 0.012f, 0.004f, 5);
            // Hassa (usturlobli)
            var grip = MountRot(rig.mountR, 0f);
            Staff(k, grip, ColorUtil.Hex("#5a3a1e"), Pal.Gold, ColorUtil.Hex("#7fc8ff"), out rig.weaponBaseR, out rig.weaponTipR);
            // Kitob (belda)
            k[Bone.Hips].SetColor(ColorUtil.Hex("#6a2a1a")).Box(new Vector3(0.17f, 0.0f, 0.04f), new Vector3(0.04f, 0.14f, 0.11f));
            k.Finish();
            rig.gameObject.AddComponent<CharacterProps>();
            return rig;
        }

        // ===================== Chingizxon =====================
        public static Rig BuildChingiz(Transform parent)
        {
            var shape = new BodyShape { height = 0.98f, shoulders = 1.12f, bulk = 1.15f, legLength = 0.96f };
            var rig = Rig.Create(parent, shape, "Chingiz");
            var k = new BodyKit(rig);
            // Del (mo'g'ul to'ni) — diagonal yoqa
            Func<float, float, Color> deel = (u, v) =>
            {
                float lap = 0.08f + v * 0.1f;
                if (Mathf.Abs(u - lap) < 0.025f) return Pal.Gold;
                if (v < 0.06f) return Pal.Fur;
                return Frac(v * 20) < 0.08f ? ColorUtil.Hex("#5e2a1f") : Pal.Burgundy;
            };
            Func<float, float, Color> lamellar = (u, v) =>
            {
                float lap = 0.08f + v * 0.15f;
                if (Mathf.Abs(u - lap) < 0.03f) return Pal.Gold;
                int row = Mathf.FloorToInt(v * 8);
                if (Frac(v * 8) < 0.2f) return Pal.LeatherDark;
                return Frac(u * 26 + (row % 2) * 0.5f) < 0.15f ? Pal.LeatherDark : ColorUtil.Hex("#7a4a26");
            };
            var o = new Outfit
            {
                skin = Pal.SkinDark, shirt = ColorUtil.Hex("#7a4a26"), sleeve = Pal.Burgundy, trousers = ColorUtil.Hex("#2e2620"),
                boots = Pal.LeatherDark, belt = ColorUtil.Hex("#2b1a12"), beltBuckle = Pal.Gold, robe = Pal.Burgundy, robeFn = deel,
                chestFn = lamellar, sleeveFn = (u, v) => v < 0.12f ? Pal.Fur : Pal.Burgundy, bracers = true, bracerColor = Pal.LeatherDark, bootsTall = true, robeFlare = 1.1f
            };
            BuildBody(k, shape, o);
            Brows(k, Pal.Hair, 18f, 1.4f);
            Beard(k, Pal.Hair, 0.7f, 0.0f, true, true);
            Goatee(k, Pal.Hair);
            var h = k[Bone.Head];
            // Mo'ynali qalpoq
            h.SetColor(Pal.Burgundy).Lathe(new[] { new Vector2(0.112f, 0.195f), new Vector2(0.118f, 0.245f), new Vector2(0.095f, 0.315f), new Vector2(0.05f, 0.365f), new Vector2(0, 0.380f) }, 14, Vector3.zero, 1, 1, false,
                (u, v) => Frac(u * 6) < 0.06f ? Pal.Gold : Pal.Burgundy);
            h.SetColor(Pal.Fur).Torus(new Vector3(0, 0.200f, 0), 0.122f, 0.042f, 18, 6, 1.05f);
            h.SetColor(Pal.Gold).Sphere(new Vector3(0, 0.390f, 0), 0.025f, 4, 8);
            h.SetColor(Pal.Crimson).Capsule(new Vector3(0, 0.405f, 0), new Vector3(0, 0.475f, -0.03f), 0.01f, 0.025f, 6);
            // Quloqchinlar
            h.SetColor(Pal.Fur).Box(new Vector3(-0.112f, 0.12f, -0.035f), new Vector3(0.025f, 0.11f, 0.06f));
            h.SetColor(Pal.Fur).Box(new Vector3(0.112f, 0.12f, -0.035f), new Vector3(0.025f, 0.11f, 0.06f));
            // O'rilgan sochlar
            foreach (var sx in new[] { -1f, 1f })
                h.SetColor(Pal.Hair).Capsule(new Vector3(sx * 0.09f, 0.1f, -0.07f), new Vector3(sx * 0.1f, -0.13f, -0.06f), 0.02f, 0.012f, 6);
            // Qilich + kamon orqada + o'qdon
            var grip = MountRot(rig.mountR, 50f);
            Saber(k, grip, 0.78f, ColorUtil.Hex("#d6dae0"), ColorUtil.Hex("#b08a40"), Pal.LeatherDark, out rig.weaponBaseR, out rig.weaponTipR);
            var props = rig.gameObject.AddComponent<CharacterProps>();
            var bowBack = Bow(rig.mountBack, new Vector3(0, -0.02f, -0.04f), Quaternion.Euler(0, 90, 35), ColorUtil.Hex("#6a3a1c"), Pal.Gold);
            var bowHand = Bow(rig.mountL, new Vector3(0, 0, 0.02f), Quaternion.Euler(90, 0, 0) * Quaternion.Euler(0, 180, 0), ColorUtil.Hex("#6a3a1c"), Pal.Gold);
            bowHand.SetActive(false);
            props.items["bowBack"] = bowBack;
            props.items["bowHand"] = bowHand;
            Quiver(k[Bone.Hips], Pal.Leather);
            k.Finish();
            return rig;
        }

        // ===================== Qishloq aholisi (tomoshabinlar) =====================
        public static Rig BuildVillager(Transform parent, int seed)
        {
            var r = new System.Random(seed);
            float Rf(float a, float b) => a + (float)r.NextDouble() * (b - a);
            bool female = r.NextDouble() < 0.35;
            var shape = new BodyShape { height = Rf(0.9f, 1.02f), shoulders = female ? 0.9f : Rf(0.95f, 1.05f), bulk = Rf(0.92f, 1.12f) };
            var rig = Rig.Create(parent, shape, "Villager");
            var k = new BodyKit(rig) { outline = 0.008f };
            Color[][] palettes =
            {
                new[] { ColorUtil.Hex("#2a4d8f"), ColorUtil.Hex("#c23b3b"), ColorUtil.Hex("#e8c547"), ColorUtil.Hex("#2a4d8f"), ColorUtil.Hex("#f3eadb") },
                new[] { ColorUtil.Hex("#7a2a5a"), ColorUtil.Hex("#e0a030"), ColorUtil.Hex("#2f7a4a"), ColorUtil.Hex("#7a2a5a") },
                new[] { ColorUtil.Hex("#3a3a6a"), ColorUtil.Hex("#9a9ad0"), ColorUtil.Hex("#3a3a6a"), ColorUtil.Hex("#d0b070") },
                new[] { ColorUtil.Hex("#5a2a1a"), ColorUtil.Hex("#c06030"), ColorUtil.Hex("#f0d090"), ColorUtil.Hex("#5a2a1a") },
                new[] { ColorUtil.Hex("#1a5a5a"), ColorUtil.Hex("#e0e0d0"), ColorUtil.Hex("#c03050"), ColorUtil.Hex("#1a5a5a") },
            };
            var pal = palettes[r.Next(palettes.Length)];
            Color skin = Color.Lerp(Pal.SkinDark, Pal.SkinLight, (float)r.NextDouble());
            var robe = female ? Ikat(pal, 4f) : Stripes(pal);
            var o = new Outfit
            {
                skin = skin, shirt = Pal.White, sleeve = pal[0], trousers = ColorUtil.Hex("#2a2a30"), boots = Pal.LeatherDark,
                belt = female ? pal[1] : ColorUtil.Hex("#e8e0d0"), beltBuckle = pal[2], robe = pal[0], robeFn = robe,
                chestFn = (u, v) => robe(u, v), sleeveFn = (u, v) => robe(u, v), robeLong = female || r.NextDouble() < 0.3, bootsTall = true, robeFlare = 1f
            };
            BuildBody(k, shape, o);
            Brows(k, Pal.Hair, Rf(-4, 8), 1f);
            var h = k[Bone.Head];
            if (female)
            {
                // Ro'mol
                Color scarf = pal[r.Next(pal.Length)];
                h.SetColor(scarf).Lathe(new[] { new Vector2(0.105f, 0.08f), new Vector2(0.115f, 0.16f), new Vector2(0.1f, 0.24f), new Vector2(0.05f, 0.27f), new Vector2(0, 0.275f) }, 14, Vector3.zero, 1, 1.05f, false, null, 40f, 280f);
                h.SetColor(scarf).Lathe(new[] { new Vector2(0.11f, 0.12f), new Vector2(0.13f, 0.0f), new Vector2(0.16f, -0.12f) }, 12, Vector3.zero, 1, 1.05f, true, null, 70f, 220f);
            }
            else
            {
                // Chust do'ppisi — to'rt qirrali, qora, oq qalampir naqsh
                h.SetColor(Pal.Black).Lathe(new[] { new Vector2(0.135f, 0.17f), new Vector2(0.14f, 0.22f), new Vector2(0.12f, 0.27f), new Vector2(0, 0.285f) }, 4, Vector3.zero, 1, 1, true,
                    (u, v) => (Frac(u * 4) > 0.35f && Frac(u * 4) < 0.65f && v > 0.25f && v < 0.75f) ? Pal.White : Pal.Black, 45f);
                if (r.NextDouble() < 0.6) Beard(k, r.NextDouble() < 0.4 ? Pal.HairGrey : Pal.Hair, Rf(0.85f, 1.05f), Rf(0.2f, 1.2f));
            }
            k.Finish();
            return rig;
        }
    }
}
