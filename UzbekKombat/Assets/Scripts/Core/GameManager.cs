using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    public enum UIScreen { Title, MainMenu, CharSelect, Versus, Fight, Results, Controls, Options, Ending }

    /// <summary>
    /// O'yin oqimi: titul → bosh menyu → qahramon tanlash → "QARSHI" ekrani → jang → natija.
    /// Arkada (CPU zinapoyasi), ikki o'yinchi, mashq va tomosha rejimlari.
    /// </summary>
    public class GameManager : MonoBehaviour
    {
        public static GameManager I { get; private set; }

        public UIScreen screen = UIScreen.Title;
        public GameMode mode = GameMode.Arcade;
        public FightCamera cam;
        public Arena arena;
        public MatchController match;
        public GameUI ui;
        public KeyboardInput p1Keys, p2Keys;
        public DummyInput dummy;

        // Sozlamalar
        public int difficulty = 1;
        public int roundsToWin = 2;
        public int arenaChoice; // 0 — shom, 1 — tun, 2 — tasodifiy
        public bool showHitboxes;

        // Tanlov
        public int p1Index, p2Index = 1;
        public bool p1Ready, p2Ready;
        public readonly Dictionary<string, RenderTexture> portraits = new Dictionary<string, RenderTexture>();
        Fighter previewA, previewB;
        Transform previewRoot;
        int previewAIdx = -1, previewBIdx = -1;

        // Arkada
        public List<int> ladder = new List<int>();
        public int ladderStep;
        public bool lastMatchWon;
        public bool paused;

        public List<FighterDefinition> Roster => UzbekKombat.Roster.All;

        public static void Boot()
        {
            if (I != null) return;
            var go = new GameObject("GameManager");
            DontDestroyOnLoad(go);
            I = go.AddComponent<GameManager>();
        }

        void Awake()
        {
            I = this;
            Application.targetFrameRate = 60;
            QualitySettings.vSyncCount = 1;
            QualitySettings.shadowDistance = 45f;
            QualitySettings.shadowCascades = 2;
            QualitySettings.shadows = ShadowQuality.All;
            QualitySettings.shadowResolution = ShadowResolution.High;
            QualitySettings.antiAliasing = 4;
            Time.fixedDeltaTime = 1f / 60f;

            SynthAudio.Create();
            Shader.SetGlobalTexture("_UKDetailTex", TextureFactory.Detail());
            VFX.Init();
            cam = FightCamera.Create();
            cam.transform.SetParent(transform, false);
            BuildArena(ArenaPreset.Sunset);
            p1Keys = new KeyboardInput(KeyMap.Player1());
            p2Keys = new KeyboardInput(KeyMap.Player2());
            dummy = new DummyInput();
            ui = gameObject.AddComponent<GameUI>();
            ui.gm = this;
            RenderPortraits();
            cam.Orbit(new Vector3(0, 2.2f, 6f), 15f, 2.5f, 4f, -90f, 45f);
            SynthAudio.I.PlayMusic("menu");
        }

        void BuildArena(ArenaPreset p)
        {
            if (arena != null && arena.preset == p) return;
            if (arena != null) Destroy(arena.gameObject);
            arena = Arena.Build(p);
            if (cam != null && cam.post != null) cam.post.Preset(p);
        }

        void Update()
        {
            p1Keys.Latch();
            p2Keys.Latch();
            if (screen == UIScreen.Fight && match != null && Input.GetKeyDown(KeyCode.Escape) && match.phase != MatchPhase.MatchEnd) TogglePause();
            if (screen == UIScreen.Fight && match != null && mode == GameMode.Training && !paused) TrainingKeys();
            if (Input.GetKeyDown(KeyCode.F7)) showHitboxes = !showHitboxes;
        }

        void TrainingKeys()
        {
            if (Input.GetKeyDown(KeyCode.F1)) dummy.mode = DummyInput.Mode.Stand;
            if (Input.GetKeyDown(KeyCode.F2)) dummy.mode = DummyInput.Mode.Crouch;
            if (Input.GetKeyDown(KeyCode.F3)) dummy.mode = DummyInput.Mode.Jump;
            if (Input.GetKeyDown(KeyCode.F4)) dummy.mode = DummyInput.Mode.BlockAll;
            if (Input.GetKeyDown(KeyCode.F5)) dummy.mode = DummyInput.Mode.BlockRandom;
            if (Input.GetKeyDown(KeyCode.F6)) dummy.mode = DummyInput.Mode.CPU;
            if (Input.GetKeyDown(KeyCode.F8) && match != null)
            {
                match.f1.ResetForRound(-2.4f, 1);
                match.f2.ResetForRound(2.4f, -1);
            }
        }

        // ======================= Portretlar =======================
        void RenderPortraits()
        {
            var studio = new GameObject("PortraitStudio").transform;
            studio.position = new Vector3(400, 0, 400);
            var camGo = new GameObject("PortraitCam");
            camGo.transform.SetParent(studio, false);
            var pc = camGo.AddComponent<Camera>();
            pc.clearFlags = CameraClearFlags.SolidColor;
            pc.backgroundColor = new Color(0, 0, 0, 0);
            pc.fieldOfView = 24;
            pc.nearClipPlane = 0.05f;
            pc.farClipPlane = 8f;
            pc.enabled = false;
            var key = new GameObject("Key").AddComponent<Light>();
            key.transform.SetParent(studio, false);
            key.type = LightType.Point; key.range = 6; key.intensity = 1.6f; key.color = new Color(1f, 0.85f, 0.7f);
            key.transform.localPosition = new Vector3(1.2f, 2.2f, 1.6f);
            var fill = new GameObject("Fill").AddComponent<Light>();
            fill.transform.SetParent(studio, false);
            fill.type = LightType.Point; fill.range = 6; fill.intensity = 0.9f; fill.color = new Color(0.5f, 0.6f, 1f);
            fill.transform.localPosition = new Vector3(-1.4f, 1.4f, 0.8f);

            foreach (var d in Roster)
            {
                var holder = new GameObject("p_" + d.id).transform;
                holder.SetParent(studio, false);
                var rig = d.buildVisual(holder);
                var an = rig.gameObject.AddComponent<ProceduralAnimator>();
                an.rig = rig;
                an.breathing = false;
                an.Play(d.anims.idle, 0);
                an.Tick(0.01f);
                Vector3 head = rig.Pos(Bone.Head) + Vector3.up * 0.1f;
                camGo.transform.position = head + new Vector3(0.5f, 0.02f, 1.35f);
                camGo.transform.LookAt(head + Vector3.down * 0.12f);
                var rt = new RenderTexture(320, 400, 24, RenderTextureFormat.ARGB32) { name = "portrait_" + d.id, antiAliasing = 4 };
                pc.targetTexture = rt;
                pc.Render();
                portraits[d.id] = rt;
                Destroy(holder.gameObject);
            }
            pc.targetTexture = null;
            Destroy(studio.gameObject);
        }

        // ======================= Ekranlar =======================
        public void GoMainMenu()
        {
            EndMatch();
            ClearPreviews();
            screen = UIScreen.MainMenu;
            cam.Orbit(new Vector3(0, 2.2f, 6f), 15f, 2.5f, 4f, -90f, 45f);
            SynthAudio.I.PlayMusic("menu");
        }

        public void StartMode(GameMode m)
        {
            mode = m;
            p1Ready = p2Ready = false;
            if (m == GameMode.Arcade) { ladder.Clear(); ladderStep = 0; }
            screen = UIScreen.CharSelect;
            p2Index = (p1Index + 1) % Roster.Count;
            UpdatePreviews();
            cam.Shot(new Vector3(0, 1.7f, -7.2f), new Vector3(0, 1.25f, 0), 36, 1.0f);
        }

        public void SelectMove(int player, int dir)
        {
            int n = Roster.Count;
            if (player == 0 && !p1Ready) p1Index = (p1Index + dir + n) % n;
            if (player == 1 && !p2Ready) p2Index = (p2Index + dir + n) % n;
            SynthAudio.Play(Sfx.UIMove, 0.6f);
            UpdatePreviews();
        }

        public void Confirm(int player)
        {
            if (player == 0 && !p1Ready)
            {
                p1Ready = true;
                SynthAudio.Play(Sfx.UISelect, 0.8f);
                if (previewA) previewA.anim.Play(previewA.def.anims.victory, 0.15f);
                if (mode != GameMode.Versus)
                {
                    // CPU raqibini tanlash
                    if (mode == GameMode.Arcade)
                    {
                        ladder.Clear();
                        for (int i = 0; i < Roster.Count; i++) if (i != p1Index) ladder.Add(i);
                        Shuffle(ladder);
                        ladder.Add(p1Index); // final — ko'zgu jangi (soya)
                        ladderStep = 0;
                        p2Index = ladder[0];
                    }
                    else if (mode == GameMode.Watch) { p2Index = (p1Index + 1 + Random.Range(0, Roster.Count - 1)) % Roster.Count; }
                    else if (mode == GameMode.Training) { p2Index = (p1Index + 1) % Roster.Count; }
                    p2Ready = true;
                    UpdatePreviews();
                    if (previewB) previewB.anim.Play(previewB.def.anims.victory, 0.15f);
                }
            }
            else if (player == 1 && !p2Ready && mode == GameMode.Versus)
            {
                p2Ready = true;
                SynthAudio.Play(Sfx.UISelect, 0.8f);
                if (previewB) previewB.anim.Play(previewB.def.anims.victory, 0.15f);
            }
            if (p1Ready && p2Ready) StartCoroutine(GoVersus());
        }

        public void Back(int player)
        {
            if (player == 1 && p2Ready && mode == GameMode.Versus) { p2Ready = false; SynthAudio.Play(Sfx.UIBack, 0.6f); UpdatePreviews(true); return; }
            if (p1Ready) { p1Ready = false; if (mode != GameMode.Versus) p2Ready = false; SynthAudio.Play(Sfx.UIBack, 0.6f); UpdatePreviews(true); return; }
            SynthAudio.Play(Sfx.UIBack, 0.6f);
            GoMainMenu();
        }

        static void Shuffle(List<int> l)
        {
            for (int i = l.Count - 1; i > 0; i--) { int j = Random.Range(0, i + 1); (l[i], l[j]) = (l[j], l[i]); }
        }

        void UpdatePreviews(bool forceIdle = false)
        {
            if (previewRoot == null) previewRoot = new GameObject("Previews").transform;
            if (previewAIdx != p1Index || previewA == null)
            {
                if (previewA) Destroy(previewA.gameObject);
                previewA = MakePreview(Roster[p1Index], -2.0f, 1);
                previewAIdx = p1Index;
            }
            else if (forceIdle) previewA.anim.Play(previewA.def.anims.idle, 0.2f);
            if (previewBIdx != p2Index || previewB == null)
            {
                if (previewB) Destroy(previewB.gameObject);
                previewB = MakePreview(Roster[p2Index], 2.0f, -1);
                previewBIdx = p2Index;
            }
            else if (forceIdle) previewB.anim.Play(previewB.def.anims.idle, 0.2f);
            bool showB = mode == GameMode.Versus || p2Ready;
            previewB.gameObject.SetActive(showB);
        }

        Fighter MakePreview(FighterDefinition d, float x, int face)
        {
            var go = new GameObject("Preview_" + d.id);
            go.transform.SetParent(previewRoot, false);
            var f = go.AddComponent<Fighter>();
            f.Setup(d, 0, null, null);
            f.pos = f.prevPos = new Vector2(x, 0);
            f.SetFacing(face);
            f.state = FState.Intro;
            f.anim.Play(d.anims.intro, 0.05f);
            VFX.Emit(VFX.Kind.Smoke, new Vector3(x, 1, 0), d.energyColor.WithA(0.5f), 10, 1.5f, 1f, 0.6f, Vector3.up, 1f);
            return f;
        }

        void ClearPreviews()
        {
            if (previewA) Destroy(previewA.gameObject);
            if (previewB) Destroy(previewB.gameObject);
            previewA = previewB = null;
            previewAIdx = previewBIdx = -1;
        }

        IEnumerator GoVersus()
        {
            yield return new WaitForSeconds(0.9f);
            screen = UIScreen.Versus;
            SynthAudio.Play(Sfx.Gong, 1f);
            SynthAudio.Play(Sfx.DrumRoll, 0.8f);
            yield return new WaitForSeconds(2.6f);
            StartFight();
        }

        public void StartFight()
        {
            ClearPreviews();
            EndMatch();
            var preset = arenaChoice == 0 ? ArenaPreset.Sunset : arenaChoice == 1 ? ArenaPreset.Night : (Random.value < 0.5f ? ArenaPreset.Sunset : ArenaPreset.Night);
            BuildArena(preset);
            IInputSource in1, in2;
            switch (mode)
            {
                case GameMode.Versus: in1 = p1Keys; in2 = p2Keys; break;
                case GameMode.Training: in1 = p1Keys; in2 = dummy; break;
                case GameMode.Watch: in1 = new FighterAI(difficulty, 1); in2 = new FighterAI(difficulty, 2); break;
                default:
                    in1 = p1Keys;
                    int diff = Mathf.Clamp(difficulty + (ladderStep >= 2 ? 1 : 0), 0, 3);
                    in2 = new FighterAI(diff, ladderStep + 7);
                    break;
            }
            match = MatchController.Create(Roster[p1Index], Roster[p2Index], in1, in2, mode, arena, cam);
            match.roundsToWin = roundsToWin;
            match.onMatchOver = OnMatchOver;
            screen = UIScreen.Fight;
            paused = false;
            match.Begin();
        }

        void OnMatchOver(MatchController m)
        {
            lastMatchWon = m.matchWinner == m.f1;
            StartCoroutine(ShowResults());
        }

        IEnumerator ShowResults()
        {
            yield return new WaitForSeconds(1.2f);
            screen = UIScreen.Results;
        }

        public void ResultsAction(int action)
        {
            SynthAudio.Play(Sfx.UISelect, 0.7f);
            switch (action)
            {
                case 0: // davom / qayta
                    if (mode == GameMode.Arcade)
                    {
                        if (lastMatchWon)
                        {
                            ladderStep++;
                            if (ladderStep >= ladder.Count) { EndMatch(); screen = UIScreen.Ending; cam.Orbit(new Vector3(0, 1.4f, 0), 6f, 1.2f, 8f, -90, 38); ShowEndingHero(); return; }
                            p2Index = ladder[ladderStep];
                        }
                        StartCoroutine(VersusThenFight());
                    }
                    else StartFight();
                    break;
                case 1: // qahramon tanlash
                    EndMatch();
                    StartMode(mode);
                    break;
                default:
                    GoMainMenu();
                    break;
            }
        }

        IEnumerator VersusThenFight()
        {
            EndMatch();
            screen = UIScreen.Versus;
            SynthAudio.Play(Sfx.Gong, 1f);
            yield return new WaitForSeconds(2.4f);
            StartFight();
        }

        void ShowEndingHero()
        {
            ClearPreviews();
            if (previewRoot == null) previewRoot = new GameObject("Previews").transform;
            previewA = MakePreview(Roster[p1Index], 0, 1);
            previewA.anim.Play(previewA.def.anims.victory, 0.2f);
            arena.Cheer(1f);
            SynthAudio.Play(Sfx.CrowdBig, 0.8f);
            SynthAudio.I.PlayMusic("menu");
        }

        public void TogglePause()
        {
            paused = !paused;
            match?.Pause(paused);
            SynthAudio.Play(paused ? Sfx.UIBack : Sfx.UISelect, 0.6f);
        }

        public void EndMatch()
        {
            if (match != null)
            {
                match.Cleanup();
                match = null;
            }
            paused = false;
            Time.timeScale = 1f;
        }

        public void OpenScreen(UIScreen s) { screen = s; SynthAudio.Play(Sfx.UISelect, 0.6f); }

        public void Quit()
        {
#if UNITY_EDITOR
            UnityEditor.EditorApplication.isPlaying = false;
#else
            Application.Quit();
#endif
        }
    }
}
