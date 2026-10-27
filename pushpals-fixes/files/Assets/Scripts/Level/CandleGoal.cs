using PushPals.Fire;
using UnityEngine;

namespace PushPals.Level
{
    /// <summary>
    /// Свечи на торте (мир 2): когда горят все — «С днём рождения!», конфетти и двери открываются насовсем.
    /// Над тортом — сколько свечей уже горит. Решает хост, клиент получает «готово» снимком (свечи синхронизируются сами).
    /// Позиция — середина торта сверху (для надписи и конфетти).
    /// </summary>
    public class CandleGoal : MonoBehaviour, INetState
    {
        [SerializeField] private Candle[] candles;
        [SerializeField] private Door[] doors;
        [SerializeField] private string doneText = "С днём рождения!";

        private bool done, shownDone;
        private float message;

        public bool IsDone => done;

        public int LitCount
        {
            get
            {
                int n = 0;
                if (candles != null) foreach (var c in candles) if (c != null && c.IsLit) n++;
                return n;
            }
        }

        private void FixedUpdate()
        {
            if (!Online.IsClientView && !done && candles != null && candles.Length > 0 && LitCount == candles.Length) done = true;
            if (done && !shownDone)
            {
                shownDone = true;
                message = 4f;
                if (doors != null) foreach (var d in doors) if (d != null) d.SetOpen(true, this);
                for (int i = 0; i < 3; i++) Puffs.Sparks((Vector2)transform.position + new Vector2((i - 1) * 2f, 1f), 30);
            }
        }

        private void Update()
        {
            if (message > 0f) message -= Time.deltaTime;
        }

        // Дверь «все кнопки» (requireAll) должна знать о торте заранее
        private void Start()
        {
            if (doors != null) foreach (var d in doors) if (d != null) d.Register(this);
        }

        public void WriteNet(System.IO.BinaryWriter w) => w.Write(done);
        public void ReadNet(System.IO.BinaryReader r) => done = r.ReadBoolean();

        private void OnGUI()
        {
            if (PushPals.UI.UiScreen.BlocksGame) return; // открыт экран меню — мировые надписи не поверх него
            if (candles == null) return;
            Vector3 top = transform.position + Vector3.up * 2.4f;
            if (message > 0f) { WorldLabel.Draw(top, PushPals.UI.Loc.Auto(doneText), Mathf.Clamp01(message), 20, -1, 260f); return; }
            if (done || WorldLabel.NearestPlayer(transform.position) > 9f) return;
            WorldLabel.Draw(top, PushPals.UI.Loc.T("candles.light", LitCount, candles.Length), 0.9f, 14, -1, 200f);
        }
    }
}
