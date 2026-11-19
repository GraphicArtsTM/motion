using System.Collections.Generic;
using System.Text;
using RoyalRun.Net;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.UI;

// The game's main "director". The only object that has to be placed in the scene.
// It creates the light, menu, lobby, UI, player worlds and the split screen by itself.
// The interface is in three languages (Russian, English, Uzbek) - the LANGUAGE button in the menu.
// Even if the scene is empty, the game starts: AutoCreate() adds this object by itself.
//
//   Menu ─┬─ Single Player ──> Hero select ───────────┐
//         └─ Multiplayer ─> Lobby (QR code) -> Countdown ─┴─> Game -> Results -> (back to select / lobby)
[RequireComponent(typeof(GameAssets))]
public class GameBootstrap : MonoBehaviour
{
    enum Phase { Menu, SingleSelect, Lobby, Countdown, Playing, Results }
    enum Mode { Single, Network }

    class LobbySlotView
    {
        public Transform root;
        public GameObject pedestalObject;
        public Renderer pedestal;
        public GameObject model;
        public int shownCharacter = -2;
        public Text nameText;
        public Text charText;
        public Text statusText;
        public Image strip;
    }

    const string BestScoreKey = "royalrun_best";

    [SerializeField] float countdownSeconds = 3f;
    [SerializeField] float resultsTimeout = 40f;

    GameAssets assets;
    PhoneHub hub;
    Phase phase = Phase.Menu;
    Mode mode = Mode.Network;

    // --- UI ---
    Canvas canvas;
    GameObject menuUi, selectUi, lobbyUi, resultsUi, helpUi;
    Text footerText;
    Text countText;

    MenuButton[] menuButtons;         // 0 single, 1 multi, 2 help, 3 language, 4 quit
    int menuSelected;
    string footerKey;                 // localization key of the footer text

    MenuButton[] selectButtons;       // 0 "<", 1 ">", 2 "PLAY", 3 "BACK"
    int selectSelected = 2;
    Text selName, selDesc, selStats, selCounter;

    Text stepsText, urlText, qrCaption;
    RawImage qrImage;
    Texture2D qrTexture;
    string qrShownUrl;
    Text hintText;

    RectTransform resultsRows;
    Text resultsHint;
    MenuButton[] resultsButtons;      // 0 RESTART, 1 ADD PLAYERS / CHANGE HERO, 2 MAIN MENU
    int resultsSelected;

    GameObject pauseUi;
    MenuButton[] pauseButtons;        // 0 RESUME, 1 RESTART, 2 ADD PLAYERS / CHANGE HERO, 3 MAIN MENU
    int pauseSelected;
    bool paused;

    MenuButton[] helpButtons;
    int helpSelected;
    Text helpText;
    bool helpOpen;
    float helpRefresh;

    // --- lobby scene ---
    Transform stage;
    Camera lobbyCam;
    readonly LobbySlotView[] views = new LobbySlotView[PhoneHub.MaxPlayers];

    // --- game ---
    readonly List<PlayerWorld> worlds = new List<PlayerWorld>();
    float countdownLeft;
    int lastCountShown;
    float finishDelay;
    float resultsTimer;

    // ============================================================
    //  Start-up
    // ============================================================

    // If someone presses Play in an empty scene, the game still starts.
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    static void AutoCreate()
    {
        if (FindFirstObjectByType<GameBootstrap>() != null) return;
        GameObject go = new GameObject("GameBootstrap");
        go.AddComponent<GameBootstrap>();
    }

    void Awake()
    {
        Application.runInBackground = true;      // the game must not pause when the window loses focus
        Application.targetFrameRate = 60;
        _ = Loc.Current;                         // load the saved language before the server starts
        assets = GetComponent<GameAssets>();
        if (assets == null) assets = gameObject.AddComponent<GameAssets>();
        assets.EnsureDefaults();                 // models, road, obstacles and music built by code
        Sfx.Init(gameObject);
        GameUI.ClearBindings();
        Loc.Changed += OnLanguageChanged;

        if (FindFirstObjectByType<AudioListener>() == null) gameObject.AddComponent<AudioListener>();

        CreateLight();
        CreateAtmosphere();
        CreateMusic();

        hub = gameObject.AddComponent<PhoneHub>();
        hub.Changed += OnHubChanged;

        canvas = GameUI.CreateCanvas("Canvas", transform);
        BuildStage();
        BuildMenuUi();
        BuildSelectUi();
        BuildLobbyUi();
        BuildResultsUi();
        BuildPauseUi();
        BuildHelpUi();
        BuildFooter();

        EnterMenu();
    }

    void OnDestroy()
    {
        Time.timeScale = 1f;
        Loc.Changed -= OnLanguageChanged;
        if (hub != null) hub.Changed -= OnHubChanged;
        if (qrTexture != null) Destroy(qrTexture);
    }

    // ============================================================
    //  Building the scene
    // ============================================================

    void CreateLight()
    {
        GameObject go = new GameObject("Directional Light");
        go.transform.SetParent(transform, false);
        go.transform.rotation = new Quaternion(-0.36955687f, 0.56243926f, -0.3280403f, -0.6629324f);
        Light l = go.AddComponent<Light>();
        l.type = LightType.Directional;
        l.intensity = 1.2f;
        l.shadows = LightShadows.Soft;
    }

    // Ambient light and fog (the scene has no skybox - the background is a solid colour).
    void CreateAtmosphere()
    {
        Color fog = new Color(0.10f, 0.06f, 0.20f, 1f);
        RenderSettings.ambientMode = AmbientMode.Trilight;
        RenderSettings.ambientSkyColor = new Color(0.62f, 0.58f, 0.78f);
        RenderSettings.ambientEquatorColor = new Color(0.40f, 0.36f, 0.48f);
        RenderSettings.ambientGroundColor = new Color(0.18f, 0.15f, 0.22f);
        RenderSettings.fog = true;
        RenderSettings.fogMode = FogMode.Linear;
        RenderSettings.fogColor = fog;
        RenderSettings.fogStartDistance = 40f;
        RenderSettings.fogEndDistance = 120f;
    }

    void CreateMusic()
    {
        if (assets.music == null) return;
        AudioSource src = gameObject.AddComponent<AudioSource>();
        src.clip = assets.music;
        src.loop = true;
        src.volume = 0.4f;
        src.playOnAwake = false;
        src.Play();
    }

    // Three "podiums" with heroes, visible in the menu, hero select and lobby.
    void BuildStage()
    {
        stage = new GameObject("Lobby Stage").transform;
        stage.SetParent(transform, false);
        stage.position = new Vector3(-300f, 0f, -300f);   // far away from the game worlds

        GameObject camGo = new GameObject("Lobby Camera");
        camGo.transform.SetParent(stage, false);
        camGo.transform.localPosition = new Vector3(0f, 1.7f, -8f);
        lobbyCam = camGo.AddComponent<Camera>();
        lobbyCam.fieldOfView = 40f;
        lobbyCam.nearClipPlane = 0.3f;
        lobbyCam.farClipPlane = 200f;
        lobbyCam.clearFlags = CameraClearFlags.SolidColor;
        lobbyCam.backgroundColor = new Color(0.10f, 0.06f, 0.20f, 1f);

        for (int i = 0; i < PhoneHub.MaxPlayers; i++)
        {
            LobbySlotView v = new LobbySlotView();
            v.root = new GameObject("Slot " + (i + 1)).transform;
            v.root.SetParent(stage, false);

            GameObject ped = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            ped.name = "Pedestal";
            Destroy(ped.GetComponent<Collider>());
            ped.transform.SetParent(v.root, false);
            ped.transform.localScale = new Vector3(2.4f, 0.08f, 2.4f);
            ped.transform.localPosition = new Vector3(0f, -0.08f, 0f);
            v.pedestalObject = ped;
            v.pedestal = ped.GetComponent<Renderer>();

            // a gold rim and a darker base under the coloured top
            MatLib.Prim(PrimitiveType.Cylinder, "Rim", ped.transform, new Vector3(0f, -1.2f, 0f), new Vector3(1.06f, 0.6f, 1.06f), GameUI.Gold, false, default(Vector3), 0.8f, 0.25f);
            MatLib.Prim(PrimitiveType.Cylinder, "Base", ped.transform, new Vector3(0f, -4f, 0f), new Vector3(0.95f, 2.4f, 0.95f), new Color(0.2f, 0.14f, 0.32f));

            views[i] = v;
        }

        BuildBackdrop();
    }

    // A dark castle hall behind the heroes: columns, banners and glowing windows.
    void BuildBackdrop()
    {
        Transform back = new GameObject("Backdrop").transform;
        back.SetParent(stage, false);
        back.localPosition = new Vector3(0f, 0f, 16f);
        Color wall = new Color(0.16f, 0.11f, 0.27f);
        Color column = new Color(0.24f, 0.18f, 0.38f);
        MatLib.Prim(PrimitiveType.Cube, "Wall", back, new Vector3(0f, 0f, 2f), new Vector3(60f, 30f, 1f), wall);
        for (int i = -4; i <= 4; i++)
        {
            float x = i * 4.5f;
            MatLib.Prim(PrimitiveType.Cylinder, "Column", back, new Vector3(x, -1f, 0.5f), new Vector3(0.9f, 9f, 0.9f), column);
            MatLib.Prim(PrimitiveType.Cube, "Capital", back, new Vector3(x, 8.1f, 0.5f), new Vector3(1.3f, 0.4f, 1.3f), GameUI.Gold, false, default(Vector3), 0.7f, 0.15f);
            if (i == 4) continue;
            float wx = x + 2.25f;
            bool banner = (i + 4) % 2 == 0;
            if (banner)
            {
                MatLib.Prim(PrimitiveType.Cube, "Banner", back, new Vector3(wx, 3.5f, 1.3f), new Vector3(1.6f, 4.5f, 0.1f), new Color(0.5f, 0.12f, 0.2f));
                MatLib.Prim(PrimitiveType.Cube, "Stripe", back, new Vector3(wx, 3.5f, 1.2f), new Vector3(0.3f, 4.5f, 0.05f), GameUI.Gold, false, default(Vector3), 0.6f, 0.2f);
            }
            else
            {
                MatLib.Prim(PrimitiveType.Cube, "Window", back, new Vector3(wx, 4f, 1.4f), new Vector3(1.2f, 3f, 0.1f), new Color(0.55f, 0.45f, 0.9f), false, default(Vector3), 0.3f, 0.9f);
                MatLib.Prim(PrimitiveType.Sphere, "Window Arch", back, new Vector3(wx, 5.5f, 1.4f), new Vector3(1.2f, 1.2f, 0.1f), new Color(0.55f, 0.45f, 0.9f), false, default(Vector3), 0.3f, 0.9f);
            }
        }
        MeshBaker.Bake(back.gameObject);
    }

    void BuildMenuUi()
    {
        menuUi = GameUI.CreateRect("Menu UI", canvas.transform, Vector2.zero, Vector2.one).gameObject;
        Transform p = menuUi.transform;

        GameUI.CreateText("Title", p, new Vector2(0.06f, 0.72f), new Vector2(0.62f, 0.95f),
                          "ROYAL RUN", 150, GameUI.Gold, TextAnchor.MiddleLeft);
        GameUI.Bind(GameUI.CreateText("Subtitle", p, new Vector2(0.065f, 0.655f), new Vector2(0.62f, 0.73f),
                          "", 42, new Color(1f, 1f, 1f, 0.85f), TextAnchor.MiddleLeft), "menu.subtitle");

        menuButtons = new MenuButton[5];
        string[] keys = { "menu.single", "menu.multi", "menu.help", null, "menu.quit" };
        System.Action[] actions = { StartSingle, StartNetwork, OpenHelp, Loc.Next, QuitGame };
        for (int i = 0; i < menuButtons.Length; i++)
        {
            float top = 0.60f - i * 0.115f;
            menuButtons[i] = GameUI.CreateButton("Button " + (i + 1), p,
                new Vector2(0.06f, top - 0.09f), new Vector2(0.46f, top), "", 38, actions[i]);
            if (keys[i] != null) GameUI.Bind(menuButtons[i].label, keys[i]);
        }
        // the language button shows the current language in that language: "ЯЗЫК: РУССКИЙ", "TIL: O‘ZBEKCHA"...
        GameUI.Bind(menuButtons[3].label, () => Loc.F("menu.lang", Loc.NativeName(Loc.Current)));
    }

    void BuildSelectUi()
    {
        selectUi = GameUI.CreateRect("Select UI", canvas.transform, Vector2.zero, Vector2.one).gameObject;
        Transform p = selectUi.transform;

        GameUI.Bind(GameUI.CreateText("Title", p, new Vector2(0f, 0.88f), new Vector2(1f, 1f),
                          "", 90, GameUI.Gold, TextAnchor.MiddleCenter), "select.title");
        selCounter = GameUI.CreateText("Counter", p, new Vector2(0.3f, 0.82f), new Vector2(0.7f, 0.88f),
                                       "", 30, new Color(1f, 1f, 1f, 0.7f), TextAnchor.MiddleCenter);

        Image card = GameUI.CreatePanel("Card", p, new Vector2(0.27f, 0.03f), new Vector2(0.73f, 0.30f), GameUI.Panel);
        selName = GameUI.CreateText("Name", card.transform, new Vector2(0.03f, 0.66f), new Vector2(0.97f, 1f),
                                    "", 58, Color.white, TextAnchor.MiddleCenter);
        selDesc = GameUI.CreateText("Desc", card.transform, new Vector2(0.05f, 0.40f), new Vector2(0.95f, 0.68f),
                                    "", 30, new Color(1f, 1f, 1f, 0.85f), TextAnchor.MiddleCenter, false);
        selStats = GameUI.CreateText("Stats", card.transform, new Vector2(0.05f, 0.03f), new Vector2(0.95f, 0.42f),
                                     "", 30, GameUI.Cyan, TextAnchor.MiddleCenter, false);

        selectButtons = new MenuButton[4];
        selectButtons[0] = GameUI.CreateButton("Prev", p, new Vector2(0.10f, 0.44f), new Vector2(0.17f, 0.58f), "<", 80, PrevCharacter);
        selectButtons[1] = GameUI.CreateButton("Next", p, new Vector2(0.83f, 0.44f), new Vector2(0.90f, 0.58f), ">", 80, NextCharacter);
        selectButtons[2] = GameUI.CreateButton("Play", p, new Vector2(0.78f, 0.04f), new Vector2(0.97f, 0.14f), "", 42, BeginSingleGame);
        selectButtons[3] = GameUI.CreateButton("Back", p, new Vector2(0.03f, 0.04f), new Vector2(0.20f, 0.12f), "", 34, EnterMenu);
        GameUI.Bind(selectButtons[2].label, "select.play");
        GameUI.Bind(selectButtons[3].label, "select.back");
    }

    void BuildLobbyUi()
    {
        lobbyUi = GameUI.CreateRect("Lobby UI", canvas.transform, Vector2.zero, Vector2.one).gameObject;
        Transform p = lobbyUi.transform;

        GameUI.CreateText("Title", p, new Vector2(0.03f, 0.89f), new Vector2(0.5f, 1f),
                          "ROYAL RUN", 84, GameUI.Gold, TextAnchor.MiddleLeft);
        GameUI.Bind(GameUI.CreateText("Subtitle", p, new Vector2(0.032f, 0.85f), new Vector2(0.5f, 0.9f),
                          "", 30, new Color(1f, 1f, 1f, 0.75f), TextAnchor.MiddleLeft), "lobby.subtitle");

        // connection steps + address
        Image steps = GameUI.CreatePanel("Steps", p, new Vector2(0.03f, 0.61f), new Vector2(0.60f, 0.85f), GameUI.Panel);
        stepsText = GameUI.CreateText("StepsText", steps.transform, new Vector2(0.03f, 0.40f), new Vector2(0.97f, 0.97f),
                                      "", 32, Color.white, TextAnchor.MiddleLeft, false);
        urlText = GameUI.CreateText("Url", steps.transform, new Vector2(0.03f, 0.02f), new Vector2(0.97f, 0.40f),
                                    "", 54, GameUI.Cyan, TextAnchor.MiddleCenter);

        // QR code
        Image qrPanel = GameUI.CreatePanel("QrPanel", p, new Vector2(0.72f, 0.58f), new Vector2(0.97f, 0.97f), GameUI.Panel);
        RectTransform qrBox = GameUI.CreateRect("QrBox", qrPanel.transform, new Vector2(0.5f, 0.57f), new Vector2(0.5f, 0.57f));
        qrBox.sizeDelta = new Vector2(310f, 310f);
        Image qrBg = qrBox.gameObject.AddComponent<Image>();
        qrBg.color = Color.white;
        qrBg.raycastTarget = false;
        qrImage = GameUI.CreateRawImage("Qr", qrBox, new Vector2(0.03f, 0.03f), new Vector2(0.97f, 0.97f));
        qrCaption = GameUI.CreateText("QrCaption", qrPanel.transform, new Vector2(0.03f, 0.01f), new Vector2(0.97f, 0.17f),
                                      Loc.T("lobby.qr"), 26, Color.white, TextAnchor.MiddleCenter, false);

        hintText = GameUI.CreateText("Hint", p, new Vector2(0.05f, 0.215f), new Vector2(0.95f, 0.27f),
                                     "", 34, Color.white, TextAnchor.MiddleCenter);

        for (int i = 0; i < PhoneHub.MaxPlayers; i++)
        {
            float x0 = i / 3f + 0.02f;
            float x1 = (i + 1) / 3f - 0.02f;
            LobbySlotView v = views[i];
            Image card = GameUI.CreatePanel("Card " + (i + 1), p, new Vector2(x0, 0.05f), new Vector2(x1, 0.205f), GameUI.Panel);
            v.strip = GameUI.CreatePanel("Strip", card.transform, new Vector2(0.03f, 0.88f), new Vector2(0.97f, 0.96f),
                                         PhoneHub.SlotColors[i], false);
            v.nameText = GameUI.CreateText("Name", card.transform, new Vector2(0f, 0.52f), new Vector2(1f, 0.88f),
                                           "", 44, Color.white, TextAnchor.MiddleCenter);
            v.charText = GameUI.CreateText("Char", card.transform, new Vector2(0f, 0.28f), new Vector2(1f, 0.55f),
                                           "", 32, Color.white, TextAnchor.MiddleCenter);
            v.statusText = GameUI.CreateText("Status", card.transform, new Vector2(0f, 0.02f), new Vector2(1f, 0.30f),
                                             "", 30, Color.white, TextAnchor.MiddleCenter);
        }

        countText = GameUI.CreateText("Countdown", canvas.transform, new Vector2(0f, 0.3f), new Vector2(1f, 0.7f),
                                      "3", 320, GameUI.Gold, TextAnchor.MiddleCenter);
        countText.gameObject.SetActive(false);
    }

    void BuildResultsUi()
    {
        RectTransform root = GameUI.CreateRect("Results UI", canvas.transform, Vector2.zero, Vector2.one);
        resultsUi = root.gameObject;

        GameUI.CreatePanel("Shade", root, new Vector2(0.27f, 0.10f), new Vector2(0.73f, 0.90f), new Color(0.06f, 0.03f, 0.13f, 0.92f));
        GameUI.Bind(GameUI.CreateText("Title", root, new Vector2(0.27f, 0.77f), new Vector2(0.73f, 0.90f),
                          "", 96, GameUI.Gold, TextAnchor.MiddleCenter), "results.title");
        resultsRows = GameUI.CreateRect("Rows", root, new Vector2(0.30f, 0.38f), new Vector2(0.70f, 0.76f));
        resultsHint = GameUI.CreateText("Hint", root, new Vector2(0.28f, 0.23f), new Vector2(0.72f, 0.29f),
                                        "", 26, new Color(1f, 1f, 1f, 0.7f), TextAnchor.MiddleCenter, false);

        resultsButtons = new MenuButton[3];
        string[] names = { "btn.restart", "btn.addPlayers", "btn.mainMenu" };
        System.Action[] acts = { RestartGame, ResultsSecondAction, EnterMenu };
        for (int i = 0; i < 3; i++)
        {
            float x0 = 0.285f + i * 0.145f;
            resultsButtons[i] = GameUI.CreateButton("Button " + (i + 1), root,
                new Vector2(x0, 0.12f), new Vector2(x0 + 0.135f, 0.215f), Loc.T(names[i]), 28, acts[i]);
        }
        resultsUi.SetActive(false);
    }

    void BuildPauseUi()
    {
        RectTransform root = GameUI.CreateRect("Pause UI", canvas.transform, Vector2.zero, Vector2.one);
        pauseUi = root.gameObject;

        GameUI.CreatePanel("Panel", root, new Vector2(0.34f, 0.14f), new Vector2(0.66f, 0.86f), new Color(0.06f, 0.03f, 0.13f, 0.92f));
        GameUI.Bind(GameUI.CreateText("Title", root, new Vector2(0.34f, 0.72f), new Vector2(0.66f, 0.86f),
                          "", 90, GameUI.Gold, TextAnchor.MiddleCenter), "pause.title");

        pauseButtons = new MenuButton[4];
        string[] names = { "btn.resume", "btn.restart", "btn.addPlayers", "btn.mainMenu" };
        System.Action[] acts = { ResumeGame, RestartGame, ResultsSecondAction, EnterMenu };
        for (int i = 0; i < 4; i++)
        {
            float top = 0.68f - i * 0.135f;
            pauseButtons[i] = GameUI.CreateButton("Button " + (i + 1), root,
                new Vector2(0.37f, top - 0.105f), new Vector2(0.63f, top), Loc.T(names[i]), 36, acts[i]);
        }
        pauseUi.SetActive(false);
    }

    void BuildHelpUi()
    {
        RectTransform root = GameUI.CreateRect("Help UI", canvas.transform, Vector2.zero, Vector2.one);
        helpUi = root.gameObject;

        GameUI.CreatePanel("Dim", root, Vector2.zero, Vector2.one, new Color(0f, 0f, 0f, 0.7f), false);
        GameUI.CreatePanel("Panel", root, new Vector2(0.10f, 0.05f), new Vector2(0.90f, 0.95f), new Color(0.10f, 0.06f, 0.20f, 0.98f));
        GameUI.Bind(GameUI.CreateText("Title", root, new Vector2(0.10f, 0.86f), new Vector2(0.90f, 0.95f),
                          "", 62, GameUI.Gold, TextAnchor.MiddleCenter), "help.title");
        helpText = GameUI.CreateText("Text", root, new Vector2(0.13f, 0.17f), new Vector2(0.87f, 0.86f),
                                     "", 29, Color.white, TextAnchor.UpperLeft, false);

        helpButtons = new MenuButton[1];
        helpButtons[0] = GameUI.CreateButton("Close", root, new Vector2(0.38f, 0.07f), new Vector2(0.62f, 0.15f),
                                             "", 38, CloseHelp);
        GameUI.Bind(helpButtons[0].label, "btn.close");
        helpUi.SetActive(false);
    }

    void BuildFooter()
    {
        footerText = GameUI.CreateText("Footer", canvas.transform, new Vector2(0.02f, 0f), new Vector2(0.98f, 0.04f),
                                       "", 24, new Color(1f, 1f, 1f, 0.65f), TextAnchor.MiddleCenter);
    }

    void SetFooter(string key)
    {
        footerKey = key;
        footerText.text = string.IsNullOrEmpty(key) ? "" : Loc.T(key);
    }

    // The language was switched (the LANGUAGE button in the menu).
    void OnLanguageChanged()
    {
        GameUI.RefreshBindings();
        SetFooter(footerKey);
        qrCaption.text = Loc.T("lobby.qr");
        qrShownUrl = null;
        if (phase == Phase.SingleSelect) RefreshSelect();
        if (phase == Phase.Lobby || phase == Phase.Countdown) RefreshLobbyUi();
        if (helpOpen) helpText.text = BuildHelpText();
        hub.BroadcastLanguage();
    }

    // ============================================================
    //  Every frame
    // ============================================================

    void Update()
    {
        if (helpOpen) { UpdateHelp(); return; }
        if (paused) { UpdatePause(); return; }

        if (GameInput.Down(GKey.F1) && phase != Phase.Playing) { OpenHelp(); return; }
        if (GameInput.Down(GKey.Escape))
        {
            if (phase == Phase.Menu)
            {
#if !UNITY_EDITOR
                QuitGame();
#endif
            }
            else if (phase == Phase.Playing) OpenPause();
            else EnterMenu();
            return;
        }

        switch (phase)
        {
            case Phase.Menu: UpdateMenu(); break;
            case Phase.SingleSelect: UpdateSingleSelect(); break;
            case Phase.Lobby: UpdateLobby(); break;
            case Phase.Countdown: UpdateCountdown(); break;
            case Phase.Playing: UpdatePlaying(); break;
            case Phase.Results: UpdateResults(); break;
        }
    }

    void UpdateMenu()
    {
        LayoutStage();
        GameUI.UpdateButtons(menuButtons, ref menuSelected, true);
    }

    void UpdateSingleSelect()
    {
        LayoutStage();

        if (GameInput.Down(GKey.Left) || GameInput.Down(GKey.A)) { PrevCharacter(); Sfx.Play(SynthAudio.Click, 0.5f); }
        if (GameInput.Down(GKey.Right) || GameInput.Down(GKey.D)) { NextCharacter(); Sfx.Play(SynthAudio.Click, 0.5f); }
        if (GameInput.Down(GKey.Enter) || GameInput.Down(GKey.Space)) { BeginSingleGame(); return; }
        GameUI.UpdateButtons(selectButtons, ref selectSelected, false);
    }

    void UpdateLobby()
    {
        if (GameInput.Down(GKey.Tab) && hub.Urls.Count > 1)
        {
            hub.UrlIndex = (hub.UrlIndex + 1) % hub.Urls.Count;
            RefreshLobbyUi();
        }
        if (GameInput.Down(GKey.K)) hub.AddKeyboardPlayer();

        // keyboard players: L removes the last one, Enter toggles READY for all of them,
        // each one flips through the heroes with their own left/right keys
        PhonePlayer lastKeyboard = FindLastKeyboardPlayer();
        if (lastKeyboard != null)
        {
            if (GameInput.Down(GKey.L)) hub.RemovePlayer(lastKeyboard);
            else if (GameInput.Down(GKey.Enter))
            {
                bool allReady = true;
                foreach (PhonePlayer p in hub.Slots) if (p != null && p.isKeyboard && !p.ready) allReady = false;
                foreach (PhonePlayer p in hub.Slots) if (p != null && p.isKeyboard) p.ready = !allReady;
                OnHubChanged();
            }
            else
            {
                foreach (PhonePlayer p in hub.Slots)
                {
                    if (p == null || !p.isKeyboard || p.ready) continue;
                    int step = GameInput.StepPressed(p.keyboardScheme);
                    if (step != 0 && CycleCharacter(p, step)) OnHubChanged();
                }
            }
        }

        LayoutStage();

        if (hub.PlayerCount > 0 && AllReady()) BeginCountdown();
    }

    void UpdateCountdown()
    {
        LayoutStage();

        if (!AllReady() || hub.PlayerCount == 0)
        {
            EnterLobby();
            return;
        }

        countdownLeft -= Time.deltaTime;
        int n = Mathf.CeilToInt(countdownLeft);
        if (n != lastCountShown && n > 0)
        {
            lastCountShown = n;
            countText.text = n.ToString();
            hub.SendToAll("{\"t\":\"count\",\"n\":" + n + "}");
            Sfx.Play(SynthAudio.Beep, 0.7f);
        }

        // the digit "pops" and shrinks every second
        float frac = countdownLeft - Mathf.Floor(countdownLeft);
        countText.transform.localScale = Vector3.one * (1f + 0.5f * frac);

        if (countdownLeft <= 0f)
        {
            Sfx.Play(SynthAudio.Go, 0.7f);
            StartGame();
        }
    }

    void UpdatePlaying()
    {
        bool allDone = worlds.Count > 0;
        foreach (PlayerWorld w in worlds) if (!w.Finished) { allDone = false; break; }

        if (!allDone) { finishDelay = 0f; return; }

        finishDelay += Time.deltaTime;
        if (finishDelay >= 2.5f) ShowResults();
    }

    void UpdateResults()
    {
        resultsTimer += Time.deltaTime;

        // the winner on a gold podium to the left of the table
        LobbySlotView winner = views[0];
        if (winner.root.gameObject.activeSelf)
        {
            winner.root.position = lobbyCam.ViewportToWorldPoint(new Vector3(0.14f, 0.18f, 8f));
            winner.root.localScale = Vector3.one * 1.25f;
            winner.root.rotation = Quaternion.Euler(0f, 180f + Mathf.Sin(Time.time * 1.2f) * 20f, 0f);
        }

        // Enter / Space - the selected button (RESTART by default), L - add players
        if (GameInput.Down(GKey.L)) { ResultsSecondAction(); return; }
        if (GameUI.UpdateButtons(resultsButtons, ref resultsSelected, true)) return;

        if (mode == Mode.Network && AllPhonesWantAgain()) { RestartGame(); return; }
        if (resultsTimer > resultsTimeout) ResultsSecondAction();
    }

    void UpdatePause()
    {
        if (GameInput.Down(GKey.Escape)) { ResumeGame(); return; }
        GameUI.UpdateButtons(pauseButtons, ref pauseSelected, true);
    }

    void UpdateHelp()
    {
        helpRefresh -= Time.deltaTime;
        if (helpRefresh <= 0f)
        {
            helpRefresh = 0.5f;
            helpText.text = BuildHelpText();
        }

        if (GameInput.Down(GKey.Escape) || GameInput.Down(GKey.F1) || GameInput.Down(GKey.Enter))
        {
            CloseHelp();
            return;
        }
        GameUI.UpdateButtons(helpButtons, ref helpSelected, false);
    }

    // ============================================================
    //  Switching between screens
    // ============================================================

    void HideAllScreens()
    {
        menuUi.SetActive(false);
        selectUi.SetActive(false);
        lobbyUi.SetActive(false);
        resultsUi.SetActive(false);
        if (pauseUi != null) pauseUi.SetActive(false);
        countText.gameObject.SetActive(false);
        countText.transform.localScale = Vector3.one;
    }

    void ClearWorlds()
    {
        paused = false;
        Time.timeScale = 1f;
        if (pauseUi != null) pauseUi.SetActive(false);
        foreach (PlayerWorld w in worlds) if (w != null) Destroy(w.gameObject);
        worlds.Clear();
    }

    void EnterMenu()
    {
        ClearWorlds();
        HideAllScreens();

        // phones that were in the game move to the waiting screen
        if (hub.Enabled) hub.SendToAll(PhoneHub.MessageJson("wait", Loc.T("phone.waitReturned")));
        hub.Enabled = false;
        hub.ResetPlayers();

        menuUi.SetActive(true);
        stage.gameObject.SetActive(true);
        phase = Phase.Menu;
        SetFooter("footer.menu");

        ShowModel(views[1], 0);
    }

    void StartSingle()
    {
        mode = Mode.Single;
        hub.Enabled = false;
        hub.ResetPlayers();

        PhonePlayer p = hub.AddKeyboardPlayer();
        if (p != null)
        {
            p.name = Loc.T("player.single");
            p.keyboardScheme = GameInput.SchemeSolo;
            p.character = 0;
            p.ready = true;
        }
        EnterSingleSelect();
    }

    void EnterSingleSelect()
    {
        ClearWorlds();
        HideAllScreens();
        selectUi.SetActive(true);
        stage.gameObject.SetActive(true);
        phase = Phase.SingleSelect;
        selectSelected = 2;
        SetFooter("footer.select");
        RefreshSelect();
    }

    void RefreshSelect()
    {
        PhonePlayer p = hub.Slots[0];
        if (p == null) return;

        CharacterDef def = CharacterCatalog.All[p.character];
        selName.text = def.Name;
        selName.color = Color.Lerp(Color.white, def.tint, 0.85f);
        selDesc.text = def.Description;
        selStats.text = string.Join("\n", def.StatLines().ToArray());
        selCounter.text = (p.character + 1) + " / " + CharacterCatalog.Count;
        ShowModel(views[1], p.character);
    }

    void PrevCharacter()
    {
        PhonePlayer p = hub.Slots[0];
        if (p == null) return;
        p.character = (p.character - 1 + CharacterCatalog.Count) % CharacterCatalog.Count;
        RefreshSelect();
    }

    void NextCharacter()
    {
        PhonePlayer p = hub.Slots[0];
        if (p == null) return;
        p.character = (p.character + 1) % CharacterCatalog.Count;
        RefreshSelect();
    }

    void BeginSingleGame()
    {
        if (hub.Slots[0] == null) return;
        hub.AcceptNewPlayers = false;
        StartGame();
    }

    void StartNetwork()
    {
        mode = Mode.Network;
        hub.ResetPlayers();
        hub.Enabled = true;
        EnterLobby();
    }

    void EnterLobby()
    {
        EnterLobby(false);
    }

    // keepReady = true: everyone stays "ready" and the game starts the countdown at once (restart with the same players).
    void EnterLobby(bool keepReady)
    {
        ClearWorlds();
        HideAllScreens();

        // prepare the players for a new round
        hub.AcceptNewPlayers = true;
        for (int i = 0; i < hub.Slots.Length; i++)
        {
            PhonePlayer p = hub.Slots[i];
            if (p == null) continue;
            if (!p.isKeyboard && !p.connected) { hub.Slots[i] = null; continue; }
            if (!keepReady) p.ready = false;
            p.wantsAgain = false;
            p.move = Vector2.zero;
        }

        lobbyUi.SetActive(true);
        stage.gameObject.SetActive(true);
        phase = Phase.Lobby;
        SetFooter("footer.lobby");

        RefreshLobbyUi();
        PushLobbyAll();
    }

    void BeginCountdown()
    {
        phase = Phase.Countdown;
        countdownLeft = countdownSeconds;
        lastCountShown = -1;
        countText.gameObject.SetActive(true);
    }

    void StartGame()
    {
        hub.AcceptNewPlayers = false;
        if (mode == Mode.Network) NormalizeKeyboardSchemes();

        List<PhonePlayer> players = new List<PhonePlayer>();
        foreach (PhonePlayer p in hub.Slots) if (p != null) players.Add(p);
        if (players.Count == 0) { EnterMenu(); return; }

        HideAllScreens();
        stage.gameObject.SetActive(false);
        SetFooter(null);

        int n = players.Count;
        for (int i = 0; i < n; i++)
            worlds.Add(PlayerWorld.Create(i, n, players[i], assets, hub));

        finishDelay = 0f;
        phase = Phase.Playing;
    }

    void ShowResults()
    {
        phase = Phase.Results;
        resultsTimer = 0f;

        List<PlayerWorld> ranking = Ranking();
        BuildResultRows(ranking);
        resultsButtons[0].label.text = Loc.T("btn.restart");
        resultsButtons[1].label.text = Loc.T(mode == Mode.Single ? "btn.changeHero" : "btn.addPlayers");
        resultsButtons[2].label.text = Loc.T("btn.mainMenu");
        resultsSelected = 0;
        resultsHint.text = Loc.T(mode == Mode.Single ? "results.hintSingle" : "results.hintNet");

        // the record of the single-player game is kept between launches
        if (mode == Mode.Single && ranking.Count > 0)
        {
            int best = PlayerPrefs.GetInt(BestScoreKey, 0);
            int score = ranking[0].Score;
            if (score > best)
            {
                PlayerPrefs.SetInt(BestScoreKey, score);
                PlayerPrefs.Save();
                resultsHint.text = "<color=#ffd54f><b>" + Loc.T("results.newBest") + "</b></color>\n" + resultsHint.text;
            }
            else
            {
                resultsHint.text = Loc.F("results.best", best) + "\n" + resultsHint.text;
            }
        }

        resultsUi.SetActive(true);
        SetFooter(null);

        // World cameras draw only their own strip of the screen and "cut" the shared UI.
        // On the results screen we turn them off and show the full-screen lobby camera with a dark background.
        ShowCleanBackground();
        if (ranking.Count > 0)
        {
            LobbySlotView v = views[0];
            v.root.gameObject.SetActive(true);
            ShowModel(v, ranking[0].Owner.character);
            v.pedestal.material.color = GameUI.Gold;
            SetRigState(v, true);
            Sfx.Play(SynthAudio.Checkpoint, 0.6f);
        }

        PushResultsAll();
    }

    List<PlayerWorld> Ranking()
    {
        List<PlayerWorld> ranking = new List<PlayerWorld>(worlds);
        ranking.Sort(delegate (PlayerWorld a, PlayerWorld b) { return b.Score.CompareTo(a.Score); });
        return ranking;
    }

    void BuildResultRows(List<PlayerWorld> ranking)
    {
        foreach (Transform child in resultsRows) Destroy(child.gameObject);

        Color[] medal = { new Color(1f, 0.84f, 0.2f), new Color(0.8f, 0.82f, 0.88f), new Color(0.85f, 0.55f, 0.3f) };
        for (int i = 0; i < ranking.Count; i++)
        {
            float yMax = 1f - i * 0.34f;
            float yMin = yMax - 0.30f;
            PlayerWorld w = ranking[i];
            Color slotColor = PhoneHub.SlotColors[w.Owner.slot];

            Image row = GameUI.CreatePanel("Row " + (i + 1), resultsRows, new Vector2(0f, yMin), new Vector2(1f, yMax),
                                           new Color(slotColor.r * 0.45f, slotColor.g * 0.45f, slotColor.b * 0.45f, 0.9f));
            GameUI.CreateText("Rank", row.transform, new Vector2(0.02f, 0f), new Vector2(0.17f, 1f),
                              (i + 1).ToString(), 64, medal[Mathf.Min(i, 2)], TextAnchor.MiddleCenter);
            GameUI.CreateText("Name", row.transform, new Vector2(0.18f, 0f), new Vector2(0.68f, 1f),
                              w.Owner.name + "\n<size=26>" + w.Character.Name + "  ·  " + Loc.F("hud.distance", w.Distance) + "</size>", 42, Color.white, TextAnchor.MiddleLeft);
            GameUI.CreateText("Score", row.transform, new Vector2(0.66f, 0f), new Vector2(0.97f, 1f),
                              w.Score.ToString(), 56, GameUI.Gold, TextAnchor.MiddleRight);
        }
    }

    // ============================================================
    //  Pause, restart, adding players
    // ============================================================

    // World cameras draw only their own strip of the screen and "cut" the shared UI.
    // So for the pause menu and the results we turn them off and show a full-screen camera with a dark background.
    void ShowCleanBackground()
    {
        foreach (PlayerWorld w in worlds) if (w != null) w.SetViewVisible(false);
        stage.gameObject.SetActive(true);
        foreach (LobbySlotView v in views) v.root.gameObject.SetActive(false);
    }

    void OpenPause()
    {
        if (phase != Phase.Playing || paused) return;
        paused = true;
        Time.timeScale = 0f;
        ShowCleanBackground();

        pauseButtons[0].label.text = Loc.T("btn.resume");
        pauseButtons[1].label.text = Loc.T("btn.restart");
        pauseButtons[2].label.text = Loc.T(mode == Mode.Single ? "btn.changeHero" : "btn.addPlayers");
        pauseButtons[3].label.text = Loc.T("btn.mainMenu");
        pauseSelected = 0;
        pauseUi.SetActive(true);
        SetFooter("footer.pause");
        hub.SendToAll("{\"t\":\"pause\",\"on\":true}");
    }

    void ResumeGame()
    {
        if (!paused) return;
        paused = false;
        Time.timeScale = 1f;
        pauseUi.SetActive(false);
        stage.gameObject.SetActive(false);
        foreach (PlayerWorld w in worlds) if (w != null) w.SetViewVisible(true);
        SetFooter(null);
        hub.SendToAll("{\"t\":\"pause\",\"on\":false}");
    }

    // Start the round again with the same players and heroes.
    void RestartGame()
    {
        if (mode == Mode.Single)
        {
            ClearWorlds();
            HideAllScreens();
            if (hub.Slots[0] == null) { EnterMenu(); return; }
            StartGame();
        }
        else
        {
            hub.SendToAll("{\"t\":\"pause\",\"on\":false}");
            EnterLobby(true);      // everyone is already "ready" - the countdown will start by itself
        }
    }

    // "ADD PLAYERS": back to the lobby where new players can join (in single-player mode: hero select).
    void ResultsSecondAction()
    {
        if (mode == Mode.Single) EnterSingleSelect();
        else
        {
            hub.SendToAll("{\"t\":\"pause\",\"on\":false}");
            EnterLobby(false);
        }
    }

    // ============================================================
    //  Help window
    // ============================================================

    void OpenHelp()
    {
        helpOpen = true;
        helpRefresh = 0f;
        helpSelected = 0;
        helpUi.SetActive(true);
        helpText.text = BuildHelpText();
    }

    void CloseHelp()
    {
        helpOpen = false;
        helpUi.SetActive(false);
    }

    string BuildHelpText()
    {
        StringBuilder sb = new StringBuilder();
        sb.Append(Loc.T("help.now")).Append('\n');

        if (!hub.ServerOk)
        {
            sb.Append(Loc.T("help.serverFail")).Append('\n');
        }
        else
        {
            sb.Append(Loc.F("help.portLine", hub.Port, string.Join("   ", hub.Urls.ToArray()))).Append('\n');
            sb.Append(Loc.F("help.statsLine", hub.HttpHits, hub.WsTotal, hub.ClientCount)).Append('\n');

            if (hub.HttpHits == 0) sb.Append(Loc.T("help.noHits")).Append('\n');
            else if (hub.WsTotal == 0) sb.Append(Loc.T("help.noWs")).Append('\n');
            else sb.Append(Loc.T("help.ok")).Append('\n');
        }

        sb.Append('\n').Append(Loc.T("help.ifCant")).Append('\n');
        sb.Append(Loc.T("help.s1")).Append('\n');
        sb.Append(Loc.T("help.s2")).Append('\n');
        sb.Append(Loc.T("help.s3")).Append('\n');
        sb.Append("      <color=#80eaff>netsh advfirewall firewall add rule name=\"Royal Run\" dir=in action=allow protocol=TCP localport=8080-8090</color>\n");
        sb.Append(Loc.T("help.s4")).Append('\n');
        sb.Append(Loc.T("help.s5")).Append('\n');
        sb.Append(Loc.T("help.s6"));
        return sb.ToString();
    }

    // ============================================================
    //  Events from phones
    // ============================================================

    void OnHubChanged()
    {
        if (phase == Phase.Lobby || phase == Phase.Countdown)
        {
            NormalizeKeyboardSchemes();
            RefreshLobbyUi();
            PushLobbyAll();
        }
        else
        {
            PushStateAll();   // a phone reconnected in the middle of a game
        }
    }

    bool AllPhonesWantAgain()
    {
        int phones = 0;
        foreach (PhonePlayer p in hub.Slots)
        {
            if (p == null || p.isKeyboard || !p.connected) continue;
            phones++;
            if (!p.wantsAgain) return false;
        }
        return phones > 0;
    }

    bool AllReady()
    {
        foreach (PhonePlayer p in hub.Slots)
            if (p != null && !p.ready) return false;
        return true;
    }

    PhonePlayer FindLastKeyboardPlayer()
    {
        PhonePlayer last = null;
        foreach (PhonePlayer p in hub.Slots) if (p != null && p.isKeyboard) last = p;
        return last;
    }

    // Next free hero for a keyboard player (heroes taken by others are skipped).
    bool CycleCharacter(PhonePlayer p, int step)
    {
        int n = CharacterCatalog.Count;
        for (int k = 1; k < n; k++)
        {
            int c = ((p.character + step * k) % n + n) % n;
            if (!hub.IsCharacterTaken(c, p))
            {
                p.character = c;
                Sfx.Play(SynthAudio.Click, 0.5f);
                return true;
            }
        }
        return false;
    }

    // One keyboard player uses WASD and the arrows; several share the keyboard: WASD / arrows / numpad.
    void NormalizeKeyboardSchemes()
    {
        int count = 0;
        foreach (PhonePlayer p in hub.Slots) if (p != null && p.isKeyboard) count++;
        int next = 0;
        foreach (PhonePlayer p in hub.Slots)
        {
            if (p == null || !p.isKeyboard) continue;
            p.keyboardScheme = count == 1 ? GameInput.SchemeSolo : Mathf.Min(next++, GameInput.SchemeCount - 1);
        }
    }

    static string SchemeLabel(int scheme)
    {
        switch (scheme)
        {
            case 0: return Loc.T("keys.wasd");
            case 1: return Loc.T("keys.arrows");
            case 2: return Loc.T("keys.numpad");
            default: return Loc.T("keys.solo");
        }
    }

    void QuitGame()
    {
#if UNITY_EDITOR
        UnityEditor.EditorApplication.isPlaying = false;   // in the editor: stop Play Mode
#else
        Application.Quit();
#endif
    }

    // ============================================================
    //  The hero stage (menu, select, lobby)
    // ============================================================

    void ShowModel(LobbySlotView v, int character)
    {
        if (character == v.shownCharacter) return;

        if (v.model != null) Destroy(v.model);
        v.model = null;
        v.shownCharacter = character;
        if (character < 0) return;

        v.model = Instantiate(assets.ModelFor(character), v.root);
        v.model.transform.localPosition = Vector3.zero;
        v.model.transform.localRotation = Quaternion.identity;
        v.model.transform.localScale = Vector3.one;
        ModelTint.Apply(v.model, CharacterCatalog.All[character].tint);
        Animator anim = v.model.GetComponentInChildren<Animator>();
        if (anim != null) anim.applyRootMotion = false;
        SetRigState(v, false);
    }

    static void SetRigState(LobbySlotView v, bool cheering)
    {
        if (v.model == null) return;
        CharacterRig rig = v.model.GetComponentInChildren<CharacterRig>();
        if (rig == null) return;
        rig.showcase = true;
        rig.running = false;
        rig.airborne = false;
        rig.cheering = cheering;
    }

    // Put the heroes in the right places on the screen however the window size changes.
    void LayoutStage()
    {
        float t = Time.time;

        if (phase == Phase.Menu || phase == Phase.SingleSelect)
        {
            bool menu = phase == Phase.Menu;
            for (int i = 0; i < views.Length; i++)
            {
                bool show = (i == 1);
                views[i].root.gameObject.SetActive(show);
            }
            Vector2 vp = menu ? new Vector2(0.76f, 0.16f) : new Vector2(0.5f, 0.36f);
            float scale = menu ? 1.7f : 1.4f;
            views[1].pedestalObject.SetActive(true);
            views[1].pedestal.material.color = menu ? GameUI.Gold : new Color(0.5f, 0.4f, 0.8f);
            views[1].root.position = lobbyCam.ViewportToWorldPoint(new Vector3(vp.x, vp.y, 8f));
            views[1].root.localScale = Vector3.one * scale;
            views[1].root.rotation = Quaternion.Euler(0f, 180f + Mathf.Sin(t * 1.1f) * 28f, 0f);
            return;
        }

        for (int i = 0; i < views.Length; i++)
        {
            views[i].root.gameObject.SetActive(true);
            views[i].pedestalObject.SetActive(true);
            views[i].root.localScale = Vector3.one * 1.05f;
            views[i].root.position = lobbyCam.ViewportToWorldPoint(new Vector3((i + 0.5f) / 3f, 0.27f, 8f));
            views[i].root.rotation = Quaternion.Euler(0f, 180f + Mathf.Sin(t * 1.3f + i) * 22f, 0f);
        }
    }

    // ============================================================
    //  Lobby: refreshing the screen
    // ============================================================

    void RefreshLobbyUi()
    {
        if (!hub.ServerOk)
        {
            stepsText.text = Loc.T("lobby.serverFail");
            urlText.text = "";
            qrImage.gameObject.SetActive(false);
        }
        else
        {
            stepsText.text = Loc.T("lobby.steps");
            urlText.text = hub.CurrentUrl;
            urlText.fontSize = 54;
            RefreshQr();
        }

        int count = 0, ready = 0;
        for (int i = 0; i < PhoneHub.MaxPlayers; i++)
        {
            PhonePlayer p = hub.Slots[i];
            LobbySlotView v = views[i];
            Color slotColor = PhoneHub.SlotColors[i];

            if (p != null) { count++; if (p.ready) ready++; }

            v.pedestal.material.color = p != null ? slotColor : new Color(0.25f, 0.25f, 0.28f);
            ShowModel(v, p != null ? p.character : -1);
            SetRigState(v, p != null && p.ready);

            if (p == null)
            {
                v.nameText.text = Loc.T("lobby.free");
                v.nameText.color = new Color(1f, 1f, 1f, 0.45f);
                v.charText.text = Loc.T("lobby.waitingPhone");
                v.statusText.text = "";
                v.strip.color = new Color(1f, 1f, 1f, 0.15f);
            }
            else
            {
                v.nameText.text = p.name;
                v.nameText.color = slotColor;
                v.charText.text = p.character < 0 ? Loc.T("lobby.choosing") : CharacterCatalog.All[p.character].Name;
                if (p.isKeyboard) v.charText.text += "  <size=22>(" + SchemeLabel(p.keyboardScheme) + ")</size>";
                v.statusText.text = p.ready ? "<color=#8bff8b>" + Loc.T("lobby.ready") + "</color>" : Loc.T("lobby.notReady");
                v.strip.color = slotColor;
            }
        }

        hintText.text = count == 0
            ? Loc.T("lobby.hintEmpty")
            : Loc.F("lobby.hintCount", ready, count);
    }

    void RefreshQr()
    {
        string url = hub.CurrentUrl;
        if (url == qrShownUrl && qrImage.gameObject.activeSelf) return;
        qrShownUrl = url;

        bool[,] m = QrCode.Encode(url);
        if (m == null) { qrImage.gameObject.SetActive(false); return; }

        int n = m.GetLength(0);
        int quiet = 2;                          // white border around the code
        int size = n + quiet * 2;
        Texture2D tex = new Texture2D(size, size, TextureFormat.RGBA32, false);
        tex.filterMode = FilterMode.Point;      // sharp squares, no blurring
        tex.wrapMode = TextureWrapMode.Clamp;

        Color dark = new Color(0.08f, 0.04f, 0.16f);
        for (int y = 0; y < size; y++)
        {
            for (int x = 0; x < size; x++)
            {
                int mx = x - quiet;
                int my = size - 1 - y - quiet;   // in a texture the Y axis points upwards
                bool isDark = mx >= 0 && my >= 0 && mx < n && my < n && m[my, mx];
                tex.SetPixel(x, y, isDark ? dark : Color.white);
            }
        }
        tex.Apply();

        if (qrTexture != null) Destroy(qrTexture);
        qrTexture = tex;
        qrImage.texture = tex;
        qrImage.gameObject.SetActive(true);

        qrCaption.text = hub.Urls.Count > 1
            ? Loc.F("lobby.qrMany", (hub.UrlIndex % hub.Urls.Count) + 1, hub.Urls.Count)
            : Loc.T("lobby.qr");
    }

    // ============================================================
    //  Messages to phones
    // ============================================================

    void PushStateAll()
    {
        switch (phase)
        {
            case Phase.Lobby: PushLobbyAll(); break;
            case Phase.Countdown: hub.SendToAll("{\"t\":\"count\",\"n\":" + Mathf.Max(1, lastCountShown) + "}"); break;
            case Phase.Playing: foreach (PlayerWorld w in worlds) w.ForcePush(); break;
            case Phase.Results: PushResultsAll(); break;
        }
    }

    void PushLobbyAll()
    {
        int count = 0, ready = 0;
        foreach (PhonePlayer p in hub.Slots)
        {
            if (p == null) continue;
            count++;
            if (p.ready) ready++;
        }

        foreach (PhonePlayer p in hub.Slots)
        {
            if (p == null || p.isKeyboard) continue;

            StringBuilder sb = new StringBuilder();
            sb.Append("{\"t\":\"lobby\",\"char\":").Append(p.character);
            sb.Append(",\"ready\":").Append(p.ready ? "true" : "false");
            sb.Append(",\"players\":").Append(count);
            sb.Append(",\"readyCount\":").Append(ready);
            sb.Append(",\"taken\":[");
            for (int i = 0; i < CharacterCatalog.Count; i++)
            {
                if (i > 0) sb.Append(',');
                sb.Append(hub.IsCharacterTaken(i, p) ? "true" : "false");
            }
            sb.Append("]}");
            hub.SendTo(p, sb.ToString());
        }
    }

    void PushResultsAll()
    {
        List<PlayerWorld> ranking = Ranking();

        StringBuilder list = new StringBuilder("[");
        for (int i = 0; i < ranking.Count; i++)
        {
            if (i > 0) list.Append(',');
            list.Append("{\"name\":").Append(PhoneHub.Quote(ranking[i].Owner.name));
            list.Append(",\"score\":").Append(ranking[i].Score);
            list.Append(",\"slot\":").Append(ranking[i].Owner.slot).Append('}');
        }
        list.Append(']');

        for (int i = 0; i < ranking.Count; i++)
        {
            string json = "{\"t\":\"results\",\"rank\":" + (i + 1) + ",\"list\":" + list + "}";
            hub.SendTo(ranking[i].Owner, json);
        }
    }
}
