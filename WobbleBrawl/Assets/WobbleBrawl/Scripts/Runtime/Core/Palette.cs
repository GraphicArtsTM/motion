using UnityEngine;

namespace WobbleBrawl
{
    public static class Palette
    {
        public static readonly Color[] Players =
        {
            new Color(0.96f, 0.32f, 0.30f), // red
            new Color(0.26f, 0.56f, 0.98f), // blue
            new Color(0.36f, 0.84f, 0.36f), // green
            new Color(1.00f, 0.80f, 0.22f), // yellow
            new Color(0.74f, 0.42f, 0.96f), // purple
            new Color(1.00f, 0.56f, 0.18f), // orange
            new Color(0.26f, 0.84f, 0.84f), // teal
            new Color(1.00f, 0.52f, 0.76f), // pink
        };

        public static readonly string[] BotNames =
        {
            "Пельмень", "Батон", "Кефир", "Шпрот", "Пончик", "Борщ", "Сырник", "Кабачок",
            "Холодец", "Вареник", "Бублик", "Огурчик",
        };

        public static readonly Color UiBg = new Color(0.07f, 0.06f, 0.11f, 0.86f);
        public static readonly Color UiPanel = new Color(0.13f, 0.11f, 0.20f, 0.92f);
        public static readonly Color UiAccent = new Color(1.00f, 0.78f, 0.20f);
        public static readonly Color UiText = Color.white;
        public static readonly Color UiDim = new Color(1f, 1f, 1f, 0.55f);
        public static readonly Color UiDanger = new Color(1f, 0.35f, 0.3f);

        public static Color Darken(Color c, float k) => new Color(c.r * k, c.g * k, c.b * k, c.a);
        public static Color WithAlpha(Color c, float a) => new Color(c.r, c.g, c.b, a);
        public static string Hex(Color c) => ColorUtility.ToHtmlStringRGB(c);
        public static string Paint(string text, Color c) => $"<color=#{Hex(c)}>{text}</color>";
    }
}
