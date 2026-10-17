using UnityEngine;

namespace UzbekKombat
{
    /// <summary>
    /// Kamera post-effektlari (Built-in RP, OnRenderImage): bloom, rang gradatsiyasi, vinyetka,
    /// zarbada xromatik aberratsiya, KO paytida rangsizlanish. Tashqi paketsiz ishlaydi.
    /// </summary>
    [RequireComponent(typeof(Camera))]
    public class PostFX : MonoBehaviour
    {
        public bool bloomOn = true;
        public float threshold = 0.9f, knee = 0.5f, bloomIntensity = 0.75f;
        public float contrast = 1.08f, saturation = 1.12f, exposure = 1.0f, vignette = 0.32f;
        public Color tint = new Color(1.04f, 1.0f, 0.94f), shadowTint = new Color(0.62f, 0.62f, 0.72f);
        public float grain = 0.02f;
        public float aberration;   // zarbada qisqa "kick"
        public float desaturate;   // KO / yakuniy zarba
        Material mat;
        const int Levels = 5;
        readonly RenderTexture[] chain = new RenderTexture[Levels];

        void OnEnable()
        {
            var sh = Shader.Find("Hidden/UzbekKombat/PostFX");
            if (sh == null || !sh.isSupported) { enabled = false; return; }
            mat = new Material(sh) { hideFlags = HideFlags.HideAndDontSave };
        }

        void OnDisable() { if (mat) DestroyImmediate(mat); }

        public void Kick(float amount) { aberration = Mathf.Max(aberration, amount); }

        public void Preset(ArenaPreset p)
        {
            if (p == ArenaPreset.Sunset)
            {
                tint = new Color(1.06f, 0.99f, 0.9f); shadowTint = new Color(0.6f, 0.58f, 0.75f);
                threshold = 0.85f; bloomIntensity = 0.8f; saturation = 1.12f; contrast = 1.08f; exposure = 1f;
            }
            else
            {
                tint = new Color(0.95f, 0.98f, 1.08f); shadowTint = new Color(0.5f, 0.55f, 0.8f);
                threshold = 0.7f; bloomIntensity = 1.1f; saturation = 1.0f; contrast = 1.12f; exposure = 1.08f;
            }
        }

        void Update()
        {
            aberration = Mathf.MoveTowards(aberration, 0, Time.unscaledDeltaTime * 6f);
        }

        void OnRenderImage(RenderTexture src, RenderTexture dst)
        {
            if (mat == null) { Graphics.Blit(src, dst); return; }
            var fmt = src.format;
            int w = src.width / 2, h = src.height / 2;
            mat.SetVector("_Threshold", new Vector4(threshold, knee, bloomOn ? bloomIntensity : 0, 0));
            mat.SetVector("_Grade", new Vector4(contrast, saturation, exposure, vignette));
            mat.SetColor("_Tint", tint);
            mat.SetColor("_Shadows", shadowTint);
            mat.SetVector("_Fx", new Vector4(aberration * 0.12f, grain, Time.time % 100f + 1f, Mathf.Clamp01(desaturate)));
            mat.SetColor("_Flash", new Color(0, 0, 0, 0));

            RenderTexture bloom = null;
            if (bloomOn)
            {
                int n = 0;
                for (int i = 0; i < Levels; i++)
                {
                    if (w < 8 || h < 8) break;
                    chain[i] = RenderTexture.GetTemporary(w, h, 0, fmt);
                    chain[i].filterMode = FilterMode.Bilinear;
                    Graphics.Blit(i == 0 ? src : chain[i - 1], chain[i], mat, i == 0 ? 0 : 1);
                    w /= 2; h /= 2; n++;
                }
                for (int i = n - 2; i >= 0; i--) Graphics.Blit(chain[i + 1], chain[i], mat, 2);
                bloom = chain[0];
                for (int i = 1; i < n; i++) { RenderTexture.ReleaseTemporary(chain[i]); chain[i] = null; }
            }
            mat.SetTexture("_BloomTex", bloom != null ? bloom : (Texture)Texture2D.blackTexture);
            mat.SetTexture("_SourceTex", src);
            Graphics.Blit(src, dst, mat, 3);
            if (bloom != null) { RenderTexture.ReleaseTemporary(bloom); chain[0] = null; }
        }
    }
}
