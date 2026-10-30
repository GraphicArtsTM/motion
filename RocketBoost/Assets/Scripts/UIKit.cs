using UnityEngine;

// Shared look for all OnGUI screens (menu, HUD, Game Over, pause).
// The font is DejaVu Sans Bold from Assets/Resources/Fonts: it has Cyrillic and the Uzbek letters (oʻ, gʻ),
// so the text looks the same on PC, Android and in the browser (WebGL has no system fonts).
public static class UIKit
{
    // The "virtual" screen: the shorter side is always 720 units
    public const float RefSize = 720f;

    public static GUIStyle Label { get; private set; }
    public static GUIStyle Small { get; private set; }
    public static GUIStyle SmallLeft { get; private set; }
    public static GUIStyle Title { get; private set; }
    public static GUIStyle Big { get; private set; }
    public static GUIStyle Button { get; private set; }
    public static GUIStyle Selected { get; private set; }
    public static GUIStyle Panel { get; private set; }

    static Font font;
    static Texture2D texNormal, texHover, texActive, texSelected, texPanel;

    public static float Scale => Mathf.Max(0.01f, Mathf.Min(Screen.width, Screen.height) / RefSize);
    public static float Width => Screen.width / Scale;
    public static float Height => Screen.height / Scale;

    // Call at the start of every OnGUI: sets the scale and creates the styles once
    public static void Begin()
    {
        EnsureStyles();
        GUI.matrix = Matrix4x4.Scale(new Vector3(Scale, Scale, 1f));
        GUI.color = Color.white;
    }

    public static bool DoButton(Rect r, string text, bool selected = false)
    {
        return GUI.Button(r, text, selected ? Selected : Button);
    }

    // Three language buttons in a row. Returns true if the language was changed.
    public static bool LanguageRow(Rect r)
    {
        bool changed = false;
        float gap = 10f;
        float w = (r.width - gap * 2f) / 3f;
        for (int i = 0; i < 3; i++)
        {
            Rect b = new Rect(r.x + i * (w + gap), r.y, w, r.height);
            bool isCurrent = (int)Loc.Current == i;
            if (DoButton(b, Loc.LanguageNames[i], isCurrent) && !isCurrent)
            {
                Loc.Set((Lang)i);
                changed = true;
            }
        }
        return changed;
    }

    public static void DrawPanel(Rect r)
    {
        GUI.Box(r, GUIContent.none, Panel);
    }

    // Text with a soft dark shadow, so it can be read over any background
    public static void ShadowLabel(Rect r, string text, GUIStyle style)
    {
        Color old = GUI.color;
        GUI.color = new Color(0f, 0f, 0f, 0.7f * old.a);
        GUI.Label(new Rect(r.x + 2f, r.y + 2f, r.width, r.height), text, style);
        GUI.color = old;
        GUI.Label(r, text, style);
    }

    static void EnsureStyles()
    {
        if (Label != null && texNormal != null) return;

        if (font == null) font = Resources.Load<Font>("Fonts/DejaVuSans-Bold");

        texNormal = MakeTex(new Color(0.16f, 0.22f, 0.38f, 0.92f));
        texHover = MakeTex(new Color(0.22f, 0.32f, 0.55f, 0.95f));
        texActive = MakeTex(new Color(0.95f, 0.55f, 0.15f, 1f));
        texSelected = MakeTex(new Color(0.95f, 0.55f, 0.15f, 0.95f));
        texPanel = MakeTex(new Color(0.03f, 0.05f, 0.12f, 0.85f));

        Label = new GUIStyle(GUI.skin.label)
        {
            font = font,
            fontSize = 28,
            alignment = TextAnchor.MiddleLeft,
            wordWrap = true,
        };
        Label.normal.textColor = Color.white;

        Small = new GUIStyle(Label) { fontSize = 22, alignment = TextAnchor.MiddleCenter };
        Small.normal.textColor = new Color(0.85f, 0.9f, 1f);
        SmallLeft = new GUIStyle(Small) { alignment = TextAnchor.MiddleLeft };

        Big = new GUIStyle(Label) { fontSize = 40, alignment = TextAnchor.MiddleCenter };

        Title = new GUIStyle(Label) { fontSize = 76, alignment = TextAnchor.MiddleCenter, wordWrap = false };
        Title.normal.textColor = new Color(1f, 0.85f, 0.3f);

        Button = new GUIStyle(GUI.skin.button)
        {
            font = font,
            fontSize = 30,
            alignment = TextAnchor.MiddleCenter,
            wordWrap = true,
            padding = new RectOffset(12, 12, 8, 8),
            border = new RectOffset(0, 0, 0, 0),
        };
        SetBackground(Button, texNormal, texHover, texActive, Color.white);

        Selected = new GUIStyle(Button);
        SetBackground(Selected, texSelected, texSelected, texActive, new Color(0.1f, 0.05f, 0f));

        Panel = new GUIStyle(GUI.skin.box) { border = new RectOffset(0, 0, 0, 0) };
        Panel.normal.background = texPanel;
    }

    static void SetBackground(GUIStyle s, Texture2D normal, Texture2D hover, Texture2D active, Color text)
    {
        s.normal.background = normal;
        s.hover.background = hover;
        s.focused.background = hover;
        s.active.background = active;
        s.onNormal.background = normal;
        s.onHover.background = hover;
        s.onActive.background = active;
        s.normal.textColor = text;
        s.hover.textColor = text;
        s.focused.textColor = text;
        s.active.textColor = Color.black;
        s.onNormal.textColor = text;
        s.onHover.textColor = text;
        s.onActive.textColor = Color.black;
    }

    static Texture2D MakeTex(Color c)
    {
        Texture2D t = new Texture2D(1, 1, TextureFormat.RGBA32, false);
        t.SetPixel(0, 0, c);
        t.Apply();
        // HideAndDontSave: the texture is not unloaded when a new scene loads
        t.hideFlags = HideFlags.HideAndDontSave;
        return t;
    }
}
