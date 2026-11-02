# Фронтир

Пиксельная 2D онлайн-стратегия для Roblox. Дизайн-документ: [`docs/GDD.md`](docs/GDD.md).

## Что понадобится
- [Roblox Studio](https://create.roblox.com/)
- [Git](https://git-scm.com/)
- [Rokit](https://github.com/rojo-rbx/rokit) — ставит остальные инструменты (Rojo, Lune, StyLua, Selene, luau-lsp) нужных версий из `rokit.toml`.
- Желательно: VS Code с расширениями из `.vscode/extensions.json` (luau-lsp, StyLua, Selene, Rojo).

## Установка

### Windows
1. Установи Rokit в PowerShell:
   ```powershell
   Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
   ```
   (или скачай `rokit.exe` со страницы [релизов](https://github.com/rojo-rbx/rokit/releases) и выполни `rokit.exe self-install`). Перезапусти терминал.
2. Склонируй репозиторий и поставь инструменты:
   ```powershell
   git clone <url-репозитория>
   cd motion\frontir
   rokit install
   ```
   На вопрос о доверии инструментам ответь «да».
3. Поставь плагин Rojo в Studio:
   ```powershell
   rojo plugin install
   ```

### Mac
1. Установи Rokit:
   ```bash
   curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
   ```
   Перезапусти терминал.
2. Склонируй репозиторий и поставь инструменты:
   ```bash
   git clone <url-репозитория>
   cd motion/frontir
   rokit install
   ```
3. Плагин Rojo для Studio:
   ```bash
   rojo plugin install
   ```

## Проверка этапа в Studio
Делается после каждого этапа. Все команды выполняются в папке `frontir/`.

1. Поставь или обнови инструменты проекта (после каждого `git pull` тоже):
   ```bash
   rokit install
   ```
2. Поставь плагин Rojo в Studio (один раз, и после обновления версии Rojo):
   ```bash
   rojo plugin install
   ```
3. Запусти синхронизацию и не закрывай терминал:
   ```bash
   rojo serve
   ```
4. Открой Roblox Studio → пустой **Baseplate**. Вкладка **Plugins → Rojo → Connect** (адрес по умолчанию `localhost:34872`).
5. Нажми **Play** (или **Test → Clients and Servers → 2 Players**, когда этап про мультиплеер).
6. Сверь увиденное с разделом «Как проверить в Studio» из отчёта по этапу.

**Этап 1:** на весь экран — карта «Пангея» (один материк, горы со снежными вершинами, реки, озёра, тундра у полюсов),
на воде мерцают блики. В Studio слева сверху открыто окно отладки (F3 — скрыть/показать): FPS, зум, клетка под курсором,
память EditableImage. Управление:
- колесо мыши — зум к курсору (×1…×12, пиксели остаются чёткими);
- зажатая правая или средняя кнопка — тащить карту; WASD и стрелки — прокрутка; Space — показать всю карту;
- телефон (Test → Device Emulator или реальное устройство): палец — тащить, щипок — зум.

В Output: `[Frontir] server: карта Pangea 512×320, …` и `[Frontir] client: карта Pangea 512×320, чанков 4`.

**Публикация.** EditableImage в опубликованной игре по умолчанию выключен. Включи его один раз:
Studio → **File → Experience Settings → Security → Allow Mesh / Image APIs** (или Creator Dashboard → Configure → Settings).
Иначе на экране будет сообщение об ошибке вместо карты.

> Персонажи отключены (`Players.CharacterAutoLoads = false`): игра 2D и аватар не нужен.

## Тесты и проверки
Из папки `frontir/` — то же самое, что делает CI (`.github/workflows/ci.yml` в корне репозитория):
```bash
lune run tests
```
```bash
stylua --check src tests tools
```
```bash
selene src tests tools
```
Проверка типов (strict). Первые две команды нужны один раз и после изменения структуры файлов:
```bash
lune setup
```
```bash
rojo sourcemap default.project.json -o sourcemap.json
```
```bash
luau-lsp analyze --platform=roblox --definitions:@roblox=types/globalTypes.d.luau --sourcemap=sourcemap.json --base-luaurc=.luaurc src tests tools
```

### Карты
Выдуманные карты генерируются по сиду из параметров `Config.MapGen.<Имя>` и упаковываются в `maps/<Имя>.luau`:
```bash
lune run tools/genmap Pangea
```
Заодно пишется превью `build/Pangea.bmp` (в git не идёт). Тест `MapFormat.spec` падает, если закоммиченная карта
не совпадает с генератором — после правки параметров карты перезапусти команду выше.

### Обновление определений Roblox
Определения для selene (`roblox.yml`) и luau-lsp (`types/globalTypes.d.luau`) закоммичены, чтобы проверки работали одинаково локально и в CI без сети.
Обновлять, когда в Roblox появились нужные новые API:
```bash
selene generate-roblox-std
```
```bash
curl -sSfL -o types/globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.70.1/scripts/globalTypes.d.luau
```
(в ссылке — версия luau-lsp из `rokit.toml`).

## Автодополнение (luau-lsp)
```bash
rojo sourcemap default.project.json -o sourcemap.json
```
```bash
lune setup
```
Первая команда даёт luau-lsp карту Roblox-инстансов, вторая — типы модулей Lune (алиас `@lune` в `.luaurc`).

## Структура
```
src/shared   чистая логика + Config + типы (тестируется в Lune)
src/server   серверные скрипты
src/client   клиент: рендер, UI, ввод
maps/        упакованные карты
tools/       Lune-скрипты (генерация карт)
tests/       Lune-тесты (*.spec.luau)
docs/        GDD, список арта, баланс, changelog
types/       определения Roblox для luau-lsp
roblox.yml   определения Roblox для selene
```
