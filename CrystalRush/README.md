# Crystal Rush — мид-терм проект на Unity 6

3D-аркада: катай светящийся шар по арене, собирай кристаллы, обходи ловушки и успей в портал.
Интерфейс на трёх языках: **English / Русский / O‘zbekcha** (переключается в главном меню, выбор сохраняется).

- Движок: **Unity 6 (6000.3.x)**, шаблон **Universal 3D (URP)**, язык C#
- Платформы: PC (Windows/Mac) + Android (APK) или WebGL
- Управление: клавиатура (WASD / стрелки, Пробел — рывок, Esc — пауза) и экранный джойстик + кнопка «РЫВОК» на телефоне

> Паспорт игры на трёх языках — [Docs/GamePassport.md](Docs/GamePassport.md),
> план презентации — [Docs/Presentation.md](Docs/Presentation.md),
> ответы на вопросы защиты — [Docs/Defense.md](Docs/Defense.md).

---

## 1. Как запустить

Папка `CrystalRush` — это **готовый Unity-проект** (собран на основе официального шаблона Universal 3D для Unity 6000.3).

1. Скачайте репозиторий (кнопка **Code → Download ZIP** на GitHub для ветки `claude/loving-hypatia-1vtkqz`, или `git clone`)
   и положите папку `CrystalRush` туда, где в пути **нет кириллицы и пробелов**, например `C:\Unity\CrystalRush`.
2. **Unity Hub → Add → Add project from disk** → выберите папку `CrystalRush` → откройте в Unity **6000.3.x**.
3. Первое открытие: Unity скачает пакеты и импортирует проект (несколько минут). Затем **автоматически**
   запустится сборка игры (окно с прогрессом, 10–20 секунд) и появится окно «Done!».
   Инструмент сам создаст:
   - папки `Materials`, `Prefabs`, `Audio`, `Particles`, `Scenes`, `Textures`, `Models`;
   - текстуры, материалы, 3D-модели, частицы, звуки и музыку (всё генерируется кодом — без скачанных ассетов);
   - префабы, интерфейс, 4 сцены (`MainMenu`, `Level1`–`Level3`) и Build Settings;
   - Player Settings: название, иконку, Package Name `com.yourname.crystalrush`, альбомную ориентацию.
4. Откроется сцена `Assets/Scenes/MainMenu` — нажмите **Play**.

После обновления скриптов (git pull) Unity сам предложит пересобрать сцены.
Если автосборка не запустилась — меню **Crystal Rush → Build Game (create scenes, prefabs, sounds)**.
Этим же пунктом можно пересобрать всё заново в любой момент.
Если Hub предложит другую версию 6000.3.x — соглашайтесь, проект подходит для любой 6000.3.

Перед сдачей поменяйте `yourname` в Package Name и Company Name на своё имя
(Project Settings → Player, или константы в `Assets/Scripts/Editor/CrystalRushSetup.cs`).

Меню **Crystal Rush → Reset saved progress** сбрасывает рекорд, открытые уровни, язык и громкость.

## 2. Правила игры

- На уровне есть кристаллы. Собери **все** — откроется портал. Войди в открытый портал — уровень пройден.
- **3 жизни** и **таймер**. Касание опасности: −1 жизнь, отбрасывание и 1,5 с неуязвимости (шар мигает).
- Проигрыш: закончились жизни **или** вышло время → экран Game Over (игра на паузе, `Time.timeScale = 0`).
- Очки: +100 за кристалл, бонус за оставшееся время (+10 за секунду). Очки идут через все 3 уровня, рекорд сохраняется.
- Бонусы: зелёный крест — +1 жизнь, жёлтые часы — +10 секунд.
- **Рывок** (Пробел / кнопка): короткое ускорение, перезарядка 1,2 с — чтобы проскочить лазер.

### Опасности (3 типа, ведут себя по-разному)

| Опасность | Поведение | Как работает в коде |
|---|---|---|
| **Лазерный барьер** | Цикл: выключен → мигает (предупреждение) → горит. Опасен только когда горит | `LaserBarrier.cs`: таймер цикла, триггер луча включается только в фазе On |
| **Патрульный дрон** | Летает туда-обратно между двумя точками, твёрдый, толкает шар | `PatrolDrone.cs`: кинематический Rigidbody + `MovePosition` |
| **Шипы в полу** | Пластина светится оранжевым → шипы выезжают → прячутся | `SpikeTrap.cs`: фазы Hidden/Warning/Up, триггер только в фазе Up |

### Уровни (каждый сложнее)

| Уровень | Арена | Кристаллы | Лазеры | Дроны | Шипы | Время |
|---|---|---|---|---|---|---|
| 1 | 20×20 | 8 | 2 | 1 | 2 | 80 с |
| 2 | 24×24 | 12 | 3 (быстрее) | 3 | 4 | 95 с |
| 3 | 28×28 | 16 | 6 (ещё быстрее) | 5 | 7 | 110 с |

Раскладки уровней — обычные данные в `Assets/Scripts/Editor/SetupLevels.cs`: поменяйте число и снова запустите **Build Game**.

## 3. Архитектура

```
Assets/Scripts
├── Core/          GameManager (Singleton: жизни, время, очки, состояние раунда), SaveData (PlayerPrefs), GameScenes
├── Player/        PlayerController (движение + рывок, клавиатура И джойстик), PlayerCollision (теги, удары), VirtualJoystick
├── Obstacles/     LaserBarrier, PatrolDrone, SpikeTrap
├── Collectibles/  Crystal, Pickup, ExitPortal
├── CameraSystem/  CameraFollow (плавное следование + тряска при ударе)
├── Audio/         AudioManager (музыка + звуки, переживает смену сцен)
├── Localization/  Localization (все тексты EN/RU/UZ), LocalizedText
├── UI/            GameUI (HUD + панели), MainMenuUI, EventSystemSpawner, Rotator
├── Ads/           AdManager (единственная точка рекламы), IAdProvider, StubAdProvider, LevelPlayAdProvider, MonetagAdProvider
└── Editor/        CrystalRushSetup + Setup*.cs — генератор проекта (меню Crystal Rush)
```

```
Player ──(теги: Hazard / Crystal / Pickup / Finish)──► PlayerCollision ──► GameManager.Instance
Crystal / Pickup / ExitPortal ─────────────────────────────────────────────► GameManager.Instance
GameManager ──(события StatsChanged, StateChanged, PortalOpened, MessageShown)──► GameUI
GameUI (кнопки) ──► GameManager.Restart / Next / WatchAdForLives ──► AdManager ──► IAdProvider
                                                                                ├─ StubAdProvider (Editor, PC)
                                                                                ├─ LevelPlayAdProvider (Android)
                                                                                └─ MonetagAdProvider (WebGL, jslib)
```

**Префабы** (используются много раз): `Crystal`, `Wall`, `FloorTile`, `LaserBarrier`, `PatrolDrone`, `SpikeTrap`,
`ExtraLife`, `ExtraTime`, `ExitPortal`, `Player`, `GameUI`, `AudioManager`, `AdManager`; частицы в `Assets/Particles`.

## 4. Реклама

Где показывается:
- **Главное меню → «Смотреть рекламу: +2 жизни в следующей игре»** (rewarded). Бонус сохраняется и тратится
  при старте следующей игры. Пока бонус не использован, кнопка показывает «Бонус готов».
- **Game Over → «Смотреть рекламу: +3 жизни»** (rewarded) — один раз за раунд, игра продолжается с того же места.
- **Interstitial** — только между раундами (Restart / Next level / Play again): каждый **3-й** раз
  и не чаще чем раз в **30 секунд**. Никогда во время игры.

Как устроено (`Assets/Scripts/Ads`):
- Игровой код вызывает **только** `AdManager.Instance`. SDK напрямую нигде не вызывается.
- Сети подключаются через интерфейс `IAdProvider`: `StubAdProvider` (Editor и PC), `LevelPlayAdProvider` (Android),
  `MonetagAdProvider` (WebGL). Провайдер только сообщает события (открыта / награда / закрыта / ошибка),
  все правила — в `AdManager`.

Почему реклама стабильная — игра никогда не «зависает» из-за рекламы:
1. Каждый запрос получает **ровно один ответ**. Поздние и повторные события SDK игнорируются.
2. **Сторожевой таймер**: если реклама не открылась за 15 с или не закрылась за 120 с, `AdManager` завершает её сам.
   Время, пока приложение свёрнуто (на Android реклама открывается поверх игры), не считается.
3. Награда считается, даже если сеть прислала «награда» на секунду позже «закрыто».
4. Ответы SDK переводятся в главный поток Unity, ошибки SDK ловятся и не ломают игру.
5. Если реклама не загрузилась — автоматический повтор через 5, 10, 20, 40, 60 секунд.
   Если рекламы нет — «Реклама загружается, попробуйте через минуту», игра идёт дальше без бонуса.

Проверка в Editor: на префабе `Assets/Prefabs/AdManager` галочка `stubSimulateNoFill` включает случай «реклама не загрузилась».
**Не нажимайте на свою настоящую рекламу** — только тестовый режим.

### Android — Unity LevelPlay (уже подключено)

**Почему в редакторе написано «тест»?** В Unity Editor и в PC-сборке всегда показывается встроенная тестовая реклама.
Так задумано: настоящую рекламу LevelPlay показывает только на телефоне (APK). Ключи берутся из файла
**`Assets/Scripts/Ads/AdKeys.cs`**. Сейчас там демо-ключи Unity: в APK будет тестовая реклама без дохода.

**Шаг 1. Ad unit для Rewarded** (форма «Ad unit setup» в кабинете LevelPlay):
| Поле | Что ввести |
|---|---|
| Ad unit name | `CrystalRush_Rewarded` |
| Ad format | `Rewarded` |
| Setup configuration | `New setup` |
| Reward item name | `Lives` |
| Reward amount | `2` |

→ **Save**. Значения Reward в игре не используются: бонус задаёт сам код (+2 жизни в меню, +3 на Game Over).

**Шаг 2. Ad unit для Interstitial**: ещё раз **Add ad unit** → name `CrystalRush_Interstitial`, format `Interstitial`,
`New setup` → **Save**.

**Шаг 3. Скопируйте ключи** в `Assets/Scripts/Ads/AdKeys.cs`:
- `LevelPlayAppKey` — App Key: значок копирования рядом с названием приложения **CrystalRush** вверху страницы;
- `LevelPlayRewardedAdUnitId` и `LevelPlayInterstitialAdUnitId` — колонка **Ad unit ID** в списке Ad units.

**Шаг 4. Package Name** приложения в кабинете должен совпадать с Project Settings → Player → Android →
Package Name (сейчас `com.yourname.crystalrush`; поменяйте в обоих местах одинаково).

**Шаг 5. Тестовое устройство** (чтобы не получить бан за свои клики): в кабинете LevelPlay →
**Testing → Test devices → Add**. Advertising ID телефона: Настройки Android → Google → Реклама.
Включите для него тестовый режим. **На свою настоящую рекламу не нажимайте.**

**Шаг 6. Сборка APK.** File → Build Profiles → Android → **Switch Platform**:
1. Project Settings → Player → Android → Publishing Settings: включите **Custom Main Gradle Template**
   и **Custom Gradle Properties Template**.
2. Меню **Assets → External Dependency Manager → Android Resolver → Force Resolve**.
   Если спросит про авто-резолв, нажмите **Enable**.
3. **Build** → установите APK на телефон (нужен интернет) → кнопка «Смотреть рекламу» в меню.

Проверить LevelPlay прямо в редакторе: при активной платформе Android поставьте галочку `levelPlayInEditor`
на префабе `Assets/Prefabs/AdManager`. Тогда покажется тестовая реклама самого LevelPlay вместо нашей.
Символ `LEVELPLAY_ENABLED` для Android выставляется автоматически (`Assets/Scripts/Editor/DefineGuard`).

### WebGL — Monetag
1. В кабинете Monetag создайте зону **Rewarded Interstitial**, скопируйте Zone ID (только цифры).
2. Впишите его в `Assets/Scripts/Ads/AdKeys.cs` → `MonetagRewardedZoneId` (и `MonetagInterstitialZoneId`, можно тот же).
3. `Assets/Plugins/WebGL/MonetagBridge.jslib` сам подключит SDK Monetag и вызовет `show_ZONEID()`.
   Если SDK не загрузился (нет интернета, блокировщик рекламы), повторит попытку позже.
4. Пока Zone ID не вписан, кнопки рекламы честно отвечают «реклама недоступна». Для показа заглушки в браузере включите `forceStub`.
5. Adsterra (баннеры / Social Bar) — по желанию, в `index.html` WebGL-шаблона, вне области игры.

## 5. Сборка

- **PC**: File → Build Profiles → Windows/Mac → Build.
- **Android**: Switch Platform → Android. Package Name, название и иконка уже выставлены инструментом.
  Build → `.apk`, установить на телефон, проверить джойстик и кнопку РЫВОК.
- **WebGL**: Switch Platform → Web. Decompression Fallback уже включён (сборка работает на любом хостинге, например itch.io).

### Чек-лист перед защитой
- [ ] Игра запускается из `MainMenu`, язык переключается (EN / RU / UZ)
- [ ] Все 3 уровня проходятся, Game Over по жизням и по времени, Restart работает
- [ ] Пауза (Esc / кнопка II), громкость в меню и на паузе
- [ ] Rewarded в меню (+2 жизни в следующей игре) и на Game Over (+3 жизни, один раз за раунд); «нет рекламы» обрабатывается
- [ ] Interstitial только между раундами (каждый 3-й рестарт / переход)
- [ ] На телефоне работают джойстик и РЫВОК
- [ ] Console без красных ошибок

## 6. Ассеты и лицензии

- Шрифт **Rubik** (Google Fonts, SIL Open Font License 1.1) — кириллица и узбекская латиница (o‘, g‘).
- Все текстуры, модели, частицы, звуки и музыка созданы кодом в `Assets/Scripts/Editor` — сторонних ассетов нет.

---

## English — quick start

1. Put the `CrystalRush` folder in a path without spaces or Cyrillic letters.
2. Unity Hub → **Add → Add project from disk** → choose `CrystalRush` → open with Unity 6000.3.x.
3. On the first start the game builds itself (scenes, prefabs, sounds). If not: **Crystal Rush → Build Game**.
4. The `MainMenu` scene opens → Play. Pick the language in the menu: English / Русский / O‘zbekcha.

Controls: WASD / arrows — move, Space — dash, Esc — pause. Phone: joystick + DASH button.
Goal: collect all crystals → the portal opens → enter it. Dangers: laser gates, patrol drones, floor spikes.

## O‘zbekcha — tez boshlash

1. `CrystalRush` papkasini bo‘sh joy va kirill harflari bo‘lmagan yo‘lga joylang.
2. Unity Hub → **Add → Add project from disk** → `CrystalRush` papkasini tanlang → Unity 6000.3.x bilan oching.
3. Birinchi ochilishda o‘yin o‘zi yig‘iladi (sahnalar, prefablar, ovozlar). Agar bo‘lmasa: **Crystal Rush → Build Game**.
4. `MainMenu` sahnasi ochiladi → Play. Tilni menyuda tanlang: English / Русский / O‘zbekcha.

Boshqaruv: WASD / strelkalar — harakat, Probel — otilish, Esc — pauza. Telefonda: joystik + OTILISH tugmasi.
Maqsad: barcha kristallarni yig‘ → portal ochiladi → portalga kir. Xavflar: lazer to‘siqlari, patrul dronlari, poldagi tikanlar.
