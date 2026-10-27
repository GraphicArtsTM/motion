using PushPals.Players;
using PushPals.Ragdoll.Visual;
using UnityEngine;

namespace PushPals.Level
{
    /// <summary>
    /// Места для друзей в лобби (как пустые места в Among Us): у каждой точки появления — бледный силуэт спички,
    /// пока игроков меньше; над первым свободным — «нажми любую кнопку». Вошёл игрок — силуэт пропадает.
    /// Позиция — ступни первого места, дальше через spacing вправо.
    /// </summary>
    public class JoinSlots : MonoBehaviour
    {
        [SerializeField] private int count = PlayerManager.MaxPlayers;
        [SerializeField] private float spacing = 1f;
        [SerializeField] private Color silhouette = new Color(0.28f, 0.17f, 0.09f, 0.22f);

        private Transform[] slots;

        private void Awake()
        {
            slots = new Transform[count];
            for (int i = 0; i < count; i++)
            {
                var s = MatchVisual.NewChild(transform, "Slot " + (i + 1));
                s.localPosition = new Vector3(i * spacing, 0f, 0f);
                // Силуэт: ножки, палочка, головка
                for (int leg = -1; leg <= 1; leg += 2)
                {
                    var l = MatchVisual.AddPill(s, 0.09f, 0.8f, silhouette, -25);
                    l.transform.localPosition = new Vector3(leg * 0.09f, 0.4f, 0f);
                }
                var body = MatchVisual.AddPill(s, 0.2f, 0.8f, silhouette, -25);
                body.transform.localPosition = new Vector3(0f, 1.15f, 0f);
                var head = MatchVisual.AddEllipse(s, new Vector2(0.42f, 0.5f), silhouette, -25);
                head.transform.localPosition = new Vector3(0f, 1.8f, 0f);
                slots[i] = s;
            }
        }

        private int Taken
        {
            get
            {
                var m = PlayerManager.Instance;
                return m != null ? m.Visible.Count : 0;
            }
        }

        private void Update()
        {
            int taken = Taken;
            for (int i = 0; i < slots.Length; i++)
            {
                bool free = i >= taken;
                slots[i].gameObject.SetActive(free);
                // Свободные места чуть «дышат»
                if (free) slots[i].localScale = Vector3.one * (1f + 0.03f * Mathf.Sin(Time.time * 2f + i));
            }
        }

        private void OnGUI()
        {
            if (PushPals.UI.UiScreen.BlocksGame) return; // открыт экран меню — мировые надписи не поверх него
            int taken = Taken;
            if (taken >= slots.Length || Online.IsClientView) return;
            Vector3 top = slots[taken].position + Vector3.up * 2.3f;
            string text = PushPals.UI.Loc.T(taken == 0 ? "slots.join" : Online.IsActive ? "slots.online" : "slots.local");
            WorldLabel.Draw(top, text, 0.85f, 12, -1, 150f);
        }
    }
}
