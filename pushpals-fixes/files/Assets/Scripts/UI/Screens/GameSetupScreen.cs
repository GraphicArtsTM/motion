using System.Collections.Generic;
using PushPals.Level;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Настройки игры у доски в лобби — только хосту (за одним ПК — первому вошедшему): уровень (карта миров), режим,
    /// время горения спичек, шлепки по друзьям, кто может войти, онлайн; «Начать!» — отсчёт у всех.
    /// Открывается у доски (X / E) и из паузы. Заменяет временное меню HostMenu: тот же набор интерфейса, что у
    /// остальных экранов, и перевод на язык игры. Карта миров и «Онлайн» открываются поверх — закрылись, и снова здесь.
    /// </summary>
    public class GameSetupScreen : UiScreen
    {
        private TextMeshProUGUI levelText, goalText, problemText;
        private Button startButton;
        private LocText startLabel;
        private float refreshClock;

        /// <summary>Открыть (null — уже открыт другой экран или это не лобби).</summary>
        public static GameSetupScreen Open()
        {
            if (LobbyBoard.Instance == null) return null;
            return Create<GameSetupScreen>("Game Setup Screen", true, true, UiPanel.Motion.Drawer);
        }

        protected override void Build()
        {
            var area = Paper(new Vector2(1240f, 930f), "setup.title");
            var f = new UiForm(area);

            // Уровень: что выбрано и кнопка «Выбрать» (карта миров)
            var levelRow = f.Row("setup.level", 84f);
            levelText = Ink(levelRow, "", 28f);
            levelText.rectTransform.anchorMin = Vector2.zero;
            levelText.rectTransform.anchorMax = Vector2.one;
            levelText.rectTransform.offsetMin = Vector2.zero;
            levelText.rectTransform.offsetMax = new Vector2(-230f, 0f);
            levelText.enableAutoSizing = true;
            levelText.fontSizeMin = 18f;
            levelText.fontSizeMax = 28f;
            var choose = UiPrefabs.Spawn<Button>("SecondaryButton", levelRow);
            var crt = (RectTransform)choose.transform;
            crt.anchorMin = crt.anchorMax = new Vector2(1f, 0.5f);
            crt.pivot = new Vector2(1f, 0.5f);
            crt.sizeDelta = new Vector2(220f, 66f);
            crt.anchoredPosition = Vector2.zero;
            choose.GetComponentInChildren<LocText>().Key = "setup.choose";
            choose.onClick.AddListener(() => WorldMapScreen.Open(true));
            goalText = Tall(f.Note("setup.goal", ""), 64f);

            f.Choice("setup.mode", Names(GameRules.ModeCount, i => GameRules.ModeName((GameRules.GameMode)i)), (int)GameRules.Mode,
                i => { GameRules.Mode = (GameRules.GameMode)i; GameRules.NotifyChanged(); Refresh(); });
            f.Choice("setup.burn", Names(GameRules.BurnScales.Length, GameRules.BurnName), GameRules.Burn,
                i => { GameRules.Burn = i; GameRules.NotifyChanged(); });
            f.Toggle("setup.slaps", GameRules.FriendSlaps, v => { GameRules.FriendSlaps = v; GameRules.NotifyChanged(); });
            f.Choice("setup.access", Names(GameRules.PrivacyCount, i => GameRules.PrivacyName((GameRules.Privacy)i)), (int)GameRules.Access,
                i => { GameRules.Access = (GameRules.Privacy)i; GameRules.NotifyChanged(); });
            f.Note("setup.access_note");
            f.Button("setup.online", false, () => OnlineScreen.Open(false));

            // Почему нельзя начать (режим «Предатель» без сети или людей мало)
            problemText = Tall(f.Note("setup.goal", ""), 40f);
            problemText.color = Theme.accent;
            startButton = f.Button("setup.start", true, StartOrCancel);
            startLabel = startButton.GetComponentInChildren<LocText>();

            BackButton(Rect, new Vector2(0.5f, 0f), new Vector2(0f, 40f));
            Panel.FirstSelected = startButton;
            Refresh();
        }

        private static List<string> Names(int count, System.Func<int, string> name)
        {
            var list = new List<string>();
            for (int i = 0; i < count; i++) list.Add(name(i));
            return list;
        }

        // Пояснение повыше (в одну строку не влезает)
        private static TextMeshProUGUI Tall(TextMeshProUGUI note, float height)
        {
            var fit = note.transform.parent.GetComponent<LayoutElement>();
            if (fit != null) fit.preferredHeight = height;
            return note;
        }

        private void StartOrCancel()
        {
            var board = LobbyBoard.Instance;
            if (board == null) return;
            if (board.Counting) { board.CancelCountdown(); Refresh(); return; }
            board.StartCountdown();
            if (board.Counting) { Close(); PauseScreen.CloseIfOpen(); } // отсчёт идёт — смотрим на доску и коробок
            else Refresh();
        }

        private void Update()
        {
            refreshClock -= Time.unscaledDeltaTime;
            if (refreshClock > 0f) return;
            refreshClock = 0.25f;
            Refresh();
        }

        // Уровень и цель могли смениться на карте миров, люди — подключиться
        private void Refresh()
        {
            var board = LobbyBoard.Instance;
            var level = board != null ? board.Selected : null;
            levelText.text = level == null ? Loc.T("board.none")
                : Loc.T("setup.level_golden", board.Title(level), Mathf.Min(LevelProgress.Golden(level.id), level.goldenCount), level.goldenCount);
            string goalKey = level != null ? "goal." + level.id : "";
            goalText.text = level != null && Loc.Has(goalKey) ? Loc.T("setup.goal", Loc.T(goalKey))
                : level != null && !string.IsNullOrEmpty(level.goal) ? Loc.T("setup.goal", level.goal) : "";
            bool counting = board != null && board.Counting;
            problemText.text = counting ? "" : GameRules.ModeProblem;
            startLabel.Key = counting ? "setup.cancel" : "setup.start";
            startButton.interactable = counting || (level != null && GameRules.ModeReady);
        }
    }
}
