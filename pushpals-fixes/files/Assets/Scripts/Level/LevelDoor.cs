using PushPals.Players;
using PushPals.Ragdoll.Visual;
using UnityEngine;

namespace PushPals.Level
{
    /// <summary>
    /// Дверь уровня в лобби: зашла вся команда и постояла holdTime — уровень загружается (с той же командой;
    /// по сети — у всех, решает хост). Над дверью номер, название и золотые спички. Закрытая дверь (мир ещё не готов) —
    /// «Скоро». Позиция — низ середины проёма.
    /// </summary>
    public class LevelDoor : MonoBehaviour, INetState
    {
        [SerializeField] private LevelDefinition level;
        [SerializeField] private WorldDefinition world;
        [Tooltip("Дверь закрыта (мир ещё не готов)")]
        [SerializeField] private bool locked;
        [SerializeField] private string lockedText = "Скоро";
        [SerializeField] private Vector2 size = new Vector2(1.8f, 2.8f);
        [Tooltip("Сколько секунд вся команда должна постоять внутри")]
        [SerializeField] private float holdTime = 1.2f;
        [SerializeField] private Color frame = new Color(0.45f, 0.3f, 0.18f);
        [SerializeField] private Color inside = new Color(0.25f, 0.18f, 0.12f);
        [SerializeField] private Color ready = new Color(1f, 0.85f, 0.4f);
        [SerializeField] private Color plank = new Color(0.62f, 0.5f, 0.38f);

        public int Inside { get; private set; }
        public int Total { get; private set; }

        private float held;
        private bool loading;
        private SpriteRenderer back;

        private void Awake()
        {
            var f = MatchVisual.AddPill(transform, 0.14f, 1f, frame, -8); f.size = size + Vector2.one * 0.18f;
            f.transform.localPosition = new Vector3(0f, size.y * 0.5f, 0f);
            back = MatchVisual.AddPill(transform, 0.14f, 1f, inside, -7); back.size = size;
            back.transform.localPosition = new Vector3(0f, size.y * 0.5f, 0f);
            if (locked)
            {
                // Заколочена досками
                for (int i = 0; i < 2; i++)
                {
                    var p = MatchVisual.AddPill(transform, 0.12f, 1f, plank, -6);
                    p.size = new Vector2(size.x + 0.3f, 0.3f);
                    p.transform.localPosition = new Vector3(0f, size.y * (0.35f + i * 0.35f), 0f);
                    p.transform.localRotation = Quaternion.Euler(0f, 0f, i == 0 ? 12f : -10f);
                }
            }
        }

        private void FixedUpdate()
        {
            if (locked || Online.IsClientView) { ShowFill(); return; }
            var manager = PlayerManager.Instance;
            if (manager == null) return;
            var rect = new Rect((Vector2)transform.position - new Vector2(size.x * 0.5f, 0f), size);
            int count = 0;
            foreach (var p in manager.Players)
                if (p != null && p.Ragdoll.Body.IsBuilt && rect.Contains(p.Ragdoll.Body.Torso.Body.position)) count++;
            Inside = count;
            Total = manager.Players.Count;
            held = Total > 0 && count == Total ? held + Time.fixedDeltaTime : 0f;
            if (held >= holdTime && !loading && level != null)
            {
                loading = LevelLoader.Load(level.sceneName, PushPals.UI.UiNames.Level(level)); // название — на обложке, как со старта у доски
                if (loading) PushPals.Fire.Puffs.Sparks((Vector2)transform.position + Vector2.up * size.y, 30);
            }
            ShowFill();
        }

        // Проём светлеет, пока команда стоит внутри
        private void ShowFill()
        {
            back.color = Color.Lerp(inside, ready, Mathf.Clamp01(held / Mathf.Max(0.01f, holdTime)));
        }

        public void WriteNet(System.IO.BinaryWriter w) { w.Write((byte)Inside); w.Write((byte)Total); w.Write(held); }
        public void ReadNet(System.IO.BinaryReader r) { Inside = r.ReadByte(); Total = r.ReadByte(); held = r.ReadSingle(); }

        private void OnGUI()
        {
            if (PushPals.UI.UiScreen.BlocksGame) return; // открыт экран меню — мировые надписи не поверх него
            Vector3 top = transform.position + Vector3.up * (size.y + 0.35f);
            float d = WorldLabel.NearestPlayer((Vector2)transform.position + Vector2.up);
            bool near = d < 4f;
            if (locked)
            {
                WorldLabel.Draw(top, PushPals.UI.Loc.Auto(lockedText), near ? 1f : 0.6f, 13, -1, 150f);
                return;
            }
            if (level == null) return;
            int number = world != null ? world.NumberOf(level) : 0;
            string title = (number > 0 ? number + ". " : "") + PushPals.UI.UiNames.Level(level);
            if (!near) { WorldLabel.Draw(top, title, 0.75f, 13, LevelProgress.Golden(level.id), 150f, level.goldenCount); return; }
            string text = title + (level.tutorial ? "\n" + PushPals.UI.Loc.T("board.tutorial") : "") + "\n" + PushPals.UI.Loc.T("door.team", Inside, Mathf.Max(1, Total));
            WorldLabel.Draw(top, text, 1f, 15, LevelProgress.Golden(level.id), 220f, level.goldenCount);
        }

        private void OnDrawGizmos()
        {
            Gizmos.color = frame;
            Gizmos.DrawWireCube(transform.position + Vector3.up * size.y * 0.5f, size);
        }
    }
}
