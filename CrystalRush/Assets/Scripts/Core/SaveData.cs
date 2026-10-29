using UnityEngine;

/// <summary>
/// Everything the game remembers between launches, stored in PlayerPrefs:
/// high score, opened levels, language and volume.
/// </summary>
public static class SaveData
{
    const string HighScoreKey = "high_score";
    const string UnlockedLevelKey = "unlocked_level";
    const string LanguageKey = "language";
    const string VolumeKey = "volume";
    const string LanguageChosenKey = "language_chosen";

    public static int HighScore
    {
        get => PlayerPrefs.GetInt(HighScoreKey, 0);
        private set { PlayerPrefs.SetInt(HighScoreKey, value); PlayerPrefs.Save(); }
    }

    /// <summary>Saves the score if it beats the record. Returns true for a new record.</summary>
    public static bool TrySetHighScore(int score)
    {
        if (score <= HighScore) return false;
        HighScore = score;
        return true;
    }

    /// <summary>The highest level the player may start from the menu (1 = only the first one).</summary>
    public static int UnlockedLevel
    {
        get => Mathf.Clamp(PlayerPrefs.GetInt(UnlockedLevelKey, 1), 1, GameScenes.LevelCount);
    }

    public static void UnlockLevel(int level)
    {
        if (level <= UnlockedLevel) return;
        PlayerPrefs.SetInt(UnlockedLevelKey, Mathf.Min(level, GameScenes.LevelCount));
        PlayerPrefs.Save();
    }

    public static Language Language
    {
        get
        {
            // On the very first launch pick the language of the device.
            if (!PlayerPrefs.HasKey(LanguageChosenKey)) return LanguageFromSystem();
            return (Language)Mathf.Clamp(PlayerPrefs.GetInt(LanguageKey, 0), 0, 2);
        }
        set
        {
            PlayerPrefs.SetInt(LanguageKey, (int)value);
            PlayerPrefs.SetInt(LanguageChosenKey, 1);
            PlayerPrefs.Save();
        }
    }

    public static float Volume
    {
        get => PlayerPrefs.GetFloat(VolumeKey, 0.8f);
        set { PlayerPrefs.SetFloat(VolumeKey, Mathf.Clamp01(value)); PlayerPrefs.Save(); }
    }

    static Language LanguageFromSystem()
    {
        switch (Application.systemLanguage)
        {
            case SystemLanguage.Russian:
            case SystemLanguage.Ukrainian:
            case SystemLanguage.Belarusian:
                return Language.Russian;
            default:
                // Unity has no SystemLanguage value for Uzbek, so Uzbek players pick it in the menu.
                return Language.English;
        }
    }
}
