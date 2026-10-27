using System.Collections.Generic;
using PushPals.Players;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.SceneManagement;

namespace PushPals.Level
{
    /// <summary>
    /// Прохождение уровня: время, сколько раз команда сгорела, золотые спички. Название и цель в начале, время
    /// и находки — тихий HUD (GameHud), итог — экран LevelResultScreen (Этап 17.5); в конце (вся команда в выходе TeamExit) — итог и переход на следующий уровень мира
    /// с той же командой (PlayerManager.RememberParty). Перезапуск — держать «Заново» (R / Select).
    /// Один на сцену уровня; уровень не хранит ссылок на игроков — берёт их у PlayerManager.
    /// По сети время, сгоревших и конец считает хост (у клиента — из снимка, INetState), переход и перезапуск —
    /// у всех сразу (Online.LoadSceneForAll). «Заново» — голосование: большинство держит кнопку.
    /// </summary>
    public class LevelRun : MonoBehaviour, INetState
    {
        [SerializeField] private LevelDefinition level;
        [SerializeField] private WorldDefinition world;
        [Tooltip("Выход уровня (если пусто — найдётся сам)")]
        [SerializeField] private TeamExit exit;
        [Tooltip("Сколько секунд показывать итог, прежде чем перейти дальше самим")]
        [SerializeField] private float autoContinue = 12f;
        [Tooltip("Сколько секунд держать «Заново»")]
        [SerializeField] private float restartHold = 1.2f;

        public static LevelRun Instance { get; private set; }

        public LevelDefinition Level => level;
        public float Elapsed { get; private set; }
        public int Ghosts { get; private set; }
        public bool Finished { get; private set; }
        /// <summary>Сколько золотых спичек уровня найдено — раньше или сейчас.</summary>
        public int GoldenFound => level != null ? Mathf.Min(LevelProgress.Golden(level.id), level.goldenCount) : 0;
        /// <summary>Сколько найдено впервые в этом прохождении.</summary>
        public int GoldenNew => Mathf.Max(0, GoldenFound - goldenAtStart);
        private int goldenAtStart;

        private bool started;
        private float finishedTime;
        private float restartHeld;
        private bool loading;
        private readonly HashSet<Player> watched = new HashSet<Player>();

        private void Awake()
        {
            Instance = this;
            // Режим «Предатель» (выбран в лобби, игра по сети) — тайные роли и голосование после уровня
            if (GameRules.Mode == GameRules.GameMode.Traitor && Online.IsActive) gameObject.AddComponent<TraitorRound>();
        }
        private void OnDestroy() { if (Instance == this) Instance = null; }

        private int unlocksAtStart;
        private float bestBefore;

        // ---------- Для экранов (HUD, итог) ----------

        public WorldDefinition World => world;
        /// <summary>Уровень начался (кто-то в нём есть) — для заставки с названием.</summary>
        public bool Started => started;
        /// <summary>Лучшее время до этого прохождения (0 — первое).</summary>
        public float BestBefore => bestBefore;
        /// <summary>Что было открыто в шкафу до уровня (Unlocks.Mask) — показать новое.</summary>
        public int UnlocksAtStart => unlocksAtStart;
        /// <summary>Следующий уровень мира (null — мир пройден).</summary>
        public LevelDefinition NextLevel => world != null && level != null ? world.Next(level) : null;
        /// <summary>Сколько секунд до автоперехода (меньше нуля — не идёт).</summary>
        public float ContinueIn => Finished && !loading ? autoContinue - (Time.time - finishedTime) : -1f;
        /// <summary>Можно идти дальше: решает этот ПК (хост или игра без сети), голосование «Предателя» закончено.</summary>
        public bool CanContinue => Finished && !loading && !Online.IsClientView && Time.time - finishedTime > 1f &&
                                   !(TraitorRound.Instance != null && TraitorRound.Instance.BlocksContinue);

        /// <summary>Итог: «Дальше» — следующий уровень (мир пройден — в коробок).</summary>
        public void Continue() { if (CanContinue) LoadNext(); }

        /// <summary>Итог: «Начать заново» — этот же уровень с той же командой.</summary>
        public void Restart()
        {
            if (CanContinue) Load(SceneManager.GetActiveScene().name, level != null ? PushPals.UI.UiNames.Level(level) : "");
        }

        /// <summary>Итог: «В коробок».</summary>
        public void ToLobby() { if (CanContinue && LevelLoader.Exists(LevelLoader.LobbyScene)) Load(LevelLoader.LobbyScene, ""); }

        private void Start()
        {
            if (exit == null) exit = FindAnyObjectByType<TeamExit>();
            unlocksAtStart = Unlocks.Mask;
            goldenAtStart = GoldenFound;
        }

        /// <summary>Сколько людей голосуют «Заново» и сколько всего (для надписи).</summary>
        public int RestartVotes { get; private set; }
        public int RestartTotal { get; private set; }

        private void Update()
        {
            var manager = PlayerManager.Instance;
            if (manager == null) return;
            int localVotes = Online.VoteOverride.HasValue ? (Online.VoteOverride.Value ? 1 : 0) : CountLocal("VoteRestart");

            // Клиент: время, конец и голоса — из снимка хоста; сами только сообщаем свой голос
            if (Online.IsClientView)
            {
                started = true;
                if (Online.SendRestartVote != null) Online.SendRestartVote(localVotes > 0);
                return;
            }

            WatchGhosts(manager);
            if (!Finished)
            {
                // Время идёт, когда в уровне кто-то есть
                if (manager.Players.Count > 0) { started = true; Elapsed += Time.deltaTime; }
                if (exit != null && exit.Completed) Finish();
            }
            else if (TraitorRound.Instance != null && TraitorRound.Instance.BlocksContinue)
                finishedTime = Time.time; // сначала голосование «Предателя», дальше — после раскрытия
            else if (!loading && Time.time - finishedTime > autoContinue)
                LoadNext(); // кнопки «Дальше» / «В коробок» — на экране итога (LevelResultScreen)

            // «Заново» — большинство людей держит кнопку (по сети — люди на всех ПК)
            if (Online.IsActive)
            {
                RestartTotal = Mathf.Max(1, Online.PeopleCount);
                RestartVotes = Mathf.Min(RestartTotal, (localVotes > 0 ? 1 : 0) + Online.RemoteRestartVotes);
            }
            else
            {
                RestartTotal = Mathf.Max(1, CountLocalPeople());
                RestartVotes = Mathf.Min(RestartTotal, localVotes);
            }
            bool majority = RestartVotes * 2 > RestartTotal;
            restartHeld = majority ? restartHeld + Time.deltaTime : 0f;
            if (restartHeld >= restartHold && !loading) Load(SceneManager.GetActiveScene().name, level != null ? PushPals.UI.UiNames.Level(level) : "");
        }

        // ---------- Сеть ----------

        public void WriteNet(System.IO.BinaryWriter w)
        {
            w.Write(Elapsed);
            w.Write((byte)Mathf.Clamp(Ghosts, 0, 255));
            w.Write(Finished);
            w.Write((byte)RestartVotes);
            w.Write((byte)RestartTotal);
        }

        public void ReadNet(System.IO.BinaryReader r)
        {
            Elapsed = r.ReadSingle();
            Ghosts = r.ReadByte();
            bool finished = r.ReadBoolean();
            RestartVotes = r.ReadByte();
            RestartTotal = r.ReadByte();
            // Хост закончил уровень — у клиента тоже итог и прохождение в его прогресс
            if (finished && !Finished) Finish();
        }

        // Каждого игрока считаем: стал призраком — счёт сгоревших (итог, достижение «Ни одной искры зря», «Предатель»)
        private void WatchGhosts(PlayerManager manager)
        {
            foreach (var p in manager.Players)
            {
                if (p == null || watched.Contains(p)) continue;
                watched.Add(p);
                p.Ragdoll.GhostChanged += ghost => { if (ghost && !Finished) Ghosts++; };
            }
        }

        private void Finish()
        {
            Finished = true;
            finishedTime = Time.time;
            bestBefore = level != null ? LevelProgress.BestTime(level.id) : 0f;
            if (level != null)
            {
                LevelProgress.Complete(level.id, Elapsed);
                PushPals.Save.Achievements.LevelFinished(level, Ghosts, Online.IsActive ? Online.PeopleCount : CountLocalPeople());
            }
            // В лобби на доске — уже следующий уровень
            var next = world != null && level != null ? world.Next(level) : null;
            if (next != null) GameRules.LevelId = next.id;
            PushPals.UI.LevelResultScreen.Open(this); // итог (Этап 17.5)
        }

        private void LoadNext()
        {
            var next = world != null && level != null ? world.Next(level) : null;
            // Мир пройден — обратно в коробок-лобби (если его нет в сборке — заново с первого уровня)
            if (next == null && LevelLoader.Exists(LevelLoader.LobbyScene)) { Load(LevelLoader.LobbyScene, ""); return; }
            if (next == null && world != null && world.levels.Count > 0) next = world.levels[0];
            if (next == null || string.IsNullOrEmpty(next.sceneName)) return;
            Load(next.sceneName, PushPals.UI.UiNames.Level(next));
        }

        // Загрузка с названием на обложке-заставке
        private void Load(string scene, string title)
        {
            if (LevelLoader.Load(scene, title)) loading = true;
        }

        // Сколько людей на этом ПК держат кнопку
        private static int CountLocal(string action)
        {
            int n = 0;
            foreach (var input in FindObjectsByType<PlayerInput>(FindObjectsSortMode.None))
            {
                var a = input.actions != null ? input.actions.FindAction(action) : null;
                if (a != null && a.IsPressed()) n++;
            }
            return n;
        }

        // Сколько людей на этом ПК (манекены не голосуют)
        private static int CountLocalPeople() => FindObjectsByType<PlayerInput>(FindObjectsSortMode.None).Length;
    }
}
