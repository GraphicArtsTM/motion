@echo off
setlocal
title PS2 Intro - render
cd /d "%~dp0"
set "PATH=%~dp0tools\node;%PATH%"
where node >nul 2>nul
if errorlevel 1 call :getnode
where node >nul 2>nul
if errorlevel 1 goto :nonode
if not exist "node_modules\playwright\package.json" goto :install
if not exist "node_modules\ffmpeg-static\package.json" goto :install
goto :run

:install
echo.
echo === Installing libraries - one time only, 1-3 minutes ===
call npm install --no-audit --no-fund --loglevel=error
if errorlevel 1 goto :npmfail
goto :run

:getnode
echo.
echo === Node.js not found - downloading portable Node.js 22, about 30 MB ===
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol='Tls12'; $v='v22.12.0'; $a='x64'; if (-not [Environment]::Is64BitOperatingSystem) { $a='x86' }; New-Item -ItemType Directory -Force tools | Out-Null; Invoke-WebRequest ('https://nodejs.org/dist/' + $v + '/node-' + $v + '-win-' + $a + '.zip') -OutFile tools\node.zip; Expand-Archive tools\node.zip -DestinationPath tools -Force; if (Test-Path tools\node) { Remove-Item tools\node -Recurse -Force }; Rename-Item ('tools\node-' + $v + '-win-' + $a) node; Remove-Item tools\node.zip"
exit /b 0

:nonode
echo.
echo [!] Could not get Node.js. Install it from https://nodejs.org (LTS) and run this file again.
pause
exit /b 1

:npmfail
echo.
echo [!] Library install failed. Check the internet connection and run this file again.
pause
exit /b 1

:run
node render-all.mjs %*
echo.
pause
exit /b 0
