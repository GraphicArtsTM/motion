using System.Collections.Generic;
using PushPals.Audio;
using TMPro;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Отсчёт перед стартом (префаб Countdown — собирает UiKitBuilder). Сверху лента «Старт через» (по языку игры),
    /// под ней цифра: каждую секунду новая выпрыгивает (масштаб 1,4 → 1 с лёгким отскоком), старая быстро сжимается
    /// и гаснет, на каждой — тихий деревянный тик. Рядом горящая спичка-таймер: пламя за весь отсчёт прогорает вниз
    /// по палочке. «Поехали!» — табличка выскакивает крупно, лёгкая тряска камеры, искры от спички, чирк и «вжух»;
    /// через 0,8 с всё гаснет.
    /// Лобби (Follow): время ведёт доска (по сети — хост), отмена — B / Esc у хоста, отсчёт тут же исчезает;
    /// на нуле коробок закрывается, а «Поехали!» говорит уже открывшийся уровень (Go). Сам по себе (Play) — считает
    /// сам, B / Esc — отмена. Нет картинок слов или цифры на языке игры — тот же текст TextMeshPro, тем же цветом.
    /// Длительность — в инспекторе префаба (её же берёт доска в лобби).
    /// </summary>
    public class Countdown : MonoBehaviour
    {
        public const string PrefabName = "Countdown";

        [Header("Отсчёт")]
        [Tooltip("Длительность отсчёта, с: цифры от неё вниз до 1 (её же берёт доска в лобби)")]
        [SerializeField, Min(1f)] private float duration = 5f;
        [Tooltip("Сколько держится «Поехали!», прежде чем всё погаснет, с")]
        [SerializeField] private float goHold = 0.8f;
        [Tooltip("Тряска камеры на «Поехали!» (0–1; в настройках доступности — слабее или выключена)")]
        [SerializeField, Range(0f, 1f)] private float shake = 0.3f;
        [SerializeField, Range(0f, 1f)] private float tickVolume = 0.35f;
        [Header("Текст, если нет картинки (цвета — как у надписей на картинках)")]
        [SerializeField] private Color ink = new Color(0.98f, 0.93f, 0.82f);
        [SerializeField] private Color outline = new Color(0.32f, 0.13f, 0.08f);

        // Цифра: картинка cd_N или (нет её) текст
        [System.Serializable]
        private class Slot
        {
            public RectTransform root;
            public Image image;
            public TextMeshProUGUI text;
        }

        [Header("Части (собирает BuildView; в префабе их можно двигать)")]
        [SerializeField] private CanvasGroup group;
        [SerializeField] private RectTransform countRoot, matchRoot, goRoot, sparkRoot;
        [SerializeField] private Image shade, title, goPlate, wood, charred, flame, glow;
        [SerializeField] private TextMeshProUGUI titleText, goText, hint;
        [SerializeField] private Slot slotA, slotB;

        // Спичка-таймер — картинка menu_pointer, повёрнутая головкой вверх: видна доля ширины от StickStart до края,
        // край сползает от StickTop (головка уже сгорела — чёрный кончик) до огарка StickStub. Палочка на высоте StickLine
        private const float StickStart = 0.035f, StickTop = 0.716f, StickStub = 0.12f, CharLength = 0.035f, StickLine = 0.256f;
        private const float MatchLength = 240f; // видимая палочка целиком, единиц интерфейса

        private enum Mode { Count, WaitLevel, Go, Out }

        private struct Spark
        {
            public Image image;
            public Vector2 velocity;
            public float life, age;
        }

        public static Countdown Current { get; private set; }
        /// <summary>Отсчёт или «Поехали!» на экране (заставка уровня ждёт).</summary>
        public static bool Showing => Current != null;

        private static bool prefabLooked;
        private static Countdown prefab;
        private static Sprite soft;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStatics()
        {
            prefabLooked = false;
            prefab = null;
            Current = null;
        }

        private Mode mode = Mode.Out;
        private System.Func<float> source; // лобби: секунд до старта (меньше нуля — отменили)
        private System.Action onGo, onCancel;
        private bool selfTimed, cancellable;
        private float left, total, modeTime, digitTime;
        private int shownDigit = -1;
        private Slot current, previous;
        private bool previousShown; // у первой цифры прежней нет
        private float burnt;  // 0 — спичка целая, 1 — огарок
        private readonly List<Spark> sparks = new List<Spark>();

        /// <summary>Длительность из префаба (инспектор); 0 — префаба нет (UiKitBuilder ещё не запускали).</summary>
        public static float Duration
        {
            get
            {
                var p = Prefab();
                return p != null ? Mathf.Max(1f, p.duration) : 0f;
            }
        }

        private static Countdown Prefab()
        {
            if (!prefabLooked)
            {
                prefabLooked = true;
                var go = UiPrefabs.Get(PrefabName);
                prefab = go != null ? go.GetComponent<Countdown>() : null;
            }
            return prefab;
        }

        /// <summary>
        /// Лобби: показать и вести по внешнему времени (секунд до старта; меньше нуля — отменили: исчезает).
        /// subtitle — строка под цифрой (уровень), canCancel — подсказать «B / Esc — отменить».
        /// </summary>
        public static void Follow(System.Func<float> remaining, string subtitle, bool canCancel)
        {
            var c = Spawn();
            c.source = remaining;
            c.selfTimed = false;
            c.cancellable = false; // отменяет доска (кнопки хоста — PlayerIntentReader)
            c.onGo = c.onCancel = null;
            c.Begin(remaining(), subtitle, canCancel ? Loc.T("board.cancel_hint") : "");
        }

        /// <summary>Сам по себе: отсчёт на Duration, в конце — «Поехали!» и onGo; B / Esc — отмена (onCancel).</summary>
        public static Countdown Play(System.Action go, System.Action cancel = null)
        {
            var c = Spawn();
            c.source = null;
            c.selfTimed = true;
            c.cancellable = true;
            c.onGo = go;
            c.onCancel = cancel;
            c.Begin(c.duration, "", Loc.T("countdown.cancel"));
            return c;
        }

        /// <summary>Уровень открылся: «Поехали!» (спичка уже догорела) — как только уедет обложка коробка.</summary>
        public static void Go()
        {
            var c = Spawn();
            c.source = null;
            c.onGo = c.onCancel = null;
            c.burnt = 1f;
            c.SetMode(Mode.WaitLevel);
        }

        /// <summary>Убрать сразу (отменили).</summary>
        public static void Stop()
        {
            if (Current != null) Current.SetMode(Mode.Out);
        }

        // Свой холст поверх всего, даже обложки коробка (у неё 300): «1» видна, пока коробок закрывается.
        // В UiRoot — живёт между сценами: «Поехали!» показывает уже новый уровень
        private static Countdown Spawn()
        {
            if (Current != null) return Current;
            var host = new GameObject("Countdown Canvas", typeof(RectTransform), typeof(Canvas));
            host.transform.SetParent(UiRoot.Instance.Safe, false);
            UiRoot.Stretch((RectTransform)host.transform);
            var canvas = host.GetComponent<Canvas>();
            canvas.overrideSorting = true;
            canvas.sortingOrder = 310;
            var p = Prefab();
            Countdown c;
            if (p != null) c = Instantiate(p, host.transform, false);
            else
            {
                c = new GameObject(PrefabName, typeof(RectTransform)).AddComponent<Countdown>();
                c.transform.SetParent(host.transform, false);
            }
            UiRoot.Stretch((RectTransform)c.transform);
            Current = c;
            return c;
        }

        private void Awake()
        {
            if (group == null) BuildView();
            if (soft == null) soft = MakeSoftCircle();
            shade.sprite = glow.sprite = soft;
            foreach (var t in new[] { titleText, goText, hint, slotA.text, slotB.text })
            {
                t.color = ink;
                t.outlineColor = outline;
                t.outlineWidth = 0.22f;
            }
            group.alpha = 0f;
            current = slotA;
            previous = slotB;
        }

        private void OnDestroy()
        {
            if (Current == this) Current = null;
        }

        /// <summary>Собрать части (UiKitBuilder — в префаб; без префаба — в игре).</summary>
        public void BuildView()
        {
            var root = (RectTransform)transform;
            group = gameObject.GetComponent<CanvasGroup>();
            if (group == null) group = gameObject.AddComponent<CanvasGroup>();
            group.interactable = false;
            group.blocksRaycasts = false;

            // Полутень за отсчётом — читается на любом уровне
            shade = UiFactory.Rect(root, "Shade").gameObject.AddComponent<Image>();
            shade.raycastTarget = false;
            shade.color = new Color(0.04f, 0.02f, 0.01f, 0.4f);
            UiFactory.Place(shade.rectTransform, new Vector2(0.5f, 1f), new Vector2(1500f, 820f), new Vector2(0f, -320f));

            // Отсчёт: лента «Старт через», цифра, подпись
            countRoot = Top(root, "Count");
            title = UiFactory.Image(countRoot, "cd_title_ru", false, "Title");
            UiFactory.Place(title.rectTransform, new Vector2(0.5f, 1f), new Vector2(560f, 106f), new Vector2(0f, -120f));
            titleText = Word(title.rectTransform, 56f);
            slotA = Digit(countRoot, "Digit A");
            slotB = Digit(countRoot, "Digit B");
            hint = UiFactory.Text(countRoot, "", 24f, ink, false);
            hint.gameObject.name = "Hint";
            UiFactory.Place(hint.rectTransform, new Vector2(0.5f, 1f), new Vector2(1200f, 40f), new Vector2(0f, -505f));

            // Спичка-таймер справа от цифры: низ палочки — вровень с низом цифры
            matchRoot = UiFactory.Rect(root, "Match");
            matchRoot.anchorMin = matchRoot.anchorMax = new Vector2(0.5f, 1f);
            matchRoot.pivot = new Vector2(0.5f, 0f);
            matchRoot.sizeDelta = new Vector2(60f, MatchLength);
            matchRoot.anchoredPosition = new Vector2(195f, -465f);
            glow = UiFactory.Rect(matchRoot, "Glow").gameObject.AddComponent<Image>();
            glow.raycastTarget = false;
            glow.color = new Color(1f, 0.63f, 0.24f, 0.55f);
            glow.rectTransform.anchorMin = glow.rectTransform.anchorMax = new Vector2(0.5f, 0f);
            glow.rectTransform.sizeDelta = new Vector2(170f, 170f);
            charred = Stick(matchRoot, "Charred");
            charred.color = new Color(0.16f, 0.1f, 0.07f, 1f);
            wood = Stick(matchRoot, "Wood");
            flame = UiFactory.Image(matchRoot, "ic_fire", false, "Flame");
            flame.rectTransform.anchorMin = flame.rectTransform.anchorMax = new Vector2(0.5f, 0f);
            flame.rectTransform.pivot = new Vector2(0.5f, 0.12f);
            flame.rectTransform.sizeDelta = new Vector2(64f, 84f);

            // «Поехали!» — на месте цифры, крупно
            goRoot = Top(root, "Go");
            goPlate = UiFactory.Image(goRoot, "cd_go_ru", false, "Plate");
            UiFactory.Place(goPlate.rectTransform, new Vector2(0.5f, 1f), new Vector2(760f, 304f), new Vector2(0f, -335f));
            goText = Word(goPlate.rectTransform, 120f);

            sparkRoot = Top(root, "Sparks");
        }

        private static RectTransform Top(RectTransform parent, string name)
        {
            var rt = UiFactory.Rect(parent, name);
            UiRoot.Stretch(rt);
            return rt;
        }

        // Запасной текст поверх места картинки
        private static TextMeshProUGUI Word(RectTransform place, float size)
        {
            var t = UiFactory.Text(place, "", size, Color.white, true);
            UiRoot.Stretch(t.rectTransform);
            t.enableAutoSizing = true;
            t.fontSizeMin = size * 0.4f;
            t.fontSizeMax = size;
            return t;
        }

        private static Slot Digit(RectTransform parent, string name)
        {
            var s = new Slot { root = UiFactory.Rect(parent, name) };
            UiFactory.Place(s.root, new Vector2(0.5f, 1f), new Vector2(200f, 260f), new Vector2(0f, -335f));
            s.image = UiFactory.Image(s.root, "cd_5", false, "Image");
            UiRoot.Stretch(s.image.rectTransform);
            s.text = UiFactory.Text(s.root, "", 220f, Color.white, true);
            UiRoot.Stretch(s.text.rectTransform);
            return s;
        }

        // Палочка: menu_pointer, повёрнутая головкой вверх и заполняемая от низа (Filled) — край прогорает вниз
        private static Image Stick(RectTransform matchRoot, string name)
        {
            var img = UiFactory.Image(matchRoot, "menu_pointer", false, name);
            img.preserveAspect = false;
            img.type = Image.Type.Filled;
            img.fillMethod = Image.FillMethod.Horizontal;
            img.fillOrigin = (int)Image.OriginHorizontal.Left;
            var sprite = img.sprite;
            float aspect = sprite != null ? sprite.rect.height / sprite.rect.width : 164f / 342f;
            float w = MatchLength / (StickTop - StickStart), h = w * aspect;
            var rt = img.rectTransform;
            rt.anchorMin = rt.anchorMax = new Vector2(0.5f, 0f);
            rt.sizeDelta = new Vector2(w, h);
            rt.localEulerAngles = new Vector3(0f, 0f, 90f); // левый край картинки — внизу
            // Палочка (StickLine по высоте картинки) — по середине, её низ (StickStart) — в точке опоры
            rt.anchoredPosition = new Vector2(-(0.5f - StickLine) * h, (0.5f - StickStart) * w);
            return img;
        }

        // ---------- Ход отсчёта ----------

        private void Begin(float remaining, string subtitle, string cancelHint)
        {
            total = Mathf.Max(0.1f, Mathf.Max(remaining, duration));
            left = remaining;
            shownDigit = -1;
            burnt = 0f;
            string line = subtitle ?? "";
            if (!string.IsNullOrEmpty(cancelHint)) line += (line.Length > 0 ? "   ·   " : "") + cancelHint;
            hint.text = line;
            SetMode(Mode.Count);
        }

        private void SetMode(Mode m)
        {
            mode = m;
            modeTime = 0f;
            Words();
            countRoot.gameObject.SetActive(m == Mode.Count);
            goRoot.gameObject.SetActive(m == Mode.Go);
            matchRoot.gameObject.SetActive(m == Mode.Count || m == Mode.Go);
            if (m != Mode.Go) return;
            // «Поехали!»: табличка, искры, тряска, чирк и «вжух»
            Burst(26);
            CameraShake.Shake(shake);
            Sfx.Ui("strike", 0.7f);
            Sfx.Ui("whoosh", 0.55f);
        }

        private void Update()
        {
            float dt = Time.unscaledDeltaTime;
            modeTime += dt;
            switch (mode)
            {
                case Mode.Count:
                    if (!Counting(dt)) return;
                    break;
                case Mode.WaitLevel:
                    // Уровень виден, когда обложка коробка поехала (без обложки — сразу)
                    if (MatchboxSleeve.Cover < 0.6f || modeTime > 8f) SetMode(Mode.Go);
                    break;
                case Mode.Go:
                    if (modeTime > goHold) SetMode(Mode.Out);
                    break;
                case Mode.Out:
                    if (group.alpha <= 0.001f && sparks.Count == 0)
                    {
                        Destroy(transform.parent != null && transform.parent.GetComponent<Canvas>() != null ? transform.parent.gameObject : gameObject);
                        return;
                    }
                    break;
            }
            Animate(dt);
        }

        // false — отсчёт кончился или отменён (режим уже сменён)
        private bool Counting(float dt)
        {
            if (source != null)
            {
                float r = source();
                if (r < 0f) { SetMode(Mode.Out); return false; } // отменили (или доски уже нет)
                // По сети время приходит рывками — между снимками считаем сами
                left = Mathf.Abs(r - (left - dt)) > 0.25f ? r : Mathf.Max(0f, left - dt);
            }
            else left -= dt;
            if (cancellable && CancelPressed())
            {
                var cancel = onCancel;
                SetMode(Mode.Out);
                if (cancel != null) cancel();
                return false;
            }
            if (left <= 0f)
            {
                burnt = 1f;
                if (selfTimed)
                {
                    var go = onGo;
                    SetMode(Mode.Go);
                    if (go != null) go();
                }
                else SetMode(Mode.Out); // лобби: коробок закрывается, «Поехали!» скажет новый уровень
                return false;
            }
            int n = Mathf.CeilToInt(left);
            if (n != shownDigit) ShowDigit(n);
            burnt = 1f - Mathf.Clamp01(left / total);
            return true;
        }

        private static bool CancelPressed()
        {
            var k = Keyboard.current;
            if (k != null && k.escapeKey.wasPressedThisFrame) return true;
            foreach (var g in Gamepad.all) if (g.buttonEast.wasPressedThisFrame) return true;
            return false;
        }

        // Новая цифра выпрыгивает, прежняя — сжимается и гаснет
        private void ShowDigit(int n)
        {
            bool first = shownDigit < 0;
            shownDigit = n;
            var t = previous;
            previous = current;
            current = t;
            var sprite = n >= 1 && n <= 5 ? UiSprites.Get("cd_" + n) : null;
            current.image.sprite = sprite;
            current.image.enabled = sprite != null;
            current.text.gameObject.SetActive(sprite == null);
            current.text.text = n.ToString();
            current.root.SetAsLastSibling();
            previousShown = !first;
            digitTime = 0f;
            Sfx.Ui("wood_tick", tickVolume);
        }

        // Картинки слов на языке игры; нет — тот же текст
        private void Words()
        {
            string lang = Loc.Current == Loc.Language.En ? "en" : "ru";
            Pick(title, titleText, UiSprites.Get("cd_title_" + lang), Loc.T("countdown.title"));
            Pick(goPlate, goText, UiSprites.Get("cd_go_" + lang), Loc.T("countdown.go"));
        }

        private static void Pick(Image image, TextMeshProUGUI text, Sprite sprite, string fallback)
        {
            image.sprite = sprite;
            image.enabled = sprite != null;
            text.gameObject.SetActive(sprite == null);
            text.text = fallback;
        }

        // ---------- Анимация ----------

        private void Animate(float dt)
        {
            float t = Time.unscaledTime;
            bool visible = mode == Mode.Count || mode == Mode.Go;
            group.alpha = Mathf.MoveTowards(group.alpha, visible ? 1f : 0f, dt * (visible ? 7f : 4f));

            // Цифры: новая 1,4 → 1 с лёгким «проседанием», прежняя — быстро меньше и прозрачнее
            digitTime += dt;
            float u = Mathf.Clamp01(digitTime / 0.32f);
            float pop = 1f + 0.4f * (1f - u) * (1f - u) * (1f - u) - 0.08f * Mathf.Sin(Mathf.PI * u) * (1f - u * 0.3f) * (u < 1f ? 1f : 0f);
            current.root.localScale = Vector3.one * pop;
            Alpha(current, Mathf.Clamp01(digitTime / 0.08f));
            float v = Mathf.Clamp01(digitTime / 0.18f);
            previous.root.localScale = Vector3.one * (1f - 0.45f * v);
            Alpha(previous, previousShown ? 1f - v : 0f);

            // Спичка: край палочки сползает вниз, над ним пламя «дышит», у огарка — тлеет
            float edge = Mathf.Lerp(StickTop, StickStub, burnt);
            wood.fillAmount = edge;
            charred.fillAmount = Mathf.Min(1f, edge + CharLength);
            float w = MatchLength / (StickTop - StickStart);
            float y = (edge - StickStart) * w;
            float flicker = 0.9f + 0.1f * Mathf.PerlinNoise(t * 7f, 0.3f) + 0.05f * Mathf.Sin(t * 23f);
            float big = mode == Mode.Go ? 1f + 0.8f * Mathf.Exp(-modeTime * 6f) : 1f;
            flame.rectTransform.anchoredPosition = new Vector2(0f, y - 4f);
            flame.rectTransform.localScale = new Vector3(1f + 0.05f * Mathf.Sin(t * 17f), flicker, 1f) * big * (mode == Mode.Go ? Mathf.Clamp01(1.2f - modeTime * 1.2f) : 1f);
            glow.rectTransform.anchoredPosition = new Vector2(0f, y + 24f);
            glow.color = new Color(1f, 0.63f, 0.24f, 0.5f * flicker * big);

            // «Поехали!»: из маленькой — крупнее нужного — на место
            if (mode == Mode.Go)
            {
                float a = Mathf.Clamp01(modeTime / 0.12f), b = Mathf.Clamp01((modeTime - 0.12f) / 0.2f);
                float s = modeTime < 0.12f ? Mathf.Lerp(0.4f, 1.18f, 1f - (1f - a) * (1f - a)) : Mathf.Lerp(1.18f, 1f, 1f - (1f - b) * (1f - b));
                goPlate.rectTransform.localScale = Vector3.one * s; // вокруг середины таблички
            }

            // Искры: летят вверх и в стороны, падают, гаснут
            for (int i = sparks.Count - 1; i >= 0; i--)
            {
                var sp = sparks[i];
                sp.age += dt;
                if (sp.age >= sp.life || sp.image == null)
                {
                    if (sp.image != null) Destroy(sp.image.gameObject);
                    sparks.RemoveAt(i);
                    continue;
                }
                sp.velocity += Vector2.down * 900f * dt;
                var rt = sp.image.rectTransform;
                rt.anchoredPosition += sp.velocity * dt;
                float k = 1f - sp.age / sp.life;
                rt.localScale = Vector3.one * (0.4f + 0.6f * k);
                var c = sp.image.color;
                c.a = k;
                sp.image.color = c;
                sparks[i] = sp;
            }
        }

        private static void Alpha(Slot s, float a)
        {
            var c = s.image.color;
            c.a = a;
            s.image.color = c;
            s.text.alpha = a;
        }

        // Искры от огонька спички
        private void Burst(int count)
        {
            float w = MatchLength / (StickTop - StickStart);
            Vector2 from = matchRoot.anchoredPosition + new Vector2(0f, (Mathf.Lerp(StickTop, StickStub, burnt) - StickStart) * w + 10f);
            for (int i = 0; i < count; i++)
            {
                var img = UiFactory.Rect(sparkRoot, "Spark").gameObject.AddComponent<Image>();
                img.sprite = soft;
                img.raycastTarget = false;
                img.color = Color.Lerp(new Color(1f, 0.95f, 0.7f), new Color(1f, 0.6f, 0.2f), Random.value);
                var rt = img.rectTransform;
                rt.anchorMin = rt.anchorMax = new Vector2(0.5f, 1f);
                rt.sizeDelta = Vector2.one * Random.Range(8f, 16f);
                rt.anchoredPosition = from;
                float angle = Random.Range(15f, 165f) * Mathf.Deg2Rad;
                sparks.Add(new Spark
                {
                    image = img,
                    velocity = new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * Random.Range(250f, 680f),
                    life = Random.Range(0.45f, 0.9f),
                });
            }
        }

        // Мягкий круг: белый в центре, прозрачный к краю (полутень, отсвет, искры)
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
    }
}
