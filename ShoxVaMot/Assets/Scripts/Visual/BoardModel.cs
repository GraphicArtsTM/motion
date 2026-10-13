using System.Collections.Generic;
using UnityEngine;
using Shatranj.Chess;

namespace Shatranj.Visual
{
    /// <summary>
    /// Резная доска «как у мастера из Хивы»: клетки-плитки из чинары и ореха с фаской,
    /// золотой валик, широкая рама с позолоченной резной лозой ислими, профилированный карниз,
    /// боковины с гирих-резьбой, точёные ножки и золотые розетки по углам.
    /// Только геометрия — коллайдеры и подписи добавляет BoardView.
    /// </summary>
    public static class BoardModel
    {
        public const float Inner = 4f;          // полусторона игрового поля
        public const float BandMid = 4.32f;     // середина резной полосы (там подписи координат)
        public const float Outer = 4.74f;       // внешний край рамы
        public const float Bottom = -0.37f;     // низ доски
        public const float FootHeight = 0.25f;

        public static void Build(Transform root)
        {
            Squares(root, true);
            Squares(root, false);
            Part(root, MeshBuilder.QuadXZ, MaterialLib.BoardGroove, new Vector3(0, -0.014f, 0), Vector3.zero, new Vector3(8.02f, 1f, 8.02f));

            // валик → резная полоса → карниз → боковина
            Part(root, MeshBuilder.FrameExtrude("bead", new[]
            {
                new Vector2(-0.01f, -0.014f), new Vector2(0f, 0.012f), new Vector2(0.015f, 0.038f), new Vector2(0.04f, 0.05f),
                new Vector2(0.065f, 0.042f), new Vector2(0.075f, 0.03f)
            }, Inner, 1f, 1f), MaterialLib.Inlay, Vector3.zero, Vector3.zero, Vector3.one);
            Part(root, MeshBuilder.FrameExtrude("band", new[]
            {
                new Vector2(0.075f, 0.03f), new Vector2(0.08f, 0.045f), new Vector2(0.56f, 0.045f), new Vector2(0.565f, 0.03f)
            }, Inner, 1.9f, 0.5f), MaterialLib.FrameCarved, Vector3.zero, Vector3.zero, Vector3.one);
            Part(root, MeshBuilder.FrameExtrude("molding", new[]
            {
                new Vector2(0.565f, 0.03f), new Vector2(0.575f, 0.06f), new Vector2(0.6f, 0.075f), new Vector2(0.625f, 0.07f),
                new Vector2(0.645f, 0.045f), new Vector2(0.66f, 0.0f), new Vector2(0.675f, -0.035f), new Vector2(0.7f, -0.055f),
                new Vector2(0.725f, -0.065f), new Vector2(0.74f, -0.085f), new Vector2(Outer - Inner, -0.1f)
            }, Inner, 1.2f, 0.3f), MaterialLib.FrameWood, Vector3.zero, Vector3.zero, Vector3.one);
            Part(root, MeshBuilder.FrameExtrude("side", new[]
            {
                new Vector2(Outer - Inner, -0.1f), new Vector2(Outer - Inner, Bottom + 0.03f)
            }, Inner, 0.27f, 0.27f), MaterialLib.FrameSide, Vector3.zero, Vector3.zero, Vector3.one);
            Part(root, MeshBuilder.FrameExtrude("plinth", new[]
            {
                new Vector2(Outer - Inner, Bottom + 0.03f), new Vector2(Outer - Inner + 0.03f, Bottom + 0.015f), new Vector2(Outer - Inner, Bottom), new Vector2(0f, Bottom)
            }, Inner, 1f, 1f), MaterialLib.Inlay, Vector3.zero, Vector3.zero, Vector3.one);

            // угловые розетки и точёные ножки
            var rosette = MeshBuilder.Cached("lathe.rosette2", () => MeshBuilder.Lathe("rosette2", new[]
            {
                new Vector2(0, 0), new Vector2(0.21f, 0), new Vector2(0.21f, 0.012f), new Vector2(0.15f, 0.025f),
                new Vector2(0.06f, 0.04f), new Vector2(0, 0.045f)
            }, 8, 22.5f, 360f, true));
            var foot = MeshBuilder.Cached("lathe.boardfoot", () => MeshBuilder.Lathe("boardfoot", new[]
            {
                new Vector2(0, 0), new Vector2(0.3f, 0), new Vector2(0.34f, 0.035f), new Vector2(0.27f, 0.08f),
                new Vector2(0.19f, 0.13f), new Vector2(0.27f, 0.19f), new Vector2(0.34f, 0.23f), new Vector2(0.34f, FootHeight), new Vector2(0, FootHeight)
            }, 20));
            for (int i = 0; i < 4; i++)
            {
                float sx = (i % 2 == 0 ? 1 : -1), sz = (i < 2 ? 1 : -1);
                Part(root, rosette, MaterialLib.Inlay, new Vector3(sx * BandMid, 0.045f, sz * BandMid), new Vector3(0, 22.5f, 0), Vector3.one);
                Part(root, foot, MaterialLib.FrameWood, new Vector3(sx * 4.3f, Bottom - FootHeight, sz * 4.3f), Vector3.zero, Vector3.one);
                Part(root, MeshBuilder.Torus(0.3f, 0.018f, 24, 6), MaterialLib.Inlay, new Vector3(sx * 4.3f, Bottom - 0.065f, sz * 4.3f), Vector3.zero, Vector3.one);
            }

            // ромбики-картуши под буквами и цифрами координат
            for (int i = 0; i < 8; i++)
            {
                float c = i - 3.5f;
                foreach (var p in new[] { new Vector3(c, 0, -BandMid), new Vector3(c, 0, BandMid), new Vector3(-BandMid, 0, c), new Vector3(BandMid, 0, c) })
                    Part(root, MeshBuilder.Cube, MaterialLib.BoardGroove, new Vector3(p.x, 0.047f, p.z), new Vector3(0, 45, 0), new Vector3(0.2f, 0.006f, 0.2f));
            }
        }

        static Transform Part(Transform parent, Mesh mesh, Material m, Vector3 pos, Vector3 euler, Vector3 scale)
        {
            var go = new GameObject(mesh.name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = Quaternion.Euler(euler);
            go.transform.localScale = scale;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            go.AddComponent<MeshRenderer>().sharedMaterial = m;
            return go.transform;
        }

        /// <summary>Плитки клеток с фаской; у каждой свой кусок древесины, волокна чередуются паркетом.</summary>
        static void Squares(Transform parent, bool light)
        {
            var verts = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            var rng = new System.Random(light ? 17 : 29);
            const float b = 0.035f, gap = 0.006f, top = 0f, low = -0.013f;
            for (int sq = 0; sq < 64; sq++)
            {
                if (Sq.IsLight(sq) != light) continue;
                float cx = Sq.File(sq) - 3.5f, cz = Sq.Rank(sq) - 3.5f;
                float ou = (float)rng.NextDouble(), ov = (float)rng.NextDouble();
                bool rot = ((Sq.File(sq) + Sq.Rank(sq) / 2) & 1) == 0;
                const float uvs_ = 0.45f;
                System.Func<float, float, Vector2> uvOf = (x, z) =>
                {
                    float a = (x - cx + 0.5f) * uvs_, c = (z - cz + 0.5f) * uvs_;
                    return rot ? new Vector2(ou + c, ov + a) : new Vector2(ou + a, ov + c);
                };
                float o = 0.5f - gap, i = 0.5f - b;
                // верх
                Quad(verts, uvs, tris, uvOf,
                    new Vector3(cx - i, top, cz - i), new Vector3(cx - i, top, cz + i), new Vector3(cx + i, top, cz + i), new Vector3(cx + i, top, cz - i));
                // четыре фаски
                Quad(verts, uvs, tris, uvOf,
                    new Vector3(cx - o, low, cz - o), new Vector3(cx - i, top, cz - i), new Vector3(cx + i, top, cz - i), new Vector3(cx + o, low, cz - o));
                Quad(verts, uvs, tris, uvOf,
                    new Vector3(cx + o, low, cz - o), new Vector3(cx + i, top, cz - i), new Vector3(cx + i, top, cz + i), new Vector3(cx + o, low, cz + o));
                Quad(verts, uvs, tris, uvOf,
                    new Vector3(cx + o, low, cz + o), new Vector3(cx + i, top, cz + i), new Vector3(cx - i, top, cz + i), new Vector3(cx - o, low, cz + o));
                Quad(verts, uvs, tris, uvOf,
                    new Vector3(cx - o, low, cz + o), new Vector3(cx - i, top, cz + i), new Vector3(cx - i, top, cz - i), new Vector3(cx - o, low, cz - o));
            }
            var m = new Mesh { name = light ? "squares.light" : "squares.dark" };
            m.SetVertices(verts);
            m.SetUVs(0, uvs);
            m.SetTriangles(tris, 0);
            m.RecalculateNormals();
            m.RecalculateBounds();
            m.RecalculateTangents();
            Part(parent, m, light ? MaterialLib.BoardLight : MaterialLib.BoardDark, Vector3.zero, Vector3.zero, Vector3.one);
        }

        /// <summary>Четырёхугольник a-b-c-d по часовой стрелке, если смотреть сверху (лицом вверх/наружу).</summary>
        static void Quad(List<Vector3> v, List<Vector2> uv, List<int> t, System.Func<float, float, Vector2> uvOf, Vector3 a, Vector3 b, Vector3 c, Vector3 d)
        {
            int i0 = v.Count;
            v.Add(a); v.Add(b); v.Add(c); v.Add(d);
            uv.Add(uvOf(a.x, a.z)); uv.Add(uvOf(b.x, b.z)); uv.Add(uvOf(c.x, c.z)); uv.Add(uvOf(d.x, d.z));
            t.Add(i0); t.Add(i0 + 1); t.Add(i0 + 2);
            t.Add(i0); t.Add(i0 + 2); t.Add(i0 + 3);
        }
    }
}
