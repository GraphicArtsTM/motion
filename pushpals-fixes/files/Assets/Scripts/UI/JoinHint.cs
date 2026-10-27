using PushPals.Players;
using UnityEngine;

namespace PushPals.UI
{
    /// <summary>
    /// Подсказка внизу экрана: как войти, где пауза и как уйти из команды; по сети — где код и приглашения.
    /// </summary>
    public class JoinHint : MonoBehaviour
    {
        [SerializeField] private int fontSize = 18;

        private GUIStyle style;

        private void OnGUI()
        {
            if (PushPals.UI.UiScreen.BlocksGame) return; // открыт экран меню — мировые надписи не поверх него
            var manager = PlayerManager.Instance;
            if (manager == null) return;

            if (style == null)
            {
                style = new GUIStyle(GUI.skin.label) { alignment = TextAnchor.LowerCenter, fontSize = fontSize };
                style.normal.textColor = new Color(0.25f, 0.16f, 0.1f);
            }

            // Раньше по сети отправляла к отладочной панели F2 — теперь к паузе → «Онлайн»
            int count = manager.Visible.Count;
            string text = Online.IsActive
                ? Loc.T("hint.online", count, PlayerManager.MaxPlayers)
                : manager.Players.Count == 0
                ? Loc.T("hint.join")
                : manager.Players.Count < PlayerManager.MaxPlayers
                    ? Loc.T("hint.players", manager.Players.Count, PlayerManager.MaxPlayers)
                    : Loc.T("hint.full");
            GUI.Label(new Rect(0, Screen.height - 40, Screen.width, 32), text, style);
        }
    }
}
