using TMPro;
using UnityEngine;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Экран меню (Этап 17.4): собирается кодом из префабов набора, открывается панелью (проявление или ящик),
    /// «назад» закрывает, после закрытия удаляется. Пока открыт хоть один экран — спички не слушают ввод
    /// и новые игроки не входят (BlocksGame). Наследник строит содержимое в Build().
    /// </summary>
    [RequireComponent(typeof(CanvasGroup))]
    public abstract class UiScreen : MonoBehaviour
    {
        private static int open;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStatics() => open = 0;

        /// <summary>Открыт какой-нибудь экран — игре ввод не давать.</summary>
        public static bool BlocksGame => open > 0;

        protected UiPanel Panel { get; private set; }
        protected RectTransform Rect => (RectTransform)transform;
        protected UiTheme Theme => UiTheme.Current;

        /// <summary>Закрылся (кнопкой или «назад»).</summary>
        public event System.Action Closed;

        /// <summary>Создать и открыть экран: dim — затемнить всё позади, popup — поверх других экранов.</summary>
        protected static T Create<T>(string name, bool dim, bool popup = false, UiPanel.Motion motion = UiPanel.Motion.Fade) where T : UiScreen
        {
            var root = UiRoot.Instance;
            var go = new GameObject(name, typeof(RectTransform), typeof(CanvasGroup));
            go.transform.SetParent(popup ? root.Popups : root.Screens, false);
            UiRoot.Stretch((RectTransform)go.transform);
            if (dim)
            {
                var d = UiFactory.Rect(go.transform, "Dim").gameObject.AddComponent<Image>();
                UiRoot.Stretch(d.rectTransform);
                d.rectTransform.offsetMin = new Vector2(-4000f, -4000f); // и за пределами 16:9
                d.rectTransform.offsetMax = new Vector2(4000f, 4000f);
                d.color = new Color(0.08f, 0.05f, 0.03f, 0.72f);
                d.raycastTarget = true; // клики мимо окна не проходят в игру
            }
            var screen = go.AddComponent<T>();
            screen.Panel = go.AddComponent<UiPanel>();
            screen.Panel.Configure(motion, UiPanel.Side.Bottom, true);
            screen.Build();
            screen.Panel.Closed += screen.OnPanelClosed;
            screen.Panel.Open();
            return screen;
        }

        protected abstract void Build();

        /// <summary>Закрыть экран (как «назад»).</summary>
        public void Close() => Panel.Close();

        /// <summary>
        /// Собрать содержимое заново на этом же экране (сменился язык — тексты в списках переведены при сборке).
        /// Экран не пересоздаётся: кто ждёт его закрытия (главное меню — чтобы «камера» вернулась), так и ждёт.
        /// </summary>
        protected void Rebuild()
        {
            for (int i = transform.childCount - 1; i >= 0; i--)
            {
                var child = transform.GetChild(i).gameObject;
                if (child.name == "Dim") continue; // затемнение — от Create, его оставляем
                child.SetActive(false); // уже сейчас не мешает выбрать первую кнопку нового содержимого
                Destroy(child);
            }
            Build();
            Panel.SelectFirst();
        }

        private void OnPanelClosed()
        {
            if (Closed != null) Closed();
            Destroy(gameObject, 0.6f); // после анимации закрытия
        }

        private int createdFrame = -1;

        protected virtual void OnEnable()
        {
            open++;
            if (createdFrame < 0) createdFrame = Time.frameCount;
            UnityEngine.SceneManagement.SceneManager.sceneLoaded += OnSceneLoaded;
        }

        protected virtual void OnDisable()
        {
            open--;
            UnityEngine.SceneManagement.SceneManager.sceneLoaded -= OnSceneLoaded;
        }

        // Новая сцена — экран прошлой сцены не нужен (итог, пауза, настройки)
        private void OnSceneLoaded(UnityEngine.SceneManagement.Scene scene, UnityEngine.SceneManagement.LoadSceneMode mode)
        {
            // Создан в Awake этой же загрузки (главное меню из LobbyBoard) — это наша сцена, не прошлая
            if (Time.frameCount == createdFrame) return;
            if (mode == UnityEngine.SceneManagement.LoadSceneMode.Single) Destroy(gameObject);
        }

        // ---------- Общие кирпичики экранов ----------

        /// <summary>Бумажная панель с лентой-заголовком по центру; возвращает область содержимого (с полями).</summary>
        protected RectTransform Paper(Vector2 size, string titleKey)
        {
            var paper = UiFactory.Image(transform, "panel_dialog", true, "Paper");
            UiFactory.Place(paper.rectTransform, new Vector2(0.5f, 0.5f), size, new Vector2(0f, -20f));
            paper.raycastTarget = true;
            if (!string.IsNullOrEmpty(titleKey))
            {
                var banner = UiFactory.Image(paper.transform, "banner_header", true, "Banner");
                UiFactory.Place(banner.rectTransform, new Vector2(0.5f, 1f), new Vector2(Mathf.Min(760f, size.x - 120f), 126f), new Vector2(0f, 26f));
                var title = UiFactory.LocText(banner.transform, titleKey, 48f, Theme.inkLight, true);
                UiRoot.Stretch(title.rectTransform);
                title.rectTransform.offsetMin = new Vector2(100f, 26f);
                title.rectTransform.offsetMax = new Vector2(-100f, -12f);
                title.enableAutoSizing = true;
                title.fontSizeMin = 24f;
                title.fontSizeMax = 48f;
            }
            var content = UiFactory.Rect(paper.transform, "Content");
            UiRoot.Stretch(content);
            content.offsetMin = new Vector2(70f, 60f);
            content.offsetMax = new Vector2(-70f, string.IsNullOrEmpty(titleKey) ? -60f : -110f);
            return content;
        }

        /// <summary>Кнопка «Назад» внизу слева от панели-содержимого.</summary>
        protected Button BackButton(RectTransform parent, Vector2 anchor, Vector2 position)
        {
            var b = UiPrefabs.Spawn<Button>("SecondaryButton", parent);
            var rt = (RectTransform)b.transform;
            UiFactory.Place(rt, anchor, rt.sizeDelta, position);
            b.GetComponentInChildren<LocText>().Key = "ui.back";
            b.onClick.AddListener(Close);
            return b;
        }

        /// <summary>
        /// Вкладки над областью: закладки tab_off/tab_on и страницы под ними (UiTabs: клик, LB/RB, Q/E).
        /// Возвращает страницы (в них строить содержимое).
        /// </summary>
        protected RectTransform[] Tabs(RectTransform area, string[] keys, float tabWidth = 250f)
        {
            var bar = UiFactory.Rect(area, "Tab Bar");
            bar.anchorMin = new Vector2(0f, 1f);
            bar.anchorMax = new Vector2(1f, 1f);
            bar.pivot = new Vector2(0.5f, 1f);
            bar.sizeDelta = new Vector2(0f, 80f);
            var layout = bar.gameObject.AddComponent<HorizontalLayoutGroup>();
            layout.spacing = 6f;
            layout.childAlignment = TextAnchor.LowerCenter;
            layout.childControlWidth = layout.childControlHeight = false;
            layout.childForceExpandWidth = layout.childForceExpandHeight = false;
            var pagesRoot = UiFactory.Rect(area, "Pages");
            UiRoot.Stretch(pagesRoot);
            pagesRoot.offsetMax = new Vector2(0f, -96f);
            var line = UiFactory.Image(area, "slider_fill", true, "Tab Line"); // полоска под закладками
            line.rectTransform.anchorMin = new Vector2(0f, 1f);
            line.rectTransform.anchorMax = new Vector2(1f, 1f);
            line.rectTransform.sizeDelta = new Vector2(0f, 6f);
            line.rectTransform.anchoredPosition = new Vector2(0f, -84f);
            var buttons = new Button[keys.Length];
            var pages = new RectTransform[keys.Length];
            var pageObjects = new GameObject[keys.Length];
            for (int i = 0; i < keys.Length; i++)
            {
                var tab = UiFactory.Rect(bar, "Tab " + keys[i]);
                tab.sizeDelta = new Vector2(tabWidth, 80f);
                var visual = UiFactory.Image(tab, "tab_off", true, "Visual");
                UiRoot.Stretch(visual.rectTransform);
                visual.raycastTarget = true;
                var label = UiFactory.LocText(visual.transform, keys[i], 28f, Theme.ink, false);
                UiRoot.Stretch(label.rectTransform);
                label.rectTransform.offsetMin = new Vector2(16f, 6f);
                label.rectTransform.offsetMax = new Vector2(-16f, -16f);
                label.enableAutoSizing = true;
                label.fontSizeMin = 16f;
                label.fontSizeMax = 28f;
                var b = tab.gameObject.AddComponent<Button>();
                b.targetGraphic = visual;
                b.transition = Selectable.Transition.None;
                tab.gameObject.AddComponent<UiButtonFx>();
                buttons[i] = b;
                pages[i] = UiFactory.Rect(pagesRoot, "Page " + keys[i]);
                UiRoot.Stretch(pages[i]);
                pageObjects[i] = pages[i].gameObject;
            }
            var tabs = area.gameObject.AddComponent<UiTabs>();
            tabs.Setup(buttons, pageObjects);
            return pages;
        }

        /// <summary>Текст на бумаге (тёмный).</summary>
        protected TextMeshProUGUI Ink(Transform parent, string text, float size, bool heading = false)
        {
            var t = UiFactory.Text(parent, text, size, Theme.ink, heading);
            t.alignment = TextAlignmentOptions.MidlineLeft;
            return t;
        }
    }
}
