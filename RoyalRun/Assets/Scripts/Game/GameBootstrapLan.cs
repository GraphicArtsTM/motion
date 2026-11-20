using System.Collections.Generic;
using RoyalRun.Net;
using UnityEngine;
using UnityEngine.UI;

// The Wi-Fi race screens of GameBootstrap (a second file of the same class):
//   "WI-FI RACE" menu: create a room or join one found on the network;
//   the room: the runners, their heroes, the mode; the host presses START;
//   the race: every device runs its own copy of the same road (see LanRace and PlayerWorld ghosts);
//   the results: the places of everybody, updated live until the last runner finishes.
public partial class GameBootstrap
{
    const string HeroKey = "royalrun_hero";
    const string NameKey = "royalrun_name";

    LanRace lan;
    int lanSeed;
    GameObject netMenuUi, netLobbyUi;
    Text netMenuStatus, netLobbyInfo, netLobbyPlayers, netLobbyHint;
    MenuButton netCreate, netRescan, netBack;
    MenuButton[] netRoomButtons;
    MenuButton[] netMenuActive = new MenuButton[0];
    int netMenuSelected;
    MenuButton netHero, netMode, netStart, netLeave;
    MenuButton[] netLobbyActive = new MenuButton[0];
    int netLobbySelected;
    string netError;
    float lanResultsRefresh;

    // ---- the player's name and favourite hero are remembered between launches ----

    string LocalName()
    {
        string n = PlayerPrefs.GetString(NameKey, "");
        if (string.IsNullOrEmpty(n))
        {
            n = Loc.T("player.single") + " " + Random.Range(10, 100);
            PlayerPrefs.SetString(NameKey, n);
        }
        return n;
    }

    static int LocalHero()
    {
        return Mathf.Clamp(PlayerPrefs.GetInt(HeroKey, 0), 0, CharacterCatalog.Count - 1);
    }

    static void SaveHero(int ch)
    {
        PlayerPrefs.SetInt(HeroKey, ch);
        PlayerPrefs.Save();
    }

    void EnsureLan()
    {
        if (lan != null) return;
        lan = gameObject.AddComponent<LanRace>();
        lan.Changed += OnLanChanged;
        lan.Started += OnLanStarted;
        lan.Ended += OnLanEnded;
        lan.BackToLobby += OnLanBackToLobby;
        lan.Failed += OnLanFailed;
    }

    // ============================================================
    //  Building the screens
    // ============================================================

    void BuildNetUi()
    {
        bool portrait = GameUI.Portrait;
        Vector2 a, b;

        // ---- the Wi-Fi race menu ----
        RectTransform m = GameUI.CreateRect("Net Menu UI", canvas.transform, Vector2.zero, Vector2.one);
        netMenuUi = m.gameObject;
        GameUI.Pick(new Vector4(0.1f, 0.86f, 0.9f, 0.97f), new Vector4(0.03f, 0.87f, 0.97f, 0.96f), out a, out b);
        GameUI.Bind(GameUI.CreateText("Title", m, a, b, "", 84, GameUI.Gold, TextAnchor.MiddleCenter), "lan.title");
        GameUI.Pick(new Vector4(0.15f, 0.75f, 0.85f, 0.86f), new Vector4(0.05f, 0.77f, 0.95f, 0.87f), out a, out b);
        GameUI.Bind(GameUI.CreateText("Info", m, a, b, "", 30, new Color(1f, 1f, 1f, 0.85f), TextAnchor.MiddleCenter, false), "lan.info");
        GameUI.Pick(new Vector4(0.15f, 0.69f, 0.85f, 0.75f), new Vector4(0.05f, 0.71f, 0.95f, 0.77f), out a, out b);
        netMenuStatus = GameUI.CreateText("Status", m, a, b, "", 32, GameUI.Cyan, TextAnchor.MiddleCenter);

        MenuButton[] all = new MenuButton[6];
        for (int i = 0; i < all.Length; i++)
        {
            if (portrait) { float top = 0.67f - i * 0.085f; a = V(0.1f, top - 0.07f); b = V(0.9f, top); }
            else { float top = 0.66f - i * 0.1f; a = V(0.3f, top - 0.085f); b = V(0.7f, top); }
            all[i] = GameUI.CreateButton("Button " + (i + 1), m, a, b, "", 36, null);
        }
        netCreate = all[0];
        netCreate.onClick = CreateRoom;
        netCreate.normal = new Color(0.15f, 0.55f, 0.25f, 0.95f);
        netCreate.Refresh();
        GameUI.Bind(netCreate.label, "lan.create");
        netRoomButtons = new[] { all[1], all[2], all[3] };
        for (int i = 0; i < netRoomButtons.Length; i++)
        {
            int index = i;
            netRoomButtons[i].onClick = () => JoinRoom(index);
        }
        netRescan = all[4];
        netRescan.onClick = () => { netError = null; lan.StartScan(); RefreshNetMenu(); };
        GameUI.Bind(netRescan.label, "lan.rescan");
        netBack = all[5];
        netBack.onClick = LeaveLan;
        GameUI.Bind(netBack.label, "select.back");
        netMenuUi.SetActive(false);

        // ---- the room ----
        RectTransform l = GameUI.CreateRect("Net Lobby UI", canvas.transform, Vector2.zero, Vector2.one);
        netLobbyUi = l.gameObject;
        GameUI.Pick(new Vector4(0.04f, 0.89f, 0.6f, 0.98f), new Vector4(0.03f, 0.89f, 0.97f, 0.97f), out a, out b);
        GameUI.Bind(GameUI.CreateText("Title", l, a, b, "", 74, GameUI.Gold, portrait ? TextAnchor.MiddleCenter : TextAnchor.MiddleLeft), "lan.title");
        GameUI.Pick(new Vector4(0.04f, 0.83f, 0.6f, 0.89f), new Vector4(0.03f, 0.845f, 0.97f, 0.89f), out a, out b);
        netLobbyInfo = GameUI.CreateText("Info", l, a, b, "", 30, GameUI.Cyan, portrait ? TextAnchor.MiddleCenter : TextAnchor.MiddleLeft);
        GameUI.Pick(new Vector4(0.04f, 0.45f, 0.58f, 0.82f), new Vector4(0.06f, 0.62f, 0.94f, 0.84f), out a, out b);
        Image panel = GameUI.CreatePanel("Players Panel", l, a, b, GameUI.Panel);
        netLobbyPlayers = GameUI.CreateText("Players", panel.transform, new Vector2(0.05f, 0.05f), new Vector2(0.95f, 0.95f), "", 40, Color.white, TextAnchor.UpperLeft);
        GameUI.Pick(new Vector4(0.04f, 0.37f, 0.58f, 0.44f), new Vector4(0.05f, 0.28f, 0.95f, 0.34f), out a, out b);
        netLobbyHint = GameUI.CreateText("Hint", l, a, b, "", 30, new Color(1f, 1f, 1f, 0.85f), TextAnchor.MiddleCenter, false);

        MenuButton[] lb = new MenuButton[4];
        for (int i = 0; i < lb.Length; i++)
        {
            if (portrait)
            {
                if (i < 2) { float top = 0.27f - i * 0.07f; a = V(0.1f, top - 0.06f); b = V(0.9f, top); }
                else if (i == 2) { a = V(0.52f, 0.04f); b = V(0.9f, 0.12f); }
                else { a = V(0.1f, 0.04f); b = V(0.48f, 0.12f); }
            }
            else { float top = 0.82f - i * 0.11f; a = V(0.64f, top - 0.09f); b = V(0.96f, top); }
            lb[i] = GameUI.CreateButton("Button " + (i + 1), l, a, b, "", 34, null);
        }
        netHero = lb[0];
        netHero.onClick = NextLanHero;
        GameUI.Bind(netHero.label, () => Loc.F("lan.hero", CharacterCatalog.All[LocalHero()].Name));
        netMode = lb[1];
        netMode.onClick = () => { if (lan != null && lan.State == LanRace.Role.Host) { ToggleMode(); lan.SetMode(rules); } };
        GameUI.Bind(netMode.label, () => Loc.F("mode.label", Loc.T((lan != null && lan.State == LanRace.Role.Client ? lan.Mode : rules) == GameRules.Endless ? "mode.endless" : "mode.classic")));
        netStart = lb[2];
        netStart.onClick = () => { if (lan != null) lan.HostStart(); };
        netStart.normal = new Color(0.15f, 0.55f, 0.25f, 0.95f);
        netStart.Refresh();
        GameUI.Bind(netStart.label, "lan.start");
        netLeave = lb[3];
        netLeave.onClick = LeaveLan;
        GameUI.Bind(netLeave.label, "lan.leave");
        netLobbyUi.SetActive(false);
    }

    // ============================================================
    //  The Wi-Fi race menu: create / find a room
    // ============================================================

    void OpenNetMenu()
    {
        EnsureLan();
        lan.Leave();
        ClearWorlds();
        HideAllScreens();
        mode = Mode.Lan;
        hub.Enabled = false;
        hub.ResetPlayers();
        netMenuUi.SetActive(true);
        stage.gameObject.SetActive(true);
        phase = Phase.NetMenu;
        SetFooter(null);
        lan.StartScan();
        RefreshNetMenu();
    }

    void UpdateNetMenu()
    {
        LayoutStage();

        // joined: the host has answered
        if (lan.State == LanRace.Role.Client && lan.MyId >= 0) { EnterNetLobby(); return; }

        RefreshNetMenuStatus();
        GameUI.UpdateButtons(netMenuActive, ref netMenuSelected, true);
    }

    void RefreshNetMenu()
    {
        if (netRoomButtons == null) return;
        List<MenuButton> active = new List<MenuButton> { netCreate };
        for (int i = 0; i < netRoomButtons.Length; i++)
        {
            bool has = lan != null && i < lan.Rooms.Count;
            netRoomButtons[i].rect.gameObject.SetActive(has);
            if (!has) continue;
            FoundRoom r = lan.Rooms[i];
            string players = LanRace.JsonField(r.Json, "players") + "/" + LanRace.JsonField(r.Json, "max");
            bool racing = LanRace.JsonField(r.Json, "racing") == "true";
            netRoomButtons[i].label.text = Loc.F("lan.join", LanRace.JsonField(r.Json, "name"), players) + (racing ? "  ·  " + Loc.T("lan.running") : "");
            active.Add(netRoomButtons[i]);
        }
        active.Add(netRescan);
        active.Add(netBack);
        netMenuActive = active.ToArray();
        if (netMenuSelected >= netMenuActive.Length) netMenuSelected = 0;
        RefreshNetMenuStatus();
    }

    void RefreshNetMenuStatus()
    {
        if (netMenuStatus == null || lan == null) return;
        if (!string.IsNullOrEmpty(netError)) netMenuStatus.text = "<color=#ff8a80>" + Loc.T(netError) + "</color>";
        else if (lan.Connecting) netMenuStatus.text = Loc.T("lan.connecting");
        else if (lan.Scanning) netMenuStatus.text = Loc.T("lan.searching") + new string('.', 1 + (int)(Time.time * 2f) % 3);
        else if (lan.Rooms.Count > 0) netMenuStatus.text = Loc.F("lan.found", lan.Rooms.Count);
        else netMenuStatus.text = Loc.T("lan.none");
    }

    void CreateRoom()
    {
        netError = null;
        if (lan.Host(LocalName(), LocalHero(), rules)) EnterNetLobby();
        else RefreshNetMenu();
    }

    void JoinRoom(int index)
    {
        if (index >= lan.Rooms.Count) return;
        netError = null;
        lan.Join(lan.Rooms[index].Ip, LocalName(), LocalHero());
        RefreshNetMenuStatus();
    }

    void LeaveLan()
    {
        if (lan != null) lan.Leave();
        EnterMenu();
    }

    // ============================================================
    //  The room
    // ============================================================

    void EnterNetLobby()
    {
        ClearWorlds();
        HideAllScreens();
        netLobbyUi.SetActive(true);
        stage.gameObject.SetActive(true);
        phase = Phase.NetLobby;
        mode = Mode.Lan;
        SetFooter(null);
        RefreshNetLobby();
    }

    void UpdateNetLobby()
    {
        LayoutStage();
        GameUI.UpdateButtons(netLobbyActive, ref netLobbySelected, true);
    }

    void RefreshNetLobby()
    {
        if (lan == null || netLobbyUi == null) return;
        bool host = lan.State == LanRace.Role.Host;
        netLobbyInfo.text = host ? Loc.F("lan.hostInfo", lan.HostIp) : Loc.F("lan.clientInfo", lan.HostName ?? lan.HostIp);

        System.Text.StringBuilder sb = new System.Text.StringBuilder();
        foreach (NetPlayer p in lan.Players)
        {
            Color c = PhoneHub.SlotColors[Mathf.Clamp(p.color, 0, PhoneHub.SlotColors.Length - 1)];
            sb.Append("<color=#").Append(ColorUtility.ToHtmlStringRGB(c)).Append(">●</color>  ")
              .Append(p.id == lan.MyId ? "<b>" + p.name + "</b>" : p.name)
              .Append("  <size=28><color=#bbbbbb>").Append(CharacterCatalog.All[Mathf.Clamp(p.ch, 0, CharacterCatalog.Count - 1)].Name)
              .Append(p.id == 0 ? "  ·  " + Loc.T("lan.hostTag") : "").Append("</color></size>\n");
        }
        for (int i = lan.Players.Count; i < LanRace.MaxPlayers; i++)
            sb.Append("<color=#777777>○  ").Append(Loc.T("lobby.free")).Append("</color>\n");
        netLobbyPlayers.text = sb.ToString();
        netLobbyHint.text = Loc.T(host ? "lan.hintHost" : "lan.hintClient");

        netStart.rect.gameObject.SetActive(host);
        netMode.normal = host ? new Color(0.20f, 0.14f, 0.36f, 0.92f) : new Color(0.2f, 0.2f, 0.25f, 0.6f);
        netMode.Refresh();
        GameUI.RefreshBindings();

        List<MenuButton> active = new List<MenuButton> { netHero };
        if (host) { active.Add(netMode); active.Add(netStart); }
        active.Add(netLeave);
        netLobbyActive = active.ToArray();
        if (netLobbySelected >= netLobbyActive.Length) netLobbySelected = 0;
    }

    void NextLanHero()
    {
        int ch = (LocalHero() + 1) % CharacterCatalog.Count;
        SaveHero(ch);
        if (lan != null) lan.SetCharacter(ch);
        GameUI.RefreshBindings();
        RefreshNetLobby();
    }

    // ============================================================
    //  Network events
    // ============================================================

    void OnLanChanged()
    {
        if (phase == Phase.NetLobby) RefreshNetLobby();
        else if (phase == Phase.NetMenu) RefreshNetMenu();
    }

    void OnLanStarted(int seed, GameRules raceRules)
    {
        lanSeed = seed;
        rules = raceRules;
        ClearWorlds();
        HideAllScreens();
        stage.gameObject.SetActive(true);
        phase = Phase.Countdown;
        countdownLeft = countdownSeconds;
        lastCountShown = -1;
        countText.gameObject.SetActive(true);
    }

    void OnLanEnded()
    {
        if (phase == Phase.Results) ShowLanResults();
    }

    void OnLanBackToLobby()
    {
        EnterNetLobby();
    }

    void OnLanFailed(string key)
    {
        bool wasPlaying = phase == Phase.Playing || phase == Phase.Countdown || phase == Phase.Results;
        if (phase == Phase.Menu) return;
        netError = key;
        ClearWorlds();
        HideAllScreens();
        netMenuUi.SetActive(true);
        stage.gameObject.SetActive(true);
        phase = Phase.NetMenu;
        mode = Mode.Lan;
        if (!wasPlaying) lan.StartScan();
        RefreshNetMenu();
    }

    // ============================================================
    //  The race
    // ============================================================

    void UpdateLanCountdown()
    {
        LayoutStage();
        countdownLeft -= Time.deltaTime;
        int n = Mathf.CeilToInt(countdownLeft);
        if (n != lastCountShown && n > 0)
        {
            lastCountShown = n;
            countText.text = n.ToString();
            Sfx.Play(SynthAudio.Beep, 0.7f);
        }
        float frac = countdownLeft - Mathf.Floor(countdownLeft);
        countText.transform.localScale = Vector3.one * (1f + 0.5f * frac);
        if (countdownLeft <= 0f) StartLanGame();
    }

    void StartLanGame()
    {
        NetPlayer me = lan.Me;
        if (me == null) { LeaveLan(); return; }
        HideAllScreens();
        stage.gameObject.SetActive(false);
        SetFooter(null);

        PhonePlayer local = new PhonePlayer
        {
            slot = me.color,
            name = me.name,
            character = me.ch,
            isKeyboard = true,
            keyboardScheme = GameInput.SchemeSolo,
            connected = true,
            ready = true,
        };
        worlds.Add(PlayerWorld.Create(0, 1, local, assets, null, rules, lanSeed, lan));
        finishDelay = 0f;
        phase = Phase.Playing;
    }

    void UpdateLanPlaying()
    {
        PlayerWorld w = worlds.Count > 0 ? worlds[0] : null;
        if (w == null) return;
        lan.ReportStatus(w, w.Avatar);
        if (!w.Finished) { finishDelay = 0f; return; }
        finishDelay += Time.deltaTime;
        if (finishDelay >= 2.6f) ShowLanResults();
    }

    // ============================================================
    //  Results (live until everybody has finished)
    // ============================================================

    void ShowLanResults()
    {
        bool first = phase != Phase.Results;
        phase = Phase.Results;
        if (first)
        {
            resultsTimer = 0f;
            resultsSelected = 0;
            ShowCleanBackground();
            resultsUi.SetActive(true);
            SetFooter(null);
        }

        List<NetPlayer> list = new List<NetPlayer>(lan.Players);
        list.Sort((a, b) => b.s.CompareTo(a.s));
        BuildLanRows(list);

        resultsTitle.text = Loc.T(lan.RaceEnded ? "lan.raceOver" : "results.runOver");
        resultsHint.text = lan.RaceEnded ? "" : Loc.T("lan.waitOthers");
        bool host = lan.State == LanRace.Role.Host;
        resultsButtons[0].label.text = Loc.T(host && !lan.RaceEnded ? "lan.waitEnd" : "lan.again");
        resultsButtons[1].label.text = Loc.T("lan.leave");
        resultsButtons[2].label.text = Loc.T("btn.mainMenu");
    }

    void UpdateLanResults()
    {
        lanResultsRefresh -= Time.deltaTime;
        if (lanResultsRefresh <= 0f && !lan.RaceEnded)
        {
            lanResultsRefresh = 0.5f;
            ShowLanResults();
        }
        GameUI.UpdateButtons(resultsButtons, ref resultsSelected, true);
    }

    void BuildLanRows(List<NetPlayer> ranking)
    {
        foreach (Transform child in resultsRows) Destroy(child.gameObject);

        Color[] medal = { new Color(1f, 0.84f, 0.2f), new Color(0.8f, 0.82f, 0.88f), new Color(0.85f, 0.55f, 0.3f), new Color(0.6f, 0.6f, 0.65f) };
        float h = 1f / Mathf.Max(3, ranking.Count);
        for (int i = 0; i < ranking.Count; i++)
        {
            NetPlayer p = ranking[i];
            float yMax = 1f - i * h;
            float yMin = yMax - h * 0.88f;
            Color slotColor = PhoneHub.SlotColors[Mathf.Clamp(p.color, 0, PhoneHub.SlotColors.Length - 1)];

            Image row = GameUI.CreatePanel("Row " + (i + 1), resultsRows, new Vector2(0f, yMin), new Vector2(1f, yMax),
                                           new Color(slotColor.r * 0.45f, slotColor.g * 0.45f, slotColor.b * 0.45f, 0.9f));
            GameUI.CreateText("Rank", row.transform, new Vector2(0.02f, 0f), new Vector2(0.15f, 1f),
                              (i + 1).ToString(), 58, medal[Mathf.Min(i, 3)], TextAnchor.MiddleCenter);

            string state = p.gone ? Loc.T("lan.left") : !p.over ? "<color=#8bff8b>" + Loc.T("lan.running") + "</color>" : CauseName((CrashCause)p.cause);
            GameUI.CreateText("Name", row.transform, new Vector2(0.16f, 0f), new Vector2(0.68f, 1f),
                              (p.id == lan.MyId ? "<b>" + p.name + "</b>" : p.name) + "\n<size=24>"
                              + CharacterCatalog.All[Mathf.Clamp(p.ch, 0, CharacterCatalog.Count - 1)].Name + "  ·  "
                              + Loc.F("hud.distance", Mathf.FloorToInt(p.d)) + "  ·  " + state + "</size>",
                              38, Color.white, TextAnchor.MiddleLeft);
            GameUI.CreateText("Score", row.transform, new Vector2(0.66f, 0f), new Vector2(0.97f, 1f),
                              p.s.ToString(), 50, GameUI.Gold, TextAnchor.MiddleRight);
        }
    }

    static string CauseName(CrashCause c)
    {
        switch (c)
        {
            case CrashCause.MissedTurn: return Loc.T("end.missedTurn");
            case CrashCause.Caught: return Loc.T("end.caught");
            case CrashCause.TimeUp: return Loc.T("end.timeUp");
            default: return Loc.T("end.crashed");
        }
    }

    // "ONCE MORE": the host takes everybody back to the room (after the last runner finished);
    // a guest goes to the room and waits for the host.
    void LanAgain()
    {
        if (lan.State == LanRace.Role.Host)
        {
            if (lan.RaceEnded) lan.HostBackToLobby();
            return;
        }
        EnterNetLobby();
    }
}
