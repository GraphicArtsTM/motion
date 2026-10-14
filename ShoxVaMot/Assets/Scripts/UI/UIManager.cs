using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using Shatranj.Core;

namespace Shatranj.UI
{
    /// <summary>Базовый экран интерфейса.</summary>
    public abstract class UIScreen
    {
        public RectTransform Root;
        public CanvasGroup Group;
        protected UIManager UI;
        protected GameRoot Game { get { return UI.Game; } }
        public bool Visible { get { return Root != null && Root.gameObject.activeSelf; } }

        public void Create(UIManager ui, RectTransform parent)
        {
            UI = ui;
            Root = UIKit.Rect(parent, GetType().Name);
            Group = Root.gameObject.AddComponent<CanvasGroup>();
            Build();
            Root.gameObject.SetActive(false);
        }

        protected abstract void Build();
        public virtual void OnShow() { }
        public virtual void OnHide() { }
        /// <summary>Аппаратная кнопка «Назад». true — обработано.</summary>
        public virtual bool OnBack() { return false; }
        public virtual void Tick() { }

        /// <summary>Типовая страница: панель, заголовок, прокручиваемое содержимое, подвал с кнопками.</summary>
        protected RectTransform Page(string title, out RectTransform content, out RectTransform footer)
        {
            var panel = UIKit.Panel(Root, "page");
            UIKit.Stretch(panel, 30, 40, 30, 50);
            var t = UIKit.Label(panel, title, 62, UIKit.Gold, TextAnchor.MiddleCenter, FontStyle.Bold, "title");
            UIKit.Shadow(t, new Color(0, 0, 0, 0.6f), 3f);
            t.rectTransform.anchorMin = new Vector2(0, 1);
            t.rectTransform.anchorMax = new Vector2(1, 1);
            t.rectTransform.pivot = new Vector2(0.5f, 1);
            t.rectTransform.offsetMin = new Vector2(40, -170);
            t.rectTransform.offsetMax = new Vector2(-40, -62);

            var sr = UIKit.Scroll(panel, out content, 18f, new RectOffset(10, 10, 10, 40));
            UIKit.Stretch((RectTransform)sr.transform, 40, 190, 40, 185);

            footer = UIKit.Rect(panel, "footer");
            footer.anchorMin = new Vector2(0, 0);
            footer.anchorMax = new Vector2(1, 0);
            footer.pivot = new Vector2(0.5f, 0);
            footer.offsetMin = new Vector2(40, 40);
            footer.offsetMax = new Vector2(-40, 160);
            var h = UIKit.HList(footer.gameObject, 24f);
            h.childForceExpandWidth = true;
            return panel;
        }
    }

    /// <summary>Управляет экранами, затемнением, баннерами и кнопкой «Назад» Android.</summary>
    public class UIManager : MonoBehaviour
    {
        public GameRoot Game;
        public Canvas Canvas;
        RectTransform safe;
        RectTransform screensRoot, overlayRoot;
        Rect lastSafe;

        public LoadingScreen Loading;
        public MainMenuScreen Main;
        public NewGameScreen NewGame;
        public SettingsScreen Settings;
        public RulesScreen Rules;
        public AboutScreen About;
        public MuseumScreen Museum;
        public StatsScreen Stats;
        public HudScreen Hud;
        public PauseScreen Pause;
        public GameOverScreen GameOver;
        public PromotionDialog Promotion;
        public ConfirmDialog Confirm;
        public Banner Banner;

        readonly List<UIScreen> all = new List<UIScreen>();
        readonly List<UIScreen> overlays = new List<UIScreen>();
        UIScreen current;

        public UIScreen Current { get { return current; } }
        public bool HasOverlay { get { return overlays.Count > 0; } }

        public static UIManager Create(GameRoot game)
        {
            var go = new GameObject("UI");
            var ui = go.AddComponent<UIManager>();
            ui.Game = game;
            ui.Build();
            return ui;
        }

        void Build()
        {
            UIKit.OnClickSound = () => Shatranj.Audio.AudioManager.Play(Shatranj.Audio.Sfx.Click, 0.7f, 0.02f);
            Canvas = UIKit.CreateCanvas("Canvas", 10);
            Canvas.transform.SetParent(transform, false);
            // мягкая виньетка поверх 3D-сцены — «киношная» глубина кадра
            var vignette = UIKit.Raw(Canvas.transform, Shatranj.Visual.TextureFactory.Vignette(), Color.white, "Vignette");
            vignette.raycastTarget = false;
            safe = UIKit.Rect(Canvas.transform, "SafeArea");
            screensRoot = UIKit.Rect(safe, "Screens");
            overlayRoot = UIKit.Rect(safe, "Overlays");

            Loading = Add(new LoadingScreen(), screensRoot);
            Main = Add(new MainMenuScreen(), screensRoot);
            NewGame = Add(new NewGameScreen(), screensRoot);
            Settings = Add(new SettingsScreen(), screensRoot);
            Rules = Add(new RulesScreen(), screensRoot);
            About = Add(new AboutScreen(), screensRoot);
            Museum = Add(new MuseumScreen(), screensRoot);
            Stats = Add(new StatsScreen(), screensRoot);
            Hud = Add(new HudScreen(), screensRoot);
            Pause = Add(new PauseScreen(), overlayRoot);
            GameOver = Add(new GameOverScreen(), overlayRoot);
            Promotion = Add(new PromotionDialog(), overlayRoot);
            Confirm = Add(new ConfirmDialog(), overlayRoot);

            var bannerRt = UIKit.Rect(safe, "Banner");
            Banner = bannerRt.gameObject.AddComponent<Banner>();
            Banner.Build();
            ApplySafeArea();
        }

        T Add<T>(T s, RectTransform parent) where T : UIScreen
        {
            s.Create(this, parent);
            all.Add(s);
            return s;
        }

        void ApplySafeArea()
        {
            Rect r = Screen.safeArea;
            if (r == lastSafe || Screen.width <= 0 || Screen.height <= 0) return;
            lastSafe = r;
            safe.anchorMin = new Vector2(r.xMin / Screen.width, r.yMin / Screen.height);
            safe.anchorMax = new Vector2(r.xMax / Screen.width, r.yMax / Screen.height);
            safe.offsetMin = safe.offsetMax = Vector2.zero;
        }

        // ------------------------------------------------------------------ Переходы

        public void Show(UIScreen s)
        {
            CloseAllOverlays();
            if (current == s && s.Visible) { s.OnShow(); return; }
            if (current != null) Hide(current);
            current = s;
            Open(s);
        }

        public void PushOverlay(UIScreen s)
        {
            if (!overlays.Contains(s)) overlays.Add(s);
            s.Root.SetAsLastSibling();
            Open(s);
        }

        public void PopOverlay(UIScreen s)
        {
            if (!overlays.Remove(s)) return;
            Hide(s);
        }

        public void CloseAllOverlays()
        {
            foreach (var o in overlays.ToArray()) PopOverlay(o);
        }

        void Open(UIScreen s)
        {
            s.Root.gameObject.SetActive(true);
            s.OnShow();
            StartCoroutine(Fade(s, true));
        }

        void Hide(UIScreen s)
        {
            if (!s.Visible) return;
            s.OnHide();
            StartCoroutine(Fade(s, false));
        }

        IEnumerator Fade(UIScreen s, bool show)
        {
            var g = s.Group;
            g.interactable = show;
            g.blocksRaycasts = show;
            float from = show ? 0f : g.alpha, to = show ? 1f : 0f;
            float s0 = show ? 0.97f : 1f, s1 = show ? 1f : 0.98f;
            for (float t = 0; t < 1f; t += Time.unscaledDeltaTime / 0.18f)
            {
                g.alpha = Mathf.Lerp(from, to, t);
                float k = Mathf.Lerp(s0, s1, t);
                s.Root.localScale = new Vector3(k, k, 1);
                yield return null;
            }
            g.alpha = to;
            s.Root.localScale = Vector3.one;
            if (!show && !(current == s || overlays.Contains(s))) s.Root.gameObject.SetActive(false);
        }

        // ------------------------------------------------------------------ Диалоги

        public void Ask(string message, Action yes, Action no = null, string yesText = null, string noText = null)
        {
            Confirm.Setup(message, yes, no, yesText, noText);
            PushOverlay(Confirm);
        }

        void Update()
        {
            ApplySafeArea();
            if (current != null) current.Tick();
            foreach (var o in overlays) o.Tick();

            if (UnityEngine.Input.GetKeyDown(KeyCode.Escape))
            {
                if (overlays.Count > 0)
                {
                    var top = overlays[overlays.Count - 1];
                    if (!top.OnBack()) PopOverlay(top);
                }
                else if (current != null) current.OnBack();
            }
        }

        /// <summary>Пересобрать интерфейс (после смены языка) и вернуть тот же экран.</summary>
        public UIManager Rebuild()
        {
            Type cur = current != null ? current.GetType() : typeof(MainMenuScreen);
            var game = Game;
            Destroy(gameObject);
            var ui = Create(game);
            foreach (var s in ui.all)
                if (s.GetType() == cur) { ui.Show(s); break; }
            return ui;
        }
    }

    /// <summary>Крупная надпись по центру: «ШАХ!», «МАТ!», «ПАХЛАВОН!», а также всплывающие подсказки.</summary>
    public class Banner : MonoBehaviour
    {
        Text big, small, toast;
        CanvasGroup bigGroup, toastGroup;
        Coroutine bigCo, toastCo;
        RectTransform bigRoot;

        public void Build()
        {
            var rt = (RectTransform)transform;
            bigRoot = UIKit.Rect(rt, "big");
            bigRoot.anchorMin = new Vector2(0, 0.5f);
            bigRoot.anchorMax = new Vector2(1, 0.5f);
            bigRoot.sizeDelta = new Vector2(0, 360);
            bigGroup = bigRoot.gameObject.AddComponent<CanvasGroup>();
            bigGroup.alpha = 0f;
            bigGroup.blocksRaycasts = false;
            var glow = UIKit.Img(bigRoot, UIKit.Round, new Color(0.02f, 0.05f, 0.14f, 0.7f), "bg");
            glow.rectTransform.offsetMin = new Vector2(60, 40);
            glow.rectTransform.offsetMax = new Vector2(-60, -40);
            var fr = UIKit.Img(bigRoot, UIKit.Frame, UIKit.Gold, "frame");
            fr.rectTransform.offsetMin = new Vector2(66, 46);
            fr.rectTransform.offsetMax = new Vector2(-66, -46);
            big = UIKit.Label(bigRoot, "", 128, UIKit.Gold, TextAnchor.MiddleCenter, FontStyle.Bold);
            big.rectTransform.offsetMin = new Vector2(80, 110);
            big.rectTransform.offsetMax = new Vector2(-80, -50);
            UIKit.Outline(big, new Color(0.25f, 0.12f, 0.02f, 1f), 4f);
            UIKit.Shadow(big, new Color(0, 0, 0, 0.6f), 6f);
            small = UIKit.Label(bigRoot, "", 40, UIKit.Ivory, TextAnchor.MiddleCenter, FontStyle.Italic);
            small.rectTransform.offsetMin = new Vector2(90, 55);
            small.rectTransform.offsetMax = new Vector2(-90, -250);

            var trt = UIKit.Rect(rt, "toast");
            trt.anchorMin = new Vector2(0.5f, 0.28f);
            trt.anchorMax = new Vector2(0.5f, 0.28f);
            trt.sizeDelta = new Vector2(860, 110);
            toastGroup = trt.gameObject.AddComponent<CanvasGroup>();
            toastGroup.alpha = 0f;
            toastGroup.blocksRaycasts = false;
            UIKit.Img(trt, UIKit.Pill, new Color(0.02f, 0.05f, 0.14f, 0.85f), "bg");
            toast = UIKit.Label(trt, "", 38, UIKit.Ivory, TextAnchor.MiddleCenter);
            toast.rectTransform.offsetMin = new Vector2(30, 0);
            toast.rectTransform.offsetMax = new Vector2(-30, 0);
        }

        public void Show(string title, string subtitle = "", Color? color = null)
        {
            big.text = title;
            big.color = color ?? UIKit.Gold;
            small.text = subtitle ?? "";
            if (bigCo != null) StopCoroutine(bigCo);
            bigCo = StartCoroutine(BigRoutine());
        }

        IEnumerator BigRoutine()
        {
            for (float t = 0; t < 1f; t += Time.unscaledDeltaTime / 0.25f)
            {
                bigGroup.alpha = t;
                float s = Mathf.Lerp(1.5f, 1f, Shatranj.Visual.Ease.OutBack(t));
                bigRoot.localScale = new Vector3(s, s, 1);
                yield return null;
            }
            bigGroup.alpha = 1f;
            bigRoot.localScale = Vector3.one;
            for (float t = 0; t < 1.1f; t += Time.unscaledDeltaTime) yield return null;
            for (float t = 0; t < 1f; t += Time.unscaledDeltaTime / 0.35f)
            {
                bigGroup.alpha = 1f - t;
                yield return null;
            }
            bigGroup.alpha = 0f;
        }

        public void Toast(string text, float seconds = 1.8f)
        {
            toast.text = text;
            if (toastCo != null) StopCoroutine(toastCo);
            toastCo = StartCoroutine(ToastRoutine(seconds));
        }

        IEnumerator ToastRoutine(float seconds)
        {
            for (float t = 0; t < 1f; t += Time.unscaledDeltaTime / 0.15f) { toastGroup.alpha = t; yield return null; }
            toastGroup.alpha = 1f;
            for (float t = 0; t < seconds; t += Time.unscaledDeltaTime) yield return null;
            for (float t = 0; t < 1f; t += Time.unscaledDeltaTime / 0.3f) { toastGroup.alpha = 1f - t; yield return null; }
            toastGroup.alpha = 0f;
        }
    }
}
