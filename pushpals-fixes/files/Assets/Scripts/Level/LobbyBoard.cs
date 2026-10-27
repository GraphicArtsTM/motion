using PushPals.Ragdoll.Visual;
using UnityEngine;

namespace PushPals.Level
{
    /// <summary>
    /// Доска у выхода из лобби: какой уровень следующий и с какими настройками (их выбирает хост на экране «Настройки игры» — GameSetupScreen).
    /// «Начать» — отсчёт 5 секунд (хост может отменить), потом уровень грузится у всех (по сети решает хост).
    /// Рядом — дверь-выход, светлеет во время отсчёта. По сети клиент получает настройки и отсчёт снимком (INetState).
    /// Позиция — низ середины доски (на полу).
    /// </summary>
    public class LobbyBoard : MonoBehaviour, INetState
    {
        [Tooltip("Миры по порядку: хост выбирает любой уровень любого мира")]
        [SerializeField] private WorldDefinition[] worlds;
        [Tooltip("Отсчёт перед стартом, с")]
        [SerializeField] private float countdownTime = 5f;
        [SerializeField] private Vector2 boardSize = new Vector2(4.6f, 2.5f);
        [Tooltip("Низ доски над полом")]
        [SerializeField] private float boardHeight = 1.3f;
        [SerializeField] private Vector2 doorSize = new Vector2(2f, 3.1f);
        [Tooltip("Середина двери от середины доски по x")]
        [SerializeField] private float doorOffset = 4f;
        [SerializeField] private Color board = new Color(0.55f, 0.38f, 0.24f);
        [SerializeField] private Color paper = new Color(0.98f, 0.94f, 0.82f);
        [SerializeField] private Color frame = new Color(0.45f, 0.3f, 0.18f);
        [SerializeField] private Color inside = new Color(0.25f, 0.18f, 0.12f);
        [SerializeField] private Color ready = new Color(1f, 0.85f, 0.4f);

        public static LobbyBoard Instance { get; private set; }

        /// <summary>Мир, в котором этот уровень (null — ни в каком).</summary>
        public WorldDefinition WorldOf(LevelDefinition level)
        {
            if (worlds != null) foreach (var w in worlds) if (w != null && w.levels.Contains(level)) return w;
            return null;
        }

        /// <summary>«Мир 2 · 1. Шарики» (на текущем языке).</summary>
        public string Title(LevelDefinition level)
        {
            if (level == null) return "—";
            var w = WorldOf(level);
            int wi = w != null ? System.Array.IndexOf(worlds, w) + 1 : 0;
            return (wi > 0 ? PushPals.UI.Loc.T("board.world", wi) + " · " : "") + (w != null ? w.NumberOf(level) + ". " : "") + PushPals.UI.UiNames.Level(level);
        }

        // Все уровни всех миров подряд
        private System.Collections.Generic.List<LevelDefinition> AllLevels()
        {
            var list = new System.Collections.Generic.List<LevelDefinition>();
            if (worlds != null) foreach (var w in worlds) if (w != null) foreach (var l in w.levels) if (l != null) list.Add(l);
            return list;
        }
        /// <summary>Секунд до старта; меньше нуля — отсчёта нет.</summary>
        public float Countdown { get; private set; } = -1f;
        public bool Counting => Countdown >= 0f;

        [Tooltip("За сколько секунд до старта коробок начинает закрываться")]
        [SerializeField] private float sleeveTime = 0.7f;

        private SpriteRenderer doorInside;
        private bool loading, sleeveClosing;
        private static GUIStyle big;
        private static bool introShown;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStatics() { introShown = false; }

        /// <summary>Выбранный уровень (по GameRules.LevelId; нет такого — первый уровень мира).</summary>
        public LevelDefinition Selected
        {
            get
            {
                var all = AllLevels();
                if (all.Count == 0) return null;
                foreach (var l in all) if (l.id == GameRules.LevelId) return l;
                return all[0];
            }
        }

        private void Awake()
        {
            Instance = this;
            // Игра только началась — коробок открывается; вернулись из игры в главное меню — оно снова на столе
            if (PushPals.UI.MainMenuScreen.ConsumeReturn() || !introShown) { introShown = true; PushPals.UI.TitleScreen.Show(); }
            var f = MatchVisual.AddPill(transform, 0.12f, 1f, frame, -9); f.size = boardSize + Vector2.one * 0.2f;
            f.transform.localPosition = new Vector3(0f, boardHeight + boardSize.y * 0.5f, 0f);
            var b = MatchVisual.AddPill(transform, 0.12f, 1f, board, -8); b.size = boardSize;
            b.transform.localPosition = f.transform.localPosition;
            var p = MatchVisual.AddPill(transform, 0.06f, 1f, paper, -7); p.size = boardSize - Vector2.one * 0.5f;
            p.transform.localPosition = f.transform.localPosition;
            // Ножка доски
            var leg = MatchVisual.AddPill(transform, 0.16f, boardHeight, frame, -10);
            leg.transform.localPosition = new Vector3(0f, boardHeight * 0.5f, 0f);

            // Дверь-выход
            var df = MatchVisual.AddPill(transform, 0.14f, 1f, frame, -8); df.size = doorSize + Vector2.one * 0.2f;
            df.transform.localPosition = new Vector3(doorOffset, doorSize.y * 0.5f, 0f);
            doorInside = MatchVisual.AddPill(transform, 0.14f, 1f, inside, -7); doorInside.size = doorSize;
            doorInside.transform.localPosition = df.transform.localPosition;
        }

        private void OnDestroy()
        {
            if (Instance == this) Instance = null;
        }

        /// <summary>Хост: следующий/предыдущий уровень мира.</summary>
        public void Select(int dir)
        {
            var all = AllLevels();
            if (all.Count == 0) return;
            int i = Mathf.Max(0, all.IndexOf(Selected));
            i = (i + dir + all.Count) % all.Count;
            GameRules.LevelId = all[i].id;
            GameRules.NotifyChanged();
        }

        /// <summary>Хост: начать отсчёт (если режим готов).</summary>
        public void StartCountdown()
        {
            if (Online.IsClientView || loading || Selected == null || !GameRules.ModeReady) return;
            Countdown = countdownTime;
        }

        public void CancelCountdown()
        {
            // Коробок уже закрывается — поздно
            if (Online.IsClientView || loading || sleeveClosing) return;
            Countdown = -1f;
        }

        private void FixedUpdate()
        {
            if (!Online.IsClientView && Counting && !loading)
            {
                int before = Mathf.CeilToInt(Countdown);
                Countdown -= Time.fixedDeltaTime;
                if (Mathf.CeilToInt(Countdown) != before && Countdown > 0f) PushPals.Audio.Sfx.Ui("tick", 0.7f);
                if (Countdown <= 0f)
                {
                    var level = Selected;
                    loading = level != null && LevelLoader.Load(level.sceneName);
                    Countdown = loading ? 0f : -1f;
                    if (loading) PushPals.Fire.Puffs.Sparks((Vector2)transform.position + new Vector2(doorOffset, doorSize.y), 30);
                }
            }
            // Перед стартом коробок закрывается (у клиента — по отсчёту из снимка)
            if (Counting && Countdown <= sleeveTime && !sleeveClosing)
            {
                sleeveClosing = true;
                var level = Selected;
                PushPals.UI.MatchboxSleeve.Close(Mathf.Max(0.2f, Countdown), Title(level));
            }
            if (!Counting) sleeveClosing = false;
            // Проём двери светлеет к старту
            float k = Counting ? 1f - Mathf.Clamp01(Countdown / Mathf.Max(0.01f, countdownTime)) : 0f;
            doorInside.color = Color.Lerp(inside, ready, k);
        }

        public void WriteNet(System.IO.BinaryWriter w)
        {
            GameRules.Write(w);
            w.Write(Countdown);
        }

        public void ReadNet(System.IO.BinaryReader r)
        {
            GameRules.Read(r);
            Countdown = r.ReadSingle();
        }

        private void OnGUI()
        {
            if (PushPals.UI.UiScreen.BlocksGame) return; // открыт экран меню — мировые надписи не поверх него
            var level = Selected;
            Vector3 boardTop = transform.position + Vector3.up * (boardHeight + boardSize.y - 0.25f);
            string text;
            int golden = -1, goldenMax = 0;
            if (level == null) text = PushPals.UI.Loc.T("board.none");
            else
            {
                var w = WorldOf(level);
                int wi = w != null ? System.Array.IndexOf(worlds, w) + 1 : 0;
                text = (w != null ? PushPals.UI.UiNames.World(wi, w) + "\n" : "") + PushPals.UI.Loc.T("board.next", Title(level))
                       + (level.tutorial ? " " + PushPals.UI.Loc.T("board.tutorial") : "")
                       + "\n" + GameRules.ModeName(GameRules.Mode) + " · " + PushPals.UI.Loc.T("board.fire", GameRules.BurnName(GameRules.Burn))
                       + (GameRules.FriendSlaps ? "" : " · " + PushPals.UI.Loc.T("board.no_slaps"));
                golden = LevelProgress.Golden(level.id);
                goldenMax = level.goldenCount;
            }
            string code = Online.LobbyCode != null ? Online.LobbyCode() : "";
            if (code.Length > 0) text += "\n" + PushPals.UI.Loc.T("board.code", code);
            // Раньше: «Хост: … или Start / Esc» — но Start / Esc открывает паузу, а настройки — в ней
            if (!Counting) text += "\n" + PushPals.UI.Loc.T("board.hint");
            WorldLabel.Draw(boardTop, text, 1f, 14, golden, 300f, goldenMax);
            WorldLabel.Draw(transform.position + new Vector3(doorOffset, doorSize.y + 0.45f, 0f), PushPals.UI.Loc.T(Counting ? "board.go" : "board.exit"), 1f, 15, -1, 110f);

            // Метка над хостом: кто выбирает уровень
            var manager = PushPals.Players.PlayerManager.Instance;
            var host = manager != null && manager.Visible.Count > 1 ? manager.HostPlayer : null;
            if (host != null && host.Ragdoll.Body.IsBuilt)
                WorldLabel.Draw((Vector3)host.Ragdoll.Body.Head.EndPoint + Vector3.up * 0.75f, PushPals.UI.Loc.T("board.host"), 0.8f, 11, -1, 46f);

            if (!Counting) return;
            // Отсчёт крупно — всем
            if (big == null)
            {
                big = new GUIStyle(GUI.skin.label) { alignment = TextAnchor.MiddleCenter, fontSize = 40, fontStyle = FontStyle.Bold };
                big.normal.textColor = new Color(1f, 0.93f, 0.75f);
            }
            int secs = Mathf.CeilToInt(Mathf.Max(0f, Countdown));
            string line = loading || secs == 0 ? PushPals.UI.Loc.T("board.go") : PushPals.UI.Loc.T("board.start_in", secs);
            var r = new Rect(0f, Screen.height * 0.18f, Screen.width, 60f);
            var shadow = new GUIStyle(big); shadow.normal.textColor = new Color(0.2f, 0.12f, 0.05f, 0.8f);
            GUI.Label(new Rect(r.x + 3f, r.y + 3f, r.width, r.height), line, shadow);
            GUI.Label(r, line, big);
            if (level != null)
            {
                var small = new GUIStyle(big) { fontSize = 18, fontStyle = FontStyle.Normal };
                GUI.Label(new Rect(0f, r.yMax, Screen.width, 30f), Title(level) + (Online.IsClientView ? "" : "   ·   " + PushPals.UI.Loc.T("board.cancel_hint")), small);
            }
        }

        private void OnDrawGizmos()
        {
            Gizmos.color = frame;
            Gizmos.DrawWireCube(transform.position + Vector3.up * (boardHeight + boardSize.y * 0.5f), boardSize);
            Gizmos.DrawWireCube(transform.position + new Vector3(doorOffset, doorSize.y * 0.5f, 0f), doorSize);
        }
    }
}
