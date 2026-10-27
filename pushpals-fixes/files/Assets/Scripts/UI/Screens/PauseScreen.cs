using System.Collections.Generic;
using PushPals.Input;
using PushPals.Level;
using TMPro;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Пауза (Этап 17.5) — короткое нажатие Start / Esc. Время не останавливается (играете вместе, по сети — тем более).
    /// Слева — список: продолжить, настройки игры (хосту в лобби), онлайн (код, приглашения, кто в игре), настройки,
    /// заново и в коробок (кто решает — на уровне), главное меню, выйти из игры (оба — с вопросом «точно?»).
    /// Справа — уровень, золотые спички, время. «Назад» — продолжить.
    /// </summary>
    public class PauseScreen : UiScreen
    {
        private static bool hostNext;
        private bool host;
        private static PauseScreen current;

        /// <summary>Закрыть паузу, если открыта (настройки игры над ней начали отсчёт — пора смотреть на доску).</summary>
        public static void CloseIfOpen()
        {
            if (current != null) current.Close();
        }

        private void OnDestroy() { if (current == this) current = null; }

        /// <summary>Открыть паузу (host — может менять настройки игры; byPlayer — ввод игрока, открывшего паузу).</summary>
        public static PauseScreen Open(bool isHost, PlayerIntentReader byPlayer)
        {
            hostNext = isHost;
            return Create<PauseScreen>("Pause Screen", true, true, UiPanel.Motion.Fade);
        }

        protected override void Build()
        {
            host = hostNext;
            current = this;
            bool inLobby = LobbyBoard.Instance != null;
            bool decides = !Online.IsClientView;
            // Тень слева под списком — светлый уровень не мешает читать
            var shade = UiFactory.Fade(Rect, "Shade", true, new Color(0f, 0f, 0f, 0.55f));
            shade.rectTransform.anchorMin = Vector2.zero;
            shade.rectTransform.anchorMax = new Vector2(0f, 1f);
            shade.rectTransform.pivot = new Vector2(0f, 0.5f);
            shade.rectTransform.sizeDelta = new Vector2(1100f, 0f);
            // Заголовок
            var title = UiFactory.LocText(Rect, "pause.title", 84f, Theme.inkLight, true);
            title.alignment = TextAlignmentOptions.MidlineLeft;
            UiFactory.Place(title.rectTransform, new Vector2(0f, 1f), new Vector2(700f, 110f), new Vector2(470f, -170f));
            title.gameObject.AddComponent<Shadow>().effectColor = new Color(0f, 0f, 0f, 0.7f);
            // Список
            var list = UiFactory.Rect(Rect, "Items");
            list.anchorMin = list.anchorMax = new Vector2(0f, 1f);
            list.pivot = new Vector2(0f, 1f);
            list.anchoredPosition = new Vector2(160f, -260f);
            list.sizeDelta = new Vector2(620f, 600f);
            var layout = list.gameObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 6f;
            layout.childControlWidth = true;
            layout.childControlHeight = false;
            layout.childForceExpandHeight = false;
            Item(list, "pause.resume", Close);
            // Настройки игры, онлайн и настройки — поверх паузы: закрыли — снова пауза
            if (inLobby && host) Item(list, "pause.host", () => GameSetupScreen.Open());
            Item(list, "menu.online", () => OnlineScreen.Open(false));
            Item(list, "menu.settings", () => SettingsScreen.Open());
            // Посреди уровня — сначала «точно?»: прохождение начнётся сначала (по сети — у всех)
            if (!inLobby && decides && LevelRun.Instance != null)
                Item(list, "pause.restart", () => Confirm("pause.restart_confirm", "pause.restart", () =>
                {
                    var run = LevelRun.Instance;
                    LevelLoader.Load(SceneManager.GetActiveScene().name, run != null ? UiNames.Level(run.Level) : "");
                }));
            if (!inLobby && decides && LevelLoader.Exists(LevelLoader.LobbyScene))
                Item(list, "pause.lobby", () => Confirm("pause.lobby_confirm", "pause.lobby", () => LevelLoader.Load(LevelLoader.LobbyScene)));
            Item(list, "pause.main_menu", AskMainMenu);
            Item(list, "pause.quit", AskQuit);
            // Сводка справа
            var run = LevelRun.Instance;
            if (run != null && run.Level != null)
            {
                var card = UiCard.Create(Rect, 560f, false);
                var rt = card.Rect;
                rt.anchorMin = rt.anchorMax = new Vector2(1f, 1f);
                rt.pivot = new Vector2(1f, 1f);
                rt.anchoredPosition = new Vector2(-150f, -240f);
                int wn = WorldCatalog.NumberOf(run.World);
                card.Set((wn > 0 ? Loc.T("result.world", wn, UiNames.World(wn, run.World)) + "\n" : "") + UiNames.Level(run.Level),
                    Loc.T("result.golden", run.GoldenFound, run.Level.goldenCount) + "\n" + Loc.T("result.time", LevelDefinition.FormatTime(run.Elapsed)));
            }
            var note = UiFactory.LocText(Rect, Online.IsActive ? "pause.note_online" : "pause.note_local", 26f, Theme.inkLight, false);
            note.alignment = TextAlignmentOptions.MidlineLeft;
            UiFactory.Place(note.rectTransform, new Vector2(0f, 0f), new Vector2(900f, 40f), new Vector2(160f + 450f, 70f));
        }

        private void Item(RectTransform list, string key, System.Action onClick)
        {
            var item = UiPrefabs.Spawn<UiMenuItem>("MenuListItem", list);
            ((RectTransform)item.transform).sizeDelta = new Vector2(620f, 80f);
            item.GetComponentInChildren<LocText>().Key = key;
            item.GetComponent<Button>().onClick.AddListener(() => onClick());
        }

        private void AskQuit() => UiDialog.Confirm("menu.quit_confirm", Online.IsActive ? "pause.leave_online" : "settings.saved", "menu.exit", MainMenuScreen.QuitGame);

        // Уровень пройден наполовину: подтвердить, потом закрыть паузу и сделать
        private void Confirm(string titleKey, string confirmKey, System.Action action)
        {
            bool finished = LevelRun.Instance != null && LevelRun.Instance.Finished;
            if (finished) { Close(); action(); return; } // уровень уже пройден — терять нечего
            UiDialog.Confirm(titleKey, Online.IsActive ? "pause.progress_lost_online" : "pause.progress_lost", confirmKey, () => { Close(); action(); });
        }

        // В главное меню: по сети — сначала «точно?» (игра закончится), без сети — сразу (всё сохранено)
        private void AskMainMenu()
        {
            if (!Online.IsActive) { ToMainMenu(); return; }
            UiDialog.Confirm("pause.main_menu_confirm", "pause.leave_online", "pause.main_menu", ToMainMenu);
        }

        private void ToMainMenu()
        {
            Close();
            MainMenuScreen.ReturnFromGame();
        }
    }
}
