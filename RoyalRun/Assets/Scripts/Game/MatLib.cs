using System.Collections.Generic;
using UnityEngine;

// Materials created from code. The base is the default material of a primitive (Cube):
// in the built-in render pipeline it is the Standard shader, in URP - URP/Lit.
// Each material gets a procedural texture and normal map (TextureLib) for its surface type,
// so things look like stone, wood, grass or cloth instead of plastic.
public static class MatLib
{
    static Material baseMaterial;
    static readonly Dictionary<string, Material> cache = new Dictionary<string, Material>();

    static readonly int ColorId = Shader.PropertyToID("_Color");
    static readonly int BaseColorId = Shader.PropertyToID("_BaseColor");
    static readonly int GlossId = Shader.PropertyToID("_Glossiness");
    static readonly int SmoothId = Shader.PropertyToID("_Smoothness");
    static readonly int MetallicId = Shader.PropertyToID("_Metallic");
    static readonly int EmissionId = Shader.PropertyToID("_EmissionColor");
    static readonly int MainTexId = Shader.PropertyToID("_MainTex");
    static readonly int BaseMapId = Shader.PropertyToID("_BaseMap");
    static readonly int BumpMapId = Shader.PropertyToID("_BumpMap");
    static readonly int BumpScaleId = Shader.PropertyToID("_BumpScale");

    static Material Base
    {
        get
        {
            if (baseMaterial == null)
            {
                GameObject probe = GameObject.CreatePrimitive(PrimitiveType.Cube);
                probe.SetActive(false);
                baseMaterial = probe.GetComponent<Renderer>().sharedMaterial;
                Object.Destroy(probe);
            }
            return baseMaterial;
        }
    }

    // A material of the given colour. Identical requests return the same material (it is shared).
    public static Material Get(Color color, float smoothness = 0.15f, float emission = 0f)
    {
        return Get(color, smoothness, emission, Surface.Grime, Vector2.one);
    }

    public static Material Get(Color color, float smoothness, float emission, Surface surface, Vector2 tiling)
    {
        color.a = 1f;
        float sm = TextureLib.Smoothness(surface);
        if (sm < 0f) sm = smoothness;
        tiling = new Vector2(Mathf.Max(1f, Mathf.Round(tiling.x * 2f) * 0.5f), Mathf.Max(1f, Mathf.Round(tiling.y * 2f) * 0.5f));

        string key = ColorUtility.ToHtmlStringRGB(color) + "|" + sm.ToString("F2") + "|" + emission.ToString("F2")
                     + "|" + surface + "|" + tiling.x + "x" + tiling.y;
        Material m;
        if (cache.TryGetValue(key, out m) && m != null) return m;

        m = new Material(Base);
        m.name = "RR " + key;
        if (m.HasProperty(ColorId)) m.SetColor(ColorId, color);
        if (m.HasProperty(BaseColorId)) m.SetColor(BaseColorId, color);
        if (m.HasProperty(GlossId)) m.SetFloat(GlossId, sm);
        if (m.HasProperty(SmoothId)) m.SetFloat(SmoothId, sm);
        if (m.HasProperty(MetallicId)) m.SetFloat(MetallicId, surface == Surface.Metal ? 0.55f : 0f);

        Texture2D tex = TextureLib.Albedo(surface);
        if (tex != null)
        {
            if (m.HasProperty(MainTexId)) { m.SetTexture(MainTexId, tex); m.SetTextureScale(MainTexId, tiling); }
            if (m.HasProperty(BaseMapId)) { m.SetTexture(BaseMapId, tex); m.SetTextureScale(BaseMapId, tiling); }
            if (m.HasProperty(BumpMapId))
            {
                m.SetTexture(BumpMapId, TextureLib.Normal(surface));
                if (m.HasProperty(BumpScaleId)) m.SetFloat(BumpScaleId, 1f);
                m.EnableKeyword("_NORMALMAP");
            }
        }

        if (emission > 0f && m.HasProperty(EmissionId))
        {
            m.EnableKeyword("_EMISSION");
            m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
            m.SetColor(EmissionId, color * emission);
        }
        cache[key] = m;
        return m;
    }

    // A primitive with a colour. The collider is removed unless asked for.
    // The texture repeats according to the object's real size (a long fence gets more planks, not stretched ones).
    public static GameObject Prim(PrimitiveType type, string name, Transform parent,
                                  Vector3 localPos, Vector3 localScale, Color color,
                                  bool keepCollider = false, Vector3 euler = default(Vector3),
                                  float smoothness = 0.15f, float emission = 0f, Surface surface = Surface.Grime,
                                  Vector2 tilingOverride = default(Vector2))
    {
        GameObject go = GameObject.CreatePrimitive(type);
        go.name = name;
        if (!keepCollider)
        {
            Collider c = go.GetComponent<Collider>();
            if (c != null) Object.DestroyImmediate(c);
        }
        go.transform.SetParent(parent, false);
        go.transform.localPosition = localPos;
        go.transform.localRotation = Quaternion.Euler(euler);
        go.transform.localScale = localScale;

        Renderer r = go.GetComponent<Renderer>();
        Vector2 tiling = tilingOverride != Vector2.zero ? tilingOverride : Tiling(go.transform.lossyScale, type, surface);
        r.sharedMaterial = Get(color, smoothness, emission, surface, tiling);
        return go;
    }

    static Vector2 Tiling(Vector3 size, PrimitiveType type, Surface surface)
    {
        if (surface == Surface.Plain) return Vector2.one;
        float tile = TextureLib.TileSize(surface);
        float x = Mathf.Abs(size.x), y = Mathf.Abs(size.y), z = Mathf.Abs(size.z);
        switch (type)
        {
            case PrimitiveType.Cube:
            {
                // the two largest sides decide the repeat (good for floors, walls and planks)
                float a = Mathf.Max(x, Mathf.Max(y, z));
                float b = x + y + z - a - Mathf.Min(x, Mathf.Min(y, z));
                return new Vector2(a / tile, b / tile);
            }
            case PrimitiveType.Cylinder:
            case PrimitiveType.Capsule:
                return new Vector2(Mathf.PI * Mathf.Max(x, z) / tile, 2f * y / tile);
            default:
                return new Vector2(Mathf.PI * Mathf.Max(x, z) / tile, Mathf.Max(y, Mathf.Max(x, z)) / tile);
        }
    }
}
