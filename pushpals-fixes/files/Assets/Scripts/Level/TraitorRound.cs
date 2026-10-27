using System.Collections.Generic;
using System.IO;
using PushPals.Players;
using UnityEngine;

namespace PushPals.Level
{
    /// <summary>
    /// Режим «Предатель» (Этап 16): в начале уровня хост тайно выбирает одного человека и даёт ему задачу
    /// (чтобы сгорели спички, друзья падали, оглушались или команда задержалась). Роль знает только его ПК.
    /// После уровня все голосуют, кто предатель (в голосовании голос слышно всех), хост раскрывает:
    /// очки — за угадывание и за выполненную задачу (и если не поймали). Только по сети, от 3 людей:
    /// за одним экраном тайну не спрятать. Создаётся LevelRun, когда в лобби выбран этот режим.
    /// </summary>
    public class TraitorRound : MonoBehaviour
    {
        public enum Task { Burn = 0, Falls = 1, Slow = 2, Stuns = 3 }

        private const string RoleChannel = "t_role", ProgressChannel = "t_prog", VoteChannel = "t_vote", ResultChannel = "t_result", EscapeChannel = "t_escape", AskChannel = "t_ask";
        // Клиент без роли переспрашивает хоста так часто (роль могла прийти, пока уровень ещё грузился)
        private const float AskInterval = 1.5f;
        private const int MinPeople = 3;

        [Tooltip("Через сколько секунд после начала уровня раздать роли (все успели загрузиться)")]
        [SerializeField] private float assignDelay = 2f;
        [Tooltip("Сколько секунд ждать голосов после прохождения")]
        [SerializeField] private float voteTime = 30f;
        [SerializeField] private float roleCardTime = 7f;

        public static TraitorRound Instance { get; private set; }

        /// <summary>Сейчас голосование — голос по сети слышно всех, не только рядом.</summary>
        public static bool EveryoneHears => Instance != null && Instance.phase == Phase.Voting;

        // Очки за игру (живут между уровнями; считает хост, всем — в тексте итога)
        private static readonly Dictionary<ulong, int> scores = new Dictionary<ulong, int>();

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStatics() => scores.Clear();

        private enum Phase { Waiting, Playing, Voting, Revealed, Off }
        private Phase phase = Phase.Waiting;

        // Своя роль (на этом ПК)
        private bool roleKnown, isTraitor;
        private Task task;
        private int target, progress;
        private float roleCard;

        // Хост: кто предатель и счётчики
        private ulong traitorId;
        private readonly List<ulong> people = new List<ulong>();
        private readonly Dictionary<ulong, ulong> votes = new Dictionary<ulong, ulong>();
        private int falls, stuns;
        private readonly HashSet<Player> watched = new HashSet<Player>();
        private float clock, progressTimer, voteClock;

        // Голос этого ПК
        private bool voted;
        private float askTimer;
        private string result = "";
        private string note = "";

        public bool IsTraitor => isTraitor;
        public bool RoleKnown => roleKnown;
        public bool Revealed => phase == Phase.Revealed || phase == Phase.Off;
        /// <summary>Пока не раскрыли — дальше не идём (LevelRun ждёт).</summary>
        public bool BlocksContinue => phase == Phase.Voting || (phase == Phase.Playing && LevelRun.Instance != null && LevelRun.Instance.Finished);
        public string Result => result;

        // ---------- Для интерфейса (TraitorHud, экран итога) ----------

        /// <summary>Сейчас можно голосовать или ждём голосов.</summary>
        public bool Voting => !Revealed && LevelRun.Instance != null && LevelRun.Instance.Finished && phase != Phase.Waiting;
        public bool Voted => voted;
        /// <summary>Раскрыто (итог «Предателя» — текст Result).</summary>
        public bool IsRevealed => phase == Phase.Revealed;
        /// <summary>Сколько ещё показывать карточку роли (с).</summary>
        public float RoleCardLeft => roleCard;
        /// <summary>Пояснение («нужно от 3 людей…»; пусто — нет) и сколько уровень уже идёт.</summary>
        public string Note => note;
        public float Clock => clock;
        /// <summary>Тайная задача предателя (текст) и её ход сейчас.</summary>
        public string TaskLine => TaskText(task, target);
        public string ProgressLine => task == Task.Slow ? LevelDefinition.FormatTime(progress) + " / " + LevelDefinition.FormatTime(target) : progress + " / " + target;

        private void Awake()
        {
            Instance = this;
            gameObject.AddComponent<PushPals.UI.TraitorHud>(); // карточка роли и тайная задача (Этап 17.5)
            // Роль, ход задачи, итог и достижение решает только хост: от других ПК не принимаем
            Online.On(RoleChannel, OnRole);
            Online.On(ProgressChannel, (s, d) => { if (Online.FromHost(s) && d.Length >= 2) progress = d[0] | (d[1] << 8); });
            Online.On(VoteChannel, OnVote);
            Online.On(ResultChannel, (s, d) => { if (Online.FromHost(s)) ShowResult(System.Text.Encoding.UTF8.GetString(d)); });
            Online.On(EscapeChannel, (s, d) => { if (Online.FromHost(s)) PushPals.Save.Achievements.Unlock(PushPals.Save.Achievements.TraitorEscape); });
            Online.On(AskChannel, OnAsk);
            var manager = PlayerManager.Instance;
            if (manager != null) manager.PlayerFell += OnFell;
        }

        private void OnDestroy()
        {
            if (Instance == this) Instance = null;
            Online.Off(RoleChannel);
            Online.Off(ProgressChannel);
            Online.Off(VoteChannel);
            Online.Off(ResultChannel);
            Online.Off(EscapeChannel);
            Online.Off(AskChannel);
            var manager = PlayerManager.Instance;
            if (manager != null) manager.PlayerFell -= OnFell;
        }

        // ---------- Люди (по одному на ПК) ----------

        // Номера ПК людей в игре (по их спичкам)
        private static List<ulong> People()
        {
            var list = new List<ulong>();
            var m = PlayerManager.Instance;
            if (m == null) return list;
            foreach (var p in m.Visible)
                if (p != null && !list.Contains(p.NetworkOwner) && (Online.IsClientView || p.IsNetworkPlayer)) list.Add(p.NetworkOwner);
            list.Sort();
            return list;
        }

        private static Player PlayerOf(ulong owner)
        {
            var m = PlayerManager.Instance;
            if (m == null) return null;
            foreach (var p in m.Visible) if (p != null && p.NetworkOwner == owner) return p;
            return null;
        }

        public static string NameOf(ulong owner)
        {
            var p = PlayerOf(owner);
            return p != null ? PushPals.UI.Loc.T("wardrobe.player", p.Index + 1) : PushPals.UI.Loc.T("traitor.gone");
        }

        // ---------- Хост: роли и задача ----------

        private void Update()
        {
            if (roleCard > 0f) roleCard -= Time.deltaTime;
            if (!Online.IsActive) { phase = Phase.Off; return; }
            if (!Online.IsClientView) HostUpdate();
            else AskRole();
        }

        // Клиент: роли всё нет — спросить хоста ещё раз
        private void AskRole()
        {
            if (roleKnown || Revealed || Online.SendToHost == null) return;
            if ((askTimer -= Time.deltaTime) > 0f) return;
            askTimer = AskInterval;
            Online.SendToHost(AskChannel, new byte[0]);
        }

        // Хост: клиент спрашивает свою роль — опоздавший к раздаче становится честным
        private void OnAsk(ulong sender, byte[] d)
        {
            if (Online.IsClientView || (phase != Phase.Playing && phase != Phase.Voting)) return;
            if (!people.Contains(sender))
            {
                if (!People().Contains(sender)) return; // его спички в игре ещё нет
                people.Add(sender);
            }
            SendRole(sender, sender == traitorId);
        }

        private void HostUpdate()
        {
            var run = LevelRun.Instance;
            clock += Time.deltaTime;
            if (phase == Phase.Waiting && clock >= assignDelay) Assign();
            if (phase == Phase.Off) return;
            WatchStuns();

            // Опоздавший — честный (роли уже розданы)
            if (phase == Phase.Playing)
                foreach (var id in People())
                    if (!people.Contains(id)) { people.Add(id); SendRole(id, false); }

            // Прогресс задачи — предателю
            progress = Progress(run);
            if ((progressTimer -= Time.deltaTime) <= 0f && traitorId != Online.LocalClientId)
            {
                progressTimer = 0.5f;
                if (Online.SendToClient != null) Online.SendToClient(traitorId, ProgressChannel, new[] { (byte)(progress & 255), (byte)(progress >> 8) });
            }

            if (phase == Phase.Playing && run != null && run.Finished) { phase = Phase.Voting; voteClock = 0f; }
            if (phase == Phase.Voting)
            {
                voteClock += Time.deltaTime;
                int alive = 0, done = 0;
                foreach (var id in People()) { alive++; if (votes.ContainsKey(id)) done++; }
                if (done >= alive || voteClock >= voteTime) Reveal(run);
            }
        }

        private void Assign()
        {
            people.Clear();
            people.AddRange(People());
            if (people.Count < MinPeople)
            {
                phase = Phase.Off;
                note = PushPals.UI.Loc.T("traitor.need_people", MinPeople);
                return;
            }
            traitorId = people[Random.Range(0, people.Count)];
            task = (Task)Random.Range(0, 4);
            var level = LevelRun.Instance != null ? LevelRun.Instance.Level : null;
            switch (task)
            {
                case Task.Burn: target = 2; break;
                case Task.Falls: target = 3; break;
                case Task.Stuns: target = 3; break;
                default: target = Mathf.RoundToInt((level != null ? level.parTime : 180f) * 1.25f); break;
            }
            foreach (var id in people) SendRole(id, id == traitorId);
            phase = Phase.Playing;
            Debug.Log("[PushPals] Предатель: " + NameOf(traitorId) + ", задача " + task + " " + target);
        }

        private void SendRole(ulong id, bool traitor)
        {
            if (id == Online.LocalClientId) { SetRole(traitor, task, target); return; }
            if (Online.SendToClient == null) return;
            Online.SendToClient(id, RoleChannel, new[] { (byte)(traitor ? 1 : 0), (byte)task, (byte)(target & 255), (byte)(target >> 8) });
        }

        private void OnRole(ulong sender, byte[] d)
        {
            // Повтор (ответ на переспрос пришёл вслед за обычной раздачей) — карточку роли второй раз не показываем
            if (!Online.FromHost(sender) || d.Length < 4 || roleKnown) return;
            SetRole(d[0] == 1, (Task)d[1], d[2] | (d[3] << 8));
            if (phase == Phase.Waiting) phase = Phase.Playing;
        }

        private void SetRole(bool traitor, Task t, int goal)
        {
            roleKnown = true;
            isTraitor = traitor;
            task = t;
            target = goal;
            roleCard = roleCardTime;
            Debug.Log("[PushPals бот] роль: " + (traitor ? "ПРЕДАТЕЛЬ, задача " + t + " " + goal : "честная спичка"));
        }

        // Сколько уже сделано по задаче (хост)
        private int Progress(LevelRun run)
        {
            switch (task)
            {
                case Task.Burn: return run != null ? run.Ghosts : 0;
                case Task.Falls: return falls;
                case Task.Stuns: return stuns;
                default: return run != null ? Mathf.FloorToInt(run.Elapsed) : 0;
            }
        }

        private bool TaskDone(LevelRun run) => task == Task.Slow ? run != null && run.Elapsed > target : Progress(run) >= target;

        private void OnFell(Player p)
        {
            if (p != null && p.NetworkOwner != traitorId) falls++;
        }

        // Оглушения друзей (не самого предателя)
        private void WatchStuns()
        {
            var m = PlayerManager.Instance;
            if (m == null) return;
            foreach (var p in m.Players)
            {
                if (p == null || watched.Contains(p)) continue;
                watched.Add(p);
                var owner = p.NetworkOwner;
                p.Ragdoll.Stunned += () => { if (owner != traitorId && phase == Phase.Playing) stuns++; };
            }
        }

        public static string TaskText(Task t, int goal)
        {
            switch (t)
            {
                case Task.Burn: return PushPals.UI.Loc.T("traitor.task.burn", goal);
                case Task.Falls: return PushPals.UI.Loc.T("traitor.task.falls", goal);
                case Task.Stuns: return PushPals.UI.Loc.T("traitor.task.stuns", goal);
                default: return PushPals.UI.Loc.T("traitor.task.slow", LevelDefinition.FormatTime(goal));
            }
        }

        // ---------- Голосование ----------

        /// <summary>За кого можно голосовать с этого ПК (все, кроме себя).</summary>
        public List<ulong> Candidates
        {
            get
            {
                var list = People();
                list.Remove(Online.LocalClientId);
                return list;
            }
        }

        public bool CanVote => phase != Phase.Off && phase != Phase.Revealed && roleKnown && !voted && LevelRun.Instance != null && LevelRun.Instance.Finished;

        /// <summary>Проголосовать с этого ПК.</summary>
        public void CastVote(ulong suspect)
        {
            if (!CanVote) return;
            voted = true;
            if (Online.IsClientView)
            {
                if (Online.SendToHost != null) Online.SendToHost(VoteChannel, System.BitConverter.GetBytes(suspect));
            }
            else votes[Online.LocalClientId] = suspect;
        }

        private void OnVote(ulong sender, byte[] d)
        {
            if (Online.IsClientView || d.Length < 8 || phase != Phase.Voting) return;
            // Голосуют люди в игре и только за другого человека в игре
            ulong suspect = System.BitConverter.ToUInt64(d, 0);
            var inGame = People();
            if (suspect == sender || !inGame.Contains(sender) || !inGame.Contains(suspect)) return;
            votes[sender] = suspect;
        }


        // ---------- Раскрытие (хост) ----------

        private void Reveal(LevelRun run)
        {
            phase = Phase.Revealed;
            var alive = People();
            bool done = TaskDone(run);
            var sb = new System.Text.StringBuilder();
            // Текст собирает хост на своём языке и рассылает всем (у клиента — как пришло)
            sb.Append(PushPals.UI.Loc.T("traitor.was", NameOf(traitorId))).Append('\n');
            sb.Append(PushPals.UI.Loc.T(done ? "traitor.task_done" : "traitor.task_failed", TaskText(task, target))).Append('\n');

            int honest = 0, correct = 0;
            var guessed = new List<string>();
            foreach (var id in alive)
            {
                if (id == traitorId) continue;
                honest++;
                ulong v;
                if (votes.TryGetValue(id, out v) && v == traitorId) { correct++; guessed.Add(NameOf(id)); Add(id, 1); }
            }
            bool caught = honest > 0 && correct * 2 > honest;
            int traitorPoints = (done ? 2 : 0) + (caught ? 0 : 1);
            Add(traitorId, traitorPoints);
            if (!caught) EscapeAchievement(traitorId);
            sb.Append(guessed.Count > 0 ? PushPals.UI.Loc.T("traitor.guessed", string.Join(", ", guessed.ToArray())) : PushPals.UI.Loc.T("traitor.nobody")).Append('\n');
            sb.Append(PushPals.UI.Loc.T(caught ? "traitor.caught" : "traitor.escaped", traitorPoints)).Append('\n');
            sb.Append(PushPals.UI.Loc.T("traitor.score"));
            foreach (var id in alive) sb.Append("  ").Append(NameOf(id)).Append(" — ").Append(scores.ContainsKey(id) ? scores[id] : 0);
            string text = sb.ToString();
            ShowResult(text);
            if (Online.SendToClient != null)
                foreach (var id in alive) if (id != Online.LocalClientId) Online.SendToClient(id, ResultChannel, System.Text.Encoding.UTF8.GetBytes(text));
        }

        // Достижение «Тихий саботаж» — на ПК предателя (своё сохранение и Steam у каждого свои)
        private static void EscapeAchievement(ulong id)
        {
            if (id == Online.LocalClientId) PushPals.Save.Achievements.Unlock(PushPals.Save.Achievements.TraitorEscape);
            else if (Online.SendToClient != null) Online.SendToClient(id, EscapeChannel, new byte[1]);
        }

        private static void Add(ulong id, int points)
        {
            int s;
            scores.TryGetValue(id, out s);
            scores[id] = s + points;
        }

        private void ShowResult(string text)
        {
            result = text;
            phase = Phase.Revealed;
            Debug.Log("[PushPals бот] итог «Предателя»: " + text.Replace("\n", " | "));
        }
    }
}
