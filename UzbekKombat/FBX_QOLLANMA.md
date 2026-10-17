# Как заменить героев на реалистичные FBX-модели (без навыков моделирования)

Игра уже умеет подхватывать внешние модели и анимации. Вам нужно только **сгенерировать модель, загрузить её в Mixamo, скачать движения и положить файлы в нужные папки**. Код всё сделает сам:
- настроит модель как Humanoid;
- синхронизирует удары с моментом попадания;
- повесит меч, лук или посох в руку модели;
- для движений, которых нет, перенесёт встроенную анимацию на скелет модели;
- если модели нет — оставит текущего героя из кода.

Время на одного героя: ~30–60 минут.

---

## Шаг 1. Модель через ИИ-генератор

Подойдут **Meshy.ai**, **Tripo3D.ai** или **Hyper3D Rodin**. Ниже — порядок на примере Meshy.

1. Сначала сгенерируйте **картинку-концепт** персонажа: в Meshy (Text to Image) или любом генераторе изображений. Из картинки модель получается заметно лучше, чем из одного текста.
2. **Image to 3D** (или Text to 3D) → включите **PBR-текстуры** → поза **A-pose или T-pose** → стиль **Realistic**.
3. **Оружие в руки не давайте**: игра добавит своё (меч, сабли, посох, лук).
4. Скачайте **FBX** с текстурами. Модель до ~50 тыс. полигонов: в Meshy есть Remesh / Target polycount.

### Готовые описания (вставлять на английском)

**Амир Темур**
> Full body realistic 3D character, A-pose, Amir Timur, 14th century Central Asian Turkic emperor, strong middle-aged man, black beard, stern face, pointed steel helmet with gold band and chainmail aventail, lamellar steel armor with gold trim over crimson silk robe with gold embroidery, long red cape, dark trousers, tall leather boots, no weapon, game-ready, PBR textures

**Джалолиддин Мангуберди**
> Full body realistic 3D character, A-pose, Jalal ad-Din Mingburnu, 13th century Khwarezmian warrior sultan, athletic young man, short black beard, steel spiked helmet wrapped with white turban, brown leather armor vest, teal and white striped chapan robe, leather bracers, tall boots, no weapon, game-ready, PBR textures

**Мирзо Улугбек**
> Full body realistic 3D character, A-pose, Ulugh Beg, 15th century Timurid astronomer king, dignified man with neat dark-grey beard, large white turban with emerald jewel and white feather, long indigo silk robe embroidered with small gold stars, gold sash, soft leather boots, no weapon, game-ready, PBR textures

**Чингисхан**
> Full body realistic 3D character, A-pose, Genghis Khan, 12th century Mongol khan, stocky powerful man, long thin drooping mustache and small goatee, braided hair, round fur-trimmed burgundy Mongol hat, leather lamellar armor over burgundy deel robe with gold trim, fur cuffs, leather boots, quiver on belt, no weapon, game-ready, PBR textures

---

## Шаг 2. Скелет в Mixamo (бесплатно)

1. Зайдите на **mixamo.com** (нужен бесплатный аккаунт Adobe) → **Upload Character** → выберите FBX.
2. Расставьте маркеры: подбородок, запястья, локти, колени, пах. **Skeleton LOD: Standard Skeleton (65)** → Next.
3. Проверьте, что модель двигается без разрывов → **Download**:
   - Format: **FBX for Unity (.fbx)**
   - Skin: **With Skin**
   - Pose: **T-pose**
4. Переименуйте файл в **`model.fbx`**.

---

## Шаг 3. Движения в Mixamo

Персонаж остаётся загруженным. Ищите движение по слову из таблицы, при необходимости поставьте галочку **In Place**, затем **Download** с такими настройками:
- Format: **FBX for Unity**
- Skin: **Without Skin**
- Frames per second: **30**

**Главное — переименовать файл в имя слота** (вторая колонка). Тогда игра точно поймёт, что это за движение.

| Что это | Имя файла | Что искать в Mixamo |
|---|---|---|
| Боевая стойка | `idle.fbx` | Fighting Idle / Sword And Shield Idle / Great Sword Idle |
| Шаг вперёд | `walkF.fbx` | Walking (In Place) / Sword And Shield Walk |
| Шаг назад | `walkB.fbx` | Walking Backwards (In Place) |
| Присед | `crouch.fbx` | Crouch Idle / Crouching Idle |
| Блок | `block.fbx` | Block / Standing Block Idle / Sword And Shield Block Idle |
| Блок в приседе | `crouchBlock.fbx` | Crouch Block (необязательно) |
| Прыжок вверх | `jump.fbx` | Jump (In Place) |
| Прыжок вперёд | `jumpF.fbx` | Front Flip (In Place) |
| Бег | `run.fbx` | Running (In Place) |
| Лёгкий удар (U) | `LP.fbx` | Lead Jab / Punching / Sword And Shield Slash |
| Сильный удар (I) | `HP.fbx` | Great Sword Slash / Sword Slash / Cross Punch |
| Лёгкий пинок (J) | `LK.fbx` | Front Kick / Kick |
| Сильный пинок (K) | `HK.fbx` | Roundhouse Kick / Mma Kick |
| Апперкот в приседе | `cHP.fbx` | Uppercut / Rising Slash |
| Подсечка | `cHK.fbx` | Leg Sweep |
| Удар в прыжке | `jK.fbx` | Flying Kick |
| Бросок | `throw.fbx` | Throw / Grab |
| Удар в голову (получение) | `hitHigh.fbx` | Head Hit |
| Удар в корпус | `hitMid.fbx` | Stomach Hit |
| Тяжёлый удар | `hitHeavy.fbx` | Big Stomach Hit |
| Падение | `knockdown.fbx` | Falling Back Death / Knocked Down |
| Подъём | `getUp.fbx` | Getting Up / Standing Up |
| Шатание («TUGAT UNI!») | `dizzy.fbx` | Dizzy Idle / Drunk Idle |
| Победа | `victory.fbx` | Victory / Cheering |
| Выход на бой | `intro.fbx` | Taunt / Rallying |
| Жест в покое | `taunt.fbx` | Taunt (необязательно) |

**Спецприёмы** (необязательно, иначе работает встроенная анимация):

| Герой | Имена файлов |
|---|---|
| Темур | `wave` (волна меча), `charge` (таран), `quake` (удар в землю), `counter` (парирование), `super` |
| Джалолиддин | `dagger`, `whirl` (вихрь), `leap` (прыжок с ударом), `step` (телепорт), `super` |
| Улугбек | `orb`, `sextant`, `rain`, `ring`, `super` |
| Чингисхан | `arrow` (стрела), `lasso`, `wolf` (рывок с коленом), `grip` (захват), `super` |

**Момент попадания.** Игра совмещает момент удара в клипе с моментом попадания. По умолчанию удар считается на 40% длины клипа. Если в клипе удар раньше или позже, добавьте к имени `@` и долю: `HP@0.55.fbx` — удар на 55% клипа.

---

## Шаг 4. Положить файлы в Unity

```
UzbekKombat/Assets/Resources/Characters/
    temur/        model.fbx   Anims/idle.fbx, Anims/LP.fbx, ...
    jaloliddin/   model.fbx   Anims/...
    ulugbek/      model.fbx   Anims/...
    chingiz/      model.fbx   Anims/...
```

1. Перетащите файлы в эти папки прямо в окне Project. Unity сам настроит импорт: Humanoid, имена клипов, зацикливание, «на месте».
2. Меню **O'zbek Jangi → FBX personajlarni tekshirish** покажет, что найдено, чего не хватает и какие файлы не распознаны.
3. Нажмите **Play**. В консоли появится строка вида `[O'zbek Jangi] temur: FBX ulandi ...`.

Можно подключать по одному герою и по одной анимации: всё, чего нет, остаётся встроенным.

---

## Если что-то не так

| Проблема | Решение |
|---|---|
| Герой остался «кубическим» | Файл должен называться `model.fbx` и лежать в папке героя. Смотрите отчёт в меню. |
| В консоли «Humanoid emas» | Модель не прошла риг в Mixamo. Повторите шаг 2 или выберите модель → Inspector → Rig → Animation Type = Humanoid → Apply. |
| Модель стоит в T-позе и не двигается | Проверьте, что в Rig у модели стоит Humanoid и аватар без ошибок (Configure Avatar — все кости зелёные). |
| Руки или ноги вывернуты | Rig → Configure → Pose → Enforce T-Pose → Done. Затем меню **O'zbek Jangi → FBX'larni qayta import qilish**. |
| Розовые материалы | Текстуры не подтянулись: выберите model.fbx → Materials → **Extract Textures** и **Extract Materials**. |
| Движение «уезжает» с места | При скачивании поставьте **In Place**; импортёр и так запекает движение корня в позу. |
| Удар не совпадает с попаданием | Добавьте суффикс `@0.3` … `@0.6` к имени файла и переимпортируйте. |
| Меч не в руке | Оружие крепится к кости кисти. Если кисть повёрнута странно — проверьте Configure Avatar (кости Hand). |

## Права на использование
- **Mixamo**: модели и анимации бесплатны, в том числе в коммерческих играх.
- **Meshy / Tripo / Rodin**: на бесплатном тарифе модели часто публичные или под лицензией CC BY. Для коммерческого релиза нужен платный тариф — проверьте условия сервиса.

## Ещё лучше по качеству
- **Unity Asset Store**: готовые реалистичные паки воинов (Medieval, Mongol, Persian warriors) и паки боевых анимаций (Sword Animset, Fighting Motions). Кладутся в те же папки по тем же правилам.
- **Художник на заказ** (ArtStation, Fiverr): ~$300–1500 за персонажа — ближе всего к AAA. Попросите сразу «Humanoid rig, Mixamo-compatible, PBR, до 50k полигонов».
