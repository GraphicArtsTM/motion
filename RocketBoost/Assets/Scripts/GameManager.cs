using UnityEngine;
using UnityEngine.SceneManagement;

// Tries, Game Over, continue after a rewarded ad, restart, moving between levels, pause.
// From the ads guide, Part 2.3, plus pause, messages and the main menu.
public class GameManager : MonoBehaviour
{
    public static GameManager Instance { get; private set; }

    public const int MainMenuScene = 0;

    [SerializeField] int maxAttempts = 3;
    [SerializeField] int continueBonusAttempts = 3;
    [SerializeField] int interstitialEveryNRestarts = 3;
    [SerializeField] int interstitialEveryNLevels = 2;

    // static: these values do not reset when the scene reloads
    static int attempts = -1;
    static bool continueUsed = false;
    static int restartCounter = 0;
    static int levelCounter = 0;

    // true after the last level is finished; the main menu shows "Congratulations"
    public static bool GameCompleted { get; set; }

    bool isGameOver = false;
    bool isPaused = false;
    string announceKey;
    float announceTime = -100f;

    public int Attempts => attempts;
    public int MaxAttempts => maxAttempts;
    public int BonusAttempts => continueBonusAttempts;
    public bool IsGameOver => isGameOver;
    public bool IsPaused => isPaused;
    public bool CanContinue => !continueUsed;

    void Awake()
    {
        Instance = this;
        Time.timeScale = 1f;
        AudioListener.pause = false;
        if (attempts < 0) attempts = maxAttempts;
    }

    // Called from the main menu before the first level: a fresh run
    public static void ResetRun()
    {
        attempts = -1;
        continueUsed = false;
        GameCompleted = false;
    }

    // Called at the moment of a crash: we take one try away right away
    public void RegisterCrash()
    {
        if (isGameOver) return;
        attempts = Mathf.Max(0, attempts - 1);
        Debug.Log("Attempts left: " + attempts + " / " + maxAttempts);
    }

    // Called after a short pause (when the explosion is over)
    public void FinishCrash()
    {
        if (attempts <= 0)
        {
            isGameOver = true;
            Time.timeScale = 0f;
        }
        else
        {
            ReloadScene();
        }
    }

    public void ContinueAfterReward()
    {
        continueUsed = true;
        attempts = continueBonusAttempts;
        isGameOver = false;
        Time.timeScale = 1f;
        ReloadScene();
    }

    public void Restart()
    {
        attempts = maxAttempts;
        continueUsed = false;
        restartCounter++;
        bool showAd = restartCounter % interstitialEveryNRestarts == 0;
        LoadSceneWithOptionalAd(SceneManager.GetActiveScene().buildIndex, showAd);
    }

    public void LevelCompleted(int nextScene)
    {
        levelCounter++;
        if (nextScene == MainMenuScene) GameCompleted = true;
        bool showAd = levelCounter % interstitialEveryNLevels == 0;
        LoadSceneWithOptionalAd(nextScene, showAd);
    }

    public void GoToMainMenu()
    {
        Time.timeScale = 1f;
        AudioListener.pause = false;
        SceneManager.LoadScene(MainMenuScene);
    }

    public void SetPaused(bool pause)
    {
        if (isGameOver) return;
        isPaused = pause;
        Time.timeScale = pause ? 0f : 1f;
        AudioListener.pause = pause;
    }

    // A big message in the middle of the screen for a moment ("Landed!", "Crashed!")
    public void Announce(string key)
    {
        announceKey = key;
        announceTime = Time.unscaledTime;
    }

    public string CurrentAnnouncement(float duration)
    {
        if (announceKey == null || Time.unscaledTime - announceTime > duration) return null;
        return announceKey;
    }

    void LoadSceneWithOptionalAd(int sceneIndex, bool showAd)
    {
        if (showAd && AdManager.Instance != null)
            AdManager.Instance.ShowInterstitial(() => SceneManager.LoadScene(sceneIndex));
        else
            SceneManager.LoadScene(sceneIndex);
    }

    void ReloadScene()
    {
        SceneManager.LoadScene(SceneManager.GetActiveScene().buildIndex);
    }
}
