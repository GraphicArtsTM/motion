using UnityEngine;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

// Жест пальцем (или мышью в редакторе): свайп в одну из сторон.
public enum SwipeDir { None, Left, Right, Up, Down }

// Клавиши, которые нужны игре.
public enum GKey
{
    Up, Down, Left, Right, W, A, S, D, Enter, Space, Escape, F1, Tab, K, L,
    RightShift, RightCtrl, Numpad8, Numpad4, Numpad5, Numpad6, Numpad0, M
}

// Ввод с клавиатуры и мыши, который работает при любой настройке проекта
// (Project Settings -> Player -> Active Input Handling):
//   "Input System Package (New)" или "Both" - читаем через новый Input System (Keyboard.current / Mouse.current);
//   "Input Manager (Old)"                  - читаем через старый UnityEngine.Input.
//
// Раскладки клавиатуры (несколько игроков за одной клавиатурой):
//   -1  один игрок:  WASD или стрелки, прыжок - Пробел
//    0  игрок 1:     WASD, прыжок - Пробел
//    1  игрок 2:     стрелки, прыжок - правый Shift (или правый Ctrl)
//    2  игрок 3:     NumPad 8/4/5/6, прыжок - NumPad 0
public static class GameInput
{
    public const int SchemeSolo = -1;
    public const int SchemeCount = 3;

    static int cachedFrame = -1;
    static Vector2 lastMouse;
    static bool mouseMoved;

    // Клавиша нажата прямо сейчас (удерживается).
    public static bool Held(GKey k)
    {
#if ENABLE_INPUT_SYSTEM
        Keyboard kb = Keyboard.current;
        if (kb == null) return false;
        if (k == GKey.Enter) return kb.enterKey.isPressed || kb.numpadEnterKey.isPressed;
        return kb[ToKey(k)].isPressed;
#elif ENABLE_LEGACY_INPUT_MANAGER
        if (k == GKey.Enter) return Input.GetKey(KeyCode.Return) || Input.GetKey(KeyCode.KeypadEnter);
        return Input.GetKey(ToKeyCode(k));
#else
        return false;
#endif
    }

    // Клавиша была нажата в этом кадре.
    public static bool Down(GKey k)
    {
#if ENABLE_INPUT_SYSTEM
        Keyboard kb = Keyboard.current;
        if (kb == null) return false;
        if (k == GKey.Enter) return kb.enterKey.wasPressedThisFrame || kb.numpadEnterKey.wasPressedThisFrame;
        return kb[ToKey(k)].wasPressedThisFrame;
#elif ENABLE_LEGACY_INPUT_MANAGER
        if (k == GKey.Enter) return Input.GetKeyDown(KeyCode.Return) || Input.GetKeyDown(KeyCode.KeypadEnter);
        return Input.GetKeyDown(ToKeyCode(k));
#else
        return false;
#endif
    }

    // Направление для раскладки, длина не больше 1.
    public static Vector2 MoveVector(int scheme = SchemeSolo)
    {
        float x = 0f, y = 0f;
        bool wasd = scheme == SchemeSolo || scheme == 0;
        bool arrows = scheme == SchemeSolo || scheme == 1;
        bool numpad = scheme == 2;

        if ((wasd && Held(GKey.A)) || (arrows && Held(GKey.Left)) || (numpad && Held(GKey.Numpad4))) x -= 1f;
        if ((wasd && Held(GKey.D)) || (arrows && Held(GKey.Right)) || (numpad && Held(GKey.Numpad6))) x += 1f;
        if ((wasd && Held(GKey.W)) || (arrows && Held(GKey.Up)) || (numpad && Held(GKey.Numpad8))) y += 1f;
        if ((wasd && Held(GKey.S)) || (arrows && Held(GKey.Down)) || (numpad && Held(GKey.Numpad5))) y -= 1f;
        return Vector2.ClampMagnitude(new Vector2(x, y), 1f);
    }

    public static bool JumpPressed(int scheme = SchemeSolo)
    {
        switch (scheme)
        {
            case 0: return Down(GKey.Space);
            case 1: return Down(GKey.RightShift) || Down(GKey.RightCtrl);
            case 2: return Down(GKey.Numpad0);
            default: return Down(GKey.Space);
        }
    }

    // "Влево/вправо" один раз (листать героев в лобби).
    public static int StepPressed(int scheme = SchemeSolo)
    {
        bool wasd = scheme == SchemeSolo || scheme == 0;
        bool arrows = scheme == SchemeSolo || scheme == 1;
        bool numpad = scheme == 2;
        if ((wasd && Down(GKey.A)) || (arrows && Down(GKey.Left)) || (numpad && Down(GKey.Numpad4))) return -1;
        if ((wasd && Down(GKey.D)) || (arrows && Down(GKey.Right)) || (numpad && Down(GKey.Numpad6))) return 1;
        return 0;
    }

    // ------------------------------------------------------------------
    //  Touch / pointer (finger on Android, mouse on a computer)
    // ------------------------------------------------------------------

    static int pointerFrame = -1;
    static bool pointerHeld, pointerPressedThisFrame;
    static Vector2 pointerPos, pressPos;
    static float pressTime;
    static bool swipeUsed;
    static SwipeDir swipe;

    // Is the pointer (a finger or the left mouse button) pressed right now?
    static void ReadPointer(out bool held, out Vector2 pos)
    {
        held = false;
        pos = Vector2.zero;
#if ENABLE_INPUT_SYSTEM
        Touchscreen ts = Touchscreen.current;
        if (ts != null && ts.primaryTouch.press.isPressed)
        {
            held = true;
            pos = ts.primaryTouch.position.ReadValue();
            return;
        }
        Mouse m = Mouse.current;
        if (m != null)
        {
            pos = m.position.ReadValue();
            held = m.leftButton.isPressed;
        }
#elif ENABLE_LEGACY_INPUT_MANAGER
        if (Input.touchCount > 0)
        {
            held = true;
            pos = Input.GetTouch(0).position;
            return;
        }
        pos = Input.mousePosition;
        held = Input.GetMouseButton(0);
#endif
    }

    static void UpdatePointer()
    {
        if (pointerFrame == Time.frameCount) return;
        pointerFrame = Time.frameCount;

        bool held; Vector2 pos;
        ReadPointer(out held, out pos);
        pointerPressedThisFrame = held && !pointerHeld;
        pointerHeld = held;
        pointerPos = pos;
        swipe = SwipeDir.None;

        if (pointerPressedThisFrame)
        {
            pressPos = pos;
            pressTime = Time.unscaledTime;
            swipeUsed = false;
        }
        else if (held && !swipeUsed)
        {
            // a swipe = the finger moved far enough quickly enough (one swipe per touch)
            Vector2 d = pos - pressPos;
            float threshold = Mathf.Min(Screen.width, Screen.height) * 0.07f;
            if (d.magnitude > threshold && Time.unscaledTime - pressTime < 0.6f)
            {
                swipeUsed = true;
                if (Mathf.Abs(d.x) > Mathf.Abs(d.y)) swipe = d.x > 0f ? SwipeDir.Right : SwipeDir.Left;
                else swipe = d.y > 0f ? SwipeDir.Up : SwipeDir.Down;
            }
        }
    }

    // A swipe made in this frame (SwipeDir.None if there was none).
    public static SwipeDir Swipe
    {
        get { UpdatePointer(); return swipe; }
    }

    // The pointer was pressed in this frame (a tap or a click) - used by the menu buttons.
    public static bool PointerPressed
    {
        get { UpdatePointer(); return pointerPressedThisFrame; }
    }

    public static Vector2 PointerPosition
    {
        get { UpdatePointer(); return pointerPos; }
    }

    public static bool HasTouch
    {
        get
        {
#if ENABLE_INPUT_SYSTEM
            return Touchscreen.current != null;
#elif ENABLE_LEGACY_INPUT_MANAGER
            return Input.touchSupported;
#else
            return false;
#endif
        }
    }

    public static bool HasMouse
    {
        get
        {
#if ENABLE_INPUT_SYSTEM
            return Mouse.current != null;
#elif ENABLE_LEGACY_INPUT_MANAGER
            return Input.mousePresent;
#else
            return false;
#endif
        }
    }

    public static Vector2 MousePosition
    {
        get
        {
#if ENABLE_INPUT_SYSTEM
            return Mouse.current != null ? Mouse.current.position.ReadValue() : Vector2.zero;
#elif ENABLE_LEGACY_INPUT_MANAGER
            return Input.mousePosition;
#else
            return Vector2.zero;
#endif
        }
    }

    public static bool MouseClicked
    {
        get
        {
#if ENABLE_INPUT_SYSTEM
            return Mouse.current != null && Mouse.current.leftButton.wasPressedThisFrame;
#elif ENABLE_LEGACY_INPUT_MANAGER
            return Input.GetMouseButtonDown(0);
#else
            return false;
#endif
        }
    }

    // Мышь сдвинулась в этом кадре (чтобы наведение не "перебивало" выбор стрелками).
    public static bool MouseMoved
    {
        get
        {
            if (cachedFrame != Time.frameCount)
            {
                cachedFrame = Time.frameCount;
                Vector2 p = MousePosition;
                mouseMoved = (p - lastMouse).sqrMagnitude > 0.01f;
                lastMouse = p;
            }
            return mouseMoved;
        }
    }

#if ENABLE_INPUT_SYSTEM
    static Key ToKey(GKey k)
    {
        switch (k)
        {
            case GKey.Up: return Key.UpArrow;
            case GKey.Down: return Key.DownArrow;
            case GKey.Left: return Key.LeftArrow;
            case GKey.Right: return Key.RightArrow;
            case GKey.W: return Key.W;
            case GKey.A: return Key.A;
            case GKey.S: return Key.S;
            case GKey.D: return Key.D;
            case GKey.Space: return Key.Space;
            case GKey.Escape: return Key.Escape;
            case GKey.F1: return Key.F1;
            case GKey.Tab: return Key.Tab;
            case GKey.K: return Key.K;
            case GKey.L: return Key.L;
            case GKey.RightShift: return Key.RightShift;
            case GKey.RightCtrl: return Key.RightCtrl;
            case GKey.Numpad8: return Key.Numpad8;
            case GKey.Numpad4: return Key.Numpad4;
            case GKey.Numpad5: return Key.Numpad5;
            case GKey.Numpad6: return Key.Numpad6;
            case GKey.Numpad0: return Key.Numpad0;
            case GKey.M: return Key.M;
            default: return Key.Enter;
        }
    }
#elif ENABLE_LEGACY_INPUT_MANAGER
    static KeyCode ToKeyCode(GKey k)
    {
        switch (k)
        {
            case GKey.Up: return KeyCode.UpArrow;
            case GKey.Down: return KeyCode.DownArrow;
            case GKey.Left: return KeyCode.LeftArrow;
            case GKey.Right: return KeyCode.RightArrow;
            case GKey.W: return KeyCode.W;
            case GKey.A: return KeyCode.A;
            case GKey.S: return KeyCode.S;
            case GKey.D: return KeyCode.D;
            case GKey.Space: return KeyCode.Space;
            case GKey.Escape: return KeyCode.Escape;
            case GKey.F1: return KeyCode.F1;
            case GKey.Tab: return KeyCode.Tab;
            case GKey.K: return KeyCode.K;
            case GKey.L: return KeyCode.L;
            case GKey.RightShift: return KeyCode.RightShift;
            case GKey.RightCtrl: return KeyCode.RightControl;
            case GKey.Numpad8: return KeyCode.Keypad8;
            case GKey.Numpad4: return KeyCode.Keypad4;
            case GKey.Numpad5: return KeyCode.Keypad5;
            case GKey.Numpad6: return KeyCode.Keypad6;
            case GKey.Numpad0: return KeyCode.Keypad0;
            case GKey.M: return KeyCode.M;
            default: return KeyCode.Return;
        }
    }
#endif
}
