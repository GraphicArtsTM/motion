using System.Collections.Generic;
using UnityEngine;

namespace Shatranj.Visual
{
    public enum Ambience { Day, Sunset, Night }

    /// <summary>
    /// Мир вокруг доски: хонтахта на сюзане, курпачи, чайник «пахта», лепёшка-нон, гранаты;
    /// дворик с медресе (порталы-пештаки, бирюзовые купола), минареты, хауз, тополя; небо и свет.
    /// </summary>
    public class EnvironmentBuilder : MonoBehaviour
    {
        Light sun, iconLight;
        readonly List<Light> lanterns = new List<Light>();
        readonly List<GameObject> lanternGlows = new List<GameObject>();
        MeshFilter skyFilter;
        ParticleSystem stars;
        Material waterMat;

        public void Build()
        {
            var table = new GameObject("Table").transform;
            table.SetParent(transform, false);
            BuildTable(table);

            var world = new GameObject("World").transform;
            world.SetParent(transform, false);
            BuildCourtyard(world);
            BuildSky();
            BuildLights();
        }

        // ================================================================== Помощники

        static Transform Part(Transform p, Mesh mesh, Material m, Vector3 pos, Vector3 euler, Vector3 scale, bool shadows = true)
        {
            var go = new GameObject(mesh != null ? mesh.name : "part");
            go.transform.SetParent(p, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = Quaternion.Euler(euler);
            go.transform.localScale = scale;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var r = go.AddComponent<MeshRenderer>();
            r.sharedMaterial = m;
            if (!shadows) r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            return go.transform;
        }

        static Transform Box(Transform p, Material m, Vector3 c, Vector3 size, Vector3 euler = default(Vector3), bool shadows = true)
        {
            return Part(p, MeshBuilder.Cube, m, c, euler, size, shadows);
        }

        static Transform Turned(Transform p, string key, Material m, Vector3 pos, Vector2[] profile, int seg = 24, bool flat = false, float uRep = 1f, float scale = 1f)
        {
            var mesh = MeshBuilder.Cached("env." + key, () => MeshBuilder.Lathe(key, profile, seg, 0, 360, flat, uRep));
            return Part(p, mesh, m, pos, Vector3.zero, Vector3.one * scale);
        }

        static Material Tiled(Material src, Vector2 tiling)
        {
            var m = new Material(src) { mainTextureScale = tiling };
            return m;
        }

        // ================================================================== Хонтахта и чайный набор

        void BuildTable(Transform t)
        {
            const float top = -0.31f;
            Box(t, MaterialLib.TableWood, new Vector3(0, top - 0.14f, 0), new Vector3(12.6f, 0.28f, 12.6f));
            var apron = Tiled(MaterialLib.Frame, new Vector2(5f, 1f));
            for (int i = 0; i < 4; i++)
            {
                var b = Box(t, apron, Vector3.zero, new Vector3(11.6f, 0.5f, 0.25f));
                b.localRotation = Quaternion.Euler(0, 90f * i, 0);
                b.localPosition = b.localRotation * new Vector3(0, top - 0.52f, -5.75f);
            }
            var legProfile = new[]
            {
                new Vector2(0, 0), new Vector2(0.34f, 0), new Vector2(0.38f, 0.1f), new Vector2(0.3f, 0.25f),
                new Vector2(0.24f, 0.6f), new Vector2(0.34f, 0.8f), new Vector2(0.24f, 1.0f), new Vector2(0.3f, 1.3f),
                new Vector2(0.4f, 1.45f), new Vector2(0.4f, 1.6f), new Vector2(0, 1.6f)
            };
            for (int i = 0; i < 4; i++)
            {
                float x = (i % 2 == 0 ? 1 : -1) * 5.7f, z = (i < 2 ? 1 : -1) * 5.7f;
                Turned(t, "tableleg", MaterialLib.TableWood, new Vector3(x, top - 1.88f, z), legProfile, 16);
            }
            float floorY = top - 1.88f;
            FloorY = floorY;

            // сюзане на полу
            Part(t, MeshBuilder.QuadXZ, MaterialLib.Carpet, new Vector3(0, floorY + 0.01f, 0), Vector3.zero, new Vector3(22f, 1f, 22f), false);
            var floorCol = new GameObject("FloorCollider").AddComponent<BoxCollider>();
            floorCol.transform.SetParent(t, false);
            floorCol.center = new Vector3(0, floorY - 0.5f, 0);
            floorCol.size = new Vector3(60f, 1f, 60f);
            var tableCol = t.gameObject.AddComponent<BoxCollider>();
            tableCol.center = new Vector3(0, top - 0.14f, 0);
            tableCol.size = new Vector3(12.6f, 0.28f, 12.6f);

            // курпачи и подушки для двух игроков
            for (int s = -1; s <= 1; s += 2)
            {
                Box(t, MaterialLib.Kurpacha, new Vector3(0, floorY + 0.18f, s * 8.6f), new Vector3(11f, 0.34f, 2.6f));
                for (int k = -1; k <= 1; k++)
                    Part(t, MeshBuilder.Sphere, MaterialLib.Kurpacha, new Vector3(k * 3.4f, floorY + 0.65f, s * 9.6f), new Vector3(0, 0, 0), new Vector3(1.3f, 0.55f, 0.55f));
            }

            // чайник «пахта» и пиалы
            var tea = new GameObject("TeaSet").transform;
            tea.SetParent(t, false);
            tea.localPosition = new Vector3(5.45f, top, -5.45f);
            Turned(tea, "choynak", MaterialLib.Porcelain, Vector3.zero, new[]
            {
                new Vector2(0, 0), new Vector2(0.32f, 0), new Vector2(0.36f, 0.04f), new Vector2(0.52f, 0.28f),
                new Vector2(0.55f, 0.45f), new Vector2(0.48f, 0.66f), new Vector2(0.3f, 0.78f), new Vector2(0.28f, 0.82f), new Vector2(0, 0.82f)
            }, 28, false, 2f);
            Turned(tea, "choynak.lid", MaterialLib.Porcelain, new Vector3(0, 0.8f, 0), new[]
            {
                new Vector2(0, 0), new Vector2(0.29f, 0), new Vector2(0.26f, 0.06f), new Vector2(0.1f, 0.1f),
                new Vector2(0.06f, 0.16f), new Vector2(0.09f, 0.22f), new Vector2(0, 0.25f)
            }, 20);
            Part(tea, MeshBuilder.Tube("spout", new[]
            {
                new Vector3(0.4f, 0.3f, 0), new Vector3(0.62f, 0.42f, 0), new Vector3(0.74f, 0.62f, 0), new Vector3(0.8f, 0.78f, 0)
            }, new[] { 0.1f, 0.07f, 0.05f, 0.04f }, 10, false), MaterialLib.Porcelain, Vector3.zero, Vector3.zero, Vector3.one);
            Part(tea, MeshBuilder.Torus(0.22f, 0.035f, 20, 8), MaterialLib.Porcelain, new Vector3(-0.5f, 0.45f, 0), new Vector3(90, 0, 0), Vector3.one);
            tea.localRotation = Quaternion.Euler(0, 210f, 0);

            var bowlProfile = new[]
            {
                new Vector2(0, 0), new Vector2(0.14f, 0), new Vector2(0.15f, 0.04f), new Vector2(0.28f, 0.2f),
                new Vector2(0.3f, 0.27f), new Vector2(0.27f, 0.27f), new Vector2(0.13f, 0.08f), new Vector2(0, 0.07f)
            };
            Turned(t, "piyola", MaterialLib.Porcelain, new Vector3(4.6f, top, -5.75f), bowlProfile, 24, false, 2f);
            Turned(t, "piyola", MaterialLib.Porcelain, new Vector3(-5.4f, top, 5.2f), bowlProfile, 24, false, 2f);
            Turned(t, "piyola", MaterialLib.Porcelain, new Vector3(5.75f, top, -4.45f), bowlProfile, 24, false, 2f);

            // лепёшка-нон с узором штампа
            Turned(t, "non", MaterialLib.Bread, new Vector3(-5.45f, top, -5.45f), new[]
            {
                new Vector2(0, 0.04f), new Vector2(0.5f, 0), new Vector2(0.62f, 0.05f), new Vector2(0.66f, 0.14f),
                new Vector2(0.58f, 0.2f), new Vector2(0.44f, 0.16f), new Vector2(0.36f, 0.09f), new Vector2(0, 0.1f)
            }, 28);
            for (int i = 0; i < 8; i++)
            {
                float a = i * Mathf.PI / 4f;
                Part(t, MeshBuilder.Sphere, MaterialLib.White.WoodAlt, new Vector3(-5.45f + Mathf.Cos(a) * 0.18f, top + 0.1f, -5.45f + Mathf.Sin(a) * 0.18f), Vector3.zero, Vector3.one * 0.025f, false);
            }

            // ляган с гранатами (анор)
            Turned(t, "lagan", MaterialLib.Porcelain, new Vector3(5.45f, top, 5.45f), new[]
            {
                new Vector2(0, 0), new Vector2(0.3f, 0), new Vector2(0.62f, 0.08f), new Vector2(0.7f, 0.12f), new Vector2(0.66f, 0.12f), new Vector2(0.3f, 0.05f), new Vector2(0, 0.05f)
            }, 28, false, 3f);
            var pomegranate = MaterialLib.Std("anor", TextureFactory.Hex("#9E1622"), null, 0.65f, 0f);
            Vector3[] pp = { new Vector3(5.25f, 0, 5.3f), new Vector3(5.7f, 0, 5.5f), new Vector3(5.45f, 0.2f, 5.42f) };
            foreach (var p in pp)
            {
                var g = Part(t, MeshBuilder.Sphere, pomegranate, new Vector3(p.x, top + 0.24f + p.y, p.z), Vector3.zero, new Vector3(0.22f, 0.2f, 0.22f));
                Part(t, MeshBuilder.Cylinder, pomegranate, g.localPosition + new Vector3(0, 0.17f, 0), Vector3.zero, new Vector3(0.06f, 0.07f, 0.06f));
            }
        }

        public static float FloorY = -2.2f;

        // ================================================================== Дворик Регистана

        void BuildCourtyard(Transform w)
        {
            float gy = FloorY - 0.02f;
            var paving = Tiled(MaterialLib.Paving, new Vector2(40, 40));
            Part(w, MeshBuilder.QuadXZ, paving, new Vector3(0, gy, 0), Vector3.zero, new Vector3(260f, 1f, 260f), false);

            Madrasah(w, new Vector3(0, gy, 36f), 180f, 1.0f);
            Madrasah(w, new Vector3(36f, gy, 2f), 270f, 0.9f);
            Madrasah(w, new Vector3(-36f, gy, 2f), 90f, 0.9f);
            Mausoleum(w, new Vector3(0, gy, -40f));

            Minaret(w, new Vector3(-21f, gy, 27f), 1f);
            Minaret(w, new Vector3(21f, gy, 27f), 1f);
            Minaret(w, new Vector3(-24f, gy, -26f), 0.85f);
            Minaret(w, new Vector3(24f, gy, -26f), 0.85f);

            // хауз (пруд) с бирюзовой облицовкой
            var pool = new GameObject("Hauz").transform;
            pool.SetParent(w, false);
            pool.localPosition = new Vector3(15f, gy, -9f);
            for (int i = 0; i < 4; i++)
            {
                var b = Box(pool, MaterialLib.TileTurquoise, Vector3.zero, new Vector3(i % 2 == 0 ? 9f : 6.6f, 0.5f, 0.6f));
                b.localRotation = Quaternion.Euler(0, 90f * i, 0);
                b.localPosition = b.localRotation * new Vector3(0, 0.25f, i % 2 == 0 ? -3.0f : -4.2f);
            }
            waterMat = MaterialLib.Std("water", new Color(0.12f, 0.32f, 0.42f), null, 0.96f, 0.3f);
            Part(pool, MeshBuilder.QuadXZ, waterMat, new Vector3(0, 0.2f, 0), Vector3.zero, new Vector3(8f, 1f, 5.6f), false);

            // тополя и чинары
            var rnd = new System.Random(7);
            for (int i = 0; i < 22; i++)
            {
                float a = (float)(rnd.NextDouble() * Mathf.PI * 2);
                float r = 17f + (float)rnd.NextDouble() * 8f;
                Vector3 p = new Vector3(Mathf.Cos(a) * r, gy, Mathf.Sin(a) * r);
                if (Vector3.Distance(p, pool.localPosition) < 7f) continue;
                if (rnd.NextDouble() < 0.6) Poplar(w, p, 0.8f + (float)rnd.NextDouble() * 0.5f);
                else PlaneTree(w, p, 0.8f + (float)rnd.NextDouble() * 0.4f);
            }
        }

        void Madrasah(Transform w, Vector3 pos, float yaw, float s)
        {
            var m = new GameObject("Madrasah").transform;
            m.SetParent(w, false);
            m.localPosition = pos;
            m.localRotation = Quaternion.Euler(0, yaw, 0);
            m.localScale = Vector3.one * s;

            var brick = Tiled(MaterialLib.Brick, new Vector2(8, 4));
            Box(m, brick, new Vector3(0, 6f, 0), new Vector3(30f, 12f, 5f));
            Box(m, MaterialLib.TileBlue, new Vector3(0, 11.4f, 2.55f), new Vector3(30f, 1.2f, 0.12f));

            // ярусы ниш-худжр
            for (int side = -1; side <= 1; side += 2)
                for (int k = 0; k < 3; k++)
                    for (int lvl = 0; lvl < 2; lvl++)
                    {
                        float x = side * (7.2f + k * 2.6f);
                        float y = 2.4f + lvl * 4.6f;
                        Box(m, MaterialLib.NicheDark, new Vector3(x, y, 2.52f), new Vector3(1.8f, 3.0f, 0.1f));
                        Box(m, MaterialLib.NicheDark, new Vector3(x, y + 1.5f, 2.52f), new Vector3(1.27f, 1.27f, 0.1f), new Vector3(0, 0, 45));
                    }

            // портал-пештак с остроконечной аркой
            Box(m, MaterialLib.TileBlue, new Vector3(0, 9f, 3.2f), new Vector3(11f, 18f, 2.6f));
            Box(m, MaterialLib.NicheDark, new Vector3(0, 5.6f, 4.47f), new Vector3(6.4f, 11.2f, 0.2f));
            Box(m, MaterialLib.NicheDark, new Vector3(0, 11.2f, 4.47f), new Vector3(4.5f, 4.5f, 0.2f), new Vector3(0, 0, 45));
            var frameMat = Tiled(MaterialLib.Frame, new Vector2(1f, 8f));
            Box(m, frameMat, new Vector3(-4.6f, 8.2f, 4.55f), new Vector3(0.7f, 16.4f, 0.1f));
            Box(m, frameMat, new Vector3(4.6f, 8.2f, 4.55f), new Vector3(0.7f, 16.4f, 0.1f));
            Box(m, Tiled(MaterialLib.Frame, new Vector2(4f, 1f)), new Vector3(0, 16.6f, 4.55f), new Vector3(9.9f, 0.7f, 0.1f));
            Box(m, MaterialLib.Plaster, new Vector3(0, 0.4f, 4.6f), new Vector3(4f, 0.8f, 0.4f));

            // купол на барабане
            Turned(m, "drum", brick, new Vector3(0, 12f, -1f), new[] { new Vector2(0, 0), new Vector2(4.2f, 0), new Vector2(4.2f, 0), new Vector2(4.2f, 3f), new Vector2(4.2f, 3f), new Vector2(0, 3f) }, 24);
            Part(m, MeshBuilder.Torus(4.25f, 0.35f, 32, 8), MaterialLib.TileBlue, new Vector3(0, 14.6f, -1f), Vector3.zero, Vector3.one);
            Turned(m, "dome", MaterialLib.Dome, new Vector3(0, 15f, -1f), DomeProfile(4.6f, 6.6f), 32, true, 8f);
            Part(m, MeshBuilder.Sphere, MaterialLib.White.Metal, new Vector3(0, 21.8f, -1f), Vector3.zero, Vector3.one * 0.35f);

            // угловые башенки-гульдаста
            for (int side = -1; side <= 1; side += 2)
            {
                Turned(m, "guldasta", brick, new Vector3(side * 15f, 0, 2.2f), new[]
                {
                    new Vector2(0, 0), new Vector2(1.3f, 0), new Vector2(1.15f, 13f), new Vector2(1.45f, 13.4f), new Vector2(1.45f, 14f), new Vector2(0, 14f)
                }, 16);
                Turned(m, "guldasta.top", MaterialLib.Dome, new Vector3(side * 15f, 14f, 2.2f), DomeProfile(1.1f, 1.8f), 12, true, 2f);
                Box(m, MaterialLib.TileTurquoise, new Vector3(side * 15f, 8f, 2.2f), new Vector3(2.5f, 1f, 2.5f));
            }
        }

        static Vector2[] DomeProfile(float r, float h)
        {
            // «дыневидный» купол Гур-Эмира: выпуклый, с выраженным плечом
            return new[]
            {
                new Vector2(r * 0.88f, 0), new Vector2(r, h * 0.15f), new Vector2(r * 1.04f, h * 0.35f), new Vector2(r * 0.95f, h * 0.55f),
                new Vector2(r * 0.72f, h * 0.75f), new Vector2(r * 0.42f, h * 0.9f), new Vector2(r * 0.12f, h * 0.98f), new Vector2(0, h)
            };
        }

        void Mausoleum(Transform w, Vector3 pos)
        {
            var m = new GameObject("Mausoleum").transform;
            m.SetParent(w, false);
            m.localPosition = pos;
            var brick = Tiled(MaterialLib.Brick, new Vector2(6, 3));
            Turned(m, "octa", brick, Vector3.zero, new[] { new Vector2(0, 0), new Vector2(9f, 0), new Vector2(9f, 0), new Vector2(9f, 10f), new Vector2(9f, 10f), new Vector2(0, 10f) }, 8);
            Turned(m, "mdrum", MaterialLib.TileBlue, new Vector3(0, 10f, 0), new[] { new Vector2(0, 0), new Vector2(6.2f, 0), new Vector2(6.2f, 0), new Vector2(6.2f, 5f), new Vector2(6.2f, 5f), new Vector2(0, 5f) }, 32, false, 6f);
            Turned(m, "mdome", MaterialLib.Dome, new Vector3(0, 15f, 0), DomeProfile(7.2f, 10f), 40, true, 10f);
            Part(m, MeshBuilder.Sphere, MaterialLib.White.Metal, new Vector3(0, 25.6f, 0), Vector3.zero, Vector3.one * 0.5f);
            Box(m, MaterialLib.TileBlue, new Vector3(0, 7f, 8.6f), new Vector3(9f, 14f, 1.6f));
            Box(m, MaterialLib.NicheDark, new Vector3(0, 4.8f, 9.45f), new Vector3(5f, 9.6f, 0.2f));
            Box(m, MaterialLib.NicheDark, new Vector3(0, 9.6f, 9.45f), new Vector3(3.5f, 3.5f, 0.2f), new Vector3(0, 0, 45));
        }

        void Minaret(Transform w, Vector3 pos, float s)
        {
            var m = new GameObject("Minaret").transform;
            m.SetParent(w, false);
            m.localPosition = pos;
            m.localScale = Vector3.one * s;
            var brick = Tiled(MaterialLib.Brick, new Vector2(3, 10));
            Turned(m, "minaret", brick, Vector3.zero, new[]
            {
                new Vector2(0, 0), new Vector2(1.6f, 0), new Vector2(1.55f, 1f), new Vector2(1.1f, 24f), new Vector2(0, 24f)
            }, 20, false, 3f);
            for (int i = 0; i < 3; i++)
            {
                float y = 6f + i * 6.5f;
                float r = Mathf.Lerp(1.52f, 1.12f, y / 24f) + 0.04f;
                Turned(m, "mband" + i, MaterialLib.TileTurquoise, new Vector3(0, y, 0), new[]
                {
                    new Vector2(r - 0.02f, 0), new Vector2(r, 0.05f), new Vector2(r, 1.1f), new Vector2(r - 0.02f, 1.15f)
                }, 20, false, 4f);
            }
            Turned(m, "lantern", MaterialLib.TileBlue, new Vector3(0, 24f, 0), new[]
            {
                new Vector2(0, 0), new Vector2(1.1f, 0), new Vector2(1.7f, 0.6f), new Vector2(1.7f, 1.0f), new Vector2(1.25f, 1.1f),
                new Vector2(1.25f, 2.6f), new Vector2(1.5f, 2.8f), new Vector2(0, 2.8f)
            }, 20);
            Turned(m, "mtop", MaterialLib.Dome, new Vector3(0, 26.8f, 0), DomeProfile(1.25f, 1.8f), 16, true, 2f);
        }

        void Poplar(Transform w, Vector3 p, float s)
        {
            Part(w, MeshBuilder.Cylinder, MaterialLib.Trunk, p, Vector3.zero, new Vector3(0.18f * s, 2.5f * s, 0.18f * s));
            Part(w, MeshBuilder.Sphere, MaterialLib.Foliage, p + new Vector3(0, 6.2f * s, 0), Vector3.zero, new Vector3(1.3f * s, 4.6f * s, 1.3f * s));
        }

        void PlaneTree(Transform w, Vector3 p, float s)
        {
            Part(w, MeshBuilder.Cylinder, MaterialLib.Trunk, p, Vector3.zero, new Vector3(0.35f * s, 4f * s, 0.35f * s));
            Part(w, MeshBuilder.Sphere, MaterialLib.Foliage, p + new Vector3(0, 5.6f * s, 0), Vector3.zero, new Vector3(3.2f * s, 2.4f * s, 3.2f * s));
            Part(w, MeshBuilder.Sphere, MaterialLib.Foliage, p + new Vector3(1.6f * s, 4.8f * s, 0.8f * s), Vector3.zero, new Vector3(2.2f * s, 1.8f * s, 2.2f * s));
            Part(w, MeshBuilder.Sphere, MaterialLib.Foliage, p + new Vector3(-1.4f * s, 5f * s, -0.9f * s), Vector3.zero, new Vector3(2.2f * s, 1.8f * s, 2.2f * s));
        }

        // ================================================================== Небо и свет

        void BuildSky()
        {
            var go = new GameObject("Sky");
            go.transform.SetParent(transform, false);
            skyFilter = go.AddComponent<MeshFilter>();
            var r = go.AddComponent<MeshRenderer>();
            r.sharedMaterial = MaterialLib.SkyMat;
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;

            var sgo = new GameObject("Stars");
            sgo.transform.SetParent(transform, false);
            stars = sgo.AddComponent<ParticleSystem>();
            stars.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = stars.main;
            main.loop = true;
            main.startLifetime = 1e6f;
            main.startSpeed = 0f;
            main.maxParticles = 600;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            var em = stars.emission;
            em.rateOverTime = 0f;
            var sh = stars.shape;
            sh.enabled = false;
            var pr = sgo.GetComponent<ParticleSystemRenderer>();
            pr.sharedMaterial = MaterialLib.Unlit(Color.white, TextureFactory.Glow());
            pr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            pr.maxParticleSize = 0.02f;
            stars.Play();
            var rnd = new System.Random(3);
            for (int i = 0; i < 500; i++)
            {
                Vector3 d = new Vector3((float)rnd.NextDouble() * 2 - 1, (float)rnd.NextDouble() * 0.9f + 0.08f, (float)rnd.NextDouble() * 2 - 1).normalized;
                var ep = new ParticleSystem.EmitParams
                {
                    position = d * 140f,
                    startSize = 0.4f + (float)rnd.NextDouble() * 0.9f,
                    startColor = new Color(1f, 1f, 0.92f, 0.5f + (float)rnd.NextDouble() * 0.5f),
                    startLifetime = 1e6f
                };
                stars.Emit(ep, 1);
            }
        }

        void BuildLights()
        {
            var sgo = new GameObject("Sun");
            sgo.transform.SetParent(transform, false);
            sun = sgo.AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = 0.75f;
            sun.shadowBias = 0.03f;
            sun.shadowNormalBias = 0.25f;
            sun.cullingMask = ~(1 << IconRenderer.Layer);

            var igo = new GameObject("IconLight");
            igo.transform.SetParent(transform, false);
            iconLight = igo.AddComponent<Light>();
            iconLight.type = LightType.Directional;
            iconLight.intensity = 1.15f;
            iconLight.color = new Color(1f, 0.95f, 0.88f);
            iconLight.transform.rotation = Quaternion.Euler(35f, 150f, 0);
            iconLight.cullingMask = 1 << IconRenderer.Layer;
            iconLight.shadows = LightShadows.None;

            Vector3[] lp = { new Vector3(-5.6f, 0.35f, 0f), new Vector3(5.6f, 0.35f, 0f) };
            var glowMat = MaterialLib.Unlit(new Color(1f, 0.75f, 0.35f, 0.9f), TextureFactory.Glow());
            foreach (var p in lp)
            {
                var lgo = new GameObject("Lantern");
                lgo.transform.SetParent(transform, false);
                lgo.transform.localPosition = p;
                var l = lgo.AddComponent<Light>();
                l.type = LightType.Point;
                l.range = 14f;
                l.intensity = 1.5f;
                l.color = new Color(1f, 0.7f, 0.38f);
                l.shadows = LightShadows.None;
                l.cullingMask = ~(1 << IconRenderer.Layer);
                lanterns.Add(l);

                // сам фонарь-«чироқ»: латунный корпус и тёплое свечение
                var body = new GameObject("LanternBody").transform;
                body.SetParent(transform, false);
                body.localPosition = new Vector3(p.x, -0.31f, p.z);
                Turned(body, "chiroq", MaterialLib.Black.Metal, Vector3.zero, new[]
                {
                    new Vector2(0, 0), new Vector2(0.25f, 0), new Vector2(0.2f, 0.1f), new Vector2(0.12f, 0.15f), new Vector2(0.16f, 0.5f),
                    new Vector2(0.22f, 0.55f), new Vector2(0.1f, 0.75f), new Vector2(0.03f, 0.9f), new Vector2(0, 0.95f)
                }, 12, true);
                var glow = Part(body, MeshBuilder.QuadXZ, glowMat, new Vector3(0, 0.4f, 0), new Vector3(-90, 0, 0), new Vector3(1.4f, 1f, 1.4f), false);
                glow.gameObject.AddComponent<Billboard>();
                lanternGlows.Add(glow.gameObject);
            }
        }

        public void Apply(Ambience a, int quality)
        {
            Color horizon, zenith, ground, sunColor, ambSky, ambEq, ambGround;
            float sunI;
            Vector3 sunRot;
            bool night = a == Ambience.Night;
            switch (a)
            {
                case Ambience.Day:
                    horizon = new Color(0.8f, 0.87f, 0.95f); zenith = new Color(0.22f, 0.48f, 0.85f); ground = new Color(0.75f, 0.68f, 0.55f);
                    sunColor = new Color(1f, 0.96f, 0.88f); sunI = 1.15f; sunRot = new Vector3(52f, -35f, 0);
                    ambSky = new Color(0.55f, 0.66f, 0.82f); ambEq = new Color(0.58f, 0.56f, 0.5f); ambGround = new Color(0.36f, 0.3f, 0.24f);
                    break;
                case Ambience.Sunset:
                    horizon = new Color(1f, 0.6f, 0.36f); zenith = new Color(0.2f, 0.22f, 0.48f); ground = new Color(0.55f, 0.36f, 0.26f);
                    sunColor = new Color(1f, 0.66f, 0.4f); sunI = 1.1f; sunRot = new Vector3(20f, -55f, 0);
                    ambSky = new Color(0.5f, 0.42f, 0.55f); ambEq = new Color(0.62f, 0.44f, 0.34f); ambGround = new Color(0.26f, 0.18f, 0.15f);
                    break;
                default:
                    horizon = new Color(0.09f, 0.13f, 0.26f); zenith = new Color(0.01f, 0.02f, 0.07f); ground = new Color(0.05f, 0.05f, 0.08f);
                    sunColor = new Color(0.55f, 0.66f, 1f); sunI = 0.42f; sunRot = new Vector3(48f, 30f, 0);
                    ambSky = new Color(0.14f, 0.18f, 0.32f); ambEq = new Color(0.12f, 0.12f, 0.18f); ambGround = new Color(0.06f, 0.05f, 0.06f);
                    break;
            }
            sun.color = sunColor;
            sun.intensity = sunI;
            sun.transform.rotation = Quaternion.Euler(sunRot);
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = ambSky;
            RenderSettings.ambientEquatorColor = ambEq;
            RenderSettings.ambientGroundColor = ambGround;
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Linear;
            RenderSettings.fogColor = Color.Lerp(horizon, ground, 0.3f);
            RenderSettings.fogStartDistance = 45f;
            RenderSettings.fogEndDistance = 170f;
            RenderSettings.skybox = null;

            skyFilter.sharedMesh = MeshBuilder.SkyDome(horizon, zenith, ground, 160f);
            var cam = Camera.main;
            if (cam != null) cam.backgroundColor = horizon;
            if (stars != null) stars.GetComponent<ParticleSystemRenderer>().enabled = night;
            foreach (var l in lanterns) l.enabled = night || a == Ambience.Sunset;
            foreach (var l in lanterns) l.intensity = night ? 1.7f : 0.7f;
            foreach (var g in lanternGlows) g.SetActive(night || a == Ambience.Sunset);
            if (waterMat != null) waterMat.color = night ? new Color(0.05f, 0.1f, 0.18f) : new Color(0.12f, 0.32f, 0.42f);

            ApplyQuality(quality);
        }

        public void ApplyQuality(int q)
        {
            switch (q)
            {
                case 0:
                    sun.shadows = LightShadows.None;
                    QualitySettings.antiAliasing = 0;
                    QualitySettings.pixelLightCount = 0;
                    break;
                case 1:
                    sun.shadows = LightShadows.Hard;
                    QualitySettings.shadowResolution = ShadowResolution.Medium;
                    QualitySettings.antiAliasing = 2;
                    QualitySettings.pixelLightCount = 1;
                    break;
                default:
                    sun.shadows = LightShadows.Soft;
                    QualitySettings.shadowResolution = ShadowResolution.High;
                    QualitySettings.antiAliasing = 4;
                    QualitySettings.pixelLightCount = 2;
                    break;
            }
            QualitySettings.shadows = q == 0 ? ShadowQuality.Disable : ShadowQuality.All;
            QualitySettings.shadowDistance = 34f;
            QualitySettings.shadowCascades = 1;
        }
    }

    /// <summary>Поворачивает объект лицом к камере (свечение фонарей).</summary>
    public class Billboard : MonoBehaviour
    {
        void LateUpdate()
        {
            var cam = Camera.main;
            if (cam == null) return;
            transform.rotation = Quaternion.LookRotation(transform.position - cam.transform.position) * Quaternion.Euler(-90, 0, 0);
        }
    }
}
