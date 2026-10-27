using PushPals.Players;
using PushPals.Ragdoll.Visual;
using UnityEngine;

namespace PushPals.Level
{
    /// <summary>
    /// Табличка-подсказка обучающего уровня: колышек с карточкой, текст появляется над ней, когда рядом
    /// игрок (кнопки и для геймпада, и для клавиатуры). Позиция — низ колышка.
    /// Пока это надписи OnGUI; настоящий интерфейс (значки кнопок по устройству игрока) — Этап 17.
    /// </summary>
    public class TutorialSign : MonoBehaviour
    {
        [TextArea(2, 6)]
        [SerializeField] private string text = "Подсказка";
        [Tooltip("Текст виден, когда игрок ближе этого (0 — всегда)")]
        [SerializeField] private float showRadius = 6f;
        [Tooltip("Где карточка с текстом над колышком")]
        [SerializeField] private float height = 2.6f;
        [SerializeField] private Color post = new Color(0.62f, 0.45f, 0.28f);
        [SerializeField] private Color card = new Color(1f, 0.97f, 0.88f);
        [SerializeField] private Color outline = new Color(0.28f, 0.17f, 0.09f);

        private static readonly System.Collections.Generic.List<TutorialSign> all = new System.Collections.Generic.List<TutorialSign>();
        private float nearest = float.MaxValue; // до ближайшего игрока

        private GUIStyle style;
        private Texture2D pixel;
        private float alpha;

        public string Text { get => text; set => text = value; }

        private void Awake()
        {
            // Колышек и пустая карточка-«значок вопроса» в мире (текст рисуется поверх экрана)
            var stick = MatchVisual.AddPill(transform, 0.09f, height * 0.6f, post, -6);
            stick.transform.localPosition = new Vector3(0f, height * 0.3f, 0f);
            var o = MatchVisual.AddPill(transform, 0.12f, 1f, outline, -5); o.size = new Vector2(0.75f, 0.55f);
            o.transform.localPosition = new Vector3(0f, height * 0.6f, 0f);
            var c = MatchVisual.AddPill(transform, 0.1f, 1f, card, -4); c.size = new Vector2(0.67f, 0.47f);
            c.transform.localPosition = new Vector3(0f, height * 0.6f, 0f);
            var mark = MatchVisual.AddEllipse(transform, new Vector2(0.16f, 0.16f), new Color(0.85f, 0.22f, 0.16f), -3);
            mark.transform.localPosition = new Vector3(0f, height * 0.6f, 0f);
        }

        private void OnEnable() => all.Add(this);
        private void OnDisable() => all.Remove(this);

        private void Update()
        {
            nearest = float.MaxValue;
            var manager = PlayerManager.Instance;
            if (manager != null)
                foreach (var p in manager.Visible)
                    if (p != null && p.Ragdoll.Body.IsBuilt)
                        nearest = Mathf.Min(nearest, Vector2.Distance(p.Ragdoll.Body.Torso.Body.position, transform.position));
            // Видна только ближайшая к игрокам табличка (две рядом налезают друг на друга); уровень пройден — не видна
            bool show = showRadius <= 0f || nearest < showRadius;
            if (show && showRadius > 0f) // вывески, видные всегда (showRadius 0), не спорят с подсказками
                foreach (var other in all)
                    if (other != this && other.showRadius > 0f && other.nearest < nearest && other.nearest < other.showRadius) { show = false; break; }
            // Пока показано название уровня (первые 5 с) и после прохождения — таблички не мешают
            if (LevelRun.Instance != null && (LevelRun.Instance.Finished || LevelRun.Instance.Elapsed < 5f)) show = false;
            alpha = Mathf.MoveTowards(alpha, show ? 1f : 0f, Time.deltaTime * 4f);
        }

        private void OnGUI()
        {
            if (PushPals.UI.UiScreen.BlocksGame) return; // открыт экран меню — мировые надписи не поверх него
            if (alpha <= 0.01f) return;
            var cam = Camera.main;
            if (cam == null) return;
            if (style == null)
            {
                style = new GUIStyle(GUI.skin.label) { fontSize = 17, alignment = TextAnchor.MiddleCenter, wordWrap = true };
                style.normal.textColor = new Color(0.25f, 0.15f, 0.07f);
                pixel = new Texture2D(1, 1);
                pixel.SetPixel(0, 0, Color.white);
                pixel.Apply();
            }
            Vector3 screen = cam.WorldToScreenPoint(transform.position + Vector3.up * (height + 0.3f));
            if (screen.z < 0f) return;
            float width = 300f;
            string shown = PushPals.UI.Loc.Auto(text); // в сцене записано по-русски — на другом языке перевод из таблицы
            float textHeight = style.CalcHeight(new GUIContent(shown), width - 20f);
            var rect = new Rect(screen.x - width * 0.5f, Screen.height - screen.y - textHeight - 16f, width, textHeight + 16f);
            var old = GUI.color;
            GUI.color = new Color(outline.r, outline.g, outline.b, alpha * 0.9f);
            GUI.DrawTexture(new Rect(rect.x - 2f, rect.y - 2f, rect.width + 4f, rect.height + 4f), pixel);
            GUI.color = new Color(card.r, card.g, card.b, alpha * 0.95f);
            GUI.DrawTexture(rect, pixel);
            GUI.color = new Color(1f, 1f, 1f, alpha);
            GUI.Label(new Rect(rect.x + 10f, rect.y + 8f, rect.width - 20f, textHeight), shown, style);
            GUI.color = old;
        }
    }
}
