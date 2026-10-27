using System;
using System.Collections.Generic;
using PushPals.Level;
using UnityEngine;

namespace PushPals.Save
{
    /// <summary>Что лежит в сохранении (JSON). Новое поле — только с значением по умолчанию: старые файлы должны читаться.</summary>
    [Serializable]
    public class SaveData
    {
        public int version = 2;
        /// <summary>Когда сохранено (UTC, тики) — из облака и с диска берётся более новое.</summary>
        public long savedAt;
        /// <summary>Старые звёзды (до Этапа 17.2) — только чтобы перенести в levels.</summary>
        public List<LevelStars> stars = new List<LevelStars>();
        /// <summary>Прогресс уровней: пройден, золотые спички, лучшее время (Этап 17.2).</summary>
        public List<LevelSave> levels = new List<LevelSave>();
        /// <summary>Открытые достижения (id).</summary>
        public List<string> achievements = new List<string>();
        public bool partyHat;
        /// <summary>Внешний вид игроков 1–4 за этим ПК (по сети — свой в первом).</summary>
        public Look[] looks = { new Look(), new Look(), new Look(), new Look() };
        public string levelId = "";
        public int burn;
        public bool friendSlaps = true;
        public int access;
        public int mic;
        public int voiceVolume = 2;
        // Настройки (Этап 17)
        public float masterVolume = 0.8f;
        public float musicVolume = 0.6f;
        public float effectsVolume = 0.8f;
        public bool shake = true;
        public bool fullscreen = true;
        public int resWidth, resHeight;
        // Интерфейс (Этап 17.3): язык («ru», «en», пусто — как в системе), размер, режим HUD
        public string language = "";
        public float uiScale = 1f;
        public int hud;
        // Экран и доступность (Этап 17.4). −1 — «не задано»: взять из старых полей (fullscreen, shake)
        public int windowMode = -1;
        public int fpsCap = 4;
        public bool vsync = true;
        public int effects = 2;
        public float shakeAmount = -1f;
        public bool simpleControls;
        public bool playerMarkers = true;
        public bool subtitles = true;
        public float mouseSensitivity = 1f;
        /// <summary>Переназначенные кнопки (JSON переопределений Input System; пусто — как по умолчанию).</summary>
        public string bindings = "";
    }

    [Serializable]
    public class LevelStars
    {
        public string id;
        public bool done, hidden, third;
    }

    [Serializable]
    public class LevelSave
    {
        public string id;
        public bool done;
        public int golden;
        public float bestTime;
    }

    [Serializable]
    public class Look
    {
        public int hat, wood;
    }

    /// <summary>Облако (Steam Cloud) — задаёт сетевой модуль, сохранения о Steam не знают.</summary>
    public interface ICloudStorage
    {
        bool Available { get; }
        string Read();
        void Write(string json);
    }

    /// <summary>
    /// Сохранения (Этап 15): прогресс уровней (золотые спички — Этап 17.2), достижения, найденные секреты, внешний вид игроков, настройки игры и голоса.
    /// Файл в Application.persistentDataPath (в редакторе — отдельный, чтобы тесты не трогали игру) и Steam Cloud
    /// (только в сборке). Пишется сразу при изменении (файл маленький); при запуске берётся более новое — диск или облако.
    /// Автотест-клиент (-pp-bot) не сохраняет.
    /// </summary>
    public static class SaveSystem
    {
        public static SaveData Data { get; private set; } = new SaveData();

        /// <summary>Облако — подключает сетевой модуль (NetSession).</summary>
        public static ICloudStorage Cloud { get; set; }

        /// <summary>Не писать на диск (автотест).</summary>
        public static bool Disabled { get; set; }

        private static bool applying, loaded;

        private static string FileName => Application.isEditor ? "pushpals_save_editor.json" : "pushpals_save.json";
        public static string FilePath => System.IO.Path.Combine(Application.persistentDataPath, FileName);
        private static string TempPath => FilePath + ".tmp";
        private static string BackupPath => FilePath + ".bak";

        // Загрузка до первой сцены (и при каждом Play в редакторе — статика живёт между запусками)
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        private static void Boot()
        {
            loaded = false;
            Cloud = null;
            Disabled = Array.IndexOf(Environment.GetCommandLineArgs(), "-pp-bot") >= 0;
            Data = ReadFile() ?? new SaveData();
            Apply();
            loaded = true;
            LevelProgress.Changed -= Save;
            LevelProgress.Changed += Save;
            GameRules.Changed -= Save;
            GameRules.Changed += Save;
            PushPals.UI.Loc.Changed -= Save;
            PushPals.UI.Loc.Changed += Save;
            PushPals.UI.UiSettings.Changed -= Save;
            PushPals.UI.UiSettings.Changed += Save;
        }

        // Основной файл; не читается — недописанный временный (выключение посреди записи), потом прошлая копия
        private static SaveData ReadFile()
        {
            bool broken = false;
            foreach (var path in new[] { FilePath, TempPath, BackupPath })
            {
                try
                {
                    if (!System.IO.File.Exists(path)) continue;
                    var data = Parse(System.IO.File.ReadAllText(path));
                    if (data != null)
                    {
                        if (path != FilePath) Debug.LogWarning("[PushPals] Сохранение восстановлено из " + System.IO.Path.GetFileName(path));
                        return data;
                    }
                }
                catch (Exception e) { Debug.LogWarning("[PushPals] Сохранение не прочиталось (" + System.IO.Path.GetFileName(path) + "): " + e.Message); }
                if (path == FilePath) broken = true;
            }
            // Ничего не прочиталось: битый файл откладываем, чтобы первая же запись не стёрла его насовсем
            if (broken)
            {
                try { System.IO.File.Copy(FilePath, FilePath + ".broken", true); }
                catch (Exception e) { Debug.LogWarning("[PushPals] Битое сохранение не отложилось: " + e.Message); }
            }
            return null;
        }

        private static SaveData Parse(string json)
        {
            if (string.IsNullOrEmpty(json)) return null;
            var d = JsonUtility.FromJson<SaveData>(json);
            if (d == null) return null;
            if (d.looks == null || d.looks.Length < 4)
            {
                var looks = new Look[4];
                for (int i = 0; i < 4; i++) looks[i] = d.looks != null && i < d.looks.Length && d.looks[i] != null ? d.looks[i] : new Look();
                d.looks = looks;
            }
            if (d.stars == null) d.stars = new List<LevelStars>();
            if (d.levels == null) d.levels = new List<LevelSave>();
            if (d.achievements == null) d.achievements = new List<string>();
            // Старое сохранение со звёздами: «пройден» остаётся, спрятанная звезда — первая золотая спичка (она на том же месте)
            if (d.levels.Count == 0 && d.stars.Count > 0)
                foreach (var st in d.stars)
                    if (!string.IsNullOrEmpty(st.id)) d.levels.Add(new LevelSave { id = st.id, done = st.done, golden = st.hidden ? 1 : 0 });
            d.stars.Clear();
            return d;
        }

        /// <summary>
        /// Подключилось облако: прогресс (уровни, золотые спички, достижения, колпак) складываем из обоих —
        /// пройденное на любом ПК не теряется; настройки и внешний вид берём из более нового. Потом выравниваем оба.
        /// </summary>
        public static void SyncWithCloud()
        {
            if (Cloud == null || !Cloud.Available || Disabled || Application.isEditor) return;
            SaveData remote = null;
            try { remote = Parse(Cloud.Read()); }
            catch (Exception e) { Debug.LogWarning("[PushPals] Облако Steam: " + e.Message); }
            Capture(); // в Data — то, что сейчас в игре
            if (remote != null && remote.savedAt > Data.savedAt)
            {
                MergeProgress(remote, Data);
                Data = remote;
                Apply();
                Debug.Log("[PushPals] Сохранение взято из облака Steam (с прогрессом этого ПК)");
            }
            else if (remote != null && MergeProgress(Data, remote))
            {
                applying = true;
                ApplyProgress();
                applying = false;
                Debug.Log("[PushPals] В сохранение добавлен прогресс из облака Steam");
            }
            Save();
        }

        // Прогресс из from — в into (только прибавляется). true — что-то добавилось
        private static bool MergeProgress(SaveData into, SaveData from)
        {
            bool changed = false;
            foreach (var l in from.levels)
            {
                if (l == null || string.IsNullOrEmpty(l.id)) continue;
                var mine = into.levels.Find(x => x != null && x.id == l.id);
                if (mine == null)
                {
                    into.levels.Add(new LevelSave { id = l.id, done = l.done, golden = l.golden, bestTime = l.bestTime });
                    changed = true;
                    continue;
                }
                if (l.done && !mine.done) { mine.done = true; changed = true; }
                if ((mine.golden | l.golden) != mine.golden) { mine.golden |= l.golden; changed = true; } // маска найденных
                if (l.bestTime > 0f && (mine.bestTime <= 0f || l.bestTime < mine.bestTime)) { mine.bestTime = l.bestTime; changed = true; }
            }
            foreach (var a in from.achievements)
                if (!string.IsNullOrEmpty(a) && !into.achievements.Contains(a)) { into.achievements.Add(a); changed = true; }
            if (from.partyHat && !into.partyHat) { into.partyHat = true; changed = true; }
            return changed;
        }

        /// <summary>Записать всё текущее (прогресс, настройки) — диск и облако.</summary>
        public static void Save()
        {
            if (!loaded || applying || Disabled) return;
            Capture();
            Data.savedAt = DateTime.UtcNow.Ticks;
            string json = JsonUtility.ToJson(Data, true);
            WriteFile(json);
            if (Cloud != null && Cloud.Available && !Application.isEditor)
            {
                try { Cloud.Write(json); }
                catch (Exception e) { Debug.LogWarning("[PushPals] Облако Steam: " + e.Message); }
            }
        }

        private static void WriteFile(string json)
        {
            try
            {
                // Сначала во временный файл, потом подменить одним шагом (прошлое — в .bak). Раньше старый файл
                // удалялся до переноса: выключение между ними оставляло только .tmp, а его никто не читал
                System.IO.File.WriteAllText(TempPath, json);
                if (!System.IO.File.Exists(FilePath)) { System.IO.File.Move(TempPath, FilePath); return; }
                try { System.IO.File.Replace(TempPath, FilePath, BackupPath, true); }
                catch (Exception e) when (e is PlatformNotSupportedException || e is System.IO.IOException)
                {
                    // Без File.Replace: прошлое — в копию, потом подмена (ReadFile найдёт .tmp или .bak, если оборвётся)
                    System.IO.File.Copy(FilePath, BackupPath, true);
                    System.IO.File.Delete(FilePath);
                    System.IO.File.Move(TempPath, FilePath);
                }
            }
            catch (Exception e) { Debug.LogWarning("[PushPals] Сохранение не записалось: " + e.Message); }
        }

        /// <summary>Внешний вид игрока номер slot (0–3) за этим ПК.</summary>
        public static Look LookOf(int slot) => Data.looks[Mathf.Clamp(slot, 0, 3)];

        /// <summary>Запомнить внешний вид (шкаф) и сохранить.</summary>
        public static void RememberLook(int slot, int hat, int wood)
        {
            var l = LookOf(slot);
            if (l.hat == hat && l.wood == wood) return;
            l.hat = hat;
            l.wood = wood;
            Save();
        }

        // Из игры — в сохранение
        private static void Capture()
        {
            Data.levels.Clear();
            foreach (var kv in LevelProgress.Snapshot())
                Data.levels.Add(new LevelSave { id = kv.Key, done = kv.Value.completed, golden = kv.Value.golden, bestTime = kv.Value.bestTime });
            Data.partyHat = GameRules.PartyHatFound;
            Data.levelId = GameRules.LevelId ?? "";
            Data.burn = GameRules.Burn;
            Data.friendSlaps = GameRules.FriendSlaps;
            Data.access = (int)GameRules.Access;
            Data.mic = (int)VoiceSettings.Mic;
            Data.voiceVolume = VoiceSettings.Volume;
            Data.masterVolume = SoundSettings.Master;
            Data.musicVolume = SoundSettings.Music;
            Data.effectsVolume = SoundSettings.Effects;
            Data.shake = VideoSettings.Shake;
            Data.shakeAmount = VideoSettings.ShakeAmount;
            Data.windowMode = (int)VideoSettings.Window;
            Data.fullscreen = VideoSettings.Window != VideoSettings.WindowMode.Windowed;
            Data.resWidth = VideoSettings.Width;
            Data.resHeight = VideoSettings.Height;
            Data.fpsCap = VideoSettings.FpsCap;
            Data.vsync = VideoSettings.VSync;
            Data.effects = (int)VideoSettings.Effects;
            Data.simpleControls = AccessSettings.SimpleControls;
            Data.playerMarkers = AccessSettings.PlayerMarkers;
            Data.subtitles = AccessSettings.Subtitles;
            Data.mouseSensitivity = AccessSettings.MouseSensitivity;
            Data.language = PushPals.UI.Loc.Code;
            Data.uiScale = PushPals.UI.UiSettings.Scale;
            Data.hud = (int)PushPals.UI.UiSettings.Hud;
        }

        /// <summary>Экран: запомнить и применить (полный экран, разрешение; 0×0 — текущее).</summary>
        public static void SetScreen(bool fullscreen, int width, int height) =>
            SetScreen(fullscreen ? VideoSettings.WindowMode.Borderless : VideoSettings.WindowMode.Windowed, width, height);

        /// <summary>Экран: режим окна и разрешение — применить и сохранить.</summary>
        public static void SetScreen(VideoSettings.WindowMode mode, int width, int height)
        {
            VideoSettings.ApplyScreen(mode, width, height);
            Save();
        }

        // Из сохранения — в игру
        private static void Apply()
        {
            applying = true;
            ApplyProgress();
            GameRules.LevelId = Data.levelId;
            GameRules.Burn = Mathf.Clamp(Data.burn, 0, GameRules.BurnScales.Length - 1);
            GameRules.FriendSlaps = Data.friendSlaps;
            GameRules.Access = (GameRules.Privacy)Mathf.Clamp(Data.access, 0, 2);
            VoiceSettings.Mic = (VoiceSettings.MicMode)Mathf.Clamp(Data.mic, 0, 2);
            VoiceSettings.Volume = Mathf.Clamp(Data.voiceVolume, 0, VoiceSettings.Volumes.Length - 1);
            SoundSettings.Master = Mathf.Clamp01(Data.masterVolume);
            SoundSettings.Music = Mathf.Clamp01(Data.musicVolume);
            SoundSettings.Effects = Mathf.Clamp01(Data.effectsVolume);
            VideoSettings.ShakeAmount = Data.shakeAmount >= 0f ? Mathf.Clamp01(Data.shakeAmount) : (Data.shake ? 1f : 0f);
            var mode = Data.windowMode >= 0 ? (VideoSettings.WindowMode)Mathf.Clamp(Data.windowMode, 0, 2)
                : Data.fullscreen ? VideoSettings.WindowMode.Borderless : VideoSettings.WindowMode.Windowed;
            VideoSettings.ApplyScreen(mode, Data.resWidth, Data.resHeight);
            VideoSettings.ApplyFrames(Data.vsync, Data.fpsCap);
            VideoSettings.ApplyEffects((VideoSettings.Quality)Mathf.Clamp(Data.effects, 0, 2));
            AccessSettings.SimpleControls = Data.simpleControls;
            AccessSettings.PlayerMarkers = Data.playerMarkers;
            AccessSettings.Subtitles = Data.subtitles;
            AccessSettings.MouseSensitivity = Mathf.Clamp(Data.mouseSensitivity, 0.25f, 2f);
            PushPals.UI.Loc.Code = Data.language;
            PushPals.UI.UiSettings.Scale = Data.uiScale > 0f ? Data.uiScale : 1f;
            PushPals.UI.UiSettings.Hud = (PushPals.UI.UiSettings.HudMode)Mathf.Clamp(Data.hud, 0, 2);
            applying = false;
        }

        // Прогресс уровней и колпак — в игру (достижения игра читает прямо из Data)
        private static void ApplyProgress()
        {
            var levels = new Dictionary<string, LevelProgress.Entry>();
            foreach (var l in Data.levels)
                if (l != null && !string.IsNullOrEmpty(l.id)) levels[l.id] = new LevelProgress.Entry { completed = l.done, golden = l.golden, bestTime = l.bestTime };
            LevelProgress.Load(levels);
            GameRules.PartyHatFound = Data.partyHat;
        }
    }
}
