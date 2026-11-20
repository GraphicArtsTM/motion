using System;
using System.Collections.Generic;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using RoyalRun.Net;
using UnityEngine;

// One player (phone or keyboard).
public class PhonePlayer
{
    public int slot;                 // 0, 1, 2 - the player's permanent slot
    public int clientId = -1;        // WebSocket connection number
    public string cid;               // permanent phone id (for reconnecting)
    public string name;
    public int character = -1;       // index in CharacterCatalog, -1 = not chosen
    public bool ready;
    public bool connected;
    public bool isKeyboard;
    public Vector2 move;             // joystick position, length at most 1
    public bool jumpQueued;          // a tap on the phone (= jump), taken by PlayerAvatar
    // swipes from the phone: 'L' left, 'R' right, 'U' up (jump), 'D' down (slide); taken by PlayerAvatar
    public readonly System.Collections.Generic.Queue<char> actions = new System.Collections.Generic.Queue<char>();
    public Vector2 lastMove;         // for turning old joystick messages into swipes
    public int keyboardScheme = -1;  // keyboard player: -1 WASD+arrows, 0 WASD, 1 arrows, 2 numpad (see GameInput)
    public bool wantsAgain;
}

// Messages from the phone. JsonUtility can only parse simple fields - that is enough for us.
[Serializable]
public class PhoneMessage
{
    public string t;     // type: join, char, ready, move, swipe, jump, again
    public string d;     // swipe direction: l, r, u, d
    public string cid;
    public string name;
    public int id;
    public bool v;
    public float x;
    public float y;
}

// The bridge between the network and the game. The network runs on other threads,
// and this script picks up the events in Update() and handles them on Unity's main thread.
public class PhoneHub : MonoBehaviour
{
    public const int MaxPlayers = 3;

    public static readonly Color[] SlotColors =
    {
        new Color(0.94f, 0.33f, 0.31f),
        new Color(0.26f, 0.65f, 0.96f),
        new Color(0.40f, 0.73f, 0.42f),
    };

    [SerializeField] int port = 8080;

    public readonly PhonePlayer[] Slots = new PhonePlayer[MaxPlayers];

    // true only in Multiplayer mode. In the menu, phones get a "please wait" message.
    public bool Enabled = false;

    // true only in the lobby. New phones are not accepted during a game.
    public bool AcceptNewPlayers = true;

    // Statistics for the help window: did the phone reach the computer?
    public int HttpHits { get { return server != null ? server.HttpHits : 0; } }
    public int WsTotal { get { return server != null ? server.WsTotal : 0; } }
    public int ClientCount { get { return server != null ? server.ClientCount : 0; } }

    // Which of the found addresses is shown (the Tab key switches it).
    public int UrlIndex;
    public string CurrentUrl
    {
        get { return Urls.Count == 0 ? "" : Urls[Mathf.Abs(UrlIndex) % Urls.Count]; }
    }

    public bool ServerOk { get; private set; }
    public int Port { get; private set; }
    public List<string> Urls = new List<string>();

    public event Action Changed;                    // someone joined / left / picked a character / pressed Ready
    public event Action<PhonePlayer> AgainPressed;  // "Play again" was pressed on the results screen

    MiniWebSocketServer server;
    readonly Dictionary<int, PhonePlayer> byClient = new Dictionary<int, PhonePlayer>();

    // Set before the component is added: no server (the Android version is single-player on the phone itself).
    public static bool DisableServer;

    void Awake()
    {
        if (DisableServer)
        {
            ServerOk = false;
            return;
        }

        // The page is built for every request with the current game language.
        server = new MiniWebSocketServer(() => ControllerPage.Build(Loc.CodeForThreads));
        server.Log = delegate (string m) { Debug.Log("[PhoneHub] " + m); };
        ServerOk = server.Start(port);
        if (ServerOk)
        {
            Port = server.Port;
            foreach (string ip in FindLocalIps()) Urls.Add("http://" + ip + ":" + Port);
            if (Urls.Count == 0) Urls.Add("http://localhost:" + Port);
            Debug.Log("[PhoneHub] Controller page available at: " + string.Join("  |  ", Urls));
        }
        else
        {
            Debug.LogError("[PhoneHub] Could not start the server. Ports " + port + "–" + (port + 10) + " in use?");
        }
    }

    void OnDestroy()
    {
        if (server != null) server.Stop();
    }

    void OnApplicationQuit()
    {
        if (server != null) server.Stop();
    }

    void Update()
    {
        if (server == null) return;

        ServerEvent ev;
        int guard = 0;
        while (guard++ < 500 && server.TryDequeue(out ev))
        {
            switch (ev.Type)
            {
                case ServerEventType.Message: HandleMessage(ev.ClientId, ev.Text); break;
                case ServerEventType.Disconnected: HandleDisconnect(ev.ClientId); break;
            }
        }
    }

    // ---------------- incoming messages ----------------

    void HandleMessage(int clientId, string text)
    {
        PhoneMessage m;
        try { m = JsonUtility.FromJson<PhoneMessage>(text); }
        catch { return; }
        if (m == null || string.IsNullOrEmpty(m.t)) return;

        if (m.t == "join") { HandleJoin(clientId, m); return; }

        PhonePlayer p;
        if (!byClient.TryGetValue(clientId, out p)) return;

        switch (m.t)
        {
            case "move":
                Vector2 v = new Vector2(m.x, m.y);
                if (float.IsNaN(v.x) || float.IsNaN(v.y)) v = Vector2.zero;
                p.move = Vector2.ClampMagnitude(v, 1f);
                // the hero runs in lanes now: a joystick pushed far to a side counts as one swipe
                if (p.actions.Count < 8)
                {
                    if (p.move.x > 0.6f && p.lastMove.x <= 0.6f) p.actions.Enqueue('R');
                    if (p.move.x < -0.6f && p.lastMove.x >= -0.6f) p.actions.Enqueue('L');
                    if (p.move.y > 0.6f && p.lastMove.y <= 0.6f) p.actions.Enqueue('U');
                    if (p.move.y < -0.6f && p.lastMove.y >= -0.6f) p.actions.Enqueue('D');
                }
                p.lastMove = p.move;
                break;

            case "jump":
                p.jumpQueued = true;
                break;

            case "swipe":
                if (!string.IsNullOrEmpty(m.d) && p.actions.Count < 8)
                {
                    char c = char.ToUpperInvariant(m.d[0]);
                    if (c == 'L' || c == 'R' || c == 'U' || c == 'D') p.actions.Enqueue(c);
                }
                break;

            case "char":
                if (!AcceptNewPlayers) break;
                if (m.id >= 0 && m.id < CharacterCatalog.Count && !IsCharacterTaken(m.id, p))
                {
                    p.character = m.id;
                    if (Changed != null) Changed();
                }
                break;

            case "ready":
                if (!AcceptNewPlayers) break;
                p.ready = m.v && p.character >= 0;
                if (Changed != null) Changed();
                break;

            case "again":
                p.wantsAgain = true;
                if (AgainPressed != null) AgainPressed(p);
                break;
        }
    }

    void HandleJoin(int clientId, PhoneMessage m)
    {
        // 0) network mode is off (we are in the menu) - ask the phone to wait
        if (!Enabled)
        {
            server.Send(clientId, MessageJson("wait", Loc.T("phone.waitMenu")));
            return;
        }

        // 1) this phone was already in the game - put it back in its slot
        if (!string.IsNullOrEmpty(m.cid))
        {
            foreach (PhonePlayer existing in Slots)
            {
                if (existing != null && existing.cid == m.cid && !existing.isKeyboard)
                {
                    if (existing.clientId >= 0 && existing.clientId != clientId)
                    {
                        byClient.Remove(existing.clientId);
                        server.Disconnect(existing.clientId);
                    }
                    existing.clientId = clientId;
                    existing.connected = true;
                    byClient[clientId] = existing;
                    SendJoined(existing);
                    if (Changed != null) Changed();
                    return;
                }
            }
        }

        // 2) a new player
        if (!AcceptNewPlayers)
        {
            server.Send(clientId, MessageJson("full", Loc.T("phone.fullStarted")));
            return;
        }

        int free = -1;
        for (int i = 0; i < MaxPlayers; i++) if (Slots[i] == null) { free = i; break; }
        if (free < 0)
        {
            server.Send(clientId, MessageJson("full", Loc.T("phone.fullRoom")));
            return;
        }

        PhonePlayer p = new PhonePlayer
        {
            slot = free,
            clientId = clientId,
            cid = string.IsNullOrEmpty(m.cid) ? Guid.NewGuid().ToString("N") : m.cid,
            name = CleanName(m.name, free),
            connected = true,
        };
        Slots[free] = p;
        byClient[clientId] = p;
        SendJoined(p);
        if (Changed != null) Changed();
    }

    void HandleDisconnect(int clientId)
    {
        PhonePlayer p;
        if (!byClient.TryGetValue(clientId, out p)) return;
        byClient.Remove(clientId);

        p.move = Vector2.zero;
        p.connected = false;
        p.clientId = -1;

        // In the lobby the slot is freed. During a game the player stays registered so the phone can come back.
        if (AcceptNewPlayers) Slots[p.slot] = null;
        if (Changed != null) Changed();
    }

    // ---------------- outgoing messages ----------------

    void SendJoined(PhonePlayer p)
    {
        StringBuilder sb = new StringBuilder();
        sb.Append("{\"t\":\"joined\",\"slot\":").Append(p.slot);
        sb.Append(",\"color\":\"#").Append(ColorUtility.ToHtmlStringRGB(SlotColors[p.slot])).Append('"');
        sb.Append(",\"name\":").Append(Quote(p.name));
        sb.Append(",\"lang\":\"").Append(Loc.Code).Append('"');
        sb.Append(",\"chars\":[");
        for (int i = 0; i < CharacterCatalog.Count; i++)
        {
            CharacterDef c = CharacterCatalog.All[i];
            if (i > 0) sb.Append(',');
            sb.Append("{\"n\":").Append(Quote(c.Name));
            sb.Append(",\"d\":").Append(Quote(c.Description));
            sb.Append(",\"c\":\"").Append(c.TintHex).Append("\"}");
        }
        sb.Append("]}");
        server.Send(p.clientId, sb.ToString());
    }

    public void SendTo(PhonePlayer p, string json)
    {
        if (p == null || p.isKeyboard || !p.connected || p.clientId < 0 || server == null) return;
        server.Send(p.clientId, json);
    }

    public void SendToAll(string json)
    {
        foreach (PhonePlayer p in Slots) SendTo(p, json);
    }

    // A message with text for the phone: {"t":"wait","msg":"...","lang":"ru"}
    public static string MessageJson(string type, string msg)
    {
        return "{\"t\":\"" + type + "\",\"msg\":" + Quote(msg) + ",\"lang\":\"" + Loc.Code + "\"}";
    }

    // The language was changed on the computer - all open pages (even ones still waiting) switch too.
    public void BroadcastLanguage()
    {
        if (server != null) server.Broadcast("{\"t\":\"lang\",\"lang\":\"" + Loc.Code + "\"}");
    }

    // ---------------- helpers ----------------

    public bool IsCharacterTaken(int characterIndex, PhonePlayer except)
    {
        foreach (PhonePlayer p in Slots)
            if (p != null && p != except && p.character == characterIndex) return true;
        return false;
    }

    public int PlayerCount
    {
        get { int n = 0; foreach (PhonePlayer p in Slots) if (p != null) n++; return n; }
    }

    // A keyboard player - for testing without a phone.
    public PhonePlayer AddKeyboardPlayer()
    {
        for (int i = 0; i < MaxPlayers; i++)
        {
            if (Slots[i] != null) continue;

            int character = 0;
            while (character < CharacterCatalog.Count && IsCharacterTaken(character, null)) character++;
            if (character >= CharacterCatalog.Count) character = 0;

            int keyboards = 0;
            foreach (PhonePlayer other in Slots) if (other != null && other.isKeyboard) keyboards++;

            PhonePlayer p = new PhonePlayer
            {
                slot = i,
                keyboardScheme = keyboards,
                name = keyboards == 0 ? Loc.T("player.keyboard") : Loc.T("player.keyboard") + " " + (keyboards + 1),
                character = character,
                ready = false,
                connected = true,
                isKeyboard = true,
            };
            Slots[i] = p;
            if (Changed != null) Changed();
            return p;
        }
        return null;
    }

    // Forget all players (when returning to the menu). The connections themselves stay open:
    // phones stay on the page and will return by themselves when network mode is turned on.
    public void ResetPlayers()
    {
        for (int i = 0; i < Slots.Length; i++) Slots[i] = null;
        byClient.Clear();
    }

    public void RemovePlayer(PhonePlayer p)
    {
        if (p == null) return;
        if (p.clientId >= 0) byClient.Remove(p.clientId);
        Slots[p.slot] = null;
        if (Changed != null) Changed();
    }

    static string CleanName(string raw, int slot)
    {
        string s = string.IsNullOrEmpty(raw) ? "" : raw.Trim();
        StringBuilder sb = new StringBuilder();
        foreach (char ch in s)
        {
            if (char.IsControl(ch) || ch == '<' || ch == '>' || ch == '&' || ch == '"' || ch == '\\') continue;
            sb.Append(ch);
            if (sb.Length >= 12) break;
        }
        string result = sb.ToString().Trim();
        return result.Length == 0 ? Loc.F("player.default", slot + 1) : result;
    }

    public static string Quote(string s)
    {
        StringBuilder sb = new StringBuilder("\"");
        foreach (char c in s)
        {
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': break;
                default:
                    if (c < 0x20) sb.Append(' '); else sb.Append(c);
                    break;
            }
        }
        sb.Append('"');
        return sb.ToString();
    }

    // The computer's IP addresses on the local network. The home network (192.168.x.x) goes first,
    // virtual adapters (VirtualBox, Docker, WSL...) are discarded.
    static List<string> FindLocalIps()
    {
        List<string> good = new List<string>();
        List<string> other = new List<string>();

        try
        {
            foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up) continue;
                if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;

                string n = (ni.Name + " " + ni.Description).ToLowerInvariant();
                bool virt = n.Contains("virtual") || n.Contains("vmware") || n.Contains("vbox")
                            || n.Contains("docker") || n.Contains("hyper-v") || n.Contains("vethernet")
                            || n.Contains("wsl") || n.Contains("tailscale") || n.Contains("zerotier");

                foreach (UnicastIPAddressInformation ua in ni.GetIPProperties().UnicastAddresses)
                {
                    if (ua.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                    string ip = ua.Address.ToString();
                    if (ip.StartsWith("169.254.")) continue;

                    if (!virt && ip.StartsWith("192.168.")) good.Insert(0, ip);
                    else if (!virt) good.Add(ip);
                    else other.Add(ip);
                }
            }
        }
        catch (Exception e)
        {
            Debug.LogWarning("[PhoneHub] Could not detect the IP address: " + e.Message);
        }

        good.AddRange(other);
        return good;
    }
}
