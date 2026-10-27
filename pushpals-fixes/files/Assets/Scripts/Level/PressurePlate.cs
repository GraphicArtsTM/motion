using System.Collections.Generic;
using PushPals.Players;
using PushPals.Ragdoll;
using PushPals.Ragdoll.Visual;
using UnityEngine;
using UnityEngine.Events;

namespace PushPals.Level
{
    /// <summary>
    /// Кнопка в полу. Два вида: по весу (тяжёлая кнопка — продавит Тяжёлый или несколько спичек и ящиков вместе)
    /// и «на всех» (нужно, чтобы на ней стояло столько игроков, сколько в команде — задаёт PlayerCountScaler).
    /// Нажата — открывает двери (Door) и зовёт onPressed; отпустили — закрывает (если не «защёлка»).
    /// Позиция — середина верха кнопки (ставить на пол).
    /// </summary>
    public class PressurePlate : MonoBehaviour, INetState
    {
        public enum Mode { Weight, Players }

        [SerializeField] private Mode mode = Mode.Weight;
        [Tooltip("Сколько массы нужно (по весу). Обычная спичка ≈ 3,3, Тяжёлый ≈ 6, ящик ≈ 1")]
        [SerializeField] private float requiredMass = 5.5f;
        [Tooltip("Сколько игроков нужно (режим «на всех» — ставит PlayerCountScaler)")]
        [SerializeField] private int requiredPlayers = 2;
        [SerializeField] private Vector2 size = new Vector2(1.6f, 0.2f);
        [Tooltip("Однажды нажата — так и остаётся")]
        [SerializeField] private bool latch;
        [SerializeField] private List<Door> doors = new List<Door>();
        [SerializeField] private UnityEvent onPressed, onReleased;
        [SerializeField] private Color plate = new Color(0.9f, 0.35f, 0.25f);
        [SerializeField] private Color pressedColor = new Color(0.45f, 0.8f, 0.35f);
        [SerializeField] private Color outline = new Color(0.28f, 0.17f, 0.09f);

        public bool IsPressed { get; private set; }
        public float CurrentMass { get; private set; }
        public int CurrentPlayers { get; private set; }
        public int RequiredPlayers { get => requiredPlayers; set => requiredPlayers = Mathf.Max(1, value); }
        public Mode PlateMode => mode;

        private readonly List<Collider2D> hits = new List<Collider2D>(32);
        private readonly HashSet<Rigidbody2D> counted = new HashSet<Rigidbody2D>();
        private readonly HashSet<RagdollBody> bodies = new HashSet<RagdollBody>();
        private ContactFilter2D filter;
        private SpriteRenderer top;
        private Transform topRoot;
        private float press;

        private void Awake()
        {
            filter = new ContactFilter2D { useTriggers = false };
            filter.SetLayerMask(LayerMask.GetMask("Player", "PlayerArm", "PlayerLeg", "Grabbable", "Metal", "Default"));
            var baseSr = MatchVisual.AddPill(transform, 0.1f, 1f, outline, 1);
            baseSr.size = new Vector2(size.x + 0.3f, 0.12f);
            baseSr.transform.localPosition = new Vector3(0f, -size.y - 0.04f, 0f);
            topRoot = MatchVisual.NewChild(transform, "Top");
            var o = MatchVisual.AddPill(topRoot, 0.1f, 1f, outline, 2); o.size = size + Vector2.one * 0.05f;
            top = MatchVisual.AddPill(topRoot, 0.1f, 1f, plate, 3); top.size = size;
            topRoot.localPosition = new Vector3(0f, -size.y * 0.5f, 0f);
            // Сама кнопка твёрдая (на ней стоят), чуть-чуть ниже — продавливается
            var col = gameObject.AddComponent<BoxCollider2D>();
            col.size = size;
            col.offset = new Vector2(0f, -size.y * 0.5f);
        }

        // Дверь «все кнопки» (requireAll) должна знать о кнопке до первого нажатия
        private void Start()
        {
            foreach (var d in doors) if (d != null) d.Register(this);
        }

        public void WriteNet(System.IO.BinaryWriter w) { w.Write(IsPressed); w.Write(press); }
        public void ReadNet(System.IO.BinaryReader r) { IsPressed = r.ReadBoolean(); press = r.ReadSingle(); }

        private void FixedUpdate()
        {
            // Сетевой клиент: нажата ли — решает хост, у нас только вид
            if (Online.IsClientView) { ShowPress(); return; }

            // Что стоит на кнопке: полоса сразу над ней
            Vector2 center = (Vector2)transform.position + Vector2.up * 0.15f;
            int count = Physics2D.OverlapBox(center, new Vector2(size.x * 0.95f, 0.3f), 0f, filter, hits);
            counted.Clear();
            bodies.Clear();
            float mass = 0f;
            int playersOn = 0;
            for (int i = 0; i < count; i++)
            {
                var rb = hits[i].attachedRigidbody;
                if (rb == null || rb.bodyType != RigidbodyType2D.Dynamic) continue;
                var ragdoll = RagdollBody.Of(rb);
                if (ragdoll != null)
                {
                    if (!bodies.Add(ragdoll)) continue;
                    var controller = ragdoll.GetComponent<RagdollController>();
                    if (controller != null && controller.IsGhost) continue; // призрак ничего не весит
                    mass += ragdoll.TotalMass + StackedMass(controller);
                    if (ragdoll.GetComponent<Player>() != null) playersOn++;
                    continue;
                }
                if (counted.Add(rb)) mass += rb.mass;
            }
            CurrentMass = mass;
            CurrentPlayers = playersOn;

            bool pressed = mode == Mode.Weight ? mass >= requiredMass : playersOn >= requiredPlayers;
            if (latch && IsPressed) pressed = true;
            if (pressed != IsPressed)
            {
                IsPressed = pressed;
                foreach (var d in doors) if (d != null) d.SetOpen(pressed, this);
                if (pressed) onPressed?.Invoke(); else onReleased?.Invoke();
            }

            press = Mathf.MoveTowards(press, IsPressed ? 1f : Mathf.Clamp01(mass / Mathf.Max(0.1f, requiredMass)) * 0.4f, Time.fixedDeltaTime * 4f);
            ShowPress();
        }

        private void ShowPress()
        {
            topRoot.localPosition = new Vector3(0f, -size.y * 0.5f - press * size.y * 0.6f, 0f);
            top.color = IsPressed ? pressedColor : plate;
        }

        // Вес тех, кто стоит на спичке (пирамида на кнопке давит всем весом)
        private static float StackedMass(RagdollController controller)
        {
            if (controller == null) return 0f;
            float g = Mathf.Abs(Physics2D.gravity.y) * controller.Profile.gravityScale;
            return g > 0f ? controller.CarriedLoad / g : 0f;
        }

        private void OnDrawGizmos()
        {
            Gizmos.color = plate;
            Gizmos.DrawWireCube(transform.position + Vector3.down * size.y * 0.5f, size);
        }
    }
}
