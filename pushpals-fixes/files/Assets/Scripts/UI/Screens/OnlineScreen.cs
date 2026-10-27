using System.Collections.Generic;
using PushPals.Network;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Онлайн (Этап 17.4, банки-телефон на столе; в игре — из паузы и «Настроек игры»).
    /// Не в игре: создать игру (лобби Steam), найти открытые игры, войти по коду, игра без Steam (локальный хост /
    /// подключиться по адресу). В игре: что происходит и что делать дальше, код лобби (копировать), пригласить
    /// друзей Steam (из списка или окном Steam), кто в игре, выйти из сетевой игры. Состояние обновляется само.
    /// Из главного меню: игра создана — нижняя кнопка «В коробок» (там ждём друзей; Esc — то же самое),
    /// подключились к другу — коробок хоста загрузится сам. Из игры нижняя кнопка — «Назад».
    /// Работает через NetSession (тот же код, что временная панель F2).
    /// </summary>
    public class OnlineScreen : UiScreen
    {
        private static bool fromMenuNext;

        private NetSession net;
        private bool fromMenu;
        private TextMeshProUGUI status, details, hint, codeText;
        private RectTransform lobbyList, friendsList, membersList;
        private GameObject offlineColumn, sessionColumn;
        private TMP_InputField codeField, addressField;
        private Button copyButton, inviteButton, bottomButton;
        private readonly List<Button> steamButtons = new List<Button>(); // без Steam не работают — и не нажимаются
        private TMP_Dropdown accessChoice;
        private LocText bottomLabel;
        private float refreshClock;
        private string shownLobbies = "", shownFriends = "", shownMembers = "";
        private bool lastInSession;

        /// <summary>Открыть: fromMainMenu — со стола главного меню (созданная игра продолжается в коробке).</summary>
        public static OnlineScreen Open(bool fromMainMenu)
        {
            fromMenuNext = fromMainMenu;
            return Create<OnlineScreen>("Online Screen", true, true, UiPanel.Motion.Drawer);
        }

        protected override void Build()
        {
            fromMenu = fromMenuNext;
            net = NetSession.Instance;
            if (net != null) net.TryInitSteam();
            var area = Paper(new Vector2(1500f, 930f), "online.title");
            status = Ink(area, "", 30f);
            UiFactory.Place(status.rectTransform, new Vector2(0.5f, 1f), new Vector2(1360f, 44f), new Vector2(0f, -10f));
            details = Ink(area, "", 24f);
            details.color = Theme.inkMuted;
            UiFactory.Place(details.rectTransform, new Vector2(0.5f, 1f), new Vector2(1360f, 34f), new Vector2(0f, -50f));

            // Не в игре: создать / найти / войти
            var offline = UiFactory.Rect(area, "Offline");
            UiRoot.Stretch(offline);
            offline.offsetMax = new Vector2(0f, -90f);
            offlineColumn = offline.gameObject;
            var left = Half(offline, true);
            var f = new UiForm(left);
            steamButtons.Add(f.Button("online.host", true, () => { if (net != null) net.HostSteam(); }));
            steamButtons.Add(f.Button("online.find", false, () => { if (net != null) net.FindLobbies(); }));
            var codeSlot = f.Row(null);
            codeField = Field(codeSlot, "", -270f, "online.code");
            steamButtons.Add(SmallButton(codeSlot, "online.join_code", () => { if (net != null && !net.JoinByCode(codeField.text)) UiTheme.Play(Theme.backSound, Theme.backVolume); }));
            f.Header("online.local");
            f.Button("online.local_host", false, () => { if (net != null) net.StartLocalHost(); });
            var addrSlot = f.Row(null);
            addressField = Field(addrSlot, "127.0.0.1", -270f, null);
            SmallButton(addrSlot, "online.local_join", () => { if (net != null) net.StartLocalClient(addressField.text.Trim()); });
            var right = Half(offline, false);
            var found = new UiForm(right);
            Tall(found.Note("online.found_hint"), 70f);
            lobbyList = found.Content;

            // В игре: что дальше, код, пригласить, выйти, кто в игре
            var session = UiFactory.Rect(area, "Session");
            UiRoot.Stretch(session);
            session.offsetMax = new Vector2(0f, -90f);
            sessionColumn = session.gameObject;
            var sl = new UiForm(Half(session, true));
            hint = Tall(sl.Note("online.host_hint"), 70f);
            var codeRow = sl.Row("online.code");
            codeText = Ink(codeRow, "", 30f, true);
            codeText.rectTransform.anchorMin = Vector2.zero;
            codeText.rectTransform.anchorMax = Vector2.one;
            codeText.rectTransform.offsetMin = Vector2.zero;
            codeText.rectTransform.offsetMax = new Vector2(-260f, 0f); // справа — «Копировать»
            codeText.enableAutoSizing = true;
            codeText.fontSizeMin = 18f;
            codeText.fontSizeMax = 30f;
            copyButton = SmallButton(codeRow, "online.copy", () =>
            {
                GUIUtility.systemCopyBuffer = net != null ? net.LobbyCodeText : "";
                details.text = Loc.T("online.copied");
            });
            // Кто может войти — хосту прямо здесь: выбор хранится между запусками, и «никто» из прошлой игры
            // молча не пускал друзей (а на этом экране его было не видно)
            var accessNames = new List<string>();
            for (int i = 0; i < GameRules.PrivacyCount; i++) accessNames.Add(GameRules.PrivacyName((GameRules.Privacy)i));
            accessChoice = sl.Choice("setup.access", accessNames, (int)GameRules.Access, i =>
            {
                GameRules.Access = (GameRules.Privacy)i;
                GameRules.NotifyChanged();
            });
            inviteButton = sl.Button("online.invite_overlay", false, () => { if (net != null) net.OpenInviteOverlay(); });
            sl.Button("online.leave", false, () => { if (net != null) net.Leave(); });
            sl.Header("online.members");
            membersList = sl.Content;
            var sr = new UiForm(Half(session, false));
            sr.Header("online.friends");
            sr.Button("online.refresh", false, () => { if (net != null) net.UpdateFriends(); shownFriends = "?"; });
            friendsList = sr.Content;

            // Внизу: «Назад», а со стола с идущей игрой — «В коробок» (меню само уводит туда после закрытия)
            bottomButton = BackButton(Rect, new Vector2(0.5f, 0f), new Vector2(0f, 40f));
            bottomLabel = bottomButton.GetComponentInChildren<LocText>();
            Refresh(true);
        }

        // Пояснение повыше (в одну строку не влезает)
        private static TextMeshProUGUI Tall(TextMeshProUGUI note, float height)
        {
            var fit = note.transform.parent.GetComponent<LayoutElement>();
            if (fit != null) fit.preferredHeight = height;
            return note;
        }

        private static RectTransform Half(RectTransform parent, bool left)
        {
            var r = UiFactory.Rect(parent, left ? "Left" : "Right");
            r.anchorMin = new Vector2(left ? 0f : 0.52f, 0f);
            r.anchorMax = new Vector2(left ? 0.48f : 1f, 1f);
            r.offsetMin = r.offsetMax = Vector2.zero;
            return r;
        }

        // Поле ввода на бумаге (код лобби, адрес)
        private TMP_InputField Field(RectTransform slot, string text, float right, string placeholderKey)
        {
            var res = new TMP_DefaultControls.Resources { inputField = UiSprites.Get("input_field") };
            var go = TMP_DefaultControls.CreateInputField(res);
            go.transform.SetParent(slot, false);
            var rt = (RectTransform)go.transform;
            rt.anchorMin = new Vector2(0f, 0.5f);
            rt.anchorMax = new Vector2(1f, 0.5f);
            rt.sizeDelta = new Vector2(right, 62f);
            rt.anchoredPosition = new Vector2(right * 0.5f, 0f);
            var img = go.GetComponent<Image>();
            img.type = Image.Type.Sliced;
            var field = go.GetComponent<TMP_InputField>();
            foreach (var t in go.GetComponentsInChildren<TMP_Text>(true))
            {
                if (Theme.body != null) t.font = Theme.body;
                t.fontSize = 28f;
                t.color = Theme.ink;
            }
            field.text = text;
            var ph = field.placeholder as TMP_Text;
            if (ph != null) { ph.text = placeholderKey != null ? Loc.T(placeholderKey) : ""; ph.color = Theme.inkMuted; ph.fontStyle = FontStyles.Italic; }
            if (field.textViewport != null) { field.textViewport.offsetMin = new Vector2(20f, 6f); field.textViewport.offsetMax = new Vector2(-20f, -6f); }
            return field;
        }

        private Button SmallButton(RectTransform slot, string key, System.Action onClick)
        {
            var b = UiPrefabs.Spawn<Button>("SecondaryButton", slot);
            var rt = (RectTransform)b.transform;
            rt.anchorMin = rt.anchorMax = new Vector2(1f, 0.5f);
            rt.pivot = new Vector2(1f, 0.5f);
            rt.sizeDelta = new Vector2(250f, 66f);
            rt.anchoredPosition = Vector2.zero;
            b.GetComponentInChildren<LocText>().Key = key;
            b.onClick.AddListener(() => onClick());
            return b;
        }

        private void Update()
        {
            refreshClock -= Time.unscaledDeltaTime;
            if (refreshClock > 0f) return;
            refreshClock = 0.5f;
            Refresh(false);
        }

        private void Refresh(bool force)
        {
            if (net == null)
            {
                status.text = Loc.T("online.offline");
                offlineColumn.SetActive(true);
                sessionColumn.SetActive(false);
                return;
            }
            bool inSession = net.IsInSession;
            if (inSession != lastInSession || force)
            {
                lastInSession = inSession;
                offlineColumn.SetActive(!inSession);
                sessionColumn.SetActive(inSession);
                // Что дальше: хост ждёт друзей (со стола — в коробке), клиент играет у хоста
                hint.text = Loc.T(!net.IsHost ? "online.client_hint" : fromMenu ? "online.hosting_hint" : "online.host_hint");
                bool toBox = fromMenu && inSession;
                bottomLabel.Key = toBox ? "online.to_box" : "ui.back";
                Panel.FirstSelected = toBox ? bottomButton : null;
                shownMembers = shownFriends = shownLobbies = "?"; // списки — заново
                Panel.SelectFirst();
            }
            status.text = net.Status;
            var info = new List<string>();
            info.Add(net.SteamReady ? Loc.T("online.steam", net.SteamName) : Loc.T("online.no_steam"));
            if (inSession) info.Add(Loc.T("online.players", net.PlayersInSession));
            if (inSession && net.PingMs.Length > 0) info.Add(Loc.T("online.ping", net.PingMs));
            if (details.text != Loc.T("online.copied") || refreshClock < -2f) details.text = string.Join("   ·   ", info.ToArray());
            if (!inSession)
            {
                // Steam не запущен — создать/найти/войти по коду нельзя (подсказка «online.no_steam» — в строке выше);
                // игра без Steam (локальная сеть) работает
                foreach (var b in steamButtons) if (b != null) b.interactable = net.SteamReady;
                RefreshLobbies();
                return;
            }
            // Код: Steam-лобби — число для друзей; локальная игра — порт; клиент без Steam — кода нет
            string code = Online.LobbyCode != null ? Online.LobbyCode() : "";
            codeText.text = code.Length > 0 ? code : "—";
            // Кто может войти — решает хост; у клиента строки нет
            var accessRow = accessChoice.transform.parent != null ? accessChoice.transform.parent.parent : null;
            if (accessRow != null && accessRow.gameObject.activeSelf != net.IsHost) accessRow.gameObject.SetActive(net.IsHost);
            if (accessChoice.value != (int)GameRules.Access) accessChoice.SetValueWithoutNotify((int)GameRules.Access);
            bool steamLobby = net.LobbyCodeText.Length > 0;
            copyButton.interactable = steamLobby;
            inviteButton.interactable = steamLobby && net.SteamReady;
            RefreshMembers();
            RefreshFriends();
        }

        // Найденные игры — кнопки «Войти»
        private void RefreshLobbies()
        {
            var lobbies = net.FoundLobbies;
            string key = "";
            foreach (var l in lobbies) key += l.Id.Value + ":" + l.MemberCount + ";";
            if (key == shownLobbies) return;
            shownLobbies = key;
            for (int i = lobbyList.childCount - 1; i >= 0; i--)
                if (lobbyList.GetChild(i).name.StartsWith("Friend")) Destroy(lobbyList.GetChild(i).gameObject); // подсказку сверху оставить
            foreach (var l in lobbies)
            {
                var lobby = l;
                var b = ListButton(lobbyList, Loc.T("online.join", lobby.GetData("name"), lobby.MemberCount, lobby.MaxMembers));
                b.onClick.AddListener(() => net.JoinSteam(lobby.Id));
            }
        }

        private void RefreshMembers()
        {
            var names = net.LobbyMembers();
            string key = string.Join("|", names.ToArray());
            if (key == shownMembers) return;
            shownMembers = key;
            // Участники — строки после заголовка «В лобби» (заголовок и кнопки выше — не трогаем)
            for (int i = membersList.childCount - 1; i >= 0; i--)
                if (membersList.GetChild(i).name.StartsWith("Member")) Destroy(membersList.GetChild(i).gameObject);
            foreach (var n in names)
            {
                var row = UiFactory.Rect(membersList, "Member");
                row.gameObject.AddComponent<LayoutElement>().preferredHeight = 44f;
                var t = Ink(row, "• " + n, 28f);
                UiRoot.Stretch(t.rectTransform);
            }
        }

        private void RefreshFriends()
        {
            var friends = net.OnlineFriends;
            string key = "";
            foreach (var f in friends) key += f.Id.Value + ";";
            if (key == shownFriends) return;
            shownFriends = key;
            for (int i = friendsList.childCount - 1; i >= 0; i--)
                if (friendsList.GetChild(i).name.StartsWith("Friend")) Destroy(friendsList.GetChild(i).gameObject);
            if (friends.Count == 0)
            {
                var row = UiFactory.Rect(friendsList, "Friend None");
                row.gameObject.AddComponent<LayoutElement>().preferredHeight = 44f;
                var t = Ink(row, Loc.T("online.no_friends"), 26f);
                t.color = Theme.inkMuted;
                UiRoot.Stretch(t.rectTransform);
                return;
            }
            foreach (var f in friends)
            {
                var friend = f;
                var b = ListButton(friendsList, Loc.T("online.invite") + ": " + friend.Name);
                b.name = "Friend " + friend.Name;
                b.onClick.AddListener(() => net.InviteFriend(friend.Id));
            }
        }

        // Кнопка во всю ширину списка с готовым текстом
        private Button ListButton(RectTransform list, string text)
        {
            var holder = UiFactory.Rect(list, "Friend Item");
            holder.gameObject.AddComponent<LayoutElement>().preferredHeight = 72f;
            var b = UiPrefabs.Spawn<Button>("SecondaryButton", holder);
            var rt = (RectTransform)b.transform;
            UiRoot.Stretch(rt);
            var loc = b.GetComponentInChildren<LocText>();
            var tmp = loc.GetComponent<TMP_Text>();
            Destroy(loc); // готовый текст, не ключ
            tmp.text = text;
            tmp.fontStyle = FontStyles.Normal;
            return b;
        }
    }
}
