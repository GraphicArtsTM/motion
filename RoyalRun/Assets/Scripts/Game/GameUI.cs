using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

// One player's part of the screen: name, time, score, pop-up messages.
public class ColumnHud
{
    public RectTransform root;
    public Image badge;
    public Text name;
    public Text character;
    public Text time;
    public RectTransform timeFill;
    public Image timeFillImage;
    public Text score;
    public Text big;
    public Text toast;
    public Text combo;       // "x3"
    public Text status;      // active power-ups
    public Text distance;    // metres run
    public Image flash;      // a red flash over the whole strip on a hit
}

// A menu button. Works with mouse and keyboard, without an EventSystem.
public class MenuButton
{
    public RectTransform rect;
    public Image background;
    public Text label;
    public Action onClick;
    public Color normal = new Color(0.20f, 0.14f, 0.36f, 0.92f);
    public Color highlight = new Color(1f, 0.78f, 0.15f, 1f);
    public bool selected;

    public void Refresh()
    {
        background.color = selected ? highlight : normal;
        label.color = selected ? new Color(0.16f, 0.08f, 0.30f) : Color.white;
    }

    public bool Contains(Vector2 screenPoint)
    {
        return rect.gameObject.activeInHierarchy && RectTransformUtility.RectangleContainsScreenPoint(rect, screenPoint, null);
    }
}

// Helpers for building the UI from code (no prefabs or manual placement).
// Text is a regular UnityEngine.UI.Text with the built-in font, which supports Cyrillic letters.
public static class GameUI
{
    public static readonly Color Gold = new Color(1f, 0.84f, 0.3f);
    public static readonly Color Panel = new Color(0.08f, 0.05f, 0.16f, 0.82f);
    public static readonly Color PanelLight = new Color(1f, 1f, 1f, 0.10f);
    public static readonly Color Cyan = new Color(0.5f, 0.95f, 1f);

    static Font font;
    static Sprite roundedSprite;

    // Texts whose content is a localization key: they are re-translated when the language changes.
    static readonly List<KeyValuePair<Text, string>> bound = new List<KeyValuePair<Text, string>>();
    static readonly List<KeyValuePair<Text, Func<string>>> boundFn = new List<KeyValuePair<Text, Func<string>>>();

    public static Text Bind(Text t, string key)
    {
        t.text = Loc.T(key);
        bound.Add(new KeyValuePair<Text, string>(t, key));
        return t;
    }

    public static Text Bind(Text t, Func<string> text)
    {
        t.text = text();
        boundFn.Add(new KeyValuePair<Text, Func<string>>(t, text));
        return t;
    }

    public static void RefreshBindings()
    {
        bound.RemoveAll(p => p.Key == null);
        boundFn.RemoveAll(p => p.Key == null);
        foreach (KeyValuePair<Text, string> p in bound) p.Key.text = Loc.T(p.Value);
        foreach (KeyValuePair<Text, Func<string>> p in boundFn) p.Key.text = p.Value();
    }

    public static void ClearBindings()
    {
        bound.Clear();
        boundFn.Clear();
    }

    public static Font DefaultFont
    {
        get
        {
            if (font == null) font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            return font;
        }
    }

    // A rounded rectangle drawn by code. With "nine slices" (Sliced) it stretches without distorting the corners.
    public static Sprite RoundedSprite
    {
        get
        {
            if (roundedSprite != null) return roundedSprite;

            const int size = 64;
            const float radius = 22f;
            Texture2D tex = new Texture2D(size, size, TextureFormat.RGBA32, false);
            tex.filterMode = FilterMode.Bilinear;
            tex.wrapMode = TextureWrapMode.Clamp;

            for (int y = 0; y < size; y++)
            {
                for (int x = 0; x < size; x++)
                {
                    float cx = Mathf.Clamp(x + 0.5f, radius, size - radius);
                    float cy = Mathf.Clamp(y + 0.5f, radius, size - radius);
                    float dx = x + 0.5f - cx;
                    float dy = y + 0.5f - cy;
                    float dist = Mathf.Sqrt(dx * dx + dy * dy);
                    float alpha = Mathf.Clamp01(radius - dist + 0.5f);
                    tex.SetPixel(x, y, new Color(1f, 1f, 1f, alpha));
                }
            }
            tex.Apply();

            roundedSprite = Sprite.Create(tex, new Rect(0, 0, size, size), new Vector2(0.5f, 0.5f), 100f, 0,
                                          SpriteMeshType.FullRect, new Vector4(24, 24, 24, 24));
            return roundedSprite;
        }
    }

    public static Canvas CreateCanvas(string name, Transform parent)
    {
        GameObject go = new GameObject(name);
        go.transform.SetParent(parent, false);

        Canvas canvas = go.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;

        CanvasScaler scaler = go.AddComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920f, 1080f);
        scaler.matchWidthOrHeight = 0.5f;
        return canvas;
    }

    public static RectTransform CreateRect(string name, Transform parent, Vector2 anchorMin, Vector2 anchorMax)
    {
        GameObject go = new GameObject(name, typeof(RectTransform));
        go.transform.SetParent(parent, false);
        RectTransform rt = go.GetComponent<RectTransform>();
        rt.anchorMin = anchorMin;
        rt.anchorMax = anchorMax;
        rt.offsetMin = Vector2.zero;
        rt.offsetMax = Vector2.zero;
        return rt;
    }

    public static Image CreatePanel(string name, Transform parent, Vector2 anchorMin, Vector2 anchorMax,
                                    Color color, bool rounded = true)
    {
        RectTransform rt = CreateRect(name, parent, anchorMin, anchorMax);
        Image img = rt.gameObject.AddComponent<Image>();
        if (rounded)
        {
            img.sprite = RoundedSprite;
            img.type = Image.Type.Sliced;
        }
        img.color = color;
        img.raycastTarget = false;
        return img;
    }

    public static Text CreateText(string name, Transform parent, Vector2 anchorMin, Vector2 anchorMax,
                                  string text, int size, Color color, TextAnchor align, bool outline = true)
    {
        RectTransform rt = CreateRect(name, parent, anchorMin, anchorMax);
        Text t = rt.gameObject.AddComponent<Text>();
        t.font = DefaultFont;
        t.text = text;
        t.fontSize = size;
        t.color = color;
        t.alignment = align;
        t.horizontalOverflow = HorizontalWrapMode.Wrap;
        t.verticalOverflow = VerticalWrapMode.Overflow;
        t.supportRichText = true;
        t.raycastTarget = false;

        if (outline)
        {
            Outline o = rt.gameObject.AddComponent<Outline>();
            o.effectColor = new Color(0f, 0f, 0f, 0.8f);
            o.effectDistance = new Vector2(2f, -2f);
        }
        return t;
    }

    public static RawImage CreateRawImage(string name, Transform parent, Vector2 anchorMin, Vector2 anchorMax)
    {
        RectTransform rt = CreateRect(name, parent, anchorMin, anchorMax);
        RawImage img = rt.gameObject.AddComponent<RawImage>();
        img.raycastTarget = false;
        return img;
    }

    public static MenuButton CreateButton(string name, Transform parent, Vector2 anchorMin, Vector2 anchorMax,
                                          string label, int fontSize, Action onClick)
    {
        MenuButton b = new MenuButton();
        Image bg = CreatePanel(name, parent, anchorMin, anchorMax, b.normal);
        b.rect = bg.rectTransform;
        b.background = bg;
        b.label = CreateText("Label", bg.transform, new Vector2(0.04f, 0.06f), new Vector2(0.96f, 0.94f), label, fontSize, Color.white,
                             TextAnchor.MiddleCenter, false);
        // long translations (for example in Uzbek) shrink to fit the button
        b.label.resizeTextForBestFit = true;
        b.label.resizeTextMinSize = Mathf.Max(10, fontSize / 2);
        b.label.resizeTextMaxSize = fontSize;
        b.label.verticalOverflow = VerticalWrapMode.Truncate;
        b.onClick = onClick;
        b.Refresh();
        return b;
    }

    // Updates mouse hover/click and keyboard selection for a set of buttons.
    // Returns true if a button was pressed.
    public static bool UpdateButtons(MenuButton[] buttons, ref int selected, bool allowKeyboardNav)
    {
        if (allowKeyboardNav)
        {
            if (GameInput.Down(GKey.Down) || GameInput.Down(GKey.S))
                selected = (selected + 1) % buttons.Length;
            if (GameInput.Down(GKey.Up) || GameInput.Down(GKey.W))
                selected = (selected - 1 + buttons.Length) % buttons.Length;
        }

        if (GameInput.HasMouse)
        {
            Vector2 pos = GameInput.MousePosition;
            bool moved = GameInput.MouseMoved;
            bool clicked = GameInput.MouseClicked;
            for (int i = 0; i < buttons.Length; i++)
            {
                if (buttons[i].Contains(pos))
                {
                    if (moved) selected = i;
                    if (clicked)
                    {
                        selected = i;
                        Refresh(buttons, selected);
                        Press(buttons[i]);
                        return true;
                    }
                }
            }
        }

        Refresh(buttons, selected);

        if (allowKeyboardNav && (GameInput.Down(GKey.Enter) || GameInput.Down(GKey.Space)))
        {
            Press(buttons[selected]);
            return true;
        }
        return false;
    }

    static void Press(MenuButton b)
    {
        Sfx.Play(SynthAudio.Click, 0.6f);
        if (b.onClick != null) b.onClick();
    }

    static void Refresh(MenuButton[] buttons, int selected)
    {
        for (int i = 0; i < buttons.Length; i++)
        {
            buttons[i].selected = (i == selected);
            buttons[i].Refresh();
        }
    }

    // One of N vertical strips of the screen with the player's readouts.
    // The canvas is attached to the player's camera (Screen Space - Camera), so it occupies exactly its strip of the screen.
    public static ColumnHud CreateColumnHud(Camera cam, int index, int total, string playerName,
                                            string characterName, Color playerColor, Transform parent)
    {
        GameObject cgo = new GameObject("HUD Canvas " + (index + 1));
        cgo.transform.SetParent(parent, false);
        Canvas canvas = cgo.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceCamera;
        canvas.worldCamera = cam;
        canvas.planeDistance = 1f;

        CanvasScaler scaler = cgo.AddComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920f, 1080f);
        scaler.matchWidthOrHeight = 0.5f;

        ColumnHud hud = new ColumnHud();
        hud.root = CreateRect("HUD " + (index + 1), cgo.transform, Vector2.zero, Vector2.one);

        RectTransform flash = CreateRect("Hit Flash", hud.root, Vector2.zero, Vector2.one);
        hud.flash = flash.gameObject.AddComponent<Image>();
        hud.flash.color = new Color(1f, 0.1f, 0.1f, 0f);
        hud.flash.raycastTarget = false;
        hud.flash.enabled = false;

        // black divider strip between screens
        if (index > 0)
        {
            RectTransform sep = CreateRect("Separator", hud.root, new Vector2(0f, 0f), new Vector2(0f, 1f));
            sep.sizeDelta = new Vector2(8f, 0f);
            Image sepImg = sep.gameObject.AddComponent<Image>();
            sepImg.color = Color.black;
            sepImg.raycastTarget = false;
        }

        // name and hero badge
        hud.badge = CreatePanel("Badge", hud.root, new Vector2(0.03f, 0.925f), new Vector2(0.60f, 0.985f),
                                new Color(playerColor.r * 0.5f, playerColor.g * 0.5f, playerColor.b * 0.5f, 0.85f));
        hud.name = CreateText("Name", hud.badge.transform, new Vector2(0.05f, 0.30f), new Vector2(0.97f, 1f),
                              playerName, 32, Color.white, TextAnchor.MiddleLeft);
        hud.character = CreateText("Character", hud.badge.transform, new Vector2(0.05f, 0f), new Vector2(0.97f, 0.42f),
                                   characterName, 20, new Color(1f, 1f, 1f, 0.75f), TextAnchor.MiddleLeft, false);

        // score
        Image scorePanel = CreatePanel("ScorePanel", hud.root, new Vector2(0.62f, 0.925f), new Vector2(0.97f, 0.985f), Panel);
        hud.score = CreateText("Score", scorePanel.transform, new Vector2(0.05f, 0f), new Vector2(0.95f, 1f),
                               "0", 36, Gold, TextAnchor.MiddleCenter);

        // time bar
        Image barBg = CreatePanel("TimeBar", hud.root, new Vector2(0.03f, 0.875f), new Vector2(0.97f, 0.915f),
                                  new Color(0f, 0f, 0f, 0.55f));
        RectTransform fill = CreateRect("Fill", barBg.transform, new Vector2(0.01f, 0.12f), new Vector2(0.99f, 0.88f));
        hud.timeFill = fill;
        hud.timeFillImage = fill.gameObject.AddComponent<Image>();
        hud.timeFillImage.sprite = RoundedSprite;
        hud.timeFillImage.type = Image.Type.Sliced;
        hud.timeFillImage.raycastTarget = false;
        hud.time = CreateText("Time", barBg.transform, Vector2.zero, Vector2.one, "", 26, Color.white, TextAnchor.MiddleCenter);

        hud.combo = CreateText("Combo", hud.root, new Vector2(0.62f, 0.80f), new Vector2(0.97f, 0.87f),
                               "", 44, Gold, TextAnchor.MiddleRight);
        hud.status = CreateText("Status", hud.root, new Vector2(0.03f, 0.80f), new Vector2(0.62f, 0.87f),
                                "", 28, Color.white, TextAnchor.MiddleLeft);
        hud.distance = CreateText("Distance", hud.root, new Vector2(0.03f, 0.015f), new Vector2(0.5f, 0.07f),
                                  "", 30, new Color(1f, 1f, 1f, 0.85f), TextAnchor.MiddleLeft);
        hud.toast = CreateText("Toast", hud.root, new Vector2(0.05f, 0.66f), new Vector2(0.95f, 0.77f),
                               "", 44, Color.white, TextAnchor.MiddleCenter);
        hud.big = CreateText("Big", hud.root, new Vector2(0.05f, 0.35f), new Vector2(0.95f, 0.65f),
                             "", 58, new Color(1f, 0.55f, 0.5f), TextAnchor.MiddleCenter);
        return hud;
    }
}
