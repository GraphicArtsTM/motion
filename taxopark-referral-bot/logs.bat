@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Журнал бота
echo  Журнал бота (последние строки и новые в реальном времени). Закрыть — Ctrl+C или крестик окна.
echo.
docker compose ps
echo.
docker compose logs -f --tail=150 bot web worker migrate
pause
