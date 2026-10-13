using System.Collections.Generic;
using UnityEngine;

namespace Shatranj.Core
{
    /// <summary>Локализация: O'zbek (lotin) / Русский / English.</summary>
    public static class Loc
    {
        public static Language Current = Language.Uzbek;

        static readonly Dictionary<string, string[]> T3 = new Dictionary<string, string[]>
        {
            // ---------------------------------------------------------------- Общее
            { "app.title", new[] { "SHATRANJ", "ШАТРАНДЖ", "SHATRANJ" } },
            { "app.subtitle", new[] { "Samarqand afsonasi", "Легенда Самарканда", "The Legend of Samarkand" } },
            { "loading", new[] { "Yuklanmoqda...", "Загрузка...", "Loading..." } },
            { "common.back", new[] { "Orqaga", "Назад", "Back" } },
            { "common.yes", new[] { "Ha", "Да", "Yes" } },
            { "common.no", new[] { "Yo'q", "Нет", "No" } },
            { "common.ok", new[] { "Yaxshi", "ОК", "OK" } },
            { "common.start", new[] { "Jangni boshlash", "В бой!", "To battle!" } },
            { "common.soon", new[] { "Tez kunda", "Скоро", "Coming soon" } },
            { "common.on", new[] { "Yoq", "Вкл", "On" } },
            { "common.off", new[] { "O'chiq", "Выкл", "Off" } },
            { "version", new[] { "Versiya", "Версия", "Version" } },

            // ---------------------------------------------------------------- Главное меню
            { "menu.continue", new[] { "Davom etish", "Продолжить", "Continue" } },
            { "menu.newgame", new[] { "Yangi o'yin", "Новая игра", "New game" } },
            { "menu.settings", new[] { "Sozlamalar", "Настройки", "Settings" } },
            { "menu.rules", new[] { "Qoidalar", "Правила", "How to play" } },
            { "menu.museum", new[] { "Afrosiyob muzeyi", "Музей Афросиаба", "Afrosiyob Museum" } },
            { "menu.stats", new[] { "Statistika", "Статистика", "Statistics" } },
            { "menu.exit", new[] { "Chiqish", "Выход", "Exit" } },
            { "confirm.exit", new[] { "O'yindan chiqasizmi?", "Выйти из игры?", "Quit the game?" } },

            // ---------------------------------------------------------------- Новая игра
            { "ng.mode", new[] { "O'yin turi", "Режим", "Mode" } },
            { "mode.pvp", new[] { "Ikki o'yinchi", "Два игрока", "Two players" } },
            { "mode.pvp.desc", new[] { "Bitta qurilmada, navbatma-navbat", "На одном устройстве, по очереди", "One device, taking turns" } },
            { "mode.ai", new[] { "Kompyuterga qarshi", "Против компьютера", "Versus computer" } },
            { "ng.variant", new[] { "Qoidalar", "Правила", "Rules" } },
            { "variant.classic", new[] { "Klassik shaxmat", "Классические шахматы", "Classic chess" } },
            { "variant.afrosiyob", new[] { "Qadimiy shatranj", "Древний шатрандж", "Ancient shatranj" } },
            { "variant.classic.desc", new[] { "Zamonaviy xalqaro qoidalar", "Современные международные правила", "Modern international rules" } },
            { "variant.afrosiyob.desc", new[] {
                "Afrosiyob davri qoidalari: Farzin va Fil qisqa yuradi, pat — g'alaba",
                "Правила эпохи Афросиаба: Фарзин и Фил ходят коротко, пат — победа",
                "Rules of the Afrosiyob era: short-moving Farzin and Fil, stalemate wins" } },
            { "ng.time", new[] { "Vaqt nazorati", "Контроль времени", "Time control" } },
            { "time.unlimited", new[] { "Cheksiz", "Без часов", "Unlimited" } },
            { "time.min", new[] { "daq", "мин", "min" } },
            { "ng.white", new[] { "Oq tomon", "Белые", "White" } },
            { "ng.black", new[] { "Qora tomon", "Чёрные", "Black" } },
            { "ng.name.hint", new[] { "Ism kiriting", "Введите имя", "Enter a name" } },
            { "side.white", new[] { "Oq", "Белые", "White" } },
            { "side.black", new[] { "Qora", "Чёрные", "Black" } },

            // ---------------------------------------------------------------- Настройки
            { "set.language", new[] { "Til", "Язык", "Language" } },
            { "set.music", new[] { "Musiqa", "Музыка", "Music" } },
            { "set.sfx", new[] { "Ovozlar", "Звуки", "Sound effects" } },
            { "set.vibration", new[] { "Tebranish", "Вибрация", "Vibration" } },
            { "set.showmoves", new[] { "Yurishlarni ko'rsatish", "Подсказка ходов", "Show legal moves" } },
            { "set.coords", new[] { "Koordinatalar", "Координаты", "Coordinates" } },
            { "set.autorotate", new[] { "Doskani burish", "Поворот доски", "Rotate board" } },
            { "set.cinematic", new[] { "Kino kamera", "Кинокамера", "Cinematic camera" } },
            { "set.battle", new[] { "Jang sahnalari", "Сцены боя", "Battle scenes" } },
            { "battle.full", new[] { "To'liq", "Полные", "Full" } },
            { "battle.fast", new[] { "Tezkor", "Быстрые", "Fast" } },
            { "battle.off", new[] { "O'chiq", "Выкл", "Off" } },
            { "set.ambience", new[] { "Vaqt", "Время суток", "Time of day" } },
            { "amb.day", new[] { "Kunduz", "День", "Day" } },
            { "amb.sunset", new[] { "Shom", "Закат", "Sunset" } },
            { "amb.night", new[] { "Tun", "Ночь", "Night" } },
            { "set.quality", new[] { "Grafika", "Графика", "Graphics" } },
            { "q.low", new[] { "Past", "Низкая", "Low" } },
            { "q.med", new[] { "O'rta", "Средняя", "Medium" } },
            { "q.high", new[] { "Yuqori", "Высокая", "High" } },

            // ---------------------------------------------------------------- HUD
            { "hud.turn", new[] { "{0} yuradi", "Ход: {0}", "{0} to move" } },
            { "hud.menu", new[] { "Menyu", "Меню", "Menu" } },
            { "hud.undo", new[] { "Qaytarish", "Отмена", "Undo" } },
            { "hud.view", new[] { "Burish", "Вид", "View" } },
            { "hud.check", new[] { "SHAX!", "ШАХ!", "CHECK!" } },
            { "hud.mate", new[] { "MOT!", "МАТ!", "CHECKMATE!" } },
            { "hud.hero", new[] { "PAHLAVON!", "ПАХЛАВОН!", "PAHLAVON!" } },
            { "hud.hero.desc", new[] { "{0} uchinchi g'alabasini qozondi", "{0} одержал третью победу", "{0} won a third duel" } },
            { "hud.promoted", new[] { "{0} — yangi unvon!", "{0} — новое звание!", "{0} — promoted!" } },
            { "hud.material", new[] { "+{0}", "+{0}", "+{0}" } },
            { "hud.moves", new[] { "Yurishlar", "Ходы", "Moves" } },
            { "hud.flag", new[] { "Vaqt tugadi!", "Время вышло!", "Time is up!" } },

            // ---------------------------------------------------------------- Пауза и подтверждения
            { "pause.title", new[] { "Tanaffus", "Пауза", "Paused" } },
            { "pause.resume", new[] { "Davom etish", "Продолжить", "Resume" } },
            { "pause.undo", new[] { "Yurishni qaytarish", "Отменить ход", "Undo move" } },
            { "pause.draw", new[] { "Durang taklif qilish", "Предложить ничью", "Offer a draw" } },
            { "pause.resign", new[] { "Taslim bo'lish", "Сдаться", "Resign" } },
            { "pause.restart", new[] { "Qaytadan boshlash", "Начать заново", "Restart" } },
            { "pause.menu", new[] { "Bosh menyu", "Главное меню", "Main menu" } },
            { "confirm.resign", new[] { "{0}, rostdan ham taslim bo'lasizmi?", "{0}, вы действительно сдаётесь?", "{0}, do you really resign?" } },
            { "confirm.draw", new[] { "{0} durang taklif qilmoqda.\n{1}, rozimisiz?", "{0} предлагает ничью.\n{1}, вы согласны?", "{0} offers a draw.\n{1}, do you accept?" } },
            { "confirm.restart", new[] { "O'yinni qaytadan boshlaysizmi?", "Начать партию заново?", "Restart the game?" } },
            { "confirm.menu", new[] { "Bosh menyuga chiqasizmi?\nO'yin saqlanadi.", "Выйти в главное меню?\nПартия будет сохранена.", "Exit to the main menu?\nThe game will be saved." } },
            { "draw.declined", new[] { "Durang rad etildi", "Ничья отклонена", "Draw declined" } },
            { "promo.title", new[] { "Sarboz kim bo'ladi?", "Кем станет сарбоз?", "Promote your Sarboz" } },

            // ---------------------------------------------------------------- Конец партии
            { "over.winner", new[] { "{0} g'alaba qozondi!", "{0}: победа!", "{0} wins!" } },
            { "over.draw", new[] { "Durang!", "Ничья!", "Draw!" } },
            { "over.moves", new[] { "Yurishlar soni: {0}", "Ходов: {0}", "Moves: {0}" } },
            { "over.rematch", new[] { "Revansh", "Реванш", "Rematch" } },
            { "over.view", new[] { "Doskani ko'rish", "Посмотреть доску", "View board" } },
            { "over.result", new[] { "Natija", "Итог", "Result" } },
            { "reason.Checkmate", new[] { "Mot", "Мат", "Checkmate" } },
            { "reason.Stalemate", new[] { "Pat", "Пат", "Stalemate" } },
            { "reason.StalemateWin", new[] { "Pat — qadimiy qoida bo'yicha g'alaba", "Пат — победа по древним правилам", "Stalemate — a win by ancient rules" } },
            { "reason.BareKing", new[] { "Yolg'iz qolgan shoh", "Голый король", "Bare king" } },
            { "reason.Resignation", new[] { "Raqib taslim bo'ldi", "Соперник сдался", "Resignation" } },
            { "reason.Timeout", new[] { "Vaqt tugadi", "Время вышло", "Time out" } },
            { "reason.Agreement", new[] { "Kelishuv bo'yicha", "По соглашению", "By agreement" } },
            { "reason.FiftyMove", new[] { "50 yurish qoidasi", "Правило 50 ходов", "Fifty-move rule" } },
            { "reason.Repetition", new[] { "Uch marta takrorlanish", "Троекратное повторение", "Threefold repetition" } },
            { "reason.InsufficientMaterial", new[] { "Mot qilishga kuch yetmaydi", "Недостаточно материала", "Insufficient material" } },

            // ---------------------------------------------------------------- Статистика
            { "stats.played", new[] { "O'ynalgan o'yinlar", "Сыграно партий", "Games played" } },
            { "stats.white", new[] { "Oq g'alabalari", "Побед белых", "White wins" } },
            { "stats.black", new[] { "Qora g'alabalari", "Побед чёрных", "Black wins" } },
            { "stats.draws", new[] { "Duranglar", "Ничьих", "Draws" } },
            { "stats.captures", new[] { "Qilich zarbalari", "Ударов мечом", "Sword strikes" } },
            { "stats.heroes", new[] { "Pahlavonlar", "Пахлавонов", "Pahlavons" } },
            { "stats.fastest", new[] { "Eng tez mot (yurish)", "Самый быстрый мат (ходов)", "Fastest mate (moves)" } },
            { "stats.afro", new[] { "Qadimiy shatranj o'yinlari", "Партий в древний шатрандж", "Ancient shatranj games" } },
            { "stats.reset", new[] { "Statistikani tozalash", "Сбросить статистику", "Reset statistics" } },
            { "stats.reset.confirm", new[] { "Barcha natijalar o'chirilsinmi?", "Удалить все результаты?", "Erase all results?" } },

            // ---------------------------------------------------------------- Фигуры
            { "piece.King", new[] { "Shoh", "Шох (Король)", "Shoh (King)" } },
            { "piece.Queen", new[] { "Farzin", "Фарзин (Ферзь)", "Farzin (Queen)" } },
            { "piece.Rook", new[] { "Rux", "Рух (Ладья)", "Rukh (Rook)" } },
            { "piece.Bishop", new[] { "Fil", "Фил (Слон)", "Fil (Bishop)" } },
            { "piece.Knight", new[] { "Ot", "От (Конь)", "Ot (Knight)" } },
            { "piece.Pawn", new[] { "Piyoda", "Пиёда (Пешка)", "Piyoda (Pawn)" } },

            { "hero.King", new[] { "Amir — hukmdor", "Амир — повелитель", "Amir — the Ruler" } },
            { "hero.Queen", new[] { "Vazir — sarkarda", "Визирь — полководец", "Vizier — the Commander" } },
            { "hero.Rook", new[] { "Qal'a posboni", "Страж крепости", "Fortress Guardian" } },
            { "hero.Bishop", new[] { "Jangovar fil", "Боевой слон", "War Elephant" } },
            { "hero.Knight", new[] { "Chavandoz", "Чавандоз — всадник", "Chavandoz — the Rider" } },
            { "hero.Pawn", new[] { "Sarboz", "Сарбоз — воин", "Sarboz — the Soldier" } },

            { "lore.King", new[] {
                "Toj kiygan Amir Samarqand taxtining egasi. U qulasa — saltanat quladi. Shuning uchun uni har bir askar o'z jonidan aziz bilib qo'riqlaydi.",
                "Амир в короне — владыка самаркандского трона. Падёт он — падёт и держава, поэтому каждый воин бережёт его пуще жизни.",
                "The crowned Amir rules the throne of Samarkand. If he falls, the realm falls — so every warrior guards him above all else." } },
            { "lore.Queen", new[] {
                "Dono vazir va qo'mondon. Qadimiy shatranjda u faqat bir qadam yurgan, bugun esa butun maydon uniki.",
                "Мудрый визирь и полководец. В древнем шатрандже он ступал лишь на одно поле, а сегодня ему подвластно всё поле боя.",
                "Wise vizier and commander. In ancient shatranj he moved a single step; today the whole battlefield is his." } },
            { "lore.Rook", new[] {
                "Ichan qal'a devorlaridek mustahkam minora va uning posboni. Ochiq yo'lda unga teng keladigan kuch yo'q.",
                "Башня, крепкая, как стены Ичан-Калы, и её страж. На открытой линии ему нет равных.",
                "A tower as firm as the walls of Itchan Kala, and its guardian. On an open file he has no equal." } },
            { "lore.Bishop", new[] {
                "Ustida feruza gumbazli kajava bilan jangovar fil. Afrosiyob donalari orasida ham fil bor edi.",
                "Боевой слон с бирюзовым куполом-паланкином. Слон был и среди фигур, найденных на Афросиабе.",
                "A war elephant carrying a turquoise-domed howdah. An elephant was among the chessmen found at Afrosiyob." } },
            { "lore.Knight", new[] {
                "Ko'pkari ustasi, telpakli chavandoz. U to'siqlardan sakrab o'tadi va kutilmagan tomondan zarba beradi.",
                "Мастер кўпкари, всадник в тельпаке. Перепрыгивает через преграды и бьёт с неожиданной стороны.",
                "A master of kupkari in a fur telpak. He leaps over obstacles and strikes from where no one expects." } },
            { "lore.Pawn", new[] {
                "Do'ppi kiygan oddiy sarboz. Kichik, ammo jasur: oxirgi qatorga yetsa — sarkardaga aylanadi.",
                "Простой сарбоз в тюбетейке. Мал, да удал: дойдя до последней линии, становится полководцем.",
                "A humble soldier in a do'ppi. Small but brave: reaching the last rank, he becomes a commander." } },

            { "move.King", new[] { "Istalgan tomonga bir qadam. Rokirovka mumkin.", "На одно поле в любую сторону. Есть рокировка.", "One step in any direction. Can castle." } },
            { "move.Queen", new[] { "Istalgan yo'nalishda istalgancha. (Qadimiy: diagonal bo'ylab bir qadam.)", "В любом направлении на любое расстояние. (Древние правила: на одно поле по диагонали.)", "Any distance in any direction. (Ancient: one step diagonally.)" } },
            { "move.Rook", new[] { "To'g'ri chiziq bo'ylab istalgancha.", "По прямой на любое расстояние.", "Any distance in a straight line." } },
            { "move.Bishop", new[] { "Diagonal bo'ylab istalgancha. (Qadimiy: diagonal bo'ylab aynan 2 katakka sakraydi.)", "По диагонали на любое расстояние. (Древние правила: прыжок ровно на 2 поля по диагонали.)", "Any distance diagonally. (Ancient: jumps exactly 2 squares diagonally.)" } },
            { "move.Knight", new[] { "«G» harfi shaklida sakraydi.", "Прыгает буквой «Г».", "Jumps in an L-shape." } },
            { "move.Pawn", new[] { "Oldinga bir qadam, qiyalab uradi. (Qadimiy: ikki qadam yo'q, faqat Farzinga aylanadi.)", "Вперёд на одно поле, бьёт наискосок. (Древние правила: без двойного хода, превращается только в Фарзина.)", "One step forward, captures diagonally. (Ancient: no double step, promotes only to Farzin.)" } },

            { "museum.attack", new[] { "Hujum!", "Атака!", "Attack!" } },
            { "museum.side", new[] { "Tomonni almashtirish", "Сменить сторону", "Switch side" } },
            { "museum.hint", new[] { "Aylantirish uchun suring", "Проведите пальцем, чтобы повернуть", "Swipe to rotate" } },
            { "museum.moves", new[] { "Yurishi", "Как ходит", "Movement" } },

            // ---------------------------------------------------------------- Правила
            { "rules.goal.t", new[] { "Maqsad", "Цель", "Goal" } },
            { "rules.goal", new[] {
                "Raqib Shohiga mot qiling: shoh hujum ostida va qochishga joyi yo'q. Har bir urish — haqiqiy qilich jangi: hujumchi raqibga yaqinlashib, qilich bilan uradi va yog'och qahramon parchalanib ketadi.",
                "Поставьте мат вражескому Шоху: он под ударом, и ему некуда уйти. Каждое взятие — настоящий поединок: нападающий подходит к врагу, бьёт мечом, и деревянный воин разлетается на куски.",
                "Checkmate the enemy Shoh: he is attacked and has nowhere to go. Every capture is a real sword duel: the attacker closes in, strikes, and the wooden warrior shatters." } },
            { "rules.controls.t", new[] { "Boshqaruv", "Управление", "Controls" } },
            { "rules.controls", new[] {
                "Donani tanlash uchun unga bosing, so'ng nuqta bilan belgilangan katakni bosing. Bir barmoq bilan surib — kamerani aylantiring, ikki barmoq bilan — yaqinlashtiring.",
                "Нажмите на фигуру, затем на подсвеченную клетку. Проведите одним пальцем — повернуть камеру, двумя — приблизить.",
                "Tap a piece, then tap a highlighted square. Drag with one finger to orbit the camera, pinch with two to zoom." } },
            { "rules.special.t", new[] { "Maxsus yurishlar", "Особые ходы", "Special moves" } },
            { "rules.special", new[] {
                "Rokirovka: Shoh va Rux bir yurishda joy almashadi. O'tib ketayotganni urish: ikki qadam yurgan piyodani qo'shni piyoda urishi mumkin. Piyoda oxirgi qatorga yetsa — istalgan donaga aylanadi.",
                "Рокировка: Шох и Рух меняются местами за один ход. Взятие на проходе: пешку, шагнувшую на два поля, может взять соседняя пешка. Пешка на последней линии превращается в любую фигуру.",
                "Castling: the Shoh and a Rukh move together in one turn. En passant: a pawn that advanced two squares can be captured by a neighbouring pawn. A pawn reaching the last rank promotes to any piece." } },
            { "rules.hero.t", new[] { "Pahlavon unvoni", "Звание Пахлавон", "The Pahlavon title" } },
            { "rules.hero", new[] {
                "Uchta raqibni yenggan har qanday dona «Pahlavon» unvonini oladi va oltin nur bilan porlaydi. Bu qoidalarga ta'sir qilmaydi, ammo shon-shuhrat abadiy!",
                "Любая фигура, победившая трёх врагов, получает звание «Пахлавон» и сияет золотом. На правила это не влияет, но слава — навеки!",
                "Any piece that defeats three enemies earns the Pahlavon title and glows with gold. It doesn't change the rules, but the glory is eternal!" } },
            { "rules.afro.t", new[] { "Qadimiy shatranj", "Древний шатрандж", "Ancient shatranj" } },
            { "rules.afro", new[] {
                "1977-yilda Samarqanddagi Afrosiyob tepaligida VII–VIII asrlarga oid shaxmat donalari topilgan — ular dunyodagi eng qadimiylaridan. Bu rejimda o'sha davr qoidalari: Farzin diagonal bo'ylab 1 qadam, Fil diagonal bo'ylab aynan 2 katakka sakraydi, piyoda faqat 1 qadam yuradi va Farzinga aylanadi, rokirovka yo'q. Raqibni pat qilish yoki uning barcha donalarini olib, Shohini yolg'iz qoldirish — g'alaba!",
                "В 1977 году на городище Афросиаб в Самарканде нашли шахматные фигуры VII–VIII веков — одни из древнейших в мире. В этом режиме действуют правила той эпохи: Фарзин ходит на 1 поле по диагонали, Фил прыгает ровно на 2 поля по диагонали, пешка ходит только на 1 поле и превращается в Фарзина, рокировки нет. Пат сопернику или «голый король» (у врага остался один Шох) — победа!",
                "In 1977 chessmen from the 7th–8th centuries — among the oldest in the world — were found at the Afrosiyob site in Samarkand. This mode uses the rules of that era: the Farzin moves 1 square diagonally, the Fil jumps exactly 2 squares diagonally, pawns move 1 square and promote only to Farzin, and there is no castling. Stalemating your opponent or leaving them with a bare king wins!" } },
            { "rules.draw.t", new[] { "Durang", "Ничья", "Draws" } },
            { "rules.draw", new[] {
                "Pat (klassikada), uch marta takrorlanish, 50 yurish qoidasi, mot uchun kuch yetmasligi yoki kelishuv.",
                "Пат (в классике), троекратное повторение, правило 50 ходов, недостаточно материала или соглашение.",
                "Stalemate (classic), threefold repetition, the fifty-move rule, insufficient material, or agreement." } },
            { "rules.about.t", new[] { "O'yin haqida", "Об игре", "About" } },
            { "rules.about", new[] {
                "Barcha 3D modellar, naqshlar, musiqa (dutor va doira) va ovozlar o'yin ichida protsedura usulida yaratiladi. Ilhom manbai: Registon, Ichan qal'a, suzana, adras va Chust do'ppisi.",
                "Все 3D-модели, узоры, музыка (дутар и дойра) и звуки создаются процедурно прямо в игре. Вдохновение: Регистан, Ичан-Кала, сюзане, адрас и чустская тюбетейка.",
                "All 3D models, patterns, music (dutar and doira) and sounds are generated procedurally in-game. Inspired by the Registan, Itchan Kala, suzani, adras silk and the Chust do'ppi." } },

            // ---------------------------------------------------------------- Мудрость (мақоллар)
            { "proverb.0", new[] { "«Yetti o'lchab, bir kes.»", "«Семь раз отмерь — один раз отрежь.» (узб. пословица)", "“Measure seven times, cut once.” (Uzbek proverb)" } },
            { "proverb.1", new[] { "«Sabr tagi — sariq oltin.»", "«Терпение — чистое золото.» (узб. пословица)", "“Patience is pure gold.” (Uzbek proverb)" } },
            { "proverb.2", new[] { "«Kuch — adolatdadir.» — Amir Temur", "«Сила — в справедливости.» — Амир Темур", "“Strength lies in justice.” — Amir Temur" } },
            { "proverb.3", new[] { "«Aql yoshda emas — boshda.»", "«Ум не в годах, а в голове.» (узб. пословица)", "“Wisdom is not in age, but in the head.” (Uzbek proverb)" } },
            { "proverb.4", new[] { "«Birlashgan o'zar, birlashmagan to'zar.»", "«Сплочённые побеждают, разобщённые рассыпаются.» (узб. пословица)", "“The united prevail, the divided scatter.” (Uzbek proverb)" } },
            { "proverb.5", new[] { "«Sabr qilsang, g'o'radan holva bitar.»", "«Наберёшься терпения — из незрелого винограда выйдет халва.»", "“With patience, sour grapes turn into halva.” (Uzbek proverb)" } },
            { "proverb.6", new[] { "«Mehnatning tagi — rohat.»", "«За трудом приходит отрада.» (узб. пословица)", "“After toil comes delight.” (Uzbek proverb)" } },
            { "proverb.7", new[] { "«Yaxshi ot — yigitning qanoti.»", "«Добрый конь — крылья джигита.» (узб. пословица)", "“A good horse is a young man's wings.” (Uzbek proverb)" } },
            { "proverb.8", new[] { "«Do'st achitib gapirar, dushman — kuldirib.»", "«Друг говорит горькую правду, враг — сладкую ложь.»", "“A friend speaks bitter truth, a foe makes you laugh.” (Uzbek proverb)" } },
            { "proverb.9", new[] { "«Bilim — baxt kaliti.»", "«Знание — ключ к счастью.» (узб. пословица)", "“Knowledge is the key to happiness.” (Uzbek proverb)" } },
        };

        public const int ProverbCount = 10;

        public static string T(string key)
        {
            string[] v;
            if (T3.TryGetValue(key, out v)) return v[(int)Current];
            return key;
        }

        public static string T(string key, params object[] args)
        {
            try { return string.Format(T(key), args); }
            catch (System.FormatException) { return T(key); }
        }

        public static string RandomProverb()
        {
            return T("proverb." + Random.Range(0, ProverbCount));
        }

        public static string LanguageName(Language l)
        {
            switch (l)
            {
                case Language.Uzbek: return "O'zbekcha";
                case Language.Russian: return "Русский";
                default: return "English";
            }
        }
    }
}
