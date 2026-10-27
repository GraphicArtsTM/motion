using PushPals.Players;
using PushPals.Ragdoll.Visual;
using UnityEngine;
using UnityEngine.Events;

namespace PushPals.Level
{
    /// <summary>
    /// Выход уровня: открывается, когда внутри вся команда (сколько бы игроков ни было). Пока — надпись
    /// «Уровень пройден!» и событие onAllInside (переход на следующий уровень — Этап 10).
    /// Позиция — низ середины проёма.
    /// </summary>
    public class TeamExit : MonoBehaviour, INetState
    {
        [SerializeField] private Vector2 size = new Vector2(2.4f, 3f);
        [SerializeField] private UnityEvent onAllInside;
        [SerializeField] private Color frame = new Color(0.45f, 0.3f, 0.18f);
        [SerializeField] private Color inside = new Color(0.25f, 0.18f, 0.12f, 0.6f);
        [SerializeField] private Color done = new Color(1f, 0.85f, 0.4f, 0.7f);

        public int Inside { get; private set; }
        public bool Completed { get; private set; }

        private SpriteRenderer back;
        private GUIStyle style;

        private void Awake()
        {
            var f = MatchVisual.AddPill(transform, 0.12f, 1f, frame, -5); f.size = size + Vector2.one * 0.16f;
            f.transform.localPosition = new Vector3(0f, size.y * 0.5f, 0f);
            back = MatchVisual.AddPill(transform, 0.12f, 1f, inside, -4); back.size = size;
            back.transform.localPosition = new Vector3(0f, size.y * 0.5f, 0f);
        }

        public void WriteNet(System.IO.BinaryWriter w) { w.Write(Completed); w.Write((byte)Inside); }
        public void ReadNet(System.IO.BinaryReader r)
        {
            bool done = r.ReadBoolean();
            Inside = r.ReadByte();
            if (done && !Completed)
            {
                Completed = true;
                back.color = this.done;
                PushPals.Fire.Puffs.Sparks((Vector2)transform.position + Vector2.up * size.y, 30);
            }
        }

        private void FixedUpdate()
        {
            if (Online.IsClientView) return; // кто внутри — считает хост
            var manager = PlayerManager.Instance;
            if (manager == null) return;
            var rect = new Rect((Vector2)transform.position - new Vector2(size.x * 0.5f, 0f), size);
            int count = 0;
            foreach (var p in manager.Players)
                if (p != null && p.Ragdoll.Body.IsBuilt && rect.Contains(p.Ragdoll.Body.Torso.Body.position)) count++;
            Inside = count;
            bool all = manager.Players.Count > 0 && count == manager.Players.Count;
            if (all && !Completed)
            {
                Completed = true;
                back.color = done;
                PushPals.Fire.Puffs.Sparks((Vector2)transform.position + Vector2.up * size.y, 30);
                onAllInside?.Invoke();
            }
        }

        private void OnGUI()
        {
            if (PushPals.UI.UiScreen.BlocksGame) return; // открыт экран меню — мировые надписи не поверх него
            var manager = PlayerManager.Instance;
            if (manager == null) return;
            if (style == null) { style = new GUIStyle(GUI.skin.label) { fontSize = 28, alignment = TextAnchor.MiddleCenter, fontStyle = FontStyle.Bold }; style.normal.textColor = new Color(0.3f, 0.18f, 0.08f); }
            // На уровне мира итог показывает LevelRun
            if (Completed && LevelRun.Instance == null) GUI.Label(new Rect(0, Screen.height * 0.2f, Screen.width, 50), PushPals.UI.Loc.T("result.title"), style);
        }

        private void OnDrawGizmos()
        {
            Gizmos.color = frame;
            Gizmos.DrawWireCube(transform.position + Vector3.up * size.y * 0.5f, size);
        }
    }
}
