using System.Collections;
using System.Collections.Generic;
using TMPro;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Главное меню-стол (Этап 17.4): ночная кухня, «камера» близко к столу, над ним логотип, на столешнице крупные
    /// предметы — коробок «Играть», банки-телефон «Онлайн», линейка «Настройки», шкаф из напёрстков «Гардероб»,
    /// книга «Коллекция», дверь «Выход». Предметы стоят в два ряда, у каждого тень у основания и падающая от свечи
    /// (влево-вниз), перед каждым — бумажный ярлык с подписью; чем дальше от свечи, тем темнее.
    /// Выбранный светлеет и приподнимается (тень остаётся на столе), за ним тёплое свечение и пятно света на столе,
    /// его ярлык крупнее и красным, к ярлыку тянется горящая спичка; остальные уходят в полутень.
    /// Выбор — мышью (предмет или ярлык), стрелками, геймпадом (между рядами — вверх/вниз); нажатие — «камера»
    /// летит к предмету и открывается экран (закрыли — летит обратно). Свеча мерцает, в её свете кружатся пылинки.
    /// «Играть» — коробок открывается, внутри лобби. Заменяет титульный экран Этапа 17.
    /// </summary>
    public class MainMenuScreen : UiScreen
    {
        // Предмет на столе. Место — на сцене 1920×1080 (кадр 16:9), в долях: x — середина, y — низ (сверху вниз),
        // h — высота. light — сколько достаётся света свечи (дальше от неё — темнее). Тень у основания — мягкое пятно
        // по «следу» предмета: сдвиг от середины низа (доли ширины и высоты, вверх — «+»), размер (доли), наклон.
        // Ярлык — на сколько ниже низа предмета (доля кадра) и наклон; спичка у ярлыка — слева или справа (где свободно)
        private struct Prop
        {
            public string sprite, key;
            public float x, y, h, light;
            public Vector2 shadowShift, shadowSize;
            public float shadowAngle, labelY, labelAngle;
            public bool pointerRight;
        }

        private static Prop P(string sprite, string key, float x, float y, float h, float light, float sx, float sy, float sw, float sh,
                              float sa, float labelY, float labelAngle, bool pointerRight = false) =>
            new Prop { sprite = sprite, key = key, x = x, y = y, h = h, light = light, shadowShift = new Vector2(sx, sy),
                       shadowSize = new Vector2(sw, sh), shadowAngle = sa, labelY = labelY, labelAngle = labelAngle, pointerRight = pointerRight };

        // Дальний ряд — у заднего края столешницы, ближний — у переднего, между ложкой (слева спереди), спичками
        // (справа спереди) и свечой (справа сзади). Предметы не заслоняют ни ярлыки, ни логотип (проверено макетом
        // из этих же картинок)
        private static readonly Prop[] Props =
        {
            P("menu_obj_exit",       "menu.exit",       0.105f, 0.64f,  0.37f, 0.84f, 0.04f, 0.02f, 1.5f,  0.14f, 0f,   0.04f,   0f,   true),
            P("menu_obj_wardrobe",   "menu.wardrobe",   0.30f,  0.635f, 0.33f, 0.88f, 0f,    0.02f, 1.4f,  0.14f, 0f,   0.04f,  -1.2f),
            P("menu_obj_online",     "menu.online",     0.67f,  0.63f,  0.23f, 0.95f, 0f,    0.10f, 1.25f, 0.30f, 0f,   0.04f,   1.2f, true),
            P("menu_obj_settings",   "menu.settings",   0.215f, 0.925f, 0.21f, 0.86f, 0f,    0.45f, 1.35f, 0.30f, 40f,  0.035f, -4f),
            P("menu_obj_play",       "menu.play",       0.485f, 0.895f, 0.34f, 0.92f, 0f,    0.22f, 1.35f, 0.50f, -12f, 0.045f, -1f),
            P("menu_obj_collection", "menu.collection", 0.778f, 0.92f,  0.26f, 0.97f, 0f,    0.18f, 1.35f, 0.45f, -20f, 0.04f,   1.5f),
        };
        private const int Exit = 0, Wardrobe = 1, OnlineProp = 2, Settings = 3, Play = 4, Collection = 5;
        // Стрелки и геймпад: соседи слева, справа, сверху, снизу (−1 — нет); вверх-вниз — пары «дальний — ближний»
        private static readonly int[,] Neighbours =
        {
            { -1, Wardrobe, -1, Settings },          // Выход
            { Exit, OnlineProp, -1, Play },          // Гардероб
            { Wardrobe, -1, -1, Collection },        // Онлайн
            { -1, Play, Exit, -1 },                  // Настройки
            { Settings, Collection, Wardrobe, -1 },  // Играть
            { Play, -1, OnlineProp, -1 },            // Коллекция
        };

        // «Камера» ближе, чем вся картинка: столешница — на полкадра, свеча в кадре (середина вида — доли картинки, сверху вниз)
        private const float ViewZoom = 1.14f;
        private static readonly Vector2 ViewCenter = new Vector2(0.56f, 0.56f);
        private const float StageWidth = 1920f, StageHeight = 1080f;
        // Где пламя свечи: на картинке фона (доли, сверху вниз) и по ширине сцены
        private static readonly Vector2 Candle = new Vector2(0.855f, 0.27f);
        private const float CandleX = 0.87f;

        // Выбранный: подъём (доля высоты) и рост; падающая тень — сдвиг от свечи (доли высоты), размытие, плотность
        private const float Lift = 0.04f, Grow = 0.05f, CastShiftX = 0.05f, CastShiftY = 0.02f, CastBlur = 0.035f, CastAlpha = 0.5f;
        private const float RestLight = 0.9f; // невыбранные — в полутени
        // Ярлык: высота, поля, наименьшая ширина, рамка тоньше (карточка невысокая), рост выбранного; спичка-указатель
        private const float LabelHeight = 52f, LabelPad = 30f, LabelMinWidth = 170f, LabelBorder = 1.9f, LabelGrow = 0.1f;
        private const float PointerWidth = 140f, PointerHeight = 67f;
        private static readonly Vector2 LogoSize = new Vector2(500f, 266f), LogoAt = new Vector2(0f, -26f - 133f);
        private static readonly Color Lit = new Color(1f, 0.985f, 0.95f, 1f);
        private static readonly Color HotInk = new Color(0.59f, 0.15f, 0.09f, 1f);
        private static readonly Color LabelShade = new Color(0.86f, 0.86f, 0.86f, 1f);

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

        // Предмет на экране: кнопки (сам предмет и его ярлык), картинка (её приподнимаем и подсвечиваем), тень, свечения
        private class PropView
        {
            public Button button, labelButton;
            public RectTransform rt, visual, label;
            public Image image, cast, glow, glowCore, pool, card;
            public TextMeshProUGUI text;
            public string fitted;  // подпись, под которую подогнана ширина ярлыка
            public float height;
            public float k;        // 0 — в полутени, 1 — выбран
        }

        private UiBackground table;
        private RectTransform stage;
        private readonly List<PropView> views = new List<PropView>();
        private int selected = -1;
        private RectTransform pointer;
        private Image pointerImage, pointerGlow;
        private bool pointerRight;
        private CanvasGroup chrome;
        private Image candleGlow;
        private readonly List<RectTransform> dust = new List<RectTransform>();
        private readonly List<Image> dustImages = new List<Image>();
        private readonly List<Vector3> dustState = new List<Vector3>(); // фаза, скорость, размер
        private bool flying, gone;
        private float shownAt;
        private static Sprite soft, vignette;

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
            shownAt = Time.unscaledTime;
            Panel.Configure(UiPanel.Motion.Fade, UiPanel.Side.Bottom, false); // «назад» из главного меню некуда
            if (soft == null) soft = MakeSoftCircle();
            if (vignette == null) vignette = MakeVignette();
            table = UiBackground.Show(Theme.menuBackground, Theme.menuBackgroundBlur);
            var picture = table.Picture;

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

            // Сцена 1920×1080 над картинкой — ровно по кадру 16:9 (ApplyView), летит вместе с «камерой».
            // Слои: тени (лежат на столе), свечения, предметы (сначала дальний ряд), ярлыки и спичка — поверх всех
            stage = UiFactory.Rect(table.Zoom, "Stage");
            stage.anchorMin = stage.anchorMax = new Vector2(0.5f, 0.5f);
            stage.sizeDelta = new Vector2(StageWidth, StageHeight);
            var shadows = Layer("Shadows");
            var glows = Layer("Glows");
            var objects = Layer("Props");
            var labels = Layer("Labels");
            views.Clear();
            for (int i = 0; i < Props.Length; i++) views.Add(null);
            var order = new List<int>();
            for (int i = 0; i < Props.Length; i++) order.Add(i);
            order.Sort((a, b) => Props[a].y.CompareTo(Props[b].y));
            foreach (int i in order) views[i] = BuildProp(i, shadows, glows, objects, labels);
            Navigation();

            // Спичка-указатель у ярлыка выбранного, с отсветом пламени
            pointerGlow = Soft(labels, "Pointer Glow", Vector2.zero, new Vector2(110f, 100f), new Color(1f, 0.67f, 0.31f, 0f));
            pointerImage = UiFactory.Image(labels, "menu_pointer", false, "Pointer");
            pointer = pointerImage.rectTransform;
            pointer.anchorMin = pointer.anchorMax = new Vector2(0f, 1f);
            pointer.sizeDelta = new Vector2(PointerWidth, PointerHeight);
            pointerImage.color = new Color(1f, 1f, 1f, 0f);

            // Углы кадра в полутьме — взгляд на стол
            var vig = UiFactory.Rect(Rect, "Vignette").gameObject.AddComponent<Image>();
            vig.sprite = vignette;
            vig.raycastTarget = false;
            UiRoot.Stretch(vig.rectTransform);

            // Логотип над столом и подсказка; пока «камера» летит к предмету — гаснут
            var top = UiFactory.Rect(Rect, "Chrome");
            UiRoot.Stretch(top);
            chrome = top.gameObject.AddComponent<CanvasGroup>();
            chrome.interactable = false;
            chrome.blocksRaycasts = false;
            var logoShadow = UiFactory.Image(top, "logo_full", false, "Logo Shadow");
            UiFactory.Place(logoShadow.rectTransform, new Vector2(0.5f, 1f), LogoSize, LogoAt + new Vector2(6f, -12f));
            logoShadow.color = new Color(0f, 0f, 0f, 0.55f);
            logoShadow.gameObject.AddComponent<UiSoftSilhouette>().Radius = 12f;
            var logo = UiFactory.Image(top, "logo_full", false, "Logo");
            UiFactory.Place(logo.rectTransform, new Vector2(0.5f, 1f), LogoSize, LogoAt);
            var hint = UiFactory.Rect(top, "Hint");
            UiFactory.Place(hint, new Vector2(1f, 0f), new Vector2(260f, 56f), new Vector2(-170f, 50f));
            var glyph = UiFactory.Image(hint, "keyboard_enter", false, "Glyph");
            UiFactory.Place(glyph.rectTransform, new Vector2(0f, 0.5f), new Vector2(56f, 56f), new Vector2(28f, 0f));
            glyph.gameObject.AddComponent<InputGlyph>().SetPaths("<Keyboard>/enter", "<Gamepad>/buttonSouth");
            var label = UiFactory.LocText(hint, "menu.hint_select", 30f, Theme.inkLight, false);
            label.alignment = TextAlignmentOptions.MidlineLeft;
            UiFactory.Place(label.rectTransform, new Vector2(0f, 0.5f), new Vector2(190f, 50f), new Vector2(160f, 0f));

            Panel.FirstSelected = views[Play].button;
            ApplyView();
        }

        private RectTransform Layer(string name)
        {
            var rt = UiFactory.Rect(stage, name);
            UiRoot.Stretch(rt);
            return rt;
        }

        private PropView BuildProp(int i, RectTransform shadows, RectTransform glows, RectTransform objects, RectTransform labels)
        {
            var p = Props[i];
            var v = new PropView();
            var sprite = UiSprites.Get(p.sprite);
            float aspect = sprite != null ? sprite.rect.width / sprite.rect.height : 1f;
            float h = p.h * StageHeight, w = h * aspect;
            v.height = h;
            var foot = new Vector2(p.x * StageWidth, -p.y * StageHeight); // середина низа, от левого верхнего угла сцены

            // Тень у основания — пятно по «следу» предмета
            var contact = Soft(shadows, "Shadow", foot + Vector2.Scale(p.shadowShift, new Vector2(w, h)),
                               Vector2.Scale(p.shadowSize, new Vector2(w, h)), new Color(0f, 0f, 0f, 0.75f));
            contact.rectTransform.localEulerAngles = new Vector3(0f, 0f, p.shadowAngle);
            // Падающая тень: свеча справа сзади — размытый силуэт уходит влево-вниз
            v.cast = UiFactory.Rect(shadows, "Cast").gameObject.AddComponent<Image>();
            v.cast.sprite = sprite;
            v.cast.raycastTarget = false;
            v.cast.color = new Color(0.055f, 0.027f, 0.012f, CastAlpha);
            float away = p.x < CandleX ? -1f : 1f;
            Stand(v.cast.rectTransform, foot + new Vector2(away * CastShiftX * h, -CastShiftY * h), w, h);
            v.cast.gameObject.AddComponent<UiSoftSilhouette>().Radius = CastBlur * h;

            // Свечение за выбранным (широкое и плотнее у самого предмета) и пятно света на столе
            var middle = foot + new Vector2(0f, h * 0.5f);
            v.glow = Soft(glows, "Glow", middle, new Vector2(w * 2.3f, h * 2f), new Color(1f, 0.745f, 0.39f, 0f));
            v.glowCore = Soft(glows, "Glow Core", middle, new Vector2(w * 1.35f, h * 1.25f), new Color(1f, 0.84f, 0.59f, 0f));
            v.pool = Soft(glows, "Light Pool", foot + new Vector2(0f, h * 0.06f), new Vector2(w * 1.7f, h * 0.55f), new Color(1f, 0.8f, 0.51f, 0f));

            // Сам предмет — кнопка; картинка растёт и поднимается от низа (стоит на столе)
            var go = new GameObject(p.key, typeof(RectTransform));
            v.rt = (RectTransform)go.transform;
            v.rt.SetParent(objects, false);
            Stand(v.rt, foot, w, h);
            v.visual = UiFactory.Rect(v.rt, "Visual");
            v.visual.anchorMin = Vector2.zero;
            v.visual.anchorMax = Vector2.one;
            v.visual.pivot = new Vector2(0.5f, 0f);
            v.visual.offsetMin = v.visual.offsetMax = Vector2.zero;
            v.image = v.visual.gameObject.AddComponent<Image>();
            v.image.sprite = sprite;
            v.image.preserveAspect = true;
            v.image.color = Rest(p.light);
            v.button = go.AddComponent<Button>();
            v.button.targetGraphic = v.image;
            v.button.transition = Selectable.Transition.None;
            // Без UiButtonFx: он сам двигает и осветляет картинку и спорил бы с подсветкой предмета (Update)
            Hook(v.button, i);

            // Ярлык: бумажная карточка перед предметом, поверх всех предметов (не заслоняется); нажимается, как сам предмет
            v.label = UiFactory.Rect(labels, "Label " + p.key);
            v.label.anchorMin = v.label.anchorMax = new Vector2(0f, 1f);
            v.label.anchoredPosition = foot + new Vector2(0f, -p.labelY * StageHeight);
            v.label.sizeDelta = new Vector2(LabelMinWidth, LabelHeight);
            v.label.localEulerAngles = new Vector3(0f, 0f, p.labelAngle);
            var cardShadow = UiFactory.Image(v.label, "input_field", true, "Shadow");
            cardShadow.pixelsPerUnitMultiplier = LabelBorder;
            UiRoot.Stretch(cardShadow.rectTransform);
            cardShadow.rectTransform.anchoredPosition = new Vector2(-4f, -5f);
            cardShadow.color = new Color(0f, 0f, 0f, 0.45f);
            cardShadow.gameObject.AddComponent<UiSoftSilhouette>().Radius = 4f;
            v.card = UiFactory.Image(v.label, "input_field", true, "Card");
            v.card.pixelsPerUnitMultiplier = LabelBorder;
            UiRoot.Stretch(v.card.rectTransform);
            v.card.color = LabelShade;
            v.card.raycastTarget = true;
            v.text = UiFactory.LocText(v.label, p.key, 21f, Theme.ink, true);
            UiRoot.Stretch(v.text.rectTransform);
            v.text.fontStyle = FontStyles.UpperCase;
            v.text.characterSpacing = 9f;
            v.text.alignment = TextAlignmentOptions.Midline;
            v.labelButton = v.card.gameObject.AddComponent<Button>();
            v.labelButton.targetGraphic = v.card;
            v.labelButton.transition = Selectable.Transition.None;
            Hook(v.labelButton, i);
            FitLabel(v);
            return v;
        }

        // Выбор и нажатие: предмет и его ярлык ведут себя одинаково
        private void Hook(Button b, int n)
        {
            b.onClick.AddListener(() => { UiTheme.Play(Theme.clickSound, Theme.clickVolume); Activate(n); });
            var trigger = b.gameObject.AddComponent<EventTrigger>();
            var select = new EventTrigger.Entry { eventID = EventTriggerType.Select };
            select.callback.AddListener(_ =>
            {
                if (selected != n && Time.frameCount != UiButtonFx.QuietFrame) UiTheme.Play(Theme.hoverSound, Theme.hoverVolume);
                selected = n;
            });
            trigger.triggers.Add(select);
            // Наведение мышью = выбор предмета (стрелки и геймпад продолжают от него)
            var enter = new EventTrigger.Entry { eventID = EventTriggerType.PointerEnter };
            enter.callback.AddListener(_ =>
            {
                var es = EventSystem.current;
                if (es == null || flying || (selected == n && es.currentSelectedGameObject != null)) return;
                es.SetSelectedGameObject(views[n].button.gameObject);
            });
            trigger.triggers.Add(enter);
        }

        // Ширина ярлыка — по подписи (и после смены языка)
        private static void FitLabel(PropView v)
        {
            if (v.text.text == v.fitted) return;
            v.fitted = v.text.text;
            float width = v.text.GetPreferredValues(v.text.text).x;
            v.label.sizeDelta = new Vector2(Mathf.Max(LabelMinWidth, width + LabelPad * 2f), LabelHeight);
        }

        // Предмет в полутени свечи: темнее и теплее
        private static Color Rest(float light)
        {
            float k = light * RestLight;
            return new Color(Mathf.Min(1f, k * 1.02f), k, k * 0.93f, 1f);
        }

        // Стоит на столе: середина низа — в точке foot (от левого верхнего угла сцены)
        private static void Stand(RectTransform rt, Vector2 foot, float width, float height)
        {
            rt.anchorMin = rt.anchorMax = new Vector2(0f, 1f);
            rt.pivot = new Vector2(0.5f, 0f);
            rt.sizeDelta = new Vector2(width, height);
            rt.anchoredPosition = foot;
        }

        // Мягкое пятно (тень, свечение) на сцене: середина — в точке at
        private static Image Soft(RectTransform parent, string name, Vector2 at, Vector2 size, Color color)
        {
            var img = UiFactory.Rect(parent, name).gameObject.AddComponent<Image>();
            img.sprite = soft;
            img.color = color;
            img.raycastTarget = false;
            var rt = img.rectTransform;
            rt.anchorMin = rt.anchorMax = new Vector2(0f, 1f);
            rt.sizeDelta = size;
            rt.anchoredPosition = at;
            return img;
        }

        private static void SetAlpha(Graphic g, float a)
        {
            var c = g.color;
            c.a = a;
            g.color = c;
        }

        // Стрелки и геймпад ходят по рядам, а не «куда ближе по прямой»; с ярлыка (нажали мышью) — туда же
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
                views[i].labelButton.navigation = nav;
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

        // Виньетка кадра: середина прозрачная, к углам — полутьма (эллипс чуть выше середины)
        private static Sprite MakeVignette()
        {
            const int w = 128, h = 72;
            var tex = new Texture2D(w, h, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp };
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    float dx = ((x + 0.5f) / w - 0.5f) * StageWidth / 1250f;
                    float dy = ((y + 0.5f) / h - 0.525f) * StageHeight / 780f;
                    float t = Mathf.InverseLerp(0.55f, 1.15f, Mathf.Sqrt(dx * dx + dy * dy));
                    tex.SetPixel(x, y, new Color(0.03f, 0.015f, 0.008f, 0.6f * t * t * (3f - 2f * t)));
                }
            tex.Apply();
            return Sprite.Create(tex, new Rect(0, 0, w, h), new Vector2(0.5f, 0.5f));
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

            // Выбранный: светлеет, приподнимается (тень остаётся на столе), светится; ярлык крупнее и красным
            var es = EventSystem.current;
            if (es != null && es.currentSelectedGameObject == null && !flying && views.Count > 0) es.SetSelectedGameObject(views[Play].button.gameObject);
            float pulse = 0.93f + 0.07f * Mathf.Sin(t * 3f);
            for (int i = 0; i < views.Count; i++)
            {
                var v = views[i];
                bool on = i == selected && !flying;
                v.k = Mathf.MoveTowards(v.k, on ? 1f : 0f, dt * 5f);
                float e = v.k * v.k * (3f - 2f * v.k);
                v.image.color = Color.Lerp(Rest(Props[i].light), Lit, e);
                v.visual.anchoredPosition = new Vector2(0f, e * (Lift * v.height + Mathf.Sin(t * 2.6f) * 2f));
                v.visual.localScale = Vector3.one * (1f + Grow * e);
                SetAlpha(v.cast, CastAlpha * (1f - 0.2f * e));
                SetAlpha(v.glow, 0.745f * e * pulse);
                SetAlpha(v.glowCore, 0.43f * e * pulse);
                SetAlpha(v.pool, 0.47f * e);
                v.label.localScale = Vector3.one * (1f + LabelGrow * e);
                v.card.color = Color.Lerp(LabelShade, Color.white, e);
                v.text.color = Color.Lerp(Theme.ink, HotInk, e);
                FitLabel(v);
            }

            // Спичка у ярлыка выбранного, головкой к нему; чуть «подпрыгивает»
            bool show = selected >= 0 && !flying;
            float alpha = Mathf.MoveTowards(pointerImage.color.a, show ? 1f : 0f, dt * 6f);
            if (selected >= 0)
            {
                var v = views[selected];
                bool right = Props[selected].pointerRight;
                float side = right ? 1f : -1f;
                float half = v.label.sizeDelta.x * v.label.localScale.x * 0.5f;
                float bob = Mathf.Sin(t * 4f) * 3f;
                Vector2 want = v.label.anchoredPosition + new Vector2(side * (half + PointerWidth * 0.5f - 8f + bob), 0f);
                bool snap = alpha < 0.05f || right != pointerRight;
                pointerRight = right;
                pointer.localScale = new Vector3(right ? -1f : 1f, 1f, 1f);
                pointer.anchoredPosition = snap ? want : Vector2.Lerp(pointer.anchoredPosition, want, 1f - Mathf.Exp(-16f * dt));
                // Пламя — на конце у ярлыка
                pointerGlow.rectTransform.anchoredPosition = pointer.anchoredPosition - new Vector2(side * PointerWidth * 0.36f, 0f);
            }
            pointerImage.color = new Color(1f, 1f, 1f, alpha);
            SetAlpha(pointerGlow, alpha * 0.6f * (0.85f + 0.15f * Mathf.PerlinNoise(t * 6f, 1.7f)));
            chrome.alpha = Mathf.MoveTowards(chrome.alpha, flying ? 0f : 1f, dt * 4f);
        }

        private void LateUpdate()
        {
            if (!gone && !flying) ApplyView();
        }

        // Вид «камеры» без полёта (каждый кадр — окно могли растянуть); при появлении она чуть «отъезжает» к столу
        private void ApplyView()
        {
            if (table == null || stage == null) return;
            var view = BaseView();
            float settle = 1f - Mathf.Clamp01((Time.unscaledTime - shownAt) / 1.4f);
            float s = view.scale * (1f + 0.05f * settle * settle * settle);
            var cam = table.Zoom;
            cam.localScale = new Vector3(s, s, 1f);
            cam.anchoredPosition = view.center - view.focus * s;
            stage.localScale = new Vector3(view.stageScale, view.stageScale, 1f);
            stage.anchoredPosition = view.focus;
        }

        // scale — масштаб «камеры» (Zoom); center — середина сцены 16:9 в кадре; focus — точка картинки в середине вида
        // (в координатах Zoom); stageScale — масштаб сцены 1920×1080 внутри Zoom, чтобы она легла ровно на кадр 16:9
        private struct CameraView
        {
            public float scale, stageScale;
            public Vector2 center, focus;
            public Vector2 Offset => center - focus * scale;
        }

        private CameraView BaseView()
        {
            var frame = UiRoot.Instance.Safe.rect;
            float width = Mathf.Max(1f, frame.width), height = Mathf.Max(1f, frame.height);
            // Сцена 16:9 — по низу кадра: на узких экранах (4:3) сверху остаётся стена, по бокам ничего не режется
            float vw = Mathf.Min(width, height * 16f / 9f), vh = vw * 9f / 16f;
            // Картинка «с обрезкой» на весь кадр — как её растягивает AspectRatioFitter
            float aspect = table.PictureAspect;
            float ph = Mathf.Max(height, width / aspect), pw = ph * aspect;
            var v = new CameraView();
            v.scale = vh * ViewZoom / ph;
            v.center = new Vector2(0f, (vh - height) * 0.5f);
            v.focus = new Vector2((ViewCenter.x - 0.5f) * pw, (0.5f - ViewCenter.y) * ph);
            v.stageScale = vh / StageHeight / v.scale;
            return v;
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

        // «Камера» летит к предмету: картинка со сценой увеличивается вокруг него
        private IEnumerator Fly(int n, float zoom, System.Action then)
        {
            flying = true;
            shownAt = -100f; // «отъезд» при появлении больше не нужен
            var cam = table.Zoom;
            var target = views[n].rt;
            Vector2 focus = cam.InverseTransformPoint(target.TransformPoint(target.rect.center)); // точка в своих координатах (без масштаба)
            float from = cam.localScale.x, to = from * zoom;
            Vector2 fromPos = cam.anchoredPosition, toPos = BaseView().center - focus * to;
            for (float k = 0f; k < 1f;)
            {
                k = Mathf.Min(1f, k + Time.unscaledDeltaTime / 0.45f);
                float e = k * k * (3f - 2f * k);
                float s = Mathf.Lerp(from, to, e);
                cam.localScale = new Vector3(s, s, 1f);
                cam.anchoredPosition = Vector2.Lerp(fromPos, toPos, e);
                yield return null;
            }
            if (then != null) then();
        }

        private IEnumerator FlyBack(int n)
        {
            var cam = table.Zoom;
            var view = BaseView();
            float from = cam.localScale.x;
            Vector2 fromPos = cam.anchoredPosition;
            for (float k = 0f; k < 1f;)
            {
                k = Mathf.Min(1f, k + Time.unscaledDeltaTime / 0.4f);
                float e = k * k * (3f - 2f * k);
                float s = Mathf.Lerp(from, view.scale, e);
                cam.localScale = new Vector3(s, s, 1f);
                cam.anchoredPosition = Vector2.Lerp(fromPos, view.Offset, e);
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
