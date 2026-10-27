using System.Collections;
using System.Collections.Generic;
using TMPro;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Главное меню-стол (Этап 17.4): ночная кухня, на столе предметы — коробок «Играть», банки-телефон «Онлайн»,
    /// линейка «Настройки», шкаф из напёрстков «Гардероб», блокнот «Коллекция», дверь «Выход».
    /// Наведение мышью или выбор стрелками/геймпадом — мягкое свечение, подпись и спичка-указатель над предметом;
    /// выбор — «камера» летит к предмету и открывается экран (закрыли — летит обратно). Свеча мерцает, в её свете
    /// кружатся пылинки. «Играть» — коробок открывается, внутри лобби. Заменяет титульный экран Этапа 17.
    /// </summary>
    public class MainMenuScreen : UiScreen
    {
        // Предмет: картинка, подпись, где стоит (доли картинки фона: x — середина, y — низ, сверху вниз), высота
        private struct Prop
        {
            public string sprite, key;
            public Vector2 at;
            public float height;
            public Prop(string sprite, string key, float x, float y, float h) { this.sprite = sprite; this.key = key; at = new Vector2(x, y); height = h; }
        }

        private static readonly Prop[] Props =
        {
            new Prop("menu_obj_exit", "menu.exit", 0.115f, 0.70f, 0.47f),
            new Prop("menu_obj_wardrobe", "menu.wardrobe", 0.275f, 0.79f, 0.40f),
            new Prop("menu_obj_online", "menu.online", 0.425f, 0.90f, 0.25f),
            new Prop("menu_obj_play", "menu.play", 0.585f, 0.87f, 0.31f),
            new Prop("menu_obj_collection", "menu.collection", 0.755f, 0.93f, 0.23f),
            new Prop("menu_obj_settings", "menu.settings", 0.875f, 0.995f, 0.21f),
        };
        private const int Exit = 0, Wardrobe = 1, OnlineProp = 2, Play = 3, Collection = 4, Settings = 5;

        // Где пламя свечи на картинке фона (доли, сверху вниз)
        private static readonly Vector2 Candle = new Vector2(0.855f, 0.27f);

        public static bool Showing { get; private set; }

        // Из игры попросили главное меню: показать, когда загрузится коробок (LobbyBoard)
        private static bool returnRequested;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetReturn() => returnRequested = false;

        /// <summary>Коробок загрузился: показать ли главное меню (просили из игры). Флаг сбрасывается.</summary>
        public static bool ConsumeReturn()
        {
            bool r = returnRequested;
            returnRequested = false;
            return r;
        }

        /// <summary>
        /// Из паузы — в главное меню: сетевая игра заканчивается (у хоста — у всех), с уровня сначала в коробок
        /// (меню стоит на столе над ним), в коробке у себя — сразу.
        /// </summary>
        public static void ReturnFromGame()
        {
            bool wasClient = Online.IsClientView;
            if (Online.IsActive && Online.LeaveSession != null) Online.LeaveSession();
            // Клиент видел мир хоста (предметы кинематические) — коробок грузим заново и в лобби
            bool inOwnLobby = PushPals.Level.LobbyBoard.Instance != null && !wasClient;
            if (!inOwnLobby && PushPals.Level.LevelLoader.Exists(PushPals.Level.LevelLoader.LobbyScene))
            {
                returnRequested = true;
                if (PushPals.Level.LevelLoader.Load(PushPals.Level.LevelLoader.LobbyScene)) return;
                returnRequested = false;
            }
            Show();
        }

        private UiBackground table;
        private readonly List<Button> buttons = new List<Button>();
        private readonly List<Image> glows = new List<Image>();
        private int selected = -1;
        private RectTransform caption, pointer;
        private TextMeshProUGUI captionText;
        private Image candleGlow;
        private readonly List<RectTransform> dust = new List<RectTransform>();
        private readonly List<Vector3> dustState = new List<Vector3>(); // фаза, скорость, размер
        private bool flying, gone;
        private static Sprite soft;

        /// <summary>Показать при запуске игры (автотест и пришедший по приглашению — сразу в коробок).</summary>
        public static void Show()
        {
            if (Online.IsActive || System.Array.IndexOf(System.Environment.GetCommandLineArgs(), "-pp-bot") >= 0)
            {
                MatchboxSleeve.Intro("");
                return;
            }
            Create<MainMenuScreen>("Main Menu", false);
        }

        protected override void Build()
        {
            Showing = true;
            Panel.Configure(UiPanel.Motion.Fade, UiPanel.Side.Bottom, false); // «назад» из главного меню некуда
            if (soft == null) soft = MakeSoftCircle();
            table = UiBackground.Show(Theme.menuBackground, Theme.menuBackgroundBlur);
            var picture = table.Picture;
            float aspect = table.PictureAspect;

            // Свеча: тёплое свечение у пламени, мерцает
            candleGlow = Glow(picture, Candle, 0.36f, new Color(1f, 0.72f, 0.35f, 0.35f));
            // Пылинки в свете свечи
            for (int i = 0; i < 28; i++)
            {
                var d = UiFactory.Rect(picture, "Dust").gameObject.AddComponent<Image>();
                d.sprite = soft;
                d.raycastTarget = false;
                d.color = new Color(1f, 0.9f, 0.7f, 0f);
                d.rectTransform.anchorMin = d.rectTransform.anchorMax = new Vector2(Random.Range(0.6f, 1f), Random.Range(0.35f, 0.95f));
                dust.Add(d.rectTransform);
                dustState.Add(new Vector3(Random.value * 10f, Random.Range(0.008f, 0.02f), Random.Range(3f, 8f)));
            }

            // Предметы на столе
            for (int i = 0; i < Props.Length; i++)
            {
                var p = Props[i];
                var sprite = UiSprites.Get(p.sprite);
                float spriteAspect = sprite != null ? sprite.rect.width / sprite.rect.height : 1f;
                float w = p.height * spriteAspect / aspect; // ширина в долях ширины картинки
                var glow = Glow(picture, new Vector2(p.at.x, p.at.y - p.height * 0.5f), p.height * 1.25f, new Color(1f, 0.85f, 0.55f, 0f));
                glows.Add(glow);
                var go = new GameObject(p.key, typeof(RectTransform));
                var rt = (RectTransform)go.transform;
                rt.SetParent(picture, false);
                rt.anchorMin = new Vector2(p.at.x - w * 0.5f, 1f - p.at.y);
                rt.anchorMax = new Vector2(p.at.x + w * 0.5f, 1f - p.at.y + p.height);
                rt.offsetMin = rt.offsetMax = Vector2.zero;
                var visual = UiFactory.Rect(rt, "Visual");
                UiRoot.Stretch(visual);
                var img = visual.gameObject.AddComponent<Image>();
                img.sprite = sprite;
                img.preserveAspect = true;
                var b = go.AddComponent<Button>();
                b.targetGraphic = img;
                b.transition = Selectable.Transition.None;
                go.AddComponent<UiButtonFx>();
                int n = i;
                b.onClick.AddListener(() => Activate(n));
                var trigger = go.AddComponent<EventTrigger>();
                var e = new EventTrigger.Entry { eventID = EventTriggerType.Select };
                e.callback.AddListener(_ => selected = n);
                trigger.triggers.Add(e);
                buttons.Add(b);
            }

            // Подпись и спичка-указатель над выбранным
            caption = UiFactory.Rect(picture, "Caption");
            caption.anchorMin = caption.anchorMax = new Vector2(0.5f, 0.5f);
            caption.sizeDelta = new Vector2(600f, 80f);
            var shadow = UiFactory.Text(caption, "", 58f, new Color(0.1f, 0.05f, 0.02f, 0.85f), true);
            UiRoot.Stretch(shadow.rectTransform);
            shadow.rectTransform.anchoredPosition = new Vector2(3f, -3f);
            captionText = UiFactory.Text(caption, "", 58f, Theme.inkLight, true);
            UiRoot.Stretch(captionText.rectTransform);
            captionText.gameObject.AddComponent<CaptionShadow>().shadow = shadow;
            var ptr = UiFactory.Image(picture, "menu_pointer", false, "Pointer");
            pointer = ptr.rectTransform;
            pointer.anchorMin = pointer.anchorMax = new Vector2(0.5f, 0.5f);
            pointer.sizeDelta = new Vector2(130f, 56f);
            pointer.localRotation = Quaternion.Euler(0f, 0f, -90f); // головкой вниз — на предмет

            // Логотип и подсказка
            var logo = UiFactory.Image(Rect, "logo_full", false, "Logo");
            UiFactory.Place(logo.rectTransform, new Vector2(0.5f, 1f), new Vector2(500f, 268f), new Vector2(-40f, -160f));
            var hint = UiFactory.Rect(Rect, "Hint");
            UiFactory.Place(hint, new Vector2(1f, 0f), new Vector2(260f, 56f), new Vector2(-170f, 50f));
            var glyph = UiFactory.Image(hint, "keyboard_enter", false, "Glyph");
            UiFactory.Place(glyph.rectTransform, new Vector2(0f, 0.5f), new Vector2(56f, 56f), new Vector2(28f, 0f));
            glyph.gameObject.AddComponent<InputGlyph>().SetPaths("<Keyboard>/enter", "<Gamepad>/buttonSouth");
            var label = UiFactory.LocText(hint, "menu.hint_select", 30f, Theme.inkLight, false);
            label.alignment = TextAlignmentOptions.MidlineLeft;
            UiFactory.Place(label.rectTransform, new Vector2(0f, 0.5f), new Vector2(190f, 50f), new Vector2(160f, 0f));

            Panel.FirstSelected = buttons[Play];
        }

        private static Image Glow(RectTransform parent, Vector2 at, float size, Color color)
        {
            var g = UiFactory.Rect(parent, "Glow").gameObject.AddComponent<Image>();
            g.sprite = soft;
            g.color = color;
            g.raycastTarget = false;
            var rt = g.rectTransform;
            rt.anchorMin = rt.anchorMax = new Vector2(at.x, 1f - at.y);
            rt.sizeDelta = Vector2.one * size * 1000f; // примерно, дальше — по высоте картинки
            rt.gameObject.AddComponent<SizeByParentHeight>().fraction = size;
            return g;
        }

        // Мягкий круг: белый в центре, прозрачный к краю
        private static Sprite MakeSoftCircle()
        {
            const int n = 64;
            var tex = new Texture2D(n, n, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp };
            for (int y = 0; y < n; y++)
                for (int x = 0; x < n; x++)
                {
                    float d = Vector2.Distance(new Vector2(x + 0.5f, y + 0.5f), new Vector2(n * 0.5f, n * 0.5f)) / (n * 0.5f);
                    float a = Mathf.Clamp01(1f - d);
                    tex.SetPixel(x, y, new Color(1f, 1f, 1f, a * a));
                }
            tex.Apply();
            return Sprite.Create(tex, new Rect(0, 0, n, n), new Vector2(0.5f, 0.5f));
        }

        private void Update()
        {
            if (gone) return;
            // Пригласили по сети, пока стоим в меню — сразу в коробок
            if (Online.IsActive && !flying) { Leave(); return; }
            float t = Time.unscaledTime, dt = Time.unscaledDeltaTime;

            // Свеча мерцает
            float flicker = 0.8f + 0.2f * Mathf.PerlinNoise(t * 3.2f, 0.3f) + 0.06f * Mathf.Sin(t * 17f);
            candleGlow.color = new Color(1f, 0.72f, 0.35f, 0.32f * flicker);
            candleGlow.rectTransform.localScale = Vector3.one * (0.96f + 0.08f * flicker);

            // Пылинки: поднимаются и покачиваются, ярче у свечи
            for (int i = 0; i < dust.Count; i++)
            {
                var s = dustState[i];
                var rt = dust[i];
                var a = rt.anchorMin;
                a.y += s.y * dt;
                a.x += Mathf.Sin(t * 0.7f + s.x) * 0.004f * dt * 10f;
                if (a.y > 0.97f) { a.y = 0.35f; a.x = Random.Range(0.6f, 1f); }
                rt.anchorMin = rt.anchorMax = a;
                rt.sizeDelta = Vector2.one * s.z;
                float near = 1f - Mathf.Clamp01(Vector2.Distance(a, new Vector2(Candle.x, 1f - Candle.y)) / 0.35f);
                var img = rt.GetComponent<Image>();
                img.color = new Color(1f, 0.9f, 0.7f, near * (0.35f + 0.3f * Mathf.Sin(t * 2f + s.x)));
            }

            // Выбранный предмет: свечение, подпись и указатель над ним
            var es = EventSystem.current;
            if (es != null && es.currentSelectedGameObject == null && !flying && buttons.Count > 0) es.SetSelectedGameObject(buttons[Play].gameObject);
            for (int i = 0; i < glows.Count; i++)
            {
                var c = glows[i].color;
                float want = i == selected && !flying ? 0.5f + 0.1f * Mathf.Sin(t * 3f) : 0f;
                c.a = Mathf.MoveTowards(c.a, want, dt * 2.5f);
                glows[i].color = c;
            }
            bool show = selected >= 0 && !flying;
            captionText.alpha = Mathf.MoveTowards(captionText.alpha, show ? 1f : 0f, dt * 6f);
            var pimg = pointer.GetComponent<Image>();
            pimg.color = new Color(1f, 1f, 1f, captionText.alpha);
            if (selected >= 0)
            {
                captionText.text = Loc.T(Props[selected].key);
                var target = (RectTransform)buttons[selected].transform;
                Vector3 top = target.TransformPoint(new Vector3(target.rect.center.x, target.rect.yMax, 0f));
                Vector2 local = caption.parent.InverseTransformPoint(top);
                float bob = Mathf.Sin(t * 4f) * 6f;
                pointer.anchoredPosition = Vector2.Lerp(pointer.anchoredPosition, local + new Vector2(0f, 50f + bob), 1f - Mathf.Exp(-14f * dt));
                caption.anchoredPosition = Vector2.Lerp(caption.anchoredPosition, local + new Vector2(0f, 140f), 1f - Mathf.Exp(-14f * dt));
                ClampCaption();
            }
        }

        // Подпись не уезжает за край экрана (предметы у краёв)
        private void ClampCaption()
        {
            var parent = (RectTransform)caption.parent;
            var r = parent.rect;
            var p = caption.anchoredPosition;
            p.x = Mathf.Clamp(p.x, r.xMin + 320f, r.xMax - 320f);
            p.y = Mathf.Min(p.y, r.yMax - 60f);
            caption.anchoredPosition = p;
        }

        private void Activate(int n)
        {
            if (flying) return;
            selected = n;
            switch (n)
            {
                case Exit: AskQuit(); return;
                case Play: StartCoroutine(Fly(n, 1.9f, () => Leave())); return;
            }
            StartCoroutine(Fly(n, 1.6f, () =>
            {
                UiScreen s;
                switch (n)
                {
                    case OnlineProp: s = OnlineScreen.Open(true); break;
                    case Wardrobe: s = WardrobeScreen.Open(); break;
                    case Collection: s = CollectionScreen.Open(); break;
                    default: s = SettingsScreen.Open(); break;
                }
                s.Closed += () =>
                {
                    if (this == null || gone) return;
                    // Из «Онлайн» с созданной игрой — сразу в коробок (там и ждём друзей), без возврата к столу
                    if (Online.IsActive) Leave();
                    else StartCoroutine(FlyBack(n));
                };
            }));
        }

        // «Камера» летит к предмету: картинка увеличивается вокруг него
        private IEnumerator Fly(int n, float zoom, System.Action then)
        {
            flying = true;
            var picture = table.Zoom;
            var target = (RectTransform)buttons[n].transform;
            Vector2 center = target.TransformPoint(target.rect.center);
            Vector2 local = picture.InverseTransformPoint(center); // точка в своих координатах (без масштаба)
            Vector2 from = picture.anchoredPosition;
            Vector2 to = -local * zoom;
            for (float k = 0f; k < 1f;)
            {
                k = Mathf.Min(1f, k + Time.unscaledDeltaTime / 0.45f);
                float e = k * k * (3f - 2f * k);
                picture.localScale = Vector3.one * Mathf.Lerp(1f, zoom, e);
                picture.anchoredPosition = Vector2.Lerp(from, to, e);
                yield return null;
            }
            if (then != null) then();
        }

        private IEnumerator FlyBack(int n)
        {
            var picture = table.Zoom;
            float zoom = picture.localScale.x;
            Vector2 from = picture.anchoredPosition;
            for (float k = 0f; k < 1f;)
            {
                k = Mathf.Min(1f, k + Time.unscaledDeltaTime / 0.4f);
                float e = k * k * (3f - 2f * k);
                picture.localScale = Vector3.one * Mathf.Lerp(zoom, 1f, e);
                picture.anchoredPosition = Vector2.Lerp(from, Vector2.zero, e);
                yield return null;
            }
            flying = false;
            var es = EventSystem.current;
            if (es != null) { UiButtonFx.QuietFrame = Time.frameCount; es.SetSelectedGameObject(buttons[n].gameObject); }
        }

        private void AskQuit() => UiDialog.Confirm("menu.quit_confirm", "settings.saved", "menu.exit", QuitGame);

        /// <summary>Выйти из игры (всё сохранено; в редакторе — остановить Play).</summary>
        public static void QuitGame()
        {
            PushPals.Save.SaveSystem.Save();
#if UNITY_EDITOR
            UnityEditor.EditorApplication.isPlaying = false;
#else
            Application.Quit();
#endif
        }

        // В коробок: обложка закрыта и сразу открывается — внутри лобби
        private void Leave()
        {
            if (gone) return;
            gone = true;
            MatchboxSleeve.Intro("");
            Destroy(table.gameObject);
            Destroy(gameObject);
        }

        protected override void OnDisable()
        {
            base.OnDisable();
            Showing = false;
        }

        private void OnDestroy()
        {
            Showing = false;
            if (table != null) Destroy(table.gameObject);
        }
    }
}
