using UnityEngine;
using UnityEngine.SceneManagement;

// The main menu (scene 0): the title, "Play", the language choice (Русский / English / Oʻzbekcha) and "Quit".
public class MainMenu : MonoBehaviour
{
    [SerializeField] int firstLevelScene = 1;
    [SerializeField] Transform showcase;       // the rocket that slowly turns behind the menu
    [SerializeField] float showcaseSpeed = 25f;

    void Awake()
    {
        Time.timeScale = 1f;
        AudioListener.pause = false;
    }

    void Update()
    {
        if (showcase != null) showcase.Rotate(Vector3.up, showcaseSpeed * Time.unscaledDeltaTime, Space.World);
    }

    void OnGUI()
    {
        UIKit.Begin();
        float w = UIKit.Width;
        float h = UIKit.Height;

        float bw = 460f, bh = 84f;
        float x = (w - bw) / 2f;
        float y = Mathf.Max(20f, h * 0.08f);

        UIKit.ShadowLabel(new Rect(0, y, w, 100), "ROCKET BOOST", UIKit.Title);
        y += 105f;

        if (GameManager.GameCompleted)
        {
            UIKit.ShadowLabel(new Rect(40, y, w - 80, 44), Loc.T("completed"), UIKit.Big);
            y += 50f;
        }
        UIKit.ShadowLabel(new Rect(60, y, w - 120, 60), Loc.T("goal"), UIKit.Small);
        y += 75f;

        if (UIKit.DoButton(new Rect(x, y, bw, bh), Loc.T("play")))
        {
            GameManager.ResetRun();
            SceneManager.LoadScene(firstLevelScene);
        }
        y += bh + 24f;

        float lw = 600f;
        GUI.Label(new Rect((w - lw) / 2f, y, lw, 34), Loc.T("language"), UIKit.Small);
        y += 40f;
        UIKit.LanguageRow(new Rect((w - lw) / 2f, y, lw, 70));
        y += 70f + 24f;

#if !UNITY_WEBGL
        if (UIKit.DoButton(new Rect(x, y, bw, bh * 0.8f), Loc.T("quit")))
        {
            Application.Quit();
#if UNITY_EDITOR
            UnityEditor.EditorApplication.isPlaying = false;
#endif
        }
#endif

        string hint = Application.isMobilePlatform ? Loc.T("hint_mobile") : Loc.T("hint_pc");
        UIKit.ShadowLabel(new Rect(20, h - 50, w - 40, 40), hint, UIKit.Small);
    }
}
