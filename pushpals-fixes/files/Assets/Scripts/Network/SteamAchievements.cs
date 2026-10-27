using PushPals.Save;
using Steamworks;
using Steamworks.Data;

namespace PushPals.Network
{
    /// <summary>
    /// Достижения Steam (Этап 17.2). Id те же, что в Achievements; для своей игры их заводят на сайте Steamworks
    /// при публикации (у AppID 480 их нет — отправка там ничего не делает, а у нас достижение всё равно сохранено).
    /// </summary>
    public class SteamAchievements : IAchievementPlatform
    {
        private bool requested, ready;

        /// <summary>
        /// Steam подключён и уже прислал статистику. Раньше достижения читались сразу после запроса, когда ответа
        /// ещё нет: открытое в Steam (на другом ПК) выглядело закрытым. Пока ответа нет — «недоступно»: открытое
        /// за это время хранится в сохранении и уходит в Steam, когда статистика придёт (Achievements.SyncPlatform).
        /// </summary>
        public bool Available => SteamClient.IsValid && Ensure();

        // Steam отдаёт достижения после запроса текущей статистики (ответ — колбэком, его крутит NetSession)
        private bool Ensure()
        {
            if (ready) return true;
            if (requested) return false;
            requested = true;
            SteamUserStats.OnUserStatsReceived += OnStatsReceived;
            // Запрос не ушёл (в новых Steamworks SDK статистика грузится сама при запуске) — читаем как есть
            if (!SteamUserStats.RequestCurrentStats())
            {
                SteamUserStats.OnUserStatsReceived -= OnStatsReceived;
                ready = true;
            }
            return ready;
        }

        private void OnStatsReceived(SteamId user, Result result)
        {
            if (!SteamClient.IsValid || user != SteamClient.SteamId) return;
            SteamUserStats.OnUserStatsReceived -= OnStatsReceived;
            if (result != Result.OK) { requested = false; return; } // не удалось — спросим при следующем обращении
            ready = true;
            Achievements.SyncPlatform(); // открытое без Steam — туда, открытое в Steam — себе
        }

        public bool IsUnlocked(string id) => new Achievement(id).State;

        public void Unlock(string id) => new Achievement(id).Trigger();
    }
}
