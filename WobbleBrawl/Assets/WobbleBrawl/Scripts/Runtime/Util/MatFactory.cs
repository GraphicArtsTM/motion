using System.Collections.Generic;
using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>
    /// Creates materials at runtime without shipping any shader assets. The base lit material is
    /// taken from a primitive, which gives the active pipeline's default (Standard or URP Lit),
    /// so the project renders in both the Built-in pipeline and URP.
    /// </summary>
    public static class MatFactory
    {
        static Material baseLit;
        static Material baseUnlit;
        static readonly Dictionary<long, Material> cache = new Dictionary<long, Material>();
        static readonly Dictionary<PrimitiveType, Mesh> meshes = new Dictionary<PrimitiveType, Mesh>();

        public static Mesh Mesh(PrimitiveType type)
        {
            if (meshes.TryGetValue(type, out var m) && m != null) return m;
            var tmp = GameObject.CreatePrimitive(type);
            m = tmp.GetComponent<MeshFilter>().sharedMesh;
            if (baseLit == null) baseLit = tmp.GetComponent<Renderer>().sharedMaterial;
            Object.Destroy(tmp);
            meshes[type] = m;
            return m;
        }

        static Material BaseLit
        {
            get
            {
                if (baseLit == null) Mesh(PrimitiveType.Cube);
                return baseLit;
            }
        }

        static long Key(Color c, float smooth, float emission, int kind)
        {
            Color32 k = c;
            long key = k.r | ((long)k.g << 8) | ((long)k.b << 16) | ((long)k.a << 24);
            key |= (long)Mathf.RoundToInt(smooth * 20f) << 32;
            key |= (long)Mathf.RoundToInt(emission * 10f) << 40;
            key |= (long)kind << 52;
            return key;
        }

        public static Material Lit(Color c, float smoothness = 0.2f, float emission = 0f)
        {
            long key = Key(c, smoothness, emission, 0);
            if (cache.TryGetValue(key, out var mat) && mat != null) return mat;
            mat = new Material(BaseLit) { name = "WB_Lit_" + Palette.Hex(c), enableInstancing = true };
            mat.color = c;
            if (mat.HasProperty("_BaseColor")) mat.SetColor("_BaseColor", c);
            if (mat.HasProperty("_Color")) mat.SetColor("_Color", c);
            if (mat.HasProperty("_Glossiness")) mat.SetFloat("_Glossiness", smoothness);
            if (mat.HasProperty("_Smoothness")) mat.SetFloat("_Smoothness", smoothness);
            if (mat.HasProperty("_Metallic")) mat.SetFloat("_Metallic", 0f);
            if (emission > 0f && mat.HasProperty("_EmissionColor"))
            {
                mat.EnableKeyword("_EMISSION");
                mat.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
                mat.SetColor("_EmissionColor", c * emission);
            }
            cache[key] = mat;
            return mat;
        }

        /// <summary>Flat, vertex-coloured material (used by particles so one system can be multi-coloured).</summary>
        public static Material Unlit()
        {
            if (baseUnlit != null) return baseUnlit;
            var shader = Shader.Find("Sprites/Default");
            baseUnlit = shader != null ? new Material(shader) { name = "WB_Unlit" } : Lit(Color.white, 0f, 0.5f);
            baseUnlit.enableInstancing = true;
            return baseUnlit;
        }
    }
}
