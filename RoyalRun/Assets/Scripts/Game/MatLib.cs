using System.Collections.Generic;
using UnityEngine;

// Materials created from code. The base is the default material of a primitive (Cube):
// in the built-in render pipeline it is the Standard shader, in URP - URP/Lit.
// So the colours work in either pipeline, and no material files are needed in the project.
public static class MatLib
{
    static Material baseMaterial;
    static readonly Dictionary<string, Material> cache = new Dictionary<string, Material>();

    static readonly int ColorId = Shader.PropertyToID("_Color");
    static readonly int BaseColorId = Shader.PropertyToID("_BaseColor");
    static readonly int GlossId = Shader.PropertyToID("_Glossiness");
    static readonly int SmoothId = Shader.PropertyToID("_Smoothness");
    static readonly int EmissionId = Shader.PropertyToID("_EmissionColor");

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
        color.a = 1f;
        string key = ColorUtility.ToHtmlStringRGB(color) + "|" + smoothness.ToString("F2") + "|" + emission.ToString("F2");
        Material m;
        if (cache.TryGetValue(key, out m) && m != null) return m;

        m = new Material(Base);
        m.name = "RR " + key;
        if (m.HasProperty(ColorId)) m.SetColor(ColorId, color);
        if (m.HasProperty(BaseColorId)) m.SetColor(BaseColorId, color);
        if (m.HasProperty(GlossId)) m.SetFloat(GlossId, smoothness);
        if (m.HasProperty(SmoothId)) m.SetFloat(SmoothId, smoothness);
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
    public static GameObject Prim(PrimitiveType type, string name, Transform parent,
                                  Vector3 localPos, Vector3 localScale, Color color,
                                  bool keepCollider = false, Vector3 euler = default(Vector3),
                                  float smoothness = 0.15f, float emission = 0f)
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
        r.sharedMaterial = Get(color, smoothness, emission);
        return go;
    }
}
