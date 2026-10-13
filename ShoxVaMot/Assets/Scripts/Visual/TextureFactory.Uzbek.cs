using UnityEngine;

namespace Shatranj.Visual
{
    /// <summary>
    /// Рельефные узоры для резного дерева и ганча, ковры, керамика, роспись потолка.
    /// Каждый рельеф даёт пару: цветовую текстуру (с затенёнными углублениями)
    /// и карту нормалей, чтобы резьба играла на свету.
    /// </summary>
    public static partial class TextureFactory
    {
        public delegate float HeightFunc(float u, float v);

        static float Smooth01(float e0, float e1, float x)
        {
            float t = Mathf.Clamp01((x - e0) / (e1 - e0));
            return t * t * (3f - 2f * t);
        }

        static float Frac(float x) { return x - Mathf.Floor(x); }

        /// <summary>Карта нормалей из поля высот (тайлится; альфа = 1, работает и с RGB, и с AG-распаковкой).</summary>
        public static Texture2D NormalMap(string key, int w, int h, HeightFunc f, float strength)
        {
            Texture2D cached;
            string k = "normal." + key;
            if (cache.TryGetValue(k, out cached) && cached != null) return cached;
            var hgt = new float[w * h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    hgt[y * w + x] = f((x + 0.5f) / w, (y + 0.5f) / h);
            var px = new Color32[w * h];
            for (int y = 0; y < h; y++)
            {
                int y0 = (y - 1 + h) % h, y1 = (y + 1) % h;
                for (int x = 0; x < w; x++)
                {
                    int x0 = (x - 1 + w) % w, x1 = (x + 1) % w;
                    float dx = (hgt[y * w + x1] - hgt[y * w + x0]) * 0.5f * strength;
                    float dy = (hgt[y1 * w + x] - hgt[y0 * w + x]) * 0.5f * strength;
                    var n = new Vector3(-dx, -dy, 1f).normalized;
                    px[y * w + x] = new Color32((byte)((n.x * 0.5f + 0.5f) * 255f), (byte)((n.y * 0.5f + 0.5f) * 255f), (byte)((n.z * 0.5f + 0.5f) * 255f), 255);
                }
            }
            var t = new Texture2D(w, h, TextureFormat.RGBA32, true, true);
            t.name = k;
            t.wrapMode = TextureWrapMode.Repeat;
            t.filterMode = FilterMode.Trilinear;
            t.anisoLevel = 2;
            t.SetPixels32(px);
            t.Apply(true, false);
            cache[k] = t;
            return t;
        }

        // ================================================================== Древесина: рельеф волокон

        public static HeightFunc WoodGrainHeight(int seed, int stripes)
        {
            return (u, v) =>
            {
                float warp = Noise.Fbm(u, v, 3, 2, seed, 4);
                float s = 0.5f + 0.5f * Mathf.Sin((u * stripes + warp * 2.4f) * Mathf.PI * 2f);
                float fiber = Noise.Value(u * 96f, v * 6f, 96, 6, seed + 7);
                return -(s * s * s) * 0.6f - fiber * 0.4f;
            };
        }

        // ================================================================== Резное ислими (рама доски)

        static float IslimiRelief(float u, float v, int w, int h, out float giltMask)
        {
            float X = u * w, Y = v * h;
            float k = 2f * Mathf.PI * 2f / w;
            float amp = h * 0.22f;
            float yc = h * 0.5f + amp * Mathf.Sin(X * k);
            float slope = amp * k * Mathf.Cos(X * k);
            float dist = Mathf.Abs(Y - yc) / Mathf.Sqrt(1f + slope * slope);
            float height = Mathf.Max(0f, 1f - (dist / 3.4f) * (dist / 3.4f));
            giltMask = height > 0.1f ? 1f : 0f;
            for (int i = 0; i < 4; i++)
            {
                float xk = (i + 0.25f) * w / 4f;
                float sgn = (i % 2 == 0) ? 1f : -1f;
                float cy = h * 0.5f + sgn * amp * 0.15f;
                float lx = X - xk, ly = Y - cy;
                if (lx > w / 2f) lx -= w;
                if (lx < -w / 2f) lx += w;
                float r = Mathf.Sqrt(lx * lx + ly * ly);
                float ring = Mathf.Max(0f, 1f - Mathf.Abs(r - 5f) / 1.6f);
                if (ring > height) { height = ring; giltMask = 1f; }
                float leaf = Mathf.Sqrt((lx / 10f) * (lx / 10f) + ((ly + sgn * 11f) / 5f) * ((ly + sgn * 11f) / 5f));
                if (leaf < 1f)
                {
                    float lh = Mathf.Sqrt(1f - leaf * leaf) * 0.9f;
                    if (lh > height) { height = lh; giltMask = 0.6f; }
                }
                if (r < 2.2f) { height = 1f; giltMask = 2f; }
            }
            if (Y < 4f || Y > h - 4f) { height = 0.85f; giltMask = 1f; }
            else if (Y < 6f || Y > h - 6f) { height = Mathf.Max(height, 0.1f); }
            return height;
        }

        /// <summary>Резная рама: орех с позолоченной лозой и бирюзовыми вставками.</summary>
        public static Texture2D CarvedIslimi(string key, Color recess, Color relief, Color gilt, Color inlay, out Texture2D normal)
        {
            const int w = 256, h = 64;
            normal = NormalMap("islimi." + key, w, h, (u, v) => { float g; return IslimiRelief(u, v, w, h, out g); }, 6f);
            return Generate("carvedislimi." + key, w, h, (u, v, x, y) =>
            {
                float g;
                float ht = IslimiRelief(u, v, w, h, out g);
                float n = 0.88f + 0.12f * Noise.Value(u * 64f, v * 16f, 64, 16, 5);
                Color c = Color.Lerp(recess, relief, ht) * n;
                if (g >= 2f) c = inlay;
                else if (g > 0.9f && ht > 0.35f) c = Color.Lerp(c, gilt, 0.85f);
                else if (g > 0.5f && ht > 0.3f) c = Color.Lerp(c, gilt, 0.35f);
                c.a = 1f;
                return c;
            });
        }

        // ================================================================== Гирих-рельеф

        /// <summary>Рельеф восьмиконечных звёзд с канавками (боковины доски, ганч, дверь).</summary>
        public static float GirihHeight(float u, float v, int cells)
        {
            float fx = Frac(u * cells) - 0.5f, fy = Frac(v * cells) - 0.5f;
            float ax = Mathf.Abs(fx), ay = Mathf.Abs(fy);
            const float s = 0.25f;
            float inside = Mathf.Max(s - Mathf.Max(ax, ay), (s * 1.414f - (ax + ay)) / 1.414f);
            float star = Smooth01(-0.005f, 0.04f, inside);
            float groove = 1f - Smooth01(0.0f, 0.018f, Mathf.Abs(inside + 0.035f));
            float corner = new Vector2(0.5f - ax, 0.5f - ay).magnitude;
            float boss = 1f - Smooth01(0.06f, 0.12f, corner);
            float center = 1f - Smooth01(0.05f, 0.08f, new Vector2(fx, fy).magnitude);
            float hgt = 0.35f + star * 0.55f - groove * 0.3f + boss * 0.5f - center * 0.25f * star;
            return hgt;
        }

        public static Texture2D GirihCarved(string key, Color low, Color high, int cells, out Texture2D normal)
        {
            normal = NormalMap("girih." + key + cells, 256, 256, (u, v) => GirihHeight(u, v, cells), 5f);
            return Generate("girihcarved." + key + cells, 256, 256, (u, v, x, y) =>
            {
                float hgt = Mathf.Clamp01(GirihHeight(u, v, cells));
                float n = 0.9f + 0.1f * Noise.Fbm(u, v, 8, 8, 13, 3);
                Color c = Color.Lerp(low, high, hgt) * n;
                c.a = 1f;
                return c;
            });
        }

        // ================================================================== Ганч (резная штукатурка)

        static float GanchHeight(float u, float v)
        {
            float g = GirihHeight(u, v, 3);
            float fx = Frac(u * 6f) - 0.5f, fy = Frac(v * 6f) - 0.5f;
            float dot = 1f - Smooth01(0.03f, 0.06f, new Vector2(fx, fy).magnitude);
            return g + dot * 0.15f;
        }

        public static Texture2D Ganch(out Texture2D normal)
        {
            normal = NormalMap("ganch", 256, 256, GanchHeight, 7f);
            Color deep = Hex("#B9A98C"), light = Hex("#F4EEDF");
            return Generate("ganch", 256, 256, (u, v, x, y) =>
            {
                float hgt = Mathf.Clamp01(GanchHeight(u, v));
                float n = 0.94f + 0.06f * Noise.Fbm(u, v, 16, 16, 21, 3);
                Color c = Color.Lerp(deep, light, Smooth01(0.1f, 0.8f, hgt)) * n;
                c.a = 1f;
                return c;
            });
        }

        // ================================================================== Резная панель (хивинская резьба)

        static float PanelHeight(float u, float v, float aspect)
        {
            float edge = Mathf.Min(Mathf.Min(u, 1f - u), Mathf.Min(v, 1f - v) * aspect);
            float frame = 1f - Smooth01(0.07f, 0.095f, edge);
            float groove = 1f - Smooth01(0f, 0.012f, Mathf.Abs(edge - 0.11f));
            float px = (u - 0.5f), py = (v - 0.5f) * aspect;
            float ax = Mathf.Abs(px), ay = Mathf.Abs(py);
            const float s = 0.22f;
            float inside = Mathf.Max(s - Mathf.Max(ax, ay), (s * 1.414f - (ax + ay)) / 1.414f);
            float star = Smooth01(-0.01f, 0.05f, inside);
            float starLine = 1f - Smooth01(0f, 0.012f, Mathf.Abs(inside - 0.07f));
            float rose = 1f - Smooth01(0.04f, 0.07f, new Vector2(px, py).magnitude);
            // лоза между звездой и рамкой
            float ang = Mathf.Atan2(py, px);
            float r = new Vector2(px, py).magnitude;
            float vineR = 0.36f + 0.03f * Mathf.Sin(ang * 8f);
            float vine = (1f - Smooth01(0f, 0.018f, Mathf.Abs(r - vineR))) * (edge > 0.13f ? 1f : 0f);
            float hgt = 0.25f + frame * 0.75f - groove * 0.2f;
            hgt = Mathf.Max(hgt, 0.25f + star * 0.6f - starLine * 0.25f + rose * 0.2f);
            hgt = Mathf.Max(hgt, 0.25f + vine * 0.55f);
            return hgt;
        }

        public static Texture2D CarvedPanel(string key, Color low, Color high, float aspect, out Texture2D normal)
        {
            normal = NormalMap("panel." + key + aspect, 128, 192, (u, v) => PanelHeight(u, v, aspect), 7f);
            return Generate("panel." + key + aspect, 128, 192, (u, v, x, y) =>
            {
                float hgt = Mathf.Clamp01(PanelHeight(u, v, aspect));
                float grain = Noise.Value(u * 40f, v * 4f, 40, 4, 77);
                Color c = Color.Lerp(low, high, hgt) * (0.85f + grain * 0.2f);
                c.a = 1f;
                return c;
            }, true, true);
        }

        // ================================================================== Колонна (устун)

        static float ColumnHeight(float u, float v)
        {
            float band = Frac(v * 4f);
            bool inBand = band < 0.12f || band > 0.88f;
            if (inBand)
            {
                float zig = Mathf.Abs(Frac(u * 24f + band * 4f) - 0.5f) * 2f;
                return 0.6f + 0.4f * zig;
            }
            float flute = 0.5f + 0.5f * Mathf.Cos(u * Mathf.PI * 2f * 16f);
            float twist = 0.5f + 0.5f * Mathf.Cos((u * 16f + v * 8f) * Mathf.PI * 2f);
            return 0.3f + 0.45f * flute * 0.6f + 0.25f * twist * 0.4f;
        }

        public static Texture2D ColumnCarving(Color low, Color high, out Texture2D normal)
        {
            normal = NormalMap("column", 256, 256, ColumnHeight, 5f);
            return Generate("column", 256, 256, (u, v, x, y) =>
            {
                float hgt = ColumnHeight(u, v);
                float grain = Noise.Value(u * 8f, v * 64f, 8, 64, 31);
                Color c = Color.Lerp(low, high, hgt) * (0.85f + grain * 0.2f);
                c.a = 1f;
                return c;
            });
        }

        // ================================================================== Половицы

        static float PlankHeight(float u, float v)
        {
            float pu = u * 6f;
            int plank = Mathf.FloorToInt(pu);
            float fu = pu - plank;
            float joint = Frac(v * 2f + Noise.Hash(plank, 3, 9) * 0.97f);
            float seam = Mathf.Min(Smooth01(0f, 0.04f, fu), Smooth01(0f, 0.04f, 1f - fu));
            float end = Mathf.Min(Smooth01(0f, 0.01f, joint), Smooth01(0f, 0.01f, 1f - joint));
            return Mathf.Min(seam, end) * (0.9f + 0.1f * Noise.Value(u * 120f, v * 8f, 120, 8, plank));
        }

        public static Texture2D Planks(Color light, Color dark, out Texture2D normal)
        {
            normal = NormalMap("planks", 256, 256, PlankHeight, 5f);
            return Generate("planks", 256, 256, (u, v, x, y) =>
            {
                int plank = Mathf.FloorToInt(u * 6f);
                float tint = Noise.Hash(plank, 1, 4);
                float grain = Noise.Value(u * 96f, v * 6f + plank * 0.37f, 96, 6, 51 + plank);
                float rings = 0.5f + 0.5f * Mathf.Sin((u * 30f + Noise.Fbm(u, v, 3, 2, 52, 3) * 3f) * Mathf.PI * 2f);
                Color c = Color.Lerp(light, dark, 0.25f + 0.35f * tint + 0.25f * grain + 0.15f * rings * rings);
                c *= 0.55f + 0.45f * PlankHeight(u, v);
                c.a = 1f;
                return c;
            });
        }

        // ================================================================== Бухарский гилам

        /// <summary>Ковёр с гёлями (восьмиугольными медальонами) на марене и широкой каймой.</summary>
        public static Texture2D Gilam()
        {
            Color red = Hex("#8C1C1F"), dark = Hex("#2A1A2E"), navy = Hex("#1D2950"), ivory = Hex("#EBDCC0"), orange = Hex("#C8662A"), green = Hex("#3E5B3A");
            return Generate("gilam", 512, 512, (u, v, x, y) =>
            {
                float n = 0.9f + 0.1f * Noise.Value(u * 256f, v * 256f, 256, 256, 3);
                float edge = Mathf.Min(Mathf.Min(u, 1f - u), Mathf.Min(v, 1f - v));
                if (edge < 0.012f) return ivory * n;
                if (edge < 0.11f)
                {
                    float t = (edge - 0.012f) / 0.098f;
                    if (t < 0.08f || t > 0.92f) return navy * n;
                    if (t < 0.14f || t > 0.86f) return ivory * n;
                    float along = (u < 0.11f || u > 0.89f) ? v : u;
                    float m = Frac(along * 18f);
                    float across = (t - 0.14f) / 0.72f;
                    float d = Mathf.Abs(m - 0.5f) * 2f + Mathf.Abs(across - 0.5f) * 2f;
                    if (d < 0.55f) return (d < 0.25f ? orange : ivory) * n;
                    if (d < 0.75f) return navy * n;
                    float hook = Mathf.Abs(Frac(along * 36f) - 0.5f);
                    return (hook < 0.08f ? green : dark) * n;
                }
                float iu = (u - 0.11f) / 0.78f, iv = (v - 0.11f) / 0.78f;
                const int cols = 4, rows = 5;
                float gx = iu * cols, gy = iv * rows;
                float lx = Frac(gx) - 0.5f, ly = Frac(gy) - 0.5f;
                ly *= rows / (float)cols * 0.9f;
                float ax = Mathf.Abs(lx), ay = Mathf.Abs(ly);
                float oct = Mathf.Max(Mathf.Max(ax, ay), (ax + ay) * 0.72f);
                Color c = red;
                if (oct < 0.36f)
                {
                    if (oct > 0.33f) c = dark;
                    else if (oct > 0.305f) c = ivory;
                    else
                    {
                        bool q = (lx > 0) ^ (ly > 0);
                        c = q ? navy : red;
                        float dm = ax + ay;
                        if (dm < 0.1f) c = orange;
                        else if (dm < 0.13f) c = ivory;
                        float leaf = Mathf.Abs(Mathf.Abs(lx) - Mathf.Abs(ly));
                        if (leaf < 0.025f && dm > 0.14f && oct < 0.28f) c = ivory;
                    }
                }
                else
                {
                    // малые гёли между рядами
                    float mx = Frac(gx + 0.5f) - 0.5f, my = (Frac(gy + 0.5f) - 0.5f) * rows / (float)cols * 0.9f;
                    float dm = Mathf.Abs(mx) + Mathf.Abs(my);
                    if (dm < 0.12f) c = dm < 0.05f ? ivory : (dm < 0.08f ? navy : orange);
                    else if (Mathf.Abs(mx) < 0.008f || Mathf.Abs(my) < 0.008f) c = dark;
                }
                return c * n;
            }, true, true);
        }

        // ================================================================== Палос (безворсовая дорожка)

        public static Texture2D Palos()
        {
            Color red = Hex("#9A2422"), indigo = Hex("#23305C"), ivory = Hex("#EADBC0"), green = Hex("#456B3B"), ochre = Hex("#C98A2E");
            return Generate("palos", 256, 256, (u, v, x, y) =>
            {
                float n = 0.9f + 0.1f * Noise.Value(u * 128f, v * 128f, 128, 128, 7);
                int band = Mathf.FloorToInt(v * 8f);
                float fv = Frac(v * 8f);
                Color bg = band % 2 == 0 ? red : indigo;
                if (fv < 0.08f || fv > 0.92f) return ivory * n;
                float m = Mathf.Abs(Frac(u * 6f + (band % 2) * 0.5f) - 0.5f) * 2f;
                float d = m + Mathf.Abs(fv - 0.5f) * 2.4f;
                if (d < 0.5f) return (d < 0.22f ? ochre : ivory) * n;
                if (d < 0.7f) return (band % 2 == 0 ? green : red) * n;
                return bg * n;
            });
        }

        // ================================================================== Риштанская керамика

        public static Texture2D Rishtan(int variant)
        {
            Color white = Hex("#F1EEE2"), turq = Hex("#1E9BB0"), cobalt = Hex("#1F3E8C"), ochre = Hex("#C27C2C"), green = Hex("#4E8A3D"), brown = Hex("#5A3A22");
            return Generate("rishtan." + variant, 256, 256, (u, v, x, y) =>
            {
                float dx = u - 0.5f, dy = v - 0.5f;
                float r = Mathf.Sqrt(dx * dx + dy * dy) * 2f;
                float a = Mathf.Atan2(dy, dx);
                int petals = variant == 0 ? 8 : 12;
                Color c = turq;
                if (r > 0.98f) return brown;
                if (r > 0.9f) c = Mathf.Cos(a * 48f) > 0.6f ? white : ochre;
                else if (r > 0.86f) c = cobalt;
                else if (r > 0.55f)
                {
                    float m = Mathf.Cos(a * petals);
                    float band = (r - 0.55f) / 0.31f;
                    c = variant == 0 ? turq : white;
                    if (m > 0.3f + Mathf.Abs(band - 0.5f) * 1.2f) c = cobalt;
                    else if (m < -0.6f && Mathf.Abs(band - 0.5f) < 0.2f) c = green;
                }
                else if (r > 0.5f) c = ochre;
                else if (r > 0.22f)
                {
                    float m = Mathf.Cos(a * petals * 0.5f + r * 6f);
                    c = m > 0.2f ? (variant == 0 ? white : turq) : cobalt;
                }
                else if (r > 0.12f) c = Mathf.Cos(a * 8f) > 0f ? turq : white;
                else c = cobalt;
                float glaze = 0.94f + 0.06f * Noise.Value(u * 32f, v * 32f, 32, 32, variant);
                return c * glaze;
            }, true, true);
        }

        // ================================================================== Роспись потолка

        public static Texture2D CeilingPaint()
        {
            return Majolica("ceiling", Hex("#B9782E"), Hex("#9C2328"), Hex("#1E4E86"), Hex("#2F7D4F"), 2, 256);
        }

        // ================================================================== Служебное

        public static Texture2D Vignette()
        {
            return Generate("vignette", 128, 128, (u, v, x, y) =>
            {
                float dx = (u - 0.5f) * 2f, dy = (v - 0.5f) * 2f;
                float d = Mathf.Sqrt(dx * dx * 0.8f + dy * dy);
                float a = Smooth01(0.55f, 1.25f, d) * 0.6f;
                return new Color(0.03f, 0.02f, 0.01f, a);
            }, false, true);
        }

        /// <summary>Луч света: мягкий по краям, тает к концу.</summary>
        public static Texture2D LightShaft()
        {
            return Generate("shaft", 64, 128, (u, v, x, y) =>
            {
                float side = Mathf.Sin(u * Mathf.PI);
                float a = side * side * Mathf.Pow(v, 1.6f);
                return new Color(1, 1, 1, a);
            }, false, true);
        }
    }
}
