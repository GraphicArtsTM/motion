using System;
using System.Collections.Generic;
using UnityEngine;

// Языки игры. Порядок важен: по нему переключается кнопка "ЯЗЫК" в меню.
public enum Lang { Ru = 0, En = 1, Uz = 2 }

// Простая локализация без пакетов: таблица "ключ -> три перевода" (русский, английский, узбекский).
// Узбекский - латиница; буквы oʻ/gʻ записаны через символ ‘ (U+2018): он есть во встроенном шрифте
// и не ломает строки JavaScript на странице телефона.
//
//   Loc.T("menu.single")            -> "ОДИНОЧНАЯ ИГРА" / "SINGLE PLAYER" / "YAKKA O‘YIN"
//   Loc.F("hud.checkpoint", 5)      -> строка с подстановкой {0}
//
// Выбранный язык запоминается в PlayerPrefs. Событие Changed вызывается при смене языка.
public static class Loc
{
    const string PrefKey = "royalrun_lang";

    static bool initialized;
    static Lang current = Lang.Ru;

    // Код языка для сетевого потока (читается без обращения к Unity API).
    static volatile string codeForThreads = "ru";

    public static event Action Changed;

    public static Lang Current
    {
        get { Init(); return current; }
    }

    public static string Code
    {
        get { Init(); return CodeOf(current); }
    }

    // Безопасно читать из любого потока (используется сервером при отдаче страницы телефону).
    public static string CodeForThreads
    {
        get { return codeForThreads; }
    }

    public static string CodeOf(Lang l)
    {
        switch (l)
        {
            case Lang.En: return "en";
            case Lang.Uz: return "uz";
            default: return "ru";
        }
    }

    // Название языка на самом этом языке - для кнопки в меню.
    public static string NativeName(Lang l)
    {
        switch (l)
        {
            case Lang.En: return "ENGLISH";
            case Lang.Uz: return "O‘ZBEKCHA";
            default: return "РУССКИЙ";
        }
    }

    static void Init()
    {
        if (initialized) return;
        initialized = true;

        int saved = PlayerPrefs.GetInt(PrefKey, -1);
        if (saved >= 0 && saved <= 2)
        {
            current = (Lang)saved;
        }
        else
        {
            // Первый запуск: язык системы. Узбекского в SystemLanguage нет, поэтому по умолчанию - русский.
            current = Application.systemLanguage == SystemLanguage.English ? Lang.En : Lang.Ru;
        }
        codeForThreads = CodeOf(current);
    }

    public static void Set(Lang lang)
    {
        Init();
        if (lang == current) return;
        current = lang;
        codeForThreads = CodeOf(current);
        PlayerPrefs.SetInt(PrefKey, (int)lang);
        PlayerPrefs.Save();
        if (Changed != null) Changed();
    }

    public static void Next()
    {
        Set((Lang)(((int)Current + 1) % 3));
    }

    public static string T(string key)
    {
        Init();
        string[] row;
        if (!Table.TryGetValue(key, out row)) return key;
        string s = row[(int)current];
        return string.IsNullOrEmpty(s) ? row[(int)Lang.En] : s;
    }

    public static string F(string key, params object[] args)
    {
        return string.Format(T(key), args);
    }

    // ------------------------------------------------------------------
    //  Таблица переводов: ключ, русский, английский, узбекский
    // ------------------------------------------------------------------

    static readonly Dictionary<string, string[]> Table = new Dictionary<string, string[]>();

    static void Add(string key, string ru, string en, string uz)
    {
        Table[key] = new[] { ru, en, uz };
    }

    static Loc()
    {
        // --- главное меню ---
        Add("menu.subtitle", "Беги, уворачивайся, собирай!", "Run, dodge, collect!", "Yugur, chetlab o‘t, yig‘!");
        Add("menu.single", "ОДИНОЧНАЯ ИГРА", "SINGLE PLAYER", "YAKKA O‘YIN");
        Add("menu.multi", "МУЛЬТИПЛЕЕР   ·   2-3 игрока", "MULTIPLAYER   ·   2-3 players", "KO‘P O‘YINCHI   ·   2-3 kishi");
        Add("menu.help", "КАК ПОДКЛЮЧИТЬСЯ", "HOW TO CONNECT", "QANDAY ULANISH");
        Add("menu.lang", "ЯЗЫК: {0}", "LANGUAGE: {0}", "TIL: {0}");
        Add("menu.quit", "ВЫХОД", "QUIT", "CHIQISH");
        Add("footer.menu",
            "Вверх / Вниз - выбор     Enter - подтвердить     мышь тоже работает     F1 - помощь с телефоном",
            "Up / Down - select     Enter - confirm     mouse works too     F1 - phone connection help",
            "Yuqori / Pastga - tanlash     Enter - tasdiqlash     sichqoncha ham ishlaydi     F1 - telefonni ulash bo‘yicha yordam");

        // --- выбор героя ---
        Add("select.title", "ВЫБЕРИ ГЕРОЯ", "CHOOSE YOUR HERO", "QAHRAMONNI TANLANG");
        Add("select.play", "ИГРАТЬ", "PLAY", "O‘YNASH");
        Add("select.back", "НАЗАД", "BACK", "ORQAGA");
        Add("footer.select",
            "Влево / Вправо - выбор героя     Enter - играть     в игре: WASD / стрелки - бег, Пробел - прыжок     Esc - назад",
            "Left / Right - choose hero     Enter - play     in game: WASD / arrows - run, Space - jump     Esc - back",
            "Chapga / O‘ngga - qahramon tanlash     Enter - o‘ynash     o‘yinda: WASD / strelkalar - yugurish, Probel - sakrash     Esc - orqaga");

        // --- лобби ---
        Add("lobby.subtitle", "СЕТЕВАЯ ИГРА", "NETWORK GAME", "TARMOQ O‘YINI");
        Add("lobby.qr", "Наведи камеру телефона сюда", "Point your phone camera here", "Telefon kamerasini shu yerga qarating");
        Add("lobby.qrMany", "Адрес {0} из {1}  ·  Tab - следующий", "Address {0} of {1}  ·  Tab - next", "Manzil {0} / {1}  ·  Tab - keyingisi");
        Add("lobby.steps",
            "<b>1.</b>  Подключи телефон к той же сети Wi-Fi\n<b>2.</b>  Наведи камеру на QR-код или введи адрес\n<b>3.</b>  Введи имя, выбери героя и нажми ГОТОВ",
            "<b>1.</b>  Connect your phone to the same Wi-Fi network\n<b>2.</b>  Point the camera at the QR code or type the address\n<b>3.</b>  Enter your name, pick a hero and tap READY",
            "<b>1.</b>  Telefonni o‘sha Wi-Fi tarmog‘iga ulang\n<b>2.</b>  Kamerani QR-kodga qarating yoki manzilni kiriting\n<b>3.</b>  Ismingizni yozing, qahramon tanlang va TAYYOR tugmasini bosing");
        Add("lobby.serverFail",
            "<color=#ff8a80>Не удалось запустить сервер для телефонов:\nпорты 8080-8090 заняты другой программой.</color>",
            "<color=#ff8a80>Could not start the controller server:\nports 8080-8090 are used by another program.</color>",
            "<color=#ff8a80>Telefonlar uchun serverni ishga tushirib bo‘lmadi:\n8080-8090 portlari boshqa dastur tomonidan band.</color>");
        Add("lobby.free", "Свободное место", "Free slot", "Bo‘sh joy");
        Add("lobby.waitingPhone", "ждём телефон...", "waiting for a phone...", "telefon kutilmoqda...");
        Add("lobby.choosing", "выбирает героя...", "choosing a hero...", "qahramon tanlamoqda...");
        Add("lobby.ready", "ГОТОВ", "READY", "TAYYOR");
        Add("lobby.notReady", "не готов", "not ready", "tayyor emas");
        Add("lobby.hintEmpty", "Ждём игроков. Подключиться могут до трёх человек.", "Waiting for players. Up to three can join.", "O‘yinchilar kutilmoqda. Uch kishigacha qo‘shilishi mumkin.");
        Add("lobby.hintCount", "Готовы: {0} из {1}.  Игра начнётся, когда все будут готовы.", "Ready: {0} of {1}.  The game starts when everyone is ready.", "Tayyor: {0} / {1}.  Hamma tayyor bo‘lganda o‘yin boshlanadi.");
        Add("footer.lobby",
            "Tab - след. адрес     F1 - помощь     K - игрок с клавиатуры (до 3: WASD / стрелки / NumPad; влево-вправо - герой, Enter - готов, L - убрать)     Esc - меню",
            "Tab - next address     F1 - help     K - keyboard player (up to 3: WASD / arrows / NumPad; left-right - hero, Enter - ready, L - remove)     Esc - menu",
            "Tab - keyingi manzil     F1 - yordam     K - klaviatura o‘yinchisi (3 tagacha: WASD / strelkalar / NumPad; chap-o‘ng - qahramon, Enter - tayyor, L - olib tashlash)     Esc - menyu");

        // --- результаты и пауза ---
        Add("results.title", "РЕЗУЛЬТАТЫ", "RESULTS", "NATIJALAR");
        Add("btn.restart", "ЗАНОВО", "RESTART", "QAYTA");
        Add("btn.addPlayers", "ДОБАВИТЬ ИГРОКОВ", "ADD PLAYERS", "O‘YINCHI QO‘SHISH");
        Add("btn.changeHero", "СМЕНИТЬ ГЕРОЯ", "CHANGE HERO", "QAHRAMONNI ALMASHTIRISH");
        Add("btn.mainMenu", "ГЛАВНОЕ МЕНЮ", "MAIN MENU", "BOSH MENYU");
        Add("btn.resume", "ПРОДОЛЖИТЬ", "RESUME", "DAVOM ETISH");
        Add("btn.close", "ЗАКРЫТЬ", "CLOSE", "YOPISH");
        Add("results.hintSingle",
            "Enter - заново     L - сменить героя     Esc - меню",
            "Enter - restart     L - change hero     Esc - menu",
            "Enter - qayta     L - qahramonni almashtirish     Esc - menyu");
        Add("results.hintNet",
            "Enter - заново     L - добавить игроков     на телефонах: «Играть ещё»     Esc - меню",
            "Enter - restart     L - add players     phones: tap Play again     Esc - menu",
            "Enter - qayta     L - o‘yinchi qo‘shish     telefonlarda: «Yana o‘ynash»     Esc - menyu");
        Add("results.best", "Рекорд: {0}", "Best: {0}", "Rekord: {0}");
        Add("results.newBest", "НОВЫЙ РЕКОРД!", "NEW RECORD!", "YANGI REKORD!");
        Add("pause.title", "ПАУЗА", "PAUSED", "PAUZA");
        Add("footer.pause",
            "Вверх / Вниз - выбор     Enter - подтвердить     Esc - продолжить",
            "Up / Down - select     Enter - confirm     Esc - resume",
            "Yuqori / Pastga - tanlash     Enter - tasdiqlash     Esc - davom etish");

        // --- окно помощи ---
        Add("help.title", "КАК ПОДКЛЮЧИТЬ ТЕЛЕФОН", "HOW TO CONNECT YOUR PHONE", "TELEFONNI QANDAY ULASH");
        Add("help.now", "<b>Что компьютер видит прямо сейчас</b>", "<b>What the computer sees right now</b>", "<b>Kompyuter hozir nimani ko‘rmoqda</b>");
        Add("help.serverFail",
            "<color=#ff8a80>Сервер для телефонов не запустился: порты 8080-8090 заняты другой программой.</color>",
            "<color=#ff8a80>The controller server did not start: ports 8080-8090 are used by another program.</color>",
            "<color=#ff8a80>Telefonlar uchun server ishga tushmadi: 8080-8090 portlari boshqa dastur tomonidan band.</color>");
        Add("help.portLine", "Порт: {0}      Адреса: {1}", "Port: {0}      Addresses: {1}", "Port: {0}      Manzillar: {1}");
        Add("help.statsLine", "Страница открыта: {0} раз      Подключений контроллера: {1} (сейчас {2})", "Page opened: {0} times      Controllers connected: {1} (now {2})", "Sahifa ochildi: {0} marta      Pult ulanishlari: {1} (hozir {2})");
        Add("help.noHits", "<color=#ffd54f>Ни один телефон ещё не достучался до компьютера - смотри шаги 1-4 ниже.</color>", "<color=#ffd54f>No phone has reached the computer yet - see steps 1-4 below.</color>", "<color=#ffd54f>Hali birorta telefon kompyuterga ulanmadi - quyidagi 1-4 qadamlarni ko‘ring.</color>");
        Add("help.noWs", "<color=#ffd54f>Страница открылась, но контроллер не подключился. Обнови страницу на телефоне.</color>", "<color=#ffd54f>The page was opened, but the controller did not connect. Refresh the page on the phone.</color>", "<color=#ffd54f>Sahifa ochildi, lekin pult ulanmadi. Telefonda sahifani yangilang.</color>");
        Add("help.ok", "<color=#8bff8b>Телефон подключён.</color>", "<color=#8bff8b>A phone is connected.</color>", "<color=#8bff8b>Telefon ulangan.</color>");
        Add("help.ifCant", "<b>Если телефон не открывает страницу</b>", "<b>If the phone cannot open the page</b>", "<b>Agar telefon sahifani ochmasa</b>");
        Add("help.s1",
            "1.  Телефон и компьютер должны быть в одной сети Wi-Fi. «Гостевая» сеть роутера обычно не подходит. Выключи мобильный интернет.",
            "1.  Phone and computer must be on the same Wi-Fi network. A router's \"guest\" network usually does not work. Turn mobile data off.",
            "1.  Telefon va kompyuter bitta Wi-Fi tarmog‘ida bo‘lishi kerak. Routerning «mehmon» tarmog‘i odatda ishlamaydi. Mobil internetni o‘chiring.");
        Add("help.s2",
            "2.  Адрес должен начинаться с <b>http://</b>, а не https://. Проще всего - отсканировать QR-код.",
            "2.  The address must start with <b>http://</b>, not https://. The easiest way is to scan the QR code.",
            "2.  Manzil <b>http://</b> bilan boshlanishi kerak, https:// emas. Eng osoni - QR-kodni skanerlash.");
        Add("help.s3",
            "3.  Windows: при первом запуске разреши доступ в частных сетях. Если окно было закрыто, выполни в командной строке от имени администратора:",
            "3.  Windows: on first launch allow access on Private networks. If you closed the window, run this in a Command Prompt as administrator:",
            "3.  Windows: birinchi ishga tushirishda xususiy tarmoqlarda ruxsat bering. Agar oyna yopilgan bo‘lsa, buyruq satrida administrator sifatida bajaring:");
        Add("help.s4",
            "4.  Несколько адресов? В лобби нажми Tab, чтобы показать следующий адрес и QR-код.",
            "4.  Several addresses? In the lobby press Tab to show the next address and QR code.",
            "4.  Bir nechta manzil bormi? Lobbida keyingi manzil va QR-kodni ko‘rsatish uchun Tab tugmasini bosing.");
        Add("help.s5",
            "5.  Проверка: открой в браузере телефона адрес с /ping на конце - должно появиться слово ok.",
            "5.  Test: open the address with /ping added in the phone browser - you should see the word ok.",
            "5.  Tekshiruv: telefon brauzerida manzil oxiriga /ping qo‘shib oching - ok so‘zi chiqishi kerak.");
        Add("help.s6",
            "6.  Не помогло? Включи на телефоне точку доступа, подключи к ней компьютер и перезапусти игру.",
            "6.  Still stuck? Turn on the phone's hotspot, connect the computer to it and restart the game.",
            "6.  Yordam bermadimi? Telefonda hotspotni yoqing, kompyuterni unga ulang va o‘yinni qayta ishga tushiring.");

        // --- игра (полоса игрока) ---
        Add("hud.seconds", "{0} с", "{0} s", "{0} s");
        Add("hud.checkpoint", "ЧЕКПОИНТ  +{0} с", "CHECKPOINT  +{0} s", "NAZORAT NUQTASI  +{0} s");
        Add("hud.speedUp", "УСКОРЕНИЕ!", "SPEED UP!", "TEZLASHISH!");
        Add("hud.hit", "УДАР!", "HIT!", "ZARBA!");
        Add("hud.hitPenalty", "УДАР!  −{0} с", "CRASH!  −{0} s", "ZARBA!  −{0} s");
        Add("hud.comboLost", "комбо потеряно", "combo lost", "kombo yo‘qoldi");
        Add("hud.go", "ВПЕРЁД!", "GO!", "OLG‘A!");
        Add("hud.coins", "монет: {0}", "coins: {0}", "tanga: {0}");
        Add("hud.bestCombo", "комбо x{0}", "combo x{0}", "kombo x{0}");
        Add("zone.0", "ЗЕЛЁНЫЕ ЛУГА", "GREEN MEADOWS", "YASHIL O‘TLOQLAR");
        Add("zone.1", "ОСЕННИЙ ЛЕС", "AUTUMN FOREST", "KUZGI O‘RMON");
        Add("zone.2", "ЗИМНИЕ ГОРЫ", "WINTER PEAKS", "QISHKI TOG‘LAR");
        Add("hud.distance", "{0} м", "{0} m", "{0} m");
        Add("hud.combo", "КОМБО x{0}!", "COMBO x{0}!", "KOMBO x{0}!");
        Add("hud.comboShort", "x{0}", "x{0}", "x{0}");
        Add("hud.gem", "САМОЦВЕТ +{0}", "GEM +{0}", "QIMMATBAHO TOSH +{0}");
        Add("hud.shield", "ЩИТ!", "SHIELD!", "QALQON!");
        Add("hud.shieldSaved", "ЩИТ ЗАЩИТИЛ!", "SHIELD SAVED YOU!", "QALQON HIMOYA QILDI!");
        Add("hud.magnet", "МАГНИТ!", "MAGNET!", "MAGNIT!");
        Add("hud.hourglass", "ВРЕМЯ  +{0} с", "TIME  +{0} s", "VAQT  +{0} s");
        Add("hud.shieldShort", "ЩИТ", "SHIELD", "QALQON");
        Add("hud.magnetShort", "МАГНИТ", "MAGNET", "MAGNIT");
        Add("hud.jumpKey", "ПРЫЖОК: {0}", "JUMP: {0}", "SAKRASH: {0}");
        Add("hud.jumpTap", "ПРЫЖОК: КОСНИСЬ ЭКРАНА", "JUMP: TAP THE SCREEN", "SAKRASH: EKRANGA TEGING");
        Add("key.space", "ПРОБЕЛ", "SPACE", "PROBEL");
        Add("keys.solo", "WASD/стрелки + Пробел", "WASD/arrows + Space", "WASD/strelkalar + Probel");
        Add("keys.wasd", "WASD + Пробел", "WASD + Space", "WASD + Probel");
        Add("keys.arrows", "стрелки + правый Shift", "arrows + Right Shift", "strelkalar + o‘ng Shift");
        Add("keys.numpad", "NumPad 8456 + 0", "NumPad 8456 + 0", "NumPad 8456 + 0");
        Add("hud.timeUp", "ВРЕМЯ ВЫШЛО\nОчки: {0}", "TIME'S UP\nScore: {0}", "VAQT TUGADI\nOchko: {0}");

        // --- имена игроков ---
        Add("player.keyboard", "Клавиатура", "Keyboard", "Klaviatura");
        Add("player.single", "Игрок", "Player", "O‘yinchi");
        Add("player.default", "Игрок {0}", "Player {0}", "O‘yinchi {0}");

        // --- сообщения на телефон ---
        Add("phone.waitMenu",
            "Игра в главном меню. Выбери «Мультиплеер» на компьютере - эта страница подключится сама.",
            "The game is on the main menu. Choose Multiplayer on the computer - this page will connect by itself.",
            "O‘yin bosh menyuda. Kompyuterda «Ko‘p o‘yinchi»ni tanlang - bu sahifa o‘zi ulanadi.");
        Add("phone.waitReturned",
            "Ведущий вернулся в меню. Подожди - страница переподключится сама.",
            "The host returned to the menu. Hold on - this page will reconnect by itself.",
            "Boshlovchi menyuga qaytdi. Kuting - sahifa o‘zi qayta ulanadi.");
        Add("phone.fullStarted",
            "Игра уже идёт. Дождись конца раунда и обнови страницу.",
            "The game has already started. Wait for the round to end, then refresh the page.",
            "O‘yin allaqachon boshlangan. Raund tugashini kuting va sahifani yangilang.");
        Add("phone.fullRoom",
            "Комната заполнена: уже подключились 3 игрока.",
            "The room is full: 3 players have already joined.",
            "Xona to‘lgan: 3 o‘yinchi allaqachon qo‘shilgan.");

        // --- герои ---
        Add("char.king", "Король", "King", "Qirol");
        Add("char.king.desc", "Сбалансированный. Без слабостей и без сюрпризов.", "Balanced. No weaknesses, no surprises.", "Muvozanatli. Zaif tomoni ham, kutilmagan jihati ham yo‘q.");
        Add("char.knight", "Рыцарь", "Knight", "Ritsar");
        Add("char.knight.desc", "Быстрее меняет полосу.", "Changes lanes faster.", "Yo‘lakni tezroq almashtiradi.");
        Add("char.ranger", "Следопыт", "Ranger", "Izquvar");
        Add("char.ranger.desc", "Монеты приносят на 50% больше очков.", "Coins are worth 50% more.", "Tangalar 50% ko‘proq ochko beradi.");
        Add("char.alchemist", "Алхимик", "Alchemist", "Kimyogar");
        Add("char.alchemist.desc", "+5 секунд на старте и +3 секунды на каждом чекпоинте.", "+5 seconds at the start and +3 seconds at every checkpoint.", "Startda +5 soniya va har bir nazorat nuqtasida +3 soniya.");
        Add("char.pyro", "Пиро", "Pyro", "Olovchi");
        Add("char.pyro.desc", "Столкновения замедляют вдвое слабее.", "Collisions slow you down half as much.", "To‘qnashuvlar ikki baravar kamroq sekinlashtiradi.");

        Add("stat.move", "Скорость смены полосы  +{0}%", "Lane-change speed  +{0}%", "Yo‘lak almashtirish tezligi  +{0}%");
        Add("stat.coin", "Очки за монеты  +{0}%", "Coin score  +{0}%", "Tanga ochkosi  +{0}%");
        Add("stat.start", "Время на старте  +{0} с", "Start time  +{0} s", "Boshlang‘ich vaqt  +{0} s");
        Add("stat.checkpoint", "Время на чекпоинте  +{0} с", "Checkpoint time  +{0} s", "Nazorat nuqtasida vaqt  +{0} s");
        Add("stat.hit", "Замедление от удара  -{0}%", "Hit slowdown  -{0}%", "Zarbadan sekinlashish  -{0}%");
        Add("stat.none", "Без бонусов, но и без слабостей", "No bonuses, but no weaknesses", "Bonus yo‘q, lekin zaif tomon ham yo‘q");
    }
}
