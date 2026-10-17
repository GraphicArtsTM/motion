using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    public enum ArenaPreset { Sunset, Night }

    /// <summary>
    /// Qadimiy o'zbek qishlog'i — jang maydoni. Barcha geometriya va teksturalar protsedural.
    /// Paxsa uylar, ayvon, peshtoq (koshinli darvoza), Go'ri Amir uslubidagi gumbaz, minora,
    /// tandir, so'ri (tapchan), tut daraxti, teraklar, tog'lar va tomoshabin qishloqdoshlar.
    /// </summary>
    public class Arena : MonoBehaviour
    {
        public ArenaPreset preset;
        public Light sun;
        Material sky;
        readonly Dictionary<Material, MeshBuilder> builders = new Dictionary<Material, MeshBuilder>();
        readonly List<Transform> flags = new List<Transform>();
        readonly List<Mesh> flagMeshes = new List<Mesh>();
        readonly List<Vector3[]> flagBase = new List<Vector3[]>();
        readonly List<Light> lanterns = new List<Light>();
        readonly List<Villager> crowd = new List<Villager>();
        readonly List<Transform> birds = new List<Transform>();
        Light lightningLight;
        Vector3[] flagWork;
        LineRenderer bolt;
        float darkT, darkTarget;
        float lightningTime = -10;
        ParticleSystem motes;

        // Preset ranglari
        Color skyTop, skyHor, skyBot, sunCol, ambSky, ambEq, ambGround, fogCol;
        float sunIntensity;

        Material mEarth, mPaving, mPlaster, mBrick, mWood, mDoor, mGirih, mBorder, mSuzani, mCarpet, mLeaves, mMountain, mVC, mGlow, mDark, mTileVC;

        public static Arena Build(ArenaPreset preset)
        {
            var go = new GameObject("Arena_" + preset);
            var a = go.AddComponent<Arena>();
            a.preset = preset;
            a.Construct();
            return a;
        }

        MeshBuilder MB(Material m)
        {
            if (!builders.TryGetValue(m, out var b)) builders[m] = b = new MeshBuilder();
            b.ResetTransform();
            return b;
        }

        void Construct()
        {
            mEarth = Mat.Toon(Color.white, TextureFactory.Earth(), 0.05f);
            mPaving = Mat.Toon(Color.white, TextureFactory.BrickPaving(), 0.05f);
            mPlaster = Mat.Toon(Color.white, TextureFactory.Plaster(), 0.1f);
            mBrick = Mat.Toon(Color.white, TextureFactory.MudBrick(), 0.1f);
            mWood = Mat.Toon(Color.white, TextureFactory.Wood(), 0.15f);
            mDoor = Mat.Toon(Color.white, TextureFactory.CarvedDoor(), 0.1f);
            mGirih = Mat.Toon(Color.white, TextureFactory.GirihTile(), 0.25f, null, 0.4f);
            mBorder = Mat.Toon(Color.white, TextureFactory.TileBorder(), 0.25f, null, 0.4f);
            mSuzani = Mat.Toon(Color.white, TextureFactory.Suzani(), 0.1f);
            mCarpet = Mat.Toon(Color.white, TextureFactory.Carpet(), 0.05f);
            mLeaves = Mat.Toon(Color.white, TextureFactory.Leaves(), 0.2f);
            mMountain = Mat.Toon(Color.white, TextureFactory.Mountain(), 0.0f);
            mVC = Mat.Toon(Color.white, null, 0.2f);
            mTileVC = Mat.Toon(Color.white, null, 0.35f, null, 0.5f);
            mGlow = Mat.Toon(Color.white, null, 0.0f, new Color(1f, 0.7f, 0.35f) * 1.8f);
            mDark = Mat.Toon(new Color(0.08f, 0.07f, 0.1f), null, 0f);

            SetupLighting();
            BuildGround();
            BuildCourtyard();
            BuildHouses();
            BuildPortal();
            BuildLandmarks();
            BuildTrees();
            BuildProps();
            BuildMountains();

            foreach (var kv in builders)
            {
                if (kv.Value.IsEmpty) continue;
                kv.Value.ResetTransform();
                var g = kv.Value.Build("static_" + kv.Key.name, transform, kv.Key, true);
                g.isStatic = true;
            }
            BuildFlags();
            BuildCrowd();
            BuildBirds();
            BuildAtmosphere();
            BuildLightning();
        }

        // ---------------- Yoritish ----------------
        void SetupLighting()
        {
            if (preset == ArenaPreset.Sunset)
            {
                skyTop = ColorUtil.Hex("#3b4f8f"); skyHor = ColorUtil.Hex("#f2a35e"); skyBot = ColorUtil.Hex("#6b4a3a");
                sunCol = ColorUtil.Hex("#ffd2a0"); sunIntensity = 1.25f;
                ambSky = ColorUtil.Hex("#8c86a8"); ambEq = ColorUtil.Hex("#9a7a68"); ambGround = ColorUtil.Hex("#4a3a30");
                fogCol = ColorUtil.Hex("#d9a07a");
            }
            else
            {
                skyTop = ColorUtil.Hex("#070b22"); skyHor = ColorUtil.Hex("#2a3466"); skyBot = ColorUtil.Hex("#141420");
                sunCol = ColorUtil.Hex("#9fb4ff"); sunIntensity = 0.55f;
                ambSky = ColorUtil.Hex("#2c3460"); ambEq = ColorUtil.Hex("#2a2840"); ambGround = ColorUtil.Hex("#151420");
                fogCol = ColorUtil.Hex("#1c2246");
            }
            sky = new Material(Mat.SkyShader);
            ApplySky(0);
            RenderSettings.skybox = sky;
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Linear;
            RenderSettings.fogStartDistance = 35f;
            RenderSettings.fogEndDistance = 240f;

            var sunGo = new GameObject("Sun");
            sunGo.transform.SetParent(transform, false);
            sun = sunGo.AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = 0.75f;
            sun.shadowBias = 0.04f;
            sun.shadowNormalBias = 0.3f;
            sunGo.transform.rotation = Quaternion.Euler(38, 28, 0);
            RenderSettings.sun = sun;

            // To'ldiruvchi orqa yorug'lik (rim)
            var rim = new GameObject("RimLight").AddComponent<Light>();
            rim.transform.SetParent(transform, false);
            rim.type = LightType.Directional;
            rim.color = preset == ArenaPreset.Sunset ? ColorUtil.Hex("#ffb070") : ColorUtil.Hex("#6080ff");
            rim.intensity = preset == ArenaPreset.Sunset ? 0.45f : 0.35f;
            rim.shadows = LightShadows.None;
            rim.transform.rotation = Quaternion.Euler(20, 200, 0);
        }

        void ApplySky(float dark)
        {
            Color dTop = ColorUtil.Hex("#1a0608"), dHor = ColorUtil.Hex("#7a1a12"), dBot = ColorUtil.Hex("#200808");
            sky.SetColor("_TopColor", Color.Lerp(skyTop, dTop, dark));
            sky.SetColor("_HorizonColor", Color.Lerp(skyHor, dHor, dark));
            sky.SetColor("_BottomColor", Color.Lerp(skyBot, dBot, dark));
            sky.SetColor("_SunColor", preset == ArenaPreset.Sunset ? Color.Lerp(ColorUtil.Hex("#ffd890"), ColorUtil.Hex("#ff5030"), dark) : ColorUtil.Hex("#dfe6ff"));
            sky.SetVector("_SunDir", preset == ArenaPreset.Sunset ? new Vector4(0.35f, 0.07f, 1f, 0) : new Vector4(-0.4f, 0.45f, 1f, 0));
            sky.SetFloat("_SunSize", preset == ArenaPreset.Sunset ? 0.035f : 0.018f);
            sky.SetFloat("_StarStrength", preset == ArenaPreset.Night ? 0.9f : dark * 0.5f);
            sky.SetColor("_CloudColor", preset == ArenaPreset.Sunset ? new Color(1f, 0.75f, 0.6f, 0.45f) : new Color(0.3f, 0.35f, 0.6f, 0.3f));
            RenderSettings.ambientSkyColor = Color.Lerp(ambSky, ColorUtil.Hex("#502020"), dark);
            RenderSettings.ambientEquatorColor = Color.Lerp(ambEq, ColorUtil.Hex("#401818"), dark);
            RenderSettings.ambientGroundColor = Color.Lerp(ambGround, ColorUtil.Hex("#180808"), dark);
            RenderSettings.fogColor = Color.Lerp(fogCol, ColorUtil.Hex("#3a0e0a"), dark);
            if (sun)
            {
                sun.color = Color.Lerp(sunCol, ColorUtil.Hex("#ff7050"), dark);
                sun.intensity = Mathf.Lerp(sunIntensity, 0.7f, dark);
            }
        }

        // ---------------- Yer ----------------
        void BuildGround()
        {
            MB(mEarth).Plane(new Vector3(0, -0.01f, 30), new Vector2(260, 140), 26, 14, 0.12f, (x, z) =>
            {
                float d = Mathf.Max(0, Mathf.Abs(z - 30) - 25) + Mathf.Max(0, Mathf.Abs(x) - 60);
                return Noise.Fbm(x * 0.05f, z * 0.05f, 3, 7) * 1.5f * Mathf.Clamp01(d / 30f) + (z > 70 ? (z - 70) * 0.05f : 0);
            });
            // Hovli yo'lagi (pishiq g'isht)
            MB(mPaving).Plane(new Vector3(0, 0.0f, 0), new Vector2(30, 5.2f), 6, 1, 0.5f);
            // Yo'lak chetlari
            MB(mBrick).Box(new Vector3(0, 0.03f, 2.7f), new Vector3(30, 0.08f, 0.25f), 1f);
            MB(mBrick).Box(new Vector3(0, 0.03f, -2.7f), new Vector3(30, 0.08f, 0.25f), 1f);
            // Markaziy gilam (palos)
            var cb = MB(mCarpet);
            float cy = 0.012f;
            cb.AddQuad(new Vector3(4.5f, cy, -1.5f), new Vector3(-4.5f, cy, -1.5f), new Vector3(-4.5f, cy, 1.9f), new Vector3(4.5f, cy, 1.9f), Vector2.zero, Vector2.one);
            var fr = MB(mVC).SetColor(ColorUtil.Hex("#e8d7b0"));
            for (int i = -8; i <= 8; i++)
            {
                fr.Box(new Vector3(4.58f, 0.012f, 0.2f + i * 0.2f), new Vector3(0.16f, 0.006f, 0.03f));
                fr.Box(new Vector3(-4.58f, 0.012f, 0.2f + i * 0.2f), new Vector3(0.16f, 0.006f, 0.03f));
            }
        }

        // ---------------- Hovli devori ----------------
        void BuildCourtyard()
        {
            // Orqa past paxsa devor (duval) — teshiklar bilan
            for (int s = -1; s <= 1; s += 2)
            {
                var w = MB(mBrick);
                w.Box(new Vector3(s * 9f, 0.7f, 6.2f), new Vector3(8f, 1.4f, 0.5f), 0.7f);
                var top = MB(mPlaster);
                top.Box(new Vector3(s * 9f, 1.45f, 6.2f), new Vector3(8.2f, 0.12f, 0.62f), 0.5f);
            }
            // Yon devorlar (uzoqda)
            MB(mBrick).Box(new Vector3(-26f, 1.2f, 8f), new Vector3(16f, 2.4f, 0.6f), 0.7f);
            MB(mBrick).Box(new Vector3(26f, 1.2f, 8f), new Vector3(16f, 2.4f, 0.6f), 0.7f);
        }

        // ---------------- Uylar ----------------
        void BuildHouses()
        {
            House(new Vector3(-12.5f, 0, 9f), new Vector3(9f, 4.2f, 5f), true, 0);
            House(new Vector3(13f, 0, 9.5f), new Vector3(8f, 3.8f, 5f), true, 1);
            House(new Vector3(-22f, 0, 13f), new Vector3(7f, 3.6f, 5f), false, 2);
            House(new Vector3(22f, 0, 14f), new Vector3(7f, 4.4f, 5f), false, 3);
            House(new Vector3(-31f, 0, 18f), new Vector3(8f, 3.4f, 5f), false, 4);
            House(new Vector3(32f, 0, 20f), new Vector3(9f, 3.9f, 5f), false, 5);
        }

        void House(Vector3 p, Vector3 size, bool ayvan, int seed)
        {
            var r = new System.Random(seed * 13 + 7);
            // Devorlar
            MB(seed % 2 == 0 ? mPlaster : mBrick).Box(p + new Vector3(0, size.y / 2, size.z / 2), size, 0.5f);
            // Tom (loy tom, yog'och to'sinlar chiqib turadi)
            MB(mPlaster).Box(p + new Vector3(0, size.y + 0.12f, size.z / 2 - 0.2f), new Vector3(size.x + 0.6f, 0.24f, size.z + 0.9f), 0.5f);
            var wood = MB(mWood);
            for (float x = -size.x / 2 + 0.3f; x < size.x / 2; x += 0.55f)
            {
                wood.SetTransform(p + new Vector3(x, size.y - 0.06f, -0.25f), Quaternion.Euler(90, 0, 0));
                wood.Cylinder(Vector3.zero, 0.07f, 0.07f, -0.2f, 0.45f, 6);
            }
            wood.ResetTransform();
            // Tomda pichan uyumi
            if (r.NextDouble() < 0.7)
            {
                var hay = MB(mVC).SetColor(ColorUtil.Hex("#c9a659"));
                hay.Sphere(p + new Vector3((float)(r.NextDouble() - 0.5) * size.x * 0.6f, size.y + 0.5f, size.z * 0.6f), new Vector3(1.2f, 0.55f, 0.9f), 5, 9);
            }
            // Eshik
            float doorX = ayvan ? 0 : (float)(r.NextDouble() - 0.5) * size.x * 0.4f;
            var door = MB(mDoor);
            door.Panel(p + new Vector3(doorX, 1.05f, -0.015f), new Vector2(1.1f, 2.1f), Vector2.zero, Vector2.one);
            var frame = MB(mWood);
            frame.Box(p + new Vector3(doorX, 2.18f, -0.05f), new Vector3(1.4f, 0.16f, 0.12f), 1f);
            frame.Box(p + new Vector3(doorX - 0.63f, 1.05f, -0.05f), new Vector3(0.14f, 2.1f, 0.12f), 1f);
            frame.Box(p + new Vector3(doorX + 0.63f, 1.05f, -0.05f), new Vector3(0.14f, 2.1f, 0.12f), 1f);
            // Derazalar (panjara)
            foreach (var wx in new[] { -size.x * 0.32f, size.x * 0.32f })
            {
                if (Mathf.Abs(wx - doorX) < 1.3f) continue;
                MB(mDark).Panel(p + new Vector3(wx, 1.9f, -0.02f), new Vector2(0.9f, 0.9f), Vector2.zero, Vector2.one);
                var lat = MB(mWood);
                for (int i = -2; i <= 2; i++)
                {
                    lat.Box(p + new Vector3(wx + i * 0.18f, 1.9f, -0.05f), new Vector3(0.04f, 0.9f, 0.04f));
                    lat.Box(p + new Vector3(wx, 1.9f + i * 0.18f, -0.05f), new Vector3(0.9f, 0.04f, 0.04f));
                }
                lat.Box(p + new Vector3(wx, 2.4f, -0.06f), new Vector3(1.1f, 0.1f, 0.1f));
                lat.Box(p + new Vector3(wx, 1.4f, -0.06f), new Vector3(1.1f, 0.1f, 0.1f));
            }
            // Devorga osilgan suzani
            if (!ayvan && r.NextDouble() < 0.8)
            {
                MB(mSuzani).Panel(p + new Vector3(size.x * 0.3f * (doorX > 0 ? -1 : 1), 2.1f, -0.03f), new Vector2(1.6f, 1.0f), Vector2.zero, Vector2.one);
            }
            if (ayvan) Ayvan(p, size);
        }

        /// <summary>Ayvon — o'ymakor ustunli ochiq ayvon (o'zbek uyi belgisi).</summary>
        void Ayvan(Vector3 p, Vector3 size)
        {
            float depth = 2.2f;
            float h = size.y - 0.2f;
            // Supa (pol)
            MB(mBrick).Box(p + new Vector3(0, 0.2f, -depth / 2), new Vector3(size.x, 0.4f, depth), 0.7f);
            // Ustunlar
            int n = 4;
            var wood = MB(mWood);
            for (int i = 0; i < n; i++)
            {
                float x = Mathf.Lerp(-size.x / 2 + 0.5f, size.x / 2 - 0.5f, i / (float)(n - 1));
                Vector3 b = p + new Vector3(x, 0.4f, -depth + 0.25f);
                wood.Lathe(new[]
                {
                    new Vector2(0, 0), new Vector2(0.24f, 0), new Vector2(0.24f, 0.18f), new Vector2(0.15f, 0.28f), new Vector2(0.2f, 0.42f), new Vector2(0.13f, 0.6f),
                    new Vector2(0.11f, h * 0.55f), new Vector2(0.14f, h * 0.6f), new Vector2(0.1f, h * 0.66f), new Vector2(0.095f, h - 0.75f),
                    new Vector2(0.17f, h - 0.62f), new Vector2(0.28f, h - 0.48f), new Vector2(0.3f, h - 0.42f), new Vector2(0, h - 0.4f)
                }, 10, b);
            }
            // To'sin va naqshli friz
            wood.Box(p + new Vector3(0, h - 0.25f + 0.4f, -depth + 0.25f), new Vector3(size.x + 0.2f, 0.32f, 0.38f), 1f);
            MB(mBorder).Panel(p + new Vector3(0, h - 0.25f + 0.4f, -depth + 0.05f), new Vector2(size.x, 0.26f), Vector2.zero, new Vector2(size.x / 1.2f, 1f));
            // Ayvon tomi
            MB(mPlaster).Box(p + new Vector3(0, h + 0.55f, -depth / 2), new Vector3(size.x + 0.4f, 0.22f, depth + 0.2f), 0.5f);
            // Ichki shift — rangli
            MB(mVC).SetColor(ColorUtil.Hex("#2c4a7a")).Box(p + new Vector3(0, h + 0.42f, -depth / 2), new Vector3(size.x, 0.04f, depth));
            // Ayvon ichida so'ri va gilam
            MB(mSuzani).Panel(p + new Vector3(-size.x * 0.25f, 2.0f, -0.02f), new Vector2(2.2f, 1.4f), Vector2.zero, Vector2.one);
            // Fonar
            Lantern(p + new Vector3(size.x * 0.25f, h - 0.1f, -depth + 0.4f));
            Lantern(p + new Vector3(-size.x * 0.25f, h - 0.1f, -depth + 0.4f));
        }

        void Lantern(Vector3 at)
        {
            MB(mVC).SetColor(ColorUtil.Hex("#3a2a1a")).Cylinder(at, 0.01f, 0.01f, 0, 0.5f, 4);
            MB(mVC).SetColor(ColorUtil.Hex("#8a6a2a")).Cylinder(at, 0.14f, 0.1f, 0.0f, 0.05f, 8);
            MB(mGlow).Lathe(new[] { new Vector2(0, -0.32f), new Vector2(0.1f, -0.26f), new Vector2(0.13f, -0.12f), new Vector2(0.1f, 0f), new Vector2(0, 0.02f) }, 8, at);
            var l = new GameObject("Lantern").AddComponent<Light>();
            l.transform.SetParent(transform, false);
            l.transform.position = at + Vector3.down * 0.2f;
            l.type = LightType.Point;
            l.color = new Color(1f, 0.65f, 0.3f);
            l.range = preset == ArenaPreset.Night ? 7f : 4f;
            l.intensity = preset == ArenaPreset.Night ? 2.2f : 0.6f;
            l.shadows = LightShadows.None;
            lanterns.Add(l);
        }

        // ---------------- Peshtoq (koshinli darvoza) ----------------
        void BuildPortal()
        {
            Vector3 c = new Vector3(0, 0, 16f);
            float W = 11f, H = 11f, D = 2f;
            // Asosiy devor bloki
            MB(mBrick).Box(c + new Vector3(0, H / 2, D / 2), new Vector3(W, H, D), 0.5f);
            // Old yuzaga girih koshinlari
            MB(mGirih).Panel(c + new Vector3(-W / 2 + 1.6f, H / 2, -0.02f), new Vector2(3.2f, H), Vector2.zero, new Vector2(1.6f, H / 2));
            MB(mGirih).Panel(c + new Vector3(W / 2 - 1.6f, H / 2, -0.02f), new Vector2(3.2f, H), Vector2.zero, new Vector2(1.6f, H / 2));
            MB(mGirih).Panel(c + new Vector3(0, H - 1.0f, -0.02f), new Vector2(4.6f, 2.0f), Vector2.zero, new Vector2(2.3f, 1f));
            // Chegara bandlari
            MB(mBorder).Panel(c + new Vector3(0, H - 0.2f, -0.04f), new Vector2(W, 0.4f), Vector2.zero, new Vector2(W / 1.5f, 1));
            var bl = MB(mBorder);
            bl.SetTransform(c + new Vector3(-2.35f, (H - 2f) / 2, -0.04f), Quaternion.Euler(0, 0, 90));
            bl.Panel(Vector3.zero, new Vector2(H - 2f, 0.35f), Vector2.zero, new Vector2((H - 2f) / 1.5f, 1));
            bl.SetTransform(c + new Vector3(2.35f, (H - 2f) / 2, -0.04f), Quaternion.Euler(0, 0, 90));
            bl.Panel(Vector3.zero, new Vector2(H - 2f, 0.35f), Vector2.zero, new Vector2((H - 2f) / 1.5f, 1));
            bl.ResetTransform();
            // Ravoq (uchli arka) — to'q ko'k nisha va oq ramka
            var niche = MB(mTileVC);
            Color deep = ColorUtil.Hex("#0d2a66"), turq = ColorUtil.Hex("#1a8f9e"), cream = ColorUtil.Hex("#e8dfc8");
            float nz = c.z - 0.03f, archBase = 6.6f, archH = 2.8f, archW = 2.1f;
            niche.SetColor(deep).Panel(new Vector3(c.x, archBase / 2, nz), new Vector2(archW * 2, archBase), Vector2.zero, Vector2.one);
            var arch = new List<Vector3>();
            for (int i = 0; i <= 16; i++)
            {
                float t = i / 16f;
                float ang = Mathf.Lerp(0, Mathf.PI, t);
                arch.Add(new Vector3(c.x - Mathf.Cos(ang) * archW, archBase + Mathf.Pow(Mathf.Sin(ang), 0.8f) * archH * (1f - 0.15f * Mathf.Abs(Mathf.Cos(ang))), nz));
            }
            Vector3 hub = new Vector3(c.x, archBase, nz);
            for (int i = 0; i < arch.Count - 1; i++)
            {
                // Muqarnas taqlidi: navbatma-navbat rangli uchburchaklar
                niche.SetColor(i % 2 == 0 ? turq : deep);
                niche.AddTriangle(hub, arch[i], arch[i + 1]);
            }
            niche.SetColor(cream);
            foreach (var ap in arch) niche.Box(ap + new Vector3(0, 0, -0.06f), new Vector3(0.3f, 0.3f, 0.14f));
            for (float yy = 0.15f; yy < archBase; yy += 0.3f)
            {
                niche.Box(new Vector3(c.x - archW, yy, nz - 0.06f), new Vector3(0.3f, 0.3f, 0.14f));
                niche.Box(new Vector3(c.x + archW, yy, nz - 0.06f), new Vector3(0.3f, 0.3f, 0.14f));
            }
            // Spandrel (ravoq usti burchaklari) — girih
            MB(mGirih).Panel(new Vector3(c.x - archW - 0.1f, archBase + archH * 0.5f + 0.1f, nz - 0.01f), new Vector2(0.4f, archH + 0.2f), Vector2.zero, new Vector2(0.2f, 1.5f));
            // Darvoza eshigi
            MB(mDoor).Panel(c + new Vector3(0, 1.6f, -0.05f), new Vector2(2.4f, 3.2f), Vector2.zero, new Vector2(2, 1));
            // Guldasta minorachalar
            foreach (var sx in new[] { -1f, 1f })
            {
                var g = MB(mTileVC);
                Vector3 b = c + new Vector3(sx * (W / 2 - 0.2f), 0, -0.1f);
                g.Lathe(new[] { new Vector2(0, 0), new Vector2(0.55f, 0), new Vector2(0.5f, H + 1.2f), new Vector2(0.65f, H + 1.3f), new Vector2(0.6f, H + 2.0f), new Vector2(0.45f, H + 2.4f), new Vector2(0, H + 2.8f) }, 12, b, 1, 1, true,
                    (u, v) => v > 0.85f ? turq : Mathf.FloorToInt(v * 30) % 3 == 0 ? ColorUtil.Hex("#c79a64") : ColorUtil.Hex("#b07a4a"));
            }
            // Orqasidagi kichik gumbazlar
            Dome(c + new Vector3(-4f, H - 1f, 4f), 2.2f, ColorUtil.Hex("#1f9fae"), 24);
            Dome(c + new Vector3(4f, H - 1f, 4f), 2.2f, ColorUtil.Hex("#1f9fae"), 24);
        }

        void Dome(Vector3 at, float r, Color c, int ribs)
        {
            var d = MB(mTileVC);
            d.Cylinder(at, r * 0.9f, r * 0.9f, -1f, 0.6f, 20, true, 1, 1, (u, v) => Mathf.FloorToInt(u * 40) % 2 == 0 ? ColorUtil.Hex("#163a8a") : ColorUtil.Hex("#e8dfc8"));
            d.Lathe(new[] { new Vector2(r * 0.88f, 0.6f), new Vector2(r * 1.02f, 0.6f + r * 0.4f), new Vector2(r * 1.0f, 0.6f + r * 0.8f), new Vector2(r * 0.75f, 0.6f + r * 1.25f),
                new Vector2(r * 0.35f, 0.6f + r * 1.55f), new Vector2(r * 0.05f, 0.6f + r * 1.7f), new Vector2(0, 0.6f + r * 1.75f) }, ribs * 2, at, 1, 1, false,
                (u, v) => Mathf.FloorToInt(u * ribs * 2) % 2 == 0 ? c : c.Mul(0.78f));
            d.SetColor(Pal.Gold).Cylinder(at + Vector3.up * (0.6f + r * 1.72f), 0.05f, 0.03f, 0, r * 0.4f, 6);
        }

        // ---------------- Uzoqdagi obidalar ----------------
        void BuildLandmarks()
        {
            // Go'ri Amir uslubidagi qovurg'ali ko'k gumbaz
            Vector3 g = new Vector3(-24f, 0, 55f);
            MB(mBrick).Box(g + new Vector3(0, 6f, 0), new Vector3(14f, 12f, 14f), 0.3f);
            MB(mGirih).Panel(g + new Vector3(0, 7f, -7.02f), new Vector2(6f, 9f), Vector2.zero, new Vector2(3f, 4.5f));
            var drum = MB(mTileVC);
            drum.Cylinder(g + Vector3.up * 12f, 5.2f, 5.2f, 0, 5f, 32, true, 1, 1, (u, v) =>
            {
                int k = Mathf.FloorToInt(u * 64);
                if (v > 0.3f && v < 0.7f) return k % 4 == 0 ? ColorUtil.Hex("#f0e6c8") : ColorUtil.Hex("#123c8c");
                return ColorUtil.Hex("#1a8f9e");
            });
            drum.Lathe(new[] { new Vector2(5.0f, 17f), new Vector2(6.3f, 19f), new Vector2(6.6f, 21.5f), new Vector2(6.0f, 24f), new Vector2(4.4f, 26.4f), new Vector2(2.2f, 28.2f), new Vector2(0.6f, 29f), new Vector2(0, 29.2f) },
                64, g, 1, 1, false, (u, v) => Mathf.FloorToInt(u * 64) % 2 == 0 ? ColorUtil.Hex("#1fa3b4") : ColorUtil.Hex("#137a8c"));
            drum.SetColor(Pal.Gold).Cylinder(g + Vector3.up * 29f, 0.2f, 0.08f, 0, 2.2f, 8);
            // Kalon uslubidagi minora
            Vector3 m = new Vector3(20f, 0, 62f);
            var mn = MB(mTileVC);
            mn.Lathe(new[] { new Vector2(0, 0), new Vector2(2.6f, 0), new Vector2(2.4f, 6f), new Vector2(1.8f, 30f), new Vector2(2.6f, 31f), new Vector2(2.6f, 33f), new Vector2(1.6f, 33.2f),
                new Vector2(1.6f, 35f), new Vector2(1.9f, 35.4f), new Vector2(1.2f, 36.8f), new Vector2(0, 37.4f) }, 20, m, 1, 1, true, (u, v) =>
            {
                if (v > 0.8f && v < 0.9f) return ColorUtil.Hex("#1a8f9e");
                int band = Mathf.FloorToInt(v * 40);
                if (band % 6 == 0) return ColorUtil.Hex("#e8c890");
                bool chk = (Mathf.FloorToInt(u * 40) + band) % 2 == 0;
                return chk ? ColorUtil.Hex("#c08a5a") : ColorUtil.Hex("#a8734a");
            });
            // Uzoqdagi kichik binolar siluetlari
            var r = new System.Random(3);
            for (int i = 0; i < 18; i++)
            {
                float x = -70 + i * 8f + (float)r.NextDouble() * 3;
                float z = 40 + (float)r.NextDouble() * 25;
                if (Mathf.Abs(x + 24) < 9 && z > 45) continue;
                float h = 3 + (float)r.NextDouble() * 4;
                MB(mPlaster).Box(new Vector3(x, h / 2, z), new Vector3(5 + (float)r.NextDouble() * 4, h, 5), 0.3f);
                if (r.NextDouble() < 0.3) Dome(new Vector3(x, h, z), 1.4f, ColorUtil.Hex("#2aa0ad"), 12);
            }
        }

        // ---------------- Daraxtlar ----------------
        void BuildTrees()
        {
            Mulberry(new Vector3(8.5f, 0, 5.2f), 1.1f, 1);
            Mulberry(new Vector3(-18f, 0, 6.5f), 0.9f, 2);
            // Teraklar qatori (o'zbek qishlog'ining belgisi)
            var r = new System.Random(11);
            for (int i = 0; i < 22; i++)
            {
                float x = -48 + i * 4.6f + (float)r.NextDouble() * 1.5f;
                float z = 26 + (float)r.NextDouble() * 6;
                if (Mathf.Abs(x) < 7) z += 6;
                Poplar(new Vector3(x, 0, z), 0.85f + (float)r.NextDouble() * 0.4f);
            }
        }

        void Mulberry(Vector3 p, float s, int seed)
        {
            var r = new System.Random(seed);
            var bark = MB(mVC).SetColor(ColorUtil.Hex("#5a4030"));
            bark.Lathe(new[] { new Vector2(0, 0), new Vector2(0.45f * s, 0), new Vector2(0.3f * s, 0.6f * s), new Vector2(0.26f * s, 2.4f * s), new Vector2(0.2f * s, 3.2f * s), new Vector2(0, 3.3f * s) }, 9, p);
            for (int i = 0; i < 4; i++)
            {
                float a = i * 1.7f;
                Vector3 b0 = p + new Vector3(0, 2.4f * s, 0);
                Vector3 b1 = b0 + new Vector3(Mathf.Cos(a) * 1.4f * s, 1.2f * s, Mathf.Sin(a) * 1.0f * s);
                bark.Capsule(b0, b1, 0.14f * s, 0.07f * s, 6);
            }
            var lv = MB(mLeaves);
            for (int i = 0; i < 9; i++)
            {
                Vector3 c = p + new Vector3(((float)r.NextDouble() - 0.5f) * 3.6f * s, (3.4f + (float)r.NextDouble() * 1.8f) * s, ((float)r.NextDouble() - 0.5f) * 2.6f * s);
                lv.Sphere(c, new Vector3(1.4f, 1.0f, 1.3f) * s * (0.8f + (float)r.NextDouble() * 0.4f), 5, 8);
            }
        }

        void Poplar(Vector3 p, float s)
        {
            MB(mVC).SetColor(ColorUtil.Hex("#d8d0c0")).Cylinder(p, 0.18f * s, 0.12f * s, 0, 2f * s, 6);
            MB(mLeaves).Lathe(new[] { new Vector2(0, 1.2f * s), new Vector2(0.9f * s, 2.4f * s), new Vector2(1.0f * s, 5f * s), new Vector2(0.75f * s, 8f * s), new Vector2(0.3f * s, 10.5f * s), new Vector2(0, 11.5f * s) }, 8, p);
        }

        // ---------------- Rekvizitlar ----------------
        void BuildProps()
        {
            // Tandir (non yopiladigan loy o'choq)
            Vector3 t = new Vector3(-7.5f, 0, 4.4f);
            MB(mBrick).Box(t + new Vector3(0, 0.45f, 0), new Vector3(1.8f, 0.9f, 1.6f), 0.7f);
            var td = MB(mVC).SetColor(ColorUtil.Hex("#c49a6c"));
            td.Lathe(new[] { new Vector2(0.75f, 0.9f), new Vector2(0.8f, 1.3f), new Vector2(0.6f, 1.75f), new Vector2(0.32f, 1.95f), new Vector2(0.3f, 1.98f), new Vector2(0, 1.98f) }, 14, t);
            MB(mDark).Box(t + new Vector3(0, 1.4f, -0.6f), new Vector3(0.45f, 0.4f, 0.1f));
            // Non (yopilgan nonlar savatda)
            var nb = MB(mVC);
            nb.SetColor(ColorUtil.Hex("#7a5a30")).Cylinder(t + new Vector3(1.6f, 0, -0.4f), 0.4f, 0.5f, 0, 0.3f, 10);
            for (int i = 0; i < 3; i++)
                nb.SetColor(ColorUtil.Hex("#d8a058")).Cylinder(t + new Vector3(1.6f, 0.3f + i * 0.06f, -0.4f), 0.3f, 0.28f, 0, 0.05f, 12, true, 1, 1, (u, v) => Mathf.FloorToInt(u * 12) % 3 == 0 ? ColorUtil.Hex("#b07838") : ColorUtil.Hex("#e0a860"));

            // So'ri (tapchan) + dasturxon
            Vector3 s = new Vector3(5.5f, 0, 4.6f);
            var w = MB(mWood);
            w.Box(s + new Vector3(0, 0.55f, 0), new Vector3(2.6f, 0.12f, 1.8f), 1f);
            foreach (var lx in new[] { -1.2f, 1.2f }) foreach (var lz in new[] { -0.8f, 0.8f }) w.Box(s + new Vector3(lx, 0.27f, lz), new Vector3(0.12f, 0.55f, 0.12f), 1f);
            for (int i = 0; i < 9; i++) w.Box(s + new Vector3(-1.2f + i * 0.3f, 0.95f, 0.85f), new Vector3(0.05f, 0.7f, 0.05f), 1f);
            w.Box(s + new Vector3(0, 1.3f, 0.85f), new Vector3(2.6f, 0.08f, 0.08f), 1f);
            {
                float sy = 0.62f;
                MB(mSuzani).AddQuad(s + new Vector3(-1.2f, sy, -0.8f), s + new Vector3(-1.2f, sy, 0.8f), s + new Vector3(1.2f, sy, 0.8f), s + new Vector3(1.2f, sy, -0.8f), Vector2.zero, Vector2.one);
            }
            var tb = MB(mVC);
            tb.SetColor(ColorUtil.Hex("#7a3a1a")).Box(s + new Vector3(0, 0.75f, 0), new Vector3(1.2f, 0.18f, 0.8f));
            tb.SetColor(ColorUtil.Hex("#c03030")).Box(s + new Vector3(0, 0.85f, 0), new Vector3(1.25f, 0.02f, 0.85f));
            // Choynak va piyolalar (ko'k-oq "paxta" naqshi)
            Vector3 tp = s + new Vector3(-0.2f, 0.86f, 0);
            tb.SetColor(Color.white).Lathe(new[] { new Vector2(0, 0), new Vector2(0.11f, 0), new Vector2(0.14f, 0.08f), new Vector2(0.12f, 0.16f), new Vector2(0.06f, 0.2f), new Vector2(0.07f, 0.24f), new Vector2(0, 0.25f) }, 12, tp, 1, 1, false,
                (u, v) => Mathf.FloorToInt(u * 12) % 2 == 0 && v > 0.2f && v < 0.6f ? ColorUtil.Hex("#2050a0") : Color.white);
            tb.SetColor(Color.white).Capsule(tp + new Vector3(0.12f, 0.08f, 0), tp + new Vector3(0.22f, 0.18f, 0), 0.02f, 0.015f, 5);
            for (int i = 0; i < 3; i++)
                tb.SetColor(Color.white).Lathe(new[] { new Vector2(0, 0), new Vector2(0.03f, 0), new Vector2(0.06f, 0.06f), new Vector2(0, 0.06f) }, 10, s + new Vector3(0.2f + i * 0.15f, 0.86f, 0.15f), 1, 1, false,
                    (u, v) => v > 0.5f ? ColorUtil.Hex("#2050a0") : Color.white);
            // Anor va non
            for (int i = 0; i < 4; i++) tb.SetColor(ColorUtil.Hex("#a01a1a")).Sphere(s + new Vector3(0.35f + (i % 2) * 0.1f, 0.91f, -0.2f + (i / 2) * 0.1f), 0.05f, 5, 7);
            // Ko'rpachalar
            var k = MB(mVC);
            k.SetColor(ColorUtil.Hex("#8a1a3a")).Box(s + new Vector3(-0.9f, 0.68f, 0), new Vector3(0.6f, 0.1f, 1.5f));
            k.SetColor(ColorUtil.Hex("#2a4a8a")).Box(s + new Vector3(0.9f, 0.68f, 0), new Vector3(0.6f, 0.1f, 1.5f));

            // Xumlar (katta loy ko'zalar)
            var r = new System.Random(21);
            Vector3[] pots = { new Vector3(-10.5f, 0, 4.2f), new Vector3(-10f, 0, 5f), new Vector3(10.6f, 0, 4.5f), new Vector3(-3.6f, 0, 5.8f), new Vector3(3.5f, 0, 5.9f) };
            foreach (var pp in pots)
            {
                float sc = 0.7f + (float)r.NextDouble() * 0.5f;
                MB(mVC).SetColor(ColorUtil.Hex("#b0683a")).Lathe(new[] { new Vector2(0, 0), new Vector2(0.18f * sc, 0), new Vector2(0.38f * sc, 0.35f * sc), new Vector2(0.4f * sc, 0.6f * sc),
                    new Vector2(0.22f * sc, 0.95f * sc), new Vector2(0.16f * sc, 1.05f * sc), new Vector2(0.2f * sc, 1.12f * sc), new Vector2(0.15f * sc, 1.12f * sc) }, 12, pp, 1, 1, false,
                    (u, v) => v > 0.45f && v < 0.52f ? ColorUtil.Hex("#2a6a8a") : ColorUtil.Hex("#b0683a"));
            }
            // Pichan g'aramlari
            MB(mVC).SetColor(ColorUtil.Hex("#c8a050")).Sphere(new Vector3(-14.5f, 0.6f, 4.8f), new Vector3(1.4f, 1.0f, 1.0f), 5, 10);
            MB(mVC).SetColor(ColorUtil.Hex("#b89040")).Sphere(new Vector3(15.5f, 0.5f, 5.2f), new Vector3(1.2f, 0.9f, 1.0f), 5, 10);
            // Arava g'ildiragi (devorga suyalgan)
            var wh = MB(mWood);
            wh.SetTransform(new Vector3(-5.2f, 0.95f, 5.85f), Quaternion.Euler(80, 0, 0));
            wh.Torus(Vector3.zero, 0.9f, 0.07f, 20, 5);
            for (int i = 0; i < 8; i++)
            {
                float a = i * Mathf.PI / 4;
                wh.Capsule(Vector3.zero, new Vector3(Mathf.Cos(a) * 0.88f, 0, Mathf.Sin(a) * 0.88f), 0.035f, 0.03f, 5);
            }
            wh.Cylinder(Vector3.zero, 0.15f, 0.15f, -0.1f, 0.1f, 8);
            wh.ResetTransform();
        }

        // ---------------- Tog'lar ----------------
        void BuildMountains()
        {
            var m = MB(mMountain);
            int n = 70;
            float z0 = 150;
            for (int layer = 0; layer < 2; layer++)
            {
                float z = z0 + layer * 40;
                float baseH = layer == 0 ? 18 : 34;
                for (int i = 0; i < n; i++)
                {
                    float x0 = -260 + i * 520f / n, x1 = -260 + (i + 1) * 520f / n;
                    float h0 = baseH + Noise.Fbm(x0 * 0.012f + layer * 5, layer, 4, 99) * (layer == 0 ? 40 : 70);
                    float h1 = baseH + Noise.Fbm(x1 * 0.012f + layer * 5, layer, 4, 99) * (layer == 0 ? 40 : 70);
                    Vector3 a = new Vector3(x0, -5, z), b = new Vector3(x0, h0, z + Mathf.Sin(x0) * 4), c = new Vector3(x1, h1, z + Mathf.Sin(x1) * 4), d = new Vector3(x1, -5, z);
                    m.AddQuad(a, b, c, d, new Vector2(x0 / 60f, 0), new Vector2(x1 / 60f, Mathf.Max(h0, h1) / 90f));
                }
            }
        }

        // ---------------- Bayroqlar ----------------
        void BuildFlags()
        {
            Color[] cs = { ColorUtil.Hex("#1a5fb4"), ColorUtil.Hex("#9e1b24") };
            for (int i = 0; i < 2; i++)
            {
                float x = i == 0 ? -4.6f : 4.6f;
                var pole = new MeshBuilder();
                pole.SetColor(ColorUtil.Hex("#5a3a20")).Cylinder(Vector3.zero, 0.07f, 0.05f, 0, 7.5f, 8);
                pole.SetColor(Pal.Gold).Sphere(new Vector3(0, 7.6f, 0), 0.14f, 5, 8);
                var pg = pole.Build("FlagPole", transform, Mat.ToonVC, true, Mat.Outline(0.01f));
                pg.transform.position = new Vector3(x, 0, 7.2f);
                var flag = new GameObject("Flag");
                flag.transform.SetParent(pg.transform, false);
                flag.transform.localPosition = new Vector3(0, 7.2f, 0);
                var mesh = new Mesh();
                int sx = 14, sy = 6;
                int n = (sx + 1) * (sy + 1);
                var verts = new Vector3[n * 2];
                var uvs = new Vector2[n * 2];
                var colors = new Color[n * 2];
                var tris = new List<int>();
                for (int y = 0; y <= sy; y++)
                    for (int xx = 0; xx <= sx; xx++)
                    {
                        int k = y * (sx + 1) + xx;
                        verts[k] = verts[k + n] = new Vector3(xx / (float)sx * 2.4f * (i == 0 ? 1 : -1), -y / (float)sy * 1.3f, 0);
                        uvs[k] = uvs[k + n] = new Vector2(xx / (float)sx, y / (float)sy);
                        bool stripe = y == 0 || y == sy || (y == sy / 2 && xx > 2 && xx < sx - 2 && xx % 3 == 0);
                        colors[k] = colors[k + n] = stripe ? Pal.Gold : cs[i];
                    }
                for (int y = 0; y < sy; y++)
                    for (int xx = 0; xx < sx; xx++)
                    {
                        int a = y * (sx + 1) + xx, b = a + 1, c = a + sx + 1, d = c + 1;
                        tris.AddRange(new[] { a, b, c, b, d, c });
                        tris.AddRange(new[] { a + n, c + n, b + n, b + n, c + n, d + n });
                    }
                mesh.vertices = verts; mesh.uv = uvs; mesh.colors = colors; mesh.SetTriangles(tris, 0);
                mesh.RecalculateNormals();
                mesh.MarkDynamic();
                flag.AddComponent<MeshFilter>().sharedMesh = mesh;
                flag.AddComponent<MeshRenderer>().sharedMaterial = Mat.Toon(Color.white, null, 0.2f);
                flags.Add(flag.transform);
                flagMeshes.Add(mesh);
                flagBase.Add((Vector3[])verts.Clone());
            }
        }

        // ---------------- Tomoshabinlar ----------------
        void BuildCrowd()
        {
            var r = new System.Random(77);
            var spots = new List<Vector3>();
            for (int i = 0; i < 9; i++) spots.Add(new Vector3(-12.5f + i * 1.0f + (float)r.NextDouble() * 0.4f, 0, 6.9f + (float)r.NextDouble() * 0.6f));
            for (int i = 0; i < 9; i++) spots.Add(new Vector3(4.2f + i * 1.0f + (float)r.NextDouble() * 0.4f, 0, 6.9f + (float)r.NextDouble() * 0.6f));
            spots.Add(new Vector3(-12f, 4.45f, 8.2f)); spots.Add(new Vector3(-10.4f, 4.45f, 8.6f)); spots.Add(new Vector3(12.4f, 4.05f, 8.8f));
            spots.Add(new Vector3(-14.5f, 0.4f, 7.6f)); spots.Add(new Vector3(-13.3f, 0.4f, 7.7f)); spots.Add(new Vector3(14f, 0.4f, 7.9f));
            int seed = 100;
            foreach (var s in spots)
            {
                if (Mathf.Abs(s.x) < 3.2f) continue;
                var v = Villager.Create(transform, s, seed++);
                crowd.Add(v);
            }
        }

        public void Cheer(float intensity)
        {
            foreach (var v in crowd) if (Random.value < 0.4f + intensity * 0.6f) v.Cheer(0.8f + Random.value * 1.4f * intensity);
        }

        // ---------------- Qushlar ----------------
        void BuildBirds()
        {
            for (int i = 0; i < 7; i++)
            {
                var mb = new MeshBuilder();
                mb.SetColor(ColorUtil.Hex("#2a2020"));
                mb.AddTriangle(new Vector3(0, 0, 0.15f), new Vector3(-0.5f, 0.05f, 0), new Vector3(0, 0, -0.1f));
                mb.AddTriangle(new Vector3(0, 0, 0.15f), new Vector3(0, 0, -0.1f), new Vector3(0.5f, 0.05f, 0));
                mb.AddTriangle(new Vector3(0, 0, 0.15f), new Vector3(0, 0, -0.1f), new Vector3(-0.5f, 0.05f, 0));
                mb.AddTriangle(new Vector3(0, 0, 0.15f), new Vector3(0.5f, 0.05f, 0), new Vector3(0, 0, -0.1f));
                var g = mb.Build("Bird", transform, Mat.Toon(Color.white, null, 0f), false);
                birds.Add(g.transform);
            }
        }

        // ---------------- Atmosfera ----------------
        void BuildAtmosphere()
        {
            var go = new GameObject("Motes");
            go.transform.SetParent(transform, false);
            go.transform.position = new Vector3(0, 2.5f, 3f);
            motes = go.AddComponent<ParticleSystem>();
            motes.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = motes.main;
            main.loop = true; main.startLifetime = 8f; main.startSpeed = 0.15f; main.startSize = preset == ArenaPreset.Night ? 0.08f : 0.05f;
            main.maxParticles = 300; main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.startColor = preset == ArenaPreset.Night ? new Color(1f, 0.85f, 0.4f, 0.9f) : new Color(1f, 0.9f, 0.7f, 0.5f);
            var em = motes.emission; em.rateOverTime = 25;
            var sh = motes.shape; sh.shapeType = ParticleSystemShapeType.Box; sh.scale = new Vector3(28, 4, 8);
            var noise = motes.noise; noise.enabled = true; noise.strength = 0.3f; noise.frequency = 0.3f;
            var col = motes.colorOverLifetime; col.enabled = true;
            var gr = new Gradient();
            gr.SetKeys(new[] { new GradientColorKey(Color.white, 0), new GradientColorKey(Color.white, 1) }, new[] { new GradientAlphaKey(0, 0), new GradientAlphaKey(1, 0.3f), new GradientAlphaKey(1, 0.7f), new GradientAlphaKey(0, 1) });
            col.color = gr;
            var rr = go.GetComponent<ParticleSystemRenderer>();
            rr.sharedMaterial = Mat.Additive(TextureFactory.SoftDot(), Color.white);
            motes.Play();

            // Tandir tutuni
            var smoke = new GameObject("TandirSmoke");
            smoke.transform.SetParent(transform, false);
            smoke.transform.position = new Vector3(-7.5f, 2.0f, 4.4f);
            var sp = smoke.AddComponent<ParticleSystem>();
            sp.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var sm = sp.main; sm.loop = true; sm.startLifetime = 4f; sm.startSpeed = 0.6f; sm.startSize = new ParticleSystem.MinMaxCurve(0.4f, 0.9f);
            sm.startColor = new Color(0.8f, 0.75f, 0.7f, 0.35f); sm.simulationSpace = ParticleSystemSimulationSpace.World;
            var se = sp.emission; se.rateOverTime = 5;
            var ss = sp.shape; ss.shapeType = ParticleSystemShapeType.Cone; ss.angle = 10; ss.radius = 0.1f; ss.rotation = new Vector3(-90, 0, 0);
            var sz = sp.sizeOverLifetime; sz.enabled = true; sz.size = new ParticleSystem.MinMaxCurve(1, AnimationCurve.Linear(0, 0.5f, 1, 2.5f));
            var sc = sp.colorOverLifetime; sc.enabled = true; sc.color = gr;
            var vel = sp.velocityOverLifetime; vel.enabled = true; vel.x = new ParticleSystem.MinMaxCurve(0.3f, 0.3f); vel.y = new ParticleSystem.MinMaxCurve(0f, 0f); vel.z = new ParticleSystem.MinMaxCurve(0f, 0f);
            smoke.GetComponent<ParticleSystemRenderer>().sharedMaterial = Mat.Alpha(TextureFactory.Smoke(), Color.white);
            sp.Play();
        }

        void BuildLightning()
        {
            var go = new GameObject("Lightning");
            go.transform.SetParent(transform, false);
            bolt = go.AddComponent<LineRenderer>();
            bolt.positionCount = 14;
            bolt.widthMultiplier = 0.25f;
            bolt.material = Mat.Additive(TextureFactory.SoftDot(), Color.white);
            bolt.startColor = bolt.endColor = new Color(1f, 0.9f, 0.6f, 0f);
            lightningLight = new GameObject("LightningLight").AddComponent<Light>();
            lightningLight.transform.SetParent(transform, false);
            lightningLight.type = LightType.Point;
            lightningLight.range = 25;
            lightningLight.intensity = 0;
            lightningLight.color = new Color(1f, 0.9f, 0.7f);
        }

        public void Lightning(Vector3 at)
        {
            lightningTime = Time.time;
            Vector3 p = at;
            for (int i = 0; i < 14; i++)
            {
                float t = i / 13f;
                Vector3 q = new Vector3(at.x + (i == 0 || i == 13 ? 0 : Random.Range(-0.5f, 0.5f)), Mathf.Lerp(18f, at.y, t), -0.5f);
                bolt.SetPosition(i, q);
            }
            lightningLight.transform.position = at + new Vector3(0, 3, -2);
            VFX.Burst(at + Vector3.up * 0.2f, new Color(1f, 0.85f, 0.5f), 1.2f);
            VFX.Dust(at, 3f);
        }

        public void SetDarkSky(bool on) { darkTarget = on ? 1 : 0; }

        void Update()
        {
            float dt = Time.unscaledDeltaTime;
            if (Mathf.Abs(darkT - darkTarget) > 0.001f)
            {
                darkT = Mathf.MoveTowards(darkT, darkTarget, dt * 1.2f);
                ApplySky(darkT);
            }
            // Chaqmoq
            float lt = Time.time - lightningTime;
            float li = lt < 0.5f ? (1 - lt / 0.5f) * (lt < 0.1f || (lt > 0.18f && lt < 0.26f) ? 1 : 0.4f) : 0;
            bolt.startColor = bolt.endColor = new Color(1f, 0.92f, 0.7f, li);
            bolt.widthMultiplier = 0.15f + li * 0.3f;
            lightningLight.intensity = li * 6f;

            // Bayroqlar to'lqini
            float time = Time.time;
            for (int i = 0; i < flagMeshes.Count; i++)
            {
                var b = flagBase[i];
                if (flagWork == null || flagWork.Length != b.Length) flagWork = new Vector3[b.Length];
                var v = flagWork;
                for (int k = 0; k < b.Length; k++)
                {
                    float x = Mathf.Abs(b[k].x);
                    float w = x / 2.4f;
                    v[k] = b[k] + new Vector3(0, -w * w * 0.25f, Mathf.Sin(time * 4.5f - x * 2.6f + i) * 0.22f * w + Mathf.Sin(time * 7.1f - x * 4f) * 0.05f * w);
                }
                flagMeshes[i].vertices = v;
                flagMeshes[i].RecalculateNormals();
            }
            // Fonarlar miltillashi
            for (int i = 0; i < lanterns.Count; i++)
            {
                float baseI = preset == ArenaPreset.Night ? 2.2f : 0.6f;
                lanterns[i].intensity = baseI * (0.9f + 0.1f * Mathf.PerlinNoise(time * 5f, i * 3.1f)) * (1 + darkT * 0.5f);
            }
            // Qushlar
            for (int i = 0; i < birds.Count; i++)
            {
                float a = time * (0.12f + i * 0.01f) + i * 0.9f;
                float rr = 14 + i * 3f;
                birds[i].position = new Vector3(Mathf.Cos(a) * rr, 18 + i * 1.6f + Mathf.Sin(time + i) * 0.6f, 40 + Mathf.Sin(a) * rr * 0.4f);
                birds[i].rotation = Quaternion.LookRotation(new Vector3(-Mathf.Sin(a), 0, Mathf.Cos(a) * 0.4f)) * Quaternion.Euler(0, 0, Mathf.Sin(time * 9 + i) * 25f);
                birds[i].localScale = new Vector3(1, 1 + Mathf.Sin(time * 9 + i) * 0.6f, 1);
            }
        }
    }

    /// <summary>Tomoshabin qishloqdosh: o'z animatsiyasi bilan (turish, olqishlash).</summary>
    public class Villager : MonoBehaviour
    {
        ProceduralAnimator anim;
        AnimClip idle, cheer;
        float cheerUntil;

        static AnimClip sharedIdleA, sharedIdleB, sharedCheer;

        public static Villager Create(Transform parent, Vector3 pos, int seed)
        {
            var go = new GameObject("Villager");
            go.transform.SetParent(parent, false);
            go.transform.position = pos;
            var rig = CharacterVisuals.BuildVillager(go.transform, seed);
            float yaw = 180 + (pos.x < 0 ? 18 : -18) + (seed % 5 - 2) * 6;
            rig.transform.localRotation = Quaternion.Euler(0, yaw, 0);
            var v = go.AddComponent<Villager>();
            v.anim = rig.gameObject.AddComponent<ProceduralAnimator>();
            v.anim.rig = rig;
            v.anim.breathAmount = 1.5f;
            v.anim.groundY = pos.y;
            BuildClips();
            v.idle = seed % 2 == 0 ? sharedIdleA : sharedIdleB;
            v.cheer = sharedCheer;
            v.anim.Play(v.idle, 0, (seed % 7) * 0.3f);
            return v;
        }

        static void BuildClips()
        {
            if (sharedIdleA != null) return;
            Pose stand = PoseLib.P().H(0, -0.01f, 0).S(Bone.Spine, 2).S(Bone.Head, -2)
                .S(Bone.UpperArmR, 8, 0, 6).S(Bone.ForeArmR, -10).S(Bone.UpperArmL, 8, 0, -6).S(Bone.ForeArmL, -10)
                .S(Bone.ThighL, -3, 0, -3).S(Bone.ThighR, 3, 0, 3);
            Pose folded = stand.Clone().S(Bone.UpperArmR, -20, 30, 10).S(Bone.ForeArmR, -100).S(Bone.UpperArmL, -20, -30, -10).S(Bone.ForeArmL, -100);
            Pose behind = stand.Clone().S(Bone.UpperArmR, 20, -10, 6).S(Bone.ForeArmR, -50).S(Bone.UpperArmL, 20, 10, -6).S(Bone.ForeArmL, -50).S(Bone.Spine, -3);
            sharedIdleA = new AnimClip("vIdleA", true).K(0, folded).K(1.6f, folded.Clone().A(Bone.Head, 4, 12, 0), Ease.InOutQuad).K(3.2f, folded, Ease.InOutQuad);
            sharedIdleB = new AnimClip("vIdleB", true).K(0, behind).K(1.8f, behind.Clone().A(Bone.Head, -2, -14, 0).A(Bone.Spine, 0, 6, 0), Ease.InOutQuad).K(3.6f, behind, Ease.InOutQuad);
            Pose up = stand.Clone().S(Bone.UpperArmR, -160, 0, 20).S(Bone.ForeArmR, -20).S(Bone.UpperArmL, -160, 0, -20).S(Bone.ForeArmL, -20).S(Bone.Head, -14).S(Bone.Chest, -6);
            Pose up2 = up.Clone().S(Bone.UpperArmR, -140, 0, 35).S(Bone.UpperArmL, -140, 0, -35).HA(0, 0.05f, 0);
            sharedCheer = new AnimClip("vCheer", true).K(0, up).K(0.25f, up2, Ease.InOutQuad).K(0.5f, up, Ease.InOutQuad);
        }

        public void Cheer(float seconds)
        {
            cheerUntil = Time.time + seconds;
            if (anim.Current != cheer) anim.Play(cheer, 0.15f, Random.value * 0.5f);
        }

        void Update()
        {
            if (anim.Current == cheer && Time.time > cheerUntil) anim.Play(idle, 0.3f);
            anim.Tick(Time.deltaTime);
        }
    }
}
