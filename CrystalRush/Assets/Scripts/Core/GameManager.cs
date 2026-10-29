using System;
using System.Collections;
using UnityEngine;
using UnityEngine.SceneManagement;

public enum GameState
{
    Playing,
    Paused,
    LevelComplete,
    Victory,
    GameOver
}

public enum LoseReason
{
    None,
    NoLives,
    TimeUp
}

/// <summary>
/// The heart of a level: lives, crystals, timer, score and the round state.
/// There is exactly one GameManager in every level scene, and any script can reach it
/// through GameManager.Instance (the Singleton pattern).
/// The UI never changes these numbers itself, it only listens to the events below.
/// </summary>
public class GameManager : MonoBehaviour
{
    public static GameManager Instance { get; private set; }

    [Header("Level")]
    [SerializeField] int levelNumber = 1;
    [SerializeField] float timeLimit = 90f;
    [SerializeField] int startLives = 3;

    [Header("Score")]
    [SerializeField] int pointsPerCrystal = 100;
    [SerializeField] int pointsPerSecondLeft = 10;

    [Header("Rewarded ad bonus")]
    [SerializeField] int rewardedLives = 3;
    [SerializeField] float rewardedMinTime = 20f;

    [Header("Effects")]
    [SerializeField] ParticleSystem victoryEffectPrefab;
    [SerializeField] float hurryUpTime = 10f;

    public GameState State { get; private set; } = GameState.Playing;
    public LoseReason LoseReason { get; private set; }
    public int LevelNumber => levelNumber;
    public bool IsLastLevel => levelNumber >= GameScenes.LevelCount;
    public int Lives { get; private set; }
    public int CrystalsCollected { get; private set; }
    public int CrystalsTotal { get; private set; }
    public float TimeLeft { get; private set; }
    public int Score { get; private set; }
    public int LastTimeBonus { get; private set; }
    public bool IsNewRecord { get; private set; }
    public bool RewardUsedThisRound { get; private set; }
    public int RewardedLives => rewardedLives;
    public bool PortalOpen => CrystalsCollected >= CrystalsTotal;

    // Events for the UI and other scripts.
    public event Action StatsChanged;
    public event Action<GameState> StateChanged;
    public event Action PortalOpened;
    public event Action<string> MessageShown; // text that is already translated

    bool hurryShown;
    int bonusLives;

    void Awake()
    {
        Instance = this;
        Time.timeScale = 1f; // a previous scene could have left the game paused

        // Bonus lives from the rewarded ad in the main menu are used once, in the first level that starts.
        bonusLives = SaveData.TakeBonusLives();
        Lives = startLives + bonusLives;
        TimeLeft = timeLimit;
        Score = GameScenes.CarriedScore;
        CrystalsTotal = FindObjectsByType<Crystal>(FindObjectsSortMode.None).Length;
    }

    IEnumerator Start()
    {
        // Wait one frame, so the UI has surely subscribed to our events.
        yield return null;
        StatsChanged?.Invoke();
        string message = Localization.Format("msg_level_start", levelNumber, CrystalsTotal);
        if (bonusLives > 0) message += "\n" + Localization.Format("msg_bonus_lives", bonusLives);
        ShowMessage(message);
    }

    void OnDestroy()
    {
        if (Instance == this) Instance = null;
    }

    void Update()
    {
        if (State != GameState.Playing) return;

        TimeLeft -= Time.deltaTime;

        if (!hurryShown && TimeLeft <= hurryUpTime)
        {
            hurryShown = true;
            ShowMessage(Localization.Get("msg_hurry"));
        }

        if (TimeLeft <= 0f)
        {
            TimeLeft = 0f;
            EndRound(LoseReason.TimeUp);
        }

        StatsChanged?.Invoke();
    }

    // ---------------- Called by the player and the collectibles ----------------

    public void LoseLife()
    {
        if (State != GameState.Playing) return;

        Lives = Mathf.Max(0, Lives - 1);
        StatsChanged?.Invoke();

        if (Lives == 0) EndRound(LoseReason.NoLives);
    }

    public void AddCrystal()
    {
        if (State != GameState.Playing) return;

        CrystalsCollected++;
        Score += pointsPerCrystal;
        StatsChanged?.Invoke();

        if (CrystalsCollected == CrystalsTotal)
        {
            AudioManager.Play(Sfx.PortalOpen);
            ShowMessage(Localization.Get("msg_portal_open"));
            PortalOpened?.Invoke();
        }
    }

    public void AddLife(int amount)
    {
        Lives += amount;
        ShowMessage(Localization.Get("msg_extra_life"));
        StatsChanged?.Invoke();
    }

    public void AddTime(float seconds)
    {
        TimeLeft += seconds;
        if (TimeLeft > hurryUpTime) hurryShown = false;
        ShowMessage(Localization.Format("msg_extra_time", Mathf.RoundToInt(seconds)));
        StatsChanged?.Invoke();
    }

    public void ShowMessage(string text)
    {
        MessageShown?.Invoke(text);
    }

    /// <summary>The player entered the open portal.</summary>
    public void CompleteLevel()
    {
        if (State != GameState.Playing) return;

        LastTimeBonus = Mathf.CeilToInt(TimeLeft) * pointsPerSecondLeft;
        Score += LastTimeBonus;
        GameScenes.CarriedScore = Score;
        SaveData.UnlockLevel(levelNumber + 1);
        IsNewRecord = SaveData.TrySetHighScore(Score);

        if (IsLastLevel)
        {
            if (victoryEffectPrefab != null)
            {
                Vector3 position = Camera.main != null ? Camera.main.transform.position + Camera.main.transform.forward * 6f : Vector3.zero;
                Instantiate(victoryEffectPrefab, position, Quaternion.identity);
            }
        }

        AudioManager.Play(Sfx.Win);
        SetState(IsLastLevel ? GameState.Victory : GameState.LevelComplete);
    }

    void EndRound(LoseReason reason)
    {
        LoseReason = reason;
        IsNewRecord = SaveData.TrySetHighScore(Score);
        AudioManager.Play(Sfx.Lose);
        SetState(GameState.GameOver);
    }

    void SetState(GameState newState)
    {
        State = newState;
        // Time.timeScale = 0 freezes physics, obstacles and the timer.
        // Only the UI keeps working (it uses unscaled time).
        Time.timeScale = newState == GameState.Playing ? 1f : 0f;
        StatsChanged?.Invoke();
        StateChanged?.Invoke(newState);
    }

    // ---------------- Called by the UI buttons ----------------

    public void Pause()
    {
        if (State == GameState.Playing) SetState(GameState.Paused);
    }

    public void Resume()
    {
        if (State == GameState.Paused) SetState(GameState.Playing);
    }

    public void TogglePause()
    {
        if (State == GameState.Playing) Pause();
        else if (State == GameState.Paused) Resume();
    }

    /// <summary>
    /// Rewarded ad on the Game Over screen. Only the player can start it (button),
    /// and only once per round. The bonus is given only if the ad was watched to the end.
    /// </summary>
    public void WatchAdForLives(Action<AdResult> onFinished)
    {
        if (State != GameState.GameOver || RewardUsedThisRound)
        {
            onFinished?.Invoke(AdResult.NotAvailable);
            return;
        }

        AdManager.Instance.ShowRewarded(result =>
        {
            if (result == AdResult.Rewarded && State == GameState.GameOver)
            {
                RewardUsedThisRound = true;
                Lives += rewardedLives;
                TimeLeft = Mathf.Max(TimeLeft, rewardedMinTime);
                hurryShown = TimeLeft <= hurryUpTime;
                LoseReason = LoseReason.None;
                SetState(GameState.Playing);
            }
            onFinished?.Invoke(result);
        });
    }

    public void RestartLevel()
    {
        // Restarting starts the level score from what we had when we entered the level.
        string scene = SceneManager.GetActiveScene().name;
        AdManager.Instance.OnRoundFinished(() => SceneManager.LoadScene(scene));
    }

    public void LoadNextLevel()
    {
        if (IsLastLevel)
        {
            PlayAgainFromStart();
            return;
        }
        string next = GameScenes.Level(levelNumber + 1);
        AdManager.Instance.OnRoundFinished(() => SceneManager.LoadScene(next));
    }

    public void PlayAgainFromStart()
    {
        AdManager.Instance.OnRoundFinished(() => GameScenes.StartNewRun(1));
    }

    public void GoToMainMenu()
    {
        Time.timeScale = 1f;
        SceneManager.LoadScene(GameScenes.MainMenu);
    }
}
