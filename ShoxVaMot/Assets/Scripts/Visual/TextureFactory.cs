using System.Collections.Generic;
using UnityEngine;

namespace Shatranj.Visual
{
    /// <summary>
    /// Процедурные текстуры в узбекском стиле: дерево (чинара, орех), адрас/икат,
    /// чустская тюбетейка, майолика Регистана, сюзане, ислими, кирпич, мех тельпака,
    /// «пахта» (хлопковый узор чайника) и служебные спрайты.
    /// </summary>
    public static partial class TextureFactory
    {
        static readonly Dictionary<string, Texture2D> cache = new Dictionary<string, Texture2D>();

        public delegate Color PixelFunc(float u, float v, int x, int y);

        public static Texture2D Generate(string key, int w, int h, PixelFunc f, bool mip = true, bool clamp = false)
        {
            Texture2D cached;
            if (cache.TryGetValue(key, out cached) && cached != null) return cached;

            var t = new Texture2D(w, h, TextureFormat.RGBA32, mip);
            t.name = key;
            t.wrapMode = clamp ? TextureWrapMode.Clamp : TextureWrapMode.Repeat;
            t.filterMode = mip ? FilterMode.Trilinear : FilterMode.Bilinear;
            t.anisoLevel = mip ? 2 : 0;
            var px = new Color32[w * h];
            for (int y = 0; y < h; y++)
            {
                float v = (y + 0.5f) / h;
                for (int x = 0; x < w; x++)
                {
                    float u = (x + 0.5f) / w;
                    px[y * w + x] = f(u, v, x, y);
                }
            }
            t.SetPixels32(px);
            t.Apply(mip, false);
            cache[key] = t;
            return t;
        }

        public static Color Hex(string hex)
        {
            Color c;
            ColorUtility.TryParseHtmlString(hex.StartsWith("#") ? hex : "#" + hex, out c);
            return c;
        }

        static float SmoothEdge(float d, float w) { return Mathf.Clamp01(0.5f - d / Mathf.Max(w, 1e-5f)); }

        // ------------------------------------------------------------------ Дерево

        /// <summary>Древесина токарной фигуры: волокна вдоль V, годичные кольца поперёк U.</summary>
        public static Texture2D Wood(string key, Color light, Color dark, int seed, int stripes = 9, int size = 256)
        {
            return Generate("wood." + key, size, size, (u, v, x, y) =>
            {
                float warp = Noise.Fbm(u, v, 3, 2, seed, 4);
                float ring = u * stripes + warp * 2.4f;
                float s = 0.5f + 0.5f * Mathf.Sin(ring * Mathf.PI * 2f);
                s = s * s * s;
                float fiber = Noise.Value(u * 96f, v * 6f, 96, 6, seed + 7);
                float blotch = Noise.Fbm(u, v, 2, 2, seed + 13, 3);
                float t = Mathf.Clamp01(s * 0.5f + fiber * 0.28f + (blotch - 0.5f) * 0.45f);
                return Color.Lerp(light, dark, t);
            });
        }

        static float WoodShade(float u, float v, int seed)
        {
            float fiber = Noise.Value(u * 80f, v * 5f, 80, 5, seed);
            return 0.86f + 0.14f * fiber;
        }

        // ------------------------------------------------------------------ Адрас / икат

        /// <summary>Узор икат (абр): вертикальные полосы с ромбами и «растёкшимися» краями, расписанный по дереву.</summary>
        public static Texture2D Ikat(string key, Color[] palette, int seed, int bands = 6, int size = 256)
        {
            return Generate("ikat." + key, size, size, (u, v, x, y) =>
            {
                int k = Mathf.FloorToInt(u * bands);
                float local = u * bands - k;
                float jitter = (Noise.Hash(y, k, seed) - 0.5f) * 0.10f;
                float dv = Mathf.Abs(((v * 3f + k * 0.5f) % 1f) - 0.5f) * 2f;
                float edge = Mathf.Abs(local - 0.5f);
                Color bg = palette[k % palette.Length];
                Color c = bg;
                if (edge < 0.47f * (1f - dv) + jitter) c = palette[(k + 2) % palette.Length];
                if (edge < 0.22f * (1f - dv) + jitter * 0.6f) c = palette[(k + 1) % palette.Length];
                if (edge > 0.47f + jitter * 0.4f) c = Color.Lerp(bg, palette[(k + 3) % palette.Length], 0.6f);
                return c * WoodShade(u, v, seed);
            });
        }

        // ------------------------------------------------------------------ Тюбетейка

        /// <summary>Чустская до'ппи: тёмный фон и белые «калампир» (миндалевидные перцы).</summary>
        public static Texture2D Doppi(string key, Color bg, Color motif, int seed)
        {
            const int cells = 4;
            return Generate("doppi." + key, 256, 128, (u, v, x, y) =>
            {
                float cx = (u * cells) % 1f - 0.5f;
                float cy = (v * 2f) % 1f - 0.5f;
                float a = 0.7f;
                float rx = cx * Mathf.Cos(a) - cy * Mathf.Sin(a);
                float ry = cx * Mathf.Sin(a) + cy * Mathf.Cos(a);
                float e = Mathf.Sqrt((rx / 0.17f) * (rx / 0.17f) + (ry / 0.36f) * (ry / 0.36f));
                // загнутый кончик
                float tip = new Vector2(rx - 0.10f, ry - 0.30f).magnitude;
                Color c = bg;
                if (e < 1f && e > 0.72f) c = motif;
                if (e < 0.42f) c = motif;
                if (tip < 0.07f && tip > 0.035f) c = motif;
                float stripe = Mathf.Abs(cy);
                if (stripe > 0.47f) c = Color.Lerp(bg, motif, 0.5f);
                float n = 0.9f + 0.1f * Noise.Value(u * 64f, v * 32f, 64, 32, seed);
                return c * n;
            });
        }

        // ------------------------------------------------------------------ Майолика

        /// <summary>Изразец с восьмиконечными звёздами (гирих), как на порталах Регистана.</summary>
        public static Texture2D Majolica(string key, Color bg, Color star, Color line, Color dot, int cells = 4, int size = 256)
        {
            return Generate("tile." + key, size, size, (u, v, x, y) =>
            {
                float fx = (u * cells) % 1f - 0.5f;
                float fy = (v * cells) % 1f - 0.5f;
                float ax = Mathf.Abs(fx), ay = Mathf.Abs(fy);
                const float s = 0.26f;
                float dsq = s - Mathf.Max(ax, ay);
                float ddi = (s * 1.414f - (ax + ay)) / 1.414f;
                float inside = Mathf.Max(dsq, ddi);
                float pxw = cells / (float)size;
                Color c = bg;
                if (inside > 0f) c = star;
                if (Mathf.Abs(inside) < 0.022f) c = Color.Lerp(c, line, SmoothEdge(Mathf.Abs(inside) - 0.012f, pxw));
                float center = new Vector2(fx, fy).magnitude;
                if (center < 0.07f) c = dot;
                else if (center < 0.09f) c = line;
                float corner = new Vector2(0.5f - ax, 0.5f - ay).magnitude;
                if (corner < 0.13f) c = corner < 0.06f ? dot : line;
                if (ax > 0.485f || ay > 0.485f) c *= 0.7f;
                float n = 0.92f + 0.08f * Noise.Fbm(u, v, 8, 8, 5, 3);
                c *= n;
                c.a = 1f;
                return c;
            });
        }

        // ------------------------------------------------------------------ Сюзане

        public static Texture2D Suzani(int size = 512)
        {
            Color cream = Hex("#EDE0C2"), red = Hex("#B0242B"), darkRed = Hex("#6E1218"), pink = Hex("#D9616A");
            Color green = Hex("#3C6B3C"), gold = Hex("#D8A740"), indigo = Hex("#24345E");
            return Generate("suzani", size, size, (u, v, x, y) =>
            {
                float edge = Mathf.Min(Mathf.Min(u, 1f - u), Mathf.Min(v, 1f - v));
                float n = 0.93f + 0.07f * Noise.Fbm(u, v, 16, 16, 77, 3);
                if (edge < 0.075f)
                {
                    // кайма
                    if (edge < 0.012f || (edge > 0.063f && edge < 0.07f)) return gold * n;
                    float along = (u < 0.075f || u > 0.925f) ? v : u;
                    float m = Mathf.Abs((along * 24f) % 1f - 0.5f) * 2f;
                    float across = (edge - 0.012f) / 0.051f;
                    float diamond = Mathf.Abs(across - 0.5f) * 2f + m;
                    if (diamond < 0.8f) return (diamond < 0.35f ? gold : cream) * n;
                    return darkRed * n;
                }
                float iu = (u - 0.09f) / 0.82f, iv = (v - 0.09f) / 0.82f;
                const int grid = 3;
                float gx = iu * grid, gy = iv * grid;
                float lx = gx - Mathf.Floor(gx) - 0.5f, ly = gy - Mathf.Floor(gy) - 0.5f;
                float d = Mathf.Sqrt(lx * lx + ly * ly);
                float ang = Mathf.Atan2(ly, lx);
                Color c = cream;

                // большие медальоны «ой» (луна)
                float scallop = 0.30f + 0.018f * Mathf.Cos(ang * 16f);
                if (d < scallop)
                {
                    if (d < 0.07f) c = darkRed;
                    else if (d < 0.105f) c = gold;
                    else if (d < 0.22f) c = Mathf.Cos(ang * 12f) > 0.2f ? red : pink;
                    else if (d < 0.245f) c = darkRed;
                    else c = red;
                }
                else
                {
                    // лепестки вокруг медальона
                    for (int k = 0; k < 8; k++)
                    {
                        float pa = k * Mathf.PI / 4f + Mathf.PI / 8f;
                        float px = Mathf.Cos(pa) * 0.39f, py = Mathf.Sin(pa) * 0.39f;
                        float dx = lx - px, dy = ly - py;
                        float rx = dx * Mathf.Cos(-pa) - dy * Mathf.Sin(-pa);
                        float ry = dx * Mathf.Sin(-pa) + dy * Mathf.Cos(-pa);
                        float e = (rx / 0.065f) * (rx / 0.065f) + (ry / 0.035f) * (ry / 0.035f);
                        if (e < 1f) { c = e < 0.35f ? indigo : green; break; }
                    }
                    // розетки на углах
                    float cdx = 0.5f - Mathf.Abs(lx), cdy = 0.5f - Mathf.Abs(ly);
                    float cd = Mathf.Sqrt(cdx * cdx + cdy * cdy);
                    if (cd < 0.1f) c = cd < 0.045f ? red : (cd < 0.065f ? gold : green);
                }
                return c * n;
            }, true, true);
        }

        // ------------------------------------------------------------------ Ислими

        /// <summary>Растительный орнамент ислими: золотая лоза на ляпис-лазури (тайлится по U).</summary>
        public static Texture2D Islimi(string key, Color bg, Color vine, Color accent, int w = 256, int h = 64)
        {
            return Generate("islimi." + key, w, h, (u, v, x, y) =>
            {
                float X = u * w, Y = v * h;
                float k = 2f * Mathf.PI * 2f / w;
                float amp = h * 0.22f;
                float yc = h * 0.5f + amp * Mathf.Sin(X * k);
                float slope = amp * k * Mathf.Cos(X * k);
                float dist = Mathf.Abs(Y - yc) / Mathf.Sqrt(1f + slope * slope);
                Color c = bg * (0.92f + 0.08f * Noise.Fbm(u, v, 8, 2, 3, 3));
                if (dist < 2.6f) c = Color.Lerp(c, vine, SmoothEdge(dist - 2.0f, 1f));

                // завитки и листья у гребней волны
                for (int i = 0; i < 4; i++)
                {
                    float xk = (i + 0.25f) * w / 4f;
                    float sgn = (i % 2 == 0) ? 1f : -1f;
                    float cy = h * 0.5f + sgn * amp * 0.15f;
                    float lx = X - xk, ly = Y - cy;
                    if (lx > w / 2f) lx -= w;
                    if (lx < -w / 2f) lx += w;
                    float r = Mathf.Sqrt(lx * lx + ly * ly);
                    if (r < 6.5f && r > 3.6f) c = vine;
                    if (r < 2.2f) c = accent;
                    float leaf = Mathf.Sqrt((lx / 9f) * (lx / 9f) + ((ly + sgn * 11f) / 4.5f) * ((ly + sgn * 11f) / 4.5f));
                    if (leaf < 1f) c = leaf < 0.5f ? accent : vine;
                }
                if (Y < 3f || Y > h - 3f) c = vine;
                else if (Y < 5f || Y > h - 5f) c = accent;
                c.a = 1f;
                return c;
            });
        }

        // ------------------------------------------------------------------ Кирпич, мех, пахта

        public static Texture2D Brick(string key, Color brick, Color mortar, int seed, int rows = 8, int perRow = 4, int size = 256)
        {
            return Generate("brick." + key, size, size, (u, v, x, y) =>
            {
                float ry = v * rows;
                int row = Mathf.FloorToInt(ry);
                float bx = u * perRow + (row % 2) * 0.5f;
                int col = Mathf.FloorToInt(bx);
                float fy = ry - row, fx = bx - col;
                float m = 0.06f;
                if (fy < m || fx < m * perRow / (float)rows * 2f) return mortar * (0.9f + 0.1f * Noise.Hash(x, y, seed));
                float var = Noise.Hash(col % perRow, row, seed);
                float n = Noise.Fbm(u, v, 16, 16, seed + 1, 3);
                Color c = brick * (0.82f + 0.25f * var) * (0.9f + 0.18f * n);
                c.a = 1f;
                return c;
            });
        }

        public static Texture2D Fur(string key, Color dark, Color light, int seed)
        {
            return Generate("fur." + key, 128, 128, (u, v, x, y) =>
            {
                float f = Noise.Fbm(u, v, 8, 8, seed, 4);
                float curl = 0.5f + 0.5f * Mathf.Sin(f * 34f);
                float n = Noise.Value(u * 64f, v * 64f, 64, 64, seed + 3);
                return Color.Lerp(dark, light, curl * 0.6f + n * 0.4f);
            });
        }

        /// <summary>Знаменитый узор «пахта» (хлопок) ташкентского фарфора: синие коробочки на белом.</summary>
        public static Texture2D Paxta()
        {
            Color white = Hex("#F5F3EE"), cobalt = Hex("#1F3C9C"), gold = Hex("#D6A33C");
            return Generate("paxta", 256, 256, (u, v, x, y) =>
            {
                const int cells = 4;
                float fx = (u * cells) % 1f - 0.5f, fy = (v * cells) % 1f - 0.5f;
                int ci = Mathf.FloorToInt(u * cells) + Mathf.FloorToInt(v * cells);
                if (ci % 2 == 1) { fx = (fx + 1f) % 1f - 0.5f; }
                Color c = white;
                float[] ox = { 0.13f, -0.13f, 0f, 0f };
                float[] oy = { 0f, 0f, 0.13f, -0.13f };
                for (int i = 0; i < 4; i++)
                {
                    float d = new Vector2(fx - ox[i], fy - oy[i]).magnitude;
                    if (d < 0.12f) c = d > 0.1f ? white : cobalt;
                }
                float cd = new Vector2(fx, fy).magnitude;
                if (cd < 0.045f) c = gold;
                float diag = Mathf.Abs(Mathf.Abs(fx) - Mathf.Abs(fy));
                if (cd > 0.28f && cd < 0.42f && diag < 0.02f) c = cobalt;
                return c;
            });
        }

        // ------------------------------------------------------------------ Служебные формы

        public static Texture2D Circle(int size = 64)
        {
            return Generate("shape.circle", size, size, (u, v, x, y) =>
            {
                float d = new Vector2(u - 0.5f, v - 0.5f).magnitude * 2f;
                float a = Mathf.Clamp01((1f - d) * size * 0.5f);
                return new Color(1, 1, 1, a);
            }, false, true);
        }

        public static Texture2D Ring(int size = 128, float thickness = 0.16f)
        {
            return Generate("shape.ring" + thickness, size, size, (u, v, x, y) =>
            {
                float d = new Vector2(u - 0.5f, v - 0.5f).magnitude * 2f;
                float dist = Mathf.Abs(d - (1f - thickness * 0.5f - 0.02f)) - thickness * 0.5f;
                float a = Mathf.Clamp01(-dist * size * 0.5f);
                return new Color(1, 1, 1, a);
            }, false, true);
        }

        public static Texture2D Glow(int size = 64)
        {
            return Generate("shape.glow", size, size, (u, v, x, y) =>
            {
                float d = new Vector2(u - 0.5f, v - 0.5f).magnitude * 2f;
                float a = Mathf.Clamp01(1f - d);
                return new Color(1, 1, 1, a * a);
            }, false, true);
        }

        public static Texture2D SoftSquare(int size = 64)
        {
            return Generate("shape.softsquare", size, size, (u, v, x, y) =>
            {
                float d = Mathf.Max(Mathf.Abs(u - 0.5f), Mathf.Abs(v - 0.5f)) * 2f;
                float a = Mathf.Clamp01((1f - d) * 6f);
                return new Color(1, 1, 1, a);
            }, false, true);
        }

        /// <summary>Восьмиконечная звезда (руб эль-хизб) — эмблема и украшение интерфейса.</summary>
        public static Texture2D Star8(int size = 256, float inner = 0f)
        {
            return Generate("shape.star8." + inner, size, size, (u, v, x, y) =>
            {
                float fx = Mathf.Abs(u - 0.5f) * 2f, fy = Mathf.Abs(v - 0.5f) * 2f;
                const float s = 0.68f;
                float dsq = s - Mathf.Max(fx, fy);
                float ddi = (s * 1.414f - (fx + fy)) / 1.414f;
                float inside = Mathf.Max(dsq, ddi);
                float a = Mathf.Clamp01(inside * size * 0.5f);
                if (inner > 0f) a *= 1f - Mathf.Clamp01((inside - inner) * size * 0.5f);
                return new Color(1, 1, 1, a);
            }, false, true);
        }

        /// <summary>Скруглённый прямоугольник (для 9-slice спрайтов интерфейса).</summary>
        public static Texture2D RoundedRect(int size, float radius, float border = 0f, float border2Offset = 0f)
        {
            string key = "shape.rrect." + size + "." + radius + "." + border + "." + border2Offset;
            return Generate(key, size, size, (u, v, x, y) =>
            {
                float px = (u - 0.5f) * size, py = (v - 0.5f) * size;
                float hx = size * 0.5f - 1f, hy = size * 0.5f - 1f;
                float qx = Mathf.Abs(px) - (hx - radius), qy = Mathf.Abs(py) - (hy - radius);
                float outside = new Vector2(Mathf.Max(qx, 0), Mathf.Max(qy, 0)).magnitude + Mathf.Min(Mathf.Max(qx, qy), 0f) - radius;
                float a = Mathf.Clamp01(0.5f - outside);
                if (border > 0f)
                {
                    float line = Mathf.Clamp01(0.5f - (Mathf.Abs(outside + border * 0.5f) - border * 0.5f));
                    float line2 = 0f;
                    if (border2Offset > 0f)
                        line2 = Mathf.Clamp01(0.5f - (Mathf.Abs(outside + border2Offset) - 0.75f));
                    return new Color(1, 1, 1, Mathf.Max(line, line2) * a);
                }
                return new Color(1, 1, 1, a);
            }, false, true);
        }

        /// <summary>Вертикальный градиент для фонов интерфейса.</summary>
        public static Texture2D VerticalGradient(string key, Color bottom, Color top)
        {
            return Generate("grad." + key, 4, 128, (u, v, x, y) => Color.Lerp(bottom, top, v), false, true);
        }
    }
}
