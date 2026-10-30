using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.SceneManagement;

// The interface inside a level: the tries counter, the level name, the pause button,
// the pause window, the Game Over window and short messages. Everything is drawn with OnGUI
// (no Canvas needed). All texts come from Loc, so they follow the chosen language.
// Based on the ads guide, Part 2.4.
public class GameUI : MonoBehaviour
{
    [SerializeField] float hintSeconds = 7f;

    static bool hintShown; // the controls hint is shown once per game launch

    void Update()
    {
        GameManager gm = GameManager.Instance;
        if (gm == null) return;

        // Escape (or "Back" on Android) opens and closes the pause window
        if (Keyboard.current != null && Keyboard.current.escapeKey.wasPressedThisFrame && !gm.IsGameOver)
        {
            gm.SetPaused(!gm.IsPaused);
        }

        if (!hintShown && Time.timeSinceLevelLoad > hintSeconds) hintShown = true;
    }

    void OnGUI()
    {
        GameManager gm = GameManager.Instance;
        if (gm == null) return;

        UIKit.Begin();
        float w = UIKit.Width;
        float h = UIKit.Height;

        DrawHud(gm, w);

        if (gm.IsGameOver)
        {
            DrawGameOver(gm, w, h);
            return;
        }
        if (gm.IsPaused)
        {
            DrawPause(gm, w, h);
            return;
        }

        string key = gm.CurrentAnnouncement(1.8f);
        if (key != null)
        {
            UIKit.ShadowLabel(new Rect(0, h * 0.25f, w, 70), Loc.T(key), UIKit.Big);
        }

        if (!hintShown)
        {
            string hint = Application.isMobilePlatform ? Loc.T("hint_mobile") : Loc.T("hint_pc");
            UIKit.ShadowLabel(new Rect(40, 110, w - 80, 40), hint, UIKit.Small);
            UIKit.ShadowLabel(new Rect(40, 150, w - 80, 40), Loc.T("goal"), UIKit.Small);
        }
    }

    void DrawHud(GameManager gm, float w)
    {
        UIKit.ShadowLabel(new Rect(20, 10, 520, 40),
            Loc.T("attempts") + ": " + gm.Attempts + " / " + gm.MaxAttempts, UIKit.Label);

        Scene scene = SceneManager.GetActiveScene();
        UIKit.ShadowLabel(new Rect(20, 50, 620, 36),
            Loc.T("level") + " " + scene.buildIndex + ": " + Loc.T("level_" + scene.name), UIKit.SmallLeft);

        CollisionHandler ch = FindRocket();
        if (ch != null && !ch.IsCollidable)
        {
            UIKit.ShadowLabel(new Rect(20, 84, 620, 30), Loc.T("debug_collide", Loc.T("off")), UIKit.SmallLeft);
        }

        if (!gm.IsGameOver && !gm.IsPaused)
        {
            if (UIKit.DoButton(new Rect(w - 190, 14, 170, 64), Loc.T("menu")))
                gm.SetPaused(true);
        }
    }

    void DrawPause(GameManager gm, float w, float h)
    {
        float bw = 520f, bh = 80f, panelH = 470f;
        float x = (w - bw) / 2f;
        float top = Mathf.Max(20f, (h - panelH) / 2f);
        UIKit.DrawPanel(new Rect(x - 30, top, bw + 60, panelH));
        UIKit.ShadowLabel(new Rect(x, top + 15, bw, 60), Loc.T("pause"), UIKit.Big);

        float y = top + 95f;
        if (UIKit.DoButton(new Rect(x, y, bw, bh), Loc.T("resume"))) gm.SetPaused(false);
        y += bh + 18f;
        if (UIKit.DoButton(new Rect(x, y, bw, bh), Loc.T("main_menu"))) gm.GoToMainMenu();
        y += bh + 26f;
        GUI.Label(new Rect(x, y, bw, 34), Loc.T("language"), UIKit.Small);
        y += 40f;
        UIKit.LanguageRow(new Rect(x, y, bw, 70));
    }

    void DrawGameOver(GameManager gm, float w, float h)
    {
        float bw = 520f, bh = 80f, panelH = 430f;
        float x = (w - bw) / 2f;
        float top = Mathf.Max(20f, (h - panelH) / 2f);
        UIKit.DrawPanel(new Rect(x - 30, top, bw + 60, panelH));
        UIKit.ShadowLabel(new Rect(x, top + 20, bw, 60), Loc.T("game_over"), UIKit.Big);

        float y = top + 110f;
        AdManager ads = AdManager.Instance;
        if (gm.CanContinue && ads != null && ads.IsRewardedReady())
        {
            if (UIKit.DoButton(new Rect(x, y, bw, bh), Loc.T("watch_ad", gm.BonusAttempts)))
                ads.ShowRewarded(gm.ContinueAfterReward);
            y += bh + 18f;
        }

        if (UIKit.DoButton(new Rect(x, y, bw, bh), Loc.T("play_again"))) gm.Restart();
        y += bh + 18f;
        if (UIKit.DoButton(new Rect(x, y, bw, bh), Loc.T("main_menu"))) gm.GoToMainMenu();
    }

    CollisionHandler cachedRocket;

    CollisionHandler FindRocket()
    {
        if (cachedRocket == null) cachedRocket = FindAnyObjectByType<CollisionHandler>();
        return cachedRocket;
    }
}
