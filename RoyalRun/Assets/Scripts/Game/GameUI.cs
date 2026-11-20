using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

// One player's part of the screen (the in-game interface).
public class ColumnHud
{
    public RectTransform root;
    public Text score;          // big, top left
    public Text distance;       // metres, under the score
    public Text coins;          // coin counter, top right
    public Text combo;          // "x3" under the coins
    public Text status;         // active power-ups
    public GameObject timeBar;  // classic mode only
    public Text time;
    public RectTransform timeFill;
    public Image timeFillImage;
    public Text big;            // GO! / RUN OVER
    public Text toast;          // pop-up messages
    public Text hint;           // how to control, at the bottom for the first seconds
    public Image flash;         // a red flash over the whole strip on a hit
    public MenuButton pause;    // the "II" button (tap / click)
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
    public Camera cam;          // for buttons on a camera canvas (the in-game pause button)

    public void Refresh()
    {
        background.color = selected ? highlight : normal;
        label.color = selected ? new Color(0.16f, 0.08f, 0.30f) : Color.white;
    }

    public bool Contains(Vector2 screenPoint)
    {
        return rect.gameObject.activeInHierarchy && RectTransformUtility.RectangleContainsScreenPoint(rect, screenPoint, cam);
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

    // A tall screen (a phone held upright): menus use the portrait layout.
    public static bool Portrait { get { return Screen.height > Screen.width; } }

    // Picks a layout rectangle: (anchorMin, anchorMax) for landscape or for portrait.
    public static void Pick(Vector4 landscape, Vector4 portrait, out Vector2 min, out Vector2 max)
    {
        Vector4 r = Portrait ? portrait : landscape;
        min = new Vector2(r.x, r.y);
        max = new Vector2(r.z, r.w);
    }

    // A rectangle anchored to a corner/edge with a fixed size in reference pixels.
    public static RectTransform CreateAnchored(string name, Transform parent, Vector2 anchor, Vector2 pivot, Vector2 pos, Vector2 size)
    {
        GameObject go = new GameObject(name, typeof(RectTransform));
        go.transform.SetParent(parent, false);
        RectTransform rt = go.GetComponent<RectTransform>();
        rt.anchorMin = anchor;
        rt.anchorMax = anchor;
        rt.pivot = pivot;
        rt.anchoredPosition = pos;
        rt.sizeDelta = size;
        return rt;
    }

    public static Canvas CreateCanvas(string name, Transform parent)
    {
        GameObject go = new GameObject(name);
        go.transform.SetParent(parent, false);

        Canvas canvas = go.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;

        CanvasScaler scaler = go.AddComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = Portrait ? new Vector2(1080f, 1920f) : new Vector2(1920f, 1080f);
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

        {
            Vector2 pos = GameInput.PointerPosition;
            bool moved = GameInput.HasMouse && GameInput.MouseMoved;
            bool clicked = GameInput.PointerPressed;
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
    // Layout (works upright and sideways): score and metres top left, coins and combo top right,
    // the pause button in the corner, pop-up messages in the middle, a control hint at the bottom.
    public static ColumnHud CreateColumnHud(Camera cam, int index, int total, string playerName,
                                            string characterName, Color playerColor, Transform parent, bool classic)
    {
        GameObject cgo = new GameObject("HUD Canvas " + (index + 1));
        cgo.transform.SetParent(parent, false);
        Canvas canvas = cgo.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceCamera;
        canvas.worldCamera = cam;
        canvas.planeDistance = 1f;

        float stripAspect = (Screen.width * cam.rect.width) / Mathf.Max(1f, Screen.height * cam.rect.height);
        CanvasScaler scaler = cgo.AddComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = stripAspect < 1f ? new Vector2(1080f, 1920f) : new Vector2(1920f, 1080f);
        scaler.matchWidthOrHeight = 0.5f;

        ColumnHud hud = new ColumnHud();
        RectTransform area = CreateRect("HUD " + (index + 1), cgo.transform, Vector2.zero, Vector2.one);

        // the red flash covers the whole strip (behind everything else)
        RectTransform flash = CreateRect("Hit Flash", area, Vector2.zero, Vector2.one);
        hud.flash = flash.gameObject.AddComponent<Image>();
        hud.flash.color = new Color(1f, 0.1f, 0.1f, 0f);
        hud.flash.raycastTarget = false;
        hud.flash.enabled = false;

        // keep away from the notch and rounded corners of phones
        hud.root = CreateRect("Safe Area", area, Vector2.zero, Vector2.one);
        if (total == 1 && Screen.width > 0 && Screen.height > 0)
        {
            Rect safe = Screen.safeArea;
            hud.root.anchorMin = new Vector2(safe.xMin / Screen.width, safe.yMin / Screen.height);
            hud.root.anchorMax = new Vector2(safe.xMax / Screen.width, safe.yMax / Screen.height);
        }
        Transform r = hud.root;

        // black divider strip between screens
        if (index > 0)
        {
            RectTransform sep = CreateRect("Separator", area, new Vector2(0f, 0f), new Vector2(0f, 1f));
            sep.sizeDelta = new Vector2(8f, 0f);
            Image sepImg = sep.gameObject.AddComponent<Image>();
            sepImg.color = Color.black;
            sepImg.raycastTarget = false;
        }

        // ---- top left: score and metres ----
        RectTransform scoreBox = CreateAnchored("Score Box", r, new Vector2(0f, 1f), new Vector2(0f, 1f), new Vector2(20f, -20f), new Vector2(400f, 140f));
        Image sb = scoreBox.gameObject.AddComponent<Image>();
        sb.sprite = RoundedSprite; sb.type = Image.Type.Sliced; sb.color = new Color(0.05f, 0.03f, 0.1f, 0.55f); sb.raycastTarget = false;
        Image stripe = CreatePanel("Player Colour", scoreBox, new Vector2(0f, 0f), new Vector2(0.025f, 1f), playerColor);
        stripe.type = Image.Type.Simple;
        hud.score = CreateText("Score", scoreBox, new Vector2(0.06f, 0.38f), new Vector2(0.98f, 1f), "0", 70, Gold, TextAnchor.MiddleLeft);
        hud.distance = CreateText("Distance", scoreBox, new Vector2(0.06f, 0.04f), new Vector2(0.98f, 0.42f), "0 m", 32, new Color(1f, 1f, 1f, 0.9f), TextAnchor.MiddleLeft);
        if (total > 1)
            CreateText("Name", scoreBox, new Vector2(0.06f, -0.38f), new Vector2(1.6f, 0f),
                       playerName + "  <size=22>" + characterName + "</size>", 30, playerColor, TextAnchor.MiddleLeft);

        // ---- top right: the pause button, coins, combo ----
        hud.pause = CreateButton("Pause", r, Vector2.zero, Vector2.zero, "II", 46, null);
        RectTransform pr = hud.pause.rect;
        pr.anchorMin = pr.anchorMax = new Vector2(1f, 1f);
        pr.pivot = new Vector2(1f, 1f);
        pr.anchoredPosition = new Vector2(-20f, -20f);
        pr.sizeDelta = new Vector2(100f, 100f);
        hud.pause.normal = new Color(0.05f, 0.03f, 0.1f, 0.55f);
        hud.pause.cam = cam;
        hud.pause.Refresh();

        RectTransform coinBox = CreateAnchored("Coin Box", r, new Vector2(1f, 1f), new Vector2(1f, 1f), new Vector2(-135f, -20f), new Vector2(250f, 80f));
        Image cb = coinBox.gameObject.AddComponent<Image>();
        cb.sprite = RoundedSprite; cb.type = Image.Type.Sliced; cb.color = new Color(0.05f, 0.03f, 0.1f, 0.55f); cb.raycastTarget = false;
        RectTransform coinIcon = CreateAnchored("Coin Icon", coinBox, new Vector2(0f, 0.5f), new Vector2(0f, 0.5f), new Vector2(14f, 0f), new Vector2(54f, 54f));
        Image ci = coinIcon.gameObject.AddComponent<Image>();
        ci.sprite = CircleSprite; ci.color = Gold; ci.raycastTarget = false;
        RectTransform coinInner = CreateAnchored("Coin Inner", coinIcon, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(34f, 34f));
        Image cin = coinInner.gameObject.AddComponent<Image>();
        cin.sprite = CircleSprite; cin.color = new Color(1f, 0.92f, 0.55f); cin.raycastTarget = false;
        hud.coins = CreateText("Coins", coinBox, new Vector2(0.32f, 0f), new Vector2(0.95f, 1f), "0", 46, Color.white, TextAnchor.MiddleRight);
        RectTransform comboBox = CreateAnchored("Combo", r, new Vector2(1f, 1f), new Vector2(1f, 1f), new Vector2(-135f, -108f), new Vector2(250f, 64f));
        hud.combo = comboBox.gameObject.AddComponent<Text>();
        StyleText(hud.combo, "", 48, Gold, TextAnchor.MiddleRight, true);

        // ---- the time bar (classic mode) ----
        RectTransform tb = CreateAnchored("Time Bar", r, new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), new Vector2(0f, -175f), new Vector2(620f, 46f));
        hud.timeBar = tb.gameObject;
        Image barBg = tb.gameObject.AddComponent<Image>();
        barBg.sprite = RoundedSprite; barBg.type = Image.Type.Sliced; barBg.color = new Color(0f, 0f, 0f, 0.55f); barBg.raycastTarget = false;
        RectTransform fill = CreateRect("Fill", tb, new Vector2(0.01f, 0.12f), new Vector2(0.99f, 0.88f));
        hud.timeFill = fill;
        hud.timeFillImage = fill.gameObject.AddComponent<Image>();
        hud.timeFillImage.sprite = RoundedSprite;
        hud.timeFillImage.type = Image.Type.Sliced;
        hud.timeFillImage.raycastTarget = false;
        hud.time = CreateText("Time", tb, Vector2.zero, Vector2.one, "", 28, Color.white, TextAnchor.MiddleCenter);
        hud.timeBar.SetActive(classic);

        // ---- power-ups (left, under the score) ----
        RectTransform st = CreateAnchored("Status", r, new Vector2(0f, 1f), new Vector2(0f, 1f), new Vector2(24f, total > 1 ? -215f : -170f), new Vector2(560f, 56f));
        hud.status = st.gameObject.AddComponent<Text>();
        StyleText(hud.status, "", 32, Color.white, TextAnchor.MiddleLeft, true);

        // ---- the middle and the bottom ----
        hud.toast = CreateText("Toast", r, new Vector2(0.04f, 0.6f), new Vector2(0.96f, 0.72f), "", 50, Color.white, TextAnchor.MiddleCenter);
        hud.big = CreateText("Big", r, new Vector2(0.04f, 0.38f), new Vector2(0.96f, 0.6f), "", 76, new Color(1f, 0.55f, 0.5f), TextAnchor.MiddleCenter);
        hud.hint = CreateText("Hint", r, new Vector2(0.04f, 0.03f), new Vector2(0.96f, 0.13f), "", 32, new Color(1f, 1f, 1f, 0.9f), TextAnchor.MiddleCenter);
        return hud;
    }

    static void StyleText(Text t, string text, int size, Color color, TextAnchor align, bool outline)
    {
        t.font = DefaultFont;
        t.text = text;
        t.fontSize = size;
        t.color = color;
        t.alignment = align;
        t.horizontalOverflow = HorizontalWrapMode.Overflow;
        t.verticalOverflow = VerticalWrapMode.Overflow;
        t.supportRichText = true;
        t.raycastTarget = false;
        if (outline)
        {
            Outline o = t.gameObject.AddComponent<Outline>();
            o.effectColor = new Color(0f, 0f, 0f, 0.8f);
            o.effectDistance = new Vector2(2f, -2f);
        }
    }

    static Sprite circleSprite;

    // A filled circle (the coin icon).
    public static Sprite CircleSprite
    {
        get
        {
            if (circleSprite != null) return circleSprite;
            const int size = 64;
            Texture2D tex = new Texture2D(size, size, TextureFormat.RGBA32, false);
            tex.filterMode = FilterMode.Bilinear;
            tex.wrapMode = TextureWrapMode.Clamp;
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    float d = Vector2.Distance(new Vector2(x + 0.5f, y + 0.5f), new Vector2(size * 0.5f, size * 0.5f));
                    tex.SetPixel(x, y, new Color(1f, 1f, 1f, Mathf.Clamp01(size * 0.5f - d)));
                }
            tex.Apply();
            circleSprite = Sprite.Create(tex, new Rect(0, 0, size, size), new Vector2(0.5f, 0.5f), 100f);
            return circleSprite;
        }
    }
}
