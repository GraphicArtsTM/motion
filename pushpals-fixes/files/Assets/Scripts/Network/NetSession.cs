using System;
using System.Collections.Generic;
using Netcode.Transports.Facepunch;
using PushPals.Players;
using PushPals.Ragdoll;
using Steamworks;
using Steamworks.Data;
using Unity.Netcode;
using Unity.Netcode.Transports.UTP;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.SceneManagement;

namespace PushPals.Network
{
    /// <summary>
    /// Сетевая сессия (эксперимент Этапа 7). Хост создаёт лобби Steam и считает физику всех спичек,
    /// друг входит по приглашению, из списка лобби или по коду. Для проверки на одном ПК — локальный режим
    /// (Unity Transport, 127.0.0.1). Временная панель — F2 (настоящее лобби в коробке — Этап 12).
    /// </summary>
    [RequireComponent(typeof(NetworkManager))]
    [DefaultExecutionOrder(-1000)] // раньше NetworkManager: лишняя копия из новой сцены выключается до его Awake
    public class NetSession : MonoBehaviour
    {
        [SerializeField] private UnityTransport localTransport;
        [SerializeField] private FacepunchTransport steamTransport;
        [Tooltip("ID приложения Steam. 480 — тестовое (Spacewar), своё будет после регистрации в Steamworks")]
        [SerializeField] private uint steamAppId = 480;
        [Tooltip("Метка наших лобби (на AppID 480 лобби создают тысячи чужих игр)")]
        [SerializeField] private string lobbyTag = "pushpals_v1";
        [SerializeField] private Key toggleKey = Key.F2;
        [SerializeField] private bool visibleOnStart = true;

        public static NetSession Instance { get; private set; }

        /// <summary>Что сейчас происходит — для панели и автотестов.</summary>
        public string Status { get; private set; } = "Не в сети";
        public bool IsInSession => net != null && net.IsListening;

        private NetworkManager net;
        private Lobby? lobby;
        private Lobby[] foundLobbies = new Lobby[0];
        private readonly List<Friend> onlineFriends = new List<Friend>();

        // ---------- Для экрана «Онлайн» (Этап 17.4) ----------

        public bool IsHost => net != null && net.IsHost;
        public bool SteamReady => SteamClient.IsValid;
        public string SteamName => SteamClient.IsValid ? SteamClient.Name : "";
        /// <summary>Код лобби Steam для друзей (пусто — нет лобби).</summary>
        public string LobbyCodeText => lobby.HasValue ? lobby.Value.Id.Value.ToString() : "";
        public IReadOnlyList<Lobby> FoundLobbies => foundLobbies;
        public IReadOnlyList<Friend> OnlineFriends => onlineFriends;
        public int PlayersInSession => net == null || !net.IsListening ? 0 : net.IsServer ? net.ConnectedClientsIds.Count : CountAvatars();
        public string PingMs => net != null && net.IsListening && !net.IsServer ? Ping() : "";

        /// <summary>Имена в лобби Steam (хост — первым).</summary>
        public List<string> LobbyMembers()
        {
            var list = new List<string>();
            if (!lobby.HasValue) return list;
            foreach (var m in lobby.Value.Members) list.Add(m.Name + (m.Id == lobby.Value.Owner.Id ? " ★" : ""));
            return list;
        }

        public void InviteFriend(SteamId id) { if (lobby.HasValue) lobby.Value.InviteFriend(id); }
        public void OpenInviteOverlay() { if (lobby.HasValue && SteamClient.IsValid) SteamFriends.OpenGameInviteOverlay(lobby.Value.Id); }
        public void UpdateFriends() => RefreshFriends();

        /// <summary>Войти по коду лобби (число); false — код не похож на код.</summary>
        public bool JoinByCode(string code)
        {
            ulong id;
            if (!ulong.TryParse((code ?? "").Trim(), out id)) return false;
            JoinSteam(id);
            return true;
        }
        private bool visible;
        private bool steamReady;
        private string joinCode = "";
        private string localAddress = "127.0.0.1";
        private Vector2 scroll;

        // ---------- Запуск ----------

        private void Awake()
        {
            // NetworkManager переживает смену сцены, а в каждой сцене уровня есть свой «Network» —
            // вторая копия выключается сразу (иначе с каждым уровнем копий становилось бы больше)
            if (Instance != null && Instance != this)
            {
                gameObject.SetActive(false);
                Destroy(gameObject);
                return;
            }
            Instance = this;
            net = GetComponent<NetworkManager>();
            visible = visibleOnStart;
            levelSync = GetComponent<LevelSync>();
            if (levelSync == null) levelSync = gameObject.AddComponent<LevelSync>();
            Online.ShowNetworkPanel = () => visible = true;
            Online.LeaveSession = () => Leave(false);
            Online.LobbyCode = () => !IsInSession ? "" : lobby.HasValue ? lobby.Value.Id.Value.ToString() : Online.IsHost ? "локальная игра (порт 7777)" : "";
            // Префаб спички Netcode регистрирует сам (список DefaultNetworkPrefabs), второй раз добавлять не нужно
        }

        private LevelSync levelSync;
        private readonly Dictionary<ulong, bool> restartVotes = new Dictionary<ulong, bool>();
        private bool sentVote;

        private void OnEnable() { SceneManager.sceneLoaded += OnSceneLoaded; GameRules.Changed += ApplyAccess; }
        private void OnDisable() { SceneManager.sceneLoaded -= OnSceneLoaded; GameRules.Changed -= ApplyAccess; }

        // Хост выбрал в лобби, кто может войти: лобби Steam — только друзья / все / закрыто
        private void ApplyAccess()
        {
            if (!lobby.HasValue) return;
            var l = lobby.Value;
            switch (GameRules.Access)
            {
                case GameRules.Privacy.Public: l.SetPublic(); break;
                case GameRules.Privacy.Closed: l.SetPrivate(); break;
                default: l.SetFriendsOnly(); break;
            }
            l.SetJoinable(GameRules.Access != GameRules.Privacy.Closed);
        }

        private void Start()
        {
            net.OnClientConnectedCallback += OnClientConnected;
            net.OnClientDisconnectCallback += OnClientDisconnected;

            // Сохранения в облаке Steam (только в сборке, не у автотеста): Steam подключается при запуске игры
            PushPals.Save.SaveSystem.Cloud = new SteamCloudStorage();
            PushPals.Save.Achievements.Platform = new SteamAchievements(); // достижения — в Steam, когда он подключён
            if (!Application.isEditor && Array.IndexOf(Environment.GetCommandLineArgs(), "-pp-bot") < 0 && EnsureSteam())
            {
                PushPals.Save.SaveSystem.SyncWithCloud();
                PushPals.Save.Achievements.SyncPlatform();
            }

            // Командная строка (автотест второй копией игры): -pp-host, -pp-client [адрес], -pp-bot
            var args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "-pp-bot") { NetworkRagdoll.SuppressLocalInput = true; botMode = true; }
                if (args[i] == "-pp-voicetest") NetworkVoice.TestTone = true;
                // Игру запустил Steam по приглашению друга — сразу входим в его лобби
                ulong invitedLobby;
                if (args[i] == "+connect_lobby" && i + 1 < args.Length && ulong.TryParse(args[i + 1], out invitedLobby)) JoinSteam(invitedLobby);
                if (args[i] == "-pp-host") StartLocalHost();
                if (args[i] == "-pp-client")
                {
                    if (i + 1 < args.Length && !args[i + 1].StartsWith("-")) localAddress = args[i + 1];
                    StartLocalClient(localAddress);
                }
            }
        }

        private void OnDestroy()
        {
            if (Instance != this) return; // лишняя копия из сцены уровня — ничего не трогаем
            if (net != null)
            {
                net.OnClientConnectedCallback -= OnClientConnected;
                net.OnClientDisconnectCallback -= OnClientDisconnected;
            }
            LeaveLobby();
            if (Instance == this) Instance = null;
        }

        private void OnApplicationQuit()
        {
            LeaveLobby();
            if (SteamClient.IsValid) SteamClient.Shutdown();
        }

        private void Update()
        {
            var keyboard = Keyboard.current;
            if (keyboard != null && keyboard[toggleKey].wasPressedThisFrame) visible = !visible;
            UpdateBot();

            // Колбэки Steam: пока транспорт Steam не работает, их вызываем сами (иначе он — каждый кадр)
            bool transportRuns = net.IsListening && net.NetworkConfig.NetworkTransport == steamTransport;
            if (SteamClient.IsValid && !transportRuns) SteamClient.RunCallbacks();

            // Сессия закончилась сама (хост вышел, связь пропала) — обратно в одиночную/локальную игру
            if (!net.IsListening && !net.ShutdownInProgress && PlayerManager.Instance != null && PlayerManager.Instance.IsOnline && !starting)
                EndSession("Связь потеряна");

            // Принятое приглашение: Netcode закрывает сессию только в конце кадра — входим, когда она закрылась
            if (pendingLobby.HasValue && !net.IsListening && !net.ShutdownInProgress && !joining)
            {
                var invited = pendingLobby.Value;
                pendingLobby = null;
                JoinSteam(invited);
            }
        }

        private bool starting; // между StartClient и подключением IsListening уже true, но на всякий случай

        // Идёт вход в лобби Steam (ждём ответа Steam): второй вход, хост или локальная игра в это время не начинаются
        private bool joining;
        // Приглашение принято во время другой игры: войти, когда старая сессия закроется до конца
        private SteamId? pendingLobby;

        /// <summary>Сессия идёт или вот-вот начнётся — новую не начинать.</summary>
        private bool Busy => IsInSession || joining;

        // ---------- Бот для автотеста (-pp-bot): своя спичка ходит, прыгает и хватается, в лог — что видим ----------

        private bool botMode;
        private float botTime, botLogTimer, prevBot;
        // Замер задержки: когда бот сменил направление и когда его спичка на экране реально поехала обратно
        private float flipTime = -1f, lastHipX, smoothVx, latencySum;
        private int flipSign, latencyCount;

        private void UpdateBot()
        {
            if (!botMode || !net.IsListening || !net.IsConnectedClient) return;
            RagdollController own = null;
            int avatars = 0;
            foreach (var c in FindObjectsByType<RagdollController>(FindObjectsSortMode.None))
            {
                avatars++;
                var no = c.GetComponent<NetworkObject>();
                if (no != null && no.IsSpawned && no.IsOwner) own = c;
            }
            if (own == null) return;

            float prevPhase = botTime % 6f;
            botTime += Time.deltaTime;
            float phase = botTime % 6f;

            // Задержка «нажал — увидел»: смена направления → скорость спички на экране сменила знак
            float hipX = own.Body.HipPoint.x;
            if (Time.deltaTime > 0f) smoothVx = Mathf.Lerp(smoothVx, (hipX - lastHipX) / Time.deltaTime, 0.5f);
            lastHipX = hipX;
            if ((prevPhase < 3f && phase >= 3f) || phase < prevPhase) { flipTime = Time.time; flipSign = phase >= 3f ? -1 : 1; }
            if (flipTime >= 0f && Mathf.Sign(smoothVx) == flipSign && Mathf.Abs(smoothVx) > 0.5f)
            {
                latencySum += Time.time - flipTime;
                latencyCount++;
                flipTime = -1f;
            }
            var intent = new RagdollIntent
            {
                Move = new Vector2(phase < 3f ? 1f : -1f, 0f),
                Aim = new Vector2(phase < 3f ? 1f : -1f, 0.3f).normalized,
                GrabLeft = phase > 1f && phase < 2.5f,
                GrabRight = phase > 1f && phase < 2.5f,
                JumpHeld = (botTime % 1.5f) < 0.3f,
            };
            intent.JumpPressed = (botTime % 1.5f) < Time.deltaTime;
            // Лобби: шкаф (корона, звёздочка, пара Б) на 4-й секунде, эмоция «Ура!» стоя — на 6-й
            if (PushPals.Level.LobbyBoard.Instance != null)
            {
                if (prevBot < 4f && botTime >= 4f)
                {
                    PlayerChoices.Look(own, 3, 4);
                    PlayerChoices.Wish(own, new[] { PushPals.Abilities.MatchKind.Light, PushPals.Abilities.MatchKind.Magnet });
                }
                if (botTime > 5.5f && botTime < 8.5f) intent = new RagdollIntent();
                if (prevBot < 6f && botTime >= 6f) intent.Emote = (byte)RagdollEmote.Kind.Cheer;
            }
            prevBot = botTime;
            own.SetIntent(intent);
            // «Предатель»: после уровня голосует за первого из возможных
            var round = PushPals.Level.TraitorRound.Instance;
            if (round != null && round.CanVote && round.Candidates.Count > 0)
            {
                Debug.Log("[PushPals бот] голосую против " + PushPals.Level.TraitorRound.NameOf(round.Candidates[0]));
                round.CastVote(round.Candidates[0]);
            }
            // Голос «Заново» с 20-й по 26-ю секунду (хост должен увидеть 1 голос)
            Online.VoteOverride = botTime > 20f && botTime < 26f;

            botLogTimer -= Time.deltaTime;
            if (botLogTimer <= 0f)
            {
                botLogTimer = 2f;
                Debug.Log("[PushPals бот] " + Status + " | спичек видно: " + avatars + " | моя: бёдра " + own.Body.HipPoint.ToString("F2")
                          + " на земле " + own.IsGrounded + " | время хоста " + net.ServerTime.TimeAsFloat.ToString("F1") + " | пинг " + Ping()
                          + " | разворот виден через " + (latencyCount > 0 ? (latencySum / latencyCount * 1000f).ToString("F0") + " мс (" + latencyCount + " раз)" : "—")
                          + " | кадров/с " + (1f / Time.smoothDeltaTime).ToString("F0")
                          + " | задержка показа " + (own.GetComponent<NetworkRagdoll>().InterpolationDelay * 1000f).ToString("F0") + " мс");
                Debug.Log("[PushPals бот] уровень " + LevelReport());
            }
        }

        // Что клиент видит на уровне — для проверки синхронизации
        private string LevelReport()
        {
            var sb = new System.Text.StringBuilder(SceneManager.GetActiveScene().name);
            sb.Append(" | элементов ").Append(levelSync.StateCount).Append(" (совпало ").Append(levelSync.MatchedStates).Append("), тел ").Append(levelSync.BodyCount).Append(" (совпало ").Append(levelSync.MatchedBodies).Append(")");
            var run = PushPals.Level.LevelRun.Instance;
            if (run != null) sb.Append(" | время ").Append(run.Elapsed.ToString("F1")).Append(run.Finished ? " ПРОЙДЕН" : "").Append(" | голоса ").Append(run.RestartVotes).Append("/").Append(run.RestartTotal);
            int golden = 0; foreach (var g in PushPals.Level.GoldenMatch.All) if (g.Collected) golden++;
            sb.Append(" | золотых взято ").Append(golden).Append("/").Append(PushPals.Level.GoldenMatch.All.Count);
            int open = 0, doors = 0;
            foreach (var d in FindObjectsByType<PushPals.Level.Door>(FindObjectsSortMode.None)) { doors++; if (d.IsOpen) open++; }
            sb.Append(" | дверей открыто ").Append(open).Append("/").Append(doors);
            var board = PushPals.Level.LobbyBoard.Instance;
            if (board != null) sb.Append(" | доска: ").Append(board.Selected != null ? board.Selected.id : "—").Append(" огонь ×").Append(GameRules.BurnTimeScale).Append(" отсчёт ").Append(board.Countdown.ToString("F1"))
                .Append(" колпак ").Append(GameRules.PartyHatFound ? "найден" : "нет");
            var pm = PlayerManager.Instance;
            if (pm != null) sb.Append(" | видно игроков ").Append(pm.Visible.Count).Append(pm.HostPlayer != null ? " (хост — игрок " + (pm.HostPlayer.Index + 1) + ")" : "");
            foreach (var c in FindObjectsByType<RagdollController>(FindObjectsSortMode.None))
            {
                var v = c.GetComponent<PushPals.Ragdoll.Visual.MatchVisual>();
                var e = c.GetComponent<RagdollEmote>();
                var b = c.GetComponent<PushPals.Abilities.Backpack>();
                var no = c.GetComponent<NetworkObject>();
                sb.Append(" | ").Append(no != null && no.IsOwner ? "моя" : "чужая").Append(" шапка ").Append(v != null ? v.Hat : -1).Append(v != null && v.HatOff ? " (СЛЕТЕЛА " + v.LooseHatPosition.ToString("F1") + ")" : "").Append(" дерево ").Append(v != null ? v.Wood : -1)
                  .Append(" эмоция ").Append(e != null ? e.Current.ToString() : "—").Append(" спичка ").Append(b != null && b.Active != null ? b.Active.kind.ToString() : "—");
                var voice = c.GetComponent<NetworkVoice>();
                if (voice != null) sb.Append(" голос: кусочков ").Append(voice.PacketsHeard).Append(" громкость ").Append(voice.Volume.ToString("F2")).Append(voice.Speaking ? " ГОВОРИТ" : "");
            }
            var box = GameObject.Find("Box");
            if (box != null) sb.Append(" | Box ").Append(((Vector2)box.transform.position).ToString("F2"));
            var heavy = GameObject.Find("Heavy Box");
            if (heavy != null) sb.Append(" | Heavy Box ").Append(((Vector2)heavy.transform.position).ToString("F2"));
            return sb.ToString();
        }

        /// <summary>Подключить Steam, если ещё не подключён (голос в локальной сети тоже идёт через Steam).</summary>
        public bool TryInitSteam() => EnsureSteam();

        private bool EnsureSteam()
        {
            if (SteamClient.IsValid) { steamReady = true; return true; }
            try
            {
                SteamClient.Init(steamAppId, false);
                steamReady = SteamClient.IsValid;
                if (steamReady)
                {
                    SteamFriends.OnGameLobbyJoinRequested -= OnInviteAccepted;
                    SteamFriends.OnGameLobbyJoinRequested += OnInviteAccepted;
                }
            }
            catch (Exception e)
            {
                steamReady = false;
                Status = "Steam не запущен или недоступен";
                Debug.LogWarning("[PushPals] Steam: " + e.Message);
            }
            return steamReady;
        }

        // ---------- Хост и клиент ----------

        /// <summary>Создать лобби Steam и стать хостом.</summary>
        public async void HostSteam()
        {
            if (Busy || !EnsureSteam()) return;
            Status = "Создаю лобби…";
            BeginSession(steamTransport);
            if (!net.StartHost()) { EndSession("Не удалось стать хостом"); return; }
            SetRole(true);

            var created = await SteamMatchmaking.CreateLobbyAsync(PlayerManager.MaxPlayers);
            if (!created.HasValue) { Status = "Хост запущен, но лобби Steam не создалось"; return; }
            var l = created.Value;
            l.SetData(lobbyTag, "1");
            l.SetData("name", SteamClient.Name);
            lobby = l;
            ApplyAccess(); // «все» — видно в списке «Найти игру» (с нашей меткой), «только друзья» — через друзей Steam
            // Друзья видят «Присоединиться» в списке друзей Steam
            SteamFriends.SetRichPresence("connect", "+connect_lobby " + l.Id.Value);
            SteamFriends.SetRichPresence("status", "Играет в PushPals — можно присоединиться");
            Status = "Хост. Лобби " + l.Id.Value + " — пригласите друга";
            RefreshFriends();
        }

        /// <summary>Войти в лобби Steam (по приглашению, из списка или по коду) и подключиться к хосту.</summary>
        public async void JoinSteam(SteamId lobbyId)
        {
            // Повторное нажатие «Войти», пока ждём Steam, второй раз не входит (иначе второй StartClient
            // не удавался и EndSession разбирал уже идущую сессию)
            if (Busy || !EnsureSteam()) return;
            joining = true;
            try
            {
                Status = "Вхожу в лобби…";
                var joined = await SteamMatchmaking.JoinLobbyAsync(lobbyId);
                if (!joined.HasValue) { Status = "Не удалось войти в лобби"; return; }
                var l = joined.Value;
                // Пока ждали Steam, сессия могла начаться другим путём — это лобби уже не нужно
                if (IsInSession) { l.Leave(); return; }
                lobby = l;
                steamTransport.targetSteamId = l.Owner.Id;
                BeginSession(steamTransport);
                Status = "Подключаюсь к " + l.Owner.Name + "…";
                if (!net.StartClient()) { EndSession("Не удалось подключиться"); return; }
                SetRole(false);
            }
            finally { joining = false; }
        }

        /// <summary>Хост на этом ПК без Steam (проверка вдвоём на одном компьютере / в локальной сети).</summary>
        public void StartLocalHost()
        {
            if (Busy) return;
            BeginSession(localTransport);
            localTransport.SetConnectionData("0.0.0.0", 7777);
            if (net.StartHost()) { Status = "Локальный хост (порт 7777)"; SetRole(true); }
            else EndSession("Не удалось стать хостом");
        }

        public void StartLocalClient(string address)
        {
            if (Busy) return;
            BeginSession(localTransport);
            localTransport.SetConnectionData(address, 7777);
            if (net.StartClient()) { Status = "Подключаюсь к " + address + "…"; SetRole(false); }
            else EndSession("Не удалось подключиться");
        }

        /// <summary>Выйти из сетевой игры. reloadClient — клиенту начать уровень заново своей игрой (false — сцену сменят следом).</summary>
        public void Leave(bool reloadClient = true)
        {
            pendingLobby = null;
            if (net.IsListening) net.Shutdown();
            EndSession("Не в сети", reloadClient);
        }

        private void BeginSession(NetworkTransport transport)
        {
            starting = true;
            net.NetworkConfig.NetworkTransport = transport;
            // Очередь пакетов побольше: 4 игрока шлют намерения 100 раз/с, при подвисании кадра 128 не хватало
            if (transport is UnityTransport utp) utp.MaxPacketQueueSize = 512;
            // Вход проверяет хост: «никто» в лобби закрывает вход, больше 4 людей не пускаем (одинаково у хоста и клиента)
            net.NetworkConfig.ConnectionApproval = true;
            net.ConnectionApprovalCallback = Approve;
            var manager = PlayerManager.Instance;
            if (manager != null)
            {
                manager.SetOnline(true);
                manager.NetworkSpawner = SpawnAvatar;
            }
            starting = false;
        }

        // Сессия запущена: кто мы, кто считает мир, как грузить уровни и голосовать
        private void SetRole(bool server)
        {
            Online.IsActive = true;
            Online.IsClientView = !server;
            Online.RemoteRestartVotes = 0;
            Online.PeopleCount = 1;
            restartVotes.Clear();
            sentVote = false;
            Online.LocalClientId = net.LocalClientId;
            net.CustomMessagingManager.RegisterNamedMessageHandler(PrivateMessage, OnPrivate);
            if (server)
            {
                Online.LoadSceneForAll = LoadSceneForAll;
                Online.SendRestartVote = null;
                Online.SendToClient = SendPrivate;
                Online.SendToHost = null;
                net.CustomMessagingManager.RegisterNamedMessageHandler(VoteMessage, OnVote);
                net.SceneManager.OnLoadEventCompleted += OnLoadEventCompleted;
            }
            else
            {
                Online.LoadSceneForAll = null;
                Online.SendRestartVote = SendVote;
                Online.SendToClient = null;
                Online.SendToHost = (channel, data) => SendPrivate(NetworkManager.ServerClientId, channel, data);
            }
            levelSync.Begin(net, server);
        }

        // Хост: пустить ли подключившегося
        private void Approve(NetworkManager.ConnectionApprovalRequest request, NetworkManager.ConnectionApprovalResponse response)
        {
            bool self = request.ClientNetworkId == NetworkManager.ServerClientId;
            bool full = net.ConnectedClientsIds.Count >= PlayerManager.MaxPlayers;
            bool closed = GameRules.Access == GameRules.Privacy.Closed;
            response.Approved = self || (!full && !closed);
            response.Reason = full ? "Все 4 места заняты" : closed ? "Хост закрыл вход" : "";
            response.CreatePlayerObject = false; // спичку создаёт PlayerManager (OnClientConnected)
            response.Pending = false;
        }

        private void EndSession(string status, bool reloadClient = true)
        {
            bool wasClient = Online.IsClientView;
            bool wasActive = Online.IsActive;
            LeaveLobby();
            levelSync.End();
            if (net != null && net.SceneManager != null) net.SceneManager.OnLoadEventCompleted -= OnLoadEventCompleted;
            Online.IsActive = false;
            Online.IsClientView = false;
            Online.LoadSceneForAll = null;
            Online.SendRestartVote = null;
            Online.SendToClient = null;
            Online.SendToHost = null;
            Online.RemoteRestartVotes = 0;
            var manager = PlayerManager.Instance;
            if (manager != null) manager.SetOnline(false);
            Status = status;
            // Клиент: уровень показывал снимки хоста (предметы кинематические, огонь не считался) —
            // начинаем его заново уже своей игрой
            if (wasActive && wasClient && reloadClient) SceneManager.LoadScene(SceneManager.GetActiveScene().name);
        }

        // ---------- Уровни по сети ----------

        // Хост: загрузить уровень у всех (Netcode сам загрузит его клиентам и опоздавшим)
        private void LoadSceneForAll(string scene)
        {
            if (!net.IsServer) return;
            restartVotes.Clear();
            Online.RemoteRestartVotes = 0;
            net.SceneManager.LoadScene(scene, LoadSceneMode.Single);
        }

        // Новая сцена загружена (у хоста и у клиента): её PlayerManager — в сетевой режим
        private void OnSceneLoaded(Scene scene, LoadSceneMode mode)
        {
            if (Instance != this || !IsInSession) return;
            var manager = PlayerManager.Instance;
            if (manager != null)
            {
                manager.SetOnline(true);
                manager.NetworkSpawner = SpawnAvatar;
            }
        }

        // Хост: все загрузили уровень — каждому снова своя спичка (старые исчезли вместе со сценой)
        private void OnLoadEventCompleted(string sceneName, LoadSceneMode mode, List<ulong> completed, List<ulong> timedOut)
        {
            var manager = PlayerManager.Instance;
            if (!net.IsServer || manager == null) return;
            foreach (var id in net.ConnectedClientsIds)
            {
                bool has = false;
                foreach (var p in manager.Players)
                {
                    var no = p != null ? p.GetComponent<NetworkObject>() : null;
                    if (no != null && no.IsSpawned && no.OwnerClientId == id && p.IsNetworkPlayer) has = true;
                }
                if (!has) manager.AddNetworkPlayer(id);
            }
        }

        private bool IsConnected(ulong id)
        {
            foreach (var c in net.ConnectedClientsIds) if (c == id) return true;
            return false;
        }

        // ---------- Личные сообщения (Online.SendToClient / SendToHost) ----------

        private const string PrivateMessage = "pp_msg";

        private void SendPrivate(ulong target, string channel, byte[] data)
        {
            if (net == null || !net.IsListening) return;
            data = data ?? new byte[0];
            using (var writer = new Unity.Netcode.FastBufferWriter(64 + data.Length + channel.Length * 2, Unity.Collections.Allocator.Temp))
            {
                writer.WriteValueSafe(channel);
                writer.WriteValueSafe(data.Length);
                writer.WriteBytesSafe(data);
                net.CustomMessagingManager.SendNamedMessage(PrivateMessage, target, writer, NetworkDelivery.Reliable);
            }
        }

        private void OnPrivate(ulong sender, Unity.Netcode.FastBufferReader reader)
        {
            string channel;
            int length;
            byte[] data;
            try
            {
                reader.ReadValueSafe(out channel);
                reader.ReadValueSafe(out length);
                // Длина пришла из сети: не больше, чем реально осталось в пакете (иначе чужой ПК мог
                // заставить выделить гигабайты одним сообщением)
                if (length < 0 || length > reader.Length - reader.Position) return;
                data = new byte[length];
                if (length > 0) reader.ReadBytesSafe(ref data, length);
            }
            catch (Exception e)
            {
                Debug.LogWarning("[PushPals] Битое сообщение от " + sender + ": " + e.Message);
                return;
            }
            Online.Dispatch(channel, sender, data);
        }

        // ---------- Голосование «Заново» ----------

        private const string VoteMessage = "pp_vote";

        // Клиент: держим ли «Заново» — хосту (только когда меняется)
        private void SendVote(bool holding)
        {
            if (holding == sentVote || !net.IsConnectedClient) return;
            sentVote = holding;
            using (var writer = new Unity.Netcode.FastBufferWriter(1, Unity.Collections.Allocator.Temp))
            {
                writer.WriteValueSafe(holding);
                net.CustomMessagingManager.SendNamedMessage(VoteMessage, NetworkManager.ServerClientId, writer, NetworkDelivery.Reliable);
            }
        }

        // Хост: голос клиента
        private void OnVote(ulong sender, Unity.Netcode.FastBufferReader reader)
        {
            bool holding;
            reader.ReadValueSafe(out holding);
            restartVotes[sender] = holding;
            int n = 0;
            foreach (var kv in restartVotes) if (kv.Value && IsConnected(kv.Key)) n++;
            Online.RemoteRestartVotes = n;
        }

        private void LeaveLobby()
        {
            // Steam мог уже отключиться (выход из Play, закрытие игры) — тогда его вызовы падают
            try
            {
                if (lobby.HasValue && SteamClient.IsValid) lobby.Value.Leave();
                if (SteamClient.IsValid) SteamFriends.ClearRichPresence();
            }
            catch (Exception e) { Debug.LogWarning("[PushPals] Steam при выходе из лобби: " + e.Message); }
            lobby = null;
        }

        // Хост: спичка появилась у PlayerManager — показать её всем (владелец — подключившийся игрок)
        private bool SpawnAvatar(GameObject avatar, ulong ownerId)
        {
            if (!net.IsServer) return false;
            var networkObject = avatar.GetComponent<NetworkObject>();
            if (networkObject == null) return false;
            if (ownerId == ulong.MaxValue) networkObject.Spawn(true);
            else networkObject.SpawnAsPlayerObject(ownerId, true);
            return true;
        }

        // ---------- События сети ----------

        private void OnClientConnected(ulong clientId)
        {
            // Свой номер в сети известен только после подключения (при StartClient он ещё 0 — как у хоста)
            if (clientId == net.LocalClientId) Online.LocalClientId = clientId;
            if (net.IsServer)
            {
                // Каждому подключившемуся (и самому хосту) — своя спичка
                PlayerManager.Instance?.AddNetworkPlayer(clientId);
                Online.PeopleCount = net.ConnectedClientsIds.Count;
                Status = (lobby.HasValue ? "Хост, лобби " + lobby.Value.Id.Value : "Хост") + ". Игроков: " + net.ConnectedClientsIds.Count;
            }
            else if (clientId == net.LocalClientId)
            {
                Status = "В игре у " + (lobby.HasValue ? lobby.Value.Owner.Name : localAddress);
            }
        }

        private void OnClientDisconnected(ulong clientId)
        {
            if (net.IsServer)
            {
                var manager = PlayerManager.Instance;
                if (manager == null) return;
                bool had = false;
                foreach (var p in manager.Players)
                {
                    var no = p.GetComponent<NetworkObject>();
                    if (no != null && no.IsSpawned && no.OwnerClientId == clientId && p.IsNetworkPlayer)
                    {
                        manager.RemoveNetworkPlayer(p);
                        had = true;
                        break;
                    }
                }
                restartVotes.Remove(clientId);
                int people = 0;
                foreach (var id in net.ConnectedClientsIds) if (id != clientId) people++;
                Online.PeopleCount = Mathf.Max(1, people);
                // Не пущенный (вход закрыт, мест нет) в игре и не был
                Status = (had ? "Игрок вышел" : "Кого-то не пустили (вход закрыт или мест нет)") + ". Игроков: " + Online.PeopleCount;
            }
            else if (clientId == net.LocalClientId || clientId == NetworkManager.ServerClientId)
            {
                string reason = net.DisconnectReason;
                EndSession(string.IsNullOrEmpty(reason) ? "Хост закрыл игру или связь пропала" : "Не пустили: " + reason);
                if (botMode) Debug.Log("[PushPals бот] " + Status);
            }
        }

        // Друг пригласил через Steam, а мы приняли приглашение (игра уже запущена)
        private void OnInviteAccepted(Lobby invited, SteamId friend)
        {
            // Netcode закрывает сессию только в конце кадра: сразу после Leave() IsListening ещё true и
            // JoinSteam ничего не делал — входим из Update, когда старая сессия закрылась
            if (IsInSession) Leave();
            pendingLobby = invited.Id;
        }

        // ---------- Поиск и приглашения ----------

        public async void FindLobbies()
        {
            if (!EnsureSteam()) return;
            Status = "Ищу игры…";
            var list = await SteamMatchmaking.LobbyList.WithKeyValue(lobbyTag, "1").WithSlotsAvailable(1).RequestAsync();
            foundLobbies = list ?? new Lobby[0];
            Status = "Найдено игр: " + foundLobbies.Length;
        }

        private void RefreshFriends()
        {
            onlineFriends.Clear();
            if (!SteamClient.IsValid) return;
            foreach (var f in SteamFriends.GetFriends())
                if (f.IsOnline) onlineFriends.Add(f);
        }

        // ---------- Временная панель (F2) ----------

        private void OnGUI()
        {
            if (!visible) return;
            GUILayout.BeginArea(new Rect(Screen.width - 340, 10, 330, Screen.height - 60), GUI.skin.box);
            GUILayout.Label("<b>Сетевая игра — F2 скрыть</b>");
            GUILayout.Label(Status);

            if (IsInSession)
            {
                GUILayout.Label((net.IsHost ? "Хост" : "Клиент") + " · игроков: " + (net.IsServer ? net.ConnectedClientsIds.Count : CountAvatars())
                                + (net.IsServer ? "" : " · пинг " + Ping() + " мс"));
                if (lobby.HasValue)
                {
                    GUILayout.BeginHorizontal();
                    GUILayout.Label("Код лобби: " + lobby.Value.Id.Value);
                    if (GUILayout.Button("Копировать", GUILayout.Width(90))) GUIUtility.systemCopyBuffer = lobby.Value.Id.Value.ToString();
                    GUILayout.EndHorizontal();
                    // Кто в лобби
                    foreach (var m in lobby.Value.Members)
                        GUILayout.Label("  • " + m.Name + (m.Id == lobby.Value.Owner.Id ? " (хост)" : ""));
                    if (net.IsHost)
                    {
                        if (GUILayout.Button("Окно приглашения Steam (только в сборке)")) SteamFriends.OpenGameInviteOverlay(lobby.Value.Id);
                        if (GUILayout.Button("Обновить список друзей")) RefreshFriends();
                        scroll = GUILayout.BeginScrollView(scroll, GUILayout.Height(160));
                        foreach (var f in onlineFriends)
                            if (GUILayout.Button("Пригласить: " + f.Name)) lobby.Value.InviteFriend(f.Id);
                        GUILayout.EndScrollView();
                    }
                }
                if (net.IsServer && GUILayout.Button("+ манекен")) PlayerManager.Instance?.AddDummy();
                if (GUILayout.Button("Выйти из сетевой игры")) Leave();
            }
            else
            {
                GUILayout.Label("<b>Steam</b>" + (SteamClient.IsValid ? " — " + SteamClient.Name : ""));
                if (GUILayout.Button("Создать игру (лобби Steam)")) HostSteam();
                if (GUILayout.Button("Найти игры друзей")) FindLobbies();
                foreach (var l in foundLobbies)
                    if (GUILayout.Button("Войти: " + l.GetData("name") + " (" + l.MemberCount + "/" + l.MaxMembers + ")")) JoinSteam(l.Id);
                GUILayout.BeginHorizontal();
                GUILayout.Label("Код:", GUILayout.Width(40));
                joinCode = GUILayout.TextField(joinCode);
                ulong code;
                if (GUILayout.Button("Войти", GUILayout.Width(60)) && ulong.TryParse(joinCode.Trim(), out code)) JoinSteam(code);
                GUILayout.EndHorizontal();

                GUILayout.Space(8);
                GUILayout.Label("<b>Без Steam (на одном ПК / в локальной сети)</b>");
                if (GUILayout.Button("Локальный хост")) StartLocalHost();
                GUILayout.BeginHorizontal();
                localAddress = GUILayout.TextField(localAddress);
                if (GUILayout.Button("Подключиться", GUILayout.Width(110))) StartLocalClient(localAddress);
                GUILayout.EndHorizontal();
            }
            GUILayout.EndArea();
        }

        private static int CountAvatars()
        {
            return FindObjectsByType<RagdollController>(FindObjectsSortMode.None).Length;
        }

        private string Ping()
        {
            var transport = net.NetworkConfig.NetworkTransport;
            return transport != null ? transport.GetCurrentRtt(NetworkManager.ServerClientId).ToString() : "?";
        }
    }
}
