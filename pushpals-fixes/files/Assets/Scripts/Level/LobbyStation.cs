using System.Collections.Generic;
using UnityEngine;

namespace PushPals.Level
{
    /// <summary>
    /// Место в лобби, где открывается меню: подойти и нажать «боднуть» (X / E). Шкаф — «мой персонаж» (каждому своё меню),
    /// доска — настройки игры (только хосту). Само меню открывает ввод игрока (PlayerIntentReader). Позиция — низ середины.
    /// </summary>
    public class LobbyStation : MonoBehaviour
    {
        public enum Kind { Wardrobe, HostBoard }

        [SerializeField] private Kind kind;
        [Tooltip("На каком расстоянии от середины (по x) можно открыть")]
        [SerializeField] private float radius = 1.6f;
        [SerializeField] private float height = 3f;
        private const string DefaultPrompt = "X / E — открыть";
        [SerializeField] private string prompt = DefaultPrompt;

        private static readonly List<LobbyStation> all = new List<LobbyStation>();

        public Kind Type => kind;

        private void OnEnable() => all.Add(this);
        private void OnDisable() => all.Remove(this);

        /// <summary>Место, у которого стоит спичка (туловище в зоне), или null.</summary>
        public static LobbyStation Near(Vector2 torso)
        {
            foreach (var s in all)
            {
                Vector2 local = torso - (Vector2)s.transform.position;
                if (Mathf.Abs(local.x) <= s.radius && local.y > -0.5f && local.y < s.height) return s;
            }
            return null;
        }

        private void OnGUI()
        {
            if (PushPals.UI.UiScreen.BlocksGame) return; // открыт экран меню — мировые надписи не поверх него
            if (string.IsNullOrEmpty(prompt)) return; // подпись рисует само место (доска)
            float d = WorldLabel.NearestPlayer((Vector2)transform.position + Vector2.up);
            if (d > radius + 0.6f) return;
            // В сцене подпись по-русски; по умолчанию — ключ station.open
            string text = prompt == DefaultPrompt ? PushPals.UI.Loc.T("station.open") : PushPals.UI.Loc.Auto(prompt);
            WorldLabel.Draw(transform.position + Vector3.up * (height + 0.4f), text, 1f, 14, -1, 200f);
        }

        private void OnDrawGizmos()
        {
            Gizmos.color = new Color(1f, 0.8f, 0.3f);
            Gizmos.DrawWireCube(transform.position + Vector3.up * height * 0.5f, new Vector3(radius * 2f, height, 0f));
        }
    }
}
