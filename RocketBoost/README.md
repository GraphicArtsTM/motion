# Rocket Boost — полный проект Unity 6

Игра в стиле «Lunar Lander»: взлетите с зелёной площадки, пролетите мимо препятствий и мягко сядьте на синюю.
Проект собран по двум книгам из папки `Docs/` («Rocket Boost From Scratch» и «Ads in Rocket Boost»)
и дополнен: языки, главное меню, пауза, звуки, частицы, флаг-реклама.

**Языки игры:** русский, английский, узбекский (латиница: oʻ, gʻ). Язык выбирается в главном меню
и в окне паузы и сохраняется между запусками. При первом запуске язык берётся из системы.

**Версия Unity:** 6000.3.26f1 (подойдёт и любая другая 6000.3.x). Рендер — URP, ввод — Input System,
камера — Cinemachine 3.

---

## Как открыть (Unity Hub → Add project)

1. Скачайте репозиторий (или `git clone`) и найдите папку **`RocketBoost`** — именно в ней лежат
   `Assets`, `Packages`, `ProjectSettings`.
2. Unity Hub → **Projects** → **Add** → **Add project from disk** → выберите папку `RocketBoost`.
3. Откройте проект. Первый запуск занимает несколько минут: Unity скачивает пакеты
   (URP, Input System, Cinemachine) и создаёт папку `Library`. Нужен интернет.
4. Когда скрипты скомпилируются, **проект сам построит игру**: материалы, префабы, сцены
   `MainMenu`, `Over`, `Tunnel`, `Pistons` и список Build Settings. В консоли появится
   `[Rocket Boost] Done!`, и откроется сцена `MainMenu`.
5. Нажмите **▶ Play**.

> Если сцены не появились (например, Unity открыл проект в безопасном режиме или вы отменили импорт),
> выберите в верхнем меню **Rocket Boost → Rebuild scenes and prefabs**.
> Эта же команда пересоздаёт сцены «с нуля», если вы что-то сломали.

Если Unity Hub предлагает другую версию редактора — выберите установленную 6000.3.x и согласитесь.

---

## Управление

| Действие | Клавиатура | Геймпад | Телефон |
|---|---|---|---|
| Двигатель (тяга) | Пробел / W / ↑ | A (South), RT | большая кнопка справа внизу |
| Поворот | ← → / A D | левый стик | две кнопки слева внизу |
| Пауза | Esc | — | кнопка «Меню» вверху справа (или «Назад») |

Отладочные клавиши (только в редакторе и Development Build): **L** — следующий уровень,
**C** — включить/выключить столкновения.

---

## Как устроена игра

* **Сцены (Build Settings):** `MainMenu` (0), `Over` (1), `Tunnel` (2), `Pistons` (3).
  После последнего уровня игра возвращается в меню с надписью «Поздравляем!».
* **Попытки:** 3. После третьей аварии — окно GAME OVER с кнопками
  «Реклама: +3 попытки» (один раз за забег), «Играть снова», «Главное меню».
* **Реклама:** межстраничная — после каждого 2-го пройденного уровня и каждого 3-го рестарта
  (числа меняются в префабе `GameManager`). Баннер внизу (Android). Флаг-спонсор под ракетой.

### Скрипты (`Assets/Scripts`)

| Файл | Что делает |
|---|---|
| `Movement.cs` | Тяга и поворот ракеты (клавиатура, геймпад, экранные кнопки), звук двигателя, частицы |
| `CollisionHandler.cs` | Friendly — безопасно, Finish — посадка, остальное — авария |
| `Oscillator.cs` | Движущиеся препятствия (поршни, блоки) |
| `GameManager.cs` | Попытки, Game Over, продолжение за рекламу, переходы между уровнями, пауза |
| `GameUI.cs` | Счётчик попыток, название уровня, пауза, окно Game Over (OnGUI) |
| `MainMenu.cs` | Главное меню: «Играть», выбор языка, «Выход» |
| `Loc.cs` | **Все тексты на трёх языках.** Чтобы поменять перевод — правьте таблицу здесь |
| `UIKit.cs` | Общий стиль кнопок и шрифт (DejaVu Sans — есть кириллица и узбекские буквы) |
| `TouchControls.cs` | Кнопки на экране телефона |
| `AdManager.cs` | Единая точка для рекламы: LevelPlay (Android/iOS), Monetag (WebGL), заглушка (редактор/ПК) |
| `AdFlag.cs` | Развевающийся рекламный флаг под ракетой |
| `QuitApplication.cs` | Выход по Esc в главном меню |
| `Editor/RocketBoostBuilder.cs` | Строит сцены и префабы (меню **Rocket Boost**) |
| `Editor/LevelPlayDefine.cs` | Включает код LevelPlay, только когда установлен пакет |

### Добавить свой язык или поменять текст

Откройте `Assets/Scripts/Loc.cs`: каждая строка таблицы — `ключ → { русский, английский, узбекский }`.

---

## Реклама

В редакторе и в сборке для ПК работает **заглушка**: реклама не показывается, награда выдаётся сразу —
так можно проверить всю логику (в консоли строки `[Ads] ...`).

### Android — Unity LevelPlay
1. Window → Package Manager → «+» → *Add package by name* → `com.unity.services.levelplay`.
   После установки скрипт `LevelPlayDefine` сам добавит символ `ROCKET_LEVELPLAY` для Android и iOS,
   и `AdManager` начнёт использовать настоящий SDK (без пакета Android-сборка тоже собирается — с заглушкой).
2. На сайте LevelPlay создайте приложение (Package Name: `com.mystudio.rocketboost` — или поменяйте
   в Player Settings и на сайте одинаково) и три Ad Unit: Rewarded, Interstitial, Banner.
3. Выберите префаб `Assets/Prefabs/AdManager` и вставьте App Key и Ad Unit ID.
4. Ads Mediation → Network Manager — установите адаптеры сетей; при необходимости
   Assets → External Dependency Manager → Android Resolver → Force Resolve.
5. Включите тестовое устройство на сайте LevelPlay и **не нажимайте на свою рекламу**.

Код написан под LevelPlay SDK 9.x (в книге был 8.x: конструктор баннера теперь принимает `Config`).

### WebGL — Monetag + Adsterra
1. Установите модуль *Web Build Support* в Unity Hub.
2. Шаблон страницы уже подключён: `Assets/WebGLTemplates/RocketBoost/index.html`
   (Player Settings → Web → WebGL Template = RocketBoost, сжатие Gzip + Decompression Fallback).
3. В `index.html` вставьте код Monetag (в `<head>`, раскомментируйте блок с
   `window.monetagShowRewarded`) и код баннера Adsterra (в `#ad-banner-bottom`).
   Пока код не вставлен, кнопка «Реклама» в браузере просто не появляется.
4. Проверяйте только на реальном домене, который добавлен в панелях Monetag/Adsterra.

Подробности, правила магазинов и согласие пользователей (GDPR) — в `Docs/Rocket_Boost_Ads_Part2_EN.docx`.

---

## Сборка

* **ПК:** File → Build Profiles → Windows/Mac → Build.
* **Android:** Build Profiles → Android → Switch Platform → Build And Run.
  Уже настроено: IL2CPP, ARM64, Min API 24, только горизонтальная ориентация.
* **WebGL:** Build Profiles → Web → Switch Platform → Build; загрузите содержимое папки на хостинг.

Перед публикацией поменяйте Company Name / Product Name / Package Name в Player Settings
и замените картинку флага `Assets/Textures/AdFlag.png` (с пометкой «Реклама/Ad»).

---

## Частые проблемы

| Симптом | Решение |
|---|---|
| Нет сцен в `Assets/Scenes` | Меню **Rocket Boost → Rebuild scenes and prefabs** |
| Розовые (пурпурные) объекты | Project Settings → Graphics: должен стоять `PC_RPAsset` (URP). Затем Rebuild |
| Красные ошибки в консоли сразу после открытия | Подождите окончания импорта пакетов; если остались — Window → Package Manager, проверьте, что установлены Input System и Cinemachine 3 |
| Ракета не реагирует на клавиши | Кликните по окну Game, чтобы оно получило фокус |
| `The type or namespace name 'LevelPlay'` при сборке Android | Пакет LevelPlay удалён не полностью: перезапустите Unity, символ `ROCKET_LEVELPLAY` уберётся сам |

Шрифт DejaVu Sans распространяется по свободной лицензии (`Docs/DejaVu-Font-LICENSE.txt`).
