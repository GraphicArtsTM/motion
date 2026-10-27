using System.Collections.Generic;
using PushPals.Ragdoll.Visual;
using UnityEngine;

namespace PushPals.Level
{
    /// <summary>
    /// Дверь-задвижка: твёрдая планка, которая уезжает вверх, когда её открывает кнопка (или несколько кнопок —
    /// тогда все должны быть нажаты, если requireAll). Позиция — низ двери.
    /// </summary>
    public class Door : MonoBehaviour, INetState
    {
        [SerializeField] private Vector2 size = new Vector2(0.5f, 3f);
        [Tooltip("На сколько уезжает вверх")]
        [SerializeField] private float lift = 2.9f;
        [SerializeField] private float speed = 3f;
        [Tooltip("Открыть, только когда нажаты все кнопки, что к ней подключены")]
        [SerializeField] private bool requireAll;
        [SerializeField] private Color fill = new Color(0.55f, 0.58f, 0.62f);
        [SerializeField] private Color outline = new Color(0.28f, 0.17f, 0.09f);

        private readonly HashSet<Object> openers = new HashSet<Object>();
        private readonly HashSet<Object> known = new HashSet<Object>();
        private Transform slab;
        private Rigidbody2D rb;
        private float open;

        public bool IsOpen => open > 0.95f;

        private void Awake()
        {
            slab = MatchVisual.NewChild(transform, "Slab");
            slab.localPosition = new Vector3(0f, size.y * 0.5f, 0f);
            rb = slab.gameObject.AddComponent<Rigidbody2D>();
            rb.bodyType = RigidbodyType2D.Kinematic;
            var col = slab.gameObject.AddComponent<BoxCollider2D>();
            col.size = size;
            int ground = LayerMask.NameToLayer("Ground");
            if (ground >= 0) slab.gameObject.layer = ground;
            var o = MatchVisual.AddPill(slab, 0.1f, 1f, outline, 5); o.size = size + Vector2.one * 0.06f;
            var f = MatchVisual.AddPill(slab, 0.1f, 1f, fill, 6); f.size = size;
            for (int i = 0; i < 3; i++)
            {
                var stripe = MatchVisual.AddPill(slab, 0.05f, 1f, fill * 0.8f, 7);
                stripe.size = new Vector2(size.x * 0.7f, 0.06f);
                stripe.transform.localPosition = new Vector3(0f, (i - 1) * size.y * 0.25f, 0f);
            }
        }

        /// <summary>
        /// Кнопка (замок, ленты, свечи) подключена к двери. Для requireAll дверь ждёт все подключённые: раньше
        /// дверь узнавала о кнопке только при её первом нажатии — и открывалась от первой же кнопки.
        /// </summary>
        public void Register(Object source)
        {
            if (source != null) known.Add(source);
        }

        /// <summary>Кнопка source открывает/закрывает дверь.</summary>
        public void SetOpen(bool value, Object source)
        {
            known.Add(source);
            if (value) openers.Add(source); else openers.Remove(source);
        }

        private bool ShouldOpen => requireAll ? openers.Count > 0 && openers.Count == known.Count : openers.Count > 0;

        public void WriteNet(System.IO.BinaryWriter w) => w.Write(open);
        public void ReadNet(System.IO.BinaryReader r) => netOpen = r.ReadSingle();
        private float netOpen;

        private void FixedUpdate()
        {
            // lift < 0 — уходит вниз (люк в полу). Сетевой клиент: насколько открыта — решает хост
            if (Online.IsClientView) open = Mathf.MoveTowards(open, netOpen, Time.fixedDeltaTime * speed * 2f / Mathf.Max(0.1f, Mathf.Abs(lift)));
            else open = Mathf.MoveTowards(open, ShouldOpen ? 1f : 0f, Time.fixedDeltaTime * speed / Mathf.Max(0.1f, Mathf.Abs(lift)));
            Vector2 target = (Vector2)transform.position + Vector2.up * (size.y * 0.5f + lift * open);
            rb.MovePosition(target);
        }

        private void OnDrawGizmos()
        {
            Gizmos.color = fill;
            Gizmos.DrawWireCube(transform.position + Vector3.up * size.y * 0.5f, size);
        }
    }
}
