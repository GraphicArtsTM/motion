using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Строка переназначения (Этап 17.3): название действия и две кнопки — клавиатура/мышь и геймпад, на каждой
    /// значок текущей кнопки. Нажали — «нажмите клавишу…» (клавиатура: Esc — отмена, геймпад: Start — отмена),
    /// новая кнопка записывается поверх (переопределение привязки). Кнопка уже занята другим действием —
    /// они меняются местами (иначе одна кнопка делала бы два дела). Хранение и сброс — экран настроек (17.4).
    /// </summary>
    public class KeybindRow : MonoBehaviour
    {
        private static int busy;
        private static int endedFrame = -10;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStatics() { busy = 0; endedFrame = -10; }

        /// <summary>
        /// Идёт переназначение (или только что кончилось): Esc, B, Start и правый клик — для него, а не «назад»
        /// для экрана. Раньше Esc-отмена и новая кнопка B закрывали весь экран настроек.
        /// </summary>
        public static bool SwallowsBack => busy > 0 || Time.frameCount - endedFrame <= 1;

        private bool rebindingPad;
        private string previousPath;
        private int rebindIndex = -1;
        [SerializeField] private InputActionAsset actions;
        [SerializeField] private string actionName;
        [SerializeField] private LocText label;
        [SerializeField] private Button keyboardButton, gamepadButton;
        [SerializeField] private InputGlyph keyboardGlyph, gamepadGlyph;

        private InputActionRebindingExtensions.RebindingOperation operation;

        /// <summary>Переназначили (сохранить привязки).</summary>
        public event System.Action Rebound;

        public void Setup(LocText labelText, Button keyboard, InputGlyph keyboardIcon, Button gamepad, InputGlyph gamepadIcon)
        {
            label = labelText;
            keyboardButton = keyboard;
            keyboardGlyph = keyboardIcon;
            gamepadButton = gamepad;
            gamepadGlyph = gamepadIcon;
        }

        public void Bind(InputActionAsset asset, string action)
        {
            actions = asset;
            actionName = action;
            Refresh();
        }

        private void Awake()
        {
            if (keyboardButton != null) keyboardButton.onClick.AddListener(() => StartRebind(false));
            if (gamepadButton != null) gamepadButton.onClick.AddListener(() => StartRebind(true));
        }

        private void OnEnable() => Refresh();
        private void OnDisable() => Cancel();

        // Геймпад: Start — отмена (WithCancelingThrough — только одна кнопка, она уже Esc)
        private void Update()
        {
            if (operation == null || !rebindingPad) return;
            foreach (var pad in Gamepad.all)
                if (pad.startButton.wasPressedThisFrame) { Cancel(); return; }
        }

        private void Refresh()
        {
            if (label != null && !string.IsNullOrEmpty(actionName)) label.Key = "action." + actionName;
            // Значки всегда показывают «свои» устройства: слева клавиатура, справа геймпад
            if (keyboardGlyph != null) { keyboardGlyph.Mode = InputGlyph.Show.Keyboard; keyboardGlyph.SetAction(actions, actionName); }
            if (gamepadGlyph != null) { gamepadGlyph.Mode = InputGlyph.Show.Gamepad; gamepadGlyph.SetAction(actions, actionName); }
        }

        // Первая привязка нужного устройства (не часть составной)
        private int BindingIndex(InputAction action, bool gamepad)
        {
            for (int i = 0; i < action.bindings.Count; i++)
            {
                var b = action.bindings[i];
                if (b.isComposite || b.isPartOfComposite || string.IsNullOrEmpty(b.effectivePath)) continue;
                bool pad = b.effectivePath.StartsWith("<Gamepad>");
                if (pad == gamepad) return i;
            }
            return -1;
        }

        public void StartRebind(bool gamepad)
        {
            var action = actions != null ? actions.FindAction(actionName) : null;
            if (action == null || operation != null) return;
            int index = BindingIndex(action, gamepad);
            if (index < 0) return;
            bool wasEnabled = action.enabled;
            action.Disable();
            rebindingPad = gamepad;
            rebindIndex = index;
            previousPath = action.bindings[index].effectivePath;
            busy++;
            if (label != null) label.Key = gamepad ? "settings.rebind_wait_pad" : "settings.rebind_wait";
            operation = action.PerformInteractiveRebinding(index)
                .WithControlsHavingToMatchPath(gamepad ? "<Gamepad>" : "<Keyboard>")
                .WithControlsHavingToMatchPath(gamepad ? "<Gamepad>" : "<Mouse>")
                .WithControlsExcluding("<Gamepad>/start") // Start — отмена на геймпаде (Update)
                .WithCancelingThrough("<Keyboard>/escape")
                .OnMatchWaitForAnother(0.1f)
                .OnComplete(op => Finish(action, wasEnabled, true))
                .OnCancel(op => Finish(action, wasEnabled, false))
                .Start();
        }

        private void Finish(InputAction action, bool enable, bool done)
        {
            if (operation != null) { operation.Dispose(); operation = null; }
            busy = Mathf.Max(0, busy - 1);
            endedFrame = Time.frameCount;
            if (done) SwapConflicts(action, rebindIndex, previousPath);
            if (enable) action.Enable();
            UiTheme.Play(done ? UiTheme.Current.clickSound : UiTheme.Current.backSound, done ? UiTheme.Current.clickVolume : UiTheme.Current.backVolume);
            // Обмен мог поменять и чужие строки — значки обновить у всех
            foreach (var row in FindObjectsByType<KeybindRow>(FindObjectsSortMode.None)) row.Refresh();
            if (done && Rebound != null) Rebound();
        }

        // Новая кнопка уже у другого действия этой же схемы — тому достаётся прежняя кнопка этого (обмен)
        private static void SwapConflicts(InputAction action, int index, string previous)
        {
            if (index < 0 || index >= action.bindings.Count) return;
            string now = action.bindings[index].effectivePath;
            var map = action.actionMap;
            if (map == null || string.IsNullOrEmpty(now) || string.IsNullOrEmpty(previous) || now == previous) return;
            foreach (var other in map.actions)
                for (int i = 0; i < other.bindings.Count; i++)
                {
                    if (other == action && i == index) continue;
                    var b = other.bindings[i];
                    if (b.isComposite || b.effectivePath != now) continue;
                    other.ApplyBindingOverride(i, previous);
                }
        }

        private void Cancel()
        {
            if (operation == null) return;
            operation.Cancel();
        }
    }
}
