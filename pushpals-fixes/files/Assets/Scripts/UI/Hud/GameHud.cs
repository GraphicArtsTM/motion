using System.Collections.Generic;
using PushPals.Fire;
using PushPals.Input;
using PushPals.Level;
using PushPals.Players;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Тихий HUD игры (Этап 17.5), живёт между сценами (создаёт GameSystems), рисуется в слое UiRoot.Hud:
    /// над спичкой — полоса горения (только пока горит или огонь кончается) и цветная метка игрока (доступность);
    /// внизу слева — полупрозрачные значки игроков (хост — корона, говорит — «волны»); справа сверху — золотые спички
    /// и время уровня: видны в начале, после находки и при «Заново», потом сами прячутся. Название и цель уровня —
    /// первые секунды. Режимы (UiSettings.Hud): всё / только нужное (значки — только когда говорят, счёт — по событиям) /
    /// без интерфейса. Под экранами меню и обложкой загрузки HUD прячется. Прицел мышью — курсор-прицел
    /// (при чувствительности ≠ 1 — свой прицел, системный курсор заперт).
    /// </summary>
    public class GameHud : MonoBehaviour
    {
        [SerializeField] private float introTime = 5f;
        [SerializeField] private float eventShowTime = 4f;
        [SerializeField] private float markerHeight = 1.05f;
        [Tooltip("Насколько выше поднимается метка, пока видна полоса горения (м)")]
        [SerializeField] private float markerAboveBar = 0.4f;

        private class PlayerView
        {
            public Player player;
            public BurnBar burn;
            public Image marker;
            public PlayerBadge badge;
            public Image badgeRibbon;
            public CanvasGroup badgeGroup;
            public MatchFire fire;
            public PushPals.Abilities.Backpack backpack;
            public PushPals.Network.NetworkVoice voice;
        }

        private readonly Dictionary<Player, PlayerView> views = new Dictionary<Player, PlayerView>();
        private readonly List<Player> gone = new List<Player>();
        private readonly HashSet<Player> visible = new HashSet<Player>();
        private RectTransform world, safe, badges;
        private CanvasGroup group;
        private CollectibleCounter counter;
        private CanvasGroup levelInfo, intro, restart;
        private TextMeshProUGUI timer, introTitle, restartText;
        private UiCard introGoal;
        private Image crosshair;
        private float showInfoUntil;
        private int lastGolden = -1;
        private LevelRun lastRun;
        private static Sprite triangle;

        public static void Create(GameObject host) => host.AddComponent<GameHud>();

        private void Start() => Build();

        private void Build()
        {
            var root = UiRoot.Instance;
            var container = UiFactory.Rect(root.Hud, "Game HUD");
            UiRoot.Stretch(container);
            group = container.gameObject.AddComponent<CanvasGroup>();
            group.blocksRaycasts = false;
            group.interactable = false;
            world = UiFactory.Rect(container, "World");      // над спичками — во весь экран
            UiRoot.Stretch(world);
            safe = UiFactory.Rect(container, "Safe");        // углы — в безопасной зоне 16:9
            UiRoot.Stretch(safe);

            // Значки игроков внизу слева
            badges = UiFactory.Rect(safe, "Badges");
            badges.anchorMin = badges.anchorMax = Vector2.zero;
            badges.pivot = Vector2.zero;
            badges.anchoredPosition = new Vector2(24f, 20f);
            badges.sizeDelta = new Vector2(1200f, 90f);
            var layout = badges.gameObject.AddComponent<HorizontalLayoutGroup>();
            layout.spacing = 10f;
            layout.childAlignment = TextAnchor.LowerLeft;
            layout.childControlWidth = layout.childControlHeight = false;
            layout.childForceExpandWidth = layout.childForceExpandHeight = false;

            // Золотые спички и время — справа сверху
            var info = UiFactory.Rect(safe, "Level Info");
            info.anchorMin = info.anchorMax = new Vector2(1f, 1f);
            info.pivot = new Vector2(1f, 1f);
            info.anchoredPosition = new Vector2(-24f, -20f);
            info.sizeDelta = new Vector2(400f, 100f);
            levelInfo = info.gameObject.AddComponent<CanvasGroup>();
            counter = UiPrefabs.Spawn<CollectibleCounter>("CollectibleCounter", info);
            var crt = (RectTransform)counter.transform;
            crt.anchorMin = crt.anchorMax = new Vector2(1f, 1f);
            crt.pivot = new Vector2(1f, 1f);
            crt.anchoredPosition = Vector2.zero;
            crt.localScale = Vector3.one * 0.85f;
            var plate = UiFactory.Image(info, "hud_timer_plate", false, "Timer Plate");
            UiFactory.Place(plate.rectTransform, new Vector2(1f, 1f), new Vector2(92f, 92f), new Vector2(-270f, -38f));
            timer = UiFactory.Text(plate.transform, "", 24f, UiTheme.Current.ink, false);
            UiRoot.Stretch(timer.rectTransform);
            timer.fontStyle = FontStyles.Bold;

            // Название и цель уровня — сверху по центру
            var introRt = UiFactory.Rect(safe, "Intro");
            UiFactory.Place(introRt, new Vector2(0.5f, 1f), new Vector2(1100f, 200f), new Vector2(0f, -150f));
            intro = introRt.gameObject.AddComponent<CanvasGroup>();
            var banner = UiFactory.Image(introRt, "banner_header", true, "Banner");
            UiFactory.Place(banner.rectTransform, new Vector2(0.5f, 1f), new Vector2(760f, 120f), new Vector2(0f, -60f));
            introTitle = UiFactory.Text(banner.transform, "", 44f, UiTheme.Current.inkLight, true);
            UiRoot.Stretch(introTitle.rectTransform);
            introTitle.rectTransform.offsetMin = new Vector2(100f, 24f);
            introTitle.rectTransform.offsetMax = new Vector2(-100f, -10f);
            introTitle.enableAutoSizing = true;
            introTitle.fontSizeMin = 22f;
            introTitle.fontSizeMax = 44f;
            // Цель — на бумажке: белый текст терялся на светлых уровнях
            introGoal = UiCard.Create(introRt, 900f, false);
            var goalRt = introGoal.Rect;
            goalRt.anchorMin = goalRt.anchorMax = new Vector2(0.5f, 1f);
            goalRt.pivot = new Vector2(0.5f, 1f);
            goalRt.anchoredPosition = new Vector2(0f, -130f);

            // «Заново» — снизу справа
            var rs = UiFactory.Rect(safe, "Restart");
            rs.anchorMin = rs.anchorMax = new Vector2(1f, 0f);
            rs.pivot = new Vector2(1f, 0f);
            rs.anchoredPosition = new Vector2(-24f, 24f);
            rs.sizeDelta = new Vector2(520f, 60f);
            restart = rs.gameObject.AddComponent<CanvasGroup>();
            var glyph = UiFactory.Image(rs, "keyboard_r", false, "Glyph");
            UiFactory.Place(glyph.rectTransform, new Vector2(1f, 0.5f), new Vector2(56f, 56f), new Vector2(-28f, 0f));
            var g = glyph.gameObject.AddComponent<InputGlyph>();
            g.SetAction(UiTheme.Current.controls, "VoteRestart");
            restartText = UiFactory.Text(rs, "", 28f, UiTheme.Current.inkLight, false);
            restartText.alignment = TextAlignmentOptions.MidlineRight;
            UiRoot.Stretch(restartText.rectTransform);
            restartText.rectTransform.offsetMax = new Vector2(-70f, 0f);
            restartText.gameObject.AddComponent<Shadow>().effectColor = new Color(0f, 0f, 0f, 0.7f);

            // Свой прицел (при чувствительности мыши ≠ 1)
            crosshair = UiFactory.Image(container, "cur_aim", false, "Crosshair");
            crosshair.rectTransform.anchorMin = crosshair.rectTransform.anchorMax = Vector2.zero;
            crosshair.rectTransform.sizeDelta = new Vector2(48f, 48f);
            crosshair.enabled = false;

            if (triangle == null) triangle = MakeTriangle();
            levelInfo.alpha = intro.alpha = restart.alpha = 0f;
        }

        private void Update()
        {
            if (group == null) return;
            var manager = PlayerManager.Instance;
            bool blocked = UiScreen.BlocksGame || MatchboxSleeve.Visible || MainMenuScreen.Showing;
            bool on = !blocked && manager != null && UiSettings.Hud != UiSettings.HudMode.Off;
            group.alpha = Mathf.MoveTowards(group.alpha, on ? 1f : 0f, Time.unscaledDeltaTime * 6f);
            var s = UiRoot.Instance.Safe; // углы — как у безопасной зоны 16:9
            safe.anchorMin = s.anchorMin;
            safe.anchorMax = s.anchorMax;
            UpdateCursor(blocked);
            SyncPlayers(manager);
            if (group.alpha <= 0f) return;
            foreach (var v in views.Values) UpdatePlayer(v);
            UpdateLevel();
        }

        // ---------- Игроки ----------

        private void SyncPlayers(PlayerManager manager)
        {
            gone.Clear();
            visible.Clear();
            if (manager != null) foreach (var p in manager.Visible) if (p != null) visible.Add(p);
            foreach (var p in views.Keys)
                if (p == null || !visible.Contains(p)) gone.Add(p);
            foreach (var p in gone)
            {
                var v = views[p];
                if (v.burn != null) Destroy(v.burn.gameObject);
                if (v.marker != null) Destroy(v.marker.gameObject);
                if (v.badge != null) Destroy(v.badge.gameObject);
                views.Remove(p);
            }
            if (manager == null) return;
            foreach (var p in manager.Visible)
                if (p != null && !views.ContainsKey(p)) views[p] = MakeView(p);
        }

        private PlayerView MakeView(Player p)
        {
            var v = new PlayerView { player = p, fire = p.GetComponent<MatchFire>(), backpack = p.GetComponent<PushPals.Abilities.Backpack>(), voice = p.GetComponent<PushPals.Network.NetworkVoice>() };
            v.burn = UiPrefabs.Spawn<BurnBar>("BurnBar", world);
            var marker = UiFactory.Rect(world, "Marker").gameObject.AddComponent<Image>();
            marker.sprite = triangle;
            marker.raycastTarget = false;
            marker.rectTransform.anchorMin = marker.rectTransform.anchorMax = Vector2.zero;
            marker.rectTransform.sizeDelta = new Vector2(26f, 20f);
            v.marker = marker;
            v.badge = UiPrefabs.Spawn<PlayerBadge>("PlayerBadge", badges);
            ((RectTransform)v.badge.transform).localScale = Vector3.one * 0.7f;
            // Треугольник цветом ленточки над значком — как метка над головой (цвет значка — это цвет головки, не игрока)
            var ribbon = UiFactory.Rect((RectTransform)v.badge.transform, "Ribbon").gameObject.AddComponent<Image>();
            ribbon.sprite = triangle;
            ribbon.raycastTarget = false;
            UiFactory.Place(ribbon.rectTransform, new Vector2(0f, 1f), new Vector2(34f, 26f), new Vector2(50f, 14f));
            v.badgeRibbon = ribbon;
            v.badgeGroup = v.badge.GetComponent<CanvasGroup>();
            return v;
        }

        private void UpdatePlayer(PlayerView v)
        {
            var p = v.player;
            bool built = p.Ragdoll != null && p.Ragdoll.Body != null && p.Ragdoll.Body.IsBuilt;
            bool ghost = built && p.Ragdoll.IsGhost;
            var head = built ? p.Ragdoll.Body.Head.transform : null;
            // Полоса горения (сама прячется, если не горит и огня хватает)
            if (v.burn != null)
            {
                v.burn.SetTarget(head);
                if (v.fire != null) v.burn.Set(ghost ? 1f : 1f - v.fire.BurnFraction, !ghost && v.fire.IsBurning);
            }
            // Метка цветом игрока над головой
            bool marker = built && AccessSettings.PlayerMarkers;
            v.marker.enabled = marker;
            if (marker)
            {
                v.marker.color = new Color(p.Color.r, p.Color.g, p.Color.b, ghost ? 0.4f : 0.9f);
                float lift = v.burn != null ? v.burn.Alpha * markerAboveBar : 0f; // над полосой горения, а не поверх
                Follow(v.marker.rectTransform, head.position + Vector3.up * (markerHeight + lift));
            }
            // Значок: номер, хост, говорит
            // Цвет значка — головка текущей спички (красный Тяжёлый, зелёный Маленький, синий Лёгкий, фиолетовый Магнит)
            var match = v.backpack != null ? v.backpack.Active : null;
            v.badge.Set(match != null ? (int)match.kind : p.Index, Loc.T("wardrobe.player", p.Index + 1));
            v.badgeRibbon.color = p.Color;
            bool speaking = v.voice != null && v.voice.Speaking;
            v.badge.SetSpeaking(speaking);
            v.badge.SetHost(Online.IsActive && p.IsHostAvatar);
            float want = UiSettings.Hud == UiSettings.HudMode.Full || speaking ? 0.8f : 0f;
            v.badgeGroup.alpha = Mathf.MoveTowards(v.badgeGroup.alpha, want, Time.unscaledDeltaTime * 4f);
        }

        // Точка мира → место на HUD
        private void Follow(RectTransform rt, Vector3 at)
        {
            var cam = Camera.main;
            if (cam == null) return;
            Vector3 screen = cam.WorldToScreenPoint(at);
            Vector2 local;
            if (RectTransformUtility.ScreenPointToLocalPointInRectangle((RectTransform)rt.parent, screen, UiRoot.EventCamera, out local))
                rt.anchoredPosition = local - ((RectTransform)rt.parent).rect.min;
        }

        // ---------- Уровень ----------

        private void UpdateLevel()
        {
            var run = LevelRun.Instance;
            float dt = Time.unscaledDeltaTime;
            bool inLevel = run != null && run.Level != null && !run.Finished;
            if (run != lastRun) { lastRun = run; lastGolden = -1; showInfoUntil = Time.unscaledTime + introTime; }
            // Название и цель — первые секунды (после «Поехали!» — не под ним)
            bool showIntro = inLevel && run.Started && run.Elapsed < introTime && !Countdown.Showing;
            if (showIntro)
            {
                int wn = WorldCatalog.NumberOf(run.World);
                introTitle.text = (wn > 0 ? Loc.T("result.world", wn, UiNames.World(wn, run.World)) + " · " : "") + UiNames.Level(run.Level);
                string goalKey = "goal." + run.Level.id;
                introGoal.Set(null, Loc.Has(goalKey) ? Loc.T(goalKey) : run.Level.goal);
            }
            intro.alpha = Mathf.MoveTowards(intro.alpha, showIntro ? 1f : 0f, dt * 2f);
            // Золотые спички и время: всё — всегда, «только нужное» — после событий
            if (inLevel)
            {
                int found = run.GoldenFound;
                if (lastGolden >= 0 && found > lastGolden) showInfoUntil = Time.unscaledTime + eventShowTime;
                lastGolden = found;
                counter.Set(found, run.Level.goldenCount);
                timer.text = LevelDefinition.FormatTime(run.Elapsed);
            }
            bool votes = run != null && run.RestartVotes > 0;
            bool showInfo = inLevel && (UiSettings.Hud == UiSettings.HudMode.Full || Time.unscaledTime < showInfoUntil || votes);
            levelInfo.alpha = Mathf.MoveTowards(levelInfo.alpha, showInfo ? 1f : 0f, dt * 3f);
            // «Заново»: сколько держат
            if (votes) restartText.text = Loc.T("hud.restart", run.RestartVotes, run.RestartTotal);
            restart.alpha = Mathf.MoveTowards(restart.alpha, votes ? 1f : 0f, dt * 5f);
        }

        // ---------- Прицел мышью ----------

        private void UpdateCursor(bool blocked)
        {
            bool aiming = !blocked && PlayerIntentReader.KeyboardAiming;
            bool virtualAim = aiming && PlayerIntentReader.VirtualAimActive;
            UiRoot.IdleCursor = aiming ? "cur_aim" : "cur_default";
            UiRoot.HideCursor = virtualAim;
            var lockWanted = virtualAim ? CursorLockMode.Locked : CursorLockMode.None;
            if (Cursor.lockState != lockWanted) Cursor.lockState = lockWanted;
            crosshair.enabled = virtualAim; // прицел нужен и в режиме «без интерфейса»
            if (virtualAim)
            {
                var parent = (RectTransform)crosshair.rectTransform.parent;
                Vector2 local;
                if (RectTransformUtility.ScreenPointToLocalPointInRectangle(parent, PlayerIntentReader.VirtualAim, UiRoot.EventCamera, out local))
                    crosshair.rectTransform.anchoredPosition = local - parent.rect.min;
            }
        }

        // Треугольник остриём вниз (метка игрока)
        private static Sprite MakeTriangle()
        {
            const int w = 32, h = 24;
            var tex = new Texture2D(w, h, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp };
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    float half = (y + 0.5f) / h * w * 0.5f; // полуширина на этой высоте (внизу — острие)
                    float d = Mathf.Abs(x + 0.5f - w * 0.5f);
                    float a = Mathf.Clamp01(half - d + 0.5f);
                    bool edge = half - d < 2.5f || y > h - 3;
                    tex.SetPixel(x, y, edge ? new Color(0.25f, 0.15f, 0.07f, a) : new Color(1f, 1f, 1f, a));
                }
            tex.Apply();
            return Sprite.Create(tex, new Rect(0, 0, w, h), new Vector2(0.5f, 0f));
        }
    }
}
