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
    /// линейка «Настройки», шкаф из напёрстков «Гардероб», книга «Коллекция», дверь «Выход».
    /// Предметы стоят на столешнице в два ряда с перспективой (дальний ряд меньше), у каждого тень от свечи
    /// и бумажный ярлык с подписью, прислонённый спереди. В тени предметы притушены, выбранный — светлеет,
    /// чуть приподнимается, за ним тёплое свечение, к его ярлыку тянется горящая спичка-указатель.
    /// Выбор — мышью, стрелками, геймпадом (между рядами — вверх/вниз); нажатие — «камера» летит к предмету
    /// и открывается экран (закрыли — летит обратно). Свеча мерцает, в её свете кружатся пылинки.
    /// «Играть» — коробок открывается, внутри лобби. Заменяет титульный экран Этапа 17.
    /// </summary>
    public class MainMenuScreen : UiScreen
    {
        // Предмет на столе. Всё — в долях картинки фона: x — середина, y — низ (сверху вниз), h — высота.
        // Тень: сдвиг по x (доля ширины предмета, «−» — влево, от свечи), ширина и высота (доли предмета), где «ступня» (доля высоты от низа).
        // Ярлык: насколько выше низа предмета его середина (доля высоты картинки) и ширина
        private struct Prop
        {
            public string sprite, key;
            public float x, y, h, tint;
            public float shadowX, shadowW, shadowH, foot;
            public float labelY, labelWidth;
        }

        private static Prop P(string sprite, string key, float x, float y, float h, float tint,
                              float shadowX, float shadowW, float shadowH, float foot, float labelY, float labelWidth) =>
            new Prop { sprite = sprite, key = key, x = x, y = y, h = h, tint = tint, shadowX = shadowX, shadowW = shadowW,
                       shadowH = shadowH, foot = foot, labelY = labelY, labelWidth = labelWidth };

        // Дальний ряд — у заднего края столешницы (он на 0,58), ближний — у переднего; слева спереди ложка,
        // справа спереди спички, справа сзади свеча — предметы между ними (проверено макетом из этих же картинок)
        private static readonly Prop[] Props =
        {
            P("menu_obj_wardrobe",   "menu.wardrobe",   0.19f,  0.685f, 0.23f,  0.66f, -0.12f, 1.0f,  0.10f, 0.05f, 0.006f, 210f),
            P("menu_obj_online",     "menu.online",     0.40f,  0.685f, 0.165f, 0.70f, -0.08f, 0.9f,  0.16f, 0.12f, 0.006f, 210f),
            P("menu_obj_exit",       "menu.exit",       0.655f, 0.685f, 0.22f,  0.82f, -0.10f, 1.1f,  0.09f, 0.05f, 0.006f, 210f),
            P("menu_obj_settings",   "menu.settings",   0.335f, 0.925f, 0.16f,  0.72f, -0.05f, 0.95f, 0.30f, 0.25f, 0.011f, 230f),
            P("menu_obj_play",       "menu.play",       0.53f,  0.925f, 0.23f,  0.85f, -0.06f, 1.0f,  0.22f, 0.12f, 0.011f, 210f),
            P("menu_obj_collection", "menu.collection", 0.705f, 0.925f, 0.17f,  0.86f, -0.06f, 1.0f,  0.20f, 0.10f, 0.011f, 230f),
        };
        private const int Wardrobe = 0, OnlineProp = 1, Exit = 2, Settings = 3, Play = 4, Collection = 5;
        // Стрелки и геймпад: соседи слева, справа, сверху, снизу (−1 — нет)
        private static readonly int[,] Neighbours =
        {
            { -1, OnlineProp, -1, Settings },        // Гардероб
            { Wardrobe, Exit, -1, Play },            // Онлайн
            { OnlineProp, -1, -1, Collection },      // Выход
            { -1, Play, Wardrobe, -1 },              // Настройки
            { Settings, Collection, OnlineProp, -1 },// Играть
            { Play, -1, Exit, -1 },                  // Коллекция
        };

        // Где пламя свечи на картинке фона (доли, сверху вниз)
        private static readonly Vector2 Candle = new Vector2(0.855f, 0.27f);
        private const float LabelHeight = 54f;

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

        // Предмет на экране: кнопка, картинка (её приподнимаем и подсвечиваем), ярлык, свечение
        private class PropView
        {
            public Button button;
            public RectTransform visual, label;
            public Image image, tag, glow;
            public TextMeshProUGUI text;
            public float k; // 0 — в тени, 1 — выбран
        }

        private UiBackground table;
        private readonly List<PropView> views = new List<PropView>();
        private int selected = -1;
        private RectTransform pointer;
        private Image pointerImage;
        private Image candleGlow;
        private readonly List<RectTransform> dust = new List<RectTransform>();
        private readonly List<Image> dustImages = new List<Image>();
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
                dustImages.Add(d);
                dustState.Add(new Vector3(Random.value * 10f, Random.Range(0.008f, 0.02f), Random.Range(3f, 8f)));
            }

            // Предметы: сначала дальний ряд (ближние рисуются поверх), у каждого — тень, свечение, картинка, ярлык
            views.Clear();
            for (int i = 0; i < Props.Length; i++) views.Add(null);
            var order = new List<int>();
            for (int i = 0; i < Props.Length; i++) order.Add(i);
            order.Sort((a, b) => Props[a].y.CompareTo(Props[b].y));
            // Ярлык дальнего ряда не заслонён ближним предметом: верх ближних — ниже ярлыков дальних (макет)
            foreach (int i in order) views[i] = BuildProp(picture, aspect, i);
            Navigation();

            // Спичка-указатель: горит у ярлыка выбранного предмета
            pointerImage = UiFactory.Image(picture, "menu_pointer", false, "Pointer");
            pointerImage.raycastTarget = false;
            pointer = pointerImage.rectTransform;
            pointer.anchorMin = pointer.anchorMax = new Vector2(0.5f, 0.5f);
            pointer.sizeDelta = new Vector2(118f, 56f);
            pointerImage.color = new Color(1f, 1f, 1f, 0f);

            // Логотип — табличкой в углу, как на эскизе (стол и предметы — главное)
            var logo = UiFactory.Image(Rect, "logo_full", false, "Logo");
            UiFactory.Place(logo.rectTransform, new Vector2(0f, 1f), new Vector2(380f, 202f), new Vector2(60f + 190f, -36f - 101f));
            logo.raycastTarget = false;
            // Подсказка
            var hint = UiFactory.Rect(Rect, "Hint");
            UiFactory.Place(hint, new Vector2(1f, 0f), new Vector2(260f, 56f), new Vector2(-170f, 50f));
            var glyph = UiFactory.Image(hint, "keyboard_enter", false, "Glyph");
            UiFactory.Place(glyph.rectTransform, new Vector2(0f, 0.5f), new Vector2(56f, 56f), new Vector2(28f, 0f));
            glyph.gameObject.AddComponent<InputGlyph>().SetPaths("<Keyboard>/enter", "<Gamepad>/buttonSouth");
            var label = UiFactory.LocText(hint, "menu.hint_select", 30f, Theme.inkLight, false);
            label.alignment = TextAlignmentOptions.MidlineLeft;
            UiFactory.Place(label.rectTransform, new Vector2(0f, 0.5f), new Vector2(190f, 50f), new Vector2(160f, 0f));

            Panel.FirstSelected = views[Play].button;
        }

        private PropView BuildProp(RectTransform picture, float aspect, int i)
        {
            var p = Props[i];
            var v = new PropView();
            var sprite = UiSprites.Get(p.sprite);
            float spriteAspect = sprite != null ? sprite.rect.width / sprite.rect.height : 1f;
            float w = p.h * spriteAspect / aspect; // ширина в долях ширины картинки
            float bottom = 1f - p.y;               // низ в долях снизу

            // Тень на столешнице — от свечи справа уходит влево
            var shadow = UiFactory.Rect(picture, "Shadow").gameObject.AddComponent<Image>();
            shadow.sprite = soft;
            shadow.color = new Color(0f, 0f, 0f, 0.72f);
            shadow.raycastTarget = false;
            float sx = p.x + p.shadowX * w, sy = bottom + p.foot * p.h;
            float sw = w * p.shadowW * 0.5f, shh = p.h * p.shadowH * 0.5f;
            shadow.rectTransform.anchorMin = new Vector2(sx - sw, sy - shh);
            shadow.rectTransform.anchorMax = new Vector2(sx + sw, sy + shh);
            shadow.rectTransform.offsetMin = shadow.rectTransform.offsetMax = Vector2.zero;

            // Тёплое свечение за выбранным
            v.glow = Glow(picture, new Vector2(p.x, p.y - p.h * 0.5f), p.h * 1.35f, new Color(1f, 0.82f, 0.48f, 0f));

            // Кнопка — по месту картинки предмета
            var go = new GameObject(p.key, typeof(RectTransform));
            var rt = (RectTransform)go.transform;
            rt.SetParent(picture, false);
            rt.anchorMin = new Vector2(p.x - w * 0.5f, bottom);
            rt.anchorMax = new Vector2(p.x + w * 0.5f, bottom + p.h);
            rt.offsetMin = rt.offsetMax = Vector2.zero;
            v.visual = UiFactory.Rect(rt, "Visual");
            UiRoot.Stretch(v.visual);
            v.image = v.visual.gameObject.AddComponent<Image>();
            v.image.sprite = sprite;
            v.image.preserveAspect = true;
            v.image.color = Shade(p.tint);
            v.button = go.AddComponent<Button>();
            v.button.targetGraphic = v.image;
            v.button.transition = Selectable.Transition.None;
            // Без UiButtonFx: он сам двигает и осветляет картинку и спорил бы с подсветкой предмета (Update)
            int n = i;
            v.button.onClick.AddListener(() => { UiTheme.Play(Theme.clickSound, Theme.clickVolume); Activate(n); });
            var trigger = go.AddComponent<EventTrigger>();
            var select = new EventTrigger.Entry { eventID = EventTriggerType.Select };
            select.callback.AddListener(_ =>
            {
                if (selected != n && Time.frameCount != UiButtonFx.QuietFrame) UiTheme.Play(Theme.hoverSound, Theme.hoverVolume);
                selected = n;
            });
            trigger.triggers.Add(select);
            // Наведение мышью = выбор (геймпад и стрелки продолжают отсюда)
            var enter = new EventTrigger.Entry { eventID = EventTriggerType.PointerEnter };
            enter.callback.AddListener(_ =>
            {
                var es = EventSystem.current;
                if (es != null && !flying && es.currentSelectedGameObject != go) es.SetSelectedGameObject(go);
            });
            trigger.triggers.Add(enter);

            // Ярлык: бумажная табличка, прислонённая спереди (часть кнопки — нажимается и она)
            var tag = UiFactory.Image(rt, "hud_team_plate", true, "Label");
            tag.pixelsPerUnitMultiplier = 2f; // рамка тоньше — табличка невысокая
            v.tag = tag;
            tag.raycastTarget = true; // ярлык нажимается и выбирается, как сам предмет
            v.label = tag.rectTransform;
            v.label.anchorMin = v.label.anchorMax = new Vector2(0.5f, p.labelY / p.h);
            v.label.pivot = new Vector2(0.5f, 0.5f);
            v.label.sizeDelta = new Vector2(p.labelWidth, LabelHeight);
            v.label.anchoredPosition = Vector2.zero;
            v.text = UiFactory.LocText(v.label, p.key, 26f, Theme.ink, true);
            UiRoot.Stretch(v.text.rectTransform);
            v.text.rectTransform.offsetMin = new Vector2(18f, 4f);
            v.text.rectTransform.offsetMax = new Vector2(-18f, -4f);
            v.text.enableAutoSizing = true;
            v.text.fontSizeMin = 16f;
            v.text.fontSizeMax = 26f;
            v.text.alignment = TextAlignmentOptions.Center;
            return v;
        }

        // Предмет в тени свечи: темнее и теплее; выбранный — как есть
        private static Color Shade(float k) => new Color(Mathf.Min(1f, k * 1.04f), k, k * 0.9f, 1f);

        // Стрелки и геймпад ходят по рядам, а не «куда ближе по прямой»
        private void Navigation()
        {
            for (int i = 0; i < views.Count; i++)
            {
                var nav = new UnityEngine.UI.Navigation { mode = UnityEngine.UI.Navigation.Mode.Explicit };
                nav.selectOnLeft = Neighbour(i, 0);
                nav.selectOnRight = Neighbour(i, 1);
                nav.selectOnUp = Neighbour(i, 2);
                nav.selectOnDown = Neighbour(i, 3);
                views[i].button.navigation = nav;
            }
        }

        private Selectable Neighbour(int i, int side)
        {
            int n = Neighbours[i, side];
            return n >= 0 ? views[n].button : null;
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
                dustImages[i].color = new Color(1f, 0.9f, 0.7f, near * (0.35f + 0.3f * Mathf.Sin(t * 2f + s.x)));
            }

            // Выбранный предмет: светлеет, приподнимается, светится; ярлык ярче; спичка-указатель у ярлыка
            var es = EventSystem.current;
            if (es != null && es.currentSelectedGameObject == null && !flying && views.Count > 0) es.SetSelectedGameObject(views[Play].button.gameObject);
            for (int i = 0; i < views.Count; i++)
            {
                var v = views[i];
                bool on = i == selected && !flying;
                v.k = Mathf.MoveTowards(v.k, on ? 1f : 0f, dt * 5f);
                float e = v.k * v.k * (3f - 2f * v.k);
                v.image.color = Color.Lerp(Shade(Props[i].tint), Color.white, e);
                float lift = e * 10f + (on ? Mathf.Sin(t * 3f) * 1.5f * e : 0f);
                v.visual.offsetMin = new Vector2(0f, lift);
                v.visual.offsetMax = new Vector2(0f, lift);
                v.label.localScale = Vector3.one * (1f + 0.06f * e);
                v.tag.color = Color.Lerp(new Color(0.86f, 0.8f, 0.72f), Color.white, e);
                var c = v.glow.color;
                c.a = e * (0.42f + 0.08f * Mathf.Sin(t * 3f));
                v.glow.color = c;
            }
            bool show = selected >= 0 && !flying;
            float alpha = Mathf.MoveTowards(pointerImage.color.a, show ? 1f : 0f, dt * 6f);
            pointerImage.color = new Color(1f, 1f, 1f, alpha);
            if (selected >= 0)
            {
                // Слева от ярлыка, головкой к нему; чуть «подпрыгивает»
                var label = views[selected].label;
                Vector3 left = label.TransformPoint(new Vector3(label.rect.xMin, label.rect.center.y, 0f));
                Vector2 local = (Vector2)pointer.parent.InverseTransformPoint(left);
                float bob = Mathf.Sin(t * 4f) * 4f;
                Vector2 want = local + new Vector2(-pointer.sizeDelta.x * 0.5f + 6f + bob, 0f);
                pointer.anchoredPosition = alpha < 0.05f ? want : Vector2.Lerp(pointer.anchoredPosition, want, 1f - Mathf.Exp(-16f * dt));
            }
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
            var target = (RectTransform)views[n].button.transform;
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
            if (es != null) { UiButtonFx.QuietFrame = Time.frameCount; es.SetSelectedGameObject(views[n].button.gameObject); }
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
