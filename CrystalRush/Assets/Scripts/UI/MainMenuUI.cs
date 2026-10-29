using UnityEngine;
using UnityEngine.UI;

/// <summary>
/// Main menu: Play, level choice, language (English / Русский / O‘zbekcha), volume, best score, quit.
/// </summary>
public class MainMenuUI : MonoBehaviour
{
    [SerializeField] Button playButton;
    [SerializeField] Button[] levelButtons;
    [SerializeField] Button[] languageButtons;      // order: English, Russian, Uzbek (as in the Language enum)
    [SerializeField] Slider volumeSlider;
    [SerializeField] Text highScoreText;
    [SerializeField] Text controlsText;
    [SerializeField] Button quitButton;
    [SerializeField] Color selectedLanguageColor = new Color(1f, 0.8f, 0.25f);
    [SerializeField] Color normalLanguageColor = new Color(0.22f, 0.24f, 0.4f);

    void Start()
    {
        Time.timeScale = 1f;

        playButton.onClick.AddListener(() => StartLevel(1));

        for (int i = 0; i < levelButtons.Length; i++)
        {
            int level = i + 1; // a copy for the lambda
            levelButtons[i].onClick.AddListener(() => StartLevel(level));
            levelButtons[i].GetComponentInChildren<Text>().text = level.ToString();
        }

        for (int i = 0; i < languageButtons.Length; i++)
        {
            Language language = (Language)i;
            languageButtons[i].onClick.AddListener(() =>
            {
                AudioManager.Play(Sfx.Click);
                Localization.SetLanguage(language);
            });
            languageButtons[i].GetComponentInChildren<Text>().text = Localization.LanguageNames[i];
        }

        volumeSlider.SetValueWithoutNotify(SaveData.Volume);
        volumeSlider.onValueChanged.AddListener(AudioManager.SetVolume);

        // There is nothing to quit to in a browser tab.
        quitButton.gameObject.SetActive(Application.platform != RuntimePlatform.WebGLPlayer);
        quitButton.onClick.AddListener(Application.Quit);

        Localization.LanguageChanged += Refresh;
        Refresh();
    }

    void OnDestroy()
    {
        Localization.LanguageChanged -= Refresh;
    }

    void Refresh()
    {
        highScoreText.text = Localization.Format("menu_highscore", SaveData.HighScore);
        controlsText.text = Localization.Get(Application.isMobilePlatform ? "menu_controls_mobile" : "menu_controls_pc")
            + "\n" + Localization.Get(Application.isMobilePlatform ? "menu_controls_pc" : "menu_controls_mobile");

        // Levels open one by one.
        for (int i = 0; i < levelButtons.Length; i++)
        {
            levelButtons[i].interactable = i + 1 <= SaveData.UnlockedLevel;
        }

        // Highlight the current language.
        for (int i = 0; i < languageButtons.Length; i++)
        {
            languageButtons[i].GetComponent<Image>().color =
                i == (int)Localization.Current ? selectedLanguageColor : normalLanguageColor;
        }
    }

    void StartLevel(int level)
    {
        AudioManager.Play(Sfx.Click);
        GameScenes.StartNewRun(level);
    }
}
