using PushPals.Level;
using PushPals.Players;
using PushPals.Ragdoll;
using PushPals.UI;
using UnityEngine;
using UnityEngine.InputSystem;

namespace PushPals.Input
{
    /// <summary>
    /// Читает Input System (геймпад или клавиатура+мышь) и передаёт намерения рэгдоллу.
    /// Единственное место, где спичка связана с устройствами ввода. Живёт на отдельном объекте
    /// «LocalController» (ввод одного игрока за этим ПК), спичку назначает PlayerManager или сеть.
    /// Ещё здесь: колесо эмоций (держать LB / Q), быстрые эмоции (крестовина, 1–8) и лобби —
    /// у шкафа «боднуть» открывает гардероб этого игрока, у доски — настройки игры (хосту); пока экран открыт, спичка стоит.
    /// </summary>
    [RequireComponent(typeof(PlayerInput))]
    public class PlayerIntentReader : MonoBehaviour
    {
        private const string KeyboardMouseScheme = "KeyboardMouse";

        [SerializeField] private RagdollController ragdoll;

        [Tooltip("Мёртвая зона левого стика")]
        [SerializeField, Range(0f, 1f)] private float moveDeadZone = 0.2f;
        [Tooltip("Насколько отклонить правый стик, чтобы руки потянулись")]
        [SerializeField, Range(0f, 1f)] private float aimDeadZone = 0.35f;
        [Tooltip("Насколько отклонить стик, чтобы выбрать эмоцию на колесе")]
        [SerializeField, Range(0f, 1f)] private float wheelDeadZone = 0.5f;
        [Tooltip("Короткое нажатие Start / Esc (меньше стольких секунд) открывает паузу; держать дольше — уйти из команды")]
        [SerializeField] private float menuTapTime = 0.4f;

        private PlayerInput playerInput;

        /// <summary>Спичка, которой управляет этот ввод (назначается при входе игрока).</summary>
        public RagdollController Target
        {
            get => ragdoll;
            set => ragdoll = value;
        }


        private InputAction move, aim, point, grabLeft, grabRight, jump, headbutt, relax, stiffen, switchMatch, emote, emoteQuick, menuAction, pushToTalk;
        private Vector2 lastStickAim = Vector2.right;

        private bool wheelOpen;
        private int wheelPick;
        private Vector2 lastQuick;
        private float menuPressTime = -1f;
        private string toast;
        private float toastTimer;

        private void Awake()
        {
            if (ragdoll == null) ragdoll = GetComponent<RagdollController>();
            playerInput = GetComponent<PlayerInput>();

            var actions = playerInput.actions;
            ControlBindings.ApplyTo(actions); // переназначенные кнопки из сохранения
            move = actions["Move"];
            aim = actions["Aim"];
            point = actions["Point"];
            grabLeft = actions["GrabLeft"];
            grabRight = actions["GrabRight"];
            jump = actions["Jump"];
            headbutt = actions["Headbutt"];
            relax = actions["Relax"];
            stiffen = actions["Stiffen"];
            switchMatch = actions["SwitchMatch"];
            emote = actions.FindAction("Emote");
            emoteQuick = actions.FindAction("EmoteQuick");
            menuAction = actions.FindAction("Menu");
            pushToTalk = actions.FindAction("PushToTalk");
        }

        private bool UsesKeyboard => playerInput.currentControlScheme == KeyboardMouseScheme;

        // Простое управление (доступность): нажал — рука держит, нажал ещё раз — отпустила
        private bool heldLeft, heldRight;

        private static bool Grab(InputAction action, ref bool held)
        {
            if (!AccessSettings.SimpleControls) { held = false; return action.IsPressed(); }
            if (action.WasPressedThisFrame()) held = !held;
            return held;
        }

        private void Update()
        {
            if (ragdoll == null || !ragdoll.Body.IsBuilt) return;
            if (toastTimer > 0f) toastTimer -= Time.unscaledDeltaTime;
            // Голос по сети: «говорить, пока держу» (V / L3)
            if (pushToTalk != null) VoiceSettings.PushToTalkHeld = pushToTalk.IsPressed();

            // Открыт экран меню (настройки, коллекция…) — кнопки у него, спичка стоит
            if (PushPals.UI.UiScreen.BlocksGame)
            {
                ragdoll.SetIntent(new RagdollIntent());
                return;
            }

            var intent = new RagdollIntent
            {
                Move = ApplyDeadZone(move.ReadValue<Vector2>(), moveDeadZone),
                GrabLeft = Grab(grabLeft, ref heldLeft),
                GrabRight = Grab(grabRight, ref heldRight),
                JumpPressed = jump.WasPressedThisFrame(),
                JumpHeld = jump.IsPressed(),
                HeadbuttPressed = headbutt.WasPressedThisFrame(),
                Relax = relax.IsPressed(),
                Stiffen = stiffen.IsPressed(),
                SwitchMatchPressed = switchMatch.WasPressedThisFrame(),
            };

            if (UsesKeyboard) ReadMouseAim(ref intent);
            else ReadStickAim(ref intent);

            ReadEmotes(ref intent);
            ReadLobby(ref intent);
            ragdoll.SetIntent(intent);
        }

        // ---------- Прицел мышью (для HUD) ----------

        /// <summary>Игрок на клавиатуре и мыши целится (в этом или прошлом кадре) — HUD ставит курсор-прицел.</summary>
        public static bool KeyboardAiming => Time.frameCount - keyboardFrame <= 2;
        /// <summary>Чувствительность мыши ≠ 1: свой прицел (точка на экране), системный курсор заперт.</summary>
        public static bool VirtualAimActive { get; private set; }
        public static Vector2 VirtualAim { get; private set; }
        private static int keyboardFrame = -10;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetAimStatics()
        {
            keyboardFrame = -10;
            VirtualAimActive = false;
        }

        // Точка прицела на экране: курсор как есть или свой прицел, который двигается на движение мыши × чувствительность
        private Vector2 AimScreenPoint()
        {
            keyboardFrame = Time.frameCount;
            float sens = AccessSettings.MouseSensitivity;
            bool virtualAim = Mathf.Abs(sens - 1f) > 0.01f;
            var mouse = Mouse.current;
            if (!virtualAim || mouse == null)
            {
                VirtualAimActive = false;
                return point.ReadValue<Vector2>();
            }
            if (!VirtualAimActive) VirtualAim = point.ReadValue<Vector2>(); // начать с того места, где был курсор
            VirtualAimActive = true;
            var p = VirtualAim + mouse.delta.ReadValue() * sens;
            VirtualAim = new Vector2(Mathf.Clamp(p.x, 0f, Screen.width), Mathf.Clamp(p.y, 0f, Screen.height));
            return VirtualAim;
        }

        // Мышь: прицел — от плеч спички к курсору. Руки тянутся только по кнопкам
        private void ReadMouseAim(ref RagdollIntent intent)
        {
            var cam = Camera.main;
            if (cam == null) return;

            Vector3 screen = AimScreenPoint();
            screen.z = -cam.transform.position.z;
            Vector2 world = cam.ScreenToWorldPoint(screen);
            Vector2 dir = world - ragdoll.Body.ShoulderPoint;
            intent.Aim = dir.sqrMagnitude > 0.0001f ? dir.normalized : Vector2.right;
            intent.ArmsFollowAim = false;
        }

        // Стик: отклонён — руки тянутся туда. Отпущен — для кнопок рук берём последнее направление
        private void ReadStickAim(ref RagdollIntent intent)
        {
            Vector2 stick = aim.ReadValue<Vector2>();
            bool active = stick.magnitude > aimDeadZone;
            if (active) lastStickAim = stick.normalized;

            bool anyGrab = intent.GrabLeft || intent.GrabRight;
            intent.ArmsFollowAim = active;
            intent.Aim = active ? lastStickAim : (anyGrab ? DefaultAim(intent) : Vector2.zero);
        }

        // Без прицела руки тянутся вперёд по взгляду
        private Vector2 DefaultAim(RagdollIntent intent)
        {
            if (Mathf.Abs(intent.Move.x) > 0.1f) return new Vector2(Mathf.Sign(intent.Move.x), 0f);
            return new Vector2(ragdoll.Facing, 0f);
        }

        private static Vector2 ApplyDeadZone(Vector2 value, float deadZone)
        {
            return value.magnitude < deadZone ? Vector2.zero : value;
        }

        // ---------- Эмоции ----------

        private void ReadEmotes(ref RagdollIntent intent)
        {
            // Колесо: держим LB / Q, показываем стиком или мышью, отпускаем
            if (emote != null && emote.IsPressed())
            {
                wheelOpen = true;
                Vector2 dir;
                if (UsesKeyboard)
                {
                    Vector2 mouse = VirtualAimActive ? VirtualAim : point.ReadValue<Vector2>(); // курсор заперт — свой прицел
                    Vector2 delta = mouse - HeadScreen();
                    dir = delta.magnitude > 30f ? delta.normalized : Vector2.zero;
                }
                else dir = aim.ReadValue<Vector2>();
                wheelPick = EmoteWheel.Pick(dir, wheelDeadZone);
                // Стик выбирает эмоцию, а не тянет руки
                intent.Aim = Vector2.zero;
                intent.ArmsFollowAim = false;
                intent.GrabLeft = intent.GrabRight = false;
            }
            else if (wheelOpen)
            {
                wheelOpen = false;
                if (wheelPick > 0) intent.Emote = (byte)wheelPick;
                wheelPick = 0;
            }

            // Крестовина: вверх / вправо / вниз / влево — те же места колеса
            if (emoteQuick != null)
            {
                Vector2 q = emoteQuick.ReadValue<Vector2>();
                if (q.magnitude > 0.5f && lastQuick.magnitude <= 0.5f) intent.Emote = (byte)EmoteWheel.Pick(q, 0.5f);
                lastQuick = q;
            }

            // Клавиатура: цифры 1–8
            var kb = Device<Keyboard>();
            if (kb != null)
            {
                for (int i = 0; i < RagdollEmote.Count; i++)
                    if (kb[(Key)((int)Key.Digit1 + i)].wasPressedThisFrame) intent.Emote = (byte)(i + 1);
            }
        }

        // ---------- Лобби: шкаф, доска, настройки хоста ----------

        private void ReadLobby(ref RagdollIntent intent)
        {
            // «Боднуть» у шкафа или доски — открыть меню (а не бодаться)
            if (intent.HeadbuttPressed)
            {
                var station = LobbyStation.Near(ragdoll.Body.Torso.Body.position);
                if (station != null)
                {
                    intent.HeadbuttPressed = false;
                    wheelOpen = false;
                    if (station.Type == LobbyStation.Kind.Wardrobe) OpenWardrobe();
                    else OpenHostMenu();
                }
            }
            // Хост отменяет отсчёт кнопкой B / Shift
            var board = LobbyBoard.Instance;
            if (board != null && board.Counting && IsHost && relax.WasPressedThisFrame()) board.CancelCountdown();
            TrackMenuTap();
        }

        // Короткое нажатие Start / Esc в лобби: хосту — настройки (или отмена отсчёта)
        private void TrackMenuTap()
        {
            if (menuAction == null) return;
            if (menuAction.WasPressedThisFrame()) menuPressTime = Time.unscaledTime;
            if (!menuAction.WasReleasedThisFrame() || menuPressTime < 0f) return;
            bool tap = Time.unscaledTime - menuPressTime < menuTapTime;
            menuPressTime = -1f;
            if (!tap || PushPals.UI.TitleScreen.Showing) return;
            var board = LobbyBoard.Instance;
            if (board != null && board.Counting && IsHost) board.CancelCountdown();
            else PushPals.UI.PauseScreen.Open(IsHost, this); // пауза на наборе интерфейса (Этап 17.5)
        }

        // Доска: настройки игры — хосту, остальным — кто решает
        private void OpenHostMenu()
        {
            if (IsHost) GameSetupScreen.Open();
            else Toast(Loc.T(Online.IsClientView ? "setup.only_host" : "setup.only_first"));
        }

        // Шкаф: гардероб этого игрока (шапка, дерево, какие спички хочет)
        private void OpenWardrobe()
        {
            var player = ragdoll.GetComponent<Player>();
            if (player != null) WardrobeScreen.OpenFor(player);
            else WardrobeScreen.Open();
        }

        // Хост: в сетевой игре — компьютер-хост, за одним ПК — первый вошедший живой игрок
        private bool IsHost
        {
            get
            {
                if (Online.IsClientView) return false;
                if (Online.IsActive) return true;
                var m = PlayerManager.Instance;
                if (m == null) return true;
                foreach (var p in m.Players)
                    if (p != null && p.Input != null) return p.Ragdoll == ragdoll;
                return true;
            }
        }

        private void Toast(string text)
        {
            toast = text;
            toastTimer = 2.2f;
        }

        private T Device<T>() where T : InputDevice
        {
            foreach (var d in playerInput.devices)
                if (d is T t) return t;
            return null;
        }

        // Голова спички на экране (GUI-координаты: y сверху)
        private Vector2 HeadScreen()
        {
            var cam = Camera.main;
            if (cam == null || ragdoll == null || !ragdoll.Body.IsBuilt) return Vector2.zero;
            Vector3 s = cam.WorldToScreenPoint(ragdoll.Body.Head.EndPoint);
            return new Vector2(s.x, s.y);
        }

        private void OnGUI()
        {
            if (PushPals.UI.UiScreen.BlocksGame) return; // открыт экран меню — мировые надписи не поверх него
            if (ragdoll == null || !ragdoll.Body.IsBuilt) return;
            Vector2 head = HeadScreen();
            Vector2 gui = new Vector2(head.x, Screen.height - head.y);
            var player = ragdoll.GetComponent<Player>();
            Color color = player != null ? player.Color : Color.white;

            if (wheelOpen) EmoteWheel.Draw(gui + Vector2.up * 10f, wheelPick, color);
            if (toastTimer > 0f) WorldLabel.Draw((Vector3)ragdoll.Body.Head.EndPoint + Vector3.up * 0.5f, toast, Mathf.Clamp01(toastTimer * 2f), 14, -1, 220f);
        }
    }
}
