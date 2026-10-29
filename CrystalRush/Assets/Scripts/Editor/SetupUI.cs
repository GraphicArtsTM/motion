using UnityEditor;
using UnityEngine;
using UnityEngine.UI;

/// <summary>
/// Setup step: the user interface. Builds the GameUI prefab (HUD, touch controls, panels)
/// and the main menu canvas. Canvas size 1920x1080, scales with the screen.
/// </summary>
public static partial class CrystalRushSetup
{
    static readonly Color PanelColor = new Color(0.08f, 0.08f, 0.18f, 0.96f);
    static readonly Color DimColor = new Color(0f, 0f, 0.03f, 0.65f);
    static readonly Color Gold = new Color(1f, 0.82f, 0.3f);
    static readonly Color ButtonBlue = new Color(0.25f, 0.35f, 0.75f);
    static readonly Color ButtonGreen = new Color(0.2f, 0.7f, 0.45f);
    static readonly Color ButtonGrey = new Color(0.3f, 0.32f, 0.45f);
    static readonly Color ButtonGold = new Color(0.95f, 0.65f, 0.15f);

    static GameObject gameUIPrefab;

    // ================================================================ GameUI prefab (levels)

    static void CreateGameUIPrefab()
    {
        GameObject root = NewCanvas("GameUI", 10);
        GameUI ui = root.AddComponent<GameUI>();
        Transform canvas = root.transform;

        // ---------- HUD ----------
        RectTransform hud = Stretch(NewRect("HUD", canvas));
        Image topBar = NewImage("TopBar", hud, roundedSprite, new Color(0f, 0f, 0.05f, 0.45f));
        Anchor(topBar.rectTransform, new Vector2(0f, 1f), new Vector2(1f, 1f), new Vector2(0.5f, 1f), new Vector2(0f, -10f), new Vector2(-40f, 100f));

        Text level = NewText("LevelText", topBar.transform, "", 38, Gold, TextAnchor.MiddleLeft);
        AnchorAt(level.rectTransform, new Vector2(0f, 0.5f), new Vector2(190f, 0f), new Vector2(330f, 90f));
        Text lives = NewText("LivesText", topBar.transform, "", 38, new Color(1f, 0.5f, 0.6f), TextAnchor.MiddleCenter);
        AnchorAt(lives.rectTransform, new Vector2(0.27f, 0.5f), Vector2.zero, new Vector2(320f, 90f));
        Text crystals = NewText("CrystalsText", topBar.transform, "", 38, new Color(1f, 0.55f, 0.95f), TextAnchor.MiddleCenter);
        AnchorAt(crystals.rectTransform, new Vector2(0.46f, 0.5f), Vector2.zero, new Vector2(380f, 90f));
        Text time = NewText("TimeText", topBar.transform, "", 38, Color.white, TextAnchor.MiddleCenter);
        AnchorAt(time.rectTransform, new Vector2(0.64f, 0.5f), Vector2.zero, new Vector2(300f, 90f));
        Text score = NewText("ScoreText", topBar.transform, "", 38, new Color(0.6f, 0.95f, 1f), TextAnchor.MiddleCenter);
        AnchorAt(score.rectTransform, new Vector2(0.8f, 0.5f), Vector2.zero, new Vector2(300f, 90f));

        Button pause = NewButton("PauseButton", topBar.transform, null, "II", ButtonGrey, new Vector2(84f, 80f), 40);
        AnchorAt((RectTransform)pause.transform, new Vector2(1f, 0.5f), new Vector2(-55f, 0f), new Vector2(84f, 80f));

        Text message = NewText("MessageText", hud, "", 54, Gold, TextAnchor.MiddleCenter);
        AnchorAt(message.rectTransform, new Vector2(0.5f, 0.74f), Vector2.zero, new Vector2(1500f, 110f));
        message.gameObject.AddComponent<Outline>().effectColor = new Color(0f, 0f, 0f, 0.8f);

        // ---------- Touch controls (bottom corners, ads never cover them) ----------
        RectTransform touch = Stretch(NewRect("TouchControls", canvas));

        Image joystickBase = NewImage("Joystick", touch, circleSprite, new Color(1f, 1f, 1f, 0.14f));
        AnchorAt(joystickBase.rectTransform, Vector2.zero, new Vector2(250f, 250f), new Vector2(320f, 320f));
        Image handle = NewImage("Handle", joystickBase.transform, circleSprite, new Color(0.6f, 0.95f, 1f, 0.55f));
        AnchorAt(handle.rectTransform, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(140f, 140f));
        handle.raycastTarget = false;
        VirtualJoystick joystick = joystickBase.gameObject.AddComponent<VirtualJoystick>();
        Set(joystick, "background", joystickBase.rectTransform);
        Set(joystick, "handle", handle.rectTransform);

        Button dash = NewButton("DashButton", touch, "btn_dash", "", new Color(0.2f, 0.75f, 1f, 0.3f), new Vector2(230f, 230f), 34, circleSprite);
        AnchorAt((RectTransform)dash.transform, new Vector2(1f, 0f), new Vector2(-220f, 220f), new Vector2(230f, 230f));
        Image fill = NewImage("CooldownFill", dash.transform, circleSprite, new Color(0.3f, 0.9f, 1f, 0.45f));
        Stretch(fill.rectTransform);
        fill.type = Image.Type.Filled;
        fill.fillMethod = Image.FillMethod.Radial360;
        fill.fillOrigin = (int)Image.Origin360.Top;
        fill.raycastTarget = false;
        fill.transform.SetAsFirstSibling(); // behind the label

        // ---------- Panels ----------
        RectTransform pausePanel = NewPanel("PausePanel", canvas, "pause_title", Color.white, 760f, out RectTransform pauseWindow);
        Text volumeLabel = NewText("VolumeLabel", pauseWindow, "", 34, new Color(0.8f, 0.85f, 1f), TextAnchor.MiddleCenter, "menu_volume");
        AnchorAt(volumeLabel.rectTransform, new Vector2(0.5f, 1f), new Vector2(0f, -190f), new Vector2(600f, 60f));
        Slider pauseVolume = NewSlider("VolumeSlider", pauseWindow);
        AnchorAt((RectTransform)pauseVolume.transform, new Vector2(0.5f, 1f), new Vector2(0f, -250f), new Vector2(520f, 40f));
        Button resume = PanelButton(pauseWindow, "ResumeButton", "btn_resume", ButtonGreen, -350f);
        Button pauseRestart = PanelButton(pauseWindow, "RestartButton", "btn_restart", ButtonBlue, -480f);
        Button pauseMenu = PanelButton(pauseWindow, "MenuButton", "btn_menu", ButtonGrey, -610f);

        RectTransform gameOverPanel = NewPanel("GameOverPanel", canvas, "gameover_title", new Color(1f, 0.4f, 0.4f), 860f, out RectTransform gameOverWindow);
        Text reason = WindowText(gameOverWindow, "ReasonText", 40, Color.white, -180f);
        Text gameOverScore = WindowText(gameOverWindow, "ScoreText", 36, new Color(0.6f, 0.95f, 1f), -245f);
        Button watchAd = PanelButton(gameOverWindow, "WatchAdButton", null, ButtonGold, -360f, 640f);
        Text watchAdLabel = watchAd.GetComponentInChildren<Text>();
        Text adStatus = WindowText(gameOverWindow, "AdStatusText", 28, new Color(1f, 0.75f, 0.5f), -450f);
        Button gameOverRestart = PanelButton(gameOverWindow, "PlayAgainButton", "btn_play_again", ButtonGreen, -560f);
        Button gameOverMenu = PanelButton(gameOverWindow, "MenuButton", "btn_menu", ButtonGrey, -690f);

        RectTransform completePanel = NewPanel("LevelCompletePanel", canvas, "level_complete", new Color(0.4f, 1f, 0.6f), 700f, out RectTransform completeWindow);
        Text completeScore = WindowText(completeWindow, "ScoreText", 40, new Color(0.6f, 0.95f, 1f), -190f);
        Text timeBonus = WindowText(completeWindow, "TimeBonusText", 34, Gold, -255f);
        Button nextLevel = PanelButton(completeWindow, "NextLevelButton", "btn_next_level", ButtonGreen, -400f);
        Button completeMenu = PanelButton(completeWindow, "MenuButton", "btn_menu", ButtonGrey, -530f);

        RectTransform victoryPanel = NewPanel("VictoryPanel", canvas, "victory_title", Gold, 760f, out RectTransform victoryWindow);
        WindowText(victoryWindow, "VictoryText", 38, Color.white, -180f, "victory_text");
        Text victoryScore = WindowText(victoryWindow, "ScoreText", 40, new Color(0.6f, 0.95f, 1f), -250f);
        Text victoryRecord = WindowText(victoryWindow, "RecordText", 34, Gold, -315f);
        Button victoryAgain = PanelButton(victoryWindow, "PlayAgainButton", "btn_play_again", ButtonGreen, -450f);
        Button victoryMenu = PanelButton(victoryWindow, "MenuButton", "btn_menu", ButtonGrey, -580f);

        // ---------- wire GameUI ----------
        Set(ui, "levelText", level);
        Set(ui, "livesText", lives);
        Set(ui, "crystalsText", crystals);
        Set(ui, "timeText", time);
        Set(ui, "scoreText", score);
        Set(ui, "messageText", message);
        Set(ui, "pauseButton", pause);
        Set(ui, "touchControls", touch.gameObject);
        Set(ui, "dashButton", dash);
        Set(ui, "dashCooldownFill", fill);
        Set(ui, "pausePanel", pausePanel.gameObject);
        Set(ui, "resumeButton", resume);
        Set(ui, "pauseRestartButton", pauseRestart);
        Set(ui, "pauseMenuButton", pauseMenu);
        Set(ui, "volumeSlider", pauseVolume);
        Set(ui, "gameOverPanel", gameOverPanel.gameObject);
        Set(ui, "gameOverReasonText", reason);
        Set(ui, "gameOverScoreText", gameOverScore);
        Set(ui, "watchAdButton", watchAd);
        Set(ui, "watchAdLabel", watchAdLabel);
        Set(ui, "adStatusText", adStatus);
        Set(ui, "gameOverRestartButton", gameOverRestart);
        Set(ui, "gameOverMenuButton", gameOverMenu);
        Set(ui, "levelCompletePanel", completePanel.gameObject);
        Set(ui, "levelCompleteScoreText", completeScore);
        Set(ui, "timeBonusText", timeBonus);
        Set(ui, "nextLevelButton", nextLevel);
        Set(ui, "levelCompleteMenuButton", completeMenu);
        Set(ui, "victoryPanel", victoryPanel.gameObject);
        Set(ui, "victoryScoreText", victoryScore);
        Set(ui, "victoryRecordText", victoryRecord);
        Set(ui, "victoryPlayAgainButton", victoryAgain);
        Set(ui, "victoryMenuButton", victoryMenu);

        foreach (RectTransform panel in new[] { pausePanel, gameOverPanel, completePanel, victoryPanel })
            panel.gameObject.SetActive(false);

        gameUIPrefab = SavePrefab(root, "GameUI");
    }

    // ================================================================ main menu canvas

    static void CreateMainMenuCanvas()
    {
        GameObject root = NewCanvas("MainMenuUI", 10);
        MainMenuUI menu = root.AddComponent<MainMenuUI>();
        Transform canvas = root.transform;

        Text title = NewText("Title", canvas, "", 130, Gold, TextAnchor.MiddleCenter, "game_title");
        AnchorAt(title.rectTransform, new Vector2(0.5f, 1f), new Vector2(0f, -170f), new Vector2(1600f, 170f));
        title.gameObject.AddComponent<Shadow>().effectDistance = new Vector2(6f, -6f);

        Text tagline = NewText("Tagline", canvas, "", 38, new Color(0.85f, 0.88f, 1f), TextAnchor.MiddleCenter, "menu_tagline");
        AnchorAt(tagline.rectTransform, new Vector2(0.5f, 1f), new Vector2(0f, -285f), new Vector2(1600f, 70f));

        Button play = NewButton("PlayButton", canvas, "menu_play", "", ButtonGreen, new Vector2(560f, 130f), 60);
        AnchorAt((RectTransform)play.transform, new Vector2(0.5f, 0.5f), new Vector2(0f, 120f), new Vector2(560f, 130f));

        Text levelsLabel = NewText("LevelsLabel", canvas, "", 34, new Color(0.8f, 0.85f, 1f), TextAnchor.MiddleCenter, "menu_levels");
        AnchorAt(levelsLabel.rectTransform, new Vector2(0.5f, 0.5f), new Vector2(0f, 10f), new Vector2(600f, 50f));
        Button[] levelButtons = new Button[GameScenes.LevelCount];
        for (int i = 0; i < levelButtons.Length; i++)
        {
            levelButtons[i] = NewButton("Level" + (i + 1) + "Button", canvas, null, (i + 1).ToString(), ButtonBlue, new Vector2(130f, 100f), 46);
            AnchorAt((RectTransform)levelButtons[i].transform, new Vector2(0.5f, 0.5f), new Vector2((i - 1) * 160f, -65f), new Vector2(130f, 100f));
        }

        Text languageLabel = NewText("LanguageLabel", canvas, "", 34, new Color(0.8f, 0.85f, 1f), TextAnchor.MiddleCenter, "menu_language");
        AnchorAt(languageLabel.rectTransform, new Vector2(0.5f, 0.5f), new Vector2(0f, -160f), new Vector2(600f, 50f));
        Button[] languageButtons = new Button[3];
        for (int i = 0; i < languageButtons.Length; i++)
        {
            languageButtons[i] = NewButton("Language" + (Language)i + "Button", canvas, null, Localization.LanguageNames[i], ButtonGrey, new Vector2(300f, 90f), 38);
            AnchorAt((RectTransform)languageButtons[i].transform, new Vector2(0.5f, 0.5f), new Vector2((i - 1) * 330f, -235f), new Vector2(300f, 90f));
        }

        Text volumeLabel = NewText("VolumeLabel", canvas, "", 32, new Color(0.8f, 0.85f, 1f), TextAnchor.MiddleRight, "menu_volume");
        AnchorAt(volumeLabel.rectTransform, new Vector2(0.5f, 0.5f), new Vector2(-250f, -340f), new Vector2(400f, 50f));
        Slider volume = NewSlider("VolumeSlider", canvas);
        AnchorAt((RectTransform)volume.transform, new Vector2(0.5f, 0.5f), new Vector2(180f, -340f), new Vector2(420f, 40f));

        Text highScore = NewText("HighScoreText", canvas, "", 36, Gold, TextAnchor.MiddleRight);
        AnchorAt(highScore.rectTransform, new Vector2(1f, 1f), new Vector2(-300f, -55f), new Vector2(560f, 60f));

        Text controls = NewText("ControlsText", canvas, "", 26, new Color(0.7f, 0.75f, 0.9f), TextAnchor.MiddleCenter);
        AnchorAt(controls.rectTransform, new Vector2(0.5f, 0f), new Vector2(0f, 60f), new Vector2(1700f, 90f));

        Button quit = NewButton("QuitButton", canvas, "menu_quit", "", ButtonGrey, new Vector2(220f, 80f), 34);
        AnchorAt((RectTransform)quit.transform, new Vector2(0f, 1f), new Vector2(150f, -60f), new Vector2(220f, 80f));

        Set(menu, "playButton", play);
        Set(menu, "levelButtons", levelButtons);
        Set(menu, "languageButtons", languageButtons);
        Set(menu, "volumeSlider", volume);
        Set(menu, "highScoreText", highScore);
        Set(menu, "controlsText", controls);
        Set(menu, "quitButton", quit);
    }

    // ================================================================ UI helpers

    static GameObject NewCanvas(string name, int sortingOrder)
    {
        GameObject root = new GameObject(name, typeof(RectTransform), typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
        Canvas canvas = root.GetComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = sortingOrder;
        CanvasScaler scaler = root.GetComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920f, 1080f);
        scaler.matchWidthOrHeight = 0.5f;
        root.AddComponent<EventSystemSpawner>();
        return root;
    }

    static RectTransform NewRect(string name, Transform parent)
    {
        GameObject go = new GameObject(name, typeof(RectTransform));
        go.layer = LayerMask.NameToLayer("UI");
        RectTransform rect = (RectTransform)go.transform;
        rect.SetParent(parent, false);
        return rect;
    }

    static RectTransform Stretch(RectTransform rect)
    {
        rect.anchorMin = Vector2.zero;
        rect.anchorMax = Vector2.one;
        rect.offsetMin = Vector2.zero;
        rect.offsetMax = Vector2.zero;
        return rect;
    }

    static void Anchor(RectTransform rect, Vector2 min, Vector2 max, Vector2 pivot, Vector2 position, Vector2 size)
    {
        rect.anchorMin = min;
        rect.anchorMax = max;
        rect.pivot = pivot;
        rect.anchoredPosition = position;
        rect.sizeDelta = size;
    }

    /// <summary>Anchors to one point of the parent (0..1) with a pixel offset and a size.</summary>
    static void AnchorAt(RectTransform rect, Vector2 anchor, Vector2 position, Vector2 size)
    {
        Anchor(rect, anchor, anchor, new Vector2(0.5f, 0.5f), position, size);
    }

    static Image NewImage(string name, Transform parent, Sprite sprite, Color color)
    {
        Image image = NewRect(name, parent).gameObject.AddComponent<Image>();
        image.sprite = sprite;
        image.color = color;
        if (sprite == roundedSprite) image.type = Image.Type.Sliced;
        return image;
    }

    /// <summary>Text with our font. If a key is given, LocalizedText keeps it translated.</summary>
    static Text NewText(string name, Transform parent, string text, int size, Color color, TextAnchor alignment, string key = null)
    {
        Text label = NewRect(name, parent).gameObject.AddComponent<Text>();
        label.font = uiFont;
        label.fontSize = size;
        label.color = color;
        label.alignment = alignment;
        label.horizontalOverflow = HorizontalWrapMode.Wrap;
        label.verticalOverflow = VerticalWrapMode.Overflow;
        label.resizeTextForBestFit = true;
        label.resizeTextMinSize = Mathf.Max(14, size / 2);
        label.resizeTextMaxSize = size;
        label.raycastTarget = false;
        label.text = key != null ? Localization.Get(key) : text;
        if (key != null) label.gameObject.AddComponent<LocalizedText>().Key = key;
        return label;
    }

    static Button NewButton(string name, Transform parent, string key, string text, Color color, Vector2 size, int fontSize, Sprite sprite = null)
    {
        Image image = NewImage(name, parent, sprite != null ? sprite : roundedSprite, color);
        image.rectTransform.sizeDelta = size;
        Button button = image.gameObject.AddComponent<Button>();
        ColorBlock colors = button.colors;
        colors.highlightedColor = new Color(1.15f, 1.15f, 1.15f, 1f);
        colors.pressedColor = new Color(0.8f, 0.8f, 0.8f, 1f);
        colors.disabledColor = new Color(0.5f, 0.5f, 0.5f, 0.6f);
        button.colors = colors;
        // No keyboard navigation between buttons: arrows and WASD are for moving the ball.
        button.navigation = new Navigation { mode = Navigation.Mode.None };

        Text label = NewText("Label", image.transform, text, fontSize, Color.white, TextAnchor.MiddleCenter, key);
        Stretch(label.rectTransform);
        label.rectTransform.offsetMin = new Vector2(12f, 6f);
        label.rectTransform.offsetMax = new Vector2(-12f, -6f);
        return button;
    }

    /// <summary>A full-screen dark layer with a centered window and a title.</summary>
    static RectTransform NewPanel(string name, Transform parent, string titleKey, Color titleColor, float height, out RectTransform window)
    {
        Image dim = NewImage(name, parent, null, DimColor);
        Stretch(dim.rectTransform);

        Image box = NewImage("Window", dim.transform, roundedSprite, PanelColor);
        AnchorAt(box.rectTransform, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(900f, height));
        window = box.rectTransform;

        Text title = NewText("Title", window, "", 70, titleColor, TextAnchor.MiddleCenter, titleKey);
        AnchorAt(title.rectTransform, new Vector2(0.5f, 1f), new Vector2(0f, -85f), new Vector2(820f, 110f));
        return dim.rectTransform;
    }

    static Button PanelButton(RectTransform window, string name, string key, Color color, float y, float width = 560f)
    {
        Button button = NewButton(name, window, key, "", color, new Vector2(width, 100f), 40);
        AnchorAt((RectTransform)button.transform, new Vector2(0.5f, 1f), new Vector2(0f, y), new Vector2(width, 100f));
        return button;
    }

    static Text WindowText(RectTransform window, string name, int size, Color color, float y, string key = null)
    {
        Text text = NewText(name, window, "", size, color, TextAnchor.MiddleCenter, key);
        AnchorAt(text.rectTransform, new Vector2(0.5f, 1f), new Vector2(0f, y), new Vector2(820f, 60f));
        return text;
    }

    static Slider NewSlider(string name, Transform parent)
    {
        RectTransform root = NewRect(name, parent);
        Slider slider = root.gameObject.AddComponent<Slider>();

        Image background = NewImage("Background", root, roundedSprite, new Color(1f, 1f, 1f, 0.15f));
        background.pixelsPerUnitMultiplier = 3f; // thin bar: smaller rounded corners
        Stretch(background.rectTransform);
        background.rectTransform.offsetMin = new Vector2(0f, 12f);
        background.rectTransform.offsetMax = new Vector2(0f, -12f);

        RectTransform fillArea = Stretch(NewRect("Fill Area", root));
        fillArea.offsetMin = new Vector2(10f, 12f);
        fillArea.offsetMax = new Vector2(-10f, -12f);
        Image fill = NewImage("Fill", fillArea, roundedSprite, new Color(0.3f, 0.85f, 1f));
        fill.pixelsPerUnitMultiplier = 3f;
        Stretch(fill.rectTransform);

        RectTransform handleArea = Stretch(NewRect("Handle Slide Area", root));
        handleArea.offsetMin = new Vector2(20f, 0f);
        handleArea.offsetMax = new Vector2(-20f, 0f);
        Image handle = NewImage("Handle", handleArea, circleSprite, Color.white);
        handle.rectTransform.sizeDelta = new Vector2(44f, 0f);
        handle.rectTransform.anchorMin = new Vector2(0f, 0f);
        handle.rectTransform.anchorMax = new Vector2(0f, 1f);
        handle.rectTransform.offsetMin = new Vector2(-22f, -4f);
        handle.rectTransform.offsetMax = new Vector2(22f, 4f);

        slider.fillRect = fill.rectTransform;
        slider.handleRect = handle.rectTransform;
        slider.targetGraphic = handle;
        slider.direction = Slider.Direction.LeftToRight;
        slider.navigation = new Navigation { mode = Navigation.Mode.None };
        slider.minValue = 0f;
        slider.maxValue = 1f;
        slider.value = 0.8f;
        return slider;
    }
}
