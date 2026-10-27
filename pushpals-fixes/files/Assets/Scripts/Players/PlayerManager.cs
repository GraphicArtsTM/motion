using System;
using System.Collections.Generic;
using PushPals.Ragdoll;
using UnityEngine;
using UnityEngine.InputSystem;

namespace PushPals.Players
{
    /// <summary>
    /// Единственное место, где игроки появляются и исчезают. Вход на ходу — нажать любую кнопку
    /// на свободном геймпаде или клавиатуре (PlayerInputManager), выход — удерживать «Меню».
    /// Новый игрок появляется рядом с друзьями (на свободном месте), упавший — тоже.
    /// Остальные системы подписываются на PlayerJoined / PlayerLeft и не хранят ссылок на игроков.
    /// </summary>
    [RequireComponent(typeof(PlayerInputManager))]
    [DefaultExecutionOrder(-50)]
    public class PlayerManager : MonoBehaviour
    {
        public const int MaxPlayers = 4;

        [Tooltip("Цвета ленточек игроков 1–4 (не красный, зелёный, синий, фиолетовый — это цвета головок спичек)")]
        [SerializeField] private Color[] playerColors =
        {
            new Color(1.00f, 0.80f, 0.15f), // жёлтый
            new Color(0.97f, 0.97f, 0.97f), // белый
            new Color(1.00f, 0.45f, 0.70f), // розовый
            new Color(0.20f, 0.20f, 0.22f), // тёмный
        };

        [Header("Появление")]
        [Tooltip("На что можно встать при появлении")]
        [SerializeField] private LayerMask groundMask = ~0;
        [Tooltip("Что мешает появиться (стены, игроки, предметы)")]
        [SerializeField] private LayerMask blockMask = ~0;
        [Tooltip("Ширина и высота места, нужного спичке")]
        [SerializeField] private Vector2 spawnSize = new Vector2(0.9f, 2f);
        [Tooltip("Расстояние между игроками при появлении рядом")]
        [SerializeField] private float spawnSpacing = 1f;

        [Header("Выход и падение")]
        [Tooltip("Ниже этой высоты игрок считается упавшим — возвращается к друзьям или на старт")]
        [SerializeField] private float fallY = -6f;
        [Tooltip("Сколько секунд держать «Меню», чтобы выйти из игры")]
        [SerializeField] private float leaveHoldTime = 1.5f;
        [Tooltip("Сколько секунд ждать переподключения геймпада, прежде чем убрать игрока")]
        [SerializeField] private float deviceLostTimeout = 10f;

        [Header("Спичка")]
        [Tooltip("Префаб спички (без ввода). Ввод игрока — отдельный объект LocalController у PlayerInputManager")]
        [SerializeField] private GameObject avatarPrefab;

        public static PlayerManager Instance { get; private set; }

        private class Slot
        {
            public Player Player;
            public float MenuHeld;
            public float LostTime = -1f; // ≥ 0 — устройство отключено столько секунд
            public bool NeedsSpawn;      // тело ещё не построено — поставим, когда будет готово
            public float LastSafeX = float.NegativeInfinity; // где последний раз стоял на твёрдой земле (для контрольных точек)
            public Action<PlayerInput> OnLost, OnRegained;
        }

        private readonly List<Slot> slots = new List<Slot>();
        private readonly List<Player> players = new List<Player>();
        private readonly List<Collider2D> blockers = new List<Collider2D>(8);
        private readonly List<RaycastHit2D> groundHits = new List<RaycastHit2D>(8);
        private PlayerInputManager inputManager;

        /// <summary>Игроки по номерам (включая манекены). У сетевого клиента пусто — игроками управляет хост.</summary>
        public IReadOnlyList<Player> Players => players;

        /// <summary>Ниже этой высоты — упал в пропасть (игроки возвращаются к точке, предметы уровня — на место).</summary>
        public float FallY => fallY;

        // Сетевой клиент: спички, которые прислал хост (только чтобы показывать)
        private readonly List<Player> remotes = new List<Player>();

        /// <summary>Кто хост (выбирает уровень в лобби): по сети — спичка ПК-хоста, за одним ПК — первый вошедший живой игрок.</summary>
        public Player HostPlayer
        {
            get
            {
                if (Online.IsActive)
                {
                    foreach (var p in Visible) if (p != null && p.IsHostAvatar) return p;
                    return null;
                }
                foreach (var p in players) if (p != null && p.Input != null) return p;
                return null;
            }
        }

        /// <summary>
        /// Все спички, видные на этом ПК: у хоста и за одним ПК — игроки, у сетевого клиента — спички от хоста.
        /// Для подсказок, HUD, шкафа — того, что только показывает (решает всё равно хост).
        /// </summary>
        public IReadOnlyList<Player> Visible
        {
            get
            {
                if (!Online.IsClientView) return players;
                remotes.RemoveAll(p => p == null);
                return remotes;
            }
        }

        public event Action<Player> PlayerJoined;
        public event Action<Player> PlayerLeft;

        /// <summary>
        /// Сетевая игра: игроки входят через сеть (по одному на компьютер), вход кнопкой выключен.
        /// Спички создаёт хост; включает сетевой модуль (PushPals.Network).
        /// </summary>
        public bool IsOnline { get; private set; }

        /// <summary>Как заспавнить спичку по сети (задаёт сетевой модуль): объект и владелец (ulong.MaxValue — хост).</summary>
        public Func<GameObject, ulong, bool> NetworkSpawner { get; set; }

        /// <summary>Цвет игрока по номеру (клиенты берут отсюда, номер приходит по сети).</summary>
        public Color ColorFor(int index) => playerColors[Mathf.Abs(index) % playerColors.Length];

        private void Awake()
        {
            Instance = this;
            inputManager = GetComponent<PlayerInputManager>();
        }

        private void OnEnable()
        {
            inputManager.onPlayerJoined += OnPlayerJoined;
            inputManager.onPlayerLeft += OnPlayerLeft;
        }

        private void OnDisable()
        {
            inputManager.onPlayerJoined -= OnPlayerJoined;
            inputManager.onPlayerLeft -= OnPlayerLeft;
            if (Instance == this) Instance = null;
        }

        // ---------- Вход и выход ----------

        // Кто-то нажал кнопку на свободном устройстве: PlayerInputManager создал LocalController — даём ему спичку
        private void OnPlayerJoined(PlayerInput input)
        {
            if (IsOnline || slots.Count >= MaxPlayers) { Destroy(input.gameObject); return; }
            var player = CreateAvatar("Игрок");
            if (player == null) { Destroy(input.gameObject); return; }
            player.LinkInput(input);
            var slot = Register(player);
            if (slot == null) { Destroy(player.gameObject); Destroy(input.gameObject); return; }

            slot.OnLost = _ => slot.LostTime = 0f;
            slot.OnRegained = _ => slot.LostTime = -1f;
            input.onDeviceLost += slot.OnLost;
            input.onDeviceRegained += slot.OnRegained;
        }

        private void OnPlayerLeft(PlayerInput input)
        {
            var slot = slots.Find(s => s.Player != null && s.Player.Input == input);
            if (slot == null) return;
            var player = slot.Player;
            Unregister(slot);
            if (player != null) Destroy(player.gameObject);
        }

        // ---------- Переход между уровнями ----------

        // Команда, запомненная перед загрузкой следующего уровня (живёт между сценами)
        private struct PartyMember
        {
            public bool Dummy;
            public string Scheme;
            public int[] Devices;
        }
        private static List<PartyMember> party;

        // Выбор в лобби: какие спички хочет игрок (по PartyKey — переживает смену уровня)
        private static readonly Dictionary<string, PushPals.Abilities.MatchKind[]> wishes = new Dictionary<string, PushPals.Abilities.MatchKind[]>();

        // Play в редакторе без перезагрузки домена: статика живёт между запусками — сбрасываем
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStatics() { party = null; wishes.Clear(); looks.Clear(); }

        // Внешний вид из шкафа: шапка и дерево (по PartyKey — переживает смену уровня)
        private static readonly Dictionary<string, Vector2Int> looks = new Dictionary<string, Vector2Int>();

        /// <summary>Шкаф в лобби: шапка и дерево игрока (запоминаются до выхода из игры; на диск — Этап 15).</summary>
        public void SetLook(Player player, int hat, int wood)
        {
            if (player == null) return;
            looks[player.PartyKey] = new Vector2Int(hat, wood);
            ApplyLook(player);
        }

        // Надеть запомненное (вызывается каждый кадр — дёшево: MatchVisual перерисовывает только при смене)
        private void ApplyLook(Player player)
        {
            Vector2Int look;
            if (Online.IsClientView) return;
            if (!looks.TryGetValue(player.PartyKey, out look))
            {
                // Нет выбора в этой игре — из сохранения (игрок за этим ПК, по номеру)
                if (player.Input == null || player.IsNetworkPlayer || player.Index < 0) return;
                var saved = PushPals.Save.SaveSystem.LookOf(player.Index);
                // Закрытое (мало звёзд) не надеваем
                looks[player.PartyKey] = look = new Vector2Int(PushPals.Level.Unlocks.Hat(saved.hat) ? saved.hat : 0, PushPals.Level.Unlocks.Wood(saved.wood) ? saved.wood : 0);
            }
            var visual = player.GetComponent<PushPals.Ragdoll.Visual.MatchVisual>();
            if (visual == null) return;
            visual.Hat = look.x;
            visual.Wood = look.y;
        }

        /// <summary>
        /// Лобби: игрок хочет эти спички (пару или одну) — выбор в шкафу. null — «любые» (пожелание снимается).
        /// Раздача пересчитывается.
        /// </summary>
        public void Wish(Player player, PushPals.Abilities.MatchKind[] kinds)
        {
            if (player == null) return;
            if (kinds == null || kinds.Length == 0)
            {
                if (wishes.Remove(player.PartyKey)) ReassignMatches();
                return;
            }
            PushPals.Abilities.MatchKind[] old;
            if (wishes.TryGetValue(player.PartyKey, out old) && SameKinds(old, kinds)) return;
            // Эти спички хочет только он: у остальных такое же пожелание снимаем
            foreach (var p in players)
            {
                if (p == null || p == player) continue;
                PushPals.Abilities.MatchKind[] w;
                // При трёх игроках целой может быть только одна пара: новый выбор пары отменяет чужой
                if (wishes.TryGetValue(p.PartyKey, out w) && (Overlaps(w, kinds) || players.Count == 3 && w.Length >= 2 && kinds.Length >= 2)) wishes.Remove(p.PartyKey);
            }
            wishes[player.PartyKey] = kinds;
            ReassignMatches();
        }

        /// <summary>Что игрок выбрал в лобби (null — ничего).</summary>
        public PushPals.Abilities.MatchKind[] WishOf(Player player)
        {
            PushPals.Abilities.MatchKind[] w;
            return player != null && wishes.TryGetValue(player.PartyKey, out w) ? w : null;
        }

        private static bool SameKinds(PushPals.Abilities.MatchKind[] a, PushPals.Abilities.MatchKind[] b)
        {
            if (a.Length != b.Length) return false;
            for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
            return true;
        }

        private static bool Overlaps(PushPals.Abilities.MatchKind[] a, PushPals.Abilities.MatchKind[] b)
        {
            foreach (var x in a) foreach (var y in b) if (x == y) return true;
            return false;
        }

        /// <summary>
        /// Запомнить команду перед загрузкой следующего уровня: в новой сцене те же игроки войдут сами,
        /// на тех же геймпадах и клавиатуре, в том же порядке (цвета ленточек сохранятся).
        /// </summary>
        public void RememberParty()
        {
            party = new List<PartyMember>();
            foreach (var p in players)
            {
                if (p == null || p.IsNetworkPlayer) continue;
                var member = new PartyMember { Dummy = p.IsDummy };
                if (p.Input != null)
                {
                    member.Scheme = p.Input.currentControlScheme;
                    var ids = new List<int>();
                    foreach (var d in p.Input.devices) ids.Add(d.deviceId);
                    member.Devices = ids.ToArray();
                }
                party.Add(member);
            }
        }

        private void Start()
        {
            if (party == null || IsOnline) return;
            var members = party;
            party = null;
            foreach (var m in members)
            {
                if (m.Dummy) { AddDummy(); continue; }
                var devices = new List<InputDevice>();
                if (m.Devices != null)
                    foreach (int id in m.Devices)
                    {
                        var d = InputSystem.GetDeviceById(id);
                        if (d != null) devices.Add(d);
                    }
                if (devices.Count == 0) continue; // устройство отключили, пока грузился уровень — войдёт кнопкой
                inputManager.JoinPlayer(-1, -1, m.Scheme, devices.ToArray());
            }
        }

        /// <summary>Добавить манекен — спичку без управления (за неё можно хвататься, носить, вставать на неё).</summary>
        public Player AddDummy()
        {
            if (slots.Count >= MaxPlayers) return null;
            var player = CreateAvatar("Манекен");
            if (player == null) return null;
            if (Register(player) == null) { Destroy(player.gameObject); return null; }
            if (IsOnline) SpawnOnNetwork(player, ulong.MaxValue);
            return player;
        }

        // Спичку ставим на место появления до того, как она построит тело (тело строится в Awake там, где стоит)
        private Player CreateAvatar(string name)
        {
            if (avatarPrefab == null) return null;
            var holder = new GameObject("AvatarHolder");
            holder.SetActive(false);
            var go = Instantiate(avatarPrefab, holder.transform);
            go.name = name;
            var player = go.GetComponent<Player>();
            if (player == null) player = go.AddComponent<Player>();
            go.transform.position = FindSpawn(player);
            go.transform.SetParent(null, true); // объект включается и просыпается
            Destroy(holder);
            return player;
        }

        /// <summary>Убрать игрока или манекен из игры (вместе с его вводом на этом ПК).</summary>
        public void Remove(Player player)
        {
            if (player == null) return;
            var slot = slots.Find(s => s.Player == player);
            if (slot != null) Unregister(slot);
            if (player.Input != null) Destroy(player.Input.gameObject);
            Destroy(player.gameObject);
        }

        // ---------- Сеть ----------

        /// <summary>Перейти в сетевую игру или выйти из неё: локальные игроки и манекены убираются, вход кнопкой выключается.</summary>
        public void SetOnline(bool online)
        {
            if (IsOnline == online) return;
            for (int i = players.Count - 1; i >= 0; i--) Remove(players[i]);
            IsOnline = online;
            inputManager.enabled = !online;
        }

        /// <summary>Хост: создать спичку игрока, подключившегося по сети (clientId — владелец).</summary>
        public Player AddNetworkPlayer(ulong clientId)
        {
            if (!IsOnline || slots.Count >= MaxPlayers) return null;
            var player = CreateAvatar("Игрок " + clientId);
            if (player == null) return null;
            player.IsNetworkPlayer = true;
            player.NetworkOwner = clientId;
            if (Register(player) == null) { Destroy(player.gameObject); return null; }
            SpawnOnNetwork(player, clientId);
            return player;
        }

        /// <summary>Хост: игрок отключился — убрать его спичку.</summary>
        public void RemoveNetworkPlayer(Player player)
        {
            if (player != null) Remove(player);
        }

        private void SpawnOnNetwork(Player player, ulong ownerId)
        {
            if (NetworkSpawner == null || !NetworkSpawner(player.gameObject, ownerId))
                Debug.LogWarning("[PushPals] Спичка создана, но не появилась по сети: нет сетевого модуля.", player);
        }

        /// <summary>Клиент: спичка пришла по сети — назначить номер и цвет (появление и падения считает хост).</summary>
        public void AttachRemoteAvatar(Player player, int index)
        {
            player.AssignFromNetwork(index, ColorFor(index));
            if (!remotes.Contains(player)) remotes.Add(player);
            remotes.Sort((a, b) => a.Index.CompareTo(b.Index));
            var group = player.GetComponent<UnityEngine.Rendering.SortingGroup>();
            if (group == null) group = player.gameObject.AddComponent<UnityEngine.Rendering.SortingGroup>();
            group.sortingOrder = index;
        }

        private Slot Register(Player player)
        {
            if (slots.Count >= MaxPlayers) return null;

            // Свободный номер — самый маленький (вышел второй — следующий вошедший станет вторым)
            int index = 0;
            while (slots.Exists(s => s.Player.Index == index)) index++;
            player.Assign(index, ColorFor(index));
            // Свой порядок отрисовки: части разных игроков не перемешиваются, когда спички в куче
            var group = player.GetComponent<UnityEngine.Rendering.SortingGroup>();
            if (group == null) group = player.gameObject.AddComponent<UnityEngine.Rendering.SortingGroup>();
            group.sortingOrder = index;

            // PlayerInput сообщает о входе раньше, чем проснулись остальные компоненты спички:
            // тогда тела ещё нет — ставим сам объект на место появления, тело построится уже там
            var body = player.Ragdoll.Body;
            bool built = body != null && body.IsBuilt;
            // Стал призраком — друзья разжимают руки (призрака не удержать)
            player.Ragdoll.GhostChanged += ghost => { if (ghost) ReleaseFromOthers(player); };
            var slot = new Slot { Player = player, NeedsSpawn = !built };
            if (!built) player.transform.position = FindSpawn(player);
            slots.Add(slot);
            RefreshList();
            if (built) Respawn(player);
            PlayerJoined?.Invoke(player);
            return slot;
        }

        private void Unregister(Slot slot)
        {
            slots.Remove(slot);
            var player = slot.Player;
            if (player != null)
            {
                if (player.Input != null)
                {
                    if (slot.OnLost != null) player.Input.onDeviceLost -= slot.OnLost;
                    if (slot.OnRegained != null) player.Input.onDeviceRegained -= slot.OnRegained;
                }
                // Друзья разжимают руки, а не висят на исчезнувшем теле
                ReleaseFromOthers(player);
            }
            RefreshList();
            PlayerLeft?.Invoke(player);
        }

        private void RefreshList()
        {
            players.Clear();
            foreach (var s in slots) players.Add(s.Player);
            players.Sort((a, b) => a.Index.CompareTo(b.Index));
            ReassignMatches();
        }

        /// <summary>Сколько игроков — столько спичек раздаём заново (MatchAssignment); уровень подстраивается.</summary>
        public event Action<int> PlayerCountChanged;

        // Раздать спички по числу игроков; спичка в игре у каждого остаётся, если она всё ещё его
        private void ReassignMatches()
        {
            var current = new List<IList<PushPals.Abilities.MatchKind>>();
            var active = new List<PushPals.Abilities.MatchKind?>();
            foreach (var p in players)
            {
                var b = p != null ? p.GetComponent<PushPals.Abilities.Backpack>() : null;
                current.Add(b != null && b.Count > 0 ? (IList<PushPals.Abilities.MatchKind>)b.Kinds : null);
                active.Add(b != null && b.Active != null ? (PushPals.Abilities.MatchKind?)b.Active.kind : null);
            }
            var requests = new List<IList<PushPals.Abilities.MatchKind>>();
            foreach (var p in players) requests.Add(WishOf(p));
            var kinds = PushPals.Abilities.MatchAssignment.AssignKeeping(current, active, requests);
            for (int i = 0; i < players.Count; i++)
            {
                if (players[i] == null) continue;
                var backpack = players[i].GetComponent<PushPals.Abilities.Backpack>();
                if (backpack != null) backpack.SetMatches(kinds[i]);
            }
            PlayerCountChanged?.Invoke(players.Count);
        }

        // ---------- Каждый кадр: падение, выход по «Меню», отключённый геймпад ----------

        private bool joiningBlocked;

        private void Update()
        {
            float dt = Time.deltaTime;
            // Открыт экран меню (главное меню, настройки) — новые игроки не входят от нажатий в меню
            bool block = PushPals.UI.UiScreen.BlocksGame;
            if (block != joiningBlocked && inputManager != null)
            {
                joiningBlocked = block;
                if (block) inputManager.DisableJoining();
                else inputManager.EnableJoining();
            }
            UpdateAllGhosts(dt);
            for (int i = slots.Count - 1; i >= 0; i--)
            {
                var slot = slots[i];
                var player = slot.Player;
                if (player == null) { slots.RemoveAt(i); RefreshList(); continue; }

                var body = player.Ragdoll.Body;
                if (body == null) continue;
                if (slot.NeedsSpawn && body.IsBuilt) { slot.NeedsSpawn = false; player.NotifySpawned(); }
                if (!body.IsBuilt) continue;
                ApplyLook(player);
                // Запоминаем, где стояли на земле (не на друге): упав, вернёмся к контрольной точке позади
                if (player.Ragdoll.IsGrounded && RagdollBody.Of(player.Ragdoll.GroundBody) == null) slot.LastSafeX = body.HipPoint.x;
                if (body.HipPoint.y < fallY) Respawn(player, true);

                var input = player.Input;
                if (input == null || !input.enabled) continue;

                var menu = input.actions != null ? input.actions.FindAction("Menu") : null;
                // «Держать Меню — выйти» не срабатывает, пока Esc / Start заняты экраном меню
                slot.MenuHeld = menu != null && menu.IsPressed() && !block ? slot.MenuHeld + dt : 0f;
                if (slot.MenuHeld >= leaveHoldTime) { Remove(player); continue; }

                if (slot.LostTime >= 0f)
                {
                    slot.LostTime += dt;
                    if (slot.LostTime >= deviceLostTimeout) Remove(player);
                }
            }
        }

        // ---------- Призраки и возрождение ----------

        [Header("Призраки")]
        [Tooltip("Все стали призраками — через столько секунд команда возрождается у последнего коробка")]
        [SerializeField] private float allGhostsReviveDelay = 2.5f;
        private float allGhostsTimer;

        /// <summary>Призрак выходит из коробка новой спичкой (свежей, сухой, без огня).</summary>
        public void Revive(Player player, MatchboxCheckpoint box)
        {
            if (player == null || !player.Ragdoll.IsGhost) return;
            var body = player.Ragdoll.Body;
            player.Ragdoll.SetGhost(false);
            var fire = player.GetComponent<PushPals.Fire.MatchFire>();
            if (fire != null) fire.ResetFresh();
            var backpack = player.GetComponent<PushPals.Abilities.Backpack>();
            if (backpack != null) backpack.RefreshAll(); // из коробка выходят все спички игрока целыми
            var grab = player.GetComponent<RagdollGrab>();
            if (grab != null) grab.ReleaseAll();
            Vector2 feet;
            Vector2 at = box != null ? box.SpawnPosition : (SpawnPoint.All.Count > 0 ? (Vector2)SpawnPoint.All[0].transform.position : (Vector2)transform.position);
            if (!TryPlaceNear(at, player, out feet)) feet = at;
            body.Teleport(feet);
            PushPals.Fire.Puffs.Emit(feet + Vector2.up, 12, new Color(1f, 0.95f, 0.7f), 0.12f, Vector2.up, 1.5f, 0.6f, 1f, 0.4f, 40);
            player.NotifySpawned();
        }

        private bool TryPlaceNear(Vector2 at, Player who, out Vector2 feet)
        {
            for (int k = 0; k <= 4; k++)
                foreach (float side in new[] { 1f, -1f })
                    if (TryPlace(at + Vector2.right * (side * k * spawnSpacing), who, out feet)) return true;
            feet = at;
            return false;
        }

        // Все сгорели — команда не застрянет: возрождаемся у последнего открытого коробка
        private void UpdateAllGhosts(float dt)
        {
            bool allGhosts = players.Count > 0;
            foreach (var p in players) if (p != null && !p.Ragdoll.IsGhost) { allGhosts = false; break; }
            allGhostsTimer = allGhosts ? allGhostsTimer + dt : 0f;
            if (allGhostsTimer < allGhostsReviveDelay) return;
            allGhostsTimer = 0f;
            foreach (var p in new List<Player>(players)) Revive(p, MatchboxCheckpoint.Active);
        }

        // ---------- Появление ----------

        /// <summary>Поставить игрока рядом с друзьями (или на точку появления), на свободное место.</summary>
        public void Respawn(Player player)
        {
            Respawn(player, false);
        }

        /// <summary>
        /// Вернуть игрока. Упал (fell) — на свою последнюю контрольную точку (SpawnPoint позади места, где стоял),
        /// иначе пропасть можно было бы «перепрыгнуть», упав к другу на другой стороне. Вход — рядом с друзьями.
        /// </summary>
        public void Respawn(Player player, bool fell)
        {
            var body = player.Ragdoll.Body;
            if (body == null || !body.IsBuilt) return;
            ReleaseFromOthers(player);
            var grab = player.GetComponent<RagdollGrab>();
            if (grab != null) grab.ReleaseAll();

            Vector2 feet;
            var slot = slots.Find(s => s.Player == player);
            if (fell && slot != null && TryCheckpoint(player, slot.LastSafeX, out feet)) body.Teleport(feet);
            else body.Teleport(FindSpawn(player));
            player.NotifySpawned();
            if (fell && PlayerFell != null) PlayerFell(player);
        }

        /// <summary>Игрок упал (в пропасть) и вернулся на контрольную точку — для задачи предателя.</summary>
        public event Action<Player> PlayerFell;

        private void ReleaseFromOthers(Player player)
        {
            foreach (var other in players)
            {
                if (other == null || other == player || player.Ragdoll.Body == null) continue;
                var grab = other.GetComponent<RagdollGrab>();
                if (grab != null) grab.ReleaseFriend(player.Ragdoll.Body);
            }
        }

        private Vector2 FindSpawn(Player who)
        {
            // 1) Рядом с другом, который стоит на земле: справа и слева от него по очереди
            foreach (var other in players)
            {
                if (other == null || other == who || other.Ragdoll.Body == null || !other.Ragdoll.Body.IsBuilt || !other.Ragdoll.IsGrounded) continue;
                var otherBody = other.Ragdoll.Body;
                Vector2 near = otherBody.HipPoint - Vector2.up * other.Ragdoll.Profile.LegLength;
                for (int k = 1; k <= 4; k++)
                {
                    foreach (float side in new[] { 1f, -1f })
                    {
                        Vector2 feet;
                        if (TryPlace(near + Vector2.right * (side * k * spawnSpacing), who, out feet)) return feet;
                    }
                }
            }

            // 2) Точки появления уровня по порядку (и рядом с ними)
            foreach (var point in SpawnPoint.All)
            {
                for (int k = 0; k <= 3; k++)
                {
                    foreach (float side in new[] { 1f, -1f })
                    {
                        Vector2 feet;
                        if (TryPlace((Vector2)point.transform.position + Vector2.right * (side * k * spawnSpacing), who, out feet)) return feet;
                    }
                }
            }

            // 3) Запасной вариант — там, где стоит менеджер
            return transform.position;
        }

        private static bool Owns(Player who, Collider2D collider)
        {
            var body = who.Ragdoll.Body;
            return body != null && body.Owns(collider);
        }

        // Самая дальняя точка появления не правее места, где игрок последний раз стоял
        private bool TryCheckpoint(Player who, float lastSafeX, out Vector2 feet)
        {
            feet = Vector2.zero;
            SpawnPoint best = null;
            foreach (var point in SpawnPoint.All)
            {
                float x = point.transform.position.x;
                if (x > lastSafeX + 0.5f) continue;
                if (best == null || x > best.transform.position.x) best = point;
            }
            if (best == null) return false;
            for (int k = 0; k <= 3; k++)
                foreach (float side in new[] { 1f, -1f })
                    if (TryPlace((Vector2)best.transform.position + Vector2.right * (side * k * spawnSpacing), who, out feet)) return true;
            return false;
        }

        // Найти пол под точкой (ищем сверху вниз) и проверить, что там свободно
        private bool TryPlace(Vector2 around, Player who, out Vector2 feet)
        {
            feet = around;
            Vector2 from = around + Vector2.up * 2f;
            var groundFilter = new ContactFilter2D { useTriggers = false };
            groundFilter.SetLayerMask(groundMask);
            int count = Physics2D.Raycast(from, Vector2.down, groundFilter, groundHits, 4f);
            float best = float.MaxValue;
            bool found = false;
            for (int i = 0; i < count; i++)
            {
                var hit = groundHits[i];
                if (hit.collider.isTrigger || Owns(who, hit.collider) || hit.distance <= 0f) continue;
                if (RagdollBody.Of(hit.rigidbody) != null) continue; // на голову другу не ставим
                if (hit.distance < best) { best = hit.distance; feet = hit.point + Vector2.up * 0.05f; found = true; }
            }
            if (!found) return false;

            Vector2 center = feet + Vector2.up * (spawnSize.y * 0.5f + 0.05f);
            var blockFilter = new ContactFilter2D { useTriggers = false };
            blockFilter.SetLayerMask(blockMask);
            int n = Physics2D.OverlapBox(center, spawnSize, 0f, blockFilter, blockers);
            for (int i = 0; i < n; i++)
            {
                if (blockers[i].isTrigger || Owns(who, blockers[i])) continue;
                return false;
            }
            return true;
        }
    }
}
