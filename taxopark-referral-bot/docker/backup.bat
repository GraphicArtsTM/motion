@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0.."
title Резервная копия базы
if not exist backups mkdir backups
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmm"') do set "STAMP=%%t"
set "FILE=backups\referral-%STAMP%.dump"
echo  Создаю резервную копию базы: %FILE%
docker compose exec -T postgres pg_dump -U referral -Fc referral > "%FILE%"
if errorlevel 1 (
  echo  [ОШИБКА] Не получилось — бот запущен? Сначала start.bat
  del "%FILE%" 2>nul
  pause
  exit /b 1
)
echo  Готово. Храните копию вне этого компьютера.
pause
