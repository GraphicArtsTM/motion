@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0"
title Мастер настройки бота

call scripts\windows\ensure-docker.bat
if errorlevel 1 goto :fail

echo.
echo  Готовлю мастер настройки. Первый раз сборка займёт несколько минут...
docker compose --profile setup build setup
if errorlevel 1 goto :fail

echo.
echo  Сейчас откроется браузер: http://localhost:8765
echo  Заполните шаги и нажмите «Сохранить и запустить» — окно мастера закроется само.
echo  Если браузер не открылся — откройте адрес вручную. Передумали — закройте это окно.
start "" cmd /c "timeout /t 6 /nobreak >nul & start http://localhost:8765"
docker compose --profile setup run --rm --service-ports setup
if errorlevel 1 goto :fail
if not exist ".env" goto :fail

rem Если бот уже работает — перезапускаем с новыми настройками
for /f %%i in ('docker compose ps -q web 2^>nul') do set "RUNNING=1"
if defined RUNNING (
  echo  Применяю новые настройки...
  docker compose up -d --build --force-recreate --remove-orphans
)
echo  Настройки сохранены.
if /i "%~1"=="nopause" exit /b 0
pause
exit /b 0

:fail
echo  [ОШИБКА] Мастер настройки не завершился.
if /i "%~1"=="nopause" exit /b 1
pause
exit /b 1
