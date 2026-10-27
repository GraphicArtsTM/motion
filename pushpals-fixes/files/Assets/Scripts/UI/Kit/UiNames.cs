using PushPals.Level;
using PushPals.Save;

namespace PushPals.UI
{
    /// <summary>Названия на текущем языке: уровни, миры, шапки, дерево, достижения, условия открытия (Этап 17.4).</summary>
    public static class UiNames
    {
        static bool En => Loc.Current == Loc.Language.En;

        /// <summary>Уровень: перевод по ключу level.&lt;id&gt;, иначе имя из описания.</summary>
        public static string Level(LevelDefinition level)
        {
            if (level == null) return "—";
            string key = "level." + level.id;
            return Loc.Has(key) ? Loc.T(key) : level.displayName;
        }

        /// <summary>Мир номер n (с 1).</summary>
        public static string World(int n, WorldDefinition world)
        {
            string key = "world." + n;
            return Loc.Has(key) ? Loc.T(key) : world != null ? world.displayName : "";
        }

        /// <summary>Спичка (Тяжёлый, Маленький, Лёгкий, Магнит).</summary>
        public static string Match(PushPals.Abilities.MatchKind kind) => Loc.T("match." + (int)kind);

        /// <summary>«Тяжёлый + Маленький».</summary>
        public static string Matches(System.Collections.Generic.IList<PushPals.Abilities.MatchKind> kinds)
        {
            string s = "";
            foreach (var k in kinds) s += (s.Length > 0 ? " + " : "") + Match(k);
            return s;
        }

        public static string Hat(int i) => Loc.T("hat." + i);
        public static string Wood(int i) => Loc.T("wood." + i);

        public static string AchievementName(Achievements.Info a) => En && !string.IsNullOrEmpty(a.nameEn) ? a.nameEn : a.name;
        public static string AchievementText(Achievements.Info a) => En && !string.IsNullOrEmpty(a.descriptionEn) ? a.descriptionEn : a.description;

        /// <summary>Чем открывается: «3 золотые спички» / «3 golden matches» или «достижение «…»».</summary>
        public static string Need(Unlocks.Need n)
        {
            if (n.achievement != null)
            {
                var a = Achievements.Find(n.achievement);
                string name = a != null ? AchievementName(a) : n.achievement;
                return En ? "achievement “" + name + "”" : "достижение «" + name + "»";
            }
            if (En) return n.golden + (n.golden == 1 ? " golden match" : " golden matches");
            return Unlocks.GoldenText(n.golden);
        }
    }
}
