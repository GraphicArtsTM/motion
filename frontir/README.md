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

## Запуск в Studio
1. В папке `frontir/`:
   ```bash
   rojo serve
   ```
2. Открой Roblox Studio → новый пустой проект **Baseplate** (или любой пустой place).
3. Вкладка **Plugins → Rojo → Connect** (адрес по умолчанию `localhost:34872`).
4. Нажми **Play**. Должен появиться тёмный экран с панелью «Фронтир / Каркас готов (этап 0)», в Output — строки `[Frontir] server boot …` и `[Frontir] client boot …`.

> Персонажи отключены (`Players.CharacterAutoLoads = false`): игра 2D и аватар не нужен.

## Тесты и проверки
Из папки `frontir/`:
```bash
lune run tests
```
```bash
stylua --check src tests tools
```
```bash
selene src tests tools
```
То же самое запускает CI на каждый push (`.github/workflows/ci.yml` в корне репозитория).

## Автодополнение (luau-lsp)
```bash
rojo sourcemap default.project.json -o sourcemap.json
```
```bash
lune setup
```
Первая команда даёт luau-lsp карту Roblox-инстансов, вторая — типы модулей Lune для тестов и инструментов.

## Структура
```
src/shared   чистая логика + Config + типы (тестируется в Lune)
src/server   серверные скрипты
src/client   клиент: рендер, UI, ввод
maps/        упакованные карты
tools/       Lune-скрипты (генерация карт)
tests/       Lune-тесты (*.spec.luau)
docs/        GDD, список арта, баланс, changelog
```
