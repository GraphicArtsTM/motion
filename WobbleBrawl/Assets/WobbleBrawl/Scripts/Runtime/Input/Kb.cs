using UnityEngine;
#if WB_INPUT_SYSTEM && ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

namespace WobbleBrawl
{
    public enum KeyId
    {
        W, A, S, D, E, F, Q, R, K, L, P,
        Up, Down, Left, Right,
        Space, Enter, Escape, Backspace, Delete, Tab,
        LeftShift, RightShift, LeftCtrl, RightCtrl,
        Comma, Period, Slash, Semicolon, Quote,
        Num0, Num1, Num2, Num3, Num4, Num5, Num6, Num7, Num8, Num9, NumEnter, NumPeriod,
        F1,
    }

    /// <summary>
    /// Thin keyboard/mouse abstraction so the game runs with either the Input System package
    /// (preferred) or the legacy Input Manager.
    /// </summary>
    public static class Kb
    {
#if WB_INPUT_SYSTEM && ENABLE_INPUT_SYSTEM
        static Key Map(KeyId k)
        {
            switch (k)
            {
                case KeyId.W: return Key.W;
                case KeyId.A: return Key.A;
                case KeyId.S: return Key.S;
                case KeyId.D: return Key.D;
                case KeyId.E: return Key.E;
                case KeyId.F: return Key.F;
                case KeyId.Q: return Key.Q;
                case KeyId.R: return Key.R;
                case KeyId.K: return Key.K;
                case KeyId.L: return Key.L;
                case KeyId.P: return Key.P;
                case KeyId.Up: return Key.UpArrow;
                case KeyId.Down: return Key.DownArrow;
                case KeyId.Left: return Key.LeftArrow;
                case KeyId.Right: return Key.RightArrow;
                case KeyId.Space: return Key.Space;
                case KeyId.Enter: return Key.Enter;
                case KeyId.Escape: return Key.Escape;
                case KeyId.Backspace: return Key.Backspace;
                case KeyId.Delete: return Key.Delete;
                case KeyId.Tab: return Key.Tab;
                case KeyId.LeftShift: return Key.LeftShift;
                case KeyId.RightShift: return Key.RightShift;
                case KeyId.LeftCtrl: return Key.LeftCtrl;
                case KeyId.RightCtrl: return Key.RightCtrl;
                case KeyId.Comma: return Key.Comma;
                case KeyId.Period: return Key.Period;
                case KeyId.Slash: return Key.Slash;
                case KeyId.Semicolon: return Key.Semicolon;
                case KeyId.Quote: return Key.Quote;
                case KeyId.Num0: return Key.Numpad0;
                case KeyId.Num1: return Key.Numpad1;
                case KeyId.Num2: return Key.Numpad2;
                case KeyId.Num3: return Key.Numpad3;
                case KeyId.Num4: return Key.Numpad4;
                case KeyId.Num5: return Key.Numpad5;
                case KeyId.Num6: return Key.Numpad6;
                case KeyId.Num7: return Key.Numpad7;
                case KeyId.Num8: return Key.Numpad8;
                case KeyId.Num9: return Key.Numpad9;
                case KeyId.NumEnter: return Key.NumpadEnter;
                case KeyId.NumPeriod: return Key.NumpadPeriod;
                case KeyId.F1: return Key.F1;
            }
            return Key.None;
        }

        public static bool Held(KeyId k)
        {
            var kb = Keyboard.current;
            return kb != null && kb[Map(k)].isPressed;
        }

        public static bool Down(KeyId k)
        {
            var kb = Keyboard.current;
            return kb != null && kb[Map(k)].wasPressedThisFrame;
        }

        public static bool HasMouse => Mouse.current != null;

        public static bool MouseHeld(int button)
        {
            var m = Mouse.current;
            if (m == null) return false;
            return button == 0 ? m.leftButton.isPressed : button == 1 ? m.rightButton.isPressed : m.middleButton.isPressed;
        }

        public static bool MouseDown(int button)
        {
            var m = Mouse.current;
            if (m == null) return false;
            return button == 0 ? m.leftButton.wasPressedThisFrame : button == 1 ? m.rightButton.wasPressedThisFrame : m.middleButton.wasPressedThisFrame;
        }

        /// <summary>Mouse movement this frame in pixels.</summary>
        public static Vector2 MouseDelta => Mouse.current != null ? Mouse.current.delta.ReadValue() : Vector2.zero;
        public static Vector2 MousePosition => Mouse.current != null ? Mouse.current.position.ReadValue() : Vector2.zero;
        /// <summary>Scroll in notches.</summary>
        public static float Scroll => Mouse.current != null ? Mouse.current.scroll.ReadValue().y / 120f : 0f;
#else
        static KeyCode Map(KeyId k)
        {
            switch (k)
            {
                case KeyId.W: return KeyCode.W;
                case KeyId.A: return KeyCode.A;
                case KeyId.S: return KeyCode.S;
                case KeyId.D: return KeyCode.D;
                case KeyId.E: return KeyCode.E;
                case KeyId.F: return KeyCode.F;
                case KeyId.Q: return KeyCode.Q;
                case KeyId.R: return KeyCode.R;
                case KeyId.K: return KeyCode.K;
                case KeyId.L: return KeyCode.L;
                case KeyId.P: return KeyCode.P;
                case KeyId.Up: return KeyCode.UpArrow;
                case KeyId.Down: return KeyCode.DownArrow;
                case KeyId.Left: return KeyCode.LeftArrow;
                case KeyId.Right: return KeyCode.RightArrow;
                case KeyId.Space: return KeyCode.Space;
                case KeyId.Enter: return KeyCode.Return;
                case KeyId.Escape: return KeyCode.Escape;
                case KeyId.Backspace: return KeyCode.Backspace;
                case KeyId.Delete: return KeyCode.Delete;
                case KeyId.Tab: return KeyCode.Tab;
                case KeyId.LeftShift: return KeyCode.LeftShift;
                case KeyId.RightShift: return KeyCode.RightShift;
                case KeyId.LeftCtrl: return KeyCode.LeftControl;
                case KeyId.RightCtrl: return KeyCode.RightControl;
                case KeyId.Comma: return KeyCode.Comma;
                case KeyId.Period: return KeyCode.Period;
                case KeyId.Slash: return KeyCode.Slash;
                case KeyId.Semicolon: return KeyCode.Semicolon;
                case KeyId.Quote: return KeyCode.Quote;
                case KeyId.Num0: return KeyCode.Keypad0;
                case KeyId.Num1: return KeyCode.Keypad1;
                case KeyId.Num2: return KeyCode.Keypad2;
                case KeyId.Num3: return KeyCode.Keypad3;
                case KeyId.Num4: return KeyCode.Keypad4;
                case KeyId.Num5: return KeyCode.Keypad5;
                case KeyId.Num6: return KeyCode.Keypad6;
                case KeyId.Num7: return KeyCode.Keypad7;
                case KeyId.Num8: return KeyCode.Keypad8;
                case KeyId.Num9: return KeyCode.Keypad9;
                case KeyId.NumEnter: return KeyCode.KeypadEnter;
                case KeyId.NumPeriod: return KeyCode.KeypadPeriod;
                case KeyId.F1: return KeyCode.F1;
            }
            return KeyCode.None;
        }

        public static bool Held(KeyId k) => Input.GetKey(Map(k));
        public static bool Down(KeyId k) => Input.GetKeyDown(Map(k));
        public static bool HasMouse => Input.mousePresent;
        public static bool MouseHeld(int button) => Input.GetMouseButton(button);
        public static bool MouseDown(int button) => Input.GetMouseButtonDown(button);
        public static Vector2 MouseDelta => new Vector2(Input.GetAxisRaw("Mouse X"), Input.GetAxisRaw("Mouse Y")) * 10f;
        public static Vector2 MousePosition => Input.mousePosition;
        public static float Scroll => Input.mouseScrollDelta.y;
#endif

        public static bool AnyHeld(KeyId a, KeyId b) => Held(a) || Held(b);
        public static bool AnyDown(KeyId a, KeyId b) => Down(a) || Down(b);
    }
}
