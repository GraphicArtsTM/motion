using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace WobbleBrawl
{
    /// <summary>Code-only uGUI helpers (no prefabs, no sprites).</summary>
    public static class UIKit
    {
        static Font font;

        public static Font Font
        {
            get
            {
                if (font != null) return font;
                try { font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf"); } catch { font = null; }
                if (font == null) font = Font.CreateDynamicFontFromOSFont(new[] { "Arial", "Helvetica", "DejaVu Sans", "Liberation Sans" }, 32);
                return font;
            }
        }

        public static Canvas CreateCanvas(Transform parent, string name, int order)
        {
            var go = new GameObject(name, typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var canvas = go.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = order;
            var scaler = go.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920, 1080);
            scaler.matchWidthOrHeight = 0.5f;
            return canvas;
        }

        public static RectTransform Rect(Transform parent, string name, Vector2 anchor, Vector2 pos, Vector2 size, Vector2? pivot = null)
        {
            var go = new GameObject(name, typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var rt = (RectTransform)go.transform;
            rt.anchorMin = rt.anchorMax = anchor;
            rt.pivot = pivot ?? new Vector2(0.5f, 0.5f);
            rt.anchoredPosition = pos;
            rt.sizeDelta = size;
            return rt;
        }

        public static RectTransform Stretch(Transform parent, string name)
        {
            var go = new GameObject(name, typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var rt = (RectTransform)go.transform;
            rt.anchorMin = Vector2.zero;
            rt.anchorMax = Vector2.one;
            rt.offsetMin = rt.offsetMax = Vector2.zero;
            return rt;
        }

        public static Text Label(Transform parent, string text, int size, Color color, TextAnchor align,
            Vector2 anchor, Vector2 pos, Vector2 box, bool outline = true, FontStyle style = FontStyle.Bold)
        {
            var rt = Rect(parent, "Text", anchor, pos, box);
            var t = rt.gameObject.AddComponent<Text>();
            t.font = Font;
            t.text = text;
            t.fontSize = size;
            t.fontStyle = style;
            t.color = color;
            t.alignment = align;
            t.supportRichText = true;
            t.horizontalOverflow = HorizontalWrapMode.Wrap;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            t.raycastTarget = false;
            if (outline)
            {
                var o = rt.gameObject.AddComponent<Outline>();
                o.effectColor = new Color(0f, 0f, 0f, 0.75f);
                o.effectDistance = new Vector2(2f, -2f);
                var s = rt.gameObject.AddComponent<Shadow>();
                s.effectColor = new Color(0f, 0f, 0f, 0.45f);
                s.effectDistance = new Vector2(3f, -5f);
            }
            return t;
        }

        public static Image Panel(Transform parent, Color color, Vector2 anchor, Vector2 pos, Vector2 size, Vector2? pivot = null)
        {
            var rt = Rect(parent, "Panel", anchor, pos, size, pivot);
            var img = rt.gameObject.AddComponent<Image>();
            img.color = color;
            img.raycastTarget = false;
            return img;
        }

        public static Image Fill(Transform parent, Color color)
        {
            var rt = Stretch(parent, "Fill");
            var img = rt.gameObject.AddComponent<Image>();
            img.color = color;
            img.raycastTarget = false;
            return img;
        }

        /// <summary>A panel with a coloured top strip — the look used for cards.</summary>
        public static Image Card(Transform parent, Color accent, Vector2 anchor, Vector2 pos, Vector2 size)
        {
            var bg = Panel(parent, Palette.UiPanel, anchor, pos, size);
            var strip = Panel(bg.transform, accent, new Vector2(0.5f, 1f), Vector2.zero, new Vector2(size.x, 8f), new Vector2(0.5f, 1f));
            strip.name = "Accent";
            var shadow = bg.gameObject.AddComponent<Shadow>();
            shadow.effectColor = new Color(0, 0, 0, 0.5f);
            shadow.effectDistance = new Vector2(6f, -6f);
            return bg;
        }
    }

    /// <summary>Keyboard / gamepad / mouse navigable vertical menu.</summary>
    public sealed class MenuList
    {
        public sealed class Item
        {
            public System.Func<string> label;
            public System.Action confirm;
            public System.Action<int> adjust;
            public System.Func<bool> visible;
            public Text text;
        }

        readonly List<Item> items = new List<Item>();
        readonly RectTransform root;
        readonly float rowHeight;
        readonly int fontSize;
        readonly float width;
        int selected;
        Vector2 lastMouse;

        public RectTransform Root => root;

        public MenuList(Transform parent, Vector2 anchor, Vector2 pos, float width, float rowHeight, int fontSize)
        {
            root = UIKit.Rect(parent, "Menu", anchor, pos, new Vector2(width, 10f), new Vector2(0.5f, 1f));
            this.rowHeight = rowHeight;
            this.fontSize = fontSize;
            this.width = width;
        }

        public Item Add(System.Func<string> label, System.Action confirm = null, System.Action<int> adjust = null, System.Func<bool> visible = null)
        {
            var item = new Item { label = label, confirm = confirm, adjust = adjust, visible = visible };
            item.text = UIKit.Label(root, "", fontSize, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 1f), Vector2.zero, new Vector2(width, rowHeight));
            items.Add(item);
            return item;
        }

        public void Reset() => selected = 0;

        bool Visible(Item i) => i.visible == null || i.visible();

        public void Tick(MenuNav nav)
        {
            // layout visible items
            float y = 0f;
            for (int i = 0; i < items.Count; i++)
            {
                var it = items[i];
                bool vis = Visible(it);
                it.text.gameObject.SetActive(vis);
                if (!vis) continue;
                it.text.rectTransform.anchoredPosition = new Vector2(0f, -y - rowHeight * 0.5f);
                y += rowHeight;
            }
            if (!Visible(items[selected])) Step(1);

            if (nav.up) { Step(-1); Sfx.PlayUI(Sfx.Tick, 0.5f); }
            if (nav.down) { Step(1); Sfx.PlayUI(Sfx.Tick, 0.5f); }

            // mouse hover / click
            Vector2 mouse = Kb.MousePosition;
            bool mouseMoved = (mouse - lastMouse).sqrMagnitude > 4f;
            lastMouse = mouse;
            int hovered = -1;
            if (Kb.HasMouse)
            {
                for (int i = 0; i < items.Count; i++)
                {
                    if (!items[i].text.gameObject.activeInHierarchy) continue;
                    if (RectTransformUtility.RectangleContainsScreenPoint(items[i].text.rectTransform, mouse, null))
                    {
                        hovered = i;
                        if (mouseMoved && selected != i) { selected = i; Sfx.PlayUI(Sfx.Tick, 0.4f); }
                    }
                }
            }

            var cur = items[selected];
            if (cur.adjust != null)
            {
                if (nav.left) { cur.adjust(-1); Sfx.PlayUI(Sfx.Tick, 0.6f, 0.9f); }
                if (nav.right) { cur.adjust(1); Sfx.PlayUI(Sfx.Tick, 0.6f, 1.1f); }
            }
            bool click = hovered == selected && hovered >= 0 && Kb.MouseDown(0);
            if (nav.confirm || click)
            {
                if (cur.confirm != null) { Sfx.PlayUI(Sfx.Select, 0.7f); cur.confirm(); }
                else if (cur.adjust != null) { cur.adjust(1); Sfx.PlayUI(Sfx.Tick, 0.6f, 1.1f); }
            }

            // render
            float pulse = 1f + Mathf.Sin(Time.unscaledTime * 6f) * 0.04f;
            for (int i = 0; i < items.Count; i++)
            {
                var it = items[i];
                if (!it.text.gameObject.activeSelf) continue;
                string label = it.label();
                bool sel = i == selected;
                it.text.text = sel ? (it.adjust != null ? "◀  " + label + "  ▶" : "▶ " + label + " ◀") : label;
                it.text.color = sel ? Palette.UiAccent : Palette.UiText;
                it.text.rectTransform.localScale = Vector3.one * (sel ? pulse : 1f);
            }
        }

        void Step(int dir)
        {
            for (int n = 0; n < items.Count; n++)
            {
                selected = (selected + dir + items.Count) % items.Count;
                if (Visible(items[selected])) return;
            }
        }
    }
}
