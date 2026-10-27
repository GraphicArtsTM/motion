using TMPro;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Переход и загрузка (Этапы 17, 17.5): на экран, как ящик коробка, наезжает обложка — загрузочная картинка
    /// (bg_loading_*), название уровня, совет и мерцающий огонёк; пока грузится сцена, потом уезжает.
    /// Живёт между сценами (создаётся сам при первом вызове), рисуется своим холстом поверх всего интерфейса.
    /// </summary>
    public class MatchboxSleeve : MonoBehaviour
    {
        private static MatchboxSleeve instance;

        private float cover;          // 0 — открыто, 1 — экран закрыт
        private float closeSpeed = 2f, openSpeed = 1.6f;
        private bool closing;
        private float delay, waited;
        private string subtitle = "";
        private bool held;

        private RectTransform panel;
        private CanvasGroup group;
        private TextMeshProUGUI title, tip;
        private Image flame;
        private int tipIndex;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStatics() => instance = null;

        /// <summary>Обложка закрыта, пока не отпустят (Release).</summary>
        public static void Hold(string text)
        {
            var s = Get();
            s.held = true;
            s.cover = 1f;
            s.closing = false;
            s.SetText(text);
        }

        /// <summary>Открыть после Hold.</summary>
        public static void Release()
        {
            var s = Get();
            s.held = false;
            s.delay = 0.1f;
        }

        /// <summary>Экран сейчас закрыт обложкой (полностью или частично).</summary>
        public static bool Visible => instance != null && instance.cover > 0.001f;

        private static MatchboxSleeve Get()
        {
            if (instance != null) return instance;
            var go = new GameObject("Matchbox Sleeve");
            DontDestroyOnLoad(go);
            instance = go.AddComponent<MatchboxSleeve>();
            instance.Build();
            return instance;
        }

        /// <summary>Закрыть коробок за seconds (дальше ждёт загрузки сцены).</summary>
        public static void Close(float seconds, string text)
        {
            var s = Get();
            s.closing = true;
            s.waited = 0f;
            s.closeSpeed = 1f / Mathf.Max(0.05f, seconds);
            s.SetText(text);
        }

        /// <summary>Закрыть сразу (перед загрузкой сцены без анимации закрытия).</summary>
        public static void CoverNow(string text)
        {
            var s = Get();
            if (!s.closing || !string.IsNullOrEmpty(text)) s.SetText(text);
            s.cover = 1f;
            s.closing = true;
            s.waited = 0f;
        }

        /// <summary>Начало игры: экран закрыт и сразу открывается.</summary>
        public static void Intro(string text)
        {
            var s = Get();
            s.cover = 1f;
            s.closing = false;
            s.delay = 0.5f;
            s.SetText(text);
        }

        private void SetText(string text)
        {
            subtitle = text ?? "";
            if (title != null) title.text = subtitle.Length > 0 ? subtitle : Loc.T("loading.title");
            // Новый совет на каждую загрузку (сколько их — по таблице: tip.1, tip.2, … — новые подхватываются сами)
            int tips = 0;
            while (Loc.Has("tip." + (tips + 1))) tips++;
            tipIndex = Random.Range(1, Mathf.Max(1, tips) + 1);
            if (tip != null) tip.text = Loc.Has("tip." + tipIndex) ? Loc.T("tip." + tipIndex) : "";
        }

        // Свой холст поверх всего (в том же UiRoot — тот же масштаб)
        private void Build()
        {
            var root = new GameObject("Sleeve Canvas", typeof(RectTransform), typeof(Canvas), typeof(CanvasGroup), typeof(GraphicRaycaster));
            root.transform.SetParent(UiRoot.Instance.transform, false);
            UiRoot.Stretch((RectTransform)root.transform);
            var canvas = root.GetComponent<Canvas>();
            canvas.overrideSorting = true;
            canvas.sortingOrder = 300;
            group = root.GetComponent<CanvasGroup>();
            panel = UiFactory.Rect(root.transform, "Cover");
            UiRoot.Stretch(panel);
            var art = UiFactory.Rect(panel, "Art Mask");
            UiRoot.Stretch(art);
            art.gameObject.AddComponent<RectMask2D>();
            var bg = UiFactory.Rect(art, "Art").gameObject.AddComponent<Image>();
            var sprites = UiTheme.Current.loadingBackgrounds;
            bg.sprite = sprites != null && sprites.Length > 0 ? sprites[Random.Range(0, sprites.Length)] : null;
            bg.color = bg.sprite != null ? Color.white : new Color(0.16f, 0.11f, 0.08f);
            bg.raycastTarget = true; // пока закрыто — клики не проходят
            var fit = bg.gameObject.AddComponent<AspectRatioFitter>();
            fit.aspectMode = AspectRatioFitter.AspectMode.EnvelopeParent;
            fit.aspectRatio = bg.sprite != null ? bg.sprite.rect.width / bg.sprite.rect.height : 16f / 9f;
            // Кромка «ящика» слева
            var edge = UiFactory.Rect(panel, "Edge").gameObject.AddComponent<Image>();
            edge.color = new Color(0.2f, 0.12f, 0.07f);
            edge.rectTransform.anchorMin = new Vector2(0f, 0f);
            edge.rectTransform.anchorMax = new Vector2(0f, 1f);
            edge.rectTransform.pivot = new Vector2(1f, 0.5f);
            edge.rectTransform.sizeDelta = new Vector2(12f, 0f);
            // Тень снизу — чтобы текст читался
            var shade = UiFactory.Fade(panel, "Shade", false, new Color(0f, 0f, 0f, 0.7f));
            shade.rectTransform.anchorMin = Vector2.zero;
            shade.rectTransform.anchorMax = new Vector2(1f, 0f);
            shade.rectTransform.pivot = new Vector2(0.5f, 0f);
            shade.rectTransform.sizeDelta = new Vector2(0f, 360f);
            // Название, совет, огонёк
            var safe = UiFactory.Rect(panel, "Text");
            UiRoot.Stretch(safe);
            title = UiFactory.Text(safe, "", 68f, UiTheme.Current.inkLight, true);
            title.alignment = TextAlignmentOptions.BottomLeft;
            UiFactory.Place(title.rectTransform, new Vector2(0f, 0f), new Vector2(1400f, 90f), new Vector2(110f + 700f, 140f));
            tip = UiFactory.Text(safe, "", 28f, new Color(1f, 0.92f, 0.8f, 0.9f), false);
            tip.alignment = TextAlignmentOptions.TopLeft;
            tip.textWrappingMode = TextWrappingModes.Normal;
            UiFactory.Place(tip.rectTransform, new Vector2(0f, 0f), new Vector2(1300f, 80f), new Vector2(110f + 650f, 60f));
            flame = UiFactory.Image(safe, "ic_fire", false, "Flame");
            UiFactory.Place(flame.rectTransform, new Vector2(1f, 0f), new Vector2(90f, 90f), new Vector2(-110f, 110f));
            SetText(subtitle);
            Apply();
        }

        private void OnEnable() => SceneManager.sceneLoaded += OnSceneLoaded;
        private void OnDisable() => SceneManager.sceneLoaded -= OnSceneLoaded;

        // Новая сцена загрузилась — немного подождать (тела строятся) и открыть
        private void OnSceneLoaded(Scene scene, LoadSceneMode mode)
        {
            if (!closing) return;
            closing = false;
            delay = 0.3f;
        }

        private void Update()
        {
            float dt = Time.unscaledDeltaTime;
            if (held) cover = 1f;
            else if (closing)
            {
                cover = Mathf.Min(1f, cover + dt * closeSpeed);
                // Сцена так и не загрузилась (отменили, клиент отстал) — открыть
                if (cover >= 1f && (waited += dt) > 8f) closing = false;
            }
            else if (delay > 0f) delay -= dt;
            else cover = Mathf.Max(0f, cover - dt * openSpeed);
            Apply();
        }

        private void Apply()
        {
            if (panel == null) return;
            bool on = cover > 0.001f;
            if (group.gameObject.activeSelf != on) group.gameObject.SetActive(on);
            if (!on) return;
            // Ящик: быстро в начале, мягко в конце
            float k = 1f - Mathf.Pow(1f - cover, 3f);
            float width = ((RectTransform)panel.parent).rect.width;
            panel.anchoredPosition = new Vector2(width * (1f - k), 0f);
            // Огонёк «дышит», пока грузится
            float t = Time.unscaledTime;
            flame.rectTransform.localScale = Vector3.one * (0.9f + 0.12f * Mathf.PerlinNoise(t * 4f, 0.5f));
            flame.color = new Color(1f, 1f, 1f, 0.75f + 0.25f * Mathf.Sin(t * 9f));
        }
    }
}
