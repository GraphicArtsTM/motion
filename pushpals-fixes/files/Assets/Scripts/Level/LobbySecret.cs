using PushPals.Players;
using PushPals.Ragdoll.Visual;
using UnityEngine;

namespace PushPals.Level
{
    /// <summary>
    /// Секрет лобби: праздничный колпак парит на верхней полке. Кто до него доберётся (лестница из коробков) —
    /// колпак появляется в шкафу у всех (GameRules.PartyHatFound). Решает хост, клиент узнаёт снимком доски.
    /// Позиция — центр колпака.
    /// </summary>
    public class LobbySecret : MonoBehaviour
    {
        [SerializeField] private float radius = 1.1f;
        [SerializeField] private float messageTime = 4f;

        private Transform art;
        private bool wasFound;
        private float message;

        private void Awake()
        {
            art = MatchVisual.NewChild(transform, "Party Hat");
            Color[] stripes = { new Color(0.95f, 0.3f, 0.45f), new Color(1f, 0.85f, 0.25f), new Color(0.3f, 0.7f, 0.95f) };
            for (int i = 0; i < 4; i++)
            {
                float w = 0.62f - i * 0.14f;
                var s = MatchVisual.AddPill(art, w, 0.2f, stripes[i % 3], -4);
                s.sprite = MatchArt.Pill(0.06f);
                s.size = new Vector2(w, 0.2f);
                s.transform.localPosition = new Vector3(0f, -0.25f + i * 0.17f, 0f);
            }
            var pom = MatchVisual.AddEllipse(art, Vector2.one * 0.16f, Color.white, -3);
            pom.transform.localPosition = new Vector3(0f, 0.48f, 0f);
            wasFound = GameRules.PartyHatFound;
            if (wasFound) PushPals.Save.Achievements.Unlock(PushPals.Save.Achievements.PartyHat); // найден до достижений (старое сохранение)
        }

        private void Update()
        {
            // Парит и покачивается
            art.localPosition = new Vector3(0f, Mathf.Sin(Time.time * 2f) * 0.08f, 0f);
            art.localRotation = Quaternion.Euler(0f, 0f, Mathf.Sin(Time.time * 1.3f) * 8f);
            art.gameObject.SetActive(!GameRules.PartyHatFound);
            if (message > 0f) message -= Time.deltaTime;
            if (GameRules.PartyHatFound && !wasFound)
            {
                wasFound = true;
                message = messageTime;
                PushPals.Save.Achievements.Unlock(PushPals.Save.Achievements.PartyHat); // у хоста и у сетевого клиента
                PushPals.Fire.Puffs.Sparks(transform.position, 40);
            }
        }

        private void FixedUpdate()
        {
            if (Online.IsClientView || GameRules.PartyHatFound) return;
            var m = PlayerManager.Instance;
            if (m == null) return;
            foreach (var p in m.Players)
            {
                if (p == null || !p.Ragdoll.Body.IsBuilt) continue;
                if (Vector2.Distance(p.Ragdoll.Body.Head.Body.position, transform.position) < radius ||
                    Vector2.Distance(p.Ragdoll.Body.Torso.Body.position, transform.position) < radius)
                {
                    GameRules.PartyHatFound = true;
                    GameRules.NotifyChanged();
                    return;
                }
            }
        }

        private void OnGUI()
        {
            if (PushPals.UI.UiScreen.BlocksGame) return; // открыт экран меню — мировые надписи не поверх него
            if (message > 0f)
                WorldLabel.Draw(transform.position + Vector3.up * 1f, PushPals.UI.Loc.T("secret.found"), Mathf.Clamp01(message), 16, -1, 260f);
            else if (!GameRules.PartyHatFound && WorldLabel.NearestPlayer(transform.position) < 3f)
                WorldLabel.Draw(transform.position + Vector3.up * 0.9f, PushPals.UI.Loc.T("secret.what"), 0.9f, 13, -1, 120f);
        }
    }
}
