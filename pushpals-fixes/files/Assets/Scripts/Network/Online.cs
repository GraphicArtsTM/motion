using System.IO;

namespace PushPals
{
    /// <summary>
    /// Общее для всех систем знание о сетевой игре (без зависимости от Netcode): уровень, огонь и предметы
    /// смотрят сюда, а заполняет — сетевой модуль (PushPals.Network.NetSession).
    /// Подход «мир считает хост»: у клиента элементы уровня ничего не решают сами, только показывают снимок хоста.
    /// </summary>
    public static class Online
    {
        /// <summary>Идёт сетевая игра (хост или клиент).</summary>
        public static bool IsActive { get; set; }

        /// <summary>Мы — сетевой клиент: мир (кнопки, двери, огонь, предметы) считает хост, у нас только вид.</summary>
        public static bool IsClientView { get; set; }

        /// <summary>Мы — хост сетевой игры.</summary>
        public static bool IsHost => IsActive && !IsClientView;

        /// <summary>Хост: загрузить уровень у всех (переход, перезапуск). Задаёт сетевой модуль.</summary>
        public static System.Action<string> LoadSceneForAll;

        /// <summary>Клиент: сообщить хосту, держим ли «Заново». Задаёт сетевой модуль.</summary>
        public static System.Action<bool> SendRestartVote;

        /// <summary>Хост: сколько игроков на других ПК сейчас держат «Заново».</summary>
        public static int RemoteRestartVotes { get; set; }

        /// <summary>Автотест: голос «Заново» вместо кнопок (null — по кнопкам).</summary>
        public static bool? VoteOverride { get; set; }

        /// <summary>Сколько всего людей в сетевой игре (ПК).</summary>
        public static int PeopleCount { get; set; }

        /// <summary>Код для друзей (номер лобби Steam или «локальная игра»); пусто — не в сети. Задаёт сетевой модуль.</summary>
        public static System.Func<string> LobbyCode;

        /// <summary>Открыть панель сетевой игры (F2). Задаёт сетевой модуль.</summary>
        public static System.Action ShowNetworkPanel;

        /// <summary>
        /// Выйти из сетевой игры, не перезагружая сцену у клиента (сразу следом грузится другая — выход в главное меню).
        /// Задаёт сетевой модуль.
        /// </summary>
        public static System.Action LeaveSession;

        // ---------- Личные сообщения (режим «Предатель»: тайная роль — только своему ПК) ----------

        /// <summary>Номер этого ПК в сети (хост — 0).</summary>
        public static ulong LocalClientId { get; set; }

        /// <summary>Номер хоста в сети (как NetworkManager.ServerClientId).</summary>
        public const ulong HostClientId = 0;

        /// <summary>Сообщение пришло от хоста к нам-клиенту (а не от другого ПК самому хосту).</summary>
        public static bool FromHost(ulong sender) => IsClientView && sender == HostClientId;

        /// <summary>Хост: отправить сообщение по каналу одному ПК (клиенту). Задаёт сетевой модуль.</summary>
        public static System.Action<ulong, string, byte[]> SendToClient;
        /// <summary>Клиент: отправить сообщение хосту. Задаёт сетевой модуль.</summary>
        public static System.Action<string, byte[]> SendToHost;

        private static readonly System.Collections.Generic.Dictionary<string, System.Action<ulong, byte[]>> handlers =
            new System.Collections.Generic.Dictionary<string, System.Action<ulong, byte[]>>();

        /// <summary>Слушать канал (обработчик получает: от кого, данные).</summary>
        public static void On(string channel, System.Action<ulong, byte[]> handler) => handlers[channel] = handler;
        public static void Off(string channel) => handlers.Remove(channel);

        /// <summary>Пришло сообщение (вызывает сетевой модуль).</summary>
        public static void Dispatch(string channel, ulong sender, byte[] data)
        {
            System.Action<ulong, byte[]> h;
            if (handlers.TryGetValue(channel, out h) && h != null) h(sender, data);
        }

        // Play в редакторе без перезагрузки домена: статика живёт между запусками — сбрасываем
        [UnityEngine.RuntimeInitializeOnLoadMethod(UnityEngine.RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStatics()
        {
            IsActive = false;
            IsClientView = false;
            LoadSceneForAll = null;
            SendRestartVote = null;
            RemoteRestartVotes = 0;
            PeopleCount = 0;
            VoteOverride = null;
            LobbyCode = null;
            ShowNetworkPanel = null;
            LeaveSession = null;
            LocalClientId = 0;
            SendToClient = null;
            SendToHost = null;
            handlers.Clear();
        }
    }

    /// <summary>
    /// Элемент уровня со своим состоянием для сети: хост пишет, клиент читает и показывает
    /// (горит ли свеча, открыта ли дверь, сколько прогорел фитиль…). Движение тел синхронизируется отдельно.
    /// </summary>
    public interface INetState
    {
        void WriteNet(BinaryWriter w);
        void ReadNet(BinaryReader r);
    }

    /// <summary>Элемент, исчезнувший у хоста (сгорел, сломан, взят): клиент показывает это и убирает его у себя.</summary>
    public interface INetRemovable
    {
        void NetRemoved();
    }
}
