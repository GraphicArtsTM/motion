using System;
using System.Collections.Generic;
using UnityEngine;

public enum Language
{
    English = 0,
    Russian = 1,
    Uzbek = 2
}

/// <summary>
/// All game texts in three languages: English, Russian, Uzbek (Latin).
/// Usage: Localization.Get("menu_play") or Localization.Format("hud_lives", 3).
/// The chosen language is saved in PlayerPrefs (see SaveData).
/// </summary>
public static class Localization
{
    // Raised when the player picks another language. LocalizedText and the UI scripts listen to it.
    public static event Action LanguageChanged;

    // Read lazily (not in a static initializer), so PlayerPrefs is touched only on the main thread.
    static Language? current;

    public static Language Current
    {
        get
        {
            if (current == null) current = SaveData.Language;
            return current.Value;
        }
    }

    // Names of the languages are written in their own language, so a player can always find theirs.
    public static readonly string[] LanguageNames = { "English", "Русский", "O‘zbekcha" };

    // key -> { English, Russian, Uzbek }
    static readonly Dictionary<string, string[]> Texts = new Dictionary<string, string[]>
    {
        // ---------- Main menu ----------
        { "game_title",        new[] { "CRYSTAL RUSH", "CRYSTAL RUSH", "CRYSTAL RUSH" } },
        { "menu_tagline",      new[] { "Collect every crystal, dodge the traps, reach the portal!",
                                       "Собери все кристаллы, обойди ловушки и доберись до портала!",
                                       "Barcha kristallarni yig‘, tuzoqlardan qoch va portalga yet!" } },
        { "menu_play",         new[] { "PLAY", "ИГРАТЬ", "O‘YNASH" } },
        { "menu_levels",       new[] { "Levels", "Уровни", "Darajalar" } },
        { "menu_language",     new[] { "Language", "Язык", "Til" } },
        { "menu_volume",       new[] { "Volume", "Громкость", "Ovoz balandligi" } },
        { "menu_highscore",    new[] { "Best score: {0}", "Рекорд: {0}", "Rekord: {0}" } },
        { "menu_quit",         new[] { "Quit", "Выход", "Chiqish" } },
        { "menu_watch_ad",     new[] { "Watch ad: +{0} lives for the next game", "Смотреть рекламу: +{0} жизни в следующей игре",
                                       "Reklama ko‘rish: keyingi o‘yinga +{0} jon" } },
        { "menu_bonus_ready",  new[] { "Bonus ready: +{0} lives in the next game", "Бонус готов: +{0} жизни в следующей игре",
                                       "Bonus tayyor: keyingi o‘yinda +{0} jon" } },
        { "menu_controls_pc",  new[] { "PC: WASD / arrows - move, Space - dash, Esc - pause",
                                       "ПК: WASD / стрелки - движение, Пробел - рывок, Esc - пауза",
                                       "Kompyuter: WASD / strelkalar - harakat, Probel - otilish, Esc - pauza" } },
        { "menu_controls_mobile", new[] { "Phone: joystick - move, DASH button - dash",
                                          "Телефон: джойстик - движение, кнопка РЫВОК - рывок",
                                          "Telefon: joystik - harakat, OTILISH tugmasi - otilish" } },

        // ---------- HUD ----------
        { "level_n",           new[] { "Level {0}", "Уровень {0}", "{0}-daraja" } },
        { "hud_lives",         new[] { "Lives: {0}", "Жизни: {0}", "Jonlar: {0}" } },
        { "hud_crystals",      new[] { "Crystals: {0}/{1}", "Кристаллы: {0}/{1}", "Kristallar: {0}/{1}" } },
        { "hud_time",          new[] { "Time: {0}", "Время: {0}", "Vaqt: {0}" } },
        { "hud_score",         new[] { "Score: {0}", "Очки: {0}", "Ball: {0}" } },
        { "btn_dash",          new[] { "DASH", "РЫВОК", "OTILISH" } },

        // ---------- Panels ----------
        { "pause_title",       new[] { "Pause", "Пауза", "Pauza" } },
        { "btn_resume",        new[] { "Resume", "Продолжить", "Davom etish" } },
        { "btn_restart",       new[] { "Restart", "Заново", "Qayta boshlash" } },
        { "btn_menu",          new[] { "Main menu", "Главное меню", "Bosh menyu" } },
        { "btn_play_again",    new[] { "Play again", "Играть снова", "Yana o‘ynash" } },
        { "btn_next_level",    new[] { "Next level", "Следующий уровень", "Keyingi daraja" } },
        { "gameover_title",    new[] { "Game Over", "Игра окончена", "O‘yin tugadi" } },
        { "gameover_no_lives", new[] { "You ran out of lives", "Закончились жизни", "Jonlar tugadi" } },
        { "gameover_time_up",  new[] { "Time is up", "Время вышло", "Vaqt tugadi" } },
        { "level_complete",    new[] { "Level complete!", "Уровень пройден!", "Daraja yakunlandi!" } },
        { "time_bonus",        new[] { "Time bonus: +{0}", "Бонус за время: +{0}", "Vaqt bonusi: +{0}" } },
        { "victory_title",     new[] { "Victory!", "Победа!", "G‘alaba!" } },
        { "victory_text",      new[] { "All levels completed!", "Все уровни пройдены!", "Barcha darajalar o‘tildi!" } },
        { "new_record",        new[] { "New record!", "Новый рекорд!", "Yangi rekord!" } },

        // ---------- Ads ----------
        { "btn_watch_ad",      new[] { "Watch ad: +{0} lives", "Смотреть рекламу: +{0} жизни", "Reklama ko‘rish: +{0} jon" } },
        { "ad_not_available",  new[] { "Ad is not available right now", "Реклама сейчас недоступна", "Reklama hozir mavjud emas" } },
        { "ad_no_reward",      new[] { "Ad was closed early - no bonus", "Реклама закрыта раньше - без бонуса", "Reklama erta yopildi - bonus yo‘q" } },
        { "ad_loading",        new[] { "The ad is loading, try again in a moment", "Реклама загружается, попробуйте через минуту",
                                       "Reklama yuklanmoqda, birozdan so‘ng urinib ko‘ring" } },
        { "ad_thanks",         new[] { "Thank you! Bonus received", "Спасибо! Бонус получен", "Rahmat! Bonus olindi" } },
        { "ad_test_title",     new[] { "TEST AD", "ТЕСТОВАЯ РЕКЛАМА", "TEST REKLAMA" } },
        { "ad_test_rewarded",  new[] { "Rewarded ad (stub)", "Реклама с наградой (заглушка)", "Mukofotli reklama (zaglushka)" } },
        { "ad_test_inter",     new[] { "Interstitial ad between rounds (stub)", "Межстраничная реклама между раундами (заглушка)",
                                       "Raundlar orasidagi reklama (zaglushka)" } },
        { "ad_wait",           new[] { "Wait {0} s...", "Подождите {0} с...", "{0} soniya kuting..." } },
        { "ad_close",          new[] { "Close", "Закрыть", "Yopish" } },
        { "ad_skip",           new[] { "Skip (no bonus)", "Пропустить (без бонуса)", "O‘tkazish (bonussiz)" } },

        // ---------- In-game messages ----------
        { "msg_level_start",   new[] { "Level {0}: collect {1} crystals!", "Уровень {0}: собери кристаллы ({1})!",
                                       "{0}-daraja: {1} ta kristall yig‘!" } },
        { "msg_portal_open",   new[] { "The portal is open!", "Портал открыт!", "Portal ochildi!" } },
        { "msg_portal_locked", new[] { "Collect all crystals first", "Сначала собери все кристаллы", "Avval barcha kristallarni yig‘" } },
        { "msg_extra_life",    new[] { "+1 life", "+1 жизнь", "+1 jon" } },
        { "msg_extra_time",    new[] { "+{0} sec", "+{0} сек", "+{0} soniya" } },
        { "msg_bonus_lives",   new[] { "+{0} lives - ad bonus", "+{0} жизни - бонус за рекламу", "+{0} jon - reklama bonusi" } },
        { "msg_hurry",         new[] { "Hurry up!", "Поторопись!", "Shoshiling!" } },
    };

    public static void SetLanguage(Language language)
    {
        if (language == Current) return;
        current = language;
        SaveData.Language = language;
        LanguageChanged?.Invoke();
    }

    public static string Get(string key)
    {
        if (string.IsNullOrEmpty(key)) return string.Empty;
        if (!Texts.TryGetValue(key, out string[] variants))
        {
            Debug.LogWarning($"Localization: no text for key '{key}'");
            return key;
        }
        return variants[(int)Current];
    }

    public static string Format(string key, params object[] args)
    {
        return string.Format(Get(key), args);
    }

    public static bool HasKey(string key) => Texts.ContainsKey(key);
}
