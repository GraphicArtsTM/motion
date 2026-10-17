using UnityEngine;

namespace UzbekKombat
{
    public static class Noise
    {
        static float Hash(int x, int y, int seed)
        {
            unchecked
            {
                int h = x * 374761393 + y * 668265263 + seed * 1442695041;
                h = (h ^ (h >> 13)) * 1274126177;
                h ^= h >> 16;
                return (h & 0x7fffffff) / (float)0x7fffffff;
            }
        }

        public static float Value(float x, float y, int seed = 0)
        {
            int xi = Mathf.FloorToInt(x), yi = Mathf.FloorToInt(y);
            float xf = x - xi, yf = y - yi;
            float u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
            float a = Hash(xi, yi, seed), b = Hash(xi + 1, yi, seed), c = Hash(xi, yi + 1, seed), d = Hash(xi + 1, yi + 1, seed);
            return Mathf.Lerp(Mathf.Lerp(a, b, u), Mathf.Lerp(c, d, u), v);
        }

        /// <summary>Takrorlanuvchi (tileable) shovqin — period birlikda.</summary>
        public static float ValueTiled(float x, float y, int period, int seed = 0)
        {
            int xi = Mathf.FloorToInt(x), yi = Mathf.FloorToInt(y);
            float xf = x - xi, yf = y - yi;
            float u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
            int x0 = Mod(xi, period), x1 = Mod(xi + 1, period), y0 = Mod(yi, period), y1 = Mod(yi + 1, period);
            float a = Hash(x0, y0, seed), b = Hash(x1, y0, seed), c = Hash(x0, y1, seed), d = Hash(x1, y1, seed);
            return Mathf.Lerp(Mathf.Lerp(a, b, u), Mathf.Lerp(c, d, u), v);
        }

        public static float Fbm(float x, float y, int octaves = 4, int seed = 0)
        {
            float sum = 0, amp = 0.5f, f = 1, norm = 0;
            for (int i = 0; i < octaves; i++)
            {
                sum += Value(x * f, y * f, seed + i * 17) * amp;
                norm += amp; amp *= 0.5f; f *= 2.03f;
            }
            return sum / norm;
        }

        public static float FbmTiled(float x, float y, int period, int octaves = 4, int seed = 0)
        {
            float sum = 0, amp = 0.5f, norm = 0;
            int p = period; float f = 1;
            for (int i = 0; i < octaves; i++)
            {
                sum += ValueTiled(x * f, y * f, p, seed + i * 17) * amp;
                norm += amp; amp *= 0.5f; f *= 2; p *= 2;
            }
            return sum / norm;
        }

        public static int Mod(int a, int m) { int r = a % m; return r < 0 ? r + m : r; }

        public static float Rand01(int i, int seed = 0) => Hash(i, i * 31 + 7, seed);
    }

    public static class ColorUtil
    {
        public static Color Hex(string hex)
        {
            ColorUtility.TryParseHtmlString(hex.StartsWith("#") ? hex : "#" + hex, out var c);
            return c;
        }

        public static Color Mul(this Color c, float k) => new Color(c.r * k, c.g * k, c.b * k, c.a);
        public static Color WithA(this Color c, float a) => new Color(c.r, c.g, c.b, a);
    }
}
