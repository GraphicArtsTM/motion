using PushPals.Ragdoll.Visual;
using PushPals.Save;

namespace PushPals.Level
{
    /// <summary>
    /// Шапки и дерево в шкафу (Этап 17.2): открываются за найденные золотые спички или за достижения — без цен и магазина.
    /// Праздничный колпак — секрет лобби (GameRules.PartyHatFound или достижение «Секрет коробка»).
    /// </summary>
    public static class Unlocks
    {
        /// <summary>Что нужно для вещи: столько золотых спичек всего или достижение (если задано).</summary>
        public struct Need
        {
            public int golden;
            public string achievement;
            public Need(int golden, string achievement = null) { this.golden = golden; this.achievement = achievement; }
        }

        /// <summary>По номеру шапки (MatchVisual.HatNames): без шапки, цилиндр, помпон, корона, каска, колпак, кепка, ушанка.</summary>
        public static readonly Need[] Hats =
        {
            new Need(0), new Need(3), new Need(6), new Need(0, Achievements.GoldenAll), new Need(9),
            new Need(0, Achievements.PartyHat), new Need(1), new Need(0, Achievements.NoBurn),
        };

        /// <summary>По номеру дерева (MatchVisual.WoodNames): светлое, тёмное, берёза, полоски, звёздочка.</summary>
        public static readonly Need[] Woods =
        {
            new Need(0), new Need(2), new Need(5), new Need(0, Achievements.World1), new Need(0, Achievements.World2),
        };

        /// <summary>Найдено золотых спичек всего.</summary>
        public static int Golden => LevelProgress.GoldenTotal();

        private static bool Met(Need n) => n.achievement != null ? Achievements.Has(n.achievement) : Golden >= n.golden;

        public static bool Hat(int hat)
        {
            if (hat < 0 || hat >= Hats.Length) return false;
            if (hat == MatchVisual.PartyHat && GameRules.PartyHatFound) return true;
            return Met(Hats[hat]);
        }

        public static bool Wood(int wood) => wood >= 0 && wood < Woods.Length && Met(Woods[wood]);

        /// <summary>«1 золотая спичка», «3 золотые спички», «5 золотых спичек».</summary>
        public static string GoldenText(int n)
        {
            int d = n % 10, h = n % 100;
            string word = d == 1 && h != 11 ? "золотая спичка" : d >= 2 && d <= 4 && (h < 12 || h > 14) ? "золотые спички" : "золотых спичек";
            return n + " " + word;
        }

        /// <summary>Сколько всего вещей открыто.</summary>
        public static int Count
        {
            get
            {
                int n = 0;
                for (int i = 0; i < MatchVisual.HatCount; i++) if (Hat(i)) n++;
                for (int i = 0; i < MatchVisual.WoodCount; i++) if (Wood(i)) n++;
                return n;
            }
        }

        /// <summary>Что открыто сейчас (маска шапок и дерева) — сравнить «до» и «после» уровня.</summary>
        public static int Mask
        {
            get
            {
                int m = 0;
                for (int i = 0; i < MatchVisual.HatCount; i++) if (Hat(i)) m |= 1 << i;
                for (int i = 0; i < MatchVisual.WoodCount; i++) if (Wood(i)) m |= 1 << (16 + i);
                return m;
            }
        }

        /// <summary>Что открылось между масками before → сейчас: (шапка?, номер) — названия переводит интерфейс.</summary>
        public static System.Collections.Generic.List<System.Collections.Generic.KeyValuePair<bool, int>> NewItems(int before)
        {
            int after = Mask;
            var list = new System.Collections.Generic.List<System.Collections.Generic.KeyValuePair<bool, int>>();
            for (int i = 0; i < MatchVisual.HatCount; i++)
                if ((after & (1 << i)) != 0 && (before & (1 << i)) == 0) list.Add(new System.Collections.Generic.KeyValuePair<bool, int>(true, i));
            for (int i = 0; i < MatchVisual.WoodCount; i++)
                if ((after & (1 << (16 + i))) != 0 && (before & (1 << (16 + i))) == 0) list.Add(new System.Collections.Generic.KeyValuePair<bool, int>(false, i));
            return list;
        }
    }
}
