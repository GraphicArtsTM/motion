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

Правила (всё в `AdManager.cs`):
- Игровой код вызывает **только** `AdManager.Instance`, SDK напрямую нигде не вызывается.
- **Rewarded** — только по кнопке «Смотреть рекламу: +3 жизни» на экране Game Over, **один раз за раунд**,
  бонус только если реклама досмотрена. Нет рекламы → сообщение «Реклама сейчас недоступна», игра продолжается как обычно.
- **Interstitial** — только между раундами (Restart / Next level / Play again), каждый **3-й** раз
  (`interstitialEveryNRounds`). Никогда во время игры. Если реклама не загрузилась — игра просто идёт дальше.
- В **Editor и PC-сборке** работает **заглушка**: полноэкранная «ТЕСТОВАЯ РЕКЛАМА» с таймером.
  Галочка `stubSimulateNoFill` на AdManager — проверить случай «реклама не загрузилась».
- Кнопки управления рекламой не перекрываются (баннеров во время игры нет).
- **Не нажимайте на свою рекламу** — только тестовый режим.

### Android — Unity LevelPlay
1. Window → Package Manager → Unity Registry → **Ads Mediation (LevelPlay)** → Install.
2. В дашборде LevelPlay создайте приложение (Package Name как в Player Settings), Ad Units Rewarded и Interstitial,
   включите тестовый режим / добавьте свой телефон как test device.
3. На префабе `Assets/Prefabs/AdManager` впишите App Key и Ad Unit ID.
4. Project Settings → Player → Android → Scripting Define Symbols: добавьте **`LEVELPLAY_ENABLED`**.
   Без этого символа проект компилируется и без SDK (работает заглушка).
5. Код написан под API LevelPlay 8.x (`LevelPlayRewardedAd`, `LevelPlayInterstitialAd`). Если в вашей версии SDK
   другие сигнатуры событий — правки нужны только в `LevelPlayAdProvider.cs`.

### WebGL — Monetag
1. В кабинете Monetag создайте зону **Rewarded Interstitial** (SDK), скопируйте Zone ID (только цифры).
2. Впишите его в `AdManager → Monetag → rewardedZoneId` (и `interstitialZoneId`, можно тот же).
3. `Assets/Plugins/WebGL/MonetagBridge.jslib` сам подключит SDK Monetag (`libtl.com/sdk.js`) и вызовет `show_ZONEID()`.
4. Для тестов без одобренного аккаунта включите `forceStub` на AdManager.
5. Adsterra (баннеры / Social Bar) — по желанию, вставляется в `index.html` WebGL-шаблона, вне области игры.

## 5. Сборка

- **PC**: File → Build Profiles → Windows/Mac → Build.
- **Android**: Switch Platform → Android. Package Name, название и иконка уже выставлены инструментом.
  Build → `.apk`, установить на телефон, проверить джойстик и кнопку РЫВОК.
- **WebGL**: Switch Platform → Web. Decompression Fallback уже включён (сборка работает на любом хостинге, например itch.io).

### Чек-лист перед защитой
- [ ] Игра запускается из `MainMenu`, язык переключается (EN / RU / UZ)
- [ ] Все 3 уровня проходятся, Game Over по жизням и по времени, Restart работает
- [ ] Пауза (Esc / кнопка II), громкость в меню и на паузе
- [ ] Rewarded: +3 жизни один раз за раунд; «нет рекламы» обрабатывается
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
