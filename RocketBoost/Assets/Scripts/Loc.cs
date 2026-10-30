using System.Collections.Generic;
using UnityEngine;

// Localization: Russian, English, Uzbek (Latin script).
// Usage: Loc.T("play") returns the text in the current language.
// The chosen language is saved in PlayerPrefs and survives restarts.
public enum Lang { RU = 0, EN = 1, UZ = 2 }

public static class Loc
{
    const string PrefKey = "lang";

    static bool loaded;
    static Lang current;

    public static Lang Current
    {
        get { EnsureLoaded(); return current; }
    }

    // Names of the languages, each written in its own language (for the buttons)
    public static readonly string[] LanguageNames = { "Русский", "English", "Oʻzbekcha" };

    // key -> { RU, EN, UZ }
    static readonly Dictionary<string, string[]> table = new Dictionary<string, string[]>
    {
        { "play",          new[] { "Играть", "Play", "Oʻynash" } },
        { "quit",          new[] { "Выход", "Quit", "Chiqish" } },
        { "language",      new[] { "Язык", "Language", "Til" } },
        { "attempts",      new[] { "Попытки", "Attempts", "Urinishlar" } },
        { "level",         new[] { "Уровень", "Level", "Bosqich" } },
        { "level_Over",    new[] { "Через гору", "Over the Hill", "Togʻ ortidan" } },
        { "level_Tunnel",  new[] { "Туннель", "Tunnel", "Tunnel" } },
        { "level_Pistons", new[] { "Поршни", "Pistons", "Porshenlar" } },
        { "game_over",     new[] { "ИГРА ОКОНЧЕНА", "GAME OVER", "OʻYIN TUGADI" } },
        { "watch_ad",      new[] { "Реклама: +{0} попытки", "Watch ad: +{0} attempts", "Reklama: +{0} urinish" } },
        { "play_again",    new[] { "Играть снова", "Play again", "Qaytadan oʻynash" } },
        { "main_menu",     new[] { "Главное меню", "Main menu", "Bosh menyu" } },
        { "menu",          new[] { "Меню", "Menu", "Menyu" } },
        { "pause",         new[] { "ПАУЗА", "PAUSED", "PAUZA" } },
        { "resume",        new[] { "Продолжить", "Resume", "Davom etish" } },
        { "landed",        new[] { "Посадка выполнена!", "Landed!", "Muvaffaqiyatli qoʻnish!" } },
        { "crashed",       new[] { "Авария!", "Crashed!", "Halokat!" } },
        { "completed",     new[] { "Поздравляем! Все уровни пройдены!", "Congratulations! All levels completed!", "Tabriklaymiz! Barcha bosqichlar oʻtildi!" } },
        { "goal",          new[] { "Взлетите с зелёной площадки и мягко сядьте на синюю.",
                                   "Take off from the green pad and land softly on the blue one.",
                                   "Yashil maydonchadan uching va koʻk maydonchaga ohista qoʻning." } },
        { "hint_pc",       new[] { "Пробел — двигатель,  ← → — поворот",
                                   "Space — thrust,  ← → — rotate",
                                   "Probel — dvigatel,  ← → — burilish" } },
        { "hint_mobile",   new[] { "Справа — двигатель, слева — поворот",
                                   "Right button — thrust, left buttons — rotate",
                                   "Oʻngdagi tugma — dvigatel, chapdagilar — burilish" } },
        { "debug_collide", new[] { "Отладка: столкновения {0}", "Debug: collisions {0}", "Debug: toʻqnashuvlar {0}" } },
        { "on",            new[] { "вкл", "on", "yoqilgan" } },
        { "off",           new[] { "выкл", "off", "oʻchirilgan" } },
    };

    public static string T(string key)
    {
        EnsureLoaded();
        if (table.TryGetValue(key, out string[] texts)) return texts[(int)current];
        return key; // a missing key is shown as is, so it is easy to notice
    }

    public static string T(string key, object arg)
    {
        return string.Format(T(key), arg);
    }

    public static void Set(Lang lang)
    {
        EnsureLoaded();
        current = lang;
        PlayerPrefs.SetInt(PrefKey, (int)lang);
        PlayerPrefs.Save();
    }

    static void EnsureLoaded()
    {
        if (loaded) return;
        loaded = true;
        if (PlayerPrefs.HasKey(PrefKey))
        {
            current = (Lang)Mathf.Clamp(PlayerPrefs.GetInt(PrefKey), 0, 2);
            return;
        }
        // First launch: guess from the system language.
        // Unity's SystemLanguage has no Uzbek, so we also look at the .NET culture name ("uz-Latn-UZ" and so on).
        string culture = "";
        try { culture = System.Globalization.CultureInfo.CurrentCulture.Name ?? ""; }
        catch (System.Exception) { }

        if (culture.StartsWith("uz"))
        {
            current = Lang.UZ;
            return;
        }
        switch (Application.systemLanguage)
        {
            case SystemLanguage.Russian:
            case SystemLanguage.Ukrainian:
            case SystemLanguage.Belarusian:
                current = Lang.RU;
                break;
            default:
                current = Lang.EN;
                break;
        }
    }
}
