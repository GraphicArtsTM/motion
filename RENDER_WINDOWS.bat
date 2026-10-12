@echo off
chcp 65001 >nul
title Паук Новограда — рендер серии
cd /d "%~dp0"
echo.
echo  ===============================================
echo    ПАУК НОВОГРАДА — сборка видео серии
echo  ===============================================
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo  Node.js не найден — устанавливаю через winget...
  winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
  set "PATH=%PATH%;%ProgramFiles%\nodejs"
)
where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo  Не получилось установить Node.js автоматически.
  echo  Скачайте установщик LTS с https://nodejs.org , установите и запустите этот файл снова.
  start https://nodejs.org
  pause
  exit /b 1
)

set "EPARG="
echo %~1 | findstr /r "^e[0-9]" >nul
if not errorlevel 1 goto :haveep
echo  Какую серию собрать? Введите номер серии (1, 2, ...) и нажмите Enter.
echo  Просто Enter — серия по умолчанию.
set "N="
set /p N=  Серия: 
if "%N%"=="" goto :haveep
if %N% LSS 10 (set "EPARG=--ep e0%N%") else (set "EPARG=--ep e%N%")
:haveep

echo  [1/3] Устанавливаю библиотеки (Playwright, ffmpeg)...
call npm install --no-audit --no-fund
if errorlevel 1 goto :err

echo  [2/3] Скачиваю браузер для рендера (один раз, ~150 МБ)...
call npx playwright install chromium
if errorlevel 1 goto :err

echo  [3/3] Рендер...
node make-video.mjs %EPARG% %*
if errorlevel 1 goto :err

echo.
echo  Готово! Видео лежит в папке out
start "" "%~dp0out"
pause
exit /b 0

:err
echo.
echo  Ошибка. Сделайте скриншот этого окна и пришлите его.
pause
exit /b 1
