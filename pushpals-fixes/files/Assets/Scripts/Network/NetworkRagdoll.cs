using System.Collections.Generic;
using PushPals.Players;
using PushPals.Ragdoll;
using Unity.Netcode;
using UnityEngine;

namespace PushPals.Network
{
    /// <summary>
    /// Спичка в сетевой игре (подход «физику считает хост»):
    /// хост симулирует все спички и 50 раз в секунду рассылает снимок частей тела;
    /// клиенты не считают физику спичек, а плавно показывают снимки с небольшой задержкой (интерполяция).
    /// Владелец спички (игрок на своём ПК) отправляет хосту только намерения — так же, как боты и локальный ввод.
    /// </summary>
    [RequireComponent(typeof(RagdollController))]
    [DefaultExecutionOrder(50)] // после PlayerIntentReader: видим нажатия этого кадра
    public class NetworkRagdoll : NetworkBehaviour, IRemoteChoices
    {
        private const int PartCount = 10;

        [Tooltip("Ввод владельца на его ПК (префаб LocalController: PlayerInput + PlayerIntentReader)")]
        [SerializeField] private GameObject localControllerPrefab;
        [Tooltip("Снимок спички — раз во столько шагов физики (шаг 0,01 с → 2 = 50 раз в секунду)")]
        [SerializeField, Range(1, 10)] private int snapshotEverySteps = 2;
        [Tooltip("Намерения владельца — раз во столько шагов физики (маленькие пакеты, шлём часто)")]
        [SerializeField, Range(1, 10)] private int intentEverySteps = 1;
        [Tooltip("Задержка показа на клиенте подстраивается под сеть: возраст снимков + запас на неровность")]
        [SerializeField, Range(0.01f, 0.2f)] private float minInterpolationDelay = 0.03f;
        [SerializeField, Range(0.05f, 0.5f)] private float maxInterpolationDelay = 0.3f;
        [Tooltip("Сколько «неровностей» сети (разброс прихода снимков) держать в запасе")]
        [SerializeField, Range(0f, 4f)] private float jitterMargin = 2f;

        /// <summary>Номер игрока (цвет ленточки) — назначает хост.</summary>
        public readonly NetworkVariable<int> PlayerIndex = new NetworkVariable<int>(-1);

        /// <summary>Спички в рюкзаке: число и типы (по 2 бита), спичка в игре — номер в списке. Назначает хост.</summary>
        public readonly NetworkVariable<int> Matches = new NetworkVariable<int>(-1);

        /// <summary>Внешний вид из шкафа: шапка + дерево × 16. Назначает хост.</summary>
        public readonly NetworkVariable<int> Look = new NetworkVariable<int>(0);

        /// <summary>Не создавать ввод для владельца (автотест: намерения задаёт бот).</summary>
        public static bool SuppressLocalInput { get; set; }

        private RagdollController controller;
        private RagdollGrab grab;
        private PushPals.Fire.MatchFire fire;
        private RagdollEmote emote;
        private PushPals.Ragdoll.Visual.MatchVisual visual;
        private Player player;
        private GameObject localInput;
        private int stepCounter;

        // Владелец-клиент: счётчики нажатий (пакет с нажатием может потеряться, счётчик — нет)
        private byte jumpCount, headbuttCount, switchCount, emoteCount, emoteId;
        // Хост: последние полученные счётчики
        private byte lastJump, lastHeadbutt, lastSwitch, lastEmote;
        // Номер пакета намерений: владелец растит, хост выкидывает опоздавшие (ненадёжная доставка их переставляет —
        // старый пакет после нового давал лишние прыжок, удар, смену спички или эмоцию)
        private ushort intentSeq, lastIntentSeq;
        private bool hasIntentSeq;

        // Клиент: снимки по времени хоста
        private readonly List<RagdollSnapshot> snapshots = new List<RagdollSnapshot>();
        // Клиент: насколько «старыми» приходят снимки и насколько неровно (для подстройки задержки показа)
        private float averageAge = -1f, jitter;

        /// <summary>Текущая задержка показа на клиенте, с (для отладки и панели сети).</summary>
        public float InterpolationDelay { get; private set; } = 0.1f;

        private void Awake()
        {
            controller = GetComponent<RagdollController>();
            grab = GetComponent<RagdollGrab>();
            player = GetComponent<Player>();
            fire = GetComponent<PushPals.Fire.MatchFire>();
            emote = GetComponent<RagdollEmote>();
            visual = GetComponent<PushPals.Ragdoll.Visual.MatchVisual>();
        }

        public override void OnNetworkSpawn()
        {
            var backpack = GetComponent<PushPals.Abilities.Backpack>();
            if (player != null)
            {
                player.IsHostAvatar = OwnerClientId == NetworkManager.ServerClientId;
                player.NetworkOwner = OwnerClientId; // и на клиенте: чей это ПК (голосование «Предателя»)
            }
            if (IsServer)
            {
                PlayerIndex.Value = player != null ? player.Index : 0;
                if (backpack != null) { backpack.Changed += SendMatches; SendMatches(); }
            }
            else
            {
                // Клиент: физику этой спички считает хост
                controller.SetRemoteView(true);
                SetSimulationComponents(false);
                PlayerIndex.OnValueChanged += OnIndexChanged;
                OnIndexChanged(-1, PlayerIndex.Value);
                Matches.OnValueChanged += OnMatchesChanged;
                OnMatchesChanged(-1, Matches.Value);
                Look.OnValueChanged += OnLookChanged;
                OnLookChanged(0, Look.Value);
            }
            if (IsOwner && !SuppressLocalInput)
            {
                CreateLocalInput();
                // Свой внешний вид из сохранения — хосту (он разошлёт всем)
                var saved = PushPals.Save.SaveSystem.LookOf(0);
                int hat = PushPals.Level.Unlocks.Hat(saved.hat) ? saved.hat : 0, wood = PushPals.Level.Unlocks.Wood(saved.wood) ? saved.wood : 0;
                if (hat != 0 || wood != 0) PlayerChoices.Look(controller, hat, wood);
            }
        }

        public override void OnNetworkDespawn()
        {
            PlayerIndex.OnValueChanged -= OnIndexChanged;
            Matches.OnValueChanged -= OnMatchesChanged;
            Look.OnValueChanged -= OnLookChanged;
            var backpack = GetComponent<PushPals.Abilities.Backpack>();
            if (backpack != null) backpack.Changed -= SendMatches;
            if (localInput != null) Destroy(localInput);
        }

        // Хост: упаковать рюкзак в число (до 4 спичек по 2 бита + число + какая в игре)
        private void SendMatches()
        {
            var backpack = GetComponent<PushPals.Abilities.Backpack>();
            if (!IsServer || backpack == null || backpack.Active == null) return;
            var kinds = backpack.Kinds;
            int code = kinds.Count & 7;
            int activeIndex = kinds.IndexOf(backpack.Active.kind);
            code |= (Mathf.Max(0, activeIndex) & 3) << 3;
            for (int i = 0; i < kinds.Count && i < 4; i++) code |= ((int)kinds[i] & 3) << (5 + i * 2);
            Matches.Value = code;
        }

        // Клиент: распаковать и показать ту же спичку (тело пересобирается)
        private void OnMatchesChanged(int previous, int code)
        {
            if (code < 0) return;
            var backpack = GetComponent<PushPals.Abilities.Backpack>();
            if (backpack == null) return;
            int count = code & 7;
            int activeIndex = (code >> 3) & 3;
            var kinds = new List<PushPals.Abilities.MatchKind>();
            for (int i = 0; i < count; i++) kinds.Add((PushPals.Abilities.MatchKind)((code >> (5 + i * 2)) & 3));
            if (kinds.Count == 0) return;
            backpack.ApplyRemote(kinds[Mathf.Min(activeIndex, kinds.Count - 1)], kinds);
            snapshots.Clear(); // старые снимки — от прежнего тела
        }

        // Клиент: надеть шапку и дерево, которые разослал хост
        private void OnLookChanged(int previous, int look)
        {
            if (visual == null) return;
            visual.Hat = look & 15;
            visual.Wood = (look >> 4) & 15;
        }

        // ---------- Выбор в шкафу (клиент → хост) ----------

        public void SendWish(PushPals.Abilities.MatchKind[] kinds)
        {
            int code = 0;
            if (kinds != null)
            {
                code = kinds.Length & 7;
                for (int i = 0; i < kinds.Length && i < 4; i++) code |= ((int)kinds[i] & 3) << (3 + i * 2);
            }
            SubmitWishRpc(code);
        }

        public void SendLook(int hat, int wood) => SubmitLookRpc((byte)hat, (byte)wood);

        [Rpc(SendTo.Server)]
        private void SubmitWishRpc(int code, RpcParams rpcParams = default)
        {
            if (rpcParams.Receive.SenderClientId != OwnerClientId) return;
            int count = code & 7;
            PushPals.Abilities.MatchKind[] kinds = null;
            if (count > 0)
            {
                kinds = new PushPals.Abilities.MatchKind[count];
                for (int i = 0; i < count; i++) kinds[i] = (PushPals.Abilities.MatchKind)((code >> (3 + i * 2)) & 3);
            }
            var manager = PlayerManager.Instance;
            if (manager != null && player != null) manager.Wish(player, kinds);
        }

        [Rpc(SendTo.Server)]
        private void SubmitLookRpc(byte hat, byte wood, RpcParams rpcParams = default)
        {
            if (rpcParams.Receive.SenderClientId != OwnerClientId) return;
            var manager = PlayerManager.Instance;
            if (manager != null && player != null) manager.SetLook(player, hat, wood);
        }

        private void OnIndexChanged(int previous, int index)
        {
            if (index < 0 || player == null) return;
            var manager = PlayerManager.Instance;
            if (manager != null) manager.AttachRemoteAvatar(player, index);
        }

        // Мышцы, хватание, «боднуть» на клиенте выключены: их считает хост
        private void SetSimulationComponents(bool on)
        {
            if (grab != null) grab.enabled = on;
            var arms = GetComponent<RagdollArms>();
            if (arms != null) arms.enabled = on;
            var headbutt = GetComponent<RagdollHeadbutt>();
            if (headbutt != null) headbutt.enabled = on;
        }

        private void CreateLocalInput()
        {
            if (localControllerPrefab == null) return;
            localInput = Instantiate(localControllerPrefab);
            localInput.name = "LocalController (сеть)";
            var reader = localInput.GetComponent<PushPals.Input.PlayerIntentReader>();
            if (reader != null) reader.Target = controller;
        }

        // ---------- Владелец: нажатия и отправка намерений ----------

        private void Update()
        {
            if (!IsSpawned) return;
            if (IsOwner && !IsServer)
            {
                var intent = controller.Intent;
                if (intent.JumpPressed) jumpCount++;
                if (intent.HeadbuttPressed) headbuttCount++;
                if (intent.SwitchMatchPressed) switchCount++;
                if (intent.Emote != 0) { emoteCount++; emoteId = intent.Emote; }
            }
            if (!IsServer) ShowSnapshots();
        }

        private void FixedUpdate()
        {
            if (!IsSpawned || !controller.Body.IsBuilt) return;
            stepCounter++;

            if (IsServer)
            {
                if (stepCounter % snapshotEverySteps == 0) SnapshotRpc(Capture());
                // Шапка и дерево — всем (NetworkVariable шлёт только при смене)
                if (visual != null)
                {
                    int look = visual.Hat | (visual.Wood << 4);
                    if (Look.Value != look) Look.Value = look;
                }
            }
            else if (IsOwner && stepCounter % intentEverySteps == 0)
            {
                var net = NetIntent.From(controller.Intent, jumpCount, headbuttCount, switchCount);
                net.EmoteCount = emoteCount;
                net.EmoteId = emoteId;
                net.Seq = ++intentSeq;
                SubmitIntentRpc(net);
            }
        }

        [Rpc(SendTo.Server, Delivery = RpcDelivery.Unreliable)]
        private void SubmitIntentRpc(NetIntent data, RpcParams rpcParams = default)
        {
            if (rpcParams.Receive.SenderClientId != OwnerClientId) return; // чужой спичкой управлять нельзя
            if (hasIntentSeq && (short)(data.Seq - lastIntentSeq) <= 0) return; // опоздавший или повтор
            hasIntentSeq = true;
            lastIntentSeq = data.Seq;
            var intent = data.ToIntent();
            intent.JumpPressed = data.JumpCount != lastJump;
            intent.HeadbuttPressed = data.HeadbuttCount != lastHeadbutt;
            intent.SwitchMatchPressed = data.SwitchCount != lastSwitch;
            intent.Emote = data.EmoteCount != lastEmote ? data.EmoteId : (byte)0;
            lastEmote = data.EmoteCount;
            lastJump = data.JumpCount;
            lastHeadbutt = data.HeadbuttCount;
            lastSwitch = data.SwitchCount;
            controller.SetIntent(intent);
        }

        // ---------- Хост: снимок ----------

        private RagdollSnapshot Capture()
        {
            var body = controller.Body;
            var s = new RagdollSnapshot
            {
                Time = NetworkManager.ServerTime.TimeAsFloat,
                Positions = new Vector2[PartCount],
                Angles = new float[PartCount],
                Intent = NetIntent.From(controller.Intent, 0, 0, 0),
            };
            for (int i = 0; i < PartCount; i++)
            {
                var rb = body.Get((BodyPartType)i).Body;
                s.Positions[i] = rb.position;
                s.Angles[i] = rb.rotation;
            }
            s.SetFlag(RagdollSnapshot.Stiff, controller.IsStiff);
            s.SetFlag(RagdollSnapshot.Stunned, controller.IsStunned);
            s.SetFlag(RagdollSnapshot.Grounded, controller.IsGrounded);
            s.SetFlag(RagdollSnapshot.FacingRight, controller.Facing > 0);
            s.SetFlag(RagdollSnapshot.HoldLeft, grab != null && grab.IsHolding(true));
            s.SetFlag(RagdollSnapshot.HoldRight, grab != null && grab.IsHolding(false));
            s.SetFire(fire != null && fire.IsBurning, fire != null && fire.IsWet, controller.IsGhost, fire != null ? fire.BurnFraction : 0f);
            s.Emote = emote != null ? (byte)emote.Current : (byte)0;
            if (visual != null && visual.HatOff)
            {
                s.FireFlags |= RagdollSnapshot.HatOffFlag;
                s.HatPos = visual.LooseHatPosition;
                s.HatAngle = visual.LooseHatAngle;
            }
            return s;
        }

        [Rpc(SendTo.NotServer, Delivery = RpcDelivery.Unreliable)]
        private void SnapshotRpc(RagdollSnapshot snapshot)
        {
            // Подстройка задержки показа: держим её чуть больше обычного «возраста» снимка плюс запас на неровность сети.
            // Хорошая сеть — задержка маленькая (отзывчиво), плохая — растёт (зато без рывков)
            float age = NetworkManager.ServerTime.TimeAsFloat - snapshot.Time;
            if (averageAge < 0f) averageAge = age;
            averageAge = Mathf.Lerp(averageAge, age, 0.05f);
            jitter = Mathf.Lerp(jitter, Mathf.Abs(age - averageAge), 0.05f);
            float interval = snapshotEverySteps * Time.fixedDeltaTime;
            InterpolationDelay = Mathf.Clamp(averageAge + interval + jitterMargin * jitter, minInterpolationDelay, maxInterpolationDelay);

            // Пакеты могут прийти не по порядку — вставляем по времени, старые выкидываем
            int i = snapshots.Count;
            while (i > 0 && snapshots[i - 1].Time > snapshot.Time) i--;
            if (i > 0 && Mathf.Approximately(snapshots[i - 1].Time, snapshot.Time)) return;
            snapshots.Insert(i, snapshot);
            while (snapshots.Count > 32) snapshots.RemoveAt(0);
        }

        // ---------- Клиент: показ с интерполяцией ----------

        private void ShowSnapshots()
        {
            if (snapshots.Count == 0 || !controller.Body.IsBuilt) return;
            float renderTime = NetworkManager.ServerTime.TimeAsFloat - InterpolationDelay;

            // Ищем пару снимков вокруг времени показа; нет более нового — держим последний
            RagdollSnapshot a = snapshots[0], b = snapshots[0];
            for (int i = 0; i < snapshots.Count; i++)
            {
                b = snapshots[i];
                if (b.Time >= renderTime) break;
                a = b;
            }
            float t = b.Time > a.Time ? Mathf.Clamp01((renderTime - a.Time) / (b.Time - a.Time)) : 1f;

            var body = controller.Body;
            for (int i = 0; i < PartCount; i++)
            {
                Vector2 pos = Vector2.Lerp(a.Positions[i], b.Positions[i], t);
                float angle = Mathf.LerpAngle(a.Angles[i], b.Angles[i], t);
                body.SetPartPose((BodyPartType)i, pos, angle);
            }

            var latest = t < 0.5f ? a : b;
            controller.ApplyRemoteState(latest.Intent.ToIntent(), latest.HasFlag(RagdollSnapshot.Stiff), latest.HasFlag(RagdollSnapshot.Stunned),
                latest.HasFlag(RagdollSnapshot.Grounded), latest.HasFlag(RagdollSnapshot.FacingRight) ? 1 : -1, IsOwner);
            if (grab != null) grab.SetRemoteHolding(latest.HasFlag(RagdollSnapshot.HoldLeft), latest.HasFlag(RagdollSnapshot.HoldRight));
            controller.SetGhost(latest.IsGhost);
            if (fire != null) fire.ApplyRemoteState(latest.IsBurning, latest.BurnFraction, latest.IsWet);
            if (emote != null) emote.ApplyRemote(latest.Emote);
            if (visual != null) visual.ApplyRemoteHat((latest.FireFlags & RagdollSnapshot.HatOffFlag) != 0, latest.HatPos, latest.HatAngle);

            // Совсем старые снимки не нужны
            while (snapshots.Count > 2 && snapshots[1].Time < renderTime) snapshots.RemoveAt(0);
        }
    }

    /// <summary>Намерения игрока в сети: кнопки — битами, нажатия — счётчиками.</summary>
    public struct NetIntent : INetworkSerializable
    {
        public Vector2 Move, Aim;
        public byte Buttons;
        public byte JumpCount, HeadbuttCount, SwitchCount;
        /// <summary>Эмоции: счётчик нажатий и номер последней.</summary>
        public byte EmoteCount, EmoteId;
        /// <summary>Номер пакета (владелец → хост), по кругу.</summary>
        public ushort Seq;

        private const byte GrabLeft = 1, GrabRight = 2, JumpHeld = 4, Relax = 8, Stiffen = 16, FollowAim = 32;

        public static NetIntent From(RagdollIntent i, byte jumps, byte headbutts, byte switches)
        {
            byte b = 0;
            if (i.GrabLeft) b |= GrabLeft;
            if (i.GrabRight) b |= GrabRight;
            if (i.JumpHeld) b |= JumpHeld;
            if (i.Relax) b |= Relax;
            if (i.Stiffen) b |= Stiffen;
            if (i.ArmsFollowAim) b |= FollowAim;
            return new NetIntent { Move = i.Move, Aim = i.Aim, Buttons = b, JumpCount = jumps, HeadbuttCount = headbutts, SwitchCount = switches };
        }

        public RagdollIntent ToIntent()
        {
            return new RagdollIntent
            {
                Move = Move,
                Aim = Aim,
                GrabLeft = (Buttons & GrabLeft) != 0,
                GrabRight = (Buttons & GrabRight) != 0,
                JumpHeld = (Buttons & JumpHeld) != 0,
                Relax = (Buttons & Relax) != 0,
                Stiffen = (Buttons & Stiffen) != 0,
                ArmsFollowAim = (Buttons & FollowAim) != 0,
            };
        }

        public void NetworkSerialize<T>(BufferSerializer<T> serializer) where T : IReaderWriter
        {
            serializer.SerializeValue(ref Move);
            serializer.SerializeValue(ref Aim);
            serializer.SerializeValue(ref Buttons);
            serializer.SerializeValue(ref JumpCount);
            serializer.SerializeValue(ref HeadbuttCount);
            serializer.SerializeValue(ref SwitchCount);
            serializer.SerializeValue(ref EmoteCount);
            serializer.SerializeValue(ref EmoteId);
            serializer.SerializeValue(ref Seq);
        }
    }

    /// <summary>Снимок спички: положения и углы 10 частей, флаги состояния и намерения (для лица и рук).</summary>
    public struct RagdollSnapshot : INetworkSerializable
    {
        public const byte Stiff = 1, Stunned = 2, Grounded = 4, FacingRight = 8, HoldLeft = 16, HoldRight = 32;

        public float Time;
        public Vector2[] Positions;
        public float[] Angles;
        public byte Flags;
        public byte FireFlags;  // горит, мокрая, призрак
        public byte Burn;       // сколько сгорело, 0..255
        public byte Emote;      // эмоция (RagdollEmote.Kind), 0 — нет
        public const byte HatOffFlag = 8; // в FireFlags: шапка слетела
        public Vector2 HatPos;  // где лежит слетевшая шапка
        public float HatAngle;
        public NetIntent Intent;

        public bool IsBurning => (FireFlags & 1) != 0;
        public bool IsWet => (FireFlags & 2) != 0;
        public bool IsGhost => (FireFlags & 4) != 0;
        public float BurnFraction => Burn / 255f;

        public void SetFire(bool burning, bool wet, bool ghost, float burnFraction)
        {
            FireFlags = (byte)((burning ? 1 : 0) | (wet ? 2 : 0) | (ghost ? 4 : 0));
            Burn = (byte)Mathf.RoundToInt(Mathf.Clamp01(burnFraction) * 255f);
        }

        public void SetFlag(byte flag, bool on)
        {
            if (on) Flags |= flag;
            else Flags &= (byte)~flag;
        }

        public bool HasFlag(byte flag) => (Flags & flag) != 0;

        public void NetworkSerialize<T>(BufferSerializer<T> serializer) where T : IReaderWriter
        {
            serializer.SerializeValue(ref Time);
            if (serializer.IsReader)
            {
                Positions = new Vector2[10];
                Angles = new float[10];
            }
            for (int i = 0; i < 10; i++)
            {
                serializer.SerializeValue(ref Positions[i]);
                serializer.SerializeValue(ref Angles[i]);
            }
            serializer.SerializeValue(ref Flags);
            serializer.SerializeValue(ref FireFlags);
            serializer.SerializeValue(ref Burn);
            serializer.SerializeValue(ref Emote);
            if ((FireFlags & HatOffFlag) != 0)
            {
                serializer.SerializeValue(ref HatPos);
                serializer.SerializeValue(ref HatAngle);
            }
            serializer.SerializeNetworkSerializable(ref Intent);
        }
    }
}
