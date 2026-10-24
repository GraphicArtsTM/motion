using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace WobbleBrawl
{
    /// <summary>Owns the canvas and every screen; GameManager tells it what to show.</summary>
    public sealed class UIRoot
    {
        readonly GameManager gm;
        public readonly Canvas canvas;
        public readonly TitleScreen title;
        public readonly LobbyScreen lobby;
        public readonly HudScreen hud;

        readonly GameObject pauseRoot;
        readonly MenuList pauseMenu;
        readonly GameObject resultsRoot;
        readonly Text resultsTitle;
        readonly RectTransform resultsRows;
        readonly Text banner, bannerSub;
        readonly Image flash;
        float bannerTime, bannerDuration, flashAlpha;

        public UIRoot(GameManager gm, Transform parent)
        {
            this.gm = gm;
            canvas = UIKit.CreateCanvas(parent, "UI", 10);
            var t = canvas.transform;

            hud = new HudScreen(t, gm);
            title = new TitleScreen(t, gm);
            lobby = new LobbyScreen(t, gm);

            // results board
            var card = UIKit.Card(t, Palette.UiAccent, new Vector2(0.5f, 0.5f), new Vector2(0, -80f), new Vector2(1000f, 520f));
            resultsRoot = card.gameObject;
            resultsTitle = UIKit.Label(card.transform, "ИТОГИ", 46, Palette.UiAccent, TextAnchor.MiddleCenter, new Vector2(0.5f, 1f), new Vector2(0, -50f), new Vector2(940f, 60f));
            resultsRows = UIKit.Rect(card.transform, "Rows", new Vector2(0.5f, 1f), new Vector2(0, -105f), new Vector2(900f, 380f), new Vector2(0.5f, 1f));
            UIKit.Label(card.transform, "ENTER / A — продолжить", 22, Palette.UiDim, TextAnchor.MiddleCenter, new Vector2(0.5f, 0f), new Vector2(0, 30f), new Vector2(900f, 40f), false, FontStyle.Normal);
            resultsRoot.SetActive(false);

            // banner
            banner = UIKit.Label(t, "", 130, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(0, 140f), new Vector2(1900f, 200f));
            banner.GetComponent<Outline>().effectDistance = new Vector2(5f, -5f);
            bannerSub = UIKit.Label(t, "", 40, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(0, 30f), new Vector2(1600f, 60f));

            // pause
            pauseRoot = UIKit.Stretch(t, "Pause").gameObject;
            UIKit.Fill(pauseRoot.transform, new Color(0.02f, 0.02f, 0.05f, 0.7f));
            UIKit.Label(pauseRoot.transform, "ПАУЗА", 110, Palette.UiAccent, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(0, 220f), new Vector2(1000f, 160f));
            pauseMenu = new MenuList(pauseRoot.transform, new Vector2(0.5f, 0.5f), new Vector2(0, 90f), 800f, 70f, 46);
            pauseMenu.Add(() => "ПРОДОЛЖИТЬ", gm.Resume);
            pauseMenu.Add(() => "ЗАНОВО", gm.RestartMatch);
            pauseMenu.Add(() => "ГРОМКОСТЬ: " + Mathf.RoundToInt(Sfx.MasterVolume * 10f), null, d =>
            {
                Sfx.MasterVolume = Mathf.Clamp01(Sfx.MasterVolume + d * 0.1f);
                Sfx.SetMusicDuck(0.4f);
            });
            pauseMenu.Add(() => "В ЛОББИ", gm.ExitToLobby);
            pauseMenu.Add(() => "В ГЛАВНОЕ МЕНЮ", gm.BackToTitle);
            pauseRoot.SetActive(false);

            flash = UIKit.Fill(t, new Color(1f, 1f, 1f, 0f));
            flash.transform.SetAsLastSibling();
        }

        public void ShowTitle() { Hide(); title.Show(true); }
        public void ShowLobby() { Hide(); lobby.Show(true); }

        public void ShowHud(IList<Participant> participants)
        {
            Hide();
            hud.root.SetActive(true);
            hud.Rebuild(participants);
        }

        public void ShowPause(bool on)
        {
            pauseRoot.SetActive(on);
            if (on) pauseMenu.Reset();
        }

        public void ShowResults(MatchConfig cfg, GameMode mode)
        {
            resultsRoot.SetActive(true);
            resultsTitle.text = mode is ClimbMode ? "ВЕРШИНА ПОКОРЕНА" : "ИТОГИ МАТЧА";
            foreach (Transform child in resultsRows) Object.Destroy(child.gameObject);

            var sorted = cfg.participants
                .OrderByDescending(p => p.wins)
                .ThenByDescending(p => p.score)
                .ThenByDescending(p => p.eliminations + p.knockouts)
                .ToList();
            bool koth = mode is KingOfTheHillMode;
            Row(-0f, Palette.UiDim, "", "Игрок", koth ? "Очки" : "Победы", "Нокауты", "Выкинул");
            for (int i = 0; i < sorted.Count; i++)
            {
                var p = sorted[i];
                Row(-(i + 1) * 44f, p.color, (i + 1) + ".", p.name,
                    koth ? Mathf.FloorToInt(p.score).ToString() : p.wins.ToString(), p.knockouts.ToString(), p.eliminations.ToString());
            }
        }

        void Row(float y, Color color, string place, string name, string a, string b, string c)
        {
            var row = UIKit.Rect(resultsRows, "Row", new Vector2(0.5f, 1f), new Vector2(0, y), new Vector2(900f, 44f), new Vector2(0.5f, 1f));
            float[] xs = { -400f, -120f, 160f, 290f, 410f };
            string[] cols = { place, name, a, b, c };
            for (int i = 0; i < cols.Length; i++)
            {
                var align = i == 1 ? TextAnchor.MiddleLeft : TextAnchor.MiddleCenter;
                UIKit.Label(row, cols[i], 30, i <= 1 ? color : Color.white, align, new Vector2(0.5f, 0.5f), new Vector2(xs[i], 0f),
                    new Vector2(i == 1 ? 400f : 130f, 44f), false, i == 1 ? FontStyle.Bold : FontStyle.Normal);
            }
        }

        void Hide()
        {
            title.Show(false);
            lobby.Show(false);
            hud.root.SetActive(false);
            pauseRoot.SetActive(false);
            resultsRoot.SetActive(false);
        }

        public void HideResults() => resultsRoot.SetActive(false);

        public void Banner(string text, string sub, Color color, float duration)
        {
            if (gm.IsAttract) return;
            banner.text = text;
            banner.color = color;
            bannerSub.text = sub ?? "";
            bannerTime = 0f;
            bannerDuration = duration;
        }

        public void Feed(string text)
        {
            if (gm.IsAttract) return;
            hud.Feed(text);
        }

        public void Flash(float alpha) => flashAlpha = Mathf.Max(flashAlpha, alpha);

        public void Tick(GameState state, MenuNav nav)
        {
            switch (state)
            {
                case GameState.Title: title.Tick(nav); break;
                case GameState.Lobby:
                    if (nav.back) { gm.BackToTitle(); return; }
                    lobby.Tick(nav);
                    break;
            }
            if (hud.root.activeSelf) hud.Tick();
            if (pauseRoot.activeSelf)
            {
                if (nav.back) gm.Resume();
                else pauseMenu.Tick(nav);
            }

            // banner pop-in / fade-out
            bannerTime += Time.unscaledDeltaTime;
            float a = bannerDuration > 0f ? Mathf.Clamp01((bannerDuration - bannerTime) / 0.3f) : 0f;
            float pop = Mathf.Clamp01(bannerTime / 0.18f);
            float scale = Mathf.Lerp(1.7f, 1f, 1f - (1f - pop) * (1f - pop)) + Mathf.Sin(bannerTime * 8f) * 0.015f;
            banner.rectTransform.localScale = Vector3.one * scale;
            var bc = banner.color; bc.a = a; banner.color = bc;
            var sc = bannerSub.color; sc.a = a; bannerSub.color = sc;
            banner.gameObject.SetActive(a > 0.001f);
            bannerSub.gameObject.SetActive(a > 0.001f);

            flashAlpha = Mathf.MoveTowards(flashAlpha, 0f, Time.unscaledDeltaTime * 3f);
            flash.color = new Color(1f, 1f, 1f, flashAlpha);
            flash.gameObject.SetActive(flashAlpha > 0.001f);
        }
    }
}
