using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    /// <summary>Material keshi. Shaderlar Resources/Shaders ichida — build'ga albatta kiradi.</summary>
    public static class Mat
    {
        static Shader toon, outline, unlit, partAdd, partAlpha, sky;
        static readonly Dictionary<string, Material> cache = new Dictionary<string, Material>();

        static Shader Find(ref Shader s, string name, string fallback)
        {
            if (s != null) return s;
            s = Shader.Find(name);
            if (s == null || !s.isSupported) s = Shader.Find(fallback);
            if (s == null) s = Shader.Find("Sprites/Default");
            return s;
        }

        public static Shader ToonShader => Find(ref toon, "UzbekKombat/Toon", "Standard");
        public static Shader OutlineShader => Find(ref outline, "UzbekKombat/Outline", "Unlit/Color");
        public static Shader UnlitShader => Find(ref unlit, "UzbekKombat/Unlit", "Unlit/Texture");
        public static Shader AddShader => Find(ref partAdd, "UzbekKombat/ParticleAdd", "Sprites/Default");
        public static Shader AlphaShader => Find(ref partAlpha, "UzbekKombat/ParticleAlpha", "Sprites/Default");
        public static Shader SkyShader => Find(ref sky, "UzbekKombat/SkyGradient", "Skybox/Procedural");

        /// <summary>Vertex-rangli toon material (personaj qismlari uchun).</summary>
        public static Material Toon(Color tint, Texture tex = null, float rim = 0.35f, Color? emission = null, float spec = 0f, Vector2? tiling = null)
        {
            string key = $"toon_{ColorUtility.ToHtmlStringRGBA(tint)}_{(tex ? tex.name : "-")}_{rim:F2}_{(emission.HasValue ? ColorUtility.ToHtmlStringRGBA(emission.Value) : "-")}_{spec:F2}_{tiling}";
            if (cache.TryGetValue(key, out var m) && m) return m;
            m = new Material(ToonShader) { name = key };
            m.SetColor("_Color", tint);
            if (m.HasProperty("_MainTex") && tex != null)
            {
                m.SetTexture("_MainTex", tex);
                if (tiling.HasValue) m.SetTextureScale("_MainTex", tiling.Value);
            }
            if (m.HasProperty("_RimStrength")) m.SetFloat("_RimStrength", rim * 0.5f);
            if (tex != null && m.HasProperty("_DetailStrength")) m.SetFloat("_DetailStrength", 0.35f);
            if (m.HasProperty("_Specular")) m.SetFloat("_Specular", spec);
            if (emission.HasValue)
            {
                if (m.HasProperty("_EmissionColor")) m.SetColor("_EmissionColor", emission.Value);
                m.EnableKeyword("_EMISSION");
            }
            cache[key] = m;
            return m;
        }

        public static Material ToonVC => Toon(Color.white);

        public static Material Outline(float width = 0.012f, Color? col = null)
        {
            width *= 0.45f; // realistik ko'rinish uchun ingichka kontur
            Color c = col ?? new Color(0.1f, 0.06f, 0.05f, 1);
            string key = $"outline_{width:F4}_{ColorUtility.ToHtmlStringRGBA(c)}";
            if (cache.TryGetValue(key, out var m) && m) return m;
            m = new Material(OutlineShader) { name = key };
            if (m.HasProperty("_OutlineColor")) m.SetColor("_OutlineColor", c);
            if (m.HasProperty("_OutlineWidth")) m.SetFloat("_OutlineWidth", width);
            if (m.HasProperty("_Color")) m.SetColor("_Color", c);
            cache[key] = m;
            return m;
        }

        public static Material Unlit(Color c, Texture tex = null)
        {
            string key = $"unlit_{ColorUtility.ToHtmlStringRGBA(c)}_{(tex ? tex.name : "-")}";
            if (cache.TryGetValue(key, out var m) && m) return m;
            m = new Material(UnlitShader) { name = key };
            m.SetColor("_Color", c);
            if (tex) m.SetTexture("_MainTex", tex);
            cache[key] = m;
            return m;
        }

        public static Material Additive(Texture tex, Color tint)
        {
            string key = $"add_{(tex ? tex.name : "-")}_{ColorUtility.ToHtmlStringRGBA(tint)}";
            if (cache.TryGetValue(key, out var m) && m) return m;
            m = new Material(AddShader) { name = key };
            m.SetTexture("_MainTex", tex);
            if (m.HasProperty("_TintColor")) m.SetColor("_TintColor", tint);
            cache[key] = m;
            return m;
        }

        public static Material Alpha(Texture tex, Color tint)
        {
            string key = $"alpha_{(tex ? tex.name : "-")}_{ColorUtility.ToHtmlStringRGBA(tint)}";
            if (cache.TryGetValue(key, out var m) && m) return m;
            m = new Material(AlphaShader) { name = key };
            m.SetTexture("_MainTex", tex);
            if (m.HasProperty("_TintColor")) m.SetColor("_TintColor", tint);
            cache[key] = m;
            return m;
        }

        /// <summary>Takrorlanmas (unique) nusxa — rangi animatsiya qilinadigan obyektlar uchun.</summary>
        public static Material Instance(Material src) => new Material(src) { name = src.name + "_inst" };
    }
}
