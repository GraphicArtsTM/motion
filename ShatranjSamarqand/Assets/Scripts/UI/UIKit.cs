using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using Shatranj.Visual;

namespace Shatranj.UI
{
    public enum BtnStyle { Primary, Secondary, Danger, Ghost }

    /// <summary>
    /// Конструктор интерфейса из кода (uGUI): цвета ляписа, золота и бирюзы,
    /// скруглённые панели с двойной золотой рамкой, ленты ислими, восьмиконечные звёзды.
    /// </summary>
    public static class UIKit
    {
        public static readonly Color Lapis = TextureFactory.Hex("#1B3D7A");
        public static readonly Color Deep = TextureFactory.Hex("#0B1A38");
        public static readonly Color Turq = TextureFactory.Hex("#2BB3B1");
        public static readonly Color Gold = TextureFactory.Hex("#E2B04A");
        public static readonly Color GoldDark = TextureFactory.Hex("#9C7224");
        public static readonly Color Ivory = TextureFactory.Hex("#F6ECD6");
        public static readonly Color Terra = TextureFactory.Hex("#B4483A");
        public static readonly Color Ink = TextureFactory.Hex("#24170A");
        public static readonly Color Dim = new Color(0.02f, 0.04f, 0.1f, 0.55f);

        static Font font;
        static Sprite round, frame, circle, star, starOutline, pill;
        static Texture2D ornament;
        public static Action OnClickSound;

        public static Font DefaultFont
        {
            get
            {
                if (font != null) return font;
                try { font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf"); } catch (Exception) { font = null; }
                if (font == null)
                {
                    try { font = Resources.GetBuiltinResource<Font>("Arial.ttf"); } catch (Exception) { font = null; }
                }
                if (font == null) font = Font.CreateDynamicFontFromOSFont(new[] { "Roboto", "Arial", "Noto Sans" }, 32);
                return font;
            }
        }

        static Sprite MakeSprite(Texture2D t, float border)
        {
            return Sprite.Create(t, new Rect(0, 0, t.width, t.height), new Vector2(0.5f, 0.5f), 100f, 0, SpriteMeshType.FullRect, new Vector4(border, border, border, border));
        }

        public static Sprite Round { get { return round != null ? round : (round = MakeSprite(TextureFactory.RoundedRect(96, 34f), 40f)); } }
        public static Sprite Frame { get { return frame != null ? frame : (frame = MakeSprite(TextureFactory.RoundedRect(96, 34f, 3f, 9f), 40f)); } }
        public static Sprite Circle { get { return circle != null ? circle : (circle = MakeSprite(TextureFactory.Circle(128), 0f)); } }
        public static Sprite Pill { get { return pill != null ? pill : (pill = MakeSprite(TextureFactory.RoundedRect(64, 31f), 31f)); } }
        public static Sprite Star { get { return star != null ? star : (star = MakeSprite(TextureFactory.Star8(256), 0f)); } }
        public static Sprite StarOutline { get { return starOutline != null ? starOutline : (starOutline = MakeSprite(TextureFactory.Star8(256, 0.035f), 0f)); } }
        public static Texture2D Ornament { get { return ornament != null ? ornament : (ornament = TextureFactory.Islimi("ui", Lapis, Gold, Turq)); } }

        // ------------------------------------------------------------------ Холст

        public static Canvas CreateCanvas(string name, int order)
        {
            var go = new GameObject(name, typeof(RectTransform));
            var canvas = go.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = order;
            var scaler = go.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1080, 1920);
            scaler.screenMatchMode = CanvasScaler.ScreenMatchMode.MatchWidthOrHeight;
            scaler.matchWidthOrHeight = 0f;
            go.AddComponent<GraphicRaycaster>();

            if (UnityEngine.Object.FindObjectOfType<EventSystem>() == null)
            {
                var es = new GameObject("EventSystem");
                es.AddComponent<EventSystem>();
                es.AddComponent<StandaloneInputModule>();
            }
            return canvas;
        }

        // ------------------------------------------------------------------ Базовые элементы

        public static RectTransform Rect(Transform parent, string name)
        {
            var go = new GameObject(name, typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var rt = (RectTransform)go.transform;
            Stretch(rt);
            return rt;
        }

        public static RectTransform Stretch(RectTransform rt, float l = 0, float b = 0, float r = 0, float t = 0)
        {
            rt.anchorMin = Vector2.zero;
            rt.anchorMax = Vector2.one;
            rt.offsetMin = new Vector2(l, b);
            rt.offsetMax = new Vector2(-r, -t);
            return rt;
        }

        /// <summary>Привязка к точке (anchor) с размером и смещением.</summary>
        public static RectTransform Place(RectTransform rt, Vector2 anchor, Vector2 pivot, Vector2 pos, Vector2 size)
        {
            rt.anchorMin = rt.anchorMax = anchor;
            rt.pivot = pivot;
            rt.anchoredPosition = pos;
            rt.sizeDelta = size;
            return rt;
        }

        public static Image Img(Transform parent, Sprite s, Color c, string name = "img")
        {
            var rt = Rect(parent, name);
            var img = rt.gameObject.AddComponent<Image>();
            img.sprite = s;
            img.color = c;
            if (s != null && s.border.sqrMagnitude > 0) img.type = Image.Type.Sliced;
            img.raycastTarget = false;
            return img;
        }

        public static RawImage Raw(Transform parent, Texture t, Color c, string name = "raw")
        {
            var rt = Rect(parent, name);
            var img = rt.gameObject.AddComponent<RawImage>();
            img.texture = t;
            img.color = c;
            img.raycastTarget = false;
            return img;
        }

        public static Text Label(Transform parent, string text, int size, Color color, TextAnchor anchor = TextAnchor.MiddleCenter, FontStyle style = FontStyle.Normal, string name = "text")
        {
            var rt = Rect(parent, name);
            var t = rt.gameObject.AddComponent<Text>();
            t.font = DefaultFont;
            t.text = text;
            t.fontSize = size;
            t.color = color;
            t.alignment = anchor;
            t.fontStyle = style;
            t.horizontalOverflow = HorizontalWrapMode.Wrap;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            t.raycastTarget = false;
            t.supportRichText = true;
            return t;
        }

        public static void Shadow(Graphic g, Color c, float dist = 3f)
        {
            var s = g.gameObject.AddComponent<Shadow>();
            s.effectColor = c;
            s.effectDistance = new Vector2(dist, -dist);
        }

        public static void Outline(Graphic g, Color c, float dist = 2f)
        {
            var o = g.gameObject.AddComponent<Outline>();
            o.effectColor = c;
            o.effectDistance = new Vector2(dist, -dist);
        }

        public static LayoutElement Layout(Component c, float prefH = -1, float prefW = -1, float flexW = -1, float flexH = -1)
        {
            var le = c.GetComponent<LayoutElement>();
            if (le == null) le = c.gameObject.AddComponent<LayoutElement>();
            if (prefH >= 0) { le.preferredHeight = prefH; le.minHeight = prefH; }
            if (prefW >= 0) { le.preferredWidth = prefW; le.minWidth = prefW; }
            if (flexW >= 0) le.flexibleWidth = flexW;
            if (flexH >= 0) le.flexibleHeight = flexH;
            return le;
        }

        public static VerticalLayoutGroup VList(GameObject go, float spacing, RectOffset pad = null, TextAnchor align = TextAnchor.UpperCenter)
        {
            var v = go.AddComponent<VerticalLayoutGroup>();
            v.spacing = spacing;
            v.padding = pad ?? new RectOffset(0, 0, 0, 0);
            v.childAlignment = align;
            v.childControlHeight = true;
            v.childControlWidth = true;
            v.childForceExpandHeight = false;
            v.childForceExpandWidth = true;
            return v;
        }

        public static HorizontalLayoutGroup HList(GameObject go, float spacing, RectOffset pad = null, TextAnchor align = TextAnchor.MiddleCenter)
        {
            var h = go.AddComponent<HorizontalLayoutGroup>();
            h.spacing = spacing;
            h.padding = pad ?? new RectOffset(0, 0, 0, 0);
            h.childAlignment = align;
            h.childControlHeight = true;
            h.childControlWidth = true;
            h.childForceExpandHeight = true;
            h.childForceExpandWidth = false;
            return h;
        }

        // ------------------------------------------------------------------ Панели

        /// <summary>Панель: тёмный ляпис, двойная золотая рамка и лента ислими сверху.</summary>
        public static RectTransform Panel(Transform parent, string name, bool ornamentStrip = true, float alpha = 0.95f)
        {
            var rt = Rect(parent, name);
            var bg = rt.gameObject.AddComponent<Image>();
            bg.sprite = Round;
            bg.type = Image.Type.Sliced;
            bg.color = new Color(Deep.r, Deep.g, Deep.b, alpha);
            bg.raycastTarget = true;
            if (ornamentStrip)
            {
                var strip = Raw(rt, Ornament, Color.white, "ornament");
                strip.rectTransform.anchorMin = new Vector2(0, 1);
                strip.rectTransform.anchorMax = new Vector2(1, 1);
                strip.rectTransform.pivot = new Vector2(0.5f, 1);
                strip.rectTransform.offsetMin = new Vector2(30, -54);
                strip.rectTransform.offsetMax = new Vector2(-30, -18);
                strip.uvRect = new Rect(0, 0, 6f, 1f);
            }
            var fr = Img(rt, Frame, Gold, "frame");
            fr.rectTransform.offsetMin = new Vector2(6, 6);
            fr.rectTransform.offsetMax = new Vector2(-6, -6);
            return rt;
        }

        public static Image Dimmer(Transform parent)
        {
            var img = Img(parent, null, Dim, "dim");
            img.raycastTarget = true;
            return img;
        }

        // ------------------------------------------------------------------ Кнопки

        public static Button Btn(Transform parent, string text, Action onClick, BtnStyle style = BtnStyle.Secondary, float height = 118f, int fontSize = 44)
        {
            var rt = Rect(parent, "btn_" + text);
            var img = rt.gameObject.AddComponent<Image>();
            img.sprite = Round;
            img.type = Image.Type.Sliced;
            Color fill, txt, border;
            switch (style)
            {
                case BtnStyle.Primary: fill = Gold; txt = Ink; border = TextureFactory.Hex("#FFE9A8"); break;
                case BtnStyle.Danger: fill = Terra; txt = Ivory; border = Gold; break;
                case BtnStyle.Ghost: fill = new Color(1, 1, 1, 0.06f); txt = Ivory; border = new Color(Gold.r, Gold.g, Gold.b, 0.6f); break;
                default: fill = new Color(Lapis.r, Lapis.g, Lapis.b, 0.95f); txt = Ivory; border = Gold; break;
            }
            img.color = fill;
            var b = rt.gameObject.AddComponent<Button>();
            var colors = b.colors;
            colors.normalColor = Color.white;
            colors.highlightedColor = new Color(1.08f, 1.08f, 1.08f, 1f);
            colors.pressedColor = new Color(0.78f, 0.78f, 0.78f, 1f);
            colors.disabledColor = new Color(0.55f, 0.55f, 0.55f, 0.6f);
            colors.fadeDuration = 0.08f;
            b.colors = colors;
            b.targetGraphic = img;
            var fr = Img(rt, Frame, border, "frame");
            fr.rectTransform.offsetMin = new Vector2(4, 4);
            fr.rectTransform.offsetMax = new Vector2(-4, -4);
            var label = Label(rt, text, fontSize, txt, TextAnchor.MiddleCenter, FontStyle.Bold, "label");
            label.rectTransform.offsetMin = new Vector2(24, 4);
            label.rectTransform.offsetMax = new Vector2(-24, -4);
            if (style != BtnStyle.Primary) Shadow(label, new Color(0, 0, 0, 0.5f), 2f);
            b.onClick.AddListener(() =>
            {
                if (OnClickSound != null) OnClickSound();
                if (onClick != null) onClick();
            });
            rt.gameObject.AddComponent<PressScale>();
            if (height > 0) Layout(b, height);
            return b;
        }

        public static Text BtnLabel(Button b) { return b.transform.Find("label").GetComponent<Text>(); }

        // ------------------------------------------------------------------ Строки настроек

        /// <summary>Строка «название — ‹ значение ›». Нажатие по значению листает варианты.</summary>
        public static Text OptionRow(Transform parent, string label, string[] options, int index, Action<int> onChange, float height = 112f)
        {
            var row = Rect(parent, "row_" + label);
            var bg = row.gameObject.AddComponent<Image>();
            bg.sprite = Round;
            bg.type = Image.Type.Sliced;
            bg.color = new Color(1, 1, 1, 0.05f);
            Layout(bg, height);

            var l = Label(row, label, 38, Ivory, TextAnchor.MiddleLeft);
            l.rectTransform.anchorMax = new Vector2(0.48f, 1);
            l.rectTransform.offsetMin = new Vector2(32, 0);

            int cur = Mathf.Clamp(index, 0, options.Length - 1);
            var valueArea = Rect(row, "value");
            valueArea.anchorMin = new Vector2(0.48f, 0);
            valueArea.offsetMin = new Vector2(0, 14);
            valueArea.offsetMax = new Vector2(-16, -14);
            var pill = valueArea.gameObject.AddComponent<Image>();
            pill.sprite = Pill;
            pill.type = Image.Type.Sliced;
            pill.color = new Color(Lapis.r, Lapis.g, Lapis.b, 0.95f);
            var value = Label(valueArea, options[cur], 36, Gold, TextAnchor.MiddleCenter, FontStyle.Bold);
            value.rectTransform.offsetMin = new Vector2(70, 0);
            value.rectTransform.offsetMax = new Vector2(-70, 0);
            var left = Label(valueArea, "‹", 60, Ivory);
            left.rectTransform.anchorMax = new Vector2(0, 1);
            left.rectTransform.offsetMax = new Vector2(70, 0);
            var right = Label(valueArea, "›", 60, Ivory);
            right.rectTransform.anchorMin = new Vector2(1, 0);
            right.rectTransform.offsetMin = new Vector2(-70, 0);

            var b = valueArea.gameObject.AddComponent<Button>();
            b.targetGraphic = pill;
            valueArea.gameObject.AddComponent<PressScale>();
            var handler = valueArea.gameObject.AddComponent<OptionClick>();
            handler.Init(valueArea, (dir) =>
            {
                cur = (cur + dir + options.Length) % options.Length;
                value.text = options[cur];
                if (OnClickSound != null) OnClickSound();
                if (onChange != null) onChange(cur);
            });
            return value;
        }

        public static Slider SliderRow(Transform parent, string label, float value, Action<float> onChange, float height = 112f)
        {
            var row = Rect(parent, "row_" + label);
            var bg = row.gameObject.AddComponent<Image>();
            bg.sprite = Round;
            bg.type = Image.Type.Sliced;
            bg.color = new Color(1, 1, 1, 0.05f);
            Layout(bg, height);

            var l = Label(row, label, 38, Ivory, TextAnchor.MiddleLeft);
            l.rectTransform.anchorMax = new Vector2(0.42f, 1);
            l.rectTransform.offsetMin = new Vector2(32, 0);

            var area = Rect(row, "slider");
            area.anchorMin = new Vector2(0.45f, 0.5f);
            area.anchorMax = new Vector2(1f, 0.5f);
            area.offsetMin = new Vector2(10, -22);
            area.offsetMax = new Vector2(-40, 22);
            var s = area.gameObject.AddComponent<Slider>();

            var track = Img(area, Pill, new Color(0, 0, 0, 0.45f), "track");
            track.rectTransform.offsetMin = new Vector2(0, 8);
            track.rectTransform.offsetMax = new Vector2(0, -8);

            var fillArea = Rect(area, "fillArea");
            fillArea.offsetMin = new Vector2(0, 8);
            fillArea.offsetMax = new Vector2(-20, -8);
            var fill = Img(fillArea, Pill, Turq, "fill");
            fill.rectTransform.sizeDelta = new Vector2(20, 0);

            var handleArea = Rect(area, "handleArea");
            handleArea.offsetMin = new Vector2(22, 0);
            handleArea.offsetMax = new Vector2(-22, 0);
            var handle = Img(handleArea, Circle, Gold, "handle");
            handle.rectTransform.sizeDelta = new Vector2(64, 20);
            handle.raycastTarget = true;

            s.fillRect = fill.rectTransform;
            s.handleRect = handle.rectTransform;
            s.targetGraphic = handle;
            s.direction = Slider.Direction.LeftToRight;
            s.minValue = 0f;
            s.maxValue = 1f;
            s.value = value;
            track.raycastTarget = true;
            s.onValueChanged.AddListener(v => { if (onChange != null) onChange(v); });
            return s;
        }

        public static InputField InputRow(Transform parent, string label, string value, string placeholder, Action<string> onChange, float height = 112f)
        {
            var row = Rect(parent, "input_" + label);
            var bg = row.gameObject.AddComponent<Image>();
            bg.sprite = Round;
            bg.type = Image.Type.Sliced;
            bg.color = new Color(1, 1, 1, 0.05f);
            Layout(bg, height);

            var l = Label(row, label, 38, Ivory, TextAnchor.MiddleLeft);
            l.rectTransform.anchorMax = new Vector2(0.42f, 1);
            l.rectTransform.offsetMin = new Vector2(32, 0);

            var field = Rect(row, "field");
            field.anchorMin = new Vector2(0.42f, 0);
            field.offsetMin = new Vector2(0, 14);
            field.offsetMax = new Vector2(-16, -14);
            var fbg = field.gameObject.AddComponent<Image>();
            fbg.sprite = Pill;
            fbg.type = Image.Type.Sliced;
            fbg.color = new Color(0, 0, 0, 0.35f);
            var input = field.gameObject.AddComponent<InputField>();
            var text = Label(field, "", 38, Ivory, TextAnchor.MiddleLeft);
            text.supportRichText = false;
            text.rectTransform.offsetMin = new Vector2(30, 0);
            text.rectTransform.offsetMax = new Vector2(-30, 0);
            var ph = Label(field, placeholder, 36, new Color(1, 1, 1, 0.35f), TextAnchor.MiddleLeft, FontStyle.Italic);
            ph.rectTransform.offsetMin = new Vector2(30, 0);
            ph.rectTransform.offsetMax = new Vector2(-30, 0);
            input.textComponent = text;
            input.placeholder = ph;
            input.targetGraphic = fbg;
            input.characterLimit = 16;
            input.lineType = InputField.LineType.SingleLine;
            input.text = value ?? "";
            input.onEndEdit.AddListener(v => { if (onChange != null) onChange(v); });
            return input;
        }

        public static ScrollRect Scroll(Transform parent, out RectTransform content, float spacing = 20f, RectOffset pad = null)
        {
            var rt = Rect(parent, "scroll");
            var sr = rt.gameObject.AddComponent<ScrollRect>();
            var viewport = Rect(rt, "viewport");
            viewport.gameObject.AddComponent<RectMask2D>();
            var vimg = viewport.gameObject.AddComponent<Image>();
            vimg.color = new Color(0, 0, 0, 0.001f);
            content = new GameObject("content", typeof(RectTransform)).GetComponent<RectTransform>();
            content.SetParent(viewport, false);
            content.anchorMin = new Vector2(0, 1);
            content.anchorMax = new Vector2(1, 1);
            content.pivot = new Vector2(0.5f, 1);
            content.offsetMin = Vector2.zero;
            content.offsetMax = Vector2.zero;
            VList(content.gameObject, spacing, pad ?? new RectOffset(0, 0, 10, 40));
            var fitter = content.gameObject.AddComponent<ContentSizeFitter>();
            fitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            sr.content = content;
            sr.viewport = viewport;
            sr.horizontal = false;
            sr.vertical = true;
            sr.movementType = ScrollRect.MovementType.Elastic;
            sr.scrollSensitivity = 40f;
            sr.inertia = true;
            return sr;
        }

        public static Text Heading(Transform parent, string text, int size = 54)
        {
            var t = Label(parent, text, size, Gold, TextAnchor.MiddleCenter, FontStyle.Bold);
            Shadow(t, new Color(0, 0, 0, 0.6f), 3f);
            Layout(t, size * 1.6f);
            return t;
        }

        public static Text Paragraph(Transform parent, string text, int size = 36, TextAnchor anchor = TextAnchor.UpperLeft)
        {
            var t = Label(parent, text, size, Ivory, anchor);
            t.lineSpacing = 1.12f;
            return t;
        }

        /// <summary>Эмблема: двойная восьмиконечная звезда.</summary>
        public static RectTransform Emblem(Transform parent, float size)
        {
            var rt = Rect(parent, "emblem");
            var a = Img(rt, Star, Gold, "starGold");
            var b = Img(rt, Star, Lapis, "starInner");
            b.rectTransform.offsetMin = new Vector2(size * 0.09f, size * 0.09f);
            b.rectTransform.offsetMax = new Vector2(-size * 0.09f, -size * 0.09f);
            var c = Img(rt, StarOutline, Turq, "starLine");
            c.rectTransform.offsetMin = new Vector2(size * 0.16f, size * 0.16f);
            c.rectTransform.offsetMax = new Vector2(-size * 0.16f, -size * 0.16f);
            var d = Img(rt, Circle, Gold, "dot");
            d.rectTransform.offsetMin = new Vector2(size * 0.42f, size * 0.42f);
            d.rectTransform.offsetMax = new Vector2(-size * 0.42f, -size * 0.42f);
            return rt;
        }

        public static List<T> FindAll<T>(Transform root) where T : Component
        {
            return new List<T>(root.GetComponentsInChildren<T>(true));
        }
    }

    /// <summary>Лёгкое «нажатие» кнопки — масштаб 0.96.</summary>
    public class PressScale : MonoBehaviour, IPointerDownHandler, IPointerUpHandler, IPointerExitHandler
    {
        float target = 1f;
        public void OnPointerDown(PointerEventData e) { target = 0.95f; }
        public void OnPointerUp(PointerEventData e) { target = 1f; }
        public void OnPointerExit(PointerEventData e) { target = 1f; }
        void Update()
        {
            float s = Mathf.Lerp(transform.localScale.x, target, 1f - Mathf.Exp(-Time.unscaledDeltaTime * 25f));
            transform.localScale = new Vector3(s, s, 1f);
        }
    }

    /// <summary>Клик по левой трети значения — назад, иначе — вперёд.</summary>
    public class OptionClick : MonoBehaviour, IPointerClickHandler
    {
        RectTransform area;
        Action<int> onStep;
        public void Init(RectTransform a, Action<int> step) { area = a; onStep = step; }
        public void OnPointerClick(PointerEventData e)
        {
            Vector2 local;
            RectTransformUtility.ScreenPointToLocalPointInRectangle(area, e.position, e.pressEventCamera, out local);
            int dir = local.x < area.rect.xMin + area.rect.width * 0.3f ? -1 : 1;
            if (onStep != null) onStep(dir);
        }
    }

    /// <summary>Плавно вращает элемент (эмблема).</summary>
    public class Spin : MonoBehaviour
    {
        public float Speed = 8f;
        void Update() { transform.Rotate(0, 0, Speed * Time.unscaledDeltaTime); }
    }
}
