using PushPals.Ragdoll;
using UnityEngine;

namespace PushPals.UI
{
    /// <summary>
    /// Колесо эмоций вокруг головы игрока: 8 штук по кругу (сверху по часовой). Держать LB / Q и показать стиком
    /// (или мышью) — отпустить. Крестовина сразу даёт верхнюю/правую/нижнюю/левую, на клавиатуре — 1–8.
    /// </summary>
    public static class EmoteWheel
    {
        private const float Radius = 78f;
        private static GUIStyle style;
        private static Texture2D dot;

        /// <summary>Номер эмоции (1..8) по направлению (вверх — 1, дальше по часовой); 0 — направление слишком слабое.</summary>
        public static int Pick(Vector2 dir, float deadZone)
        {
            if (dir.magnitude < deadZone) return 0;
            float angle = Mathf.Atan2(dir.x, dir.y) * Mathf.Rad2Deg; // 0 — вверх, по часовой
            if (angle < 0f) angle += 360f;
            return Mathf.RoundToInt(angle / 45f) % RagdollEmote.Count + 1;
        }

        /// <summary>Нарисовать колесо вокруг точки экрана (GUI-координаты); selected — подсвеченная.</summary>
        public static void Draw(Vector2 center, int selected, Color color)
        {
            if (style == null || dot == null)
            {
                style = new GUIStyle(GUI.skin.label) { alignment = TextAnchor.MiddleCenter, fontSize = 13, fontStyle = FontStyle.Bold };
                dot = new Texture2D(1, 1);
                dot.SetPixel(0, 0, Color.white);
                dot.Apply();
            }
            var old = GUI.color;
            for (int i = 1; i <= RagdollEmote.Count; i++)
            {
                float a = (i - 1) * 45f * Mathf.Deg2Rad;
                Vector2 p = center + new Vector2(Mathf.Sin(a), -Mathf.Cos(a)) * Radius;
                var r = new Rect(p.x - 38f, p.y - 13f, 76f, 26f);
                bool on = i == selected;
                GUI.color = on ? color : new Color(0.28f, 0.17f, 0.09f, 0.9f);
                GUI.DrawTexture(new Rect(r.x - 2f, r.y - 2f, r.width + 4f, r.height + 4f), dot);
                GUI.color = on ? new Color(1f, 0.9f, 0.55f) : new Color(1f, 0.97f, 0.88f, 0.95f);
                GUI.DrawTexture(r, dot);
                GUI.color = Color.white;
                style.normal.textColor = new Color(0.25f, 0.15f, 0.07f);
                GUI.Label(r, i > 0 ? Loc.T("emote." + i) : RagdollEmote.Names[i], style);
            }
            GUI.color = old;
        }
    }
}
