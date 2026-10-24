using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace WobbleBrawl
{
    /// <summary>Wobbly animated logo over a live bot brawl, plus the main menu.</summary>
    public sealed class TitleScreen
    {
        public readonly GameObject root;
        readonly MenuList menu;
        readonly List<Text> letters = new List<Text>();
        readonly GameObject controls;
        readonly Text controlsText;
        bool showControls;

        public TitleScreen(Transform canvas, GameManager gm)
        {
            root = UIKit.Stretch(canvas, "Title").gameObject;
            var shade = UIKit.Panel(root.transform, new Color(0f, 0f, 0f, 0.35f), new Vector2(0f, 0.5f), new Vector2(330f, 0f), new Vector2(760f, 2000f));
            shade.name = "LeftShade";

            BuildLogo("WOBBLE", new Vector2(390f, 330f), 0);
            BuildLogo("BRAWL", new Vector2(390f, 190f), 6);
            UIKit.Label(root.transform, "ФИЗИЧЕСКИЕ ДРАКИ ЖЕЛЕЙНЫХ ЧЕЛОВЕЧКОВ", 30, Palette.UiAccent, TextAnchor.MiddleCenter,
                new Vector2(0f, 0.5f), new Vector2(390f, 95f), new Vector2(760f, 50f));

            menu = new MenuList(root.transform, new Vector2(0f, 0.5f), new Vector2(390f, 30f), 700f, 66f, 44);
            menu.Add(() => "ДРАКА", () => gm.OpenLobby(ModeKind.Brawl));
            menu.Add(() => "ЦАРЬ ГОРЫ", () => gm.OpenLobby(ModeKind.KingOfTheHill));
            menu.Add(() => "ВОСХОЖДЕНИЕ (КООП)", () => gm.OpenLobby(ModeKind.Climb));
            menu.Add(() => "УПРАВЛЕНИЕ", () => showControls = !showControls);
            menu.Add(() => "ГРОМКОСТЬ: " + Mathf.RoundToInt(Sfx.MasterVolume * 10f), null, d =>
            {
                Sfx.MasterVolume = Mathf.Clamp01(Sfx.MasterVolume + d * 0.1f);
                Sfx.SetMusicDuck(1f);
            });
            menu.Add(() => "ВЫХОД", gm.QuitGame);

            UIKit.Label(root.transform, "↑↓ / стик — выбор    ENTER / A / клик — подтвердить", 22, Palette.UiDim, TextAnchor.MiddleCenter,
                new Vector2(0f, 0f), new Vector2(390f, 50f), new Vector2(760f, 40f), false, FontStyle.Normal);

            var c = UIKit.Card(root.transform, Palette.UiAccent, new Vector2(1f, 0.5f), new Vector2(-560f, 0f), new Vector2(980f, 640f));
            controls = c.gameObject;
            controlsText = UIKit.Label(c.transform, "", 24, Color.white, TextAnchor.UpperLeft, new Vector2(0.5f, 0.5f), new Vector2(0, -10f), new Vector2(920f, 600f), false, FontStyle.Normal);
            controlsText.text = BuildControlsText(gm);
            controls.SetActive(false);
        }

        static string BuildControlsText(GameManager gm)
        {
            var sb = new System.Text.StringBuilder();
            sb.Append("<b><size=32>УПРАВЛЕНИЕ</size></b>\n\n");
            sb.Append("<color=#FFC733><b>Клавиатура + мышь</b></color>\n").Append(gm.Input.KeyboardMouse.ControlsHint).Append("\n\n");
            sb.Append("<color=#FFC733><b>Второй игрок на клавиатуре</b></color>\n").Append(gm.Input.KeyboardArrows.ControlsHint).Append("\n\n");
            sb.Append("<color=#FFC733><b>Геймпад</b></color>\n");
            sb.Append("ЛЕВЫЙ СТИК — ходьба   A — прыжок   LT/RT — руки   ПРАВЫЙ СТИК/Y — высота рук\nX — удар   B — пинок\n\n");
            sb.Append("<color=#FFC733><b>Советы</b></color>\n");
            sb.Append("• Удары по голове вырубают. Вырубленного можно поднять обеими руками и выбросить с арены.\n");
            sb.Append("• Держишь врага двумя руками — удар превращается в удар головой.\n");
            sb.Append("• Схватили тебя? Жми прыжок/удар, чтобы вырваться. Вырубили — жми прыжок, чтобы очнуться быстрее.\n");
            sb.Append("• Лазать: подними руки, схватись за край, держи прыжок — подтянешься.");
            return sb.ToString();
        }

        void BuildLogo(string word, Vector2 pos, int colorOffset)
        {
            float spacing = 108f;
            float start = -spacing * (word.Length - 1) * 0.5f;
            for (int i = 0; i < word.Length; i++)
            {
                var t = UIKit.Label(root.transform, word[i].ToString(), 150, Palette.Players[(i + colorOffset) % Palette.Players.Length],
                    TextAnchor.MiddleCenter, new Vector2(0f, 0.5f), pos + new Vector2(start + i * spacing, 0f), new Vector2(140f, 180f));
                var o = t.GetComponent<Outline>();
                o.effectDistance = new Vector2(5f, -5f);
                o.effectColor = new Color(0.08f, 0.05f, 0.12f, 1f);
                letters.Add(t);
            }
        }

        public void Show(bool on)
        {
            root.SetActive(on);
            if (on) { menu.Reset(); showControls = false; }
        }

        public void Tick(MenuNav nav)
        {
            if (showControls && nav.back) { showControls = false; nav = default; }
            menu.Tick(nav);
            controls.SetActive(showControls);

            float t = Time.unscaledTime;
            for (int i = 0; i < letters.Count; i++)
            {
                var rt = letters[i].rectTransform;
                float w = Mathf.Sin(t * 2.6f + i * 0.7f);
                rt.localRotation = Quaternion.Euler(0, 0, w * 7f);
                rt.localScale = new Vector3(1f + Mathf.Sin(t * 3.1f + i) * 0.05f, 1f - Mathf.Sin(t * 3.1f + i) * 0.05f, 1f);
                var p = rt.anchoredPosition;
                p.y = (i < 6 ? 330f : 190f) + Mathf.Sin(t * 2f + i * 0.9f) * 9f;
                rt.anchoredPosition = p;
            }
        }
    }
}
