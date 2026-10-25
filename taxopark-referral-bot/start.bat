@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0"
title Реферальный бот таксопарка

echo.
echo  ============================================
echo     Реферальный бот таксопарка — запуск
echo  ============================================
echo.

call scripts\windows\ensure-docker.bat
if errorlevel 1 goto :fail

if exist ".env" goto :configured
echo  [1/3] Первый запуск — открываю мастер настройки в браузере...
call "%~dp0setup.bat" nopause
if errorlevel 1 goto :fail
if not exist ".env" goto :not_configured
:configured

call scripts\windows\read-env.bat BOT_MODE
if /i "%ENV_VALUE%"=="webhook" call :certificate
if errorlevel 1 goto :fail

echo  [2/3] Сборка и запуск. Первый раз это занимает 3-10 минут...
docker compose up -d --build --remove-orphans
if errorlevel 1 goto :fail

echo  [3/3] Жду готовности сервисов...
call scripts\windows\wait-health.bat
if errorlevel 1 goto :slow

echo.
echo  ГОТОВО! Бот работает.
call scripts\windows\read-env.bat BOT_USERNAME
if not "%ENV_VALUE%"=="" echo  Бот в Telegram:  https://t.me/%ENV_VALUE%
echo  Состояние:       http://localhost:8000/
echo.
echo  Это окно можно закрыть — бот продолжит работать в фоне,
echo  пока включён компьютер и запущен Docker Desktop.
echo  Остановить: stop.bat    Журнал: logs.bat    Настройки: setup.bat
start "" http://localhost:8000/
echo.
pause
exit /b 0

:certificate
call scripts\windows\read-env.bat PUBLIC_DOMAIN
set "DOMAIN=%ENV_VALUE%"
docker compose run --rm --no-deps --entrypoint sh certbot -c "test -f /etc/letsencrypt/live/%DOMAIN%/fullchain.pem" >nul 2>&1
if not errorlevel 1 exit /b 0
echo  Получаю HTTPS-сертификат для %DOMAIN% — домен должен указывать на этот сервер, порт 80 открыт...
docker compose run --rm --no-deps -p 80:80 --entrypoint certbot certbot certonly --standalone -d %DOMAIN% --agree-tos --register-unsafely-without-email --non-interactive
exit /b %errorlevel%

:slow
echo  Сервисы долго не отвечают. Посмотрите журнал: logs.bat
goto :fail

:not_configured
echo  Настройка не была сохранена. Запустите start.bat ещё раз.

:fail
echo.
echo  [ОШИБКА] Запуск не удался. Подробности — в журнале: logs.bat
echo.
pause
exit /b 1
