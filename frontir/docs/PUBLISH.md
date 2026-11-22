# Публикация World Conquer — полная инструкция

Всё, что делается руками в Creator Hub и Studio (кодом это сделать нельзя). Порядок — сверху вниз. Название игры —
**World Conquer** (логотип в главном меню уже с этим названием). Проверка после публикации — `docs/STUDIO_CHECK.md`
и F4 «Самопроверка».

## 0. Перед всем — резервная копия

Папка проекта не в git. Скопируйте всю папку `frontir` в другое место (или на внешний диск / в облако) **до**
публикации — одно неудачное действие в Studio или в папке иначе не откатить.

## 1. Проверки кода

Из папки `frontir/`, всё должно быть зелёным:

```bash
lune run tests
stylua --check src tests tools
selene src tests tools
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform=roblox --definitions:@roblox=types/globalTypes.d.luau --sourcemap=sourcemap.json --base-luaurc=.luaurc src tests tools
```

В `src/shared/Config.luau` → `Config.Dev` всё выключено: `PhoneLayout = false`, `PhoneScreenW / H = 0`, `ForceLang`,
`Map`, `BotLevel`, `Mode`, `Role` — пустые строки, `PrivateServer = false`, `Nations = 0`.

## 2. Страница игры: название, описание, жанр

Creator Hub → **Creations** → игра → **Configure** (Basic Settings).

| Поле | Что вписать |
|---|---|
| Name | `World Conquer` |
| Description | текст ниже (EN — основной; RU — в переводы, см. ниже) |
| Genre | Strategy |
| Devices | Computer, Phone, Tablet (игра сделана и под телефон) |
| Max Players | см. раздел 3 |

**Описание (EN, основное):**

```
Build a nation from a single city and conquer the world map — against bots or with up to 60 players.

⚔️ Living fronts: send troops, push the line, encircle armies in pockets, take enemy capitals.
🏭 Economy: factories, oil, cities, railways with trains, rivers and sea lines between your ports.
🚢 Navy and air force: landings, raids, missiles — and air defense to stop them.
🤝 Diplomacy: pacts, alliances with full trust, trade, embargo, betrayal, the World Council.
🎖️ Commanders with unique abilities, a tech tree, match tasks, trophies and a dramatic finale.
🏆 Commander Path: 100 levels of rewards on free and premium tracks.

Modes: Free for all, Teams, Blitz, Mist, Superweapon, Capital hunt, Duel, Flood.
New? Start with the Tutorial in the main menu. Plays on PC and phone.
```

**Описание (RU):**

```
Вырасти державу из одного города и завоюй карту мира — против ботов или вместе с 60 игроками.

⚔️ Живые фронты: веди войска, двигай линию, бери армии в котлы, захватывай столицы врагов.
🏭 Экономика: заводы, нефть, города, железные дороги с поездами, реки и морские линии между портами.
🚢 Флот и авиация: десанты, налёты, ракеты — и ПВО, чтобы их сбивать.
🤝 Дипломатия: пакты, союзы с полным доверием, торговля, эмбарго, предательство, Совет держав.
🎖️ Генералы с особыми способностями, технологии, задачи матча, трофеи и напряжённый финал.
🏆 Путь командира: 100 уровней наград — бесплатная и премиум-дорога.

Режимы: Каждый сам за себя, Команды, Блиц, Мгла, Супероружие, Охота на столицы, Дуэль, Потоп.
Впервые? Начни с «Обучения» в главном меню. Играется на ПК и телефоне.
```

Русский текст — в **Localization** (Creator Hub → игра → Localization → язык Russian → перевод названия и
описания); название можно оставить `World Conquer` и по-русски. Если в Basic Settings описание не помещается в
лимит поля — сократите строки с эмодзи, начало оставьте как есть: первые две строки видят чаще всего.

**Значок и кадры** (Creator Hub → игра → **Places → стартовое место (хаб) → Thumbnails / Icon**):
- значок 512×512 — логотип World Conquer на фоне карты;
- 2–3 кадра 1920×1080 из Studio: карта «Европа», идёт война — видны фронты, корабли, самолёты, поезда.

## 3. Настройки игры

Studio → **File → Game Settings** (или Creator Hub → игра → Configure):

| Где | Что | Зачем |
|---|---|---|
| Security → **Allow Mesh / Image APIs** | **вкл.** | карта и мини-карта рисуются в `EditableImage`; **без этого вместо карты — ошибка** |
| Security → **Enable Studio Access to API Services** | вкл. | профиль, покупки, лидеры работают и в Studio |
| Avatar | ничего | персонажи выключены, игра 2D |

**Два места.** Игра — из двух мест: **хаб** (главное меню, стартовое место, id `4316252648`) и **матч**
(id `135440328929805`); id уже в `Config.Places`. В оба места публикуется **один и тот же проект** — сервер сам
узнаёт роль по id места. Размер сервера (Places → место → Settings → Server Size): хаб — **50**, матч — **60**.
Переход хаб → матч в Studio не работает (ограничение Roblox) — проверять только в опубликованной игре.

DataStore и MemoryStore создаются сами, руками ничего заводить не нужно.

## 4. Публикация обоих мест

Для **каждого** места по очереди (сначала матч, потом хаб):

1. Creator Hub → игра → **Places** → место → **Edit in Studio**.
2. В папке проекта: `rojo serve`; в Studio — плагин Rojo → **Connect** (дождаться, пока синхронизируется).
3. Studio → **File → Publish to Roblox**.

Сверка: в Studio `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayer.StarterPlayerScripts.Client`
есть и не пустые; при запуске (Play) нет красных ошибок в Output.

## 5. Закрытый тест

- Игра остаётся **Private** (не Public), пока идёт закрытый тест.
- Доступ тестерам — в Creator Hub → игра → настройки доступа: через **группу** (игра в группе, тестерам — роль с
  правом играть) или через **участников проекта** (Collaborators). Точные названия пунктов меню Roblox меняет —
  ищите раздел доступа (Access / Permissions) у игры.
- Попросите тестеров сыграть: «Обучение», матч против ботов, матч вместе, с ПК и с телефона; ошибки — скриншотом.
- Что смотреть в аналитике после теста — `docs/LIVE_TEST.md`.

## 6. Звуки и музыка

Roblox играет только загруженные звуки; пока id нет — в игре тихо (код к звуку готов).

Файлы: музыка `assets/audio/music/Menu.mp3`, `Match.mp3`, `War.mp3` (меню, матч, война); звуки
`assets/audio/sfx/*.wav` — 17 штук: Click, Error, Capture, Province, Battle, Explosion, Plane, Parachute, Siren,
Offer, Betrayal, Victory, Defeat, Notify, Coin, Hire, Build.

Два способа:
1. **Через Config:** Creator Hub → Creations → **Audio → Import** (WAV не примут — сконвертируйте в OGG/MP3).
   Дождитесь модерации, скопируйте id и впишите как `"rbxassetid://123456"` в `Config.Music.<Menu|Match|War>.id`
   и `Config.Sounds.<Имя>.id`. Потом снова опубликуйте оба места (раздел 4).
2. **Без кода:** в Studio создайте папку `SoundService/FrontirAudio` и положите туда `Sound` с именем звука
   (`Click`, `Siren`, `Menu`, `War`…). Такой `Sound` важнее id из Config. Делать в **обоих** местах.

Проверка — F4 «Звуки по очереди» и «Музыка: следующая».

## 7. Товары (можно позже — для закрытого теста не обязательно)

Пока у товара `id = 0`, он не продаётся, кнопка пишет «Скоро». Creator Hub → игра → **Monetization**. Создайте
товар с ценой из таблицы, скопируйте id и впишите в поле `id` той же строки `src/shared/Config.luau`, затем снова
опубликуйте оба места.

**Passes** (геймпассы) → `Config.Shop.Passes.<Ключ>.id`:

| Ключ | Название | Цена |
|---|---|---|
| `HQ` | Штаб | 399 |
| `Intel` | Разведуправление | 249 |
| `Vip` | VIP | 299 |
| `AllCommanders` | Все генералы | 199 |

**Developer Products** → `Config.Shop.Boosts.<Ключ>.id`:

| Ключ | Название | Цена |
|---|---|---|
| `Mobilize` | Мобилизация | 49 |
| `Loan` | Военный заём | 39 |
| `Research` | Срочное исследование | 29 |
| `Reserve` | Резерв генерала | 25 |
| `Guards` | Гвардия | 59 |
| `Airstrike` | Авиаудар | 45 |
| `Squadron` | Эскадра | 49 |
| `AirWing` | Авиакрыло | 49 |

**Developer Products** → `Config.Shop.Packs.<Ключ>.id`:

| Ключ | Название | Цена |
|---|---|---|
| `Recruit` | Набор новобранца | 99 |
| `Medals` | Медали | 79 |
| `Tokens` | Жетоны штаба | 99 |
| `Crate1` | Ящик снабжения | 49 |
| `Crate5` | 5 ящиков | 199 |
| `PathPremium` | Премиум-дорога «Пути командира» | 499 |
| `PathPremiumPlus` | Премиум-дорога + 10 уровней | 699 |
| `Weekly` | Предложение недели | 119 |
| `Levels5` | +5 уровней «Пути» | 149 |
| `XpBoost1` | Опыт ×2 на сутки | 79 |
| `XpBoost7` | Опыт ×2 на неделю | 249 |
| `ParadeSet` | Парадный набор | 249 |

**Developer Products** → `Config.Unlocks.Items.<Ключ>.id` и `Config.Unlocks.All.id` (техника и разведка навсегда):

| Ключ | Название | Цена |
|---|---|---|
| `Tanks` | Танки | 99 |
| `Intel` | Разведка | 79 |
| `Artillery` | Артиллерия | 99 |
| `AntiAir` | ПВО (зенитки) | 79 |
| `Missile` | Ракетная шахта | 149 |
| `All` (`Config.Unlocks.All`) | Вся техника | 299 |

Описание товара — коротко, как в магазине игры (`Strings`, ключи `shop.*`); значок — 512×512 (можно без него).

## 8. Возрастной рейтинг (Experience Questionnaire)

Creator Hub → игра → **Audience → Questionnaire** (без анкеты игру видят не все). Отвечать честно:

- **Насилие:** есть — бои на стратегической карте (пиксельные юниты, взрывы), без крови и без людей крупным планом.
- **Кровь, страх, грубые шутки, алкоголь, азарт на реальные деньги:** нет.
- **Платные случайные награды:** **да** — «Ящик снабжения» и «5 ящиков» за Robux (см. раздел 9).
- **Общение:** стандартный чат Roblox; в игре — метки на карте и готовые фразы (без своего текста).
- **Реальные страны и политика:** нет — державы вымышленные, карты — только рельеф.

## 9. Ящики и правила Roblox о платных случайных наградах

Уже сделано в коде:

| Правило | Как в игре |
|---|---|
| Шансы видны **до** покупки | окно магазина, «Ящики снабжения»: проценты из `Config.Crates.Table` |
| Гарантия | не позже `Config.Crates.Pity`-го ящика подряд — джекпот, счётчик «до гарантии» |
| Страны с запретом | `PolicyService` → `ArePaidRandomItemsRestricted`: ящики не продаются, вместо кнопки — «Недоступно в вашем регионе» |
| Косвенные покупки | ящики из платных наборов в таких странах заменяются фиксированной наградой (`Config.Crates.Restricted`) |
| Бесплатные ящики | ежедневная награда и бесплатная дорога «Пути» — ящики остаются |
| Без давящих таймеров | «Предложение недели» меняется по настоящему календарю |

## 10. После публикации

1. Зайдите в опубликованную игру (хаб): главное меню, «Обучение», «Играть одному», «В БОЙ» (переход в матч).
2. В матче — F4 работает только в Studio; в опубликованной игре пройдите глазами `docs/STUDIO_CHECK.md`.
3. Проверьте с телефона: полоса команд, окна, удары — всё пальцем.
4. Когда закрытый тест пройден и звуки и товары заполнены — Experience → **Public**.
