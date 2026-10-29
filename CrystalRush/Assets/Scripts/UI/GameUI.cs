using System.Collections;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

/// <summary>
/// The interface of a level: HUD (lives, crystals, time, score), touch controls and the panels
/// Pause / Game Over / Level complete / Victory. It only SHOWS the state of GameManager
/// and sends button presses back to it.
/// </summary>
public class GameUI : MonoBehaviour
{
    [Header("HUD")]
    [SerializeField] Text levelText;
    [SerializeField] Text livesText;
    [SerializeField] Text crystalsText;
    [SerializeField] Text timeText;
    [SerializeField] Text scoreText;
    [SerializeField] Text messageText;
    [SerializeField] Button pauseButton;
    [SerializeField] Color timeNormalColor = Color.white;
    [SerializeField] Color timeLowColor = new Color(1f, 0.35f, 0.3f);

    [Header("Touch controls")]
    [SerializeField] GameObject touchControls;
    [SerializeField] Button dashButton;
    [SerializeField] Image dashCooldownFill;
    [Tooltip("Show the joystick in the Editor too, to test it with the mouse.")]
    [SerializeField] bool showTouchControlsInEditor = true;

    [Header("Pause panel")]
    [SerializeField] GameObject pausePanel;
    [SerializeField] Button resumeButton;
    [SerializeField] Button pauseRestartButton;
    [SerializeField] Button pauseMenuButton;
    [SerializeField] Slider volumeSlider;

    [Header("Game Over panel")]
    [SerializeField] GameObject gameOverPanel;
    [SerializeField] Text gameOverReasonText;
    [SerializeField] Text gameOverScoreText;
    [SerializeField] Button watchAdButton;
    [SerializeField] Text watchAdLabel;
    [SerializeField] Text adStatusText;
    [SerializeField] Button gameOverRestartButton;
    [SerializeField] Button gameOverMenuButton;

    [Header("Level complete panel")]
    [SerializeField] GameObject levelCompletePanel;
    [SerializeField] Text levelCompleteScoreText;
    [SerializeField] Text timeBonusText;
    [SerializeField] Button nextLevelButton;
    [SerializeField] Button levelCompleteMenuButton;

    [Header("Victory panel")]
    [SerializeField] GameObject victoryPanel;
    [SerializeField] Text victoryScoreText;
    [SerializeField] Text victoryRecordText;
    [SerializeField] Button victoryPlayAgainButton;
    [SerializeField] Button victoryMenuButton;

    GameManager game;
    PlayerController player;
    Coroutine messageRoutine;
    bool useTouchControls;

    void Start()
    {
        game = GameManager.Instance;
        player = FindFirstObjectByType<PlayerController>();

        // On a phone the touch controls are always on; in the Editor they can be tested with the mouse.
        useTouchControls = Application.isMobilePlatform || (Application.isEditor && showTouchControlsInEditor);

        ConnectButtons();

        game.StatsChanged += RefreshHud;
        game.StateChanged += OnStateChanged;
        game.MessageShown += ShowMessage;
        Localization.LanguageChanged += RefreshAll;

        if (messageText != null) messageText.text = string.Empty;
        OnStateChanged(game.State);
        RefreshHud();
    }

    void OnDestroy()
    {
        Localization.LanguageChanged -= RefreshAll;
        if (game == null) return;
        game.StatsChanged -= RefreshHud;
        game.StateChanged -= OnStateChanged;
        game.MessageShown -= ShowMessage;
    }

    void ConnectButtons()
    {
        pauseButton.onClick.AddListener(() => { Click(); game.Pause(); });
        dashButton.onClick.AddListener(() => { if (player != null) player.RequestDash(); });

        resumeButton.onClick.AddListener(() => { Click(); game.Resume(); });
        pauseRestartButton.onClick.AddListener(() => { Click(); game.RestartLevel(); });
        pauseMenuButton.onClick.AddListener(() => { Click(); game.GoToMainMenu(); });

        watchAdButton.onClick.AddListener(OnWatchAdPressed);
        gameOverRestartButton.onClick.AddListener(() => { Click(); game.RestartLevel(); });
        gameOverMenuButton.onClick.AddListener(() => { Click(); game.GoToMainMenu(); });

        nextLevelButton.onClick.AddListener(() => { Click(); game.LoadNextLevel(); });
        levelCompleteMenuButton.onClick.AddListener(() => { Click(); game.GoToMainMenu(); });

        victoryPlayAgainButton.onClick.AddListener(() => { Click(); game.PlayAgainFromStart(); });
        victoryMenuButton.onClick.AddListener(() => { Click(); game.GoToMainMenu(); });

        if (volumeSlider != null)
        {
            volumeSlider.SetValueWithoutNotify(SaveData.Volume);
            volumeSlider.onValueChanged.AddListener(AudioManager.SetVolume);
        }
    }

    void Update()
    {
        if (PauseKeyPressed()) game.TogglePause();

        // A clicked button stays "selected", and Space (our dash key) would press it again.
        // So while playing nothing in the UI may be selected.
        if (game.State == GameState.Playing && EventSystem.current != null && EventSystem.current.currentSelectedGameObject != null)
            EventSystem.current.SetSelectedGameObject(null);

        if (dashCooldownFill != null && player != null) dashCooldownFill.fillAmount = player.DashReady;
    }

    // ---------------- HUD ----------------

    void RefreshHud()
    {
        levelText.text = Localization.Format("level_n", game.LevelNumber);
        livesText.text = Localization.Format("hud_lives", game.Lives);
        crystalsText.text = Localization.Format("hud_crystals", game.CrystalsCollected, game.CrystalsTotal);
        scoreText.text = Localization.Format("hud_score", game.Score);

        int seconds = Mathf.CeilToInt(game.TimeLeft);
        timeText.text = Localization.Format("hud_time", $"{seconds / 60}:{seconds % 60:00}");
        timeText.color = seconds <= 10 ? timeLowColor : timeNormalColor;
    }

    void RefreshAll()
    {
        RefreshHud();
        OnStateChanged(game.State);
    }

    void ShowMessage(string text)
    {
        if (messageText == null) return;
        if (messageRoutine != null) StopCoroutine(messageRoutine);
        messageRoutine = StartCoroutine(MessageRoutine(text));
    }

    IEnumerator MessageRoutine(string text)
    {
        messageText.text = text;
        Color color = messageText.color;

        // Show for 2 seconds, then fade out. Unscaled time works during pause too.
        color.a = 1f;
        messageText.color = color;
        yield return new WaitForSecondsRealtime(2f);

        for (float t = 0f; t < 0.5f; t += Time.unscaledDeltaTime)
        {
            color.a = 1f - t / 0.5f;
            messageText.color = color;
            yield return null;
        }
        messageText.text = string.Empty;
        color.a = 1f;
        messageText.color = color;
    }

    // ---------------- Panels ----------------

    void OnStateChanged(GameState state)
    {
        pausePanel.SetActive(state == GameState.Paused);
        gameOverPanel.SetActive(state == GameState.GameOver);
        levelCompletePanel.SetActive(state == GameState.LevelComplete);
        victoryPanel.SetActive(state == GameState.Victory);

        bool playing = state == GameState.Playing;
        pauseButton.gameObject.SetActive(playing);
        if (touchControls != null) touchControls.SetActive(playing && useTouchControls);

        switch (state)
        {
            case GameState.GameOver: FillGameOver(); break;
            case GameState.LevelComplete: FillLevelComplete(); break;
            case GameState.Victory: FillVictory(); break;
        }
    }

    void FillGameOver()
    {
        gameOverReasonText.text = Localization.Get(game.LoseReason == LoseReason.TimeUp ? "gameover_time_up" : "gameover_no_lives");
        gameOverScoreText.text = Localization.Format("hud_score", game.Score)
            + (game.IsNewRecord ? "   " + Localization.Get("new_record") : string.Empty);

        watchAdLabel.text = Localization.Format("btn_watch_ad", game.RewardedLives);
        // The rewarded bonus can be taken only once per round.
        watchAdButton.gameObject.SetActive(!game.RewardUsedThisRound);
        watchAdButton.interactable = true;
        adStatusText.text = string.Empty;
    }

    void FillLevelComplete()
    {
        levelCompleteScoreText.text = Localization.Format("hud_score", game.Score);
        timeBonusText.text = Localization.Format("time_bonus", game.LastTimeBonus);
    }

    void FillVictory()
    {
        victoryScoreText.text = Localization.Format("hud_score", game.Score);
        victoryRecordText.text = game.IsNewRecord
            ? Localization.Get("new_record")
            : Localization.Format("menu_highscore", SaveData.HighScore);
    }

    void OnWatchAdPressed()
    {
        Click();
        watchAdButton.interactable = false; // no double clicks while the ad is opening

        game.WatchAdForLives(result =>
        {
            if (result == AdResult.Rewarded) return; // GameManager continues the round, this panel closes

            // No ad or closed early: no bonus, but the player can still restart as usual.
            watchAdButton.interactable = true;
            adStatusText.text = Localization.Get(result == AdResult.Skipped ? "ad_no_reward" : "ad_not_available");
        });
    }

    static void Click() => AudioManager.Play(Sfx.Click);

    static bool PauseKeyPressed()
    {
#if ENABLE_INPUT_SYSTEM
        Keyboard keyboard = Keyboard.current;
        return keyboard != null && (keyboard.escapeKey.wasPressedThisFrame || keyboard.pKey.wasPressedThisFrame);
#else
        return Input.GetKeyDown(KeyCode.Escape) || Input.GetKeyDown(KeyCode.P);
#endif
    }
}
