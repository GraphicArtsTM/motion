using System.Collections.Generic;
using UnityEngine;

namespace Shatranj.Visual
{
    /// <summary>
    /// Мехмонхона — парадный зал узбекского дома, где стоит доска:
    ///  • стены: внизу резные деревянные панели (хивинская резьба), выше — резной ганч,
    ///    ниши-токча с риштанскими ляганами и кувшинами, ступенчатый карниз;
    ///  • тахмон со стопками курпачей, хивинская двустворчатая дверь, окна с решётками-панжара;
    ///  • резные колонны-устун с «косой» у основания и кронштейнами, расписной потолок с балками;
    ///  • бухарский гилам, сундук-сандиқ с одеялами, хумы, дутар и дойра на стене;
    ///  • хонтахта с резной каймой, чайник «пахта», лепёшка, ляган с гранатами и виноградом.
    /// Только геометрия; свет, коллайдеры и эффекты добавляет EnvironmentBuilder.
    /// </summary>
    public static class InteriorBuilder
    {
        public const float TableTop = -0.62f;
        public const float TableThick = 0.28f;
        public const float LegHeight = 1.6f;
        public const float FloorY = TableTop - TableThick - LegHeight;
        public const float Half = 21f;
        public const float Height = 26f;
        public const float CeilingY = FloorY + Height;

        public struct Window { public Vector3 Center; public Vector3 Inward; public float Width, Height; }

        public static readonly List<Window> Windows = new List<Window>();
        public static readonly List<Vector3> HangingLanterns = new List<Vector3>();
        public static readonly List<Vector3> TableLanterns = new List<Vector3>();
        public static Material WindowGlow;

        // ================================================================== Помощники

        static Transform Node(Transform p, string name, Vector3 pos, Vector3 euler = default(Vector3), Vector3? scale = null)
        {
            var t = new GameObject(name).transform;
            t.SetParent(p, false);
            t.localPosition = pos;
            t.localRotation = Quaternion.Euler(euler);
            t.localScale = scale ?? Vector3.one;
            return t;
        }

        static Transform Part(Transform p, Mesh mesh, Material m, Vector3 pos, Vector3 euler, Vector3 scale)
        {
            var go = new GameObject(mesh.name);
            go.transform.SetParent(p, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = Quaternion.Euler(euler);
            go.transform.localScale = scale;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            go.AddComponent<MeshRenderer>().sharedMaterial = m;
            return go.transform;
        }

        static Transform Box(Transform p, Material m, Vector3 c, Vector3 size, Vector3 euler = default(Vector3))
        {
            return Part(p, MeshBuilder.Cube, m, c, euler, size);
        }

        static Transform Ball(Transform p, Material m, Vector3 c, Vector3 radii)
        {
            return Part(p, MeshBuilder.Sphere, m, c, Vector3.zero, radii);
        }

        static Transform Turned(Transform p, string key, Material m, Vector3 pos, Vector2[] profile, int seg = 24, bool flat = false, float uRep = 1f, float scale = 1f)
        {
            var mesh = MeshBuilder.Cached("int." + key, () => MeshBuilder.Lathe(key, profile, seg, 0, 360, flat, uRep));
            return Part(p, mesh, m, pos, Vector3.zero, Vector3.one * scale);
        }

        static Transform Ring(Transform p, Material m, Vector3 c, float R, float r, Vector3 euler = default(Vector3))
        {
            return Part(p, MeshBuilder.Torus(R, r, 28, 8), m, c, euler, Vector3.one);
        }

        /// <summary>Точки равносторонней стрельчатой арки шириной w (начало — в точке опоры слева).</summary>
        static Vector3[] ArchPoints(float w, int steps)
        {
            var pts = new List<Vector3>();
            float r = w;
            for (int i = 0; i <= steps; i++)
            {
                float a = Mathf.PI - (Mathf.PI / 3f) * i / steps;
                pts.Add(new Vector3(w * 0.5f + Mathf.Cos(a) * r, Mathf.Sin(a) * r, 0));
            }
            for (int i = steps - 1; i >= 0; i--)
            {
                float a = Mathf.PI - (Mathf.PI / 3f) * i / steps;
                pts.Add(new Vector3(-(w * 0.5f + Mathf.Cos(a) * r), Mathf.Sin(a) * r, 0));
            }
            return pts.ToArray();
        }

        /// <summary>Резной обод арки (трубка по стрельчатой кривой).</summary>
        static Mesh ArchTube(float w, float radius)
        {
            var pts = ArchPoints(w, 10);
            var radii = new float[pts.Length];
            for (int i = 0; i < radii.Length; i++) radii[i] = radius;
            return MeshBuilder.Tube("arch." + w + "." + radius, pts, radii, 8, false);
        }

        /// <summary>Плоская заливка тимпана арки (обращена в зал, −Z).</summary>
        static Mesh ArchFill(float w)
        {
            return MeshBuilder.Cached("archfill." + w, () =>
            {
                var pts = ArchPoints(w, 10);
                var v = new List<Vector3> { new Vector3(0, w * 0.3f, 0) };
                var uv = new List<Vector2> { new Vector2(0.5f, 0.3f) };
                var nr = new List<Vector3> { Vector3.back };
                foreach (var p in pts) { v.Add(p); uv.Add(new Vector2(p.x / w + 0.5f, p.y / w)); nr.Add(Vector3.back); }
                var t = new List<int>();
                for (int i = 1; i < v.Count - 1; i++) { t.Add(0); t.Add(i); t.Add(i + 1); }
                t.Add(0); t.Add(v.Count - 1); t.Add(1);
                var m = new Mesh();
                m.SetVertices(v); m.SetNormals(nr); m.SetUVs(0, uv); m.SetTriangles(t, 0);
                MeshBuilder.FixWinding(m);
                m.RecalculateBounds(); m.RecalculateTangents();
                return m;
            });
        }

        // ================================================================== Хонтахта и дастархан

        public static void BuildTable(Transform t)
        {
            TableLanterns.Clear();
            Box(t, MaterialLib.TableWood, new Vector3(0, TableTop - TableThick * 0.5f, 0), new Vector3(12.6f, TableThick, 12.6f));
            var rim = Node(t, "Rim", new Vector3(0, TableTop, 0));
            Part(rim, MeshBuilder.FrameExtrude("tablerim.top", new[]
            {
                new Vector2(0f, 0f), new Vector2(0.015f, 0.05f), new Vector2(0.33f, 0.05f), new Vector2(0.345f, 0f)
            }, 5.95f, 1.25f, 0.33f), MaterialLib.FrameCarved, Vector3.zero, Vector3.zero, Vector3.one);
            Part(rim, MeshBuilder.FrameExtrude("tablerim.side", new[]
            {
                new Vector2(0.345f, 0f), new Vector2(0.37f, -0.03f), new Vector2(0.37f, -TableThick - 0.02f), new Vector2(0.3f, -TableThick - 0.02f)
            }, 5.95f, 0.3f, 0.3f), MaterialLib.FrameSide, Vector3.zero, Vector3.zero, Vector3.one);

            for (int i = 0; i < 4; i++)
            {
                var b = Box(t, MaterialLib.Tiled(MaterialLib.FrameSide, new Vector2(18f, 1f)), Vector3.zero, new Vector3(11.4f, 0.55f, 0.22f));
                b.localRotation = Quaternion.Euler(0, 90f * i, 0);
                b.localPosition = b.localRotation * new Vector3(0, TableTop - TableThick - 0.27f, -5.75f);
            }
            var legProfile = new[]
            {
                new Vector2(0, 0), new Vector2(0.34f, 0), new Vector2(0.4f, 0.1f), new Vector2(0.3f, 0.25f),
                new Vector2(0.24f, 0.55f), new Vector2(0.36f, 0.78f), new Vector2(0.24f, 1.0f), new Vector2(0.3f, 1.3f),
                new Vector2(0.42f, 1.45f), new Vector2(0.42f, LegHeight), new Vector2(0, LegHeight)
            };
            for (int i = 0; i < 4; i++)
            {
                float x = (i % 2 == 0 ? 1 : -1) * 5.7f, z = (i < 2 ? 1 : -1) * 5.7f;
                Turned(t, "tableleg", MaterialLib.TableWood, new Vector3(x, FloorY, z), legProfile, 18);
                Ring(t, MaterialLib.Inlay, new Vector3(x, FloorY + 0.78f, z), 0.36f, 0.03f);
                Ring(t, MaterialLib.Inlay, new Vector3(x, FloorY + 1.45f, z), 0.42f, 0.03f);
            }

            // чайник «пахта» и пиалы
            var tea = Node(t, "TeaSet", new Vector3(5.45f, TableTop, -5.45f), new Vector3(0, 210f, 0));
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
            Ring(tea, MaterialLib.Inlay, new Vector3(0, 0.81f, 0), 0.29f, 0.015f);
            Part(tea, MeshBuilder.Tube("spout", new[]
            {
                new Vector3(0.4f, 0.3f, 0), new Vector3(0.62f, 0.42f, 0), new Vector3(0.74f, 0.62f, 0), new Vector3(0.8f, 0.78f, 0)
            }, new[] { 0.1f, 0.07f, 0.05f, 0.04f }, 10, false), MaterialLib.Porcelain, Vector3.zero, Vector3.zero, Vector3.one);
            Ring(tea, MaterialLib.Porcelain, new Vector3(-0.5f, 0.45f, 0), 0.22f, 0.035f, new Vector3(90, 0, 0));

            var bowl = new[]
            {
                new Vector2(0, 0), new Vector2(0.14f, 0), new Vector2(0.15f, 0.04f), new Vector2(0.28f, 0.2f),
                new Vector2(0.3f, 0.27f), new Vector2(0.27f, 0.27f), new Vector2(0.13f, 0.08f), new Vector2(0, 0.07f)
            };
            Turned(t, "piyola", MaterialLib.Porcelain, new Vector3(4.6f, TableTop, -5.8f), bowl, 24, false, 2f);
            Turned(t, "piyola", MaterialLib.Porcelain, new Vector3(5.8f, TableTop, -4.45f), bowl, 24, false, 2f);
            Turned(t, "piyola", MaterialLib.Porcelain, new Vector3(-4.6f, TableTop, 5.8f), bowl, 24, false, 2f);

            // лепёшка-нон со штампом
            Turned(t, "non", MaterialLib.Bread, new Vector3(-5.45f, TableTop, -5.45f), new[]
            {
                new Vector2(0, 0.04f), new Vector2(0.5f, 0), new Vector2(0.62f, 0.05f), new Vector2(0.66f, 0.14f),
                new Vector2(0.58f, 0.2f), new Vector2(0.44f, 0.16f), new Vector2(0.36f, 0.09f), new Vector2(0, 0.1f)
            }, 28);
            for (int i = 0; i < 12; i++)
            {
                float a = i * Mathf.PI / 6f;
                float r = i % 2 == 0 ? 0.2f : 0.12f;
                Ball(t, MaterialLib.White.WoodAlt, new Vector3(-5.45f + Mathf.Cos(a) * r, TableTop + 0.1f, -5.45f + Mathf.Sin(a) * r), Vector3.one * 0.022f);
            }

            // риштанский ляган с гранатами и виноградом
            Turned(t, "lagan.base", MaterialLib.Glaze, new Vector3(5.45f, TableTop, 5.45f), new[]
            {
                new Vector2(0, 0), new Vector2(0.3f, 0), new Vector2(0.62f, 0.08f), new Vector2(0.7f, 0.12f), new Vector2(0.66f, 0.12f), new Vector2(0, 0.05f)
            }, 28);
            Part(t, MeshBuilder.Disc, MaterialLib.Rishtan0, new Vector3(5.45f, TableTop + 0.07f, 5.45f), Vector3.zero, new Vector3(0.62f, 1f, 0.62f));
            Vector3[] pp = { new Vector3(5.25f, 0, 5.3f), new Vector3(5.72f, 0, 5.5f), new Vector3(5.45f, 0.2f, 5.42f) };
            foreach (var p in pp)
            {
                var g = Ball(t, MaterialLib.Pomegranate, new Vector3(p.x, TableTop + 0.26f + p.y, p.z), new Vector3(0.22f, 0.2f, 0.22f));
                Turned(t, "anor.crown", MaterialLib.Pomegranate, g.localPosition + new Vector3(0, 0.17f, 0), new[]
                {
                    new Vector2(0, 0), new Vector2(0.06f, 0), new Vector2(0.05f, 0.06f), new Vector2(0.08f, 0.09f), new Vector2(0, 0.07f)
                }, 6, true);
            }
            for (int i = 0; i < 14; i++)
            {
                float a = i * 2.4f, r = 0.05f + (i % 4) * 0.035f;
                Ball(t, MaterialLib.Grape, new Vector3(5.2f + Mathf.Cos(a) * r, TableTop + 0.3f - (i % 4) * 0.03f, 5.75f + Mathf.Sin(a) * r * 0.6f + (i % 3) * 0.03f), Vector3.one * 0.06f);
            }

            // коса с наввотом (кристаллический сахар)
            Turned(t, "kosa", MaterialLib.GlazeCobalt, new Vector3(-5.45f, TableTop, 5.45f), new[]
            {
                new Vector2(0, 0), new Vector2(0.2f, 0), new Vector2(0.22f, 0.05f), new Vector2(0.42f, 0.28f), new Vector2(0.45f, 0.36f),
                new Vector2(0.41f, 0.36f), new Vector2(0.2f, 0.1f), new Vector2(0, 0.1f)
            }, 24);
            for (int i = 0; i < 9; i++)
            {
                float a = i * 0.7f, r = 0.08f + (i % 3) * 0.08f;
                Part(t, MeshBuilder.Cube, MaterialLib.Sugar, new Vector3(-5.45f + Mathf.Cos(a) * r, TableTop + 0.3f + (i % 2) * 0.05f, 5.45f + Mathf.Sin(a) * r),
                    new Vector3(i * 37f, i * 53f, i * 11f), Vector3.one * 0.11f);
            }

            TableLanterns.Add(new Vector3(-5.6f, TableTop, 0f));
            TableLanterns.Add(new Vector3(5.6f, TableTop, 0f));

            // курпачи и подушки вокруг хонтахты
            var longK = MaterialLib.Tiled(MaterialLib.Quilts[0], new Vector2(4f, 1f));
            var sideK = MaterialLib.Tiled(MaterialLib.Quilts[2], new Vector2(1f, 3f));
            for (int s = -1; s <= 1; s += 2)
            {
                Box(t, longK, new Vector3(0, FloorY + 0.2f, s * 8.7f), new Vector3(11f, 0.36f, 2.6f));
                for (int k = -1; k <= 1; k++)
                    Ball(t, MaterialLib.Quilts[(k + 2) % MaterialLib.Quilts.Length], new Vector3(k * 3.4f, FloorY + 0.75f, s * 9.7f), new Vector3(1.3f, 0.55f, 0.55f));
                Box(t, sideK, new Vector3(s * 8.7f, FloorY + 0.2f, 0), new Vector3(2.6f, 0.36f, 11f));
            }
        }

        // ================================================================== Зал

        public static void BuildRoom(Transform w)
        {
            Windows.Clear();
            HangingLanterns.Clear();
            WindowGlow = MaterialLib.Unlit(new Color(1f, 0.92f, 0.75f, 1f));

            // пол из досок и бухарский гилам
            Box(w, MaterialLib.Planks, new Vector3(0, FloorY - 0.1f, 0), new Vector3(Half * 2f, 0.2f, Half * 2f));
            Box(w, MaterialLib.Gilam, new Vector3(0, FloorY + 0.02f, 0), new Vector3(29f, 0.04f, 29f));
            // палосы перед тахмоном и дверью
            Box(w, MaterialLib.Palos, new Vector3(0, FloorY + 0.03f, 17.3f), new Vector3(16f, 0.04f, 3.6f));
            Box(w, MaterialLib.Palos, new Vector3(0, FloorY + 0.03f, -17.3f), new Vector3(16f, 0.04f, 3.6f));
            // курпачи-сиденья и валики вдоль западной стены (у восточной стоит сундук)
            for (int s = -1; s <= -1; s += 2)
            {
                var seat = MaterialLib.Tiled(MaterialLib.Quilts[s < 0 ? 1 : 3], new Vector2(1f, 4f));
                Box(w, seat, new Vector3(s * 17.6f, FloorY + 0.22f, 0), new Vector3(2.8f, 0.4f, 13f));
                for (int k = -2; k <= 2; k++)
                    Part(w, MeshBuilder.Sphere, MaterialLib.Quilts[(k + 7) % MaterialLib.Quilts.Length], new Vector3(s * 19.1f, FloorY + 1.0f, k * 2.5f), Vector3.zero, new Vector3(0.55f, 0.6f, 1.15f));
            }

            for (int i = 0; i < 4; i++)
            {
                var node = Node(w, "Wall" + i, Vector3.zero, new Vector3(0, i * 90f, 0));
                Wall(node, i);
            }

            for (int i = 0; i < 4; i++)
            {
                float x = (i % 2 == 0 ? 1 : -1) * 13.5f, z = (i < 2 ? 1 : -1) * 13.5f;
                Column(w, new Vector3(x, FloorY, z));
                Xum(w, new Vector3((i % 2 == 0 ? 1 : -1) * 18.6f, FloorY, (i < 2 ? 1 : -1) * 18.6f), i);
            }
            Ceiling(w);
        }

        // ------------------------------------------------------------------ Стена

        /// <summary>Стена в локальных координатах: плоскость z = Half, зал — в сторону −z.</summary>
        static void Wall(Transform n, int kind)
        {
            float y0 = FloorY, R = Half, L = Half * 2f;
            Box(n, MaterialLib.Ganch, new Vector3(0, y0 + Height * 0.5f, R + 0.3f), new Vector3(L + 1f, Height, 0.6f));

            // проёмы, где нет нижних панелей
            var gaps = new List<Vector2>();
            if (kind == 0) gaps.Add(new Vector2(-5.7f, 5.7f));
            if (kind == 2) gaps.Add(new Vector2(-4.3f, 4.3f));

            // резные деревянные панели внизу стены
            Box(n, MaterialLib.DarkWood, new Vector3(0, y0 + 2.6f, R - 0.12f), new Vector3(L, 5.2f, 0.25f));
            for (float x = -R + 2.2f; x <= R - 2.2f; x += 3.45f)
            {
                bool skip = false;
                foreach (var g in gaps) if (x > g.x - 1.6f && x < g.y + 1.6f) skip = true;
                if (skip) continue;
                Box(n, MaterialLib.PanelWood, new Vector3(x, y0 + 2.65f, R - 0.3f), new Vector3(3.05f, 4.25f, 0.12f));
            }
            Box(n, MaterialLib.DarkWood, new Vector3(0, y0 + 5.15f, R - 0.3f), new Vector3(L, 0.4f, 0.6f));
            Box(n, MaterialLib.Inlay, new Vector3(0, y0 + 5.37f, R - 0.6f), new Vector3(L, 0.07f, 0.07f));
            Box(n, MaterialLib.DarkWood, new Vector3(0, y0 + 0.18f, R - 0.28f), new Vector3(L, 0.36f, 0.55f));

            // ступенчатый карниз с «сталактитами» ганча
            Box(n, MaterialLib.Tiled(MaterialLib.BeamPaint, new Vector2(10f, 1f)), new Vector3(0, y0 + Height - 0.45f, R - 0.3f), new Vector3(L, 0.9f, 0.6f));
            Box(n, MaterialLib.DarkWood, new Vector3(0, y0 + Height - 1.15f, R - 0.5f), new Vector3(L, 0.5f, 1.0f));
            for (float x = -R + 0.5f; x < R; x += 0.9f)
                Box(n, MaterialLib.GanchDeep, new Vector3(x, y0 + Height - 1.75f, R - 0.7f), new Vector3(0.45f, 0.7f, 0.5f));
            Box(n, MaterialLib.Inlay, new Vector3(0, y0 + Height - 2.15f, R - 0.5f), new Vector3(L, 0.08f, 0.08f));

            switch (kind)
            {
                case 0:
                    Taxmon(n);
                    Suzani(n, -12.2f, y0 + 11f, 7f, 7.5f);
                    Suzani(n, 12.2f, y0 + 11f, 7f, 7.5f);
                    for (int i = -1; i <= 1; i++) Niche(n, i * 3.6f, y0 + 16.4f, 2.4f, 3.6f, (i + 2) % 3);
                    Niche(n, -17.8f, y0 + 9.6f, 2.6f, 4.4f, 1);
                    Niche(n, 17.8f, y0 + 9.6f, 2.6f, 4.4f, 2);
                    break;
                case 1:
                    WindowAt(n, -9f);
                    WindowAt(n, 9f);
                    Niche(n, 0f, y0 + 9.6f, 2.8f, 4.6f, 0);
                    Niche(n, -17.6f, y0 + 9.6f, 2.6f, 4.4f, 2);
                    Niche(n, 17.6f, y0 + 9.6f, 2.6f, 4.4f, 1);
                    Sandiq(n, 0f);
                    break;
                case 2:
                    Door(n);
                    WindowAt(n, -11.5f);
                    WindowAt(n, 11.5f);
                    Niche(n, -17.8f, y0 + 9.6f, 2.4f, 4.4f, 0);
                    Niche(n, 17.8f, y0 + 9.6f, 2.4f, 4.4f, 1);
                    break;
                default:
                    WindowAt(n, -9f);
                    WindowAt(n, 9f);
                    Doira(n, 0f, y0 + 11.5f);
                    Dutar(n, 12.4f);
                    Niche(n, -17.6f, y0 + 9.6f, 2.6f, 4.4f, 1);
                    Niche(n, 17.6f, y0 + 9.6f, 2.6f, 4.4f, 0);
                    break;
            }
        }

        /// <summary>Ниша-токча со стрельчатым верхом; внутри ляган или кувшин.</summary>
        static void Niche(Transform n, float x, float y, float w, float h, int item)
        {
            float R = Half;
            Box(n, MaterialLib.NicheDark, new Vector3(x, y, R - 0.02f), new Vector3(w, h, 0.05f));
            Box(n, MaterialLib.GanchDeep, new Vector3(x - w * 0.5f - 0.16f, y - 0.1f, R - 0.3f), new Vector3(0.32f, h + 0.2f, 0.6f));
            Box(n, MaterialLib.GanchDeep, new Vector3(x + w * 0.5f + 0.16f, y - 0.1f, R - 0.3f), new Vector3(0.32f, h + 0.2f, 0.6f));
            Box(n, MaterialLib.DarkWood, new Vector3(x, y - h * 0.5f - 0.12f, R - 0.42f), new Vector3(w + 0.8f, 0.24f, 0.85f));
            // стрельчатая (ланцетная) арка
            Part(n, ArchFill(w), MaterialLib.NicheDark, new Vector3(x, y + h * 0.5f, R - 0.025f), Vector3.zero, Vector3.one);
            Part(n, ArchTube(w + 0.32f, 0.17f), MaterialLib.GanchDeep, new Vector3(x, y + h * 0.5f, R - 0.3f), Vector3.zero, Vector3.one);

            float baseY = y - h * 0.5f;
            if (item == 0)
            {
                float r = Mathf.Min(w * 0.42f, h * 0.36f);
                Part(n, MeshBuilder.Disc, MaterialLib.Rishtan0, new Vector3(x, baseY + r + 0.12f, R - 0.3f), new Vector3(-78f, 0, 0), new Vector3(r, 1f, r));
                Ring(n, MaterialLib.Glaze, new Vector3(x, baseY + r + 0.12f, R - 0.28f), r, 0.05f, new Vector3(-78f, 0, 0));
            }
            else if (item == 1)
            {
                Turned(n, "koza", MaterialLib.Glaze, new Vector3(x, baseY, R - 0.6f), new[]
                {
                    new Vector2(0, 0), new Vector2(0.35f, 0), new Vector2(0.62f, 0.45f), new Vector2(0.7f, 1.0f), new Vector2(0.5f, 1.55f),
                    new Vector2(0.24f, 1.85f), new Vector2(0.22f, 2.2f), new Vector2(0.32f, 2.32f), new Vector2(0.28f, 2.36f)
                }, 20, false, 3f);
                Ring(n, MaterialLib.GlazeCobalt, new Vector3(x, baseY + 1.0f, R - 0.6f), 0.69f, 0.05f);
                Ring(n, MaterialLib.GlazeCobalt, new Vector3(x + 0.45f, baseY + 1.6f, R - 0.6f), 0.3f, 0.05f, new Vector3(90, 0, 0));
            }
            else
            {
                float r = Mathf.Min(w * 0.36f, h * 0.3f);
                Part(n, MeshBuilder.Disc, MaterialLib.Rishtan1, new Vector3(x, baseY + r + 0.1f, R - 0.25f), new Vector3(-80f, 0, 0), new Vector3(r, 1f, r));
                Ring(n, MaterialLib.GlazeCobalt, new Vector3(x, baseY + r + 0.1f, R - 0.23f), r, 0.04f, new Vector3(-80f, 0, 0));
                Turned(n, "piyola.niche", MaterialLib.Porcelain, new Vector3(x - w * 0.3f, baseY, R - 0.65f), new[]
                {
                    new Vector2(0, 0), new Vector2(0.18f, 0), new Vector2(0.36f, 0.26f), new Vector2(0.38f, 0.34f), new Vector2(0.34f, 0.34f), new Vector2(0, 0.1f)
                }, 18, false, 2f);
            }
        }

        /// <summary>Тахмон: большая ниша со сложенными курпачами и подушками.</summary>
        static void Taxmon(Transform n)
        {
            float y0 = FloorY, R = Half;
            Box(n, MaterialLib.NicheDark, new Vector3(0, y0 + 6f, R - 0.03f), new Vector3(10.4f, 12f, 0.05f));
            Box(n, MaterialLib.ColumnWood, new Vector3(-5.5f, y0 + 6f, R - 0.5f), new Vector3(0.7f, 12f, 1.0f));
            Box(n, MaterialLib.ColumnWood, new Vector3(5.5f, y0 + 6f, R - 0.5f), new Vector3(0.7f, 12f, 1.0f));
            Box(n, MaterialLib.Tiled(MaterialLib.BeamPaint, new Vector2(3f, 1f)), new Vector3(0, y0 + 12.5f, R - 0.55f), new Vector3(12f, 1.1f, 1.1f));
            Box(n, MaterialLib.Inlay, new Vector3(0, y0 + 11.9f, R - 1.1f), new Vector3(12f, 0.08f, 0.08f));
            Box(n, MaterialLib.DarkWood, new Vector3(0, y0 + 0.25f, R - 1.4f), new Vector3(10.4f, 0.5f, 2.9f));
            float y = y0 + 0.5f;
            for (int i = 0; i < 10; i++)
            {
                float th = 0.5f + (i % 3) * 0.06f;
                float jx = ((i * 37) % 7 - 3) * 0.06f;
                Box(n, MaterialLib.Quilts[i % MaterialLib.Quilts.Length], new Vector3(jx, y + th * 0.5f, R - 1.45f), new Vector3(9.2f - (i % 2) * 0.3f, th, 2.6f));
                y += th;
            }
            for (int k = -1; k <= 1; k++)
                Ball(n, MaterialLib.Quilts[(k + 4) % MaterialLib.Quilts.Length], new Vector3(k * 2.9f, y + 0.45f, R - 1.4f), new Vector3(1.35f, 0.5f, 0.9f));
            // верхняя полка с посудой
            Box(n, MaterialLib.DarkWood, new Vector3(0, y0 + 9.6f, R - 0.6f), new Vector3(10.4f, 0.2f, 1.1f));
            for (int k = -2; k <= 2; k++)
            {
                if (k % 2 == 0)
                    Part(n, MeshBuilder.Disc, k == 0 ? MaterialLib.Rishtan0 : MaterialLib.Rishtan1, new Vector3(k * 1.9f, y0 + 10.55f, R - 0.4f), new Vector3(-80f, 0, 0), new Vector3(0.8f, 1f, 0.8f));
                else
                    Turned(n, "choynak.small", MaterialLib.Porcelain, new Vector3(k * 1.9f, y0 + 9.7f, R - 0.7f), new[]
                    {
                        new Vector2(0, 0), new Vector2(0.26f, 0), new Vector2(0.42f, 0.25f), new Vector2(0.44f, 0.4f), new Vector2(0.36f, 0.58f), new Vector2(0.22f, 0.66f), new Vector2(0, 0.68f)
                    }, 20, false, 2f);
            }
        }

        static void Suzani(Transform n, float x, float y, float w, float h)
        {
            float R = Half;
            Box(n, MaterialLib.Carpet, new Vector3(x, y, R - 0.06f), new Vector3(w, h, 0.04f));
            Part(n, MeshBuilder.Cylinder, MaterialLib.DarkWood, new Vector3(x - w * 0.55f, y + h * 0.5f + 0.1f, R - 0.2f), new Vector3(0, 0, -90f), new Vector3(0.09f, w * 1.1f, 0.09f));
            Ball(n, MaterialLib.Brass, new Vector3(x - w * 0.56f, y + h * 0.5f + 0.1f, R - 0.2f), Vector3.one * 0.16f);
            Ball(n, MaterialLib.Brass, new Vector3(x + w * 0.56f, y + h * 0.5f + 0.1f, R - 0.2f), Vector3.one * 0.16f);
        }

        /// <summary>Окно с деревянной решёткой-панжара и светящимся проёмом.</summary>
        static void WindowAt(Transform n, float x)
        {
            float R = Half, w = 4.6f, h = 7f, yc = FloorY + 9.6f;
            var glow = Node(n, "WindowGlow", new Vector3(x, yc, R - 0.04f), new Vector3(-90f, 0, 0));
            Part(glow, MeshBuilder.QuadXZ, WindowGlow, Vector3.zero, Vector3.zero, new Vector3(w, 1f, h));

            for (int i = 1; i <= 4; i++)
                Box(n, MaterialLib.Lattice, new Vector3(x + w * (i / 5f - 0.5f), yc + 0.6f, R - 0.14f), new Vector3(0.1f, h + 1.2f, 0.1f));
            for (int j = 1; j <= 6; j++)
                Box(n, MaterialLib.Lattice, new Vector3(x, yc + h * (j / 7f - 0.5f), R - 0.14f), new Vector3(w, 0.1f, 0.1f));
            for (int i = 1; i <= 4; i++)
                for (int j = 1; j <= 6; j++)
                    Box(n, MaterialLib.Lattice, new Vector3(x + w * (i / 5f - 0.5f), yc + h * (j / 7f - 0.5f), R - 0.16f), new Vector3(0.26f, 0.26f, 0.08f), new Vector3(0, 0, 45f));

            Box(n, MaterialLib.DarkWood, new Vector3(x - w * 0.5f - 0.2f, yc + 0.6f, R - 0.3f), new Vector3(0.4f, h + 1.4f, 0.6f));
            Box(n, MaterialLib.DarkWood, new Vector3(x + w * 0.5f + 0.2f, yc + 0.6f, R - 0.3f), new Vector3(0.4f, h + 1.4f, 0.6f));
            Box(n, MaterialLib.DarkWood, new Vector3(x, yc - h * 0.5f - 0.18f, R - 0.42f), new Vector3(w + 1.2f, 0.36f, 0.85f));
            Part(n, ArchFill(w), WindowGlow, new Vector3(x, yc + h * 0.5f, R - 0.045f), Vector3.zero, Vector3.one);
            Box(n, MaterialLib.Lattice, new Vector3(x, yc + h * 0.5f + w * 0.43f, R - 0.14f), new Vector3(0.1f, w * 0.86f, 0.1f));
            Part(n, ArchTube(w + 0.4f, 0.22f), MaterialLib.DarkWood, new Vector3(x, yc + h * 0.5f, R - 0.3f), Vector3.zero, Vector3.one);
            Box(n, MaterialLib.Tiled(MaterialLib.BeamPaint, new Vector2(2f, 1f)), new Vector3(x, yc + h * 0.5f + w * 0.95f, R - 0.3f), new Vector3(w + 1.4f, 0.6f, 0.6f));

            Windows.Add(new Window
            {
                Center = n.localRotation * new Vector3(x, yc, R - 0.1f),
                Inward = n.localRotation * Vector3.back,
                Width = w,
                Height = h
            });
        }

        /// <summary>Хивинская двустворчатая резная дверь.</summary>
        static void Door(Transform n)
        {
            float y0 = FloorY, R = Half;
            Box(n, MaterialLib.ColumnWood, new Vector3(-3.75f, y0 + 6.2f, R - 0.5f), new Vector3(0.9f, 12.4f, 1.0f));
            Box(n, MaterialLib.ColumnWood, new Vector3(3.75f, y0 + 6.2f, R - 0.5f), new Vector3(0.9f, 12.4f, 1.0f));
            Box(n, MaterialLib.Tiled(MaterialLib.BeamPaint, new Vector2(3f, 1f)), new Vector3(0, y0 + 12.9f, R - 0.55f), new Vector3(8.6f, 1.2f, 1.1f));
            Box(n, MaterialLib.Inlay, new Vector3(0, y0 + 12.25f, R - 1.12f), new Vector3(8.6f, 0.08f, 0.08f));
            Box(n, MaterialLib.GanchDeep, new Vector3(0, y0 + 15.2f, R - 0.1f), new Vector3(4.6f, 4.6f, 0.2f), new Vector3(0, 0, 45f));
            Box(n, MaterialLib.DarkWood, new Vector3(0, y0 + 6.1f, R - 0.2f), new Vector3(6.6f, 12.2f, 0.2f));
            for (int leaf = -1; leaf <= 1; leaf += 2)
            {
                float lx = leaf * 1.62f;
                for (int k = 0; k < 3; k++)
                    Box(n, MaterialLib.DoorWood, new Vector3(lx, y0 + 2.2f + k * 3.95f, R - 0.38f), new Vector3(3.0f, 3.55f, 0.16f));
                for (int k = 0; k < 4; k++)
                    for (int s = -1; s <= 1; s += 2)
                        Ball(n, MaterialLib.Brass, new Vector3(lx + s * 1.45f, y0 + 0.35f + k * 3.95f, R - 0.5f), Vector3.one * 0.1f);
                Ring(n, MaterialLib.Brass, new Vector3(leaf * 0.55f, y0 + 6.0f, R - 0.6f), 0.32f, 0.06f, new Vector3(90f, 0, 0));
                Ball(n, MaterialLib.Brass, new Vector3(leaf * 0.55f, y0 + 6.3f, R - 0.55f), Vector3.one * 0.14f);
            }
            Box(n, MaterialLib.Inlay, new Vector3(0, y0 + 6.1f, R - 0.5f), new Vector3(0.06f, 12.2f, 0.08f));
            Box(n, MaterialLib.DarkWood, new Vector3(0, y0 + 0.12f, R - 0.9f), new Vector3(7.6f, 0.24f, 1.2f));
        }

        /// <summary>Сундук-сандиқ с латунными полосами и стопкой одеял.</summary>
        static void Sandiq(Transform n, float x)
        {
            float y0 = FloorY, R = Half, z = R - 2.0f;
            Box(n, MaterialLib.DarkWood, new Vector3(x, y0 + 1.25f, z), new Vector3(5.2f, 2.5f, 2.4f));
            Box(n, MaterialLib.Tiled(MaterialLib.FrameSide, new Vector2(4f, 2f)), new Vector3(x, y0 + 1.2f, z - 1.21f), new Vector3(4.6f, 2.0f, 0.04f));
            Box(n, MaterialLib.DarkWood, new Vector3(x, y0 + 2.62f, z), new Vector3(5.5f, 0.3f, 2.6f));
            for (int s = -1; s <= 1; s += 2)
            {
                Box(n, MaterialLib.Brass, new Vector3(x + s * 1.3f, y0 + 1.3f, z), new Vector3(0.16f, 2.62f, 2.48f));
                Box(n, MaterialLib.Brass, new Vector3(x + s * 2.6f, y0 + 1.3f, z), new Vector3(0.12f, 2.62f, 2.48f));
            }
            Box(n, MaterialLib.Brass, new Vector3(x, y0 + 1.9f, z - 1.25f), new Vector3(0.5f, 0.6f, 0.06f));
            float y = y0 + 2.77f;
            for (int i = 0; i < 4; i++)
            {
                Box(n, MaterialLib.Quilts[(i + 1) % MaterialLib.Quilts.Length], new Vector3(x + (i % 2) * 0.1f, y + 0.25f, z), new Vector3(4.8f - i * 0.2f, 0.5f, 2.1f));
                y += 0.5f;
            }
            Ball(n, MaterialLib.Quilts[3], new Vector3(x, y + 0.4f, z), new Vector3(1.6f, 0.5f, 0.8f));
        }

        static void Doira(Transform n, float x, float y)
        {
            float R = Half;
            Ring(n, MaterialLib.DarkWood, new Vector3(x, y, R - 0.35f), 1.35f, 0.13f, new Vector3(90f, 0, 0));
            Part(n, MeshBuilder.Disc, MaterialLib.Skin, new Vector3(x, y, R - 0.4f), new Vector3(-90f, 0, 0), new Vector3(1.3f, 1f, 1.3f));
            for (int i = 0; i < 14; i++)
            {
                float a = i * Mathf.PI * 2f / 14f;
                Ring(n, MaterialLib.Brass, new Vector3(x + Mathf.Cos(a) * 1.1f, y + Mathf.Sin(a) * 1.1f, R - 0.45f), 0.12f, 0.02f, new Vector3(0, 0, a * Mathf.Rad2Deg));
            }
            Ball(n, MaterialLib.Brass, new Vector3(x, y + 1.6f, R - 0.2f), Vector3.one * 0.12f);
        }

        /// <summary>Дутар, прислонённый к стене.</summary>
        static void Dutar(Transform n, float x)
        {
            float R = Half;
            var d = Node(n, "Dutar", new Vector3(x, FloorY + 0.05f, R - 1.0f), new Vector3(-14f, 0, 10f));
            var body = Node(d, "Body", Vector3.zero, Vector3.zero, new Vector3(1f, 1f, 0.55f));
            Turned(body, "dutar.body", MaterialLib.TableWood, Vector3.zero, new[]
            {
                new Vector2(0, 0), new Vector2(0.4f, 0.03f), new Vector2(0.78f, 0.35f), new Vector2(0.88f, 0.85f),
                new Vector2(0.72f, 1.4f), new Vector2(0.4f, 1.8f), new Vector2(0.16f, 2.0f), new Vector2(0, 2.05f)
            }, 20);
            Part(d, MeshBuilder.Disc, MaterialLib.Leather, new Vector3(0, 0.95f, -0.42f), new Vector3(-90f, 0, 0), new Vector3(0.62f, 1f, 0.82f));
            Box(d, MaterialLib.DarkWood, new Vector3(0, 4.3f, -0.15f), new Vector3(0.22f, 4.8f, 0.14f));
            for (int k = 0; k < 7; k++) Box(d, MaterialLib.Inlay, new Vector3(0, 2.6f + k * 0.55f, -0.23f), new Vector3(0.24f, 0.03f, 0.02f));
            Box(d, MaterialLib.DarkWood, new Vector3(0, 7.0f, -0.12f), new Vector3(0.3f, 0.9f, 0.16f));
            Part(d, MeshBuilder.Cylinder, MaterialLib.Ivory, new Vector3(-0.25f, 6.85f, -0.12f), new Vector3(0, 0, 90f), new Vector3(0.05f, 0.5f, 0.05f));
            Part(d, MeshBuilder.Cylinder, MaterialLib.Ivory, new Vector3(-0.25f, 7.15f, -0.12f), new Vector3(0, 0, 90f), new Vector3(0.05f, 0.5f, 0.05f));
            Box(d, MaterialLib.Ivory, new Vector3(-0.04f, 4.0f, -0.26f), new Vector3(0.012f, 6.2f, 0.012f));
            Box(d, MaterialLib.Ivory, new Vector3(0.04f, 4.0f, -0.26f), new Vector3(0.012f, 6.2f, 0.012f));
        }

        /// <summary>Резная колонна-устун: «коса» у основания, витой ствол, капитель с кронштейнами.</summary>
        static void Column(Transform w, Vector3 p)
        {
            var c = Node(w, "Ustun", p);
            Box(c, MaterialLib.DarkWood, new Vector3(0, 0.25f, 0), new Vector3(2.3f, 0.5f, 2.3f));
            Turned(c, "ustun.kosa", MaterialLib.DarkWood, new Vector3(0, 0.5f, 0), new[]
            {
                new Vector2(0, 0), new Vector2(0.95f, 0), new Vector2(1.05f, 0.15f), new Vector2(1.12f, 0.5f), new Vector2(1.0f, 0.85f),
                new Vector2(0.75f, 1.15f), new Vector2(0.56f, 1.38f), new Vector2(0.62f, 1.48f), new Vector2(0, 1.48f)
            }, 24);
            Ring(c, MaterialLib.Inlay, new Vector3(0, 1.05f, 0), 1.1f, 0.05f);
            Ring(c, MaterialLib.Inlay, new Vector3(0, 1.95f, 0), 0.6f, 0.06f);
            const float shaftH = Height - 7.6f;
            Turned(c, "ustun.shaft", MaterialLib.ColumnWood, new Vector3(0, 1.95f, 0), new[]
            {
                new Vector2(0, 0), new Vector2(0.6f, 0), new Vector2(0.58f, 0.3f), new Vector2(0.5f, shaftH * 0.5f), new Vector2(0.42f, shaftH), new Vector2(0, shaftH)
            }, 24);
            float top = 1.95f + shaftH;
            Ring(c, MaterialLib.Inlay, new Vector3(0, top - 0.1f, 0), 0.44f, 0.06f);
            Turned(c, "ustun.capital", MaterialLib.DarkWood, new Vector3(0, top, 0), new[]
            {
                new Vector2(0, 0), new Vector2(0.45f, 0), new Vector2(0.6f, 0.5f), new Vector2(0.9f, 1.0f), new Vector2(1.25f, 1.5f), new Vector2(1.3f, 1.8f), new Vector2(0, 1.8f)
            }, 16, true);
            Box(c, MaterialLib.Tiled(MaterialLib.BeamPaint, new Vector2(1f, 1f)), new Vector3(0, top + 2.0f, 0), new Vector3(2.8f, 0.4f, 2.8f));
            Box(c, MaterialLib.DarkWood, new Vector3(0, top + 2.5f, 0), new Vector3(4.2f, 0.6f, 1.0f));
            Box(c, MaterialLib.DarkWood, new Vector3(0, top + 2.5f, 0), new Vector3(1.0f, 0.6f, 4.2f));
            Box(c, MaterialLib.DarkWood, new Vector3(0, top + 3.1f, 0), new Vector3(5.6f, 0.6f, 1.1f));
            Box(c, MaterialLib.DarkWood, new Vector3(0, top + 3.1f, 0), new Vector3(1.1f, 0.6f, 5.6f));
        }

        /// <summary>Большой изразцовый хум в углу зала.</summary>
        static void Xum(Transform w, Vector3 p, int i)
        {
            Turned(w, "xum", MaterialLib.TileTurquoise, p, new[]
            {
                new Vector2(0, 0), new Vector2(0.9f, 0), new Vector2(1.5f, 1.1f), new Vector2(1.8f, 2.8f), new Vector2(1.45f, 4.4f),
                new Vector2(0.8f, 5.2f), new Vector2(0.68f, 5.8f), new Vector2(0.95f, 6.1f), new Vector2(0.9f, 6.2f), new Vector2(0.6f, 6.0f)
            }, 28, false, 3f);
            Ring(w, MaterialLib.GlazeCobalt, p + new Vector3(0, 2.8f, 0), 1.8f, 0.09f);
            Ring(w, MaterialLib.GlazeCobalt, p + new Vector3(0, 4.4f, 0), 1.45f, 0.08f);
            Box(w, MaterialLib.DarkWood, p + new Vector3(0, -0.05f, 0), new Vector3(2.4f, 0.12f, 2.4f), new Vector3(0, 45f, 0));
        }

        /// <summary>Расписной потолок: главные балки-болор, частые балки-васса, фонари на цепях.</summary>
        static void Ceiling(Transform w)
        {
            float L = Half * 2f, top = CeilingY;
            Box(w, MaterialLib.CeilingPaint, new Vector3(0, top + 0.15f, 0), new Vector3(L, 0.3f, L));
            var beam = MaterialLib.Tiled(MaterialLib.BeamPaint, new Vector2(12f, 1f));
            foreach (float z in new[] { -13.5f, 0f, 13.5f })
                Box(w, beam, new Vector3(0, top - 0.6f, z), new Vector3(L, 1.2f, 1.1f));
            for (float x = -Half + 0.7f; x < Half; x += 1.4f)
                Part(w, MeshBuilder.Cylinder, MaterialLib.DarkWood, new Vector3(x, top - 0.2f, -Half), new Vector3(90f, 0, 0), new Vector3(0.2f, L, 0.2f));

            foreach (var lp in new[] { new Vector3(-7f, 0, -7f), new Vector3(7f, 0, -7f), new Vector3(-7f, 0, 7f), new Vector3(7f, 0, 7f) })
            {
                Vector3 pos = new Vector3(lp.x, FloorY + 18.5f, lp.z);
                Part(w, MeshBuilder.Cylinder, MaterialLib.Brass, pos + new Vector3(0, 1.2f, 0), Vector3.zero, new Vector3(0.04f, top - (pos.y + 1.2f), 0.04f));
                Turned(w, "fonar", MaterialLib.Brass, pos, new[]
                {
                    new Vector2(0, -0.2f), new Vector2(0.25f, -0.15f), new Vector2(0.4f, 0f), new Vector2(0.55f, 0.15f), new Vector2(0.55f, 0.75f),
                    new Vector2(0.62f, 0.85f), new Vector2(0.3f, 1.05f), new Vector2(0.08f, 1.2f), new Vector2(0, 1.22f)
                }, 8, true);
                HangingLanterns.Add(pos + new Vector3(0, 0.45f, 0));
            }
        }
    }
}
