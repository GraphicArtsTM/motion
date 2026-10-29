using UnityEngine;
using UnityEngine.UI;

/// <summary>
/// Put this on a UI Text that never changes (button labels, titles).
/// It shows the text for its key and updates itself when the language changes.
/// Texts with numbers (score, lives) are filled in by GameUI instead.
/// </summary>
[RequireComponent(typeof(Text))]
public class LocalizedText : MonoBehaviour
{
    [SerializeField] string key;

    Text label;

    public string Key
    {
        get => key;
        set { key = value; Refresh(); }
    }

    void Awake()
    {
        label = GetComponent<Text>();
    }

    void OnEnable()
    {
        Localization.LanguageChanged += Refresh;
        Refresh();
    }

    void OnDisable()
    {
        Localization.LanguageChanged -= Refresh;
    }

    void Refresh()
    {
        if (label != null) label.text = Localization.Get(key);
    }
}
