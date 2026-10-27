using System;
using System.Collections.Generic;
using UnityEngine;

namespace PushPals.UI
{
    /// <summary>
    /// Локализация RU/EN (Этап 17.3). Таблица — Resources/Localization/strings.txt: «ключ ⇥ русский ⇥ английский»
    /// (строки с # — комментарии, \n в тексте — перенос строки). Текст в игре — только через Loc.T(ключ) или
    /// компонент LocText; нет перевода — показывается русский, нет ключа — сам ключ (видно, что забыли).
    /// Язык по умолчанию — язык системы (русский/белорусский/украинский/казахский → RU, иначе EN), выбор хранится в сохранении.
    /// </summary>
    public static class Loc
    {
        public enum Language { Ru, En }

        public static readonly string[] LanguageNames = { "Русский", "English" };

        private static Dictionary<string, string[]> table;
        // Русский текст → строка таблицы scene.*: для текстов, записанных в сценах прямо по-русски (таблички, двери)
        private static Dictionary<string, string[]> bySource;
        private static Language language = Language.Ru;
        private static bool chosen;

        /// <summary>Язык сменился — все LocText перерисовываются.</summary>
        public static event Action Changed;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStatics()
        {
            table = null;
            chosen = false;
        }

        public static Language Current
        {
            get
            {
                if (!chosen) { language = SystemDefault(); chosen = true; }
                return language;
            }
            set
            {
                chosen = true;
                if (language == value) return;
                language = value;
                if (Changed != null) Changed();
            }
        }

        /// <summary>Язык системы: славянские и соседние — русский, остальное — английский.</summary>
        public static Language SystemDefault()
        {
            switch (Application.systemLanguage)
            {
                case SystemLanguage.Russian:
                case SystemLanguage.Belarusian:
                case SystemLanguage.Ukrainian:
                    return Language.Ru;
                default:
                    return Language.En;
            }
        }

        /// <summary>Для сохранений: «ru», «en» или пусто (как в системе).</summary>
        public static string Code
        {
            get { return Current == Language.En ? "en" : "ru"; }
            set
            {
                if (value == "en") Current = Language.En;
                else if (value == "ru") Current = Language.Ru;
                else { language = SystemDefault(); chosen = true; if (Changed != null) Changed(); }
            }
        }

        /// <summary>Текст по ключу на текущем языке.</summary>
        public static string T(string key)
        {
            if (string.IsNullOrEmpty(key)) return "";
            if (table == null) Load();
            string[] row;
            if (!table.TryGetValue(key, out row)) return key;
            int i = (int)Current;
            return i < row.Length && !string.IsNullOrEmpty(row[i]) ? row[i] : row[0];
        }

        /// <summary>Текст с подстановкой {0}, {1}…</summary>
        public static string T(string key, params object[] args)
        {
            try { return string.Format(T(key), args); }
            catch (FormatException) { return T(key); }
        }

        public static bool Has(string key)
        {
            if (table == null) Load();
            return table.ContainsKey(key);
        }

        /// <summary>
        /// Текст, который в сцене или префабе записан прямо по-русски (табличка-подсказка, подпись двери):
        /// на русском — как есть, на другом языке — перевод из таблицы, где такой же русский текст; нет — как есть.
        /// Ключ таблицы тоже подходит.
        /// </summary>
        public static string Auto(string source)
        {
            if (string.IsNullOrEmpty(source)) return source;
            if (table == null) Load();
            string[] row;
            if (table.TryGetValue(source, out row) || bySource.TryGetValue(source, out row))
            {
                int i = (int)Current;
                return i < row.Length && !string.IsNullOrEmpty(row[i]) ? row[i] : row[0];
            }
            return source;
        }

        /// <summary>Перечитать таблицу (после правки файла).</summary>
        public static void Reload()
        {
            table = null;
            if (Changed != null) Changed();
        }

        private static void Load()
        {
            table = new Dictionary<string, string[]>();
            bySource = new Dictionary<string, string[]>();
            var file = Resources.Load<TextAsset>("Localization/strings");
            if (file == null) { Debug.LogWarning("[PushPals] Нет Resources/Localization/strings.txt"); return; }
            foreach (var raw in file.text.Split('\n'))
            {
                string line = raw.TrimEnd('\r');
                if (line.Length == 0 || line[0] == '#') continue;
                var parts = line.Split('\t');
                if (parts.Length < 2) continue;
                var row = new string[2];
                for (int i = 0; i < 2; i++) row[i] = i + 1 < parts.Length ? parts[i + 1].Replace("\\n", "\n") : "";
                table[parts[0].Trim()] = row;
                // По русскому тексту ищутся только строки scene.* (иначе «Выход»-кнопка и «Выход»-дверь спорили бы)
                if (parts[0].StartsWith("scene.") && !string.IsNullOrEmpty(row[0])) bySource[row[0]] = row;
            }
        }
    }
}
