using TMPro;
using UnityEngine;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Окно (Этап 17.3): бумажная панель panel_dialog, лента-заголовок banner_header, текст и ряд кнопок снизу.
    /// Выезжает ящиком (UiPanel). Кнопки добавляются кодом: AddButton(ключ, главная?, действие).
    /// </summary>
    [RequireComponent(typeof(UiPanel))]
    public class UiDialog : MonoBehaviour
    {
        [SerializeField] private LocText title;
        [SerializeField] private LocText body;
        [SerializeField] private RectTransform buttons;
        [SerializeField] private GameObject primaryPrefab, secondaryPrefab;

        public UiPanel Panel => GetComponent<UiPanel>();

        // Кнопки окна не срабатывают сразу после открытия: нажатие, которое открыло окно («Выйти»),
        // не должно тут же нажать и его главную кнопку («Выход»)
        private const float ClickGuard = 0.3f;
        private float openedAt = -1f;

        private void OnEnable() => openedAt = Time.unscaledTime;

        public void Setup(LocText titleText, LocText bodyText, RectTransform buttonRow, GameObject primary, GameObject secondary)
        {
            title = titleText;
            body = bodyText;
            buttons = buttonRow;
            primaryPrefab = primary;
            secondaryPrefab = secondary;
        }

        public void Set(string titleKey, string bodyKey)
        {
            if (title != null) title.Key = titleKey;
            if (body != null) body.Key = bodyKey;
        }

        /// <summary>Добавить кнопку внизу (главная — красная, обычная — бумажная).</summary>
        public Button AddButton(string key, bool primary, System.Action onClick)
        {
            var prefab = primary ? primaryPrefab : secondaryPrefab;
            if (prefab == null || buttons == null) return null;
            var go = Instantiate(prefab, buttons);
            var label = go.GetComponentInChildren<LocText>();
            if (label != null) label.Key = key;
            var b = go.GetComponent<Button>();
            if (onClick != null) b.onClick.AddListener(() => { if (Time.unscaledTime - openedAt >= ClickGuard) onClick(); });
            return b;
        }

        /// <summary>Окно «точно?»: заголовок, текст, главная кнопка с действием и «Отмена». Закрылось — удаляется.</summary>
        public static UiDialog Confirm(string titleKey, string bodyKey, string confirmKey, System.Action onConfirm)
        {
            var dialog = UiPrefabs.Spawn<UiDialog>("DialogPanel", UiRoot.Instance.Popups);
            dialog.gameObject.SetActive(false);
            dialog.Set(titleKey, bodyKey);
            dialog.AddButton(confirmKey, true, () => { dialog.Panel.Close(); if (onConfirm != null) onConfirm(); });
            dialog.AddButton("ui.cancel", false, () => dialog.Panel.Close());
            dialog.Panel.Closed += () => Destroy(dialog.gameObject, 0.6f);
            dialog.Panel.Open();
            return dialog;
        }

        public void ClearButtons()
        {
            if (buttons == null) return;
            for (int i = buttons.childCount - 1; i >= 0; i--) Destroy(buttons.GetChild(i).gameObject);
        }
    }
}
