using PushPals.Level;
using UnityEngine;

namespace PushPals.UI
{
    /// <summary>
    /// Настройки игры у доски в лобби — только хосту (за одним ПК — первому вошедшему): уровень, режим,
    /// время горения спичек, шлепки по друзьям, кто может войти; «Начать» — отсчёт у всех.
    /// </summary>
    public class HostMenu : PlayerMenu
    {
        private const int LevelRow = 0, ModeRow = 1, BurnRow = 2, SlapRow = 3, AccessRow = 4, NetRow = 5, StartRow = 6;

        protected override string Title => "Настройки игры (хост)";
        protected override int RowCount => 7;

        private static LobbyBoard Board => LobbyBoard.Instance;

        /// <summary>Закрылось ради экрана (карта миров, онлайн) — после него вернуться сюда, к «Начать!».</summary>
        public bool ReturnAfterScreen { get; private set; }

        protected override string Label(int row)
        {
            switch (row)
            {
                case LevelRow: return "Уровень";
                case ModeRow: return "Режим";
                case BurnRow: return "Спички горят";
                case SlapRow: return "Шлепки по друзьям";
                case AccessRow: return "Кто может войти";
                case NetRow:
                {
                    string code = Online.LobbyCode != null ? Online.LobbyCode() : "";
                    return code.Length > 0 ? "Онлайн — код для друзей: " + code : "Онлайн: создать игру и пригласить друзей";
                }
                default:
                    if (Board != null && Board.Counting) return "Отменить старт";
                    return GameRules.ModeReady ? "Начать!" : "Начать — " + GameRules.ModeProblem;
            }
        }

        protected override bool IsButton(int row) => row == StartRow || row == NetRow;
        protected override bool Enabled(int row) => row != StartRow || GameRules.ModeReady || (Board != null && Board.Counting);

        protected override string Value(int row)
        {
            switch (row)
            {
                case LevelRow:
                {
                    var level = Board != null ? Board.Selected : null;
                    if (level == null) return "—";
                    return Board.Title(level) + "  (золотых " + LevelProgress.Golden(level.id) + " из " + level.goldenCount + ")";
                }
                case ModeRow: return GameRules.ModeNames[(int)GameRules.Mode];
                case BurnRow: return GameRules.BurnNames[GameRules.Burn];
                case SlapRow: return GameRules.FriendSlaps ? "да" : "нет";
                case AccessRow: return GameRules.PrivacyNames[(int)GameRules.Access];
                default: return "";
            }
        }

        protected override string Note
        {
            get
            {
                var level = Board != null ? Board.Selected : null;
                string goal = level != null && !string.IsNullOrEmpty(level.goal) ? "Цель: " + level.goal + "\n" : "";
                return goal + "Миры 3–5 — скоро. Шапки и спички — в шкафу.";
            }
        }

        protected override void Change(int row, int dir)
        {
            switch (row)
            {
                case LevelRow: if (Board != null) Board.Select(dir); return;
                case ModeRow: GameRules.Mode = (GameRules.GameMode)Cycle((int)GameRules.Mode, dir, GameRules.ModeNames.Length); break;
                case BurnRow: GameRules.Burn = Cycle(GameRules.Burn, dir, GameRules.BurnScales.Length); break;
                case SlapRow: GameRules.FriendSlaps = !GameRules.FriendSlaps; break;
                case AccessRow: GameRules.Access = (GameRules.Privacy)Cycle((int)GameRules.Access, dir, GameRules.PrivacyNames.Length); break;
                default: return;
            }
            GameRules.NotifyChanged();
        }

        protected override void Press(int row)
        {
            if (row == NetRow)
            {
                // Экран «Онлайн» (Steam-лобби, приглашения, код) — раньше открывалась отладочная панель F2
                ReturnAfterScreen = true;
                Close();
                OnlineScreen.Open(false);
                return;
            }
            // Уровень — на карте миров (Этап 17.4); стрелками по-прежнему листается здесь
            if (row == LevelRow) { ReturnAfterScreen = true; Close(); WorldMapScreen.Open(true); return; }
            if (row != StartRow) { Change(row, 1); return; }
            if (Board == null) return;
            if (Board.Counting) Board.CancelCountdown();
            else { Board.StartCountdown(); if (Board.Counting) Close(); }
        }

        private static int Cycle(int value, int dir, int count) => (value + dir + count) % count;
    }
}
