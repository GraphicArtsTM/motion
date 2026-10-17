using UnityEngine;

namespace UzbekKombat
{
    /// <summary>
    /// Kamera post-effektlari (Built-in RP): SSAO, bloom, ACES tonemapping, rang gradatsiyasi,
    /// vinyetka, zarbada xromatik aberratsiya, KO paytida rangsizlanish.
    /// </summary>
    [RequireComponent(typeof(Camera))]
    public class PostFX : MonoBehaviour
    {
        public bool bloomOn = true, aoOn = true;
        public float threshold = 1.2f, knee = 0.6f, bloomIntensity = 0.22f;
        public float contrast = 1.06f, saturation = 1.08f, exposure = 1.0f, vignette = 0.28f;
        public Color tint = new Color(1.03f, 1.0f, 0.95f), shadowTint = new Color(0.92f, 0.94f, 1.05f);
        public float grain = 0.012f;
        public float aoRadius = 0.45f, aoIntensity = 1.1f;
        public float aberration;
        public float desaturate;
        Material mat;
        Camera cam;
        const int Levels = 5;
        readonly RenderTexture[] chain = new RenderTexture[Levels];

        void OnEnable()
        {
            var sh = Shader.Find("Hidden/UzbekKombat/PostFX");
            if (sh == null || !sh.isSupported) { enabled = false; return; }
            mat = new Material(sh) { hideFlags = HideFlags.HideAndDontSave };
            cam = GetComponent<Camera>();
            cam.depthTextureMode |= DepthTextureMode.Depth;
        }

        void OnDisable() { if (mat) DestroyImmediate(mat); }

        public void Kick(float amount) { aberration = Mathf.Max(aberration, Mathf.Min(amount, 2.5f)); }

        public void Preset(ArenaPreset p)
        {
            if (p == ArenaPreset.Sunset)
            {
                tint = new Color(1.04f, 1.0f, 0.93f); shadowTint = new Color(0.9f, 0.92f, 1.06f);
                exposure = 1.0f; threshold = 1.25f; bloomIntensity = 0.2f; saturation = 1.08f; contrast = 1.06f;
            }
            else
            {
                tint = new Color(0.97f, 0.98f, 1.04f); shadowTint = new Color(0.85f, 0.9f, 1.12f);
                exposure = 1.25f; threshold = 0.9f; bloomIntensity = 0.32f; saturation = 0.95f; contrast = 1.1f;
            }
        }

        void Update() { aberration = Mathf.MoveTowards(aberration, 0, Time.unscaledDeltaTime * 6f); }

        void OnRenderImage(RenderTexture src, RenderTexture dst)
        {
            if (mat == null) { Graphics.Blit(src, dst); return; }
            var fmt = src.format;
            mat.SetVector("_Threshold", new Vector4(threshold, knee, bloomOn ? bloomIntensity : 0, 0));
            mat.SetVector("_Grade", new Vector4(contrast, saturation, exposure, vignette));
            mat.SetColor("_Tint", tint);
            mat.SetColor("_Shadows", shadowTint);
            mat.SetVector("_Fx", new Vector4(aberration * 0.08f, grain, Time.time % 100f + 1f, Mathf.Clamp01(desaturate)));

            // SSAO (yarim o'lchamda)
            RenderTexture ao = null;
            bool useAO = aoOn && cam != null && SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.R8);
            if (useAO)
            {
                var p = cam.projectionMatrix;
                mat.SetVector("_UVToView", new Vector4(2f / p[0, 0], 2f / p[1, 1], -1f / p[0, 0], -1f / p[1, 1]));
                mat.SetVector("_AOParams", new Vector4(aoRadius, aoIntensity, 0.002f, 1));
                int aw = src.width / 2, ah = src.height / 2;
                ao = RenderTexture.GetTemporary(aw, ah, 0, RenderTextureFormat.R8);
                var tmp = RenderTexture.GetTemporary(aw, ah, 0, RenderTextureFormat.R8);
                Graphics.Blit(src, ao, mat, 4);
                mat.SetVector("_BlurDir", new Vector4(1, 0, 0, 0));
                Graphics.Blit(ao, tmp, mat, 5);
                mat.SetVector("_BlurDir", new Vector4(0, 1, 0, 0));
                Graphics.Blit(tmp, ao, mat, 5);
                RenderTexture.ReleaseTemporary(tmp);
                mat.SetTexture("_AOTex", ao);
            }
            else mat.SetVector("_AOParams", Vector4.zero);

            RenderTexture bloom = null;
            if (bloomOn)
            {
                int w = src.width / 2, h = src.height / 2, n = 0;
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
            if (ao != null) RenderTexture.ReleaseTemporary(ao);
        }
    }
}
