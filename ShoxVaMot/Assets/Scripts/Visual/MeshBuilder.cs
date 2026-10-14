using System.Collections.Generic;
using UnityEngine;

namespace Shatranj.Visual
{
    /// <summary>
    /// Процедурная геометрия: «токарные» тела вращения (как у резных деревянных фигур),
    /// торы (чалма, пояс-белбог), трубки по кривой (хобот, хвост), клинок сабли (қилич).
    /// </summary>
    public static class MeshBuilder
    {
        static readonly Dictionary<string, Mesh> cache = new Dictionary<string, Mesh>();
        static Mesh sphere, sphereMid, sphereLow, cube, cylinder, capsule;

        public static Mesh Sphere { get { return sphere != null ? sphere : (sphere = Lathe("sphere", SphereProfile(1f, 10), 16)); } }
        /// <summary>Сфера средней детализации (головы, плечи) — 192 треугольника.</summary>
        public static Mesh SphereMid { get { return sphereMid != null ? sphereMid : (sphereMid = Lathe("sphere.mid", SphereProfile(1f, 8), 12)); } }
        /// <summary>Облегчённая сфера для мелких деталей (глаза, заклёпки, ягоды) — 120 треугольников.</summary>
        public static Mesh SphereLow { get { return sphereLow != null ? sphereLow : (sphereLow = Lathe("sphere.low", SphereProfile(1f, 6), 10)); } }
        public static Mesh Cube { get { return cube != null ? cube : (cube = BuildCube()); } }
        public static Mesh Cylinder { get { return cylinder != null ? cylinder : (cylinder = Lathe("cyl", new[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(1, 1), new Vector2(0, 1) }, 20)); } }
        public static Mesh Capsule { get { return capsule != null ? capsule : (capsule = Lathe("capsule", CapsuleProfile(1f, 2f, 6), 16)); } }

        public static Mesh Cached(string key, System.Func<Mesh> build)
        {
            Mesh m;
            if (cache.TryGetValue(key, out m) && m != null) return m;
            m = build();
            m.name = key;
            cache[key] = m;
            return m;
        }

        public static Vector2[] SphereProfile(float r, int steps)
        {
            var p = new Vector2[steps + 1];
            for (int i = 0; i <= steps; i++)
            {
                float a = -Mathf.PI / 2f + Mathf.PI * i / steps;
                p[i] = new Vector2(Mathf.Cos(a) * r, Mathf.Sin(a) * r);
            }
            p[0].x = 0f; p[steps].x = 0f;
            return p;
        }

        /// <summary>Профиль капсулы радиуса r и полной высоты h (ось Y от 0 до h).</summary>
        public static Vector2[] CapsuleProfile(float r, float h, int capSteps)
        {
            var list = new List<Vector2>();
            for (int i = 0; i <= capSteps; i++)
            {
                float a = -Mathf.PI / 2f + (Mathf.PI / 2f) * i / capSteps;
                list.Add(new Vector2(Mathf.Cos(a) * r, Mathf.Sin(a) * r + r));
            }
            for (int i = 0; i <= capSteps; i++)
            {
                float a = (Mathf.PI / 2f) * i / capSteps;
                list.Add(new Vector2(Mathf.Cos(a) * r, h - r + Mathf.Sin(a) * r));
            }
            var arr = list.ToArray();
            arr[0].x = 0; arr[arr.Length - 1].x = 0;
            return arr;
        }

        /// <summary>
        /// Тело вращения по профилю (x = радиус, y = высота), снизу вверх.
        /// Точки с нулевым радиусом на концах замыкают тело. sweep &lt; 360 даёт часть (плащ).
        /// </summary>
        public static Mesh Lathe(string name, Vector2[] profile, int segments, float startDeg = 0f, float sweepDeg = 360f, bool flat = false, float uRepeat = 1f)
        {
            int rings = profile.Length;
            int cols = segments + 1;
            var verts = new List<Vector3>(rings * cols);
            var norms = new List<Vector3>(rings * cols);
            var uvs = new List<Vector2>(rings * cols);
            var tris = new List<int>(rings * segments * 6);

            float[] len = new float[rings];
            for (int i = 1; i < rings; i++) len[i] = len[i - 1] + Vector2.Distance(profile[i], profile[i - 1]);
            float total = Mathf.Max(len[rings - 1], 1e-4f);

            for (int i = 0; i < rings; i++)
            {
                Vector2 prev = profile[Mathf.Max(i - 1, 0)];
                Vector2 next = profile[Mathf.Min(i + 1, rings - 1)];
                Vector2 t = (next - prev).normalized;
                Vector2 n2 = new Vector2(t.y, -t.x);
                for (int s = 0; s < cols; s++)
                {
                    float a = (startDeg + sweepDeg * s / segments) * Mathf.Deg2Rad;
                    float ca = Mathf.Cos(a), sa = Mathf.Sin(a);
                    verts.Add(new Vector3(profile[i].x * ca, profile[i].y, profile[i].x * sa));
                    norms.Add(new Vector3(n2.x * ca, n2.y, n2.x * sa).normalized);
                    uvs.Add(new Vector2(uRepeat * s / (float)segments, len[i] / total));
                }
            }
            for (int i = 0; i < rings - 1; i++)
            {
                for (int s = 0; s < segments; s++)
                {
                    int a = i * cols + s, b = a + 1, c = a + cols, d = c + 1;
                    tris.Add(a); tris.Add(c); tris.Add(b);
                    tris.Add(b); tris.Add(c); tris.Add(d);
                }
            }

            var mesh = new Mesh { name = name };
            mesh.SetVertices(verts);
            mesh.SetNormals(norms);
            mesh.SetUVs(0, uvs);
            mesh.SetTriangles(tris, 0);
            if (flat) MakeFlat(mesh);
            mesh.RecalculateBounds(); mesh.RecalculateTangents();
            return mesh;
        }

        /// <summary>Разваривает вершины, чтобы получить гранёный вид (тюбетейка, рёбра купола).</summary>
        public static void MakeFlat(Mesh mesh)
        {
            var v = mesh.vertices;
            var uv = mesh.uv;
            var t = mesh.triangles;
            var nv = new Vector3[t.Length];
            var nuv = new Vector2[t.Length];
            var nt = new int[t.Length];
            for (int i = 0; i < t.Length; i++)
            {
                nv[i] = v[t[i]];
                nuv[i] = uv[t[i]];
                nt[i] = i;
            }
            mesh.Clear();
            mesh.vertices = nv;
            mesh.uv = nuv;
            mesh.triangles = nt;
            mesh.RecalculateNormals();
        }

        public static Mesh Torus(float R, float r, int segU = 24, int segV = 10)
        {
            return Cached("torus." + R + "." + r + "." + segU + "." + segV, () =>
            {
                var verts = new List<Vector3>();
                var norms = new List<Vector3>();
                var uvs = new List<Vector2>();
                var tris = new List<int>();
                for (int i = 0; i <= segU; i++)
                {
                    float a = 2f * Mathf.PI * i / segU;
                    Vector3 center = new Vector3(Mathf.Cos(a) * R, 0, Mathf.Sin(a) * R);
                    Vector3 outward = new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a));
                    for (int j = 0; j <= segV; j++)
                    {
                        float b = 2f * Mathf.PI * j / segV;
                        Vector3 n = outward * Mathf.Cos(b) + Vector3.up * Mathf.Sin(b);
                        verts.Add(center + n * r);
                        norms.Add(n);
                        uvs.Add(new Vector2(i / (float)segU * 4f, j / (float)segV));
                    }
                }
                int cols = segV + 1;
                for (int i = 0; i < segU; i++)
                    for (int j = 0; j < segV; j++)
                    {
                        int a = i * cols + j, b = a + 1, c = a + cols, d = c + 1;
                        tris.Add(a); tris.Add(b); tris.Add(c);
                        tris.Add(b); tris.Add(d); tris.Add(c);
                    }
                var m = new Mesh();
                m.SetVertices(verts); m.SetNormals(norms); m.SetUVs(0, uvs); m.SetTriangles(tris, 0);
                m.RecalculateBounds(); m.RecalculateTangents();
                return m;
            });
        }

        /// <summary>Трубка по ломаной с переменным радиусом (хобот, бивни, шея коня, хвост).</summary>
        public static Mesh Tube(string key, Vector3[] pts, float[] radii, int seg = 10, bool capEnd = true)
        {
            return Cached("tube." + key, () =>
            {
                int n = pts.Length;
                var verts = new List<Vector3>();
                var norms = new List<Vector3>();
                var uvs = new List<Vector2>();
                var tris = new List<int>();
                Vector3 prevSide = Vector3.right;
                for (int i = 0; i < n; i++)
                {
                    Vector3 dir = (pts[Mathf.Min(i + 1, n - 1)] - pts[Mathf.Max(i - 1, 0)]).normalized;
                    Vector3 side = Vector3.Cross(dir, Vector3.up);
                    if (side.sqrMagnitude < 1e-4f) side = Vector3.Cross(dir, Vector3.forward);
                    side.Normalize();
                    if (Vector3.Dot(side, prevSide) < 0) side = -side;
                    prevSide = side;
                    Vector3 up = Vector3.Cross(side, dir).normalized;
                    for (int s = 0; s <= seg; s++)
                    {
                        float a = 2f * Mathf.PI * s / seg;
                        Vector3 nrm = side * Mathf.Cos(a) + up * Mathf.Sin(a);
                        verts.Add(pts[i] + nrm * radii[i]);
                        norms.Add(nrm);
                        uvs.Add(new Vector2(s / (float)seg, i / (float)(n - 1)));
                    }
                }
                int cols = seg + 1;
                for (int i = 0; i < n - 1; i++)
                    for (int s = 0; s < seg; s++)
                    {
                        int a = i * cols + s, b = a + 1, c = a + cols, d = c + 1;
                        tris.Add(a); tris.Add(c); tris.Add(b);
                        tris.Add(b); tris.Add(c); tris.Add(d);
                    }
                if (capEnd)
                {
                    int center = verts.Count;
                    Vector3 endDir = (pts[n - 1] - pts[n - 2]).normalized;
                    verts.Add(pts[n - 1] + endDir * radii[n - 1] * 0.5f);
                    norms.Add(endDir);
                    uvs.Add(new Vector2(0.5f, 1f));
                    int baseIdx = (n - 1) * cols;
                    for (int s = 0; s < seg; s++)
                    {
                        tris.Add(baseIdx + s + 1); tris.Add(baseIdx + s); tris.Add(center);
                    }
                }
                var m = new Mesh();
                m.SetVertices(verts); m.SetNormals(norms); m.SetUVs(0, uvs); m.SetTriangles(tris, 0);
                m.RecalculateBounds(); m.RecalculateTangents();
                return m;
            });
        }

        /// <summary>Изогнутый клинок сабли вдоль +Y: ромбовидное сечение, сужение к острию.</summary>
        public static Mesh SabreBlade(float length = 0.36f, float width = 0.034f, float curve = 0.05f)
        {
            return Cached("blade." + length + "." + width + "." + curve, () =>
            {
                const int steps = 12;
                var verts = new List<Vector3>();
                var tris = new List<int>();
                var uvs = new List<Vector2>();
                for (int i = 0; i <= steps; i++)
                {
                    float t = i / (float)steps;
                    float y = t * length;
                    float z = curve * t * t;
                    float w = width * (1f - Mathf.Pow(t, 3f) * 0.85f);
                    if (i == steps) w = 0.001f;
                    float th = w * 0.18f;
                    // сечение: лезвие (вперёд +Z), обух (назад), две щеки
                    verts.Add(new Vector3(0, y, z + w * 0.5f));
                    verts.Add(new Vector3(th, y, z - w * 0.1f));
                    verts.Add(new Vector3(0, y, z - w * 0.5f));
                    verts.Add(new Vector3(-th, y, z - w * 0.1f));
                    for (int k = 0; k < 4; k++) uvs.Add(new Vector2(k / 4f, t));
                }
                for (int i = 0; i < steps; i++)
                {
                    for (int k = 0; k < 4; k++)
                    {
                        int a = i * 4 + k, b = i * 4 + (k + 1) % 4, c = a + 4, d = b + 4;
                        tris.Add(a); tris.Add(b); tris.Add(c);
                        tris.Add(b); tris.Add(d); tris.Add(c);
                    }
                }
                var m = new Mesh();
                m.SetVertices(verts); m.SetUVs(0, uvs); m.SetTriangles(tris, 0);
                MakeFlat(m);
                m.RecalculateBounds(); m.RecalculateTangents();
                return m;
            });
        }

        static Mesh BuildCube()
        {
            var m = new Mesh { name = "cube" };
            var v = new List<Vector3>();
            var n = new List<Vector3>();
            var uv = new List<Vector2>();
            var t = new List<int>();
            Vector3[] dirs = { Vector3.up, Vector3.down, Vector3.left, Vector3.right, Vector3.forward, Vector3.back };
            foreach (var d in dirs)
            {
                Vector3 a = d.y != 0 ? Vector3.right : Vector3.up;
                Vector3 b = Vector3.Cross(d, a);
                int i0 = v.Count;
                v.Add((d - a - b) * 0.5f); v.Add((d + a - b) * 0.5f); v.Add((d + a + b) * 0.5f); v.Add((d - a + b) * 0.5f);
                for (int k = 0; k < 4; k++) n.Add(d);
                uv.Add(new Vector2(0, 0)); uv.Add(new Vector2(1, 0)); uv.Add(new Vector2(1, 1)); uv.Add(new Vector2(0, 1));
                t.Add(i0); t.Add(i0 + 2); t.Add(i0 + 1);
                t.Add(i0); t.Add(i0 + 3); t.Add(i0 + 2);
            }
            m.SetVertices(v); m.SetNormals(n); m.SetUVs(0, uv); m.SetTriangles(t, 0);
            FixWinding(m);
            m.RecalculateBounds(); m.RecalculateTangents();
            return m;
        }

        /// <summary>Гарантирует, что треугольники смотрят наружу (по нормалям вершин).</summary>
        public static void FixWinding(Mesh m)
        {
            var v = m.vertices; var n = m.normals; var t = m.triangles;
            for (int i = 0; i < t.Length; i += 3)
            {
                Vector3 fn = Vector3.Cross(v[t[i + 1]] - v[t[i]], v[t[i + 2]] - v[t[i]]);
                // Для лицевого треугольника Unity Cross(v1-v0, v2-v0) смотрит наружу.
                if (Vector3.Dot(fn, n[t[i]]) < 0f) { int tmp = t[i + 1]; t[i + 1] = t[i + 2]; t[i + 2] = tmp; }
            }
            m.triangles = t;
        }

        /// <summary>
        /// Профиль (s — отступ наружу от внутреннего края, y — высота), протянутый по квадратному
        /// контуру с полустороной halfInner и митровыми углами. Для резных рам доски и стола.
        /// </summary>
        public static Mesh FrameExtrude(string key, Vector2[] profile, float halfInner, float uTile, float vTile)
        {
            return Cached("frame." + key, () =>
            {
                var verts = new List<Vector3>();
                var norms = new List<Vector3>();
                var uvs = new List<Vector2>();
                var tris = new List<int>();
                int n = profile.Length;
                float[] len = new float[n];
                for (int i = 1; i < n; i++) len[i] = len[i - 1] + Vector2.Distance(profile[i], profile[i - 1]);
                Vector3[] outs = { Vector3.back, Vector3.right, Vector3.forward, Vector3.left };
                for (int side = 0; side < 4; side++)
                {
                    Vector3 o = outs[side];
                    Vector3 t = Vector3.Cross(Vector3.up, o);
                    int baseIdx = verts.Count;
                    for (int i = 0; i < n; i++)
                    {
                        Vector2 prev = profile[Mathf.Max(i - 1, 0)], next = profile[Mathf.Min(i + 1, n - 1)];
                        Vector2 d = (next - prev).normalized;
                        Vector2 n2 = new Vector2(-d.y, d.x);
                        Vector3 nrm = (o * n2.x + Vector3.up * n2.y).normalized;
                        float r = halfInner + profile[i].x;
                        Vector3 a = o * r - t * r + Vector3.up * profile[i].y;
                        Vector3 b = o * r + t * r + Vector3.up * profile[i].y;
                        verts.Add(a); verts.Add(b);
                        norms.Add(nrm); norms.Add(nrm);
                        float v = len[i] / vTile;
                        uvs.Add(new Vector2(-r / uTile, v));
                        uvs.Add(new Vector2(r / uTile, v));
                    }
                    for (int i = 0; i < n - 1; i++)
                    {
                        int a0 = baseIdx + i * 2, b0 = a0 + 1, a1 = a0 + 2, b1 = a0 + 3;
                        tris.Add(a0); tris.Add(a1); tris.Add(b0);
                        tris.Add(b0); tris.Add(a1); tris.Add(b1);
                    }
                }
                var m = new Mesh();
                m.SetVertices(verts); m.SetNormals(norms); m.SetUVs(0, uvs); m.SetTriangles(tris, 0);
                FixWinding(m);
                m.RecalculateBounds(); m.RecalculateTangents();
                return m;
            });
        }

        /// <summary>Круг радиуса 1 в плоскости XZ с плоской развёрткой UV (тарелки-ляганы, кожа дойры).</summary>
        public static Mesh Disc
        {
            get
            {
                return Cached("disc", () =>
                {
                    const int seg = 40;
                    var v = new List<Vector3> { Vector3.zero };
                    var uv = new List<Vector2> { new Vector2(0.5f, 0.5f) };
                    var nr = new List<Vector3> { Vector3.up };
                    var t = new List<int>();
                    for (int i = 0; i <= seg; i++)
                    {
                        float a = 2f * Mathf.PI * i / seg;
                        v.Add(new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a)));
                        uv.Add(new Vector2(0.5f + 0.5f * Mathf.Cos(a), 0.5f + 0.5f * Mathf.Sin(a)));
                        nr.Add(Vector3.up);
                    }
                    for (int i = 1; i <= seg; i++) { t.Add(0); t.Add(i); t.Add(i + 1); }
                    var m = new Mesh();
                    m.SetVertices(v); m.SetNormals(nr); m.SetUVs(0, uv); m.SetTriangles(t, 0);
                    FixWinding(m);
                    m.RecalculateBounds(); m.RecalculateTangents();
                    return m;
                });
            }
        }

        /// <summary>Плоский квадрат в плоскости XZ (нормаль вверх), размер 1×1.</summary>
        public static Mesh QuadXZ
        {
            get
            {
                return Cached("quadxz", () =>
                {
                    var m = new Mesh();
                    m.vertices = new[] { new Vector3(-0.5f, 0, -0.5f), new Vector3(-0.5f, 0, 0.5f), new Vector3(0.5f, 0, 0.5f), new Vector3(0.5f, 0, -0.5f) };
                    m.uv = new[] { new Vector2(0, 0), new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0) };
                    m.normals = new[] { Vector3.up, Vector3.up, Vector3.up, Vector3.up };
                    m.triangles = new[] { 0, 1, 2, 0, 2, 3 };
                    m.RecalculateBounds(); m.RecalculateTangents();
                    return m;
                });
            }
        }

        /// <summary>Сфера-небо с вертикальным градиентом в цветах вершин (рисуется изнутри).</summary>
        public static Mesh SkyDome(Color horizon, Color zenith, Color ground, float radius)
        {
            var m = Lathe("sky", SphereProfile(radius, 24), 32);
            var v = m.vertices;
            var cols = new Color[v.Length];
            for (int i = 0; i < v.Length; i++)
            {
                float h = v[i].y / radius;
                cols[i] = h >= 0f ? Color.Lerp(horizon, zenith, Mathf.Pow(h, 0.6f)) : Color.Lerp(horizon, ground, Mathf.Clamp01(-h * 4f));
            }
            m.vertices = v;
            m.colors = cols;
            m.RecalculateBounds(); m.RecalculateTangents();
            return m;
        }
    }
}
