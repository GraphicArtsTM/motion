using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace WobbleBrawl
{
    public enum GameState { Title, Lobby, Playing, RoundOver, MatchOver }

    /// <summary>
    /// Root of the game. Creates the camera, light, audio, FX and UI, then runs the state machine:
    /// Title (bots brawl in the background) → Lobby (drop-in join) → Playing → RoundOver → MatchOver.
    /// </summary>
    public sealed class GameManager : MonoBehaviour
    {
        public static GameManager I { get; private set; }
        public static float DamageMultiplier = 1f;
        public static float KillHeight => I != null && I.Arena != null ? I.Arena.KillY : -50f;
        public static bool InputLocked => I != null && (I.countdown > 0f || I.paused || I.State == GameState.MatchOver);

        public Camera MainCamera { get; private set; }
        public InputHub Input { get; private set; }
        public UIRoot UI { get; private set; }
        public Arena Arena { get; private set; }
        public GameMode Mode { get; private set; }
        public GameState State { get; private set; }
        public MatchConfig Config { get; private set; } = new MatchConfig();
        public readonly List<Participant> Lobby = new List<Participant>();
        public bool IsAttract => State == GameState.Title || State == GameState.Lobby;

        GroupCamera groupCamera;
        Light sun;
        Transform world;
        MatchConfig attractConfig;
        float stateTimer, countdown, hitStop, attractEnd = -1f;
        int lastCount;
        bool paused;
        int pauseToggleFrame = -1;
        Participant champion;
        readonly List<(Brawler b, float t)> respawns = new List<(Brawler, float)>();

        static readonly string[] FallLines = { "{0} свалился сам", "{0} решил поплавать", "{0} не удержался", "{0} покинул чат", "{0} улетел в закат" };
        static readonly string[] ThrowLines = { "{0} выкинул {1}", "{0} отправил {1} в полёт", "{0} выбросил {1}", "{0} показал {1} выход" };

        // ------------------------------------------------------------------ setup

        void Awake()
        {
            if (I != null && I != this) { Destroy(gameObject); return; }
            I = this;
            DontDestroyOnLoad(gameObject);

            Application.targetFrameRate = 120;
            Time.fixedDeltaTime = Tune.FixedStep;
            Physics.defaultSolverIterations = Tune.SolverIterations;
            Physics.defaultSolverVelocityIterations = Tune.SolverVelocityIterations;
            Physics.gravity = new Vector3(0f, -9.81f, 0f);
            Physics.defaultMaxAngularSpeed = 25f;

            BuildCamera();
            BuildSun();
            Input = new InputHub();
            Sfx.Init(transform);
            Fx.Init(transform);
            UI = new UIRoot(this, transform);

            attractConfig = new MatchConfig { mode = ModeKind.Brawl, roundsToWin = 999 };
            GoTitle();
        }

        void OnDestroy()
        {
            if (I == this) I = null;
            Input?.StopAllRumble();
        }

        void BuildCamera()
        {
            foreach (var c in FindObjectsByType<Camera>(FindObjectsSortMode.None))
                if (c.gameObject.scene.IsValid()) c.gameObject.SetActive(false);
            foreach (var l in FindObjectsByType<Light>(FindObjectsSortMode.None))
                if (l.type == LightType.Directional) l.gameObject.SetActive(false);

            var go = new GameObject("Main Camera");
            go.tag = "MainCamera";
            go.transform.SetParent(transform, false);
            MainCamera = go.AddComponent<Camera>();
            MainCamera.clearFlags = CameraClearFlags.SolidColor;
            MainCamera.fieldOfView = 50f;
            MainCamera.nearClipPlane = 0.2f;
            MainCamera.farClipPlane = 400f;
            go.AddComponent<AudioListener>();
            groupCamera = go.AddComponent<GroupCamera>();
            groupCamera.cam = MainCamera;
        }

        void BuildSun()
        {
            var go = new GameObject("Sun");
            go.transform.SetParent(transform, false);
            sun = go.AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = 0.75f;
            sun.shadowBias = 0.04f;
            sun.shadowNormalBias = 0.3f;
            QualitySettings.shadowDistance = 70f;
            RenderSettings.sun = sun;
        }

        void ApplyEnvironment(Arena a)
        {
            MainCamera.backgroundColor = a.SkyColor;
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.ExponentialSquared;
            RenderSettings.fogColor = a.FogColor;
            RenderSettings.fogDensity = a.FogDensity;
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = a.AmbientSky;
            RenderSettings.ambientEquatorColor = a.AmbientEquator;
            RenderSettings.ambientGroundColor = a.AmbientGround;
            RenderSettings.skybox = null;
            sun.color = a.SunColor;
            sun.intensity = a.SunIntensity;
            sun.transform.rotation = Quaternion.Euler(a.SunEuler);
            groupCamera.Configure(a);
        }

        // ------------------------------------------------------------------ world building

        void ClearWorld()
        {
            respawns.Clear();
            Brawler.All.Clear();
            Arena = null;
            Mode = null;
            if (world != null)
            {
                world.gameObject.SetActive(false);
                Destroy(world.gameObject);
            }
            world = new GameObject("World").transform;
            world.SetParent(transform, false);
        }

        void BuildRound(MatchConfig cfg)
        {
            ClearWorld();
            Mode = GameMode.Create(cfg.mode);
            Mode.Bind(this);
            Arena = Mode.CreateArena(cfg);
            Arena.Build(world);
            ApplyEnvironment(Arena);
            DamageMultiplier = 1f;

            for (int i = 0; i < cfg.participants.Count; i++)
            {
                var p = cfg.participants[i];
                Vector3 pos = Arena.SpawnPoint(i);
                var b = BrawlerBuilder.Build(world, p, pos, Arena.SpawnRotation(pos));
                b.brain = p.isBot ? new BotBrain(cfg.SkillValue * Random.Range(0.85f, 1.1f)) : (IBrain)new PlayerBrain(p.slot);
                b.SetChampion(p == champion);
                p.brawler = b;
            }
            Mode.BeginRound();
            groupCamera.Snap();
        }

        // ------------------------------------------------------------------ state transitions

        void GoTitle()
        {
            Time.timeScale = 1f;
            paused = false;
            countdown = 0f;
            State = GameState.Title;
            champion = null;
            StartAttract();
            UI.ShowTitle();
            Sfx.PlayMusic(Sfx.MenuMusic);
            Sfx.SetMusicDuck(1f);
        }

        void StartAttract()
        {
            attractConfig.participants.Clear();
            attractConfig.arenaIndex = Random.Range(0, ArenaCatalog.BrawlCount);
            attractConfig.botSkill = BotSkill.Normal;
            var names = new List<string>(Palette.BotNames);
            for (int i = 0; i < 4; i++)
            {
                int n = Random.Range(0, names.Count);
                attractConfig.participants.Add(new Participant
                {
                    index = i, name = names[n], color = Palette.Players[i * 2 % Palette.Players.Length],
                    hat = (HatKind)Random.Range(0, (int)HatKind.Count), isBot = true,
                });
                names.RemoveAt(n);
            }
            BuildRound(attractConfig);
            groupCamera.orbit = true;
            stateTimer = 0f;
            attractEnd = -1f;
        }

        public void OpenLobby(ModeKind mode)
        {
            Config.mode = mode;
            State = GameState.Lobby;
            UI.ShowLobby();
        }

        public void BackToTitle()
        {
            Lobby.Clear();
            Input.StopAllRumble();
            GoTitle();
        }

        public void ExitToLobby()
        {
            Time.timeScale = 1f;
            paused = false;
            countdown = 0f;
            champion = null;
            State = GameState.Lobby;
            StartAttract();
            UI.ShowLobby();
            Sfx.PlayMusic(Sfx.MenuMusic);
            Sfx.SetMusicDuck(1f);
        }

        public bool IsJoined(InputSlot s)
        {
            foreach (var p in Lobby) if (p.slot == s) return true;
            return false;
        }

        void Join(InputSlot s)
        {
            if (Lobby.Count >= LobbyScreen.MaxHumans || IsJoined(s)) return;
            var p = new Participant
            {
                name = "Игрок " + (Lobby.Count + 1),
                color = FreeColor(-1, 1),
                hat = (HatKind)Random.Range(0, (int)HatKind.Count),
                slot = s,
            };
            Lobby.Add(p);
            Sfx.PlayUI(Sfx.Select, 0.8f, 1.2f);
            s.Rumble(0.3f, 0.3f, 0.15f);
        }

        Color FreeColor(int startIndex, int dir)
        {
            int n = Palette.Players.Length;
            for (int k = 1; k <= n; k++)
            {
                var c = Palette.Players[((startIndex + k * dir) % n + n) % n];
                bool used = false;
                foreach (var p in Lobby) if (p.color == c) used = true;
                if (!used) return c;
            }
            return Palette.Players[0];
        }

        public void StartMatch()
        {
            if (Lobby.Count == 0) Join(Input.KeyboardMouse);

            Config.participants.Clear();
            int idx = 0;
            for (int i = 0; i < Lobby.Count; i++)
            {
                var h = Lobby[i];
                h.index = idx++;
                h.name = "Игрок " + (i + 1);
                h.wins = 0; h.score = 0; h.knockouts = 0; h.eliminations = 0;
                Config.participants.Add(h);
            }
            var mode = GameMode.Create(Config.mode);
            if (mode.UsesBots)
            {
                var names = new List<string>(Palette.BotNames);
                for (int i = 0; i < Config.botCount && Config.participants.Count < 8; i++)
                {
                    int n = Random.Range(0, names.Count);
                    Config.participants.Add(new Participant
                    {
                        index = idx++, name = names[n], isBot = true,
                        color = FreeBotColor(),
                        hat = (HatKind)Random.Range(0, (int)HatKind.Count),
                    });
                    names.RemoveAt(n);
                }
            }
            champion = null;
            StartRound();
        }

        Color FreeBotColor()
        {
            foreach (var c in Palette.Players)
            {
                bool used = false;
                foreach (var p in Config.participants) if (p.color == c) used = true;
                if (!used) return c;
            }
            return Random.ColorHSV(0f, 1f, 0.5f, 0.8f, 0.8f, 1f);
        }

        void StartRound()
        {
            Time.timeScale = 1f;
            paused = false;
            BuildRound(Config);
            groupCamera.orbit = false;
            State = GameState.Playing;
            countdown = 3.2f;
            lastCount = 4;
            UI.ShowHud(Config.participants);
            Sfx.PlayMusic(Sfx.BattleMusic);
            Sfx.SetMusicDuck(1f);
        }

        public void RestartMatch()
        {
            foreach (var p in Config.participants) { p.wins = 0; p.score = 0; p.knockouts = 0; p.eliminations = 0; }
            champion = null;
            StartRound();
        }

        public void Resume()
        {
            paused = false;
            Time.timeScale = 1f;
            UI.ShowPause(false);
            Sfx.SetMusicDuck(1f);
        }

        void Pause()
        {
            paused = true;
            Time.timeScale = 0f;
            UI.ShowPause(true);
            Sfx.SetMusicDuck(0.4f);
            Input.StopAllRumble();
        }

        public void QuitGame()
        {
#if UNITY_EDITOR
            UnityEditor.EditorApplication.isPlaying = false;
#else
            Application.Quit();
#endif
        }

        // ------------------------------------------------------------------ events from the world

        public void NotifyOut(Brawler b)
        {
            Arena?.OnBrawlerOut(b);
            if (Mode == null) return;

            var attacker = b.LastAttacker;
            bool credited = attacker != null && attacker != b && Time.time - b.LastAttackTime < 8f;
            if (credited && attacker.participant != null) attacker.participant.eliminations++;
            if (!IsAttract && b.participant != null)
            {
                string victim = Palette.Paint(b.participant.name, b.participant.color);
                if (credited)
                {
                    string killer = Palette.Paint(attacker.participant.name, attacker.participant.color);
                    UI.Feed(string.Format(ThrowLines[Random.Range(0, ThrowLines.Length)], killer, victim));
                }
                else UI.Feed(string.Format(FallLines[Random.Range(0, FallLines.Length)], victim));
                Sfx.Play(Sfx.Cheer, b.Position, 0.5f, Random.Range(0.95f, 1.1f));
                Shake(0.3f);
                b.participant.slot?.Rumble(0.8f, 0.8f, 0.4f);
            }

            Mode.OnBrawlerOut(b);
            if (Mode.AllowRespawn) respawns.Add((b, Time.time + Mode.RespawnDelay));
        }

        public void NotifyKnockout(Brawler victim, Brawler attacker)
        {
            if (attacker != null && attacker.participant != null) attacker.participant.knockouts++;
            Mode?.OnKnockout(victim, attacker);
            if (IsAttract) return;
            bool human = (victim.participant != null && !victim.participant.isBot) || (attacker != null && attacker.participant != null && !attacker.participant.isBot);
            if (human) HitStop(0.12f);
            Shake(0.5f);
            if (attacker != null && attacker.participant != null)
                UI.Feed(Palette.Paint(attacker.participant.name, attacker.participant.color) + " вырубил " + Palette.Paint(victim.participant.name, victim.participant.color) + "!");
        }

        public void Shake(float amount) => groupCamera.AddShake(amount);

        public void HitStop(float seconds)
        {
            if (paused) return;
            hitStop = Mathf.Max(hitStop, seconds);
            Time.timeScale = 0.15f;
        }

        // ------------------------------------------------------------------ main loop

        void Update()
        {
            float udt = Time.unscaledDeltaTime;
            Input.Refresh(udt);

            if (hitStop > 0f && !paused)
            {
                hitStop -= udt;
                if (hitStop <= 0f) Time.timeScale = 1f;
            }

            // read navigation exactly once per frame: gamepad stick edges are stateful
            MenuNav nav = State == GameState.Lobby ? TickLobbyInput() : Input.Nav();
            switch (State)
            {
                case GameState.Title:
                case GameState.Lobby:
                    TickAttract(udt);
                    break;
                case GameState.Playing:
                    TickPlaying(udt);
                    break;
                case GameState.RoundOver:
                    TickRoundOver(udt);
                    break;
                case GameState.MatchOver:
                    TickMatchOver(udt, nav);
                    break;
            }

            if (!paused) Arena?.Tick(Time.deltaTime);
            // the key that toggled pause this frame must not also drive the pause menu
            bool menuInput = paused ? pauseToggleFrame != Time.frameCount : State == GameState.Title || State == GameState.Lobby;
            UI.Tick(State, menuInput ? nav : default);
        }

        void TickAttract(float udt)
        {
            if (Mode == null) return;
            Mode.Tick(Time.deltaTime);
            stateTimer += udt;
            ProcessRespawns();
            int alive = 0;
            foreach (var b in Brawler.All) if (!b.IsOut) alive++;
            if ((Mode.RoundOver || stateTimer > 75f || alive == 0) && attractEnd < 0f) attractEnd = 2.5f;
            if (attractEnd >= 0f)
            {
                attractEnd -= udt;
                // keep the background brawl going forever
                if (attractEnd < 0f) StartAttract();
            }
        }

        MenuNav TickLobbyInput()
        {
            // navigation first, so the button that joins a pad does not also press a menu item
            var nav = new MenuNav();
            foreach (var s in Input.Slots)
            {
                if (!s.Connected) continue;
                var n = s.Nav();
                if (!IsJoined(s) && s.JoinDown()) n.confirm = false;
                nav |= n;
            }

            for (int i = Lobby.Count - 1; i >= 0; i--)
            {
                var p = Lobby[i];
                if (!p.slot.Connected || p.slot.LeaveDown())
                {
                    Lobby.RemoveAt(i);
                    Sfx.PlayUI(Sfx.Select, 0.6f, 0.7f);
                    continue;
                }
                var raw = p.slot.Read(Time.unscaledDeltaTime);
                if (raw.punchDown)
                {
                    p.hat = (HatKind)(((int)p.hat + 1) % (int)HatKind.Count);
                    Sfx.PlayUI(Sfx.Tick, 0.7f, 1.3f);
                }
                if (raw.altDown)
                {
                    int cur = System.Array.IndexOf(Palette.Players, p.color);
                    p.color = FreeColor(cur, 1);
                    Sfx.PlayUI(Sfx.Tick, 0.7f, 1.1f);
                }
            }

            foreach (var s in Input.Slots)
                if (s.Connected && !IsJoined(s) && s.JoinDown()) Join(s);

            return nav;
        }

        void TickPlaying(float udt)
        {
            if (Input.PauseDown())
            {
                if (paused) Resume(); else Pause();
                pauseToggleFrame = Time.frameCount;
            }
            if (paused) return;

            if (countdown > 0f)
            {
                countdown -= udt;
                int c = Mathf.CeilToInt(countdown);
                if (c != lastCount && c > 0 && c <= 3)
                {
                    lastCount = c;
                    UI.Banner(c.ToString(), Mode.Title + " · " + Arena.Title, Palette.UiAccent, 0.9f);
                    Sfx.PlayUI(Sfx.Tick, 0.9f, 0.8f);
                }
                if (countdown <= 0f)
                {
                    UI.Banner("В БОЙ!", Arena.Subtitle, Color.white, 1.2f);
                    Sfx.PlayUI(Sfx.Whistle, 0.8f);
                }
                return;
            }

            Mode.Tick(Time.deltaTime);
            ProcessRespawns();

            if (Mode.RoundOver)
            {
                State = GameState.RoundOver;
                stateTimer = 0f;
                var w = Mode.RoundWinner;
                bool matchOver = Mode.MatchOver || !Mode.MultiRound;
                UI.Banner(matchOver ? "ПОБЕДА!" : "РАУНД!", Mode.ResultText, w != null ? w.color : Color.white, 3f);
                Sfx.PlayUI(Sfx.Fanfare, 0.8f);
                Sfx.Play(Sfx.Cheer, MainCamera.transform.position, 0.8f);
                if (w != null && w.brawler != null)
                {
                    Fx.Confetti(w.brawler.HeadVisualPosition + Vector3.up, 60);
                    groupCamera.focusOverride = w.brawler;
                    champion = w;
                }
                Time.timeScale = 0.6f;
            }
        }

        void ProcessRespawns()
        {
            for (int i = respawns.Count - 1; i >= 0; i--)
            {
                if (Time.time < respawns[i].t) continue;
                var b = respawns[i].b;
                respawns.RemoveAt(i);
                if (b == null || Mode == null) continue;
                Vector3 p = Mode.RespawnPoint(b);
                b.Respawn(p, Arena.SpawnRotation(p));
            }
        }

        void TickRoundOver(float udt)
        {
            stateTimer += udt;
            ProcessRespawns();
            if (stateTimer < 3.2f) return;
            Time.timeScale = 1f;
            groupCamera.focusOverride = null;
            if (Mode.MatchOver || !Mode.MultiRound)
            {
                State = GameState.MatchOver;
                stateTimer = 0f;
                UI.ShowResults(Config, Mode);
                Sfx.PlayUI(Sfx.Fanfare, 0.9f, 1.1f);
            }
            else StartRound();
        }

        void TickMatchOver(float udt, MenuNav nav)
        {
            stateTimer += udt;
            if (stateTimer > 1.2f && (nav.confirm || Input.PauseDown() || stateTimer > 12f))
            {
                UI.HideResults();
                ExitToLobby();
            }
        }
    }
}
