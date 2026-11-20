using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using RoyalRun.Net;
using UnityEngine;

// One runner in a Wi-Fi race (the same data is sent over the network).
[Serializable]
public class NetPlayer
{
    public int id;          // 0 = the host
    public string name;
    public int ch;          // hero (CharacterCatalog index)
    public int color;       // 0..3 (PhoneHub.SlotColors)
    public float d;         // metres run
    public int s;           // score
    public int lane;
    public float y;         // jump height
    public bool slide;
    public bool over;       // the run has ended
    public int cause;       // CrashCause
    public bool gone;       // disconnected

    [NonSerialized] public float receivedAt;   // Time.time of the last update (for smooth ghosts)
    [NonSerialized] public float speed;        // metres per second, estimated
}

[Serializable]
class NetMsg
{
    public string t;
    public int id;
    public string name;
    public int ch;
    public int seed;
    public int mode;
    public float d;
    public int s;
    public int lane;
    public float y;
    public bool slide;
    public bool over;
    public int cause;
    public string msg;
    public NetPlayer[] p;
}

// A race over Wi-Fi between copies of the game (phones and computers).
// Every device runs its own world on the SAME road (a shared random seed), sends its distance and score
// five times a second, and shows the others as "ghosts" on the road plus a live leaderboard.
//
// The host runs a small server (MiniWebSocketServer, port 8095) and is player 0. The others find the room
// automatically (NetScan asks every address of the local network) and connect with NetLink.
//   client -> host:  hello {name, ch}, char {ch}, st {d, s, lane, y, slide, over, cause}, ping
//   host -> all:     welcome {id}, room {p[], mode}, start {seed, mode}, race {p[]}, end, lobby, full {msg}
public class LanRace : MonoBehaviour
{
    public const int Port = 8095;
    public const int MaxPlayers = 4;

    public enum Role { None, Host, Client }

    public Role State { get; private set; }
    public bool Racing { get; private set; }
    public bool RaceEnded { get; private set; }
    public int MyId { get; private set; }
    public int Seed { get; private set; }
    public GameRules Mode { get; private set; }
    public string HostName { get; private set; }
    public string HostIp { get; private set; }
    public readonly List<NetPlayer> Players = new List<NetPlayer>();
    public readonly List<FoundRoom> Rooms = new List<FoundRoom>();
    public bool Scanning { get { return scan != null && scan.Running; } }
    public bool Connecting { get { return State == Role.Client && link != null && !link.Connected && !link.Failed && MyId < 0; } }

    public event Action Changed;                  // the player list or the mode changed
    public event Action<int, GameRules> Started;  // seed, mode: begin the countdown
    public event Action Ended;                    // everybody has finished
    public event Action BackToLobby;              // the host wants another round
    public event Action<string> Failed;           // a localization key: the connection broke / the room is full

    MiniWebSocketServer server;
    NetLink link;
    NetScan scan;
    readonly Dictionary<int, NetPlayer> byClient = new Dictionary<int, NetPlayer>();
    volatile string infoJson = "{}";
    string roomId;
    float sendTimer, pingTimer, broadcastTimer;

    public NetPlayer Me
    {
        get { foreach (NetPlayer p in Players) if (p.id == MyId) return p; return null; }
    }

    // ================= finding and creating rooms =================

    public void StartScan()
    {
        Rooms.Clear();
        scan = new NetScan();
        scan.Start(Port, State == Role.Host ? HostIp : null);
    }

    public bool Host(string myName, int character, GameRules mode)
    {
        Leave();
        server = new MiniWebSocketServer("<html><body>Royal Run race room</body></html>");
        server.Log = delegate (string m) { Debug.Log("[LanRace] " + m); };
        server.InfoProvider = () => infoJson;
        if (!server.Start(Port) || server.Port != Port)
        {
            server.Stop();
            server = null;
            if (Failed != null) Failed("lan.hostFail");
            return false;
        }
        State = Role.Host;
        MyId = 0;
        Mode = mode;
        HostName = myName;
        List<string> ips = NetScan.LocalAddresses();
        HostIp = ips.Count > 0 ? ips[0] : "127.0.0.1";
        roomId = UnityEngine.Random.Range(100000, 999999).ToString();
        Players.Clear();
        Players.Add(new NetPlayer { id = 0, name = myName, ch = character, color = 0 });
        RoomChanged();
        return true;
    }

    public void Join(string ip, string myName, int character)
    {
        Leave();
        State = Role.Client;
        MyId = -1;
        HostIp = ip;
        pendingName = myName;
        pendingChar = character;
        helloSent = false;
        link = new NetLink();
        link.ConnectAsync(ip, Port);
    }

    string pendingName;
    int pendingChar;
    bool helloSent;

    public void Leave()
    {
        if (server != null) { server.Stop(); server = null; }
        if (link != null) { link.Close(); link = null; }
        State = Role.None;
        Racing = false;
        RaceEnded = false;
        Players.Clear();
        byClient.Clear();
        MyId = -1;
    }

    void OnDestroy()
    {
        Leave();
    }

    void OnApplicationQuit()
    {
        Leave();
    }

    // ================= lobby actions =================

    public void SetCharacter(int character)
    {
        NetPlayer me = Me;
        if (me != null) me.ch = character;
        if (State == Role.Host) RoomChanged();
        else if (link != null) link.Send("{\"t\":\"char\",\"ch\":" + character + "}");
        if (Changed != null) Changed();
    }

    public void SetMode(GameRules mode)
    {
        if (State != Role.Host) return;
        Mode = mode;
        RoomChanged();
    }

    // Host: everybody starts on the same road.
    public void HostStart()
    {
        if (State != Role.Host) return;
        Seed = UnityEngine.Random.Range(1, int.MaxValue);
        foreach (NetPlayer p in Players) { p.d = 0f; p.s = 0; p.over = false; p.cause = 0; p.lane = 1; p.y = 0f; }
        Racing = true;
        RaceEnded = false;
        UpdateInfo();
        server.Broadcast("{\"t\":\"start\",\"seed\":" + Seed + ",\"mode\":" + (int)Mode + "}");
        if (Started != null) Started(Seed, Mode);
    }

    // Host: another round - everybody back to the room.
    public void HostBackToLobby()
    {
        if (State != Role.Host) return;
        Racing = false;
        RaceEnded = false;
        Players.RemoveAll(p => p.gone);
        RoomChanged();
        server.Broadcast("{\"t\":\"lobby\"}");
        if (BackToLobby != null) BackToLobby();
    }

    // Every frame during the race: our own run (sent 5 times a second).
    public void ReportStatus(PlayerWorld w, PlayerAvatar a)
    {
        NetPlayer me = Me;
        if (me == null || w == null) return;
        me.d = w.Distance;
        me.s = w.Score;
        me.over = w.Finished;
        me.cause = (int)w.Cause;
        if (a != null) { me.lane = a.Lane; me.y = a.Height; me.slide = a.Sliding; }

        sendTimer -= Time.deltaTime;
        if (sendTimer > 0f) return;
        sendTimer = 0.2f;
        if (State == Role.Client && link != null)
        {
            StringBuilder sb = new StringBuilder("{\"t\":\"st\"");
            sb.Append(",\"d\":").Append(me.d.ToString("F1", CultureInfo.InvariantCulture));
            sb.Append(",\"s\":").Append(me.s);
            sb.Append(",\"lane\":").Append(me.lane);
            sb.Append(",\"y\":").Append(me.y.ToString("F2", CultureInfo.InvariantCulture));
            sb.Append(",\"slide\":").Append(me.slide ? "true" : "false");
            sb.Append(",\"over\":").Append(me.over ? "true" : "false");
            sb.Append(",\"cause\":").Append(me.cause).Append('}');
            link.Send(sb.ToString());
        }
    }

    // ================= every frame =================

    void Update()
    {
        float dt = Time.unscaledDeltaTime;

        if (scan != null)
        {
            FoundRoom r;
            while (scan.TryGet(out r))
            {
                // the same room can answer on several addresses (for example 127.0.0.1 and the Wi-Fi address)
                string id = JsonField(r.Json, "room");
                bool dup = false;
                for (int i = 0; i < Rooms.Count; i++)
                {
                    if (JsonField(Rooms[i].Json, "room") != id) continue;
                    dup = true;
                    if (Rooms[i].Ip == "127.0.0.1") Rooms[i] = r;   // prefer the real address
                }
                if (!dup) Rooms.Add(r);
                if (Changed != null) Changed();
            }
        }

        if (State == Role.Host) UpdateHost(dt);
        else if (State == Role.Client) UpdateClient(dt);
    }

    void UpdateHost(float dt)
    {
        ServerEvent ev;
        int guard = 0;
        while (server != null && guard++ < 500 && server.TryDequeue(out ev))
        {
            if (ev.Type == ServerEventType.Message) HostMessage(ev.ClientId, ev.Text);
            else if (ev.Type == ServerEventType.Disconnected) HostDisconnect(ev.ClientId);
        }

        if (Racing && server != null)
        {
            broadcastTimer -= dt;
            if (broadcastTimer <= 0f)
            {
                broadcastTimer = 0.2f;
                server.Broadcast("{\"t\":\"race\",\"p\":" + PlayersJson() + "}");
            }

            if (!RaceEnded)
            {
                bool all = true;
                foreach (NetPlayer p in Players) if (!p.over && !p.gone) all = false;
                if (all)
                {
                    RaceEnded = true;
                    server.Broadcast("{\"t\":\"race\",\"p\":" + PlayersJson() + "}");
                    server.Broadcast("{\"t\":\"end\"}");
                    if (Ended != null) Ended();
                }
            }
        }
    }

    void HostMessage(int clientId, string text)
    {
        NetMsg m;
        try { m = JsonUtility.FromJson<NetMsg>(text); } catch { return; }
        if (m == null || string.IsNullOrEmpty(m.t)) return;

        NetPlayer p;
        byClient.TryGetValue(clientId, out p);

        switch (m.t)
        {
            case "hello":
                if (p != null) return;
                if (Racing || Players.Count >= MaxPlayers)
                {
                    server.Send(clientId, "{\"t\":\"full\",\"msg\":\"" + (Racing ? "lan.started" : "lan.full") + "\"}");
                    server.Disconnect(clientId);
                    return;
                }
                p = new NetPlayer
                {
                    id = clientId,
                    name = Clean(m.name, Players.Count),
                    ch = Mathf.Clamp(m.ch, 0, CharacterCatalog.Count - 1),
                    color = FreeColor(),
                };
                Players.Add(p);
                byClient[clientId] = p;
                server.Send(clientId, "{\"t\":\"welcome\",\"id\":" + clientId + ",\"name\":" + PhoneHub.Quote(HostName) + "}");
                RoomChanged();
                break;

            case "char":
                if (p == null || Racing) return;
                p.ch = Mathf.Clamp(m.ch, 0, CharacterCatalog.Count - 1);
                RoomChanged();
                break;

            case "st":
                if (p == null || !Racing) return;
                Apply(p, m.d, m.s, m.lane, m.y, m.slide, m.over, m.cause);
                break;
        }
    }

    void HostDisconnect(int clientId)
    {
        NetPlayer p;
        if (!byClient.TryGetValue(clientId, out p)) return;
        byClient.Remove(clientId);
        if (Racing) { p.gone = true; p.over = true; }
        else Players.Remove(p);
        RoomChanged();
    }

    void UpdateClient(float dt)
    {
        if (link == null) return;

        if (link.Connected && !helloSent)
        {
            helloSent = true;
            link.Send("{\"t\":\"hello\",\"name\":" + PhoneHub.Quote(pendingName) + ",\"ch\":" + pendingChar + "}");
        }

        string line;
        int guard = 0;
        while (guard++ < 500 && link.TryReceive(out line)) ClientMessage(line);

        if (link != null && link.Failed)
        {
            Leave();
            if (Failed != null) Failed("lan.lost");
            return;
        }

        // keep the connection alive in the room (during the race statuses are sent anyway)
        pingTimer -= dt;
        if (pingTimer <= 0f && link != null && link.Connected)
        {
            pingTimer = 3f;
            if (!Racing) link.Send("{\"t\":\"ping\"}");
        }
    }

    void ClientMessage(string text)
    {
        NetMsg m;
        try { m = JsonUtility.FromJson<NetMsg>(text); } catch { return; }
        if (m == null || string.IsNullOrEmpty(m.t)) return;

        switch (m.t)
        {
            case "welcome":
                MyId = m.id;
                HostName = m.name;
                if (Changed != null) Changed();
                break;

            case "full":
                string why = string.IsNullOrEmpty(m.msg) ? "lan.full" : m.msg;
                Leave();
                if (Failed != null) Failed(why);
                break;

            case "room":
                Mode = (GameRules)Mathf.Clamp(m.mode, 0, 1);
                MergePlayers(m.p, true);
                if (Changed != null) Changed();
                break;

            case "start":
                Seed = m.seed;
                Mode = (GameRules)Mathf.Clamp(m.mode, 0, 1);
                Racing = true;
                RaceEnded = false;
                foreach (NetPlayer p in Players) { p.d = 0f; p.s = 0; p.over = false; p.cause = 0; }
                if (Started != null) Started(Seed, Mode);
                break;

            case "race":
                MergePlayers(m.p, false);
                break;

            case "end":
                RaceEnded = true;
                if (Ended != null) Ended();
                break;

            case "lobby":
                Racing = false;
                RaceEnded = false;
                if (BackToLobby != null) BackToLobby();
                break;
        }
    }

    // The host's list replaces ours; our own run is kept as we know it best.
    void MergePlayers(NetPlayer[] list, bool replace)
    {
        if (list == null) return;
        if (replace)
        {
            NetPlayer mine = Me;
            Players.Clear();
            foreach (NetPlayer p in list)
            {
                if (p.id == MyId && mine != null) { mine.color = p.color; mine.name = p.name; Players.Add(mine); }
                else Players.Add(p);
            }
            return;
        }
        foreach (NetPlayer src in list)
        {
            if (src.id == MyId) continue;
            NetPlayer dst = null;
            foreach (NetPlayer p in Players) if (p.id == src.id) { dst = p; break; }
            if (dst == null) { Players.Add(src); src.receivedAt = Time.time; continue; }
            Apply(dst, src.d, src.s, src.lane, src.y, src.slide, src.over, src.cause);
            dst.gone = src.gone;
        }
    }

    static void Apply(NetPlayer p, float d, int s, int lane, float y, bool slide, bool over, int cause)
    {
        float now = Time.time;
        float elapsed = now - p.receivedAt;
        if (elapsed > 0.05f && elapsed < 2f && d >= p.d) p.speed = Mathf.Lerp(p.speed, (d - p.d) / elapsed, 0.5f);
        p.receivedAt = now;
        p.d = d;
        p.s = s;
        p.lane = Mathf.Clamp(lane, 0, 2);
        p.y = y;
        p.slide = slide;
        p.over = over;
        p.cause = cause;
        if (over) p.speed = 0f;
    }

    // ================= helpers =================

    void RoomChanged()
    {
        UpdateInfo();
        if (server != null) server.Broadcast("{\"t\":\"room\",\"mode\":" + (int)Mode + ",\"p\":" + PlayersJson() + "}");
        if (Changed != null) Changed();
    }

    void UpdateInfo()
    {
        infoJson = "{\"game\":\"royalrun\",\"room\":\"" + roomId + "\",\"name\":" + PhoneHub.Quote(HostName ?? "")
                   + ",\"players\":" + Players.Count + ",\"max\":" + MaxPlayers + ",\"racing\":" + (Racing ? "true" : "false")
                   + ",\"mode\":" + (int)Mode + "}";
    }

    string PlayersJson()
    {
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < Players.Count; i++)
        {
            NetPlayer p = Players[i];
            if (i > 0) sb.Append(',');
            sb.Append("{\"id\":").Append(p.id);
            sb.Append(",\"name\":").Append(PhoneHub.Quote(p.name ?? ""));
            sb.Append(",\"ch\":").Append(p.ch);
            sb.Append(",\"color\":").Append(p.color);
            sb.Append(",\"d\":").Append(p.d.ToString("F1", CultureInfo.InvariantCulture));
            sb.Append(",\"s\":").Append(p.s);
            sb.Append(",\"lane\":").Append(p.lane);
            sb.Append(",\"y\":").Append(p.y.ToString("F2", CultureInfo.InvariantCulture));
            sb.Append(",\"slide\":").Append(p.slide ? "true" : "false");
            sb.Append(",\"over\":").Append(p.over ? "true" : "false");
            sb.Append(",\"cause\":").Append(p.cause);
            sb.Append(",\"gone\":").Append(p.gone ? "true" : "false").Append('}');
        }
        return sb.Append(']').ToString();
    }

    int FreeColor()
    {
        for (int c = 0; c < MaxPlayers; c++)
        {
            bool used = false;
            foreach (NetPlayer p in Players) if (p.color == c) used = true;
            if (!used) return c;
        }
        return 0;
    }

    static string Clean(string raw, int index)
    {
        string s = string.IsNullOrEmpty(raw) ? "" : raw.Trim();
        StringBuilder sb = new StringBuilder();
        foreach (char ch in s)
        {
            if (char.IsControl(ch) || ch == '<' || ch == '>' || ch == '"' || ch == '\\') continue;
            sb.Append(ch);
            if (sb.Length >= 12) break;
        }
        return sb.Length == 0 ? Loc.F("player.default", index + 1) : sb.ToString();
    }

    // A very small reader for "key":"value" or "key":number in the room description.
    public static string JsonField(string json, string key)
    {
        if (string.IsNullOrEmpty(json)) return "";
        string k = "\"" + key + "\":";
        int i = json.IndexOf(k, StringComparison.Ordinal);
        if (i < 0) return "";
        i += k.Length;
        if (i < json.Length && json[i] == '"')
        {
            int end = json.IndexOf('"', i + 1);
            return end > i ? json.Substring(i + 1, end - i - 1) : "";
        }
        int e = i;
        while (e < json.Length && json[e] != ',' && json[e] != '}') e++;
        return json.Substring(i, e - i).Trim();
    }
}
