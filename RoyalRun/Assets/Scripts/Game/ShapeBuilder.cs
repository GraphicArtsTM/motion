using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

// A shared colour palette: every colour gets a small cell of one texture, and a mesh "paints" itself
// by pointing its UVs at the cells. Everything coloured this way uses the same three materials
// (matte, shiny, glowing) - very few draw calls, which matters most on phones.
public static class PaletteLib
{
    const int Cells = 32;          // 32 x 32 = 1024 colours
    const int CellPx = 8;
    static Texture2D tex;
    static Texture2D glowTex;
    static readonly Dictionary<int, int> index = new Dictionary<int, int>();
    static int count;
    static bool dirty;
    static Material matte, shiny, glow;

    static int Key(Color c)
    {
        Color32 k = c;
        return (k.r << 16) | (k.g << 8) | k.b;
    }

    static void Ensure()
    {
        if (tex != null) return;
        tex = new Texture2D(Cells * CellPx, Cells * CellPx, TextureFormat.RGBA32, false);
        tex.name = "RR Palette";
        tex.filterMode = FilterMode.Point;
        tex.wrapMode = TextureWrapMode.Clamp;
        glowTex = new Texture2D(Cells * CellPx, Cells * CellPx, TextureFormat.RGBA32, false);
        glowTex.name = "RR Palette Glow";
        glowTex.filterMode = FilterMode.Point;
        glowTex.wrapMode = TextureWrapMode.Clamp;
        Color[] black = new Color[tex.width * tex.height];
        for (int i = 0; i < black.Length; i++) black[i] = Color.black;
        tex.SetPixels(black);
        glowTex.SetPixels(black);
        index.Clear();
        count = 0;
        dirty = true;
    }

    // The UV of a colour's cell (the colour is added if it is new).
    public static Vector2 UV(Color c)
    {
        Ensure();
        c.a = 1f;
        int key = Key(c);
        int cell;
        if (!index.TryGetValue(key, out cell))
        {
            cell = Mathf.Min(count, Cells * Cells - 1);
            count++;
            index[key] = cell;
            int cx = cell % Cells, cy = cell / Cells;
            Color[] block = new Color[CellPx * CellPx];
            for (int i = 0; i < block.Length; i++) block[i] = c;
            tex.SetPixels(cx * CellPx, cy * CellPx, CellPx, CellPx, block);
            glowTex.SetPixels(cx * CellPx, cy * CellPx, CellPx, CellPx, block);
            dirty = true;
        }
        int x = cell % Cells, y = cell / Cells;
        return new Vector2((x + 0.5f) / Cells, (y + 0.5f) / Cells);
    }

    // Sends new colours to the graphics card (called after building).
    public static void Flush()
    {
        if (tex == null || !dirty) return;
        tex.Apply(false);
        glowTex.Apply(false);
        dirty = false;
    }

    // 0 = matte, 1 = shiny (a little metallic), 2 = glowing
    public static Material Material(int kind)
    {
        Ensure();
        Flush();
        if (matte == null)
        {
            matte = Make("RR Palette Matte", 0.22f, 0f, false);
            shiny = Make("RR Palette Shiny", 0.72f, 0.35f, false);
            glow = Make("RR Palette Glow", 0.4f, 0f, true);
        }
        return kind == 2 ? glow : kind == 1 ? shiny : matte;
    }

    public static Material[] Materials()
    {
        return new[] { Material(0), Material(1), Material(2) };
    }

    static Material Make(string name, float smooth, float metallic, bool emissive)
    {
        Material m = new Material(MatLib.Get(Color.white, smooth, 0f, Surface.Plain, Vector2.one));
        m.name = name;
        if (m.HasProperty("_Color")) m.SetColor("_Color", Color.white);
        if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", Color.white);
        if (m.HasProperty("_MainTex")) m.SetTexture("_MainTex", tex);
        if (m.HasProperty("_BaseMap")) m.SetTexture("_BaseMap", tex);
        if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", smooth);
        if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", smooth);
        if (m.HasProperty("_Metallic")) m.SetFloat("_Metallic", metallic);
        if (emissive && m.HasProperty("_EmissionColor"))
        {
            m.EnableKeyword("_EMISSION");
            m.SetColor("_EmissionColor", Color.white * 1.3f);
            if (m.HasProperty("_EmissionMap")) m.SetTexture("_EmissionMap", glowTex);
            m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
        }
        return m;
    }
}

// Builds smooth, rounded meshes from simple shapes (ellipsoids, lathe profiles, tubes, tori, rounded boxes)
// coloured through PaletteLib. Every vertex can follow one or two bones, so a whole character becomes a
// single SkinnedMeshRenderer that bends smoothly at the knees and elbows.
public class ShapeBuilder
{
    public const int Matte = 0, Shiny = 1, Glow = 2;

    readonly List<Vector3> v = new List<Vector3>();
    readonly List<Vector3> n = new List<Vector3>();
    readonly List<Vector2> uv = new List<Vector2>();
    readonly List<BoneWeight> w = new List<BoneWeight>();
    readonly List<int>[] tris = { new List<int>(), new List<int>(), new List<int>() };
    readonly List<Transform> bones = new List<Transform>();
    readonly Dictionary<Transform, int> boneIndex = new Dictionary<Transform, int>();
    readonly Transform root;
    public int Detail = 14;       // segments around a shape (fewer on phones)

    public ShapeBuilder(Transform root)
    {
        this.root = root;
    }

    public int VertexCount { get { return v.Count; } }

    int Bone(Transform t)
    {
        if (t == null) t = root;
        int i;
        if (boneIndex.TryGetValue(t, out i)) return i;
        i = bones.Count;
        bones.Add(t);
        boneIndex[t] = i;
        return i;
    }

    // bone-local -> root space
    Matrix4x4 Place(Transform bone, Vector3 pos, Quaternion rot)
    {
        Matrix4x4 boneToRoot = root.worldToLocalMatrix * (bone != null ? bone.localToWorldMatrix : root.localToWorldMatrix);
        return boneToRoot * Matrix4x4.TRS(pos, rot, Vector3.one);
    }

    int Add(Vector3 p, Vector3 normal, Vector2 cell, BoneWeight bw)
    {
        v.Add(p);
        n.Add(normal.normalized);
        uv.Add(cell);
        w.Add(bw);
        return v.Count - 1;
    }

    static BoneWeight Rigid(int b)
    {
        return new BoneWeight { boneIndex0 = b, weight0 = 1f };
    }

    void Quad(int mat, int a, int b, int c, int d)
    {
        List<int> t = tris[Mathf.Clamp(mat, 0, 2)];
        t.Add(a); t.Add(b); t.Add(c);
        t.Add(a); t.Add(c); t.Add(d);
    }

    void Tri(int mat, int a, int b, int c)
    {
        List<int> t = tris[Mathf.Clamp(mat, 0, 2)];
        t.Add(a); t.Add(b); t.Add(c);
    }

    // ------------------------------------------------------------------
    //  Shapes (positions are in the bone's local space)
    // ------------------------------------------------------------------

    public void Ellipsoid(Transform bone, Vector3 pos, Vector3 radii, Color c, int mat = Matte, Quaternion rot = default(Quaternion))
    {
        if (rot.w == 0f && rot.x == 0f && rot.y == 0f && rot.z == 0f) rot = Quaternion.identity;
        Matrix4x4 m = Place(bone, pos, rot);
        BoneWeight bw = Rigid(Bone(bone));
        Vector2 cell = PaletteLib.UV(c);
        int seg = Detail, rings = Mathf.Max(6, Detail / 2 + 1);
        int start = v.Count;
        for (int i = 0; i <= rings; i++)
        {
            float th = Mathf.PI * i / rings;
            for (int j = 0; j <= seg; j++)
            {
                float ph = 2f * Mathf.PI * j / seg;
                Vector3 d = new Vector3(Mathf.Sin(th) * Mathf.Cos(ph), Mathf.Cos(th), Mathf.Sin(th) * Mathf.Sin(ph));
                Vector3 p = new Vector3(d.x * radii.x, d.y * radii.y, d.z * radii.z);
                Vector3 nn = new Vector3(d.x / radii.x, d.y / radii.y, d.z / radii.z);
                Add(m.MultiplyPoint3x4(p), m.MultiplyVector(nn), cell, bw);
            }
        }
        for (int i = 0; i < rings; i++)
            for (int j = 0; j < seg; j++)
            {
                int a = start + i * (seg + 1) + j, b = a + seg + 1;
                Quad(mat, a, a + 1, b + 1, b);
            }
    }

    // A shape turned around its Y axis: radius r[i] at height y[i] (bottom to top). sz squashes it front-to-back.
    public void Lathe(Transform bone, Vector3 pos, float[] r, float[] y, Color c, int mat = Matte,
                      Quaternion rot = default(Quaternion), float sz = 1f, bool capBottom = true, bool capTop = true, float sx = 1f)
    {
        if (rot.w == 0f && rot.x == 0f && rot.y == 0f && rot.z == 0f) rot = Quaternion.identity;
        Matrix4x4 m = Place(bone, pos, rot);
        BoneWeight bw = Rigid(Bone(bone));
        Vector2 cell = PaletteLib.UV(c);
        int seg = Detail;
        int start = v.Count;
        for (int i = 0; i < r.Length; i++)
        {
            // the profile's slope gives the normal
            int i0 = Mathf.Max(0, i - 1), i1 = Mathf.Min(r.Length - 1, i + 1);
            float dr = r[i1] - r[i0], dy = y[i1] - y[i0];
            Vector2 pn = new Vector2(dy, -dr).normalized;
            for (int j = 0; j <= seg; j++)
            {
                float ph = 2f * Mathf.PI * j / seg;
                float cs = Mathf.Cos(ph), sn = Mathf.Sin(ph);
                Vector3 p = new Vector3(cs * r[i] * sx, y[i], sn * r[i] * sz);
                Vector3 nn = new Vector3(cs * pn.x / sx, pn.y, sn * pn.x / sz);
                Add(m.MultiplyPoint3x4(p), m.MultiplyVector(nn), cell, bw);
            }
        }
        for (int i = 0; i < r.Length - 1; i++)
            for (int j = 0; j < seg; j++)
            {
                int a = start + i * (seg + 1) + j, b = a + seg + 1;
                Quad(mat, a, b, b + 1, a + 1);
            }
        if (capBottom && r[0] > 0.0001f) Cap(m, bw, cell, mat, r[0], y[0], sx, sz, false);
        if (capTop && r[r.Length - 1] > 0.0001f) Cap(m, bw, cell, mat, r[r.Length - 1], y[y.Length - 1], sx, sz, true);
    }

    void Cap(Matrix4x4 m, BoneWeight bw, Vector2 cell, int mat, float r, float y, float sx, float sz, bool top)
    {
        Vector3 up = top ? Vector3.up : Vector3.down;
        int centre = Add(m.MultiplyPoint3x4(new Vector3(0f, y, 0f)), m.MultiplyVector(up), cell, bw);
        int start = v.Count;
        for (int j = 0; j <= Detail; j++)
        {
            float ph = 2f * Mathf.PI * j / Detail;
            Add(m.MultiplyPoint3x4(new Vector3(Mathf.Cos(ph) * r * sx, y, Mathf.Sin(ph) * r * sz)), m.MultiplyVector(up), cell, bw);
        }
        for (int j = 0; j < Detail; j++)
        {
            if (top) Tri(mat, centre, start + j + 1, start + j);
            else Tri(mat, centre, start + j, start + j + 1);
        }
    }

    // A ring (belts, crowns, rims). arc < 360 makes an open arc (a bow).
    public void Torus(Transform bone, Vector3 pos, float R, float r, Color c, int mat = Matte,
                      Quaternion rot = default(Quaternion), float sz = 1f, float arc = 360f)
    {
        if (rot.w == 0f && rot.x == 0f && rot.y == 0f && rot.z == 0f) rot = Quaternion.identity;
        Matrix4x4 m = Place(bone, pos, rot);
        BoneWeight bw = Rigid(Bone(bone));
        Vector2 cell = PaletteLib.UV(c);
        int segR = Detail + 4, segr = Mathf.Max(6, Detail / 2);
        int start = v.Count;
        for (int i = 0; i <= segR; i++)
        {
            float a = arc * Mathf.Deg2Rad * i / segR;
            Vector3 dir = new Vector3(Mathf.Cos(a), 0f, Mathf.Sin(a) * sz);
            for (int j = 0; j <= segr; j++)
            {
                float b = 2f * Mathf.PI * j / segr;
                Vector3 nn = dir.normalized * Mathf.Cos(b) + Vector3.up * Mathf.Sin(b);
                Vector3 p = dir * R + nn * r;
                Add(m.MultiplyPoint3x4(p), m.MultiplyVector(nn), cell, bw);
            }
        }
        for (int i = 0; i < segR; i++)
            for (int j = 0; j < segr; j++)
            {
                int a = start + i * (segr + 1) + j, b = a + segr + 1;
                Quad(mat, a, a + 1, b + 1, b);
            }
    }

    // A box with soft, rounded edges (a superellipsoid): roundness 0 = almost a box, 1 = an ellipsoid.
    public void RoundBox(Transform bone, Vector3 pos, Vector3 size, Color c, int mat = Matte,
                         Quaternion rot = default(Quaternion), float roundness = 0.35f)
    {
        if (rot.w == 0f && rot.x == 0f && rot.y == 0f && rot.z == 0f) rot = Quaternion.identity;
        Matrix4x4 m = Place(bone, pos, rot);
        BoneWeight bw = Rigid(Bone(bone));
        Vector2 cell = PaletteLib.UV(c);
        Vector3 h = size * 0.5f;
        float e = Mathf.Lerp(0.18f, 1f, Mathf.Clamp01(roundness));
        int seg = Detail, rings = Mathf.Max(6, Detail / 2 + 1);
        int start = v.Count;
        for (int i = 0; i <= rings; i++)
        {
            float th = Mathf.PI * i / rings;
            for (int j = 0; j <= seg; j++)
            {
                float ph = 2f * Mathf.PI * j / seg;
                Vector3 d = new Vector3(Mathf.Sin(th) * Mathf.Cos(ph), Mathf.Cos(th), Mathf.Sin(th) * Mathf.Sin(ph));
                Vector3 s = new Vector3(SPow(d.x, e), SPow(d.y, e), SPow(d.z, e));
                Vector3 p = new Vector3(s.x * h.x, s.y * h.y, s.z * h.z);
                Vector3 nn = new Vector3(SPow(d.x, 2f - e) / h.x, SPow(d.y, 2f - e) / h.y, SPow(d.z, 2f - e) / h.z);
                Add(m.MultiplyPoint3x4(p), m.MultiplyVector(nn), cell, bw);
            }
        }
        for (int i = 0; i < rings; i++)
            for (int j = 0; j < seg; j++)
            {
                int a = start + i * (seg + 1) + j, b = a + seg + 1;
                Quad(mat, a, a + 1, b + 1, b);
            }
    }

    static float SPow(float x, float e)
    {
        return Mathf.Sign(x) * Mathf.Pow(Mathf.Abs(x), e);
    }

    // A smooth limb from 'a' through a joint to 'end' (root space, the bind pose), skinned to two bones:
    // the part around the joint follows both, so the knee or elbow bends without a gap.
    public void Limb(Transform upper, Transform lower, Vector3 a, Vector3 joint, Vector3 end,
                     float rA, float rJ, float rE, Color c, int mat = Matte)
    {
        int bu = Bone(upper), bl = Bone(lower);
        Vector2 cell = PaletteLib.UV(c);
        float lenA = Vector3.Distance(a, joint), lenB = Vector3.Distance(joint, end);
        float total = lenA + lenB, tj = lenA / total;
        int rings = Mathf.Max(8, Detail), seg = Detail;
        int start = v.Count;
        for (int i = 0; i <= rings; i++)
        {
            float t = i / (float)rings;
            Vector3 p = t < tj ? Vector3.Lerp(a, joint, t / tj) : Vector3.Lerp(joint, end, (t - tj) / (1f - tj));
            Vector3 dir = (t < tj ? joint - a : end - joint).normalized;
            float rad = t < tj ? Mathf.Lerp(rA, rJ, t / tj) : Mathf.Lerp(rJ, rE, (t - tj) / (1f - tj));
            // muscles: a little thicker in the middle of each part
            rad *= 1f + 0.12f * Mathf.Sin(Mathf.PI * (t < tj ? t / tj : (t - tj) / (1f - tj)));
            Vector3 side = Vector3.Cross(dir, Vector3.forward);
            if (side.sqrMagnitude < 0.01f) side = Vector3.right;
            side.Normalize();
            Vector3 fwd = Vector3.Cross(side, dir).normalized;

            // weight: fully the upper bone above the joint area, fully the lower below it, blended in between
            float blend = Mathf.Clamp01((t - (tj - 0.12f)) / 0.24f);
            blend = blend * blend * (3f - 2f * blend);
            BoneWeight bw = new BoneWeight { boneIndex0 = bu, weight0 = 1f - blend, boneIndex1 = bl, weight1 = blend };

            for (int j = 0; j <= seg; j++)
            {
                float ph = 2f * Mathf.PI * j / seg;
                Vector3 nn = side * Mathf.Cos(ph) + fwd * Mathf.Sin(ph);
                Add(p + nn * rad, nn, cell, bw);
            }
        }
        for (int i = 0; i < rings; i++)
            for (int j = 0; j < seg; j++)
            {
                int q0 = start + i * (seg + 1) + j, q1 = q0 + seg + 1;
                Quad(mat, q0, q1, q1 + 1, q0 + 1);
            }
        // round ends
        EndCap(a, (a - joint).normalized, rA, bu, cell, mat);
        EndCap(end, (end - joint).normalized, rE, bl, cell, mat);
    }

    void EndCap(Vector3 centre, Vector3 outward, float r, int bone, Vector2 cell, int mat)
    {
        Quaternion q = Quaternion.FromToRotation(Vector3.up, outward);
        Matrix4x4 m = root.worldToLocalMatrix * root.localToWorldMatrix * Matrix4x4.TRS(centre, q, Vector3.one);
        BoneWeight bw = Rigid(bone);
        int seg = Detail, rings = Mathf.Max(3, Detail / 4);
        int start = v.Count;
        for (int i = 0; i <= rings; i++)
        {
            float th = (Mathf.PI * 0.5f) * i / rings;
            for (int j = 0; j <= seg; j++)
            {
                float ph = 2f * Mathf.PI * j / seg;
                Vector3 d = new Vector3(Mathf.Sin(th) * Mathf.Cos(ph), Mathf.Cos(th), Mathf.Sin(th) * Mathf.Sin(ph));
                Add(m.MultiplyPoint3x4(d * r), m.MultiplyVector(d), cell, bw);
            }
        }
        for (int i = 0; i < rings; i++)
            for (int j = 0; j < seg; j++)
            {
                int a = start + i * (seg + 1) + j, b = a + seg + 1;
                Quad(mat, a, a + 1, b + 1, b);
            }
    }

    // A soft cloth (cape) hanging from 'top' bone; the lower half follows 'bottom'. Visible from both sides.
    public void Cloth(Transform top, Transform bottom, Vector3 topLeft, Vector3 topRight, float length, float bulge, Color c)
    {
        int bt = Bone(top), bb = Bone(bottom);
        Vector2 cell = PaletteLib.UV(c);
        int cols = 6, rows = 8;
        int start = v.Count;
        for (int pass = 0; pass < 2; pass++)
        {
            int baseIndex = v.Count;
            for (int i = 0; i <= rows; i++)
            {
                float t = i / (float)rows;
                float blend = Mathf.Clamp01((t - 0.35f) / 0.3f);
                BoneWeight bw = new BoneWeight { boneIndex0 = bt, weight0 = 1f - blend, boneIndex1 = bb, weight1 = blend };
                for (int j = 0; j <= cols; j++)
                {
                    float s = j / (float)cols;
                    Vector3 p = Vector3.Lerp(topLeft, topRight, s) * (1f + t * 0.25f) + Vector3.down * (length * t);
                    p.x = Mathf.Lerp(topLeft.x, topRight.x, s) * (1f + t * 0.3f);
                    p.z -= Mathf.Sin(s * Mathf.PI) * bulge * (0.5f + t * 0.5f) + t * 0.05f;
                    Vector3 nn = pass == 0 ? Vector3.forward : Vector3.back;   // matches the winding of each side
                    Add(p, nn, cell, bw);
                }
            }
            for (int i = 0; i < rows; i++)
                for (int j = 0; j < cols; j++)
                {
                    int a = baseIndex + i * (cols + 1) + j, b = a + cols + 1;
                    if (pass == 0) Quad(Matte, a, b, b + 1, a + 1);
                    else Quad(Matte, a, a + 1, b + 1, b);
                }
        }
        _ = start;
    }

    // ------------------------------------------------------------------
    //  Output
    // ------------------------------------------------------------------

    Mesh MakeMesh(string name)
    {
        Mesh mesh = new Mesh();
        mesh.name = name;
        if (v.Count > 65000) mesh.indexFormat = IndexFormat.UInt32;
        mesh.SetVertices(v);
        mesh.SetNormals(n);
        mesh.SetUVs(0, uv);
        mesh.subMeshCount = 3;
        for (int i = 0; i < 3; i++) mesh.SetTriangles(tris[i], i);
        return mesh;
    }

    // One skinned mesh for the whole character: one renderer, three materials.
    public SkinnedMeshRenderer BuildSkinned(GameObject host, Transform rootBone, string name)
    {
        Mesh mesh = MakeMesh(name);
        mesh.boneWeights = w.ToArray();
        Matrix4x4[] bind = new Matrix4x4[bones.Count];
        for (int i = 0; i < bones.Count; i++) bind[i] = bones[i].worldToLocalMatrix * root.localToWorldMatrix;
        mesh.bindposes = bind;
        mesh.RecalculateBounds();

        SkinnedMeshRenderer smr = host.AddComponent<SkinnedMeshRenderer>();
        smr.sharedMesh = mesh;
        smr.bones = bones.ToArray();
        smr.rootBone = rootBone;
        smr.quality = SkinQuality.Bone2;
        smr.sharedMaterials = PaletteLib.Materials();
        Bounds b = mesh.bounds;
        b.Expand(1.2f);
        smr.localBounds = new Bounds(rootBone != null ? rootBone.InverseTransformPoint(root.TransformPoint(b.center)) : b.center, b.size);
        return smr;
    }

    // A still mesh (mountains, terrain) with the palette materials.
    public GameObject BuildStatic(Transform parent, string name)
    {
        GameObject go = new GameObject(name);
        go.transform.SetParent(parent, false);
        go.AddComponent<MeshFilter>().sharedMesh = MakeMesh(name);
        go.AddComponent<MeshRenderer>().sharedMaterials = PaletteLib.Materials();
        return go;
    }
}
