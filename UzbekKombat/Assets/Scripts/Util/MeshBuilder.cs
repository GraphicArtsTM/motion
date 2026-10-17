using System;
using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    /// <summary>
    /// Protsedural geometriya yig'uvchi: lathe (aylanma jism), quti, sfera, sweep (qilich/kamon),
    /// vertex-rang bilan. Barcha model va arena shu orqali yaratiladi (tashqi asset kerak emas).
    /// </summary>
    public class MeshBuilder
    {
        readonly List<Vector3> verts = new List<Vector3>(512);
        readonly List<Vector3> norms = new List<Vector3>(512);
        readonly List<Vector2> uvs = new List<Vector2>(512);
        readonly List<Color> cols = new List<Color>(512);
        readonly List<int> tris = new List<int>(1024);

        public Color color = Color.white;
        public Matrix4x4 matrix = Matrix4x4.identity;
        public bool classifySkin;       // personaj meshlari: teri ranglarini aniqlash (UV2.y)
        public float bakeAO;            // pastga qaragan yuzalarni qoraytirish (0..1)

        public int VertexCount => verts.Count;

        public MeshBuilder SetColor(Color c) { color = c; return this; }

        public MeshBuilder SetTransform(Vector3 pos, Quaternion rot, Vector3 scale)
        {
            matrix = Matrix4x4.TRS(pos, rot, scale);
            return this;
        }

        public MeshBuilder SetTransform(Vector3 pos, Quaternion rot) => SetTransform(pos, rot, Vector3.one);
        public MeshBuilder SetTransform(Vector3 pos) => SetTransform(pos, Quaternion.identity, Vector3.one);
        public MeshBuilder ResetTransform() { matrix = Matrix4x4.identity; return this; }

        int AddVertex(Vector3 p, Vector3 n, Vector2 uv, Color c)
        {
            verts.Add(matrix.MultiplyPoint3x4(p));
            Vector3 tn = matrix.MultiplyVector(n);
            norms.Add(tn.sqrMagnitude > 1e-8f ? tn.normalized : Vector3.up);
            uvs.Add(uv);
            cols.Add(c);
            return verts.Count - 1;
        }

        public void AddTriangle(Vector3 a, Vector3 b, Vector3 c)
        {
            Vector3 n = Vector3.Cross(b - a, c - a).normalized;
            int i0 = AddVertex(a, n, new Vector2(0, 0), color);
            int i1 = AddVertex(b, n, new Vector2(1, 0), color);
            int i2 = AddVertex(c, n, new Vector2(0, 1), color);
            tris.Add(i0); tris.Add(i1); tris.Add(i2);
        }

        /// <summary>Tekis normalli to'rtburchak (a,b,c,d soat millari bo'yicha old tomondan qaraganda).</summary>
        public void AddQuad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector2 uvMin, Vector2 uvMax)
        {
            Vector3 n = Vector3.Cross(b - a, d - a);
            if (n.sqrMagnitude < 1e-10f) n = Vector3.Cross(c - b, a - b);
            n.Normalize();
            int i0 = AddVertex(a, n, new Vector2(uvMin.x, uvMin.y), color);
            int i1 = AddVertex(b, n, new Vector2(uvMin.x, uvMax.y), color);
            int i2 = AddVertex(c, n, new Vector2(uvMax.x, uvMax.y), color);
            int i3 = AddVertex(d, n, new Vector2(uvMax.x, uvMin.y), color);
            tris.Add(i0); tris.Add(i1); tris.Add(i2);
            tris.Add(i0); tris.Add(i2); tris.Add(i3);
        }

        public void AddQuad(Vector3 a, Vector3 b, Vector3 c, Vector3 d) => AddQuad(a, b, c, d, Vector2.zero, Vector2.one);

        public void AddDoubleQuad(Vector3 a, Vector3 b, Vector3 c, Vector3 d)
        {
            AddQuad(a, b, c, d);
            AddQuad(d, c, b, a);
        }

        /// <summary>Markazi va o'lchami berilgan quti. uvScale>0 bo'lsa UV dunyo o'lchamida takrorlanadi.</summary>
        public void Box(Vector3 center, Vector3 size, float uvScale = 0f)
        {
            Vector3 h = size * 0.5f;
            Vector3[] p =
            {
                center + new Vector3(-h.x, -h.y, -h.z), center + new Vector3(h.x, -h.y, -h.z),
                center + new Vector3(h.x, h.y, -h.z), center + new Vector3(-h.x, h.y, -h.z),
                center + new Vector3(-h.x, -h.y, h.z), center + new Vector3(h.x, -h.y, h.z),
                center + new Vector3(h.x, h.y, h.z), center + new Vector3(-h.x, h.y, h.z)
            };
            Vector2 uxy = uvScale > 0 ? new Vector2(size.x, size.y) * uvScale : Vector2.one;
            Vector2 uzy = uvScale > 0 ? new Vector2(size.z, size.y) * uvScale : Vector2.one;
            Vector2 uxz = uvScale > 0 ? new Vector2(size.x, size.z) * uvScale : Vector2.one;
            AddQuad(p[0], p[3], p[2], p[1], Vector2.zero, new Vector2(uxy.x, uxy.y)); // -Z
            AddQuad(p[5], p[6], p[7], p[4], Vector2.zero, new Vector2(uxy.x, uxy.y)); // +Z
            AddQuad(p[4], p[7], p[3], p[0], Vector2.zero, new Vector2(uzy.x, uzy.y)); // -X
            AddQuad(p[1], p[2], p[6], p[5], Vector2.zero, new Vector2(uzy.x, uzy.y)); // +X
            AddQuad(p[3], p[7], p[6], p[2], Vector2.zero, new Vector2(uxz.x, uxz.y)); // +Y
            AddQuad(p[4], p[0], p[1], p[5], Vector2.zero, new Vector2(uxz.x, uxz.y)); // -Y
        }

        /// <summary>
        /// Aylanma jism. profile: (radius, y) nuqtalar pastdan yuqoriga.
        /// hardProfile=true — har bir profil segmenti alohida (low-poly qirrali ko'rinish).
        /// colorFn(u,v) — har bir kvadrat uchun rang (chopon yo'llari, naqshlar uchun).
        /// </summary>
        public void Lathe(IList<Vector2> profile, int segments, Vector3 offset, float scaleX = 1f, float scaleZ = 1f,
            bool hardProfile = false, Func<float, float, Color> colorFn = null, float startAngle = 0f, float sweep = 360f)
        {
            int n = profile.Count;
            if (n < 2) return;
            float[] vlen = new float[n];
            for (int i = 1; i < n; i++) vlen[i] = vlen[i - 1] + Vector2.Distance(profile[i], profile[i - 1]);
            float total = Mathf.Max(0.0001f, vlen[n - 1]);

            // Profil normallari (r,y tekisligida)
            Vector2[] pn = new Vector2[n];
            for (int i = 0; i < n; i++)
            {
                Vector2 a = profile[Mathf.Max(0, i - 1)];
                Vector2 b = profile[Mathf.Min(n - 1, i + 1)];
                Vector2 t = b - a;
                if (t.sqrMagnitude < 1e-10f) t = new Vector2(0, 1);
                pn[i] = new Vector2(t.y, -t.x).normalized;
            }

            float a0 = startAngle * Mathf.Deg2Rad;
            float da = sweep * Mathf.Deg2Rad / segments;
            for (int s = 0; s < segments; s++)
            {
                float ang0 = a0 + s * da, ang1 = a0 + (s + 1) * da;
                Vector3 d0 = new Vector3(Mathf.Sin(ang0), 0, Mathf.Cos(ang0));
                Vector3 d1 = new Vector3(Mathf.Sin(ang1), 0, Mathf.Cos(ang1));
                for (int i = 0; i < n - 1; i++)
                {
                    Vector2 p0 = profile[i], p1 = profile[i + 1];
                    Vector2 n0 = pn[i], n1 = pn[i + 1];
                    if (hardProfile)
                    {
                        Vector2 t = p1 - p0;
                        Vector2 fn = t.sqrMagnitude < 1e-10f ? new Vector2(0, 1) : new Vector2(t.y, -t.x).normalized;
                        n0 = fn; n1 = fn;
                    }
                    Color c = colorFn != null ? colorFn((s + 0.5f) / segments, (vlen[i] + vlen[i + 1]) * 0.5f / total) : color;
                    Vector3 v00 = offset + new Vector3(d0.x * p0.x * scaleX, p0.y, d0.z * p0.x * scaleZ);
                    Vector3 v01 = offset + new Vector3(d0.x * p1.x * scaleX, p1.y, d0.z * p1.x * scaleZ);
                    Vector3 v11 = offset + new Vector3(d1.x * p1.x * scaleX, p1.y, d1.z * p1.x * scaleZ);
                    Vector3 v10 = offset + new Vector3(d1.x * p0.x * scaleX, p0.y, d1.z * p0.x * scaleZ);
                    Vector3 nn00 = Norm(d0, n0, scaleX, scaleZ), nn01 = Norm(d0, n1, scaleX, scaleZ);
                    Vector3 nn11 = Norm(d1, n1, scaleX, scaleZ), nn10 = Norm(d1, n0, scaleX, scaleZ);
                    float u0 = (float)s / segments, u1 = (float)(s + 1) / segments;
                    float vv0 = vlen[i] / total, vv1 = vlen[i + 1] / total;
                    int i00 = AddVertex(v00, nn00, new Vector2(u0, vv0), c);
                    int i01 = AddVertex(v01, nn01, new Vector2(u0, vv1), c);
                    int i11 = AddVertex(v11, nn11, new Vector2(u1, vv1), c);
                    int i10 = AddVertex(v10, nn10, new Vector2(u1, vv0), c);
                    // Tashqariga qaragan tartib
                    tris.Add(i00); tris.Add(i11); tris.Add(i01);
                    tris.Add(i00); tris.Add(i10); tris.Add(i11);
                }
            }
        }

        static Vector3 Norm(Vector3 dir, Vector2 pn, float sx, float sz)
        {
            Vector3 n = new Vector3(dir.x * pn.x / Mathf.Max(0.01f, sx), pn.y, dir.z * pn.x / Mathf.Max(0.01f, sz));
            return n.normalized;
        }

        public void Lathe(IList<Vector2> profile, int segments) => Lathe(profile, segments, Vector3.zero);

        /// <summary>Ellipsoid / sfera.</summary>
        public void Sphere(Vector3 center, Vector3 radii, int rings = 8, int segments = 12, Func<float, float, Color> colorFn = null)
        {
            var prof = new List<Vector2>(rings + 1);
            for (int i = 0; i <= rings; i++)
            {
                float a = Mathf.PI * i / rings - Mathf.PI * 0.5f;
                prof.Add(new Vector2(Mathf.Cos(a), Mathf.Sin(a) * radii.y));
            }
            prof[0] = new Vector2(0, -radii.y);
            prof[rings] = new Vector2(0, radii.y);
            Lathe(prof, segments, center, radii.x, radii.z, false, colorFn);
        }

        public void Sphere(Vector3 center, float r, int rings = 8, int segments = 12) => Sphere(center, Vector3.one * r, rings, segments);

        /// <summary>Kesik konus (frustum) — y0 dan y1 gacha, yopiq.</summary>
        public void Cylinder(Vector3 offset, float r0, float r1, float y0, float y1, int segments = 10, bool caps = true,
            float scaleX = 1, float scaleZ = 1, Func<float, float, Color> colorFn = null)
        {
            var prof = new List<Vector2>();
            if (caps) prof.Add(new Vector2(0, y0));
            prof.Add(new Vector2(r0, y0));
            prof.Add(new Vector2(r1, y1));
            if (caps) prof.Add(new Vector2(0, y1));
            Lathe(prof, segments, offset, scaleX, scaleZ, true, colorFn);
        }

        /// <summary>Ikki nuqta orasida silindr (suyak/tayoq).</summary>
        public void Capsule(Vector3 a, Vector3 b, float ra, float rb, int segments = 8)
        {
            Vector3 d = b - a;
            float len = d.magnitude;
            if (len < 1e-5f) return;
            Matrix4x4 old = matrix;
            matrix = old * Matrix4x4.TRS(a, Quaternion.FromToRotation(Vector3.up, d / len), Vector3.one);
            var prof = new List<Vector2>
            {
                new Vector2(0, -ra * 0.6f), new Vector2(ra * 0.75f, -ra * 0.45f), new Vector2(ra, 0),
                new Vector2(rb, len), new Vector2(rb * 0.75f, len + rb * 0.45f), new Vector2(0, len + rb * 0.6f)
            };
            Lathe(prof, segments, Vector3.zero);
            matrix = old;
        }

        /// <summary>
        /// Yo'l bo'ylab kesim chizish (qilich tig'i, kamon, arqon). section — (N,B) tekisligidagi nuqtalar,
        /// widthFn(t) kesim o'lchamini o'zgartiradi. Tekis normallar (qirrali po'lat ko'rinishi).
        /// </summary>
        public void Sweep(IList<Vector3> path, IList<Vector2> section, Func<float, Vector2> scaleFn, Vector3 refUp, bool closeEnds = true)
        {
            int n = path.Count, m = section.Count;
            if (n < 2) return;
            var rings = new Vector3[n][];
            for (int i = 0; i < n; i++)
            {
                Vector3 t = (path[Mathf.Min(n - 1, i + 1)] - path[Mathf.Max(0, i - 1)]).normalized;
                Vector3 nn = Vector3.Cross(t, refUp);
                if (nn.sqrMagnitude < 1e-6f) nn = Vector3.Cross(t, Vector3.right);
                nn.Normalize();
                Vector3 bb = Vector3.Cross(nn, t).normalized;
                Vector2 sc = scaleFn != null ? scaleFn((float)i / (n - 1)) : Vector2.one;
                rings[i] = new Vector3[m];
                for (int k = 0; k < m; k++)
                    rings[i][k] = path[i] + nn * section[k].x * sc.x + bb * section[k].y * sc.y;
            }
            for (int i = 0; i < n - 1; i++)
                for (int k = 0; k < m; k++)
                {
                    int k1 = (k + 1) % m;
                    AddQuad(rings[i][k], rings[i + 1][k], rings[i + 1][k1], rings[i][k1]);
                }
            if (closeEnds)
            {
                Vector3 c0 = path[0], c1 = path[n - 1];
                for (int k = 0; k < m; k++)
                {
                    int k1 = (k + 1) % m;
                    AddTriangle(c0, rings[0][k], rings[0][k1]);
                    AddTriangle(c1, rings[n - 1][k1], rings[n - 1][k]);
                }
            }
        }

        /// <summary>Torus (salla o'rami, halqalar).</summary>
        public void Torus(Vector3 center, float majorR, float minorR, int majorSeg = 16, int minorSeg = 6, float scaleZ = 1f, Func<float, float, Color> colorFn = null)
        {
            for (int i = 0; i < majorSeg; i++)
            {
                float a0 = i * Mathf.PI * 2 / majorSeg, a1 = (i + 1) * Mathf.PI * 2 / majorSeg;
                for (int j = 0; j < minorSeg; j++)
                {
                    float b0 = j * Mathf.PI * 2 / minorSeg, b1 = (j + 1) * Mathf.PI * 2 / minorSeg;
                    Color c = colorFn != null ? colorFn((i + 0.5f) / majorSeg, (j + 0.5f) / minorSeg) : color;
                    Vector3 p00 = TorusPt(center, majorR, minorR, a0, b0, scaleZ), p01 = TorusPt(center, majorR, minorR, a0, b1, scaleZ);
                    Vector3 p11 = TorusPt(center, majorR, minorR, a1, b1, scaleZ), p10 = TorusPt(center, majorR, minorR, a1, b0, scaleZ);
                    Vector3 n00 = TorusN(a0, b0), n01 = TorusN(a0, b1), n11 = TorusN(a1, b1), n10 = TorusN(a1, b0);
                    int i0 = AddVertex(p00, n00, new Vector2(0, 0), c);
                    int i1 = AddVertex(p01, n01, new Vector2(0, 1), c);
                    int i2 = AddVertex(p11, n11, new Vector2(1, 1), c);
                    int i3 = AddVertex(p10, n10, new Vector2(1, 0), c);
                    tris.Add(i0); tris.Add(i2); tris.Add(i1);
                    tris.Add(i0); tris.Add(i3); tris.Add(i2);
                }
            }
        }

        static Vector3 TorusPt(Vector3 c, float R, float r, float a, float b, float sz)
        {
            float rr = R + r * Mathf.Cos(b);
            return c + new Vector3(Mathf.Sin(a) * rr, r * Mathf.Sin(b), Mathf.Cos(a) * rr * sz);
        }

        static Vector3 TorusN(float a, float b) => new Vector3(Mathf.Sin(a) * Mathf.Cos(b), Mathf.Sin(b), Mathf.Cos(a) * Mathf.Cos(b));

        /// <summary>Gorizontal tekislik (XZ), segmentlarga bo'lingan.</summary>
        public void Plane(Vector3 center, Vector2 size, int segX = 1, int segZ = 1, float uvScale = 1f, Func<float, float, float> heightFn = null)
        {
            for (int x = 0; x < segX; x++)
                for (int z = 0; z < segZ; z++)
                {
                    float x0 = -size.x / 2 + size.x * x / segX, x1 = -size.x / 2 + size.x * (x + 1) / segX;
                    float z0 = -size.y / 2 + size.y * z / segZ, z1 = -size.y / 2 + size.y * (z + 1) / segZ;
                    float h00 = heightFn?.Invoke(center.x + x0, center.z + z0) ?? 0, h01 = heightFn?.Invoke(center.x + x0, center.z + z1) ?? 0;
                    float h11 = heightFn?.Invoke(center.x + x1, center.z + z1) ?? 0, h10 = heightFn?.Invoke(center.x + x1, center.z + z0) ?? 0;
                    AddQuad(center + new Vector3(x0, h00, z0), center + new Vector3(x0, h01, z1), center + new Vector3(x1, h11, z1), center + new Vector3(x1, h10, z0),
                        new Vector2(x0, z0) * uvScale, new Vector2(x1, z1) * uvScale);
                }
        }

        /// <summary>Old tomoni -Z ga qaragan vertikal panel.</summary>
        public void Panel(Vector3 center, Vector2 size, Vector2 uvMin, Vector2 uvMax, bool doubleSided = false)
        {
            Vector3 h = new Vector3(size.x / 2, size.y / 2, 0);
            Vector3 a = center + new Vector3(-h.x, -h.y, 0), b = center + new Vector3(-h.x, h.y, 0);
            Vector3 c = center + new Vector3(h.x, h.y, 0), d = center + new Vector3(h.x, -h.y, 0);
            AddQuad(a, b, c, d, uvMin, uvMax);
            if (doubleSided) AddQuad(d, c, b, a, uvMin, uvMax);
        }

        public void Append(MeshBuilder other)
        {
            int baseIdx = verts.Count;
            for (int i = 0; i < other.verts.Count && i < other.cols.Count; i++)
            {
                verts.Add(matrix.MultiplyPoint3x4(other.verts[i]));
                norms.Add(matrix.MultiplyVector(other.norms[i]).normalized);
                uvs.Add(other.uvs[i]);
                cols.Add(other.cols[i]);
            }
            foreach (int t in other.tris) tris.Add(t + baseIdx);
        }

        static bool IsSkin(Color c)
        {
            Color.RGBToHSV(c, out float h, out float s, out float v);
            return h > 0.035f && h < 0.1f && s > 0.25f && s < 0.62f && v > 0.5f && v < 0.92f;
        }

        public Mesh ToMesh(string name = "ProcMesh")
        {
            var mesh = new Mesh { name = name };
            if (verts.Count > 65000) mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
            mesh.SetVertices(verts);
            mesh.SetNormals(norms);
            mesh.SetUVs(0, uvs);
            // Material parametrlari: UV2.x — metall, UV2.y — teri. Vertex rang — Linear fazoga.
            bool linear = QualitySettings.activeColorSpace == ColorSpace.Linear;
            var uv2 = new List<Vector2>(cols.Count);
            var outCols = new List<Color>(cols.Count);
            for (int i = 0; i < cols.Count; i++)
            {
                Color c = cols[i];
                float metal = Mathf.Clamp01(1f - c.a);
                bool skin = classifySkin && metal < 0.01f && IsSkin(c);
                uv2.Add(new Vector2(metal, skin ? 1 : 0));
                if (bakeAO > 0)
                {
                    float down = Mathf.Max(0, -norms[i].y);
                    c = c * (1f - bakeAO * down * 0.45f);
                }
                c.a = 1;
                outCols.Add(linear ? c.linear : c);
            }
            mesh.SetUVs(1, uv2);
            mesh.SetColors(outCols);
            mesh.SetTriangles(tris, 0);
            mesh.RecalculateBounds();
            return mesh;
        }

        public bool IsEmpty => verts.Count == 0;

        public void Clear()
        {
            verts.Clear(); norms.Clear(); uvs.Clear(); cols.Clear(); tris.Clear();
            matrix = Matrix4x4.identity;
        }

        /// <summary>Mesh yaratib GameObject sifatida joylashtiradi.</summary>
        public GameObject Build(string name, Transform parent, Material mat, bool castShadows = true, Material extra = null)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.AddComponent<MeshFilter>().sharedMesh = ToMesh(name);
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterials = extra != null ? new[] { mat, extra } : new[] { mat };
            mr.shadowCastingMode = castShadows ? UnityEngine.Rendering.ShadowCastingMode.On : UnityEngine.Rendering.ShadowCastingMode.Off;
            mr.receiveShadows = true;
            return go;
        }
    }
}
