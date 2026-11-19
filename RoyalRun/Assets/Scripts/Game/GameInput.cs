using UnityEngine;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

// Клавиши, которые нужны игре.
public enum GKey { Up, Down, Left, Right, W, A, S, D, Enter, Space, Escape, F1, Tab, K, L }

// Ввод с клавиатуры и мыши, который работает при любой настройке проекта
// (Project Settings -> Player -> Active Input Handling):
//   "Input System Package (New)" или "Both" - читаем через новый Input System (Keyboard.current / Mouse.current);
//   "Input Manager (Old)"                  - читаем через старый UnityEngine.Input.
// Так проект открывается и работает сразу, без ручной настройки.
public static class GameInput
{
    static int cachedFrame = -1;
    static Vector2 lastMouse;
    static bool mouseMoved;

    // Клавиша нажата прямо сейчас (удерживается).
    public static bool Held(GKey k)
    {
#if ENABLE_INPUT_SYSTEM
        Keyboard kb = Keyboard.current;
        if (kb == null) return false;
        switch (k)
        {
            case GKey.Enter: return kb.enterKey.isPressed || kb.numpadEnterKey.isPressed;
            default: return kb[ToKey(k)].isPressed;
        }
#elif ENABLE_LEGACY_INPUT_MANAGER
        switch (k)
        {
            case GKey.Enter: return Input.GetKey(KeyCode.Return) || Input.GetKey(KeyCode.KeypadEnter);
            default: return Input.GetKey(ToKeyCode(k));
        }
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
        switch (k)
        {
            case GKey.Enter: return kb.enterKey.wasPressedThisFrame || kb.numpadEnterKey.wasPressedThisFrame;
            default: return kb[ToKey(k)].wasPressedThisFrame;
        }
#elif ENABLE_LEGACY_INPUT_MANAGER
        switch (k)
        {
            case GKey.Enter: return Input.GetKeyDown(KeyCode.Return) || Input.GetKeyDown(KeyCode.KeypadEnter);
            default: return Input.GetKeyDown(ToKeyCode(k));
        }
#else
        return false;
#endif
    }

    // Направление WASD / стрелки, длина не больше 1.
    public static Vector2 MoveVector()
    {
        float x = 0f, y = 0f;
        if (Held(GKey.A) || Held(GKey.Left)) x -= 1f;
        if (Held(GKey.D) || Held(GKey.Right)) x += 1f;
        if (Held(GKey.W) || Held(GKey.Up)) y += 1f;
        if (Held(GKey.S) || Held(GKey.Down)) y -= 1f;
        return Vector2.ClampMagnitude(new Vector2(x, y), 1f);
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
            default: return KeyCode.Return;
        }
    }
#endif
}
