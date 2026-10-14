namespace Shatranj.Core
{
    /// <summary>
    /// Данные экрана «Об игре». Замените заглушки на свои ссылки и имена —
    /// пока ссылка начинается с «YOUR_», кнопка покажет «ссылка ещё не добавлена».
    /// </summary>
    public static class AboutConfig
    {
        public const string Studio = "GraphicArts TM";

        public const string Instagram = "https://instagram.com/YOUR_INSTAGRAM";
        public const string Telegram = "https://t.me/YOUR_TELEGRAM";
        public const string Email = "YOUR_EMAIL@example.com";
        public const string PrivacyPolicyUrl = "https://YOUR_SITE/privacy";

        /// <summary>Идентификатор в Google Play (совпадает с пакетом из Player Settings).</summary>
        public const string PlayStoreId = "uz.shoxvamot.game";

        /// <summary>Команда: имя и ключ роли из Loc (about.role.*). Добавляйте и удаляйте строки.</summary>
        public static readonly string[][] Team =
        {
            new[] { "GraphicArts TM", "about.role.studio" },
            new[] { "Ism Familiya", "about.role.lead" },
            new[] { "Claude (Anthropic)", "about.role.ai" },
        };

        public static bool IsSet(string value) { return !string.IsNullOrEmpty(value) && !value.Contains("YOUR_"); }
    }
}
