using System.Collections;
using UnityEngine;
using Shatranj.Audio;
using Shatranj.Chess;
using Shatranj.UI;
using Shatranj.Visual;

namespace Shatranj.Core
{
    /// <summary>
    /// Точка входа. Сама поднимается при запуске любой сцены (RuntimeInitializeOnLoadMethod),
    /// поэтому проект работает даже с пустой сценой: всё — мир, фигуры, звук, интерфейс — строится кодом.
    /// </summary>
    public class GameRoot : MonoBehaviour
    {
        public static GameRoot I { get; private set; }

        public GameSettings Settings;
        public PlayerStats Stats;
        public UIManager UI;
        public BoardView Board;
        public CameraRig Rig;
        public EnvironmentBuilder Env;
        public MatchController Match;
        public ShowcaseStage Showcase;
        public BoardInput BoardInput;
        public bool Ready { get; private set; }

        bool menuDecor;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot()
        {
            if (I != null || FindObjectOfType<GameRoot>() != null) return;
            var go = new GameObject("ShoxVaMot");
            go.AddComponent<GameRoot>();
        }

        void Awake()
        {
            I = this;
            Application.targetFrameRate = 60;
            QualitySettings.vSyncCount = 0;
            Screen.sleepTimeout = SleepTimeout.NeverSleep;
            UnityEngine.Input.multiTouchEnabled = true;
            Physics.gravity = new Vector3(0, -12f, 0);
            Settings = GameSettings.Load();
            Loc.Current = Settings.Lang;
            Stats = PlayerStats.Load();

            // убираем камеру и свет шаблонной сцены — у нас свои
            foreach (var c in FindObjectsOfType<Camera>()) Destroy(c.gameObject);
            foreach (var l in FindObjectsOfType<Light>()) if (l.type == LightType.Directional) Destroy(l.gameObject);
        }

        IEnumerator Start()
        {
            UI = UIManager.Create(this);
            UI.Show(UI.Loading);
            Rig = CameraRig.Create();
            yield return null;
            yield return null;

            MaterialLib.Init();
            UI.Loading.SetProgress(0.3f);
            yield return null;

            Env = new GameObject("Environment").AddComponent<EnvironmentBuilder>();
            Env.Build();
            UI.Loading.SetProgress(0.5f);
            yield return null;

            Board = new GameObject("BoardView").AddComponent<BoardView>();
            Board.Build();
            Board.Rig = Rig;
            Fx.Init(transform);
            AudioManager.Create(transform);
            AdsManager.Create(transform);
            ApplyAudio();
            UI.Loading.SetProgress(0.65f);
            yield return null;

            PostFx.Setup(Rig.Cam);
            Env.Apply((Ambience)Settings.timeOfDay, Settings.quality);
            IconRenderer.RenderAll();
            Showcase = ShowcaseStage.Create(transform);
            Showcase.SetActive(false);
            Showcase.OnWhoosh = () => AudioManager.Play(Sfx.Whoosh);
            Showcase.OnImpact = () => { AudioManager.Play(Sfx.Impact); Vibrate(); };
            UI.Loading.SetProgress(0.85f);
            yield return null;

            Match = gameObject.AddComponent<MatchController>();
            Match.Init(this);
            BoardInput = gameObject.AddComponent<BoardInput>();
            BoardInput.Init(this);
            HookBoardEvents();
            ApplyVisualSettings();

            Board.SpawnAll(new PieceTracker(new Position(Variant.Classic)));
            Env.RefreshReflections();
            menuDecor = true;
            Rig.MenuOrbit = true;
            Rig.SetView(Side.White, true);
            Rig.Orbit(0, -14f);
            UI.Loading.SetProgress(1f);
            Ready = true;
            for (float t = 0; t < 0.5f; t += Time.unscaledDeltaTime) yield return null;
            AudioManager.Play(Sfx.Open);
            UI.Show(UI.Main);
        }

        void HookBoardEvents()
        {
            Board.OnFootstep = () => AudioManager.Play(Sfx.Step, 0.35f, 0.15f);
            Board.OnWhoosh = () => AudioManager.Play(Sfx.Whoosh, 1f, 0.08f);
            Board.OnImpact = () =>
            {
                AudioManager.Play(Sfx.Impact, 1f, 0.08f);
                Vibrate();
            };
            Board.OnPromote = () => AudioManager.Play(Sfx.Promote);
            Board.OnHero = v => Match.OnHero(v);
        }

        public void Vibrate()
        {
            if (!Settings.vibration) return;
#if (UNITY_ANDROID || UNITY_IOS) && !UNITY_EDITOR
            Handheld.Vibrate();
#endif
        }

        // ------------------------------------------------------------------ Переходы

        /// <summary>Декоративная расстановка и облёт камеры в главном меню.</summary>
        public void EnterMenuScene()
        {
            if (!Ready) return;
            if (Match.Game != null) return;
            if (!menuDecor)
            {
                Fx.ClearDebris();
                Board.ClearHighlights();
                Board.SpawnAll(new PieceTracker(new Position(Variant.Classic)));
                menuDecor = true;
            }
            Rig.MenuOrbit = true;
        }

        public void StartNewMatch(MatchConfig cfg)
        {
            SavedMatch.Clear();
            // перед каждой новой партией — межстраничная реклама (если загружена)
            AdsManager.ShowThen(() =>
            {
                menuDecor = false;
                Match.Begin(cfg, null);
            });
        }

        public void ContinueSaved()
        {
            var s = SavedMatch.Load();
            if (s == null || s.config == null)
            {
                SavedMatch.Clear();
                UI.Show(UI.NewGame);
                return;
            }
            AdsManager.ShowThen(() =>
            {
                menuDecor = false;
                Match.Begin(s.config, s);
            });
        }

        public void ExitToMenu()
        {
            Match.Save();
            Match.StopMatch();
            UI.Show(UI.Main);
        }

        public void Quit()
        {
            Match.Save();
            Settings.Save();
            Application.Quit();
        }

        // ------------------------------------------------------------------ Настройки

        public void SetLanguage(Language l)
        {
            if ((int)l == Settings.language) return;
            Settings.language = (int)l;
            Settings.Save();
            Loc.Current = l;
            bool inMatch = Match != null && Match.Game != null;
            UI = UI.Rebuild();
            if (inMatch) UI.Settings.ReturnTo = UI.Hud;
        }

        public void ApplyAudio()
        {
            if (AudioManager.I != null) AudioManager.I.SetVolumes(Settings.musicVolume, Settings.sfxVolume);
        }

        public void ApplyVisualSettings()
        {
            if (Env != null) Env.Apply((Ambience)Settings.timeOfDay, Settings.quality);
            PostFx.Apply(Settings.postFx, Settings.quality, (Ambience)Settings.timeOfDay);
            if (Board != null) Board.SetCoordinatesVisible(Settings.showCoordinates);
            Settings.Save();
        }

        public void RefreshBoardHints()
        {
            if (Match != null) Match.RefreshHighlights();
        }

        void OnApplicationPause(bool paused)
        {
            if (!Ready) return;
            if (!paused)
            {
                IconRenderer.RefreshIfLost();
                if (Match != null && Match.Game != null) UI.Hud.Refresh(Match);
                return;
            }
            Match.Save();
            Settings.Save();
        }

        void OnApplicationQuit()
        {
            if (!Ready) return;
            Match.Save();
            Settings.Save();
        }
    }
}
