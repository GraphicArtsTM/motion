namespace PushPals
{
    /// <summary>
    /// Настройки игры, которые хост выбирает в лобби (меню у доски): уровень, режим, время горения спичек,
    /// шлепки по друзьям, кто может войти. Живут между сценами. Физика и огонь смотрят сюда (решает хост),
    /// клиент получает их снимком доски в лобби — только чтобы показать.
    /// </summary>
    public static class GameRules
    {
        public enum GameMode { Coop = 0, Traitor = 1 }
        public enum Privacy { Friends = 0, Public = 1, Closed = 2 }

        /// <summary>Множители времени горения: обычно, ×1,5, ×2.</summary>
        public static readonly float[] BurnScales = { 1f, 1.5f, 2f };
        /// <summary>Сколько режимов и вариантов доступа (названия — на текущем языке: ModeName, PrivacyName).</summary>
        public const int ModeCount = 2, PrivacyCount = 3;

        public static string BurnName(int burn) => PushPals.UI.Loc.T("burn." + UnityEngine.Mathf.Clamp(burn, 0, BurnScales.Length - 1));
        public static string ModeName(GameMode mode) => PushPals.UI.Loc.T("mode." + (int)mode);
        public static string PrivacyName(Privacy access) => PushPals.UI.Loc.T("access." + (int)access);

        /// <summary>Уровень, который начнётся из лобби (id LevelDefinition; пусто — первый уровень мира).</summary>
        public static string LevelId { get; set; }
        public static GameMode Mode { get; set; }
        /// <summary>Номер в BurnScales.</summary>
        public static int Burn { get; set; }
        /// <summary>Шлепок и «боднуть» толкают друзей.</summary>
        public static bool FriendSlaps { get; set; } = true;
        public static Privacy Access { get; set; }
        /// <summary>Секрет лобби найден (кто-то забрался на полку): в шкафу появился праздничный колпак.</summary>
        public static bool PartyHatFound { get; set; }

        /// <summary>Во сколько раз дольше горит спичка.</summary>
        public static float BurnTimeScale => BurnScales[UnityEngine.Mathf.Clamp(Burn, 0, BurnScales.Length - 1)];

        /// <summary>Режим можно начать: «Предатель» — только по сети и от 3 людей (тайную роль за одним экраном не спрятать).</summary>
        public static bool ModeReady => ModeProblem.Length == 0;

        /// <summary>Почему режим нельзя начать (пусто — можно).</summary>
        public static string ModeProblem
        {
            get
            {
                if (Mode != GameMode.Traitor) return "";
                if (!Online.IsActive) return PushPals.UI.Loc.T("setup.problem_offline");
                if (Online.PeopleCount < 3) return PushPals.UI.Loc.T("setup.problem_people", Online.PeopleCount);
                return "";
            }
        }

        /// <summary>Что-то поменялось (сеть обновляет лобби Steam).</summary>
        public static event System.Action Changed;

        public static void NotifyChanged() { if (Changed != null) Changed(); }

        // Play в редакторе без перезагрузки домена: статика живёт между запусками — сбрасываем
        [UnityEngine.RuntimeInitializeOnLoadMethod(UnityEngine.RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStatics()
        {
            LevelId = null;
            Mode = GameMode.Coop;
            Burn = 0;
            FriendSlaps = true;
            Access = Privacy.Friends;
            PartyHatFound = false;
            Changed = null;
        }

        public static void Write(System.IO.BinaryWriter w)
        {
            w.Write(LevelId ?? "");
            w.Write((byte)Mode);
            w.Write((byte)Burn);
            w.Write(FriendSlaps);
            w.Write((byte)Access);
            w.Write(PartyHatFound);
        }

        public static void Read(System.IO.BinaryReader r)
        {
            LevelId = r.ReadString();
            Mode = (GameMode)r.ReadByte();
            Burn = r.ReadByte();
            FriendSlaps = r.ReadBoolean();
            Access = (Privacy)r.ReadByte();
            PartyHatFound = r.ReadBoolean();
        }
    }
}
