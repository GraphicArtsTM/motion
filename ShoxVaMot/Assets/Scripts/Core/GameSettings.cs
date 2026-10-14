using System;
using System.Collections.Generic;
using UnityEngine;
using Shatranj.Chess;

namespace Shatranj.Core
{
    public enum Language { Uzbek = 0, Russian = 1, English = 2, UzbekCyrillic = 3 }
    public enum BattleMode { Full = 0, Fast = 1, Off = 2 }
    public enum TimeOfDay { Day = 0, Sunset = 1, Night = 2 }
    public enum GameMode { LocalPvP = 0, VsAI = 1 }

    [Serializable]
    public class GameSettings
    {
        public int language = -1;
        public float musicVolume = 0.55f;
        public float sfxVolume = 0.9f;
        public bool vibration = true;
        public bool showLegalMoves = true;
        public bool showCoordinates = true;
        public bool autoRotate = true;
        public bool cinematicCamera = true;
        public bool postFx = true;
        public int battleMode = (int)BattleMode.Full;
        public int timeOfDay = (int)TimeOfDay.Sunset;
        public int quality = -1;
        public int perfVersion;

        const string Key = "shatranj.settings.v1";

        public Language Lang { get { return (Language)Mathf.Clamp(language, 0, 3); } }
        public BattleMode Battle { get { return (BattleMode)Mathf.Clamp(battleMode, 0, 2); } }
        public TimeOfDay Ambience { get { return (TimeOfDay)Mathf.Clamp(timeOfDay, 0, 2); } }

        public static GameSettings Load()
        {
            GameSettings s = null;
            try
            {
                string json = PlayerPrefs.GetString(Key, "");
                if (!string.IsNullOrEmpty(json)) s = JsonUtility.FromJson<GameSettings>(json);
            }
            catch (Exception e) { Debug.LogWarning("Settings load failed: " + e.Message); }
            if (s == null) s = new GameSettings();
            // игра узбекская — по умолчанию всегда O'zbekcha; сменить можно кнопкой в главном меню
            if (s.language < 0) s.language = (int)Language.Uzbek;
            // качество графики подбираем под телефон (один раз; дальше — как выберет игрок)
            if (s.quality < 0 || s.perfVersion < 1)
            {
                s.quality = DetectQuality();
                s.postFx = s.quality > 0;
                s.perfVersion = 1;
            }
            return s;
        }

        /// <summary>0 — Низкая, 1 — Средняя, 2 — Высокая. На телефонах — по объёму памяти.</summary>
        public static int DetectQuality()
        {
            if (!Application.isMobilePlatform) return 2;
            int mem = SystemInfo.systemMemorySize;
            if (mem >= 11000) return 2;
            if (mem >= 5000) return 1;
            return 0;
        }

        public void Save()
        {
            PlayerPrefs.SetString(Key, JsonUtility.ToJson(this));
            PlayerPrefs.Save();
        }
    }

    /// <summary>Контроль времени: минуты + добавление секунд за ход.</summary>
    public struct TimeControl
    {
        public int Minutes;
        public int Increment;

        public static readonly TimeControl[] Presets =
        {
            new TimeControl { Minutes = 0, Increment = 0 },
            new TimeControl { Minutes = 3, Increment = 2 },
            new TimeControl { Minutes = 5, Increment = 0 },
            new TimeControl { Minutes = 10, Increment = 0 },
            new TimeControl { Minutes = 15, Increment = 10 },
            new TimeControl { Minutes = 30, Increment = 0 },
        };

        public bool Unlimited { get { return Minutes <= 0; } }

        public string Label
        {
            get
            {
                if (Unlimited) return Loc.T("time.unlimited");
                return Increment > 0 ? Minutes + " + " + Increment : Minutes + " " + Loc.T("time.min");
            }
        }
    }

    [Serializable]
    public class MatchConfig
    {
        public int mode = (int)GameMode.LocalPvP;
        public int variant = (int)Variant.Classic;
        public int timeIndex = 0;
        public string whiteName = "";
        public string blackName = "";

        public Variant Variant { get { return (Variant)variant; } }
        public TimeControl Time { get { return TimeControl.Presets[Mathf.Clamp(timeIndex, 0, TimeControl.Presets.Length - 1)]; } }

        public string NameOf(Side s)
        {
            string n = s == Side.White ? whiteName : blackName;
            if (string.IsNullOrEmpty(n)) n = Loc.T(s == Side.White ? "side.white" : "side.black");
            return n;
        }

        public MatchConfig Clone() { return (MatchConfig)MemberwiseClone(); }
    }

    [Serializable]
    public class SavedMatch
    {
        public MatchConfig config;
        public List<string> moves = new List<string>();
        public float clockWhite;
        public float clockBlack;

        const string Key = "shatranj.save.v1";

        public static bool Exists { get { return PlayerPrefs.HasKey(Key); } }

        public static SavedMatch Load()
        {
            try
            {
                string json = PlayerPrefs.GetString(Key, "");
                if (string.IsNullOrEmpty(json)) return null;
                return JsonUtility.FromJson<SavedMatch>(json);
            }
            catch (Exception e)
            {
                Debug.LogWarning("Save load failed: " + e.Message);
                return null;
            }
        }

        public void Store()
        {
            PlayerPrefs.SetString(Key, JsonUtility.ToJson(this));
            PlayerPrefs.Save();
        }

        public static void Clear()
        {
            PlayerPrefs.DeleteKey(Key);
            PlayerPrefs.Save();
        }
    }

    [Serializable]
    public class PlayerStats
    {
        public int played;
        public int whiteWins;
        public int blackWins;
        public int draws;
        public int captures;
        public int heroes;
        public int fastestMate;
        public int afrosiyobGames;

        const string Key = "shatranj.stats.v1";

        public static PlayerStats Load()
        {
            try
            {
                string json = PlayerPrefs.GetString(Key, "");
                if (!string.IsNullOrEmpty(json)) return JsonUtility.FromJson<PlayerStats>(json);
            }
            catch (Exception) { }
            return new PlayerStats();
        }

        /// <summary>0 — Низкая, 1 — Средняя, 2 — Высокая. На телефонах — по объёму памяти.</summary>
        public static int DetectQuality()
        {
            if (!Application.isMobilePlatform) return 2;
            int mem = SystemInfo.systemMemorySize;
            if (mem >= 11000) return 2;
            if (mem >= 5000) return 1;
            return 0;
        }

        public void Save()
        {
            PlayerPrefs.SetString(Key, JsonUtility.ToJson(this));
            PlayerPrefs.Save();
        }

        public void Reset()
        {
            played = whiteWins = blackWins = draws = captures = heroes = fastestMate = afrosiyobGames = 0;
            Save();
        }
    }
}
