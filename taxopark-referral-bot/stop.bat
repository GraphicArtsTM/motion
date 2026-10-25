@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Остановка бота
echo  Останавливаю бота... Данные сохраняются, следующий start.bat продолжит работу.
docker compose --profile polling --profile webhook down
echo  Бот остановлен.
pause
