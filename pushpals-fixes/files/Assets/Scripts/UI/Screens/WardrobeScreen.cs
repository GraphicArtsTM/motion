using System.Collections.Generic;
using PushPals.Abilities;
using PushPals.Level;
using PushPals.Players;
using PushPals.Ragdoll.Visual;
using PushPals.Save;
using TMPro;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Гардероб (Этап 17.4, шкаф из напёрстков на столе): игрок 1–4 за этим ПК (по сети — свой), шапка и дерево.
    /// Наведение или выбор — примерить на манекене (и закрытое — посмотреть), нажатие — надеть (только открытое),
    /// у закрытого — чем открывается. Сохраняется сразу; если игрок уже в лобби — меняется и на его спичке.
    /// У шкафа в лобби (OpenFor) — для того, кто подошёл: его шапка и дерево и какие спички он хочет
    /// (раньше там было отдельное временное меню со своими кнопками, только по-русски, с дублем настроек голоса).
    /// </summary>
    public class WardrobeScreen : UiScreen
    {
        private static readonly MatchKind[] PairA = { MatchKind.Heavy, MatchKind.Small };
        private static readonly MatchKind[] PairB = { MatchKind.Light, MatchKind.Magnet };
        private static readonly MatchKind[] Singles = { MatchKind.Heavy, MatchKind.Small, MatchKind.Light, MatchKind.Magnet };

        private static Player ownerNext;

        private int slot, hat, wood;
        private Player owner;             // открыли у шкафа: этот игрок (null — со стола главного меню)
        private bool hadOwner;
        private MatchPreview preview;
        private TextMeshProUGUI info, ruleText;
        private TMP_Dropdown matchChoice;
        private List<MatchKind[]> matchOptions = new List<MatchKind[]>();
        private string shownOptions = "";
        private float refreshClock;
        private readonly List<Button> slotButtons = new List<Button>();
        private readonly List<int> slotNumbers = new List<int>();
        private readonly List<UiMenuItem> hatItems = new List<UiMenuItem>(), woodItems = new List<UiMenuItem>();

        /// <summary>Со стола главного меню: игроки 1–4 за этим ПК (по сети — свой).</summary>
        public static WardrobeScreen Open()
        {
            ownerNext = null;
            return Create<WardrobeScreen>("Wardrobe Screen", true, true, UiPanel.Motion.Drawer);
        }

        /// <summary>У шкафа в лобби: для этого игрока — шапка, дерево и спички.</summary>
        public static WardrobeScreen OpenFor(Player player)
        {
            ownerNext = player;
            return Create<WardrobeScreen>("Wardrobe Screen", true, true, UiPanel.Motion.Drawer);
        }

        private bool Network => Online.IsActive;

        protected override void Build()
        {
            owner = ownerNext;
            ownerNext = null;
            hadOwner = owner != null;
            var area = Paper(new Vector2(1480f, 930f), "wardrobe.title");
            // Игроки за этим ПК (по сети — только свой; у шкафа — тот, кто подошёл)
            slotButtons.Clear();
            slotNumbers.Clear();
            int slots = owner != null || Network ? 1 : 4;
            for (int i = 0; i < slots; i++)
            {
                int n = Network ? 0 : owner != null ? Mathf.Clamp(owner.Index, 0, 3) : i;
                var b = UiPrefabs.Spawn<Button>("SecondaryButton", area);
                var rt = (RectTransform)b.transform;
                UiFactory.Place(rt, new Vector2(0f, 1f), new Vector2(220f, 70f), new Vector2(120f + i * 232f, -36f));
                var label = b.GetComponentInChildren<LocText>();
                label.Set("wardrobe.player", owner != null ? owner.Index + 1 : n + 1);
                label.GetComponent<TMP_Text>().fontSizeMax = 26f;
                b.onClick.AddListener(() => SelectSlot(n));
                slotButtons.Add(b);
                slotNumbers.Add(n);
            }
            // Манекен (у шкафа — пониже, под ним выбор спичек)
            var stage = UiFactory.Rect(area, "Preview");
            if (owner != null) UiFactory.Place(stage, new Vector2(0f, 0.5f), new Vector2(300f, 380f), new Vector2(190f, 30f));
            else UiFactory.Place(stage, new Vector2(0f, 0.5f), new Vector2(340f, 460f), new Vector2(190f, -40f));
            var shelf = UiFactory.Image(stage, "card_level", true, "Frame");
            UiRoot.Stretch(shelf.rectTransform);
            shelf.rectTransform.offsetMin = new Vector2(-20f, -20f);
            shelf.rectTransform.offsetMax = new Vector2(20f, 20f);
            var raw = UiFactory.Rect(stage, "Match").gameObject.AddComponent<RawImage>();
            UiRoot.Stretch(raw.rectTransform);
            raw.raycastTarget = false;
            preview = raw.gameObject.AddComponent<MatchPreview>();
            // Списки
            hatItems.Clear();
            woodItems.Clear();
            var hats = Column(area, "wardrobe.hat", 420f);
            for (int i = 0; i < MatchVisual.HatCount; i++) hatItems.Add(Item(hats, true, i));
            var woods = Column(area, "wardrobe.wood", 890f);
            for (int i = 0; i < MatchVisual.WoodCount; i++) woodItems.Add(Item(woods, false, i));
            info = UiFactory.Text(area, Loc.T("wardrobe.note"), 26f, Theme.inkMuted, false);
            info.textWrappingMode = TextWrappingModes.Normal;
            info.alignment = TextAlignmentOptions.MidlineLeft;
            UiFactory.Place(info.rectTransform, new Vector2(0f, 0f), new Vector2(880f, 70f), new Vector2(980f, 30f));
            if (owner != null) BuildMatches(area);
            BackButton(Rect, new Vector2(0.5f, 0f), new Vector2(0f, 40f));
            SelectSlot(slotNumbers.Count > 0 ? slotNumbers[0] : 0);
            Panel.FirstSelected = hatItems.Count > 0 ? hatItems[0].GetComponent<Button>() : null;
        }

        // ---------- Спички (у шкафа в лобби) ----------

        private void BuildMatches(RectTransform area)
        {
            var box = UiFactory.Rect(area, "Matches");
            box.anchorMin = box.anchorMax = new Vector2(0f, 0f);
            box.pivot = new Vector2(0f, 0f);
            box.sizeDelta = new Vector2(400f, 190f);
            box.anchoredPosition = new Vector2(0f, 0f);
            var title = UiFactory.LocText(box, "wardrobe.matches", 30f, Theme.accent, true);
            title.alignment = TextAlignmentOptions.MidlineLeft;
            UiFactory.Place(title.rectTransform, new Vector2(0f, 1f), new Vector2(400f, 44f), new Vector2(200f, -22f));
            matchChoice = UiPrefabs.Spawn<TMP_Dropdown>("Dropdown", box);
            var rt = (RectTransform)matchChoice.transform;
            rt.anchorMin = new Vector2(0f, 1f);
            rt.anchorMax = new Vector2(1f, 1f);
            rt.pivot = new Vector2(0.5f, 1f);
            rt.sizeDelta = new Vector2(0f, rt.sizeDelta.y);
            rt.anchoredPosition = new Vector2(0f, -50f);
            matchChoice.onValueChanged.AddListener(i =>
            {
                if (owner == null || i < 0 || i >= matchOptions.Count) return;
                PlayerChoices.Wish(owner.Ragdoll, matchOptions[i]);
            });
            ruleText = UiFactory.Text(box, "", 22f, Theme.inkMuted, false);
            ruleText.textWrappingMode = TextWrappingModes.Normal;
            ruleText.alignment = TextAlignmentOptions.TopLeft;
            UiFactory.Place(ruleText.rectTransform, new Vector2(0f, 0f), new Vector2(400f, 60f), new Vector2(200f, 30f));
            RefreshMatches(true);
        }

        private static int PlayerCount
        {
            get
            {
                var m = PlayerManager.Instance;
                return m != null ? Mathf.Max(1, m.Visible.Count) : 1;
            }
        }

        // Что можно выбрать при таком числе игроков (null — «любые»): 2–3 игрока — пары, 4 — по одной
        private static List<MatchKind[]> Options()
        {
            var list = new List<MatchKind[]> { null };
            int n = PlayerCount;
            if (n >= 4) foreach (var k in Singles) list.Add(new[] { k });
            else if (n >= 2) { list.Add(PairA); list.Add(PairB); }
            return list;
        }

        private string OptionText(MatchKind[] kinds)
        {
            if (PlayerCount < 2) return Loc.T("wardrobe.all_four");
            if (kinds == null) return Loc.T("wardrobe.any");
            string s = kinds.Length == 2 ? Loc.T(kinds[0] == MatchKind.Heavy ? "wardrobe.pair_a" : "wardrobe.pair_b", UiNames.Matches(kinds)) : UiNames.Matches(kinds);
            // Уже у друга — видно сразу
            var m = PlayerManager.Instance;
            if (m != null)
                foreach (var p in m.Visible)
                {
                    if (p == null || p == owner) continue;
                    var b = p.GetComponent<Backpack>();
                    if (b == null) continue;
                    foreach (var k in kinds) if (b.Kinds.Contains(k)) return Loc.T("wardrobe.taken", s, p.Index + 1);
                }
            return s;
        }

        // Список по числу игроков; выбрано — то, что сейчас в рюкзаке
        private void RefreshMatches(bool force)
        {
            if (matchChoice == null || owner == null) return;
            matchOptions = Options();
            var names = new List<string>();
            foreach (var o in matchOptions) names.Add(OptionText(o));
            string key = string.Join("|", names.ToArray());
            int n = PlayerCount;
            ruleText.text = Loc.T("wardrobe.rule." + Mathf.Clamp(n, 1, 4));
            if (!force && key == shownOptions) return;
            shownOptions = key;
            // Тот же список (сменились только «у игрока N») — выбор остаётся; новый список — по рюкзаку
            int value = 0;
            if (!force && matchChoice.options.Count == names.Count) value = matchChoice.value;
            else
            {
                var backpack = owner.GetComponent<Backpack>();
                var have = backpack != null ? backpack.Kinds : new List<MatchKind>();
                for (int i = 1; i < matchOptions.Count; i++)
                    if (matchOptions[i].Length == have.Count && have.Contains(matchOptions[i][0]) && (matchOptions[i].Length < 2 || have.Contains(matchOptions[i][1]))) value = i;
            }
            matchChoice.ClearOptions();
            matchChoice.AddOptions(names);
            matchChoice.SetValueWithoutNotify(Mathf.Clamp(value, 0, names.Count - 1));
            matchChoice.RefreshShownValue();
            matchChoice.interactable = n >= 2;
        }

        private void Update()
        {
            // Игрок ушёл (держал Start / Esc, отключился) — его шкаф закрывается
            if (hadOwner && owner == null) { hadOwner = false; Close(); return; }
            refreshClock -= Time.unscaledDeltaTime;
            if (refreshClock > 0f) return;
            refreshClock = 0.5f;
            RefreshMatches(false);
        }

        // Колонка списка: заголовок и пункты; left — левый край от края содержимого
        private RectTransform Column(RectTransform area, string key, float left)
        {
            var title = UiFactory.LocText(area, key, 34f, Theme.accent, true);
            title.alignment = TextAlignmentOptions.MidlineLeft;
            var tr = title.rectTransform;
            tr.anchorMin = tr.anchorMax = new Vector2(0f, 1f);
            tr.pivot = new Vector2(0f, 0.5f);
            tr.sizeDelta = new Vector2(440f, 50f);
            tr.anchoredPosition = new Vector2(left + 40f, -115f);
            var col = UiFactory.Rect(area, key + " List");
            col.anchorMin = col.anchorMax = new Vector2(0f, 1f);
            col.pivot = new Vector2(0f, 1f);
            col.sizeDelta = new Vector2(440f, 640f);
            col.anchoredPosition = new Vector2(left, -145f);
            var layout = col.gameObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 4f;
            layout.childControlWidth = true;
            layout.childControlHeight = false;
            layout.childForceExpandHeight = false;
            return col;
        }

        // Строка списка: пункт меню (подсветка, указатель), справа — замок у закрытого
        private UiMenuItem Item(RectTransform column, bool isHat, int index)
        {
            var item = UiPrefabs.Spawn<UiMenuItem>("MenuListItem", column);
            ((RectTransform)item.transform).sizeDelta = new Vector2(440f, 66f);
            item.SetColors(Theme.ink, Theme.ink);
            var label = item.GetComponentInChildren<LocText>();
            label.Key = isHat ? "hat." + index : "wood." + index;
            var tmp = label.GetComponent<TMP_Text>();
            tmp.fontSize = 32f;
            tmp.enableAutoSizing = true;
            tmp.fontSizeMin = 18f;
            tmp.fontSizeMax = 32f;
            var lockIcon = UiFactory.Image(item.transform, "ic_lock", false, "Lock");
            UiFactory.Place(lockIcon.rectTransform, new Vector2(1f, 0.5f), new Vector2(40f, 40f), new Vector2(-30f, 6f));
            bool open = isHat ? Unlocks.Hat(index) : Unlocks.Wood(index);
            lockIcon.gameObject.SetActive(!open);
            var b = item.GetComponent<Button>();
            b.onClick.AddListener(() => Wear(isHat, index));
            // Наведение / выбор — примерить
            var trigger = item.gameObject.AddComponent<EventTrigger>();
            var e = new EventTrigger.Entry { eventID = EventTriggerType.Select };
            e.callback.AddListener(_ => TryOn(isHat, index));
            trigger.triggers.Add(e);
            return item;
        }

        private void SelectSlot(int n)
        {
            slot = n;
            var look = SaveSystem.LookOf(slot);
            hat = Unlocks.Hat(look.hat) ? look.hat : 0;
            wood = Unlocks.Wood(look.wood) ? look.wood : 0;
            preview.Show(hat, wood);
            for (int i = 0; i < slotButtons.Count; i++)
            {
                bool on = slotNumbers[i] == slot;
                var img = slotButtons[i].transform.GetChild(0).GetComponent<Image>();
                img.sprite = UiSprites.Get(on ? "btn_primary_normal" : "btn_secondary_normal");
                var t = slotButtons[i].GetComponentInChildren<TMP_Text>();
                t.color = on ? Theme.inkLight : Theme.ink;
                var fx = slotButtons[i].GetComponent<UiButtonFx>();
                if (fx != null) fx.RememberColors();
            }
            Mark();
        }

        // Надетое — отмечено указателем-галочкой цветом
        private void Mark()
        {
            for (int i = 0; i < hatItems.Count; i++) hatItems[i].GetComponentInChildren<TMP_Text>().fontStyle = i == hat ? FontStyles.Underline : FontStyles.Normal;
            for (int i = 0; i < woodItems.Count; i++) woodItems[i].GetComponentInChildren<TMP_Text>().fontStyle = i == wood ? FontStyles.Underline : FontStyles.Normal;
        }

        private void TryOn(bool isHat, int index)
        {
            preview.Show(isHat ? index : hat, isHat ? wood : index);
            bool open = isHat ? Unlocks.Hat(index) : Unlocks.Wood(index);
            if (open) info.text = Loc.T("wardrobe.note");
            else if (isHat && index == MatchVisual.PartyHat) info.text = Loc.T("wardrobe.secret");
            else info.text = Loc.T("wardrobe.locked", UiNames.Need(isHat ? Unlocks.Hats[index] : Unlocks.Woods[index]));
        }

        private void Wear(bool isHat, int index)
        {
            bool open = isHat ? Unlocks.Hat(index) : Unlocks.Wood(index);
            if (!open) { UiTheme.Play(Theme.backSound, Theme.backVolume); return; }
            if (isHat) hat = index; else wood = index;
            preview.Show(hat, wood);
            SaveSystem.RememberLook(slot, hat, wood);
            // Игрок уже в лобби — и на его спичке
            var m = PlayerManager.Instance;
            if (owner != null) PlayerChoices.Look(owner.Ragdoll, hat, wood);
            else if (m != null)
                foreach (var p in m.Visible)
                    if (p != null && (Network ? p.NetworkOwner == Online.LocalClientId : p.Index == slot)) PlayerChoices.Look(p.Ragdoll, hat, wood);
            Mark();
        }
    }
}
