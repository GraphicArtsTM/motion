using System.Collections.Generic;
using PushPals.Input;
using PushPals.Save;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Настройки для ПК (Этап 17.4), вкладки: Экран (разрешение, режим окна, кадры, V-Sync, качество, размер интерфейса),
    /// Звук (общая, музыка, звуки, голосовой чат, микрофон), Управление (переназначение клавиатуры и геймпада, сброс,
    /// чувствительность мыши), Доступность (простое управление, тряска, метки игроков, субтитры), Игра (язык, HUD).
    /// Всё применяется сразу и сохраняется само. Открывается из главного меню (линейка) и из паузы.
    /// </summary>
    public class SettingsScreen : UiScreen
    {
        // «Ping» (метка «сюда») в наборе есть, но в игре ещё ничего не делает — переназначать нечего, не показываем
        private static readonly string[] ActionsToBind =
            { "Jump", "GrabLeft", "GrabRight", "Headbutt", "SwitchMatch", "Relax", "Stiffen", "Emote", "PushToTalk", "VoteRestart", "Menu" };

        private readonly List<Vector2Int> resolutions = new List<Vector2Int>();
        private RectTransform controlsPage;
        private float pendingScale = -1f, scaleClock;
        private int startTab;

        public static SettingsScreen Open() => Create<SettingsScreen>("Settings Screen", true, true, UiPanel.Motion.Drawer);

        protected override void Build()
        {
            var area = Paper(new Vector2(1560f, 930f), "settings.title");
            var pages = Tabs(area, new[] { "settings.tab.video", "settings.tab.sound", "settings.tab.controls", "settings.tab.access", "settings.tab.game" }, 270f);
            BuildVideo(new UiForm(pages[0]));
            BuildSound(new UiForm(pages[1]));
            controlsPage = pages[2];
            BuildControls();
            BuildAccess(new UiForm(pages[3]));
            BuildGame(new UiForm(pages[4]));
            BackButton(Rect, new Vector2(0.5f, 0f), new Vector2(0f, 40f));
            if (startTab > 0) area.GetComponent<UiTabs>().Select(startTab, false);
            startTab = 0;
        }

        private static void Save() => SaveSystem.Save();

        private static string Percent(float v) => Mathf.RoundToInt(v * 100f) + " %";

        // ---------- Экран ----------

        private void BuildVideo(UiForm f)
        {
            foreach (var r in Screen.resolutions)
            {
                var v = new Vector2Int(r.width, r.height);
                if (!resolutions.Contains(v)) resolutions.Add(v);
            }
            if (resolutions.Count == 0) resolutions.Add(new Vector2Int(Screen.width, Screen.height));
            resolutions.Sort((a, b) => (b.x * b.y).CompareTo(a.x * a.y));
            var current = new Vector2Int(VideoSettings.Width > 0 ? VideoSettings.Width : Screen.width, VideoSettings.Height > 0 ? VideoSettings.Height : Screen.height);
            int res = Mathf.Max(0, resolutions.IndexOf(current));
            var resNames = new List<string>();
            foreach (var r in resolutions) resNames.Add(r.x + " × " + r.y);
            bool editor = Application.isEditor;
            var resChoice = f.Choice("settings.resolution", resNames, res, i => SaveSystem.SetScreen(VideoSettings.Window, resolutions[i].x, resolutions[i].y));
            var modes = new[] { Loc.T("settings.window.full"), Loc.T("settings.window.borderless"), Loc.T("settings.window.windowed") };
            var modeChoice = f.Choice("settings.window", modes, (int)VideoSettings.Window, i =>
            {
                var r = resolutions[Mathf.Clamp(resChoice.value, 0, resolutions.Count - 1)];
                SaveSystem.SetScreen((VideoSettings.WindowMode)i, r.x, r.y);
            });
            if (editor) // в редакторе окном игры управляет Unity
            {
                resChoice.interactable = modeChoice.interactable = false;
                f.Note("settings.window.editor");
            }
            var caps = new List<string>();
            foreach (int c in VideoSettings.FpsCaps) caps.Add(c > 0 ? c.ToString() : Loc.T("settings.fps.unlimited"));
            var capChoice = f.Choice("settings.fps", caps, VideoSettings.FpsCap, i => { VideoSettings.ApplyFrames(VideoSettings.VSync, i); Save(); });
            capChoice.interactable = !VideoSettings.VSync;
            f.Toggle("settings.vsync", VideoSettings.VSync, v =>
            {
                VideoSettings.ApplyFrames(v, VideoSettings.FpsCap);
                capChoice.interactable = !v; // с синхронизацией ограничение не нужно
                Save();
            });
            var q = new[] { Loc.T("settings.quality.low"), Loc.T("settings.quality.medium"), Loc.T("settings.quality.high") };
            f.Choice("settings.quality", q, (int)VideoSettings.Effects, i => { VideoSettings.ApplyEffects((VideoSettings.Quality)i); Save(); });
            // Размер интерфейса — применяется, когда ползунок отпустили (иначе всё «плывёт» под мышью)
            f.Slider("settings.ui_scale", UiSettings.MinScale, UiSettings.MaxScale, UiSettings.Scale, false,
                v => { pendingScale = v; scaleClock = 0.4f; }, Percent);
        }

        // ---------- Звук ----------

        private void BuildSound(UiForm f)
        {
            f.Slider("settings.master", 0f, 1f, SoundSettings.Master, false, v => { SoundSettings.Master = v; Save(); }, Percent);
            f.Slider("settings.music", 0f, 1f, SoundSettings.Music, false, v => { SoundSettings.Music = v; Save(); }, Percent);
            f.Slider("settings.effects", 0f, 1f, SoundSettings.Effects, false, v =>
            {
                SoundSettings.Effects = v;
                Save();
                UiTheme.Play(Theme.clickSound, Theme.clickVolume); // слышно, как громко
            }, Percent);
            f.Slider("settings.voice", 0f, VoiceSettings.Volumes.Length - 1, VoiceSettings.Volume, true,
                v => { VoiceSettings.Volume = Mathf.RoundToInt(v); Save(); }, v => Loc.T("settings.voice." + Mathf.RoundToInt(v)));
            var mic = new[] { Loc.T("settings.mic.open"), Loc.T("settings.mic.ptt"), Loc.T("settings.mic.off") };
            f.Choice("settings.mic", mic, (int)VoiceSettings.Mic, i => { VoiceSettings.Mic = (VoiceSettings.MicMode)i; Save(); });
            f.Note("settings.saved");
        }

        // ---------- Управление ----------

        private void BuildControls()
        {
            for (int i = controlsPage.childCount - 1; i >= 0; i--) Destroy(controlsPage.GetChild(i).gameObject);
            var f = new UiForm(controlsPage);
            var asset = Theme.controls;
            f.Note("settings.header.keyboard");
            if (asset != null)
                foreach (var a in ActionsToBind)
                {
                    if (asset.FindAction(a) == null) continue;
                    var row = f.Keybind(asset, a);
                    row.Rebound += () => ControlBindings.Changed(asset);
                }
            f.Slider("settings.mouse_sens", 0.25f, 2f, AccessSettings.MouseSensitivity, false,
                v => { AccessSettings.MouseSensitivity = v; Save(); }, v => v.ToString("0.00") + "×");
            f.Note("settings.mouse_note");
            f.Button("settings.reset_bindings", false, () =>
            {
                ControlBindings.Reset(asset);
                BuildControls(); // значки — заново
            });
        }

        // ---------- Доступность ----------

        private void BuildAccess(UiForm f)
        {
            f.Toggle("settings.simple_controls", AccessSettings.SimpleControls, v => { AccessSettings.SimpleControls = v; Save(); });
            f.Note("settings.simple_note");
            f.Slider("settings.shake", 0f, 1f, VideoSettings.ShakeAmount, false, v =>
            {
                VideoSettings.ShakeAmount = v;
                Save();
            }, Percent);
            f.Toggle("settings.player_colors", AccessSettings.PlayerMarkers, v => { AccessSettings.PlayerMarkers = v; Save(); });
            f.Note("settings.markers_note");
            // Субтитры — когда появится озвучка: переключатель, который ничего не меняет, только путал (значение хранится)
        }

        // ---------- Игра ----------

        private void BuildGame(UiForm f)
        {
            f.Choice("settings.language", Loc.LanguageNames, (int)Loc.Current, i =>
            {
                Loc.Current = (Loc.Language)i;
                // Тексты внутри списков переведены при сборке — собрать экран заново на этой же вкладке.
                // Раньше экран удалялся и открывался новый: главное меню ждало закрытия старого и застревало
                startTab = 4;
                StartCoroutine(RebuildLater()); // после того, как список закроется
            });
            var hud = new[] { Loc.T("settings.hud.full"), Loc.T("settings.hud.minimal"), Loc.T("settings.hud.off") };
            f.Choice("settings.hud", hud, (int)UiSettings.Hud, i => UiSettings.Hud = (UiSettings.HudMode)i);
        }

        private System.Collections.IEnumerator RebuildLater()
        {
            yield return new WaitForSecondsRealtime(0.3f);
            if (Panel.IsOpen) Rebuild();
        }

        private void Update()
        {
            if (pendingScale < 0f) return;
            // Ждём, пока ползунок отпустят (мышь) или перестанут листать (геймпад)
            var mouse = Mouse.current;
            if (mouse != null && mouse.leftButton.isPressed) { scaleClock = 0.4f; return; }
            scaleClock -= Time.unscaledDeltaTime;
            if (scaleClock > 0f) return;
            UiSettings.Scale = pendingScale;
            pendingScale = -1f;
        }
    }
}
