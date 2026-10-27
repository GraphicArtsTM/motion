using UnityEngine;

namespace PushPals.Level
{
    /// <summary>
    /// Подарок открывается, когда все его ленты натянуты одновременно (holdTime) — двери открываются насовсем,
    /// летит конфетти. Решает хост, клиент получает «открыт» снимком. Позиция — середина подарка (для конфетти и надписи).
    /// </summary>
    public class RibbonGate : MonoBehaviour, INetState
    {
        [SerializeField] private GiftRibbon[] ribbons;
        [SerializeField] private Door[] doors;
        [SerializeField] private float holdTime = 0.4f;

        private float held;
        private bool open, shownOpen;

        public bool IsOpen => open;

        private void FixedUpdate()
        {
            if (!Online.IsClientView && !open)
            {
                bool all = ribbons != null && ribbons.Length > 0;
                if (all) foreach (var r in ribbons) if (r == null || !r.Pulled) { all = false; break; }
                held = all ? held + Time.fixedDeltaTime : 0f;
                if (held >= holdTime) open = true;
            }
            if (open && !shownOpen)
            {
                shownOpen = true;
                if (doors != null) foreach (var d in doors) if (d != null) d.SetOpen(true, this);
                PushPals.Fire.Puffs.Sparks(transform.position, 40);
            }
        }

        // Дверь «все кнопки» (requireAll) должна знать о воротах заранее
        private void Start()
        {
            if (doors != null) foreach (var d in doors) if (d != null) d.Register(this);
        }

        public void WriteNet(System.IO.BinaryWriter w) => w.Write(open);
        public void ReadNet(System.IO.BinaryReader r) => open = r.ReadBoolean();

        private void OnGUI()
        {
            if (PushPals.UI.UiScreen.BlocksGame) return; // открыт экран меню — мировые надписи не поверх него
            if (open || ribbons == null) return;
            float d = WorldLabel.NearestPlayer(transform.position);
            if (d > 6f) return;
            int pulled = 0;
            foreach (var r in ribbons) if (r != null && r.Pulled) pulled++;
            WorldLabel.Draw(transform.position + Vector3.up * 1.2f, PushPals.UI.Loc.T("ribbons.pull", pulled, ribbons.Length), 0.9f, 13, -1, 190f);
        }
    }
}
