using System;
using System.Collections.Generic;
using UnityEngine;

namespace Shatranj.Core
{
    public enum TeamRole { Studio, Author, Designer, Developer, Artist, Composer, Tester, Other }

    [Serializable]
    public class TeamMember
    {
        [Tooltip("Имя или название")] public string name = "Ism Familiya";
        [Tooltip("Роль в команде (переводится на все языки игры)")] public TeamRole role = TeamRole.Developer;
        [Tooltip("Своя подпись роли — если заполнена, показывается вместо стандартной")] public string customRole = "";
    }

    /// <summary>
    /// Всё, что показывает экран «Об игре». Редактируется в инспекторе Unity:
    /// меню «Shox va Mot → Об игре (контакты и команда)» или файл Assets/Resources/AboutInfo.asset.
    /// Пустые ссылки на экране не показываются.
    /// </summary>
    [CreateAssetMenu(fileName = "AboutInfo", menuName = "Shox va Mot/About Info")]
    public class AboutInfo : ScriptableObject
    {
        [Header("Команда (порядок = порядок на экране)")]
        public List<TeamMember> team = new List<TeamMember>
        {
            new TeamMember { name = "GraphicArts TM", role = TeamRole.Studio },
            new TeamMember { name = "Ism Familiya", role = TeamRole.Author },
            new TeamMember { name = "Ism Familiya", role = TeamRole.Designer },
            new TeamMember { name = "Ism Familiya", role = TeamRole.Developer },
        };

        [Header("Ссылки (оставьте пустым, чтобы скрыть кнопку)")]
        [Tooltip("Например: https://instagram.com/shoxvamot")] public string instagram = "";
        [Tooltip("Например: https://t.me/shoxvamot")] public string telegram = "";
        [Tooltip("Например: https://youtube.com/@shoxvamot")] public string youtube = "";
        [Tooltip("Например: https://tiktok.com/@shoxvamot")] public string tiktok = "";
        [Tooltip("Сайт студии")] public string website = "";
        [Tooltip("Почта поддержки, без mailto:")] public string email = "";

        [Header("Google Play")]
        [Tooltip("Ссылка на политику конфиденциальности (нужна для приложений с рекламой)")] public string privacyPolicyUrl = "";
        [Tooltip("ID приложения в Google Play. Пусто — берётся из Player Settings")] public string playStoreId = "";

        static AboutInfo cached;

        public static AboutInfo Load()
        {
            if (cached != null) return cached;
            cached = Resources.Load<AboutInfo>("AboutInfo");
            if (cached == null) cached = CreateInstance<AboutInfo>();
            return cached;
        }

        public string StoreId { get { return string.IsNullOrEmpty(playStoreId) ? Application.identifier : playStoreId; } }

        public static bool IsSet(string value)
        {
            return !string.IsNullOrEmpty(value) && !value.Contains("YOUR_");
        }
    }
}
