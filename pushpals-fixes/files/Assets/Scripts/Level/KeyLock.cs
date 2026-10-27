using System.Collections.Generic;
using PushPals.Fire;
using PushPals.Ragdoll.Visual;
using UnityEngine;

namespace PushPals.Level
{
    /// <summary>
    /// Замок: поднеси к нему ключ (KeyItem) — ключ входит в скважину, двери открываются насовсем.
    /// Ключ тяжёлый и неудобный: его несут вдвоём или передают через препятствия. Позиция — центр скважины.
    /// </summary>
    public class KeyLock : MonoBehaviour, INetState
    {
        [SerializeField] private List<Door> doors = new List<Door>();
        [Tooltip("Насколько близко поднести ключ")]
        [SerializeField] private float radius = 0.9f;
        [SerializeField] private Color plate = new Color(0.85f, 0.7f, 0.3f);
        [SerializeField] private Color outline = new Color(0.28f, 0.17f, 0.09f);

        public bool IsUnlocked { get; private set; }

        private SpriteRenderer hole;

        private void Awake()
        {
            var o = MatchVisual.AddPill(transform, 0.2f, 1f, outline, 3); o.size = new Vector2(0.75f, 0.95f);
            var f = MatchVisual.AddPill(transform, 0.18f, 1f, plate, 4); f.size = new Vector2(0.68f, 0.88f);
            hole = MatchVisual.AddEllipse(transform, new Vector2(0.22f, 0.22f), outline, 5);
            hole.transform.localPosition = new Vector3(0f, 0.1f, 0f);
            var slot = MatchVisual.AddPill(transform, 0.1f, 0.3f, outline, 5);
            slot.transform.localPosition = new Vector3(0f, -0.1f, 0f);
        }

        // Дверь «все кнопки» (requireAll) должна знать о замке до того, как его откроют
        private void Start()
        {
            foreach (var d in doors) if (d != null) d.Register(this);
        }

        public void WriteNet(System.IO.BinaryWriter w) => w.Write(IsUnlocked);
        public void ReadNet(System.IO.BinaryReader r)
        {
            if (!r.ReadBoolean() || IsUnlocked) return;
            IsUnlocked = true;
            hole.color = new Color(0.4f, 0.85f, 0.35f);
            Puffs.Sparks(transform.position, 20);
        }

        private void FixedUpdate()
        {
            if (IsUnlocked || Online.IsClientView) return;
            foreach (var key in KeyItem.All)
            {
                if (key == null || key.Used) continue;
                if (Vector2.Distance(key.Body.worldCenterOfMass, transform.position) > radius) continue;
                Unlock(key);
                return;
            }
        }

        private void Unlock(KeyItem key)
        {
            IsUnlocked = true;
            key.Use();
            hole.color = new Color(0.4f, 0.85f, 0.35f);
            Puffs.Sparks(transform.position, 20);
            foreach (var door in doors) if (door != null) door.SetOpen(true, this);
        }

        private void OnDrawGizmos()
        {
            Gizmos.color = plate;
            Gizmos.DrawWireSphere(transform.position, radius);
            foreach (var door in doors) if (door != null) Gizmos.DrawLine(transform.position, door.transform.position);
        }
    }
}
