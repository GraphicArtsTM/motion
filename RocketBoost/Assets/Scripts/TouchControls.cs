using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.Controls;

// Buttons on the screen for a phone: turn left, turn right and "thrust".
// Movement reads TouchControls.Thrust and TouchControls.Rotation.
// From the ads guide, Part 4.2. Fingers are read through the new Input System (Touchscreen / Mouse),
// so the script works with any "Active Input Handling" setting.
public class TouchControls : MonoBehaviour
{
    // Thrust: true while the thrust button is pressed
    public static bool Thrust { get; private set; }
    // Rotation: -1 (left), 0 or 1 (right), the same as the arrow keys
    public static float Rotation { get; private set; }

    [SerializeField] float buttonSize = 130f; // the turn buttons
    [SerializeField] float thrustSize = 180f; // the big thrust button
    [SerializeField] float gap = 18f;
    [SerializeField] float margin = 40f;
    [SerializeField] bool showOnPC = false; // a checkbox to test in the editor with the mouse

    Rect leftRect, rightRect, thrustRect;
    bool leftDown, rightDown, thrustDown;
    Texture2D arrowTexture;

    bool IsVisible()
    {
        if (!Application.isMobilePlatform && !showOnPC) return false;
        GameManager gm = GameManager.Instance;
        return gm == null || (!gm.IsGameOver && !gm.IsPaused);
    }

    void BuildLayout()
    {
        float screenW = UIKit.Width;
        float screenH = UIKit.Height;
        float y = screenH - margin - buttonSize;
        leftRect = new Rect(margin, y, buttonSize, buttonSize);
        rightRect = new Rect(margin + buttonSize + gap, y, buttonSize, buttonSize);
        thrustRect = new Rect(screenW - margin - thrustSize, screenH - margin - thrustSize, thrustSize, thrustSize);
    }

    void Update()
    {
        leftDown = rightDown = thrustDown = false;
        if (!IsVisible())
        {
            Thrust = false;
            Rotation = 0f;
            return;
        }
        BuildLayout();

        // Every finger is checked, so two buttons can be held at once (thrust + turn)
        bool anyTouch = false;
        Touchscreen touchscreen = Touchscreen.current;
        if (touchscreen != null)
        {
            foreach (TouchControl touch in touchscreen.touches)
            {
                if (!touch.press.isPressed) continue;
                anyTouch = true;
                CheckPoint(touch.position.ReadValue());
            }
        }

        // There are no fingers in the editor, so we use the mouse
        if (!anyTouch && Mouse.current != null && Mouse.current.leftButton.isPressed)
        {
            CheckPoint(Mouse.current.position.ReadValue());
        }

        Thrust = thrustDown;
        Rotation = (rightDown ? 1f : 0f) - (leftDown ? 1f : 0f);
    }

    void OnDisable()
    {
        Thrust = false;
        Rotation = 0f;
    }

    void CheckPoint(Vector2 screenPos)
    {
        // Touch: (0,0) is at the bottom left. GUI: (0,0) is at the top left. We flip Y.
        float scale = UIKit.Scale;
        Vector2 p = new Vector2(screenPos.x / scale, (Screen.height - screenPos.y) / scale);
        if (leftRect.Contains(p)) leftDown = true;
        if (rightRect.Contains(p)) rightDown = true;
        if (thrustRect.Contains(p)) thrustDown = true;
    }

    void OnGUI()
    {
        if (!IsVisible()) return;
        if (arrowTexture == null) arrowTexture = MakeArrowTexture();
        UIKit.Begin();
        BuildLayout();
        Matrix4x4 scaleMatrix = GUI.matrix;
        DrawButton(leftRect, 270f, leftDown, scaleMatrix);
        DrawButton(rightRect, 90f, rightDown, scaleMatrix);
        DrawButton(thrustRect, 0f, thrustDown, scaleMatrix);
        GUI.matrix = scaleMatrix;
        GUI.color = Color.white;
    }

    void DrawButton(Rect r, float angle, bool pressed, Matrix4x4 scaleMatrix)
    {
        GUI.matrix = scaleMatrix;
        GUI.color = pressed ? new Color(1f, 1f, 1f, 0.55f) : new Color(0f, 0f, 0f, 0.45f);
        GUI.DrawTexture(r, Texture2D.whiteTexture);

        Vector3 pivot = new Vector3(r.center.x, r.center.y, 0f);
        Matrix4x4 rotate = Matrix4x4.TRS(pivot, Quaternion.Euler(0f, 0f, angle), Vector3.one)
                         * Matrix4x4.TRS(-pivot, Quaternion.identity, Vector3.one);
        GUI.matrix = scaleMatrix * rotate;
        GUI.color = pressed ? new Color(0f, 0f, 0f, 0.9f) : new Color(1f, 1f, 1f, 0.85f);
        float pad = r.width * 0.25f;
        GUI.DrawTexture(new Rect(r.x + pad, r.y + pad, r.width - 2f * pad, r.height - 2f * pad), arrowTexture);
    }

    // A triangle (point up) drawn by code: we do not need a picture file
    Texture2D MakeArrowTexture()
    {
        int size = 64;
        Texture2D tex = new Texture2D(size, size, TextureFormat.RGBA32, false);
        tex.wrapMode = TextureWrapMode.Clamp;
        for (int y = 0; y < size; y++)
        {
            float halfWidth = (size - 1 - y) / (float)(size - 1) * (size / 2f);
            for (int x = 0; x < size; x++)
            {
                bool inside = Mathf.Abs(x - (size - 1) / 2f) <= halfWidth;
                tex.SetPixel(x, y, inside ? Color.white : new Color(1f, 1f, 1f, 0f));
            }
        }
        tex.Apply();
        return tex;
    }
}
