using System.Collections.Generic;
using UnityEngine;

// Surface types. Each one has a seamless (tileable) colour texture and a normal map,
// generated in code at start-up - the project still needs no image files.
public enum Surface { Plain, Grime, Road, Grass, Wood, Bark, Stone, Bricks, Leaves, Metal, Fabric, Skin }

// Procedural textures: cobblestones (Voronoi cells), grass, wood planks with grain, bark, bricks,
// rock, leaves, brushed metal, woven fabric and a subtle "grime" for everything else.
// The colour textures are mostly grey: the material colour tints them (so one grass texture serves
// green meadows, the autumn forest and snow).
public static class TextureLib
{
    // Phones: smaller textures and no normal maps (faster to build and to draw).
    public static bool Lite;

    static readonly Dictionary<Surface, Texture2D> albedo = new Dictionary<Surface, Texture2D>();
    static readonly Dictionary<Surface, Texture2D> normals = new Dictionary<Surface, Texture2D>();

    // metres covered by one repeat of the texture
    public static float TileSize(Surface s)
    {
        switch (s)
        {
            case Surface.Road: return 3f;
            case Surface.Grass: return 2.5f;
            case Surface.Wood: return 1.2f;
            case Surface.Bark: return 1.2f;
            case Surface.Stone: return 1.5f;
            case Surface.Bricks: return 2f;
            case Surface.Leaves: return 1.2f;
            case Surface.Metal: return 1f;
            case Surface.Fabric: return 0.6f;
            default: return 2f;
        }
    }

    // How rough the surface looks (Standard shader smoothness), -1 = keep the value asked for.
    public static float Smoothness(Surface s)
    {
        switch (s)
        {
            case Surface.Road: return 0.18f;
            case Surface.Grass: return 0.04f;
            case Surface.Wood: return 0.1f;
            case Surface.Bark: return 0.03f;
            case Surface.Stone: return 0.08f;
            case Surface.Bricks: return 0.06f;
            case Surface.Leaves: return 0.08f;
            case Surface.Fabric: return 0.03f;
            case Surface.Skin: return 0.3f;
            default: return -1f;
        }
    }

    public static float NormalStrength(Surface s)
    {
        switch (s)
        {
            case Surface.Road: return 1.2f;
            case Surface.Bricks: return 1.1f;
            case Surface.Bark: return 1.2f;
            case Surface.Stone: return 1f;
            case Surface.Wood: return 0.7f;
            case Surface.Leaves: return 0.9f;
            case Surface.Grass: return 0.6f;
            case Surface.Fabric: return 0.5f;
            default: return 0.35f;
        }
    }

    public static Texture2D Albedo(Surface s)
    {
        if (s == Surface.Plain) return null;
        Texture2D t;
        if (!albedo.TryGetValue(s, out t) || t == null) { Build(s); t = albedo[s]; }
        return t;
    }

    public static Texture2D Normal(Surface s)
    {
        if (s == Surface.Plain) return null;
        Texture2D t;
        if (!normals.TryGetValue(s, out t) || t == null) { Build(s); t = normals[s]; }
        return t;
    }

    // ------------------------------------------------------------------
    //  Building one surface
    // ------------------------------------------------------------------

    static void Build(Surface s)
    {
        int n = Lite ? (s == Surface.Road ? 256 : 128) : (s == Surface.Road ? 512 : 256);
        float[] h = new float[n * n];      // height, for the normal map
        Color[] c = new Color[n * n];

        for (int y = 0; y < n; y++)
        {
            float v = y / (float)n;
            for (int x = 0; x < n; x++)
            {
                float u = x / (float)n;
                float height, lum;
                Color tint = Color.white;
                Pixel(s, u, v, out height, out lum, ref tint);
                h[y * n + x] = height;
                c[y * n + x] = new Color(Mathf.Clamp01(lum * tint.r), Mathf.Clamp01(lum * tint.g), Mathf.Clamp01(lum * tint.b), 1f);
            }
        }

        Texture2D a = new Texture2D(n, n, TextureFormat.RGBA32, true);
        a.name = "RR " + s;
        a.wrapMode = TextureWrapMode.Repeat;
        a.filterMode = FilterMode.Trilinear;
        a.anisoLevel = 4;
        a.SetPixels(c);
        a.Apply(true);
        albedo[s] = a;
        normals[s] = NormalMap(h, n, s);
    }

    static void Pixel(Surface s, float u, float v, out float height, out float lum, ref Color tint)
    {
        switch (s)
        {
            case Surface.Road:
            {
                // cobblestones: Voronoi cells = stones, the narrow gaps between them = mortar
                float f1, f2; int id;
                Voronoi(u, v, 9, 11, out f1, out f2, out id);
                float edge = f2 - f1;
                float stone = Step(0.02f, 0.13f, edge);
                float dome = 1f - Mathf.Clamp01(f1 * 1.6f);
                float detail = Fbm(u, v, 16, 4, 3);
                float r = Hash(id, 7, 1);
                lum = Mathf.Lerp(0.28f, 0.62f + 0.3f * r + (detail - 0.5f) * 0.25f, stone);
                tint = Color.Lerp(new Color(0.85f, 0.8f, 0.72f), new Color(1f, 1f, 1.04f), Hash(id, 3, 2));
                if (stone < 0.5f) tint = new Color(0.8f, 0.72f, 0.6f);
                height = stone * (0.5f + 0.5f * dome) + detail * 0.15f;
                break;
            }
            case Surface.Grass:
            {
                float big = Fbm(u, v, 4, 3, 21);
                float blades = Noise(u * 96f, v * 24f, 96, 24, 22);
                float fine = Noise(u * 128f, v * 128f, 128, 128, 23);
                lum = 0.72f + big * 0.35f + (blades - 0.5f) * 0.3f + (fine - 0.5f) * 0.12f;
                // a few slightly yellow patches
                tint = Color.Lerp(Color.white, new Color(1.05f, 1.03f, 0.88f), Mathf.Clamp01((big - 0.55f) * 2f));
                height = blades * 0.7f + fine * 0.3f;
                break;
            }
            case Surface.Wood:
            {
                // 4 planks across, grain along u, a dark seam between planks
                float plankF = v * 4f;
                int plank = Mathf.FloorToInt(plankF);
                float pv = plankF - plank;
                float warp = Fbm(u, v, 4, 3, 31 + plank) * 6f;
                float grain = Mathf.Sin((v * 4f * 9f + warp) * Mathf.PI * 2f) * 0.5f + 0.5f;
                float knot = Mathf.Clamp01(1f - Vector2.Distance(new Vector2(Mathf.Repeat(u + Hash(plank, 1, 32), 1f), pv), new Vector2(0.5f, 0.5f)) * 6f);
                float seam = Step(0f, 0.05f, Mathf.Min(pv, 1f - pv));
                lum = (0.68f + 0.18f * Hash(plank, 5, 33) + grain * 0.16f - knot * 0.35f) * Mathf.Lerp(0.35f, 1f, seam);
                height = seam * (0.6f + grain * 0.25f) - knot * 0.2f;
                break;
            }
            case Surface.Bark:
            {
                float warp = Fbm(u, v, 4, 3, 41) * 3f;
                float ridges = Mathf.Abs(Mathf.Sin((u * 10f + warp) * Mathf.PI));
                float cracks = Noise(u * 10f, v * 3f, 10, 3, 42);
                lum = 0.45f + ridges * 0.55f - cracks * 0.15f;
                height = ridges * 0.8f + cracks * 0.2f;
                break;
            }
            case Surface.Bricks:
            {
                const int rows = 8, cols = 4;
                float rv = v * rows;
                int row = Mathf.FloorToInt(rv);
                float ru = u * cols + (row % 2 == 0 ? 0f : 0.5f);
                int col = Mathf.FloorToInt(ru);
                float bu = ru - col, bv = rv - row;
                float m = Mathf.Min(Mathf.Min(bu, 1f - bu) * 2f, Mathf.Min(bv, 1f - bv));
                float brick = Step(0.03f, 0.09f, m);
                float detail = Fbm(u, v, 16, 4, 51);
                float r = Hash((col % cols + cols) % cols, row, 52);
                lum = Mathf.Lerp(0.42f, 0.7f + r * 0.3f + (detail - 0.5f) * 0.3f, brick);
                height = brick * (0.8f + detail * 0.2f);
                break;
            }
            case Surface.Stone:
            {
                float f1, f2; int id;
                Voronoi(u, v, 5, 61, out f1, out f2, out id);
                float crack = 1f - Step(0f, 0.025f, f2 - f1);
                float detail = Fbm(u, v, 8, 5, 62);
                lum = 0.48f + detail * 0.6f - crack * 0.45f + Hash(id, 1, 63) * 0.12f;
                height = detail - crack * 0.5f;
                break;
            }
            case Surface.Leaves:
            {
                float f1, f2; int id;
                Voronoi(u, v, 20, 71, out f1, out f2, out id);
                float leaf = Step(0f, 0.12f, f2 - f1);
                float r = Hash(id, 2, 72);
                lum = Mathf.Lerp(0.35f, 0.68f + r * 0.38f, leaf) * (0.85f + 0.3f * Fbm(u, v, 4, 2, 73));
                tint = Color.Lerp(Color.white, new Color(1.05f, 1.05f, 0.9f), r * 0.4f);
                height = leaf * (1f - f1);
                break;
            }
            case Surface.Metal:
            {
                float brushed = Noise(u * 4f, v * 128f, 4, 128, 81);
                float spots = Fbm(u, v, 8, 3, 82);
                lum = 0.85f + (brushed - 0.5f) * 0.12f - Mathf.Clamp01(spots - 0.65f) * 0.6f;
                height = brushed * 0.3f;
                break;
            }
            case Surface.Fabric:
            {
                float wu = Mathf.Sin(u * Mathf.PI * 2f * 48f), wv = Mathf.Sin(v * Mathf.PI * 2f * 48f);
                float weave = (wu * wv) * 0.5f + 0.5f;
                float detail = Fbm(u, v, 8, 3, 91);
                lum = 0.86f + weave * 0.1f + (detail - 0.5f) * 0.12f;
                height = weave;
                break;
            }
            case Surface.Skin:
            {
                float d = Fbm(u, v, 16, 3, 101);
                lum = 0.96f + (d - 0.5f) * 0.06f;
                height = d * 0.2f;
                break;
            }
            default: // Grime: gentle dirt and wear on painted and plain things
            {
                float d = Fbm(u, v, 8, 4, 111);
                float speck = Noise(u * 128f, v * 128f, 128, 128, 112);
                lum = 0.8f + d * 0.22f - Mathf.Clamp01(speck - 0.8f) * 0.4f;
                height = d * 0.5f + speck * 0.1f;
                break;
            }
        }
    }

    // ------------------------------------------------------------------
    //  Noise helpers. All of them repeat with period 1 in u and v, so the textures tile without seams.
    // ------------------------------------------------------------------

    static float Hash(int x, int y, int seed)
    {
        unchecked
        {
            uint h = (uint)(x * 374761393 + y * 668265263 + seed * 1442695041);
            h = (h ^ (h >> 13)) * 1274126177u;
            h ^= h >> 16;
            return (h & 0xFFFFFF) / 16777215f;
        }
    }

    // Value noise with the lattice wrapped every (px, py) cells.
    static float Noise(float x, float y, int px, int py, int seed)
    {
        int x0 = Mathf.FloorToInt(x), y0 = Mathf.FloorToInt(y);
        float fx = x - x0, fy = y - y0;
        fx = fx * fx * (3f - 2f * fx);
        fy = fy * fy * (3f - 2f * fy);
        int xa = Wrap(x0, px), xb = Wrap(x0 + 1, px), ya = Wrap(y0, py), yb = Wrap(y0 + 1, py);
        float a = Hash(xa, ya, seed), b = Hash(xb, ya, seed), c = Hash(xa, yb, seed), d = Hash(xb, yb, seed);
        return Mathf.Lerp(Mathf.Lerp(a, b, fx), Mathf.Lerp(c, d, fx), fy);
    }

    static float Fbm(float u, float v, int basePeriod, int octaves, int seed)
    {
        float sum = 0f, amp = 0.5f, norm = 0f;
        int p = basePeriod;
        for (int o = 0; o < octaves; o++)
        {
            sum += Noise(u * p, v * p, p, p, seed + o * 13) * amp;
            norm += amp;
            amp *= 0.5f;
            p *= 2;
        }
        return sum / norm;
    }

    // Distances to the nearest (f1) and second nearest (f2) cell point, in cell units; id = nearest cell.
    static void Voronoi(float u, float v, int cells, int seed, out float f1, out float f2, out int id)
    {
        float x = u * cells, y = v * cells;
        int cx = Mathf.FloorToInt(x), cy = Mathf.FloorToInt(y);
        f1 = 9f; f2 = 9f; id = 0;
        for (int dy = -1; dy <= 1; dy++)
        {
            for (int dx = -1; dx <= 1; dx++)
            {
                int gx = cx + dx, gy = cy + dy;
                int wx = Wrap(gx, cells), wy = Wrap(gy, cells);
                float px = gx + 0.15f + 0.7f * Hash(wx, wy, seed);
                float py = gy + 0.15f + 0.7f * Hash(wx, wy, seed + 1);
                float d = Mathf.Sqrt((px - x) * (px - x) + (py - y) * (py - y));
                if (d < f1) { f2 = f1; f1 = d; id = wy * cells + wx; }
                else if (d < f2) f2 = d;
            }
        }
    }

    // GLSL-style smoothstep: 0 below e0, 1 above e1, smooth in between.
    // (Unity's Mathf.SmoothStep is different: it interpolates between two values.)
    static float Step(float e0, float e1, float x)
    {
        float t = Mathf.Clamp01((x - e0) / (e1 - e0));
        return t * t * (3f - 2f * t);
    }

    static int Wrap(int i, int p)
    {
        int r = i % p;
        return r < 0 ? r + p : r;
    }

    // A normal map from the height field. Stored as (x, y, z) in RGB with A = 1:
    // the built-in shaders read both this layout and the compressed one.
    static Texture2D NormalMap(float[] h, int n, Surface s)
    {
        float strength = 6f * NormalStrength(s);
        Color[] c = new Color[n * n];
        for (int y = 0; y < n; y++)
        {
            for (int x = 0; x < n; x++)
            {
                float l = h[y * n + Wrap(x - 1, n)], r = h[y * n + Wrap(x + 1, n)];
                float d = h[Wrap(y - 1, n) * n + x], u = h[Wrap(y + 1, n) * n + x];
                Vector3 nn = new Vector3((l - r) * strength, (d - u) * strength, 1f).normalized;
                c[y * n + x] = new Color(nn.x * 0.5f + 0.5f, nn.y * 0.5f + 0.5f, nn.z * 0.5f + 0.5f, 1f);
            }
        }
        Texture2D t = new Texture2D(n, n, TextureFormat.RGBA32, true, true);   // linear: it is data, not a colour
        t.name = "RR " + s + " Normal";
        t.wrapMode = TextureWrapMode.Repeat;
        t.filterMode = FilterMode.Trilinear;
        t.anisoLevel = 4;
        t.SetPixels(c);
        t.Apply(true);
        return t;
    }
}
