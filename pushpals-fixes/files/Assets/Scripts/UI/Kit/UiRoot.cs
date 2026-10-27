using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem.UI;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Общий холст интерфейса (Этап 17.3), живёт между сценами, создаётся сам при первом обращении (UiRoot.Instance).
    /// Canvas Scaler: Scale With Screen Size 1920×1080, умноженный на «размер интерфейса» из настроек. Match 0,5 — только на 16:9;
    /// шире — по высоте, уже — по ширине: иначе на 21:9 холст по высоте меньше 1080 и вёрстка 16:9 не влезает (проверено).
    /// Слои: Background (во весь экран), Safe (16:9 по центру — на сверхшироких экранах интерфейс не расползается):
    /// Screens и Popups внутри, Overlay сверху (рамка фокуса, подсказка). Каждый кадр — ввод (UiInput), «назад»
    /// для верхней панели и курсор мыши (обычный / над кнопкой; с геймпадом курсор прячется).
    /// </summary>
    public class UiRoot : MonoBehaviour
    {
        private static UiRoot instance;

        public static UiRoot Instance
        {
            get
            {
                if (instance == null) Create();
                return instance;
            }
        }

        public static bool Exists => instance != null;

        public Canvas Canvas { get; private set; }
        public RectTransform Background { get; private set; }
        /// <summary>HUD игры (полоса горения, значки) — во весь экран, под экранами меню.</summary>
        public RectTransform Hud { get; private set; }
        public RectTransform Safe { get; private set; }
        public RectTransform Screens { get; private set; }
        public RectTransform Popups { get; private set; }
        public RectTransform Overlay { get; private set; }
        public UiTooltipView Tooltip { get; private set; }

        /// <summary>Курсор, когда мышь не над кнопкой (в игре — прицел, ставит HUD).</summary>
        public static string IdleCursor = "cur_default";
        /// <summary>Системный курсор спрятан (HUD рисует свой прицел).</summary>
        public static bool HideCursor;

        private CanvasScaler scaler;
        private string appliedCursor;
        private readonly List<RaycastResult> hits = new List<RaycastResult>();
        private PointerEventData pointer;
        private EventSystem pointerOwner;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStatics()
        {
            instance = null;
            IdleCursor = "cur_default";
            HideCursor = false;
        }

        private static void Create()
        {
            var go = new GameObject("UI Root");
            DontDestroyOnLoad(go);
            instance = go.AddComponent<UiRoot>();
            instance.Build();
        }

        private void Build()
        {
            var theme = UiTheme.Current;
            Canvas = gameObject.AddComponent<Canvas>();
            Canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            Canvas.sortingOrder = 50;
            scaler = gameObject.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.screenMatchMode = CanvasScaler.ScreenMatchMode.MatchWidthOrHeight;
            scaler.matchWidthOrHeight = theme.matchWidthOrHeight;
            gameObject.AddComponent<GraphicRaycaster>();
            ApplyScale();

            Background = Layer("Background", transform);
            Hud = Layer("Hud", transform);
            Safe = Layer("Safe", transform);
            Screens = Layer("Screens", Safe);
            Popups = Layer("Popups", Safe);
            Overlay = Layer("Overlay", transform);
            Tooltip = UiTooltipView.Create(Overlay);
            UiFocusFrame.Create(Overlay);
            EnsureEventSystem();
            UiSettings.Changed += ApplyScale;
        }

        private void OnDestroy()
        {
            UiSettings.Changed -= ApplyScale;
            if (instance == this) instance = null;
        }

        private static RectTransform Layer(string name, Transform parent)
        {
            var rt = new GameObject(name, typeof(RectTransform)).GetComponent<RectTransform>();
            rt.SetParent(parent, false);
            Stretch(rt);
            return rt;
        }

        /// <summary>Камера для перевода экранных точек в холст (null — холст поверх экрана).</summary>
        public static Camera EventCamera => instance != null && instance.Canvas.renderMode != RenderMode.ScreenSpaceOverlay ? instance.Canvas.worldCamera : null;

        /// <summary>Растянуть на всего родителя.</summary>
        public static void Stretch(RectTransform rt)
        {
            rt.anchorMin = Vector2.zero;
            rt.anchorMax = Vector2.one;
            rt.offsetMin = Vector2.zero;
            rt.offsetMax = Vector2.zero;
        }

        // Размер интерфейса 80–150 %: чем больше масштаб, тем меньше «опорное» разрешение
        private void ApplyScale()
        {
            if (scaler == null) return;
            scaler.referenceResolution = UiTheme.Current.referenceResolution / Mathf.Max(0.1f, UiSettings.Scale);
        }

        /// <summary>EventSystem с вводом Input System (если в сцене ещё нет).</summary>
        public static void EnsureEventSystem()
        {
            if (EventSystem.current != null || FindAnyObjectByType<EventSystem>() != null) return;
            var go = new GameObject("EventSystem", typeof(EventSystem), typeof(InputSystemUIInputModule));
            DontDestroyOnLoad(go);
        }

        private void Update()
        {
            UiInput.Tick();
            EnsureEventSystem();
            FitSafeArea();
            FitMatch();
            if (UiInput.BackPressed && !KeybindRow.SwallowsBack) UiPanel.BackOnTop(); // Esc/B во время переназначения — не «назад»
            UpdateCursor();
        }

        // Шире 16:9 — масштаб по высоте, уже — по ширине: в «безопасной» области всегда помещается 1920×1080
        private void FitMatch()
        {
            float aspect = Aspect;
            float want = Mathf.Abs(aspect - 16f / 9f) < 0.01f ? UiTheme.Current.matchWidthOrHeight : aspect > 16f / 9f ? 1f : 0f;
            if (!Mathf.Approximately(scaler.matchWidthOrHeight, want)) scaler.matchWidthOrHeight = want;
        }

        private float Aspect
        {
            get
            {
                var r = Canvas.pixelRect; // и для снимков в текстуру (там холст не во весь экран)
                return r.height > 0f ? r.width / r.height : 16f / 9f;
            }
        }

        // 16:9 по центру на сверхшироких; на 16:10 и 4:3 — весь экран
        private void FitSafeArea()
        {
            float aspect = Aspect;
            float f = aspect > 16f / 9f ? (16f / 9f) / aspect : 1f;
            Safe.anchorMin = new Vector2((1f - f) * 0.5f, 0f);
            Safe.anchorMax = new Vector2(1f - (1f - f) * 0.5f, 1f);
        }

        private void UpdateCursor()
        {
            bool mouse = UiInput.Current == UiInput.Device.KeyboardMouse && !HideCursor;
            if (Cursor.visible != mouse) Cursor.visible = mouse;
            if (!mouse) return;
            string want = PointerOverInteractable() ? "cur_hover" : IdleCursor;
            if (want == appliedCursor) return;
            var set = UiTheme.Current.cursors;
            if (set != null && set.Apply(want)) appliedCursor = want;
        }

        // Мышь над доступной кнопкой/ползунком интерфейса
        private bool PointerOverInteractable()
        {
            var es = EventSystem.current;
            var mouse = UnityEngine.InputSystem.Mouse.current;
            if (es == null || mouse == null) return false;
            if (pointer == null || pointerOwner != es) { pointer = new PointerEventData(es); pointerOwner = es; }
            pointer.position = mouse.position.ReadValue();
            hits.Clear();
            es.RaycastAll(pointer, hits);
            if (hits.Count == 0) return false;
            var s = hits[0].gameObject.GetComponentInParent<Selectable>();
            return s != null && s.IsInteractable();
        }
    }
}
