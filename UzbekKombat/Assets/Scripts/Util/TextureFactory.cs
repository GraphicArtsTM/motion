using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    /// <summary>
    /// Barcha teksturalar kod orqali yaratiladi: paxsa devor, pishiq g'isht, ko'k koshin (girih),
    /// suzani gilam, yog'och o'ymakorligi, zarra (particle) teksturalari, UI bezaklari.
    /// </summary>
    public static class TextureFactory
    {
        static readonly Dictionary<string, Texture2D> cache = new Dictionary<string, Texture2D>();

        static Texture2D Make(string key, int w, int h, System.Func<float, float, Color> fn, bool mip = true, TextureWrapMode wrap = TextureWrapMode.Repeat, FilterMode filter = FilterMode.Bilinear)
        {
            if (cache.TryGetValue(key, out var t) && t != null) return t;
            t = new Texture2D(w, h, TextureFormat.RGBA32, mip) { name = key, wrapMode = wrap, filterMode = filter, anisoLevel = 4 };
            var px = new Color32[w * h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    px[y * w + x] = fn((x + 0.5f) / w, (y + 0.5f) / h);
            t.SetPixels32(px);
            t.Apply(mip, false);
            cache[key] = t;
            return t;
        }

        public static Texture2D Solid(Color c)
        {
            string key = "solid_" + ColorUtility.ToHtmlStringRGBA(c);
            return Make(key, 4, 4, (u, v) => c, false, TextureWrapMode.Clamp);
        }

        // ---------------- Zarralar ----------------
        public static Texture2D SoftDot() => Make("softdot", 64, 64, (u, v) =>
        {
            float d = Vector2.Distance(new Vector2(u, v), new Vector2(0.5f, 0.5f)) * 2f;
            float a = Mathf.Clamp01(1 - d);
            a = a * a * (3 - 2 * a);
            return new Color(1, 1, 1, a);
        }, true, TextureWrapMode.Clamp);

        public static Texture2D HardDot() => Make("harddot", 64, 64, (u, v) =>
        {
            float d = Vector2.Distance(new Vector2(u, v), new Vector2(0.5f, 0.5f)) * 2f;
            float a = Mathf.Clamp01((1 - d) * 4f);
            return new Color(1, 1, 1, a);
        }, true, TextureWrapMode.Clamp);

        public static Texture2D Ring() => Make("ring", 128, 128, (u, v) =>
        {
            float d = Vector2.Distance(new Vector2(u, v), new Vector2(0.5f, 0.5f)) * 2f;
            float a = Mathf.Clamp01(1 - Mathf.Abs(d - 0.82f) * 9f);
            return new Color(1, 1, 1, a * a);
        }, true, TextureWrapMode.Clamp);

        public static Texture2D Star() => Make("star", 128, 128, (u, v) =>
        {
            Vector2 p = new Vector2(u - 0.5f, v - 0.5f) * 2f;
            float ang = Mathf.Atan2(p.y, p.x);
            float r = p.magnitude;
            float k = Mathf.Abs(Mathf.Cos(ang * 2f));
            float edge = Mathf.Lerp(0.18f, 1f, Mathf.Pow(k, 8f));
            float a = Mathf.Clamp01((edge - r) * 6f);
            float glow = Mathf.Clamp01(1 - r) * 0.5f;
            return new Color(1, 1, 1, Mathf.Clamp01(a + glow * glow));
        }, true, TextureWrapMode.Clamp);

        public static Texture2D Smoke() => Make("smoke", 128, 128, (u, v) =>
        {
            float d = Vector2.Distance(new Vector2(u, v), new Vector2(0.5f, 0.5f)) * 2f;
            float n = Noise.Fbm(u * 6, v * 6, 4, 3);
            float a = Mathf.Clamp01(1 - d) * Mathf.Clamp01(n * 1.6f - 0.2f);
            return new Color(1, 1, 1, a);
        }, true, TextureWrapMode.Clamp);

        public static Texture2D Slash() => Make("slash", 128, 64, (u, v) =>
        {
            float y = Mathf.Abs(v - 0.5f) * 2f;
            float a = Mathf.Clamp01(1 - y) * Mathf.Sin(u * Mathf.PI);
            return new Color(1, 1, 1, Mathf.Pow(a, 1.5f));
        }, true, TextureWrapMode.Clamp);

        public static Texture2D TrailGradient() => Make("trail", 64, 32, (u, v) =>
        {
            float a = Mathf.Pow(1 - u, 1.3f) * (0.12f + 0.88f * v * v);
            float core = Mathf.Clamp01((v - 0.8f) * 5f) * (1 - u);
            return new Color(1, 1, 1, Mathf.Clamp01(a + core * 0.5f));
        }, false, TextureWrapMode.Clamp);

        // ---------------- Arena ----------------
        /// <summary>Tuproq (hovli yeri).</summary>
        public static Texture2D Earth() => Make("earth", 256, 256, (u, v) =>
        {
            float n = Noise.FbmTiled(u * 8, v * 8, 8, 5, 11);
            float n2 = Noise.FbmTiled(u * 32, v * 32, 32, 3, 12);
            Color a = ColorUtil.Hex("#9a7652"), b = ColorUtil.Hex("#c69c6d"), c = ColorUtil.Hex("#7d5a3c");
            Color col = Color.Lerp(a, b, n);
            col = Color.Lerp(col, c, Mathf.Clamp01((n2 - 0.6f) * 3f));
            float pebble = Noise.ValueTiled(u * 64, v * 64, 64, 13);
            if (pebble > 0.86f) col = Color.Lerp(col, ColorUtil.Hex("#d8c0a0"), 0.5f);
            return col;
        });

        /// <summary>Paxsa / xom g'isht devor, somon izlari bilan.</summary>
        public static Texture2D MudBrick() => Make("mudbrick", 256, 256, (u, v) =>
        {
            float rows = 8, cols = 4;
            float ry = v * rows;
            int row = Mathf.FloorToInt(ry);
            float rx = u * cols + (row % 2) * 0.5f;
            float fx = rx - Mathf.Floor(rx), fy = ry - row;
            float mortar = (fx < 0.04f || fx > 0.96f || fy < 0.07f || fy > 0.93f) ? 1 : 0;
            float n = Noise.FbmTiled(u * 16, v * 16, 16, 4, 21);
            float straw = Noise.ValueTiled(u * 128, v * 24, 128, 22) > 0.8f ? 1 : 0;
            Color brick = Color.Lerp(ColorUtil.Hex("#b48a5e"), ColorUtil.Hex("#d1ab7c"), n);
            brick = Color.Lerp(brick, ColorUtil.Hex("#e3c99a"), straw * 0.35f);
            float tint = Noise.ValueTiled(Mathf.Floor(rx) * 3.1f, row * 1.7f, 64, 23);
            brick *= 0.92f + tint * 0.12f;
            Color mort = ColorUtil.Hex("#8f6c4b");
            return Color.Lerp(brick, mort, mortar * 0.8f);
        });

        /// <summary>Suvalgan loy devor (ganch emas, loy suvoq).</summary>
        public static Texture2D Plaster() => Make("plaster", 256, 256, (u, v) =>
        {
            float n = Noise.FbmTiled(u * 6, v * 6, 6, 5, 31);
            float crack = Mathf.Abs(Noise.FbmTiled(u * 10, v * 10, 10, 3, 32) - 0.5f) < 0.012f ? 1 : 0;
            Color c = Color.Lerp(ColorUtil.Hex("#c9a77c"), ColorUtil.Hex("#e0c497"), n);
            return Color.Lerp(c, ColorUtil.Hex("#8a6a4a"), crack * 0.6f);
        });

        /// <summary>Pishiq g'isht yo'lak ("archa" naqsh).</summary>
        public static Texture2D BrickPaving() => Make("paving", 256, 256, (u, v) =>
        {
            float s = 8f;
            float x = u * s, y = v * s;
            int ix = Mathf.FloorToInt(x), iy = Mathf.FloorToInt(y);
            float fx = x - ix, fy = y - iy;
            bool horiz = ((ix + iy) & 1) == 0;
            float half = horiz ? fy : fx;
            float along = horiz ? fx : fy;
            float mortar = (half > 0.47f && half < 0.53f) || along < 0.04f || along > 0.96f || half < 0.03f || half > 0.97f ? 1 : 0;
            float n = Noise.FbmTiled(u * 24, v * 24, 24, 3, 41);
            float tint = Noise.ValueTiled(ix * 2 + (half > 0.5f ? 1 : 0), iy * 2, 64, 42);
            Color b = Color.Lerp(ColorUtil.Hex("#a85b3a"), ColorUtil.Hex("#c9835a"), tint);
            b *= 0.85f + n * 0.3f;
            return Color.Lerp(b, ColorUtil.Hex("#6e4a35"), mortar * 0.85f);
        });

        /// <summary>Ko'k koshin — sakkiz qirrali yulduzli girih naqsh (Samarqand uslubi).</summary>
        public static Texture2D GirihTile() => Make("girih", 256, 256, (u, v) =>
        {
            float cells = 2f;
            float x = u * cells, y = v * cells;
            float fx = x - Mathf.Floor(x) - 0.5f, fy = y - Mathf.Floor(y) - 0.5f;
            Vector2 p = new Vector2(fx, fy);
            float r = p.magnitude;
            float ang = Mathf.Atan2(p.y, p.x);
            float seg = Mathf.PI / 4f;
            float a = Mathf.Abs(Mathf.Repeat(ang + seg * 0.5f, seg) - seg * 0.5f);
            float starR = 0.36f / Mathf.Cos(Mathf.Min(a, seg * 0.5f) * 1.0f) * (1 - 0.32f * (a / (seg * 0.5f)));
            float a2 = Mathf.Abs(Mathf.Repeat(ang, seg) - seg * 0.5f);
            float starR2 = 0.36f / Mathf.Cos(Mathf.Min(a2, seg * 0.5f)) * (1 - 0.32f * (a2 / (seg * 0.5f)));
            float star = Mathf.Max(r < starR ? 1 : 0, r < starR2 ? 1 : 0);
            float edge = Mathf.Min(Mathf.Abs(r - starR), Mathf.Abs(r - starR2));
            Color cobalt = ColorUtil.Hex("#123c8c"), turq = ColorUtil.Hex("#1aa3b0"), cream = ColorUtil.Hex("#f2e6c9"), gold = ColorUtil.Hex("#e0b43c");
            Color col = cobalt;
            // Burchak kvadratlari (oraliq shakllar)
            float corner = Mathf.Max(Mathf.Abs(fx), Mathf.Abs(fy));
            if (corner > 0.43f) col = turq;
            if (star > 0.5f) col = turq;
            if (r < 0.14f) col = cream;
            if (r < 0.07f) col = gold;
            float line = Mathf.Clamp01(1 - edge * 70f);
            if (Mathf.Abs(corner - 0.43f) < 0.012f) line = 1;
            col = Color.Lerp(col, cream, line * 0.9f);
            float glaze = Noise.FbmTiled(u * 8, v * 8, 8, 3, 51);
            return col * (0.9f + glaze * 0.18f);
        });

        /// <summary>Majolika chegara bandi (islimiy o'simlik naqsh soddalashtirilgan).</summary>
        public static Texture2D TileBorder() => Make("tileborder", 256, 64, (u, v) =>
        {
            Color bg = ColorUtil.Hex("#0f2f73"), vine = ColorUtil.Hex("#2bb3bd"), flower = ColorUtil.Hex("#f4e8cf"), yel = ColorUtil.Hex("#e6b24a");
            float x = u * 4f, y = v;
            float wave = 0.5f + 0.28f * Mathf.Sin(x * Mathf.PI * 2f);
            float dv = Mathf.Abs(y - wave);
            Color c = bg;
            if (dv < 0.06f) c = vine;
            float fxp = x - Mathf.Floor(x);
            Vector2 c1 = new Vector2(0.25f, 0.5f + 0.28f), c2 = new Vector2(0.75f, 0.5f - 0.28f);
            Vector2 pp = new Vector2(fxp, y);
            float d1 = Vector2.Distance(pp, c1), d2 = Vector2.Distance(pp, c2);
            float dmin = Mathf.Min(d1, d2);
            if (dmin < 0.14f) c = flower;
            if (dmin < 0.06f) c = yel;
            if (y < 0.08f || y > 0.92f) c = flower;
            if (y < 0.04f || y > 0.96f) c = bg;
            return c;
        });

        /// <summary>Suzani gilam — qizil medalyonlar ("oy-gul"), krem fon, chegara.</summary>
        public static Texture2D Suzani() => Make("suzani", 512, 256, (u, v) =>
        {
            Color cream = ColorUtil.Hex("#efe0c2"), red = ColorUtil.Hex("#b3242a"), dark = ColorUtil.Hex("#5a1a22"),
                green = ColorUtil.Hex("#2f5a3c"), gold = ColorUtil.Hex("#d9a441"), indigo = ColorUtil.Hex("#25306e");
            float bx = Mathf.Min(u, 1 - u) * 2f, by = Mathf.Min(v, 1 - v);
            // Chegara
            if (by < 0.1f || bx < 0.05f)
            {
                float t = by < 0.1f ? u * 24f : v * 12f;
                float f = t - Mathf.Floor(t);
                float d = Mathf.Abs(f - 0.5f);
                Color c = dark;
                float inner = by < 0.1f ? by / 0.1f : bx / 0.05f;
                if (d < 0.25f && inner > 0.25f && inner < 0.8f) c = gold;
                if (d < 0.12f && inner > 0.38f && inner < 0.66f) c = red;
                if (inner > 0.9f) c = gold;
                return c;
            }
            // Medalyonlar panjarasi
            float gx = (u - 0.05f) / 0.9f * 4f, gy = (v - 0.1f) / 0.8f * 2f;
            float cx = gx - Mathf.Floor(gx) - 0.5f, cy = gy - Mathf.Floor(gy) - 0.5f;
            Vector2 p = new Vector2(cx, cy * 0.9f);
            float r = p.magnitude;
            float ang = Mathf.Atan2(p.y, p.x);
            float petals = 0.36f + 0.06f * Mathf.Cos(ang * 8f);
            Color col = cream;
            // Novdalar
            float vine = Mathf.Abs(Mathf.Sin((u * 18f + Mathf.Sin(v * 20f)) * Mathf.PI));
            if (vine < 0.08f && r > petals + 0.04f) col = green;
            if (r < petals) col = red;
            if (r < petals - 0.05f) col = dark;
            if (r < 0.22f) col = red;
            if (r < 0.2f && Mathf.Abs(Mathf.Cos(ang * 6f)) > 0.7f) col = gold;
            if (r < 0.1f) col = indigo;
            if (r < 0.05f) col = cream;
            float fiber = Noise.Value(u * 400, v * 200, 61) * 0.08f;
            return col * (0.94f + fiber);
        });

        /// <summary>Gilam (palos) — qizil-to'q ko'k, geometrik.</summary>
        public static Texture2D Carpet() => Make("carpet", 256, 512, (u, v) =>
        {
            Color red = ColorUtil.Hex("#8e1b1f"), navy = ColorUtil.Hex("#1d2550"), ivory = ColorUtil.Hex("#e8d7b0"), orange = ColorUtil.Hex("#c8642a");
            float bx = Mathf.Min(u, 1 - u), by = Mathf.Min(v, 1 - v) * 0.5f;
            float b = Mathf.Min(bx, by);
            if (b < 0.04f) return navy;
            if (b < 0.06f) return ivory;
            if (b < 0.11f)
            {
                float t = (bx < by ? v * 16 : u * 8);
                float f = Mathf.Abs(t - Mathf.Floor(t) - 0.5f);
                return f < 0.2f ? orange : navy;
            }
            if (b < 0.125f) return ivory;
            float gx = u * 3f, gy = v * 6f;
            float cx = Mathf.Abs(gx - Mathf.Floor(gx) - 0.5f), cy = Mathf.Abs(gy - Mathf.Floor(gy) - 0.5f);
            float diamond = cx + cy;
            Color c = red;
            if (diamond < 0.42f) c = navy;
            if (diamond < 0.32f) c = orange;
            if (diamond < 0.22f) c = ivory;
            if (diamond < 0.12f) c = red;
            return c * (0.92f + Noise.Value(u * 300, v * 600, 71) * 0.1f);
        });

        /// <summary>Yog'och (o'ymakor ustun va to'sinlar uchun).</summary>
        public static Texture2D Wood() => Make("wood", 128, 256, (u, v) =>
        {
            float grain = Mathf.Sin((u * 20f + Noise.FbmTiled(u * 4, v * 2, 4, 3, 81) * 6f) * Mathf.PI);
            Color a = ColorUtil.Hex("#6b4226"), b = ColorUtil.Hex("#94643b");
            return Color.Lerp(a, b, grain * 0.5f + 0.5f) * (0.9f + Noise.Value(u * 64, v * 128, 82) * 0.15f);
        });

        /// <summary>O'ymakor eshik (yog'och panellar + naqsh).</summary>
        public static Texture2D CarvedDoor() => Make("door", 128, 256, (u, v) =>
        {
            Color wood = ColorUtil.Hex("#7a4b2a"), dark = ColorUtil.Hex("#3e2414"), light = ColorUtil.Hex("#a8743f");
            float px = u * 2f, py = v * 4f;
            float fx = px - Mathf.Floor(px), fy = py - Mathf.Floor(py);
            float border = Mathf.Min(Mathf.Min(fx, 1 - fx), Mathf.Min(fy, 1 - fy));
            Color c = wood;
            if (border < 0.08f) c = dark;
            else if (border < 0.12f) c = light;
            else
            {
                Vector2 p = new Vector2(fx - 0.5f, fy - 0.5f);
                float r = p.magnitude;
                float ang = Mathf.Atan2(p.y, p.x);
                float rosette = 0.25f + 0.07f * Mathf.Cos(ang * 8);
                if (Mathf.Abs(r - rosette) < 0.03f) c = dark;
                if (r < 0.08f) c = light;
            }
            float grain = Mathf.Sin((u * 40f + Noise.Value(u * 8, v * 8, 91) * 4f) * Mathf.PI) * 0.06f;
            return c * (1 + grain);
        });

        public static Texture2D Mountain() => Make("mountain", 256, 128, (u, v) =>
        {
            float n = Noise.FbmTiled(u * 8, v * 4, 8, 5, 101);
            Color rock = Color.Lerp(ColorUtil.Hex("#6c6f8a"), ColorUtil.Hex("#9a8f9e"), n);
            float snow = Mathf.Clamp01((v - 0.72f + n * 0.2f) * 6f);
            return Color.Lerp(rock, ColorUtil.Hex("#f1ece8"), snow);
        });

        public static Texture2D Leaves() => Make("leaves", 128, 128, (u, v) =>
        {
            float n = Noise.FbmTiled(u * 8, v * 8, 8, 4, 111);
            float n2 = Noise.ValueTiled(u * 32, v * 32, 32, 112);
            Color c = Color.Lerp(ColorUtil.Hex("#3d6b2f"), ColorUtil.Hex("#7aa04a"), n);
            return Color.Lerp(c, ColorUtil.Hex("#2a4a22"), n2 > 0.7f ? 0.5f : 0);
        });

        /// <summary>Suv to'lqinlari uchun ikki kanalli shovqin (R, G).</summary>
        public static Texture2D Ripples() => Make("ripples", 128, 128, (u, v) =>
        {
            float a = Noise.FbmTiled(u * 4, v * 4, 4, 4, 131);
            float b = Noise.FbmTiled(u * 6 + 3, v * 6, 6, 4, 132);
            return new Color(a, b, 0.5f, 1);
        });

        public static Texture2D Water() => Make("water", 128, 128, (u, v) =>
        {
            float n = Noise.FbmTiled(u * 6, v * 6, 6, 4, 121);
            return Color.Lerp(ColorUtil.Hex("#2a6f8f"), ColorUtil.Hex("#7fd0e0"), n);
        });

        // ---------------- UI ----------------
        public static Texture2D VerticalGradient(Color top, Color bottom, int h = 64)
        {
            string key = "vgrad_" + ColorUtility.ToHtmlStringRGBA(top) + ColorUtility.ToHtmlStringRGBA(bottom);
            return Make(key, 4, h, (u, v) => Color.Lerp(bottom, top, v), false, TextureWrapMode.Clamp);
        }

        public static Texture2D HorizontalGradient(Color left, Color right, int w = 128)
        {
            string key = "hgrad_" + ColorUtility.ToHtmlStringRGBA(left) + ColorUtility.ToHtmlStringRGBA(right);
            return Make(key, w, 4, (u, v) => Color.Lerp(left, right, u), false, TextureWrapMode.Clamp);
        }

        /// <summary>Burchaklari bezakli panel foni (UI).</summary>
        public static Texture2D OrnatePanel() => Make("ornatepanel", 256, 256, (u, v) =>
        {
            Color bg = new Color(0.05f, 0.07f, 0.16f, 0.88f);
            Color gold = ColorUtil.Hex("#d9a441");
            float b = Mathf.Min(Mathf.Min(u, 1 - u), Mathf.Min(v, 1 - v));
            Color c = bg;
            if (b < 0.012f) c = gold;
            else if (b > 0.025f && b < 0.032f) c = gold.Mul(0.8f);
            // Burchak yulduzchalari
            Vector2[] cs = { new Vector2(0.06f, 0.06f), new Vector2(0.94f, 0.06f), new Vector2(0.06f, 0.94f), new Vector2(0.94f, 0.94f) };
            foreach (var cc in cs)
            {
                Vector2 p = new Vector2(u, v) - cc;
                float r = p.magnitude;
                float ang = Mathf.Atan2(p.y, p.x);
                float sr = 0.03f + 0.015f * Mathf.Cos(ang * 8f);
                if (r < sr) c = gold;
            }
            // Ichki girih tasviri, juda xira
            float gx = u * 6, gy = v * 6;
            float fx = gx - Mathf.Floor(gx) - 0.5f, fy = gy - Mathf.Floor(gy) - 0.5f;
            float rr = Mathf.Sqrt(fx * fx + fy * fy);
            float aa = Mathf.Atan2(fy, fx);
            if (b > 0.04f && Mathf.Abs(rr - (0.3f + 0.06f * Mathf.Cos(aa * 8))) < 0.015f) c = Color.Lerp(c, gold, 0.12f);
            return c;
        }, false, TextureWrapMode.Clamp);

        public static Texture2D Vignette() => Make("vignette", 128, 128, (u, v) =>
        {
            float d = Vector2.Distance(new Vector2(u, v), new Vector2(0.5f, 0.5f)) * 1.41f;
            float a = Mathf.Clamp01((d - 0.55f) * 1.8f);
            return new Color(0, 0, 0, a * a * 0.85f);
        }, false, TextureWrapMode.Clamp);

        /// <summary>UI uchun yulduzli ornament (8 qirrali).</summary>
        public static Texture2D Rosette() => Make("rosette", 128, 128, (u, v) =>
        {
            Vector2 p = new Vector2(u - 0.5f, v - 0.5f) * 2f;
            float r = p.magnitude, ang = Mathf.Atan2(p.y, p.x);
            float seg = Mathf.PI / 4f;
            float a = Mathf.Abs(Mathf.Repeat(ang, seg) - seg * 0.5f) / (seg * 0.5f);
            float sr = Mathf.Lerp(0.95f, 0.62f, a);
            Color gold = ColorUtil.Hex("#e6b84f"), blue = ColorUtil.Hex("#1a3f8f"), turq = ColorUtil.Hex("#29b0bb");
            if (r > sr) return Color.clear;
            Color c = gold;
            if (r < sr - 0.08f) c = blue;
            if (r < 0.45f) c = turq;
            if (r < 0.37f) c = gold;
            if (r < 0.25f) c = blue;
            float alpha = Mathf.Clamp01((sr - r) * 40f);
            return c.WithA(alpha);
        }, true, TextureWrapMode.Clamp);
    }
}
