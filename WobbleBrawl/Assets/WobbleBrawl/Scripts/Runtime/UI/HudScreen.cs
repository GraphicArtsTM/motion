using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace WobbleBrawl
{
    /// <summary>In-match HUD: fighter cards, timer, floating name tags, kill feed, hints.</summary>
    public sealed class HudScreen
    {
        sealed class Card
        {
            public Participant p;
            public Image bg, accent, bar, barBg;
            public Text name, score, status;
            public Text tag;
        }

        public readonly GameObject root;
        readonly GameManager gm;
        readonly Text center, hint;
        readonly RectTransform cardRow, tagLayer;
        readonly List<Card> cards = new List<Card>();
        readonly List<Text> feed = new List<Text>();
        readonly List<float> feedTime = new List<float>();
        float hintTimer;

        public HudScreen(Transform canvas, GameManager gm)
        {
            this.gm = gm;
            root = UIKit.Stretch(canvas, "HUD").gameObject;
            tagLayer = UIKit.Stretch(root.transform, "Tags");
            cardRow = UIKit.Rect(root.transform, "Cards", new Vector2(0.5f, 1f), new Vector2(0, -20f), new Vector2(1800f, 110f), new Vector2(0.5f, 1f));
            center = UIKit.Label(root.transform, "", 34, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 1f), new Vector2(0, -160f), new Vector2(1200f, 50f));
            hint = UIKit.Label(root.transform, "", 24, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0f), new Vector2(0, 70f), new Vector2(1700f, 90f), true, FontStyle.Normal);
            for (int i = 0; i < 6; i++)
            {
                var t = UIKit.Label(root.transform, "", 26, Color.white, TextAnchor.MiddleRight, new Vector2(1f, 1f), new Vector2(-280f, -220f - i * 40f), new Vector2(520f, 40f));
                feed.Add(t);
                feedTime.Add(-100f);
            }
        }

        public void Rebuild(IList<Participant> participants)
        {
            foreach (var c in cards)
            {
                Object.Destroy(c.bg.gameObject);
                Object.Destroy(c.tag.gameObject);
            }
            cards.Clear();
            int n = participants.Count;
            float w = Mathf.Min(270f, 1780f / Mathf.Max(1, n) - 14f);
            for (int i = 0; i < n; i++)
            {
                var p = participants[i];
                var c = new Card { p = p };
                float x = (i - (n - 1) * 0.5f) * (w + 14f);
                c.bg = UIKit.Card(cardRow, p.color, new Vector2(0.5f, 1f), new Vector2(x, -50f), new Vector2(w, 96f));
                c.accent = c.bg.transform.Find("Accent").GetComponent<Image>();
                c.name = UIKit.Label(c.bg.transform, p.name, 28, p.color, TextAnchor.MiddleLeft, new Vector2(0.5f, 1f), new Vector2(0, -30f), new Vector2(w - 24f, 40f));
                c.score = UIKit.Label(c.bg.transform, "", 26, Palette.UiAccent, TextAnchor.MiddleRight, new Vector2(0.5f, 1f), new Vector2(0, -30f), new Vector2(w - 24f, 40f));
                c.barBg = UIKit.Panel(c.bg.transform, new Color(0, 0, 0, 0.5f), new Vector2(0.5f, 0f), new Vector2(0, 22f), new Vector2(w - 24f, 12f));
                c.bar = UIKit.Panel(c.barBg.transform, p.color, new Vector2(0f, 0.5f), Vector2.zero, new Vector2(w - 24f, 12f), new Vector2(0f, 0.5f));
                c.status = UIKit.Label(c.bg.transform, "", 22, Color.white, TextAnchor.MiddleLeft, new Vector2(0.5f, 0f), new Vector2(0, 50f), new Vector2(w - 24f, 30f), true, FontStyle.Normal);
                c.tag = UIKit.Label(tagLayer, p.name, 24, p.color, TextAnchor.LowerCenter, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(300f, 60f));
                cards.Add(c);
            }
            hintTimer = 12f;
            for (int i = 0; i < feed.Count; i++) { feed[i].text = ""; feedTime[i] = -100f; }
        }

        public void Feed(string text)
        {
            // shift down, newest on top
            for (int i = feed.Count - 1; i > 0; i--)
            {
                feed[i].text = feed[i - 1].text;
                feedTime[i] = feedTime[i - 1];
            }
            feed[0].text = text;
            feedTime[0] = Time.unscaledTime;
        }

        public void Tick()
        {
            var mode = gm.Mode;
            center.text = mode != null ? mode.HudCenter() : "";

            // hints: mode-specific (climb) or controls for the first seconds of a match
            hintTimer -= Time.unscaledDeltaTime;
            string h = mode?.Hint;
            if (string.IsNullOrEmpty(h) && hintTimer > 0f)
            {
                foreach (var p in gm.Config.participants)
                    if (!p.isBot) { h = p.slot.ControlsHint; break; }
            }
            hint.text = h ?? "";
            hint.color = new Color(1f, 1f, 1f, mode?.Hint != null ? 0.95f : Mathf.Clamp01(hintTimer / 2f));

            var cam = gm.MainCamera;
            foreach (var c in cards)
            {
                var b = c.p.brawler;
                c.score.text = mode != null ? mode.HudScore(c.p) : "";
                float prog = mode != null ? mode.HudProgress(c.p) : -1f;
                float fill = prog >= 0f ? prog : b != null ? b.Consciousness01 : 0f;
                var size = c.bar.rectTransform.sizeDelta;
                size.x = c.barBg.rectTransform.sizeDelta.x * Mathf.Clamp01(fill);
                c.bar.rectTransform.sizeDelta = size;
                c.bar.color = prog >= 0f ? c.p.color : Color.Lerp(Palette.UiDanger, c.p.color, fill);

                string status = "";
                if (b == null || b.IsOut) status = "<color=#FF5A4D>ВЫБЫЛ</color>";
                else if (b.IsKnockedOut) status = "<color=#FFC733>НОКАУТ " + b.KnockoutTimeLeft.ToString("0.0") + "</color>";
                else if (b.IsHeldByOthers) status = "схвачен!";
                else if (b.IsCarrying) status = "тащит";
                c.status.text = status;
                c.bg.color = b == null || b.IsOut ? new Color(0.1f, 0.08f, 0.12f, 0.6f) : Palette.UiPanel;

                // floating name tag
                bool show = b != null && !b.IsOut && cam != null;
                c.tag.gameObject.SetActive(show);
                if (show)
                {
                    Vector3 sp = cam.WorldToScreenPoint(b.HeadVisualPosition + Vector3.up * 0.55f);
                    bool behind = sp.z < 0f;
                    sp.x = Mathf.Clamp(sp.x, 40f, Screen.width - 40f);
                    sp.y = Mathf.Clamp(behind ? 40f : sp.y, 40f, Screen.height - 140f);
                    RectTransformUtility.ScreenPointToLocalPointInRectangle(tagLayer, sp, null, out var local);
                    c.tag.rectTransform.anchoredPosition = local + new Vector2(0, 20f);
                    string label = c.p.name;
                    if (b.IsKnockedOut) label += "\n<size=20>Zzz…</size>";
                    c.tag.text = label + "\n<size=18>▼</size>";
                }
            }

            for (int i = 0; i < feed.Count; i++)
            {
                float age = Time.unscaledTime - feedTime[i];
                var col = feed[i].color;
                col.a = Mathf.Clamp01(1f - (age - 4f) / 1.5f);
                feed[i].color = col;
            }
        }
    }
}
