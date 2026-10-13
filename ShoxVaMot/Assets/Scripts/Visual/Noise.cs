using UnityEngine;

namespace Shatranj.Visual
{
    /// <summary>Детерминированный тайлящийся value-noise для процедурных текстур.</summary>
    public static class Noise
    {
        public static float Hash(int x, int y, int seed)
        {
            unchecked
            {
                int h = x * 374761393 + y * 668265263 + seed * 1442695041;
                h = (h ^ (h >> 13)) * 1274126177;
                h ^= h >> 16;
                return (h & 0x7fffffff) / (float)0x7fffffff;
            }
        }

        static int Wrap(int v, int p) { if (p <= 0) return v; v %= p; return v < 0 ? v + p : v; }

        static float Smooth(float t) { return t * t * (3f - 2f * t); }

        /// <summary>Value noise с периодом (px, py) по целочисленной решётке.</summary>
        public static float Value(float x, float y, int px, int py, int seed)
        {
            int xi = Mathf.FloorToInt(x), yi = Mathf.FloorToInt(y);
            float fx = Smooth(x - xi), fy = Smooth(y - yi);
            int x0 = Wrap(xi, px), x1 = Wrap(xi + 1, px), y0 = Wrap(yi, py), y1 = Wrap(yi + 1, py);
            float a = Hash(x0, y0, seed), b = Hash(x1, y0, seed), c = Hash(x0, y1, seed), d = Hash(x1, y1, seed);
            return Mathf.Lerp(Mathf.Lerp(a, b, fx), Mathf.Lerp(c, d, fx), fy);
        }

        /// <summary>Тайлящийся fBm: u,v в [0,1), базовые частоты fx, fy (целые).</summary>
        public static float Fbm(float u, float v, int fx, int fy, int seed, int octaves = 4)
        {
            float sum = 0f, amp = 0.5f, norm = 0f;
            int px = fx, py = fy;
            for (int o = 0; o < octaves; o++)
            {
                sum += amp * Value(u * px, v * py, px, py, seed + o * 31);
                norm += amp;
                amp *= 0.5f;
                px *= 2; py *= 2;
            }
            return sum / norm;
        }
    }
}
