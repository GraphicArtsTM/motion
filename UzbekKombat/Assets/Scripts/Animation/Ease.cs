using UnityEngine;

namespace UzbekKombat
{
    public enum Ease { Linear, InQuad, OutQuad, InOutQuad, OutCubic, InCubic, InOutCubic, OutExpo, OutBack, InBack, OutElastic, Hold }

    public static class EaseUtil
    {
        public static float Apply(Ease e, float t)
        {
            t = Mathf.Clamp01(t);
            switch (e)
            {
                case Ease.InQuad: return t * t;
                case Ease.OutQuad: return 1 - (1 - t) * (1 - t);
                case Ease.InOutQuad: return t < 0.5f ? 2 * t * t : 1 - Mathf.Pow(-2 * t + 2, 2) / 2;
                case Ease.OutCubic: return 1 - Mathf.Pow(1 - t, 3);
                case Ease.InCubic: return t * t * t;
                case Ease.InOutCubic: return t < 0.5f ? 4 * t * t * t : 1 - Mathf.Pow(-2 * t + 2, 3) / 2;
                case Ease.OutExpo: return t >= 1 ? 1 : 1 - Mathf.Pow(2, -10 * t);
                case Ease.OutBack: { const float c1 = 1.70158f, c3 = c1 + 1; return 1 + c3 * Mathf.Pow(t - 1, 3) + c1 * Mathf.Pow(t - 1, 2); }
                case Ease.InBack: { const float c1 = 1.70158f, c3 = c1 + 1; return c3 * t * t * t - c1 * t * t; }
                case Ease.OutElastic:
                    {
                        const float c4 = (2 * Mathf.PI) / 3;
                        return t <= 0 ? 0 : t >= 1 ? 1 : Mathf.Pow(2, -10 * t) * Mathf.Sin((t * 10 - 0.75f) * c4) + 1;
                    }
                case Ease.Hold: return 0f;
                default: return t;
            }
        }
    }
}
