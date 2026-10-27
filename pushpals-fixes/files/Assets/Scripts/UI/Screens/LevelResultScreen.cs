using System.Collections.Generic;
using PushPals.Level;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Итог уровня (Этап 17.5): «Уровень пройден!», название, золотые спички (новые подпрыгивают), время и рекорд,
    /// сколько сгорело, золотые в мире, новое в шкафу. В режиме «Предатель» — голосование кнопками (за кого —
    /// значки игроков) и итог раскрытия. «Дальше» и «В коробок» — у того, кто решает (хост или игра без сети);
    /// у сетевого клиента — «Ждём хоста». Автопереход — как раньше (LevelRun). «Назад» не закрывает.
    /// </summary>
    public class LevelResultScreen : UiScreen
    {
        private LevelRun run;
        private Button next, lobby, replay;
        private TextMeshProUGUI auto;
        private RectTransform traitorArea;
        private TextMeshProUGUI traitorText;
        private readonly List<Button> voteButtons = new List<Button>();
        private string traitorState = "";
        private readonly List<RectTransform> newGolden = new List<RectTransform>();

        private static LevelRun pending;
        private const float minPaperHeight = 520f;

        public static void Open(LevelRun levelRun)
        {
            pending = levelRun;
            Create<LevelResultScreen>("Level Result", true, true, UiPanel.Motion.Drawer);
        }

        protected override void Build()
        {
            run = pending;
            Panel.Configure(UiPanel.Motion.Drawer, UiPanel.Side.Bottom, false); // итог «назад» не закрывает
            bool traitor = TraitorRound.Instance != null && Online.IsActive;
            var area = Paper(new Vector2(1180f, minPaperHeight), "result.title");
            var level = run != null ? run.Level : null;
            var world = run != null ? run.World : null;
            float y = -10f;
            // Название уровня
            int wn = WorldCatalog.NumberOf(world);
            var title = Line(area, (wn > 0 ? Loc.T("result.world", wn, UiNames.World(wn, world)) + " · " : "") + UiNames.Level(level), 36f, true, ref y, 56f);
            title.color = Theme.ink;
            // Золотые спички
            if (level != null && level.goldenCount > 0)
            {
                int found = run.GoldenFound, fresh = run.GoldenNew;
                var row = UiFactory.Rect(area, "Golden");
                UiFactory.Place(row, new Vector2(0.5f, 1f), new Vector2(600f, 96f), new Vector2(0f, y - 48f));
                for (int i = 0; i < level.goldenCount; i++)
                {
                    bool lit = i < found;
                    var icon = UiFactory.Image(row, lit ? "ic_golden_match" : "ic_golden_match_empty", false, "Golden");
                    UiFactory.Place(icon.rectTransform, new Vector2(0.5f, 0.5f), new Vector2(88f, 88f), new Vector2((i - (level.goldenCount - 1) * 0.5f) * 104f, 0f));
                    if (!lit) icon.color = new Color(1f, 1f, 1f, 0.55f);
                    if (lit && i >= found - fresh) newGolden.Add(icon.rectTransform); // найденные сейчас — подпрыгивают
                }
                y -= 104f;
                string tail = fresh > 0 ? Loc.T("result.new_golden", fresh) : found >= level.goldenCount ? Loc.T("result.all_found") : Loc.T("result.some_hidden");
                Line(area, Loc.T("result.golden", found, level.goldenCount) + "  ·  " + tail, 28f, false, ref y, 40f);
            }
            // Время, рекорд, сгоревшие
            if (run != null)
            {
                string time = Loc.T("result.time", LevelDefinition.FormatTime(run.Elapsed));
                if (run.BestBefore > 0f) time += "  ·  " + (run.Elapsed < run.BestBefore ? Loc.T("result.record") : Loc.T("result.record_was", LevelDefinition.FormatTime(run.BestBefore)));
                else time += "  ·  " + Loc.T("result.record");
                time += "  ·  " + Loc.T("result.burned", run.Ghosts);
                Line(area, time, 28f, false, ref y, 40f);
            }
            if (world != null) Line(area, Loc.T("result.world_golden", LevelProgress.GoldenFound(world), LevelProgress.GoldenMax(world)), 26f, false, ref y, 38f).color = Theme.inkMuted;
            // Новое в шкафу
            if (run != null)
            {
                var items = Unlocks.NewItems(run.UnlocksAtStart);
                if (items.Count > 0)
                {
                    var names = new List<string>();
                    foreach (var it in items) names.Add(it.Key ? UiNames.Hat(it.Value) : UiNames.Wood(it.Value));
                    var gift = Line(area, Loc.T("result.new_items", string.Join(", ", names.ToArray())), 30f, true, ref y, 48f);
                    gift.color = Theme.accent;
                }
            }
            // «Предатель»
            if (traitor)
            {
                traitorArea = UiFactory.Rect(area, "Traitor");
                UiFactory.Place(traitorArea, new Vector2(0.5f, 1f), new Vector2(1040f, 260f), new Vector2(0f, y - 140f));
                traitorText = UiFactory.Text(traitorArea, "", 26f, Theme.ink, false);
                traitorText.textWrappingMode = TextWrappingModes.Normal;
                traitorText.alignment = TextAlignmentOptions.Top;
                UiRoot.Stretch(traitorText.rectTransform);
                traitorText.rectTransform.offsetMin = new Vector2(0f, 110f);
            }
            // Лист — по содержимому, кнопки — сразу под ним (лист и кнопки вместе по центру экрана)
            var paper = (RectTransform)area.parent;
            float paperHeight = Mathf.Max(minPaperHeight, -y + (traitor ? 280f : 0f) + 200f);
            paper.sizeDelta = new Vector2(paper.sizeDelta.x, paperHeight);
            paper.anchoredPosition = new Vector2(0f, 70f);
            float bottom = 70f - paperHeight * 0.5f;
            // Кнопки
            // «Дальше» · «Заново» · «В коробок»
            var buttons = UiFactory.Rect(Rect, "Buttons");
            UiFactory.Place(buttons, new Vector2(0.5f, 0.5f), new Vector2(1200f, 90f), new Vector2(0f, bottom - 75f));
            var nextLevel = run != null ? run.NextLevel : null;
            next = UiPrefabs.Spawn<Button>("PrimaryButton", buttons);
            UiFactory.Place((RectTransform)next.transform, new Vector2(0.5f, 0.5f), new Vector2(440f, 86f), new Vector2(-370f, 0f));
            var nextLabel = next.GetComponentInChildren<LocText>();
            if (nextLevel != null) nextLabel.Set("result.next", UiNames.Level(nextLevel)); else nextLabel.Key = "result.world_done";
            next.onClick.AddListener(() => { if (run != null) run.Continue(); });
            // Заново — раньше только удержанием R / Select, кнопки на итоге не было
            replay = UiPrefabs.Spawn<Button>("SecondaryButton", buttons);
            UiFactory.Place((RectTransform)replay.transform, new Vector2(0.5f, 0.5f), new Vector2(320f, 86f), new Vector2(40f, 0f));
            replay.GetComponentInChildren<LocText>().Key = "pause.restart";
            replay.onClick.AddListener(() => { if (run != null) run.Restart(); });
            lobby = UiPrefabs.Spawn<Button>("SecondaryButton", buttons);
            UiFactory.Place((RectTransform)lobby.transform, new Vector2(0.5f, 0.5f), new Vector2(320f, 86f), new Vector2(380f, 0f));
            lobby.GetComponentInChildren<LocText>().Key = "result.lobby";
            lobby.onClick.AddListener(() => { if (run != null) run.ToLobby(); });
            lobby.gameObject.SetActive(nextLevel != null && LevelLoader.Exists(LevelLoader.LobbyScene));
            if (!lobby.gameObject.activeSelf) // двух кнопок — по центру
            {
                ((RectTransform)next.transform).anchoredPosition = new Vector2(-190f, 0f);
                ((RectTransform)replay.transform).anchoredPosition = new Vector2(220f, 0f);
            }
            auto = UiFactory.Text(Rect, "", 24f, Theme.inkLight, false);
            UiFactory.Place(auto.rectTransform, new Vector2(0.5f, 0.5f), new Vector2(800f, 34f), new Vector2(0f, bottom - 145f));
            auto.gameObject.AddComponent<Shadow>().effectColor = new Color(0f, 0f, 0f, 0.7f);
            Panel.FirstSelected = next;
            Refresh();
        }

        // Строка текста по центру сверху вниз
        private TextMeshProUGUI Line(RectTransform area, string text, float size, bool heading, ref float y, float height)
        {
            var t = UiFactory.Text(area, text, size, Theme.ink, heading);
            t.textWrappingMode = TextWrappingModes.Normal;
            UiFactory.Place(t.rectTransform, new Vector2(0.5f, 1f), new Vector2(1040f, height), new Vector2(0f, y - height * 0.5f));
            y -= height + 6f;
            return t;
        }

        private void Update()
        {
            // Новые золотые спички подпрыгивают
            float t = Time.unscaledTime;
            foreach (var g in newGolden) g.localScale = Vector3.one * (1f + 0.12f * Mathf.Abs(Mathf.Sin(t * 4f)));
            Refresh();
        }

        private void Refresh()
        {
            if (run == null) return;
            bool decides = !Online.IsClientView;
            bool waitVote = TraitorRound.Instance != null && TraitorRound.Instance.BlocksContinue;
            next.gameObject.SetActive(decides);
            replay.gameObject.SetActive(decides);
            if (lobby.gameObject.activeSelf && !decides) lobby.gameObject.SetActive(false);
            next.interactable = run.CanContinue;
            replay.interactable = run.CanContinue;
            lobby.interactable = run.CanContinue;
            if (!decides) auto.text = Loc.T("result.waiting_host");
            else if (waitVote) auto.text = Loc.T("result.waiting_vote");
            else auto.text = run.ContinueIn > 0f ? Loc.T("result.auto", Mathf.CeilToInt(run.ContinueIn)) : "";
            if (traitorArea != null) RefreshTraitor();
        }

        // Голосование: значки других игроков — кнопки; потом «голос отдан», потом итог
        private void RefreshTraitor()
        {
            var round = TraitorRound.Instance;
            if (round == null) return;
            string state = round.IsRevealed ? "result" : round.Voted ? "voted" : round.CanVote ? "vote" : "wait";
            if (state == traitorState) return;
            traitorState = state;
            foreach (var b in voteButtons) if (b != null) Destroy(b.gameObject);
            voteButtons.Clear();
            switch (state)
            {
                case "result":
                    traitorText.rectTransform.offsetMin = Vector2.zero;
                    traitorText.text = "<b>" + Loc.T("traitor.result_title") + "</b>\n" + round.Result;
                    break;
                case "voted":
                    traitorText.text = "<b>" + Loc.T("traitor.vote_title") + "</b>\n" + Loc.T("traitor.voted");
                    break;
                case "vote":
                    traitorText.text = "<b>" + Loc.T("traitor.vote_title") + "</b>  " + Loc.T("traitor.vote_hint");
                    var list = round.Candidates;
                    for (int i = 0; i < list.Count; i++)
                    {
                        ulong id = list[i];
                        var b = UiPrefabs.Spawn<Button>("SecondaryButton", traitorArea);
                        UiFactory.Place((RectTransform)b.transform, new Vector2(0.5f, 0f), new Vector2(300f, 86f), new Vector2((i - (list.Count - 1) * 0.5f) * 320f, 10f));
                        var loc = b.GetComponentInChildren<LocText>();
                        var label = loc.GetComponent<TMP_Text>();
                        Destroy(loc);
                        label.text = TraitorRound.NameOf(id);
                        b.onClick.AddListener(() => round.CastVote(id));
                        voteButtons.Add(b);
                    }
                    if (voteButtons.Count > 0) { UiButtonFx.QuietFrame = Time.frameCount; UnityEngine.EventSystems.EventSystem.current.SetSelectedGameObject(voteButtons[0].gameObject); }
                    break;
                default:
                    traitorText.text = "";
                    break;
            }
        }
    }
}
