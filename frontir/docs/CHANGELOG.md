# Changelog

## Этап 0 — правки после приёмки
- CI: проверка типов `luau-lsp analyze` (strict) с определениями Roblox (`types/globalTypes.d.luau`, luau-lsp 1.70.1); ошибки роняют сборку.
- Selene: закоммичен `roblox.yml`, `roblox-std-source = "pinned"` — одинаково работает локально и в CI без сети.
- Исправлены найденные strict-ошибки: `Strings` (тип модуля, record `Entry`), `Config.Units` как record `Types.UnitTable`, `Types.TerrainIds`, `deepFreeze`, `pcall` в TestKit.
- Шрифт-заглушка: `Enum.Font.RobotoMono` (кириллица), тема UI в `src/client/UI/Theme.luau`; пиксельный шрифт — на этапе HUD.
- CI запускается на push в любую ветку и на любой pull_request.
- README: раздел «Проверка этапа в Studio», локальная проверка типов, обновление определений.

## Этап 0 — каркас
- Проект Rojo, Rokit, StyLua, Selene, настройки luau-lsp.
- `Config.luau` со стартовыми числами из GDD, `Types.luau`, `Strings.luau` (RU/EN).
- Заглушки входа сервера и клиента.
- Lune-тесты (свой мини-фреймворк `tests/lib/TestKit.luau`), CI на GitHub Actions.
